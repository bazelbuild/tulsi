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
class HeadlessXcodeProjectGenerator {
  enum Error: ErrorType {
    /// The given required commandline option was not provided.
    case MissingConfigOption(String)
    /// The config file path was invalid for the given reason.
    case InvalidConfigPath(String)
    /// The config file contents were invalid for the given reason.
    case InvalidConfigFileContents(String)
    /// The project file contents were invalid for the given reason.
    case InvalidProjectFileContents(String)
    /// The given configuration file requires that an explicit output path be given.
    case ExplicitOutputOptionRequired
    /// XCode project generation failed for the given reason.
    case GenerationFailed(String)
    /// The path to the Bazel binary given on the commandline is invalid.
    case InvalidBazelPath
  }

  let arguments: TulsiCommandlineParser.Arguments

  init(arguments: TulsiCommandlineParser.Arguments) {
    self.arguments = arguments
  }

  /// Performs project generation.
  func generate() throws {
    TulsiProjectDocument.showAlertsOnErrors = false
    defer { TulsiProjectDocument.showAlertsOnErrors = true }

    guard let configPath = arguments.generatorConfig else {
      throw Error.MissingConfigOption(TulsiCommandlineParser.ParamGeneratorConfigLong)
    }

    let (projectURL, configURL, defaultOutputFolderURL) = try resolveConfigPath(configPath)

    let documentController = NSDocumentController.sharedDocumentController()
    let doc: NSDocument
    do {
      doc = try documentController.makeDocumentWithContentsOfURL(projectURL,
                                                                 ofType: "com.google.tulsi.project")
    } catch TulsiProjectDocument.Error.InvalidWorkspace(let info) {
      throw Error.InvalidProjectFileContents("Failed to load project due to invalid workspace: \(info)")
    } catch let e as NSError {
      throw Error.InvalidProjectFileContents("Failed to load project due to unexpected exception: \(e)")
    } catch {
      throw Error.InvalidProjectFileContents("Failed to load project due to unexpected exception.")
    }
    guard let projectDocument = doc as? TulsiProjectDocument else {
      throw Error.InvalidProjectFileContents("\(doc) is not of the expected type.")
    }

    let explicitBazelURL: NSURL?
    if let bazelPath = arguments.bazel {
      if !NSFileManager.defaultManager().isExecutableFileAtPath(bazelPath) {
        throw Error.InvalidBazelPath
      }
      explicitBazelURL = NSURL(fileURLWithPath: bazelPath)
    } else {
      explicitBazelURL = nil
    }

    let outputFolderURL: NSURL
    if let option = arguments.outputFolder {
      outputFolderURL = NSURL(fileURLWithPath: option, isDirectory: true)
    } else if let defaultOutputFolderURL = defaultOutputFolderURL {
      outputFolderURL = defaultOutputFolderURL
    } else {
      throw Error.ExplicitOutputOptionRequired
    }

    let config = try loadConfig(configURL, bazelURL: explicitBazelURL)
    let resolvedConfig: TulsiGeneratorConfig
    if let projectOptionSet = projectDocument.optionSet {
      resolvedConfig = config.configByResolvingInheritedOptions(projectOptionSet)
    } else {
      resolvedConfig = config
    }

    guard let workspaceRootURL = projectDocument.workspaceRootURL else {
      throw Error.InvalidProjectFileContents("Invalid workspaceRoot")
    }

    print("Generating project into \(outputFolderURL.path!) using config at \(configURL.path!) " +
              "and Bazel workspace at \(workspaceRootURL.path!).\n" +
              "This may take a while.")

    let result = TulsiGeneratorConfigDocument.generateXcodeProjectInFolder(outputFolderURL,
                                                                           withGeneratorConfig: resolvedConfig,
                                                                           workspaceRootURL: workspaceRootURL,
                                                                           messageLog: nil)
    switch result {
      case .Success(let url):
        if arguments.openXcodeOnSuccess {
          print("Opening generated project in Xcode")
          NSWorkspace.sharedWorkspace().openURL(url)
        } else {
          print("Generated project at \(outputFolderURL.path!)")
        }
      case .Failure(let errorInfo):
        throw Error.GenerationFailed(errorInfo)
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
      let projectPath = pathString.stringByAppendingPathExtension(tulsiProjExtension)!
      let projectURL = NSURL(fileURLWithPath: projectPath, isDirectory: true)
      if isExistingDirectory(projectURL) {
        isProject = true
        pathString = projectPath as NSString
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

    throw Error.InvalidConfigPath("The given config is invalid")
  }

  private func locateConfigNamed(configName: String,
                                 inTulsiProject tulsiProj: String) throws -> (configURL: NSURL, defaultOutputFolderURL: NSURL?) {
    let tulsiProjectURL = NSURL(fileURLWithPath: tulsiProj, isDirectory: true)
    if !isExistingDirectory(tulsiProjectURL) {
      throw Error.InvalidConfigPath("The given Tulsi project does not exist")
    }

    let configDirectoryURL = tulsiProjectURL.URLByAppendingPathComponent(TulsiProjectDocument.ProjectConfigsSubpath)
    if !isExistingDirectory(configDirectoryURL) {
      throw Error.InvalidConfigPath("The given Tulsi project does not contain any configs")
    }

    let configFilename: String
    if configName.hasSuffix(TulsiGeneratorConfig.FileExtension) {
      configFilename = configName
    } else {
      configFilename = "\(configName).\(TulsiGeneratorConfig.FileExtension)"
    }
    let configFileURL = configDirectoryURL.URLByAppendingPathComponent(configFilename)
    if NSFileManager.defaultManager().isReadableFileAtPath(configFileURL.path!) {
      return (configFileURL, tulsiProjectURL.URLByDeletingLastPathComponent!)
    }
    throw Error.InvalidConfigPath("The given Tulsi project does not contain a Tulsi config named \(configName).")
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
      throw Error.InvalidConfigFileContents("Failed to read config file at \(url.path!)")
    } catch TulsiGeneratorConfig.Error.FailedToReadAdditionalOptionsData(let info) {
      throw Error.InvalidConfigFileContents("Failed to read per-user config file: \(info)")
    } catch TulsiGeneratorConfig.Error.DeserializationFailed(let info) {
      throw Error.InvalidConfigFileContents("Config file at \(url.path!) is invalid: \(info)")
    } catch {
      throw Error.InvalidConfigFileContents("Unexpected exception reading config file at \(url.path!)")
    }

    if !config.bazelURL.fileURL {
      throw Error.InvalidBazelPath
    }
    return config
  }
}


class TulsiCommandlineParser {
  /// Commandline argument indicating that the following arguments are meant to be consumed as
  /// commandline arguments.
  static let ParamCommandlineArgumentSentinal = "--"

