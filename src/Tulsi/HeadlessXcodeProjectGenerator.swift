// Copyright 2016 The Tulsi Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Cocoa
import TulsiGenerator


/// Provides functionality to generate an Xcode project from a TulsiGeneratorConfig
struct HeadlessXcodeProjectGenerator {
  let arguments: TulsiCommandlineParser.Arguments

  /// Performs project generation.
  func generate() throws {
    TulsiProjectDocument.showAlertsOnErrors = false
    TulsiProjectDocument.suppressWORKSPACECheck = arguments.suppressWORKSPACECheck

    let explicitBazelURL: NSURL?
    if let bazelPath = arguments.bazel {
      if !NSFileManager.defaultManager().isExecutableFileAtPath(bazelPath) {
        throw HeadlessModeError.InvalidBazelPath
      }
      explicitBazelURL = NSURL(fileURLWithPath: bazelPath)
      TulsiProjectDocument.suppressRuleEntryUpdateOnLoad = true
    } else {
      explicitBazelURL = nil
    }

    defer {
      TulsiProjectDocument.showAlertsOnErrors = true
      TulsiProjectDocument.suppressWORKSPACECheck = false
      TulsiProjectDocument.suppressRuleEntryUpdateOnLoad = false
    }

    guard let configPath = arguments.generatorConfig else {
      fatalError("HeadlessXcodeProjectGenerator invoked without a valid generatorConfig")
    }

    let (projectURL, configURL, defaultOutputFolderURL) = try resolveConfigPath(configPath)

    let documentController = NSDocumentController.sharedDocumentController()
    let doc: NSDocument
    do {
      doc = try documentController.makeDocumentWithContentsOfURL(projectURL,
                                                                 ofType: "com.google.tulsi.project")
    } catch TulsiProjectDocument.Error.InvalidWorkspace(let info) {
      throw HeadlessModeError.InvalidProjectFileContents("Failed to load project due to invalid workspace: \(info)")
    } catch let e as NSError {
      throw HeadlessModeError.InvalidProjectFileContents("Failed to load project due to unexpected exception: \(e)")
    } catch {
      throw HeadlessModeError.InvalidProjectFileContents("Failed to load project due to unexpected exception.")
    }
    guard let projectDocument = doc as? TulsiProjectDocument else {
      throw HeadlessModeError.InvalidProjectFileContents("\(doc) is not of the expected type.")
    }

    let outputFolderURL: NSURL
    if let option = arguments.outputFolder {
      outputFolderURL = NSURL(fileURLWithPath: option, isDirectory: true)
    } else if let defaultOutputFolderURL = defaultOutputFolderURL {
      outputFolderURL = defaultOutputFolderURL
    } else {
      throw HeadlessModeError.ExplicitOutputOptionRequired
    }

    var config = try loadConfig(configURL, bazelURL: explicitBazelURL)
    config = config.configByAppendingPathFilters(arguments.additionalPathFilters)

    if let projectOptionSet = projectDocument.optionSet {
      config = config.configByResolvingInheritedOptions(projectOptionSet)
    }

    let workspaceRootURL: NSURL
    let projectWorkspaceRootURL = projectDocument.workspaceRootURL
    if let workspaceRootOverride = arguments.workspaceRootOverride {
      workspaceRootURL = NSURL(fileURLWithPath: workspaceRootOverride, isDirectory: true)
      if !isExistingDirectory(workspaceRootURL) {
        throw HeadlessModeError.InvalidWorkspaceRootOverride
      }
      if projectWorkspaceRootURL != nil {
        print("Overriding project workspace root (\(projectWorkspaceRootURL!.path!)) with " +
            "command-line parameter (\(workspaceRootOverride))")
      }
    } else {
      guard let projectWorkspaceRootURL = projectWorkspaceRootURL else {
        throw HeadlessModeError.InvalidProjectFileContents("Invalid workspaceRoot")
      }
      workspaceRootURL = projectWorkspaceRootURL
    }

    print("Generating project into '\(outputFolderURL.path!)' using:\n" +
              "\tconfig at '\(configURL.path!)'\n" +
              "\tBazel workspace at '\(workspaceRootURL.path!)'\n" +
              "\tBazel at '\(config.bazelURL.path!)'.\n" +
              "This may take a while.")

    let result = TulsiGeneratorConfigDocument.generateXcodeProjectInFolder(outputFolderURL,
                                                                           withGeneratorConfig: config,
                                                                           workspaceRootURL: workspaceRootURL,
                                                                           messageLog: nil)
    switch result {
      case .Success(let url):
        print("Generated project at \(url.path!)")
        if arguments.openXcodeOnSuccess {
          print("Opening generated project in Xcode")
          NSWorkspace.sharedWorkspace().openURL(url)
        }
      case .Failure(let errorInfo):
        throw HeadlessModeError.GenerationFailed(errorInfo)
    }
  }

  // MARK: - Private methods

