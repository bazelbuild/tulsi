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

    let explicitBazelURL: URL?
    if let bazelPath = arguments.bazel {
      if !FileManager.default.isExecutableFile(atPath: bazelPath) {
        throw HeadlessModeError.invalidBazelPath
      }
      explicitBazelURL = URL(fileURLWithPath: bazelPath)
      TulsiProjectDocument.suppressRuleEntryUpdateOnLoad = true
    } else {
      explicitBazelURL = nil
    }

    defer {
      TulsiProjectDocument.showAlertsOnErrors = true
      TulsiProjectDocument.suppressRuleEntryUpdateOnLoad = false
    }

    guard let configPath = arguments.generatorConfig else {
      fatalError("HeadlessXcodeProjectGenerator invoked without a valid generatorConfig")
    }

    let (projectURL, configURL, defaultOutputFolderURL) = try resolveConfigPath(configPath)

    let documentController = NSDocumentController.shared
    let doc: NSDocument
    do {
      doc = try documentController.makeDocument(withContentsOf: projectURL,
                                                                 ofType: "com.google.tulsi.project")
    } catch TulsiProjectDocument.DocumentError.invalidWorkspace(let info) {
      throw HeadlessModeError.invalidProjectFileContents("Failed to load project due to invalid workspace: \(info)")
    } catch let e as NSError {
      throw HeadlessModeError.invalidProjectFileContents("Failed to load project due to unexpected exception: \(e)")
    } catch {
      throw HeadlessModeError.invalidProjectFileContents("Failed to load project due to unexpected exception.")
    }
    guard let projectDocument = doc as? TulsiProjectDocument else {
      throw HeadlessModeError.invalidProjectFileContents("\(doc) is not of the expected type.")
    }

    let outputFolderURL: URL
    if let option = arguments.outputFolder {
      outputFolderURL = URL(fileURLWithPath: option, isDirectory: true)
    } else if let defaultOutputFolderURL = defaultOutputFolderURL {
      outputFolderURL = defaultOutputFolderURL
    } else {
      throw HeadlessModeError.explicitOutputOptionRequired
    }

    var config = try loadConfig(configURL, bazelURL: explicitBazelURL)
    config = config.configByAppendingPathFilters(arguments.additionalPathFilters)
    if let project = projectDocument.project {
      config = config.configByResolvingInheritedSettingsFromProject(project)
    }
    if let extraFlags = arguments.buildOptions {
      config.options[.BazelBuildOptionsDebug].appendProjectValue(extraFlags)
      config.options[.BazelBuildOptionsRelease].appendProjectValue(extraFlags)
    }

    let workspaceRootURL: URL
    let projectWorkspaceRootURL = projectDocument.workspaceRootURL
    if let workspaceRootOverride = arguments.workspaceRootOverride {
      workspaceRootURL = URL(fileURLWithPath: workspaceRootOverride, isDirectory: true)
      if !isExistingDirectory(workspaceRootURL) {
        throw HeadlessModeError.invalidWorkspaceRootOverride
      }
      if projectWorkspaceRootURL != nil {
        print("Overriding project workspace root (\(projectWorkspaceRootURL!.path)) with " +
            "command-line parameter (\(workspaceRootOverride))")
      }
    } else {
      guard let projectWorkspaceRootURL = projectWorkspaceRootURL else {
        throw HeadlessModeError.invalidProjectFileContents("Invalid workspaceRoot")
      }
      workspaceRootURL = projectWorkspaceRootURL as URL
    }

    print("Generating project into '\(outputFolderURL.path)' using:\n" +
              "\tconfig at '\(configURL.path)'\n" +
              "\tBazel workspace at '\(workspaceRootURL.path)'\n" +
              "\tBazel at '\(config.bazelURL.path)'.\n" +
              "This may take a while.")

    let result = TulsiGeneratorConfigDocument.generateXcodeProjectInFolder(outputFolderURL,
                                                                           withGeneratorConfig: config,
                                                                           workspaceRootURL: workspaceRootURL,
                                                                           messageLog: nil)

    switch result {
      case .success(let url):
        print("Generated project at \(url.path)")
        if arguments.openXcodeOnSuccess {
          print("Opening generated project in Xcode")
          NSWorkspace.shared.open(url)
        }
      case .failure:
        throw HeadlessModeError.generationFailed
    }
  }

  // MARK: - Private methods

  private func resolveConfigPath(_ path: String) throws -> (projectURL: URL,
                                                          configURL: URL,
                                                          defaultOutputFolderURL: URL?) {
    let tulsiProjExtension = TulsiProjectDocument.getTulsiBundleExtension()
    let components = path.components(separatedBy: ":")
    if components.count == 2 {
      var pathString = components[0] as NSString
      let projectExtension = pathString.pathExtension
      if projectExtension != tulsiProjExtension {
        pathString = pathString.appendingPathExtension(tulsiProjExtension)! as NSString
      }
      let projectURL = URL(fileURLWithPath: pathString as String)
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
      let projectPath = pathString.appendingPathExtension(tulsiProjExtension)!
      if isExistingDirectory(URL(fileURLWithPath: projectPath, isDirectory: true)) {
        isProject = true
        pathString = projectPath as NSString
      } else {
        let projectName = (pathString.lastPathComponent as NSString).appendingPathExtension(tulsiProjExtension)!
        let projectWithinPath = pathString.appendingPathComponent(projectName)
        if isExistingDirectory(URL(fileURLWithPath: projectWithinPath, isDirectory: true)) {
          isProject = true
          pathString = projectWithinPath as NSString
        }
      }
    }
    if isProject {
      let project = pathString.lastPathComponent as NSString
      let projectName = project.deletingPathExtension
      let (configURL, defaultOutputFolderURL) = try locateConfigNamed(projectName,
                                                                      inTulsiProject: pathString as String)
      let projectURL = URL(fileURLWithPath: pathString as String)
      return (projectURL, configURL, defaultOutputFolderURL)
    }

    throw HeadlessModeError.invalidConfigPath("The given config is invalid")
  }

  private func locateConfigNamed(_ configName: String,
                                 inTulsiProject tulsiProj: String) throws -> (configURL: URL, defaultOutputFolderURL: URL?) {
    let tulsiProjectURL = URL(fileURLWithPath: tulsiProj, isDirectory: true)
    if !isExistingDirectory(tulsiProjectURL) {
      throw HeadlessModeError.invalidConfigPath("The given Tulsi project does not exist")
    }

    let configDirectoryURL = tulsiProjectURL.appendingPathComponent(TulsiProjectDocument.ProjectConfigsSubpath)
    if !isExistingDirectory(configDirectoryURL) {
      throw HeadlessModeError.invalidConfigPath("The given Tulsi project does not contain any configs")
    }

    let configFilename: String
    if configName.hasSuffix(TulsiGeneratorConfig.FileExtension) {
      configFilename = configName
    } else {
      configFilename = "\(configName).\(TulsiGeneratorConfig.FileExtension)"
    }

    let configFileURL = configDirectoryURL.appendingPathComponent(configFilename)
    if FileManager.default.isReadableFile(atPath: configFileURL.path) {
      return (configFileURL, tulsiProjectURL.deletingLastPathComponent())
    }
    throw HeadlessModeError.invalidConfigPath("The given Tulsi project does not contain a Tulsi config named \(configName).")
  }

  private func isExistingDirectory(_ url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
      return false
    }
    return isDirectory.boolValue
  }

  private func loadConfig(_ url: URL, bazelURL: URL?) throws -> TulsiGeneratorConfig {
    let config: TulsiGeneratorConfig
    do {
      config = try TulsiGeneratorConfig.load(url, bazelURL: bazelURL)
    } catch TulsiGeneratorConfig.ConfigError.badInputFilePath {
      throw HeadlessModeError.invalidConfigFileContents("Failed to read config file at \(url.path)")
    } catch TulsiGeneratorConfig.ConfigError.failedToReadAdditionalOptionsData(let info) {
      throw HeadlessModeError.invalidConfigFileContents("Failed to read per-user config file: \(info)")
    } catch TulsiGeneratorConfig.ConfigError.deserializationFailed(let info) {
      throw HeadlessModeError.invalidConfigFileContents("Config file at \(url.path) is invalid: \(info)")
    } catch {
      throw HeadlessModeError.invalidConfigFileContents("Unexpected exception reading config file at \(url.path)")
    }

    if !config.bazelURL.isFileURL {
      throw HeadlessModeError.invalidBazelPath
    }
    return config
  }
}