  static let ParamHelpShort = "-h"
  static let ParamHelpLong = "--help"
  static let ParamQuietShort = "-q"
  static let ParamQuietLong = "--quiet"

  static let ParamBazel = "--bazel"
  static let ParamGeneratorConfigShort = "-c"
  static let ParamGeneratorConfigLong = "--genconfig"
  static let ParamOutputFolderShort = "-o"
  static let ParamOutputFolderLong = "--outputfolder"
  static let ParamWorkspaceRootShort = "-w"
  static let ParamWorkspaceRootLong = "--workspaceroot"
  static let ParamNoOpenXcode = "--no-open-xcode"

  let arguments: Arguments
  let commandlineSentinalFound: Bool

  struct Arguments {
    let bazel: String?
    let generatorConfig: String?
    let outputFolder: String?
    let verbose: Bool
    let openXcodeOnSuccess: Bool

    init() {
      bazel = nil
      generatorConfig = nil
      outputFolder = nil
      verbose = true
      openXcodeOnSuccess = true
    }

    init(dict: [String: AnyObject]) {
      bazel = dict[TulsiCommandlineParser.ParamBazel] as? String
      generatorConfig = dict[TulsiCommandlineParser.ParamGeneratorConfigLong] as? String
      outputFolder = dict[TulsiCommandlineParser.ParamOutputFolderLong] as? String
      verbose = !(dict[TulsiCommandlineParser.ParamQuietLong] as? Bool == true)
      openXcodeOnSuccess = !(dict[TulsiCommandlineParser.ParamNoOpenXcode] as? Bool == true)
    }
  }