  private func resolveConfigPath(path: String) throws -> (projectURL: NSURL,
                                                          configURL: NSURL,
                                                          defaultOutputFolderURL: NSURL?) {
    let tulsiProjExtension = TulsiProjectDocument.getTulsiBundleExtension()
    let components = path.componentsSeparatedByString(":")
    if components.count == 2 {
      var pathString = components[0] as NSString
      let projectExtension = pathString.pathExtension
      if projectExtension != tulsiProjExtension {
        pathString = pathString.stringByAppendingPathExtension(tulsiProjExtension)!
      }
      let projectURL = NSURL(fileURLWithPath: pathString as String)
      let (configURL, defaultOutputFolderURL) = try locateConfigNamed(components[1],
                                                                      inTulsiProject: pathString as String)
      return (projectURL, configURL, defaultOutputFolderURL)
    }

    var pathString = path as NSString
    let pathExtension = pathString.pathExtension
    var isProject = pathExtension == tulsiProjExtension
    if !isProject && pathExtension.isEmpty {
      // See if the user provided a Tulsiproj bundle without the extension or if there is a
      // tulsiproj bundle with the same name as the given directory.
      let projectPath = pathString.stringByAppendingPathExtension(tulsiProjExtension)!
      if isExistingDirectory(NSURL(fileURLWithPath: projectPath, isDirectory: true)) {
        isProject = true
        pathString = projectPath as NSString
      } else {
        let projectName = (pathString.lastPathComponent as NSString).stringByAppendingPathExtension(tulsiProjExtension)!
        let projectWithinPath = pathString.stringByAppendingPathComponent(projectName)
        if isExistingDirectory(NSURL(fileURLWithPath: projectWithinPath, isDirectory: true)) {
          isProject = true
          pathString = projectWithinPath as NSString
        }
      }
    }
    if isProject {
      let project = pathString.lastPathComponent as NSString
      let projectName = project.stringByDeletingPathExtension
      let (configURL, defaultOutputFolderURL) = try locateConfigNamed(projectName,
                                                                      inTulsiProject: pathString as String)
      let projectURL = NSURL(fileURLWithPath: pathString as String)
      return (projectURL, configURL, defaultOutputFolderURL)
    }

    throw HeadlessModeError.InvalidConfigPath("The given config is invalid")
  }

  private func locateConfigNamed(configName: String,
                                 inTulsiProject tulsiProj: String) throws -> (configURL: NSURL, defaultOutputFolderURL: NSURL?) {
    let tulsiProjectURL = NSURL(fileURLWithPath: tulsiProj, isDirectory: true)
    if !isExistingDirectory(tulsiProjectURL) {
      throw HeadlessModeError.InvalidConfigPath("The given Tulsi project does not exist")
    }

#if swift(>=2.3)
    let configDirectoryURL = tulsiProjectURL.URLByAppendingPathComponent(TulsiProjectDocument.ProjectConfigsSubpath)!
#else
    let configDirectoryURL = tulsiProjectURL.URLByAppendingPathComponent(TulsiProjectDocument.ProjectConfigsSubpath)
#endif
    if !isExistingDirectory(configDirectoryURL) {
      throw HeadlessModeError.InvalidConfigPath("The given Tulsi project does not contain any configs")
    }

    let configFilename: String
    if configName.hasSuffix(TulsiGeneratorConfig.FileExtension) {
      configFilename = configName
    } else {
      configFilename = "\(configName).\(TulsiGeneratorConfig.FileExtension)"
    }
#if swift(>=2.3)
    let configFileURL = configDirectoryURL.URLByAppendingPathComponent(configFilename)!
#else
    let configFileURL = configDirectoryURL.URLByAppendingPathComponent(configFilename)
#endif
    if NSFileManager.defaultManager().isReadableFileAtPath(configFileURL.path!) {
      return (configFileURL, tulsiProjectURL.URLByDeletingLastPathComponent!)
    }
    throw HeadlessModeError.InvalidConfigPath("The given Tulsi project does not contain a Tulsi config named \(configName).")
  }

  private func isExistingDirectory(url: NSURL) -> Bool {
    var isDirectory = ObjCBool(false)
    if !NSFileManager.defaultManager().fileExistsAtPath(url.path!, isDirectory: &isDirectory) {
      return false
    }
    return isDirectory.boolValue
  }

  private func loadConfig(url: NSURL, bazelURL: NSURL?) throws -> TulsiGeneratorConfig {
    let config: TulsiGeneratorConfig
    do {
      config = try TulsiGeneratorConfig.load(url, bazelURL: bazelURL)
    } catch TulsiGeneratorConfig.Error.BadInputFilePath {
      throw HeadlessModeError.InvalidConfigFileContents("Failed to read config file at \(url.path!)")
    } catch TulsiGeneratorConfig.Error.FailedToReadAdditionalOptionsData(let info) {
      throw HeadlessModeError.InvalidConfigFileContents("Failed to read per-user config file: \(info)")
    } catch TulsiGeneratorConfig.Error.DeserializationFailed(let info) {
      throw HeadlessModeError.InvalidConfigFileContents("Config file at \(url.path!) is invalid: \(info)")
    } catch {
      throw HeadlessModeError.InvalidConfigFileContents("Unexpected exception reading config file at \(url.path!)")
    }

    if !config.bazelURL.fileURL {
      throw HeadlessModeError.InvalidBazelPath
    }
    return config
  }
}