  init() {
    var args = [String](Process.arguments.dropFirst())

    // See if the arguments are intended to be interpreted as commandline args.
    if args.first != TulsiCommandlineParser.ParamCommandlineArgumentSentinal {
      commandlineSentinalFound = false
      arguments = Arguments()
      return
    }
    commandlineSentinalFound = true
    if let cfBundleVersion = NSBundle.mainBundle().infoDictionary?["CFBundleVersion"] as? String {
      print("Tulsi version \(cfBundleVersion)")
    }

    args = [String](args.dropFirst())

    var parsedArguments = [String: AnyObject]()
    func storeValueAt(index: Int, forArgument argumentName: String) {
      guard index < args.count else {
        print("Missing required parameter for \(argumentName) option.")
        exit(1)
      }
      let value = args[index]
      parsedArguments[argumentName] = value
    }

    var i = 0
    while i < args.count {
      let arg = args[i]
      i += 1
      switch arg {
        case TulsiCommandlineParser.ParamHelpShort:
          fallthrough
        case TulsiCommandlineParser.ParamHelpLong:
          TulsiCommandlineParser.printUsage()
          exit(1)

        case TulsiCommandlineParser.ParamQuietShort:
          fallthrough
        case TulsiCommandlineParser.ParamQuietLong:
          parsedArguments[TulsiCommandlineParser.ParamQuietLong] = true

        case TulsiCommandlineParser.ParamBazel:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamBazel)
          i += 1

        case TulsiCommandlineParser.ParamGeneratorConfigShort:
          fallthrough
        case TulsiCommandlineParser.ParamGeneratorConfigLong:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamGeneratorConfigLong)
          i += 1

        case TulsiCommandlineParser.ParamNoOpenXcode:
          parsedArguments[TulsiCommandlineParser.ParamNoOpenXcode] = true

        case TulsiCommandlineParser.ParamOutputFolderShort:
          fallthrough
        case TulsiCommandlineParser.ParamOutputFolderLong:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamOutputFolderLong)
          i += 1

        // TODO(abaire): Remove workspaceRoot entirely.
        case TulsiCommandlineParser.ParamWorkspaceRootShort:
          fallthrough
        case TulsiCommandlineParser.ParamWorkspaceRootLong:
          print("Note, the \(TulsiCommandlineParser.ParamWorkspaceRootLong) parameter is deprecated " +
                    "and will be removed in a future release.")
          i += 1

        default:
          print("Ignoring unknown option \"\(arg)\"")
      }
    }

    arguments = Arguments(dict: parsedArguments)
  }

  // MARK: - Private methods

  private static func printUsage() {
    let usage = [
        "Usage: \(Process.arguments[0]) -- [options]",
        "",
        "Where options are:",
        "  \(ParamBazel) <path>: Path to the Bazel binary.",
        "  \(ParamGeneratorConfigLong) <config>: (required)",
        "    Generates an Xcode project using the given generator config. The config must be",
        "      expressed as the path to a Tulsi project, optionally followed by a colon \":\"",
        "      and a config name.",
        "        e.g., \"/path/to/MyProject.tulsiproj:MyConfig\"",
        "      omitting the trailing colon/config will attempt to use a config with the same name",
        "      as the project. i.e.",
        "        \"MyProject.tulsiproj\"",
        "      is equivalent to ",
        "        \"MyProject.tulsiproj:MyProject\"",
        "  \(ParamNoOpenXcode): Do not automatically open the generated project in Xcode.",
        "  \(ParamOutputFolderLong) <path>: Sets the folder into which the Xcode project should be saved.",
        "  \(ParamHelpLong): Show this help message.",
        "  \(ParamQuietLong): Hide verbose info messages (warning: may also hide some error details).",
    ]
    print(usage.joinWithSeparator("\n") + "\n")
  }
}
