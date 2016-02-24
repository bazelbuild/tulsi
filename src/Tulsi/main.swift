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
class HeadlessXcodeProjectGenerator: MessageLoggerProtocol {
  enum Error: ErrorType {
    /// The given required commandline option was not provided.
    case MissingConfigOption(String)
    /// The config file path was invalid for the given reason.
    case InvalidConfigPath(String)
    /// The config file contents were invalid for the given reason.
    case InvalidConfigFileContents(String)
    /// The given configuration file requires that an explicit output path be given.
    case ExplicitOutputOptionRequired
    /// XCode project generation failed for the given reason.
    case GenerationFailed(String)
    /// The path to the Bazel binary given on the commandline is invalid.
    case InvalidBazelPath
  }

  let arguments: CommandlineParser.Arguments

  init(arguments: CommandlineParser.Arguments) {
    self.arguments = arguments
  }

  /// Performs project generation.
  func generate() throws {
    guard let configPath = arguments.generatorConfig else {
      throw Error.MissingConfigOption(CommandlineParser.ParamGeneratorConfigLong)
    }
    let (configURL, defaultOutputFolderURL) = try resolveConfigPath(configPath)

    let explicitBazelURL: NSURL?
    if let bazelPath = arguments.bazel {
      if !NSFileManager.defaultManager().isExecutableFileAtPath(bazelPath) {
        throw Error.InvalidBazelPath
      }
      explicitBazelURL = NSURL(fileURLWithPath: bazelPath)
    } else {
      explicitBazelURL = nil
    }

    let config = try loadConfig(configURL, bazelURL: explicitBazelURL)

    let outputFolderURL: NSURL
    if let option = arguments.outputFolder {
      outputFolderURL = NSURL(fileURLWithPath: option, isDirectory: true)
    } else if let defaultOutputFolderURL = defaultOutputFolderURL {
      outputFolderURL = defaultOutputFolderURL
    } else {
      throw Error.ExplicitOutputOptionRequired
    }

    guard let workspaceRootPath = arguments.workspaceRoot else {
      throw Error.MissingConfigOption(CommandlineParser.ParamWorkspaceRootLong)
    }
    let workspaceRootURL = NSURL(fileURLWithPath: workspaceRootPath, isDirectory: true)

    print("Generating project into \(outputFolderURL.path!) using config at \(configURL.path!) " +
              "and Bazel workspace at \(workspaceRootPath).\n" +
              "This may take awhile.")
    let result = TulsiGeneratorConfigDocument.generateXcodeProjectInFolder(outputFolderURL,
                                                                           withGeneratorConfig: config,
                                                                           workspaceRootURL: workspaceRootURL,
                                                                           messageLogger: self,
                                                                           treatMissingSourceTargetsAsWarnings: arguments.warnMissingSources)
    switch result {
      case .Success(let url):
        NSWorkspace.sharedWorkspace().openURL(url)
      case .Failure(let errorInfo):
        throw Error.GenerationFailed(errorInfo)
    }
  }

  // MARK: - MessageLoggerProtocol

  func warning(message: String) {
    print("W: \(message)")
  }

  func error(message: String) {
    print("E: \(message)")
  }

  func info(message: String) {
    if arguments.verbose {
      print("I: \(message)")
    }
  }

  // MARK: - Private methods

  private func resolveConfigPath(path: String) throws -> (configURL: NSURL, defaultOutputFolderURL: NSURL?) {
    let fileManager = NSFileManager.defaultManager()

    if path.hasSuffix(".xcodeproj") || path.hasSuffix(".xcodeproj/"){
      let projectURL = NSURL.fileURLWithPath(path, isDirectory: true)
      let configDirectoryURL = projectURL.URLByAppendingPathComponent(TulsiXcodeProjectGenerator.ConfigDirectorySubpath)
      if !isExistingDirectory(configDirectoryURL) {
        throw Error.InvalidConfigPath("The given Xcode project does not contain a Tulsi config folder.")
      }

      do {
        let contents = try fileManager.contentsOfDirectoryAtURL(configDirectoryURL,
                                                                includingPropertiesForKeys: nil,
                                                                options: .SkipsHiddenFiles)
        for url in contents {
          guard let path = url.path else { continue }
          if path.hasSuffix(TulsiGeneratorConfig.FileExtension) {
            return (url, projectURL.URLByDeletingLastPathComponent!)
          }
        }
      } catch let e as NSError {
        throw Error.InvalidConfigPath("Failed to search the given Xcode project: \(e.localizedDescription)")
      } catch {
        throw Error.InvalidConfigPath("Failed to search the given Xcode project")
      }
      throw Error.InvalidConfigPath("The given Xcode project does not contain a Tulsi config.")
    }

    let components = path.componentsSeparatedByString(":")
    if components.count == 2 {
      var tulsiProj = components[0]
      let bundleExtension = TulsiProjectDocument.getTulsiBundleExtension()
      if !tulsiProj.hasSuffix(bundleExtension) {
        tulsiProj += ".\(bundleExtension)"
      }

      let tulsiProjectURL = NSURL(fileURLWithPath: tulsiProj, isDirectory: true)
      if !isExistingDirectory(tulsiProjectURL) {
        throw Error.InvalidConfigPath("The given Tulsi project does not exist")
      }

      let configDirectoryURL = tulsiProjectURL.URLByAppendingPathComponent(TulsiProjectDocument.ProjectConfigsSubpath)
      if !isExistingDirectory(configDirectoryURL) {
        throw Error.InvalidConfigPath("The given Tulsi project does not contain any configs")
      }

      let configName = components[1]
      let configFilename: String
      if configName.hasSuffix(TulsiGeneratorConfig.FileExtension) {
        configFilename = configName
      } else {
        configFilename = "\(configName).\(TulsiGeneratorConfig.FileExtension)"
      }
      let configFileURL = configDirectoryURL.URLByAppendingPathComponent(configFilename)
      if fileManager.isReadableFileAtPath(configFileURL.path!) {
        return (configFileURL, tulsiProjectURL.URLByDeletingLastPathComponent!)
      }
      throw Error.InvalidConfigPath("The given Tulsi project does not contain a Tulsi config named \(configName).")
    }

    // If the given path exists, assume it's a config file.
    if path.hasSuffix(TulsiGeneratorConfig.FileExtension) && fileManager.isReadableFileAtPath(path) {
      let configURL = NSURL(fileURLWithPath:path, isDirectory: false)
      return (configURL, nil)
    }

    throw Error.InvalidConfigPath("The given config is invalid")
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


class CommandlineParser {
  /// Commandline argument indicating that the following arguments are meant to be consumed as
  /// commandline arguments.
  static let ParamCommandlineArgumentSentinal = "--"

  static let ParamHelpShort = "-h"
  static let ParamHelpLong = "--help"
  static let ParamVerboseShort = "-v"
  static let ParamVerboseLong = "--verbose"
  static let ParamWarnMissingSources = "--warn-missing-sources"

  static let ParamBazel = "--bazel"
  static let ParamGeneratorConfigShort = "-c"
  static let ParamGeneratorConfigLong = "--genconfig"
  static let ParamOutputFolderShort = "-o"
  static let ParamOutputFolderLong = "--outputfolder"
  static let ParamWorkspaceRootShort = "-w"
  static let ParamWorkspaceRootLong = "--workspaceroot"

  private let arguments: Arguments
  let commandlineSentinalFound: Bool

  struct Arguments {
    let bazel: String?
    let generatorConfig: String?
    let outputFolder: String?
    let workspaceRoot: String?
    let warnMissingSources: Bool
    let verbose: Bool

    init() {
      bazel = nil
      generatorConfig = nil
      outputFolder = nil
      workspaceRoot = nil
      warnMissingSources = false
      verbose = false
    }

    init(dict: [String: AnyObject]) {
      bazel = dict[CommandlineParser.ParamBazel] as? String
      generatorConfig = dict[CommandlineParser.ParamGeneratorConfigLong] as? String
      outputFolder = dict[CommandlineParser.ParamOutputFolderLong] as? String
      workspaceRoot = dict[CommandlineParser.ParamWorkspaceRootLong] as? String
      warnMissingSources = dict[CommandlineParser.ParamWarnMissingSources] as? Bool == true
      verbose = dict[CommandlineParser.ParamVerboseLong] as? Bool == true
    }
  }

  init() {
    var args = [String](Process.arguments.dropFirst())

    // See if the arguments are intended to be interpreted as commandline args.
    if args.first != CommandlineParser.ParamCommandlineArgumentSentinal {
      commandlineSentinalFound = false
      arguments = Arguments()
      return
    }
    commandlineSentinalFound = true
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

    for var i = 0; i < args.count; i += 1 {
      let arg = args[i]
      switch arg {
        case CommandlineParser.ParamHelpShort:
          fallthrough
        case CommandlineParser.ParamHelpLong:
          CommandlineParser.printUsage()
          exit(1)

        case CommandlineParser.ParamVerboseShort:
          fallthrough
        case CommandlineParser.ParamVerboseLong:
          parsedArguments[CommandlineParser.ParamVerboseLong] = true

        case CommandlineParser.ParamWarnMissingSources:
          parsedArguments[CommandlineParser.ParamWarnMissingSources] = true


        case CommandlineParser.ParamBazel:
          i += 1
          storeValueAt(i, forArgument: CommandlineParser.ParamBazel)

        case CommandlineParser.ParamGeneratorConfigShort:
          fallthrough
        case CommandlineParser.ParamGeneratorConfigLong:
          i += 1
          storeValueAt(i, forArgument: CommandlineParser.ParamGeneratorConfigLong)

        case CommandlineParser.ParamOutputFolderShort:
          fallthrough
        case CommandlineParser.ParamOutputFolderLong:
          i += 1
          storeValueAt(i, forArgument: CommandlineParser.ParamOutputFolderLong)

        case CommandlineParser.ParamWorkspaceRootShort:
          fallthrough
        case CommandlineParser.ParamWorkspaceRootLong:
          i += 1
          storeValueAt(i, forArgument: CommandlineParser.ParamWorkspaceRootLong)

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
        "    Generates an Xcode project using the given generator config.",
        "    The <config> may be specified in three ways:",
        "      * the path to a \".\(TulsiGeneratorConfig.FileExtension)\" file",
        "      * the path to a Tulsi-generated Xcode project",
        "        e.g., \"/path/to/MyGeneratedXcodeProject.xcodeproj\"",
        "      * the path to a Tulsi project followed by a colon \":\" and a config name",
        "        e.g., \"/path/to/MyProject.tulsiproj:MyConfig\"",
        "  \(ParamOutputFolderLong) <path>: Sets the folder into which the Xcode project should be saved.",
        "  \(ParamWorkspaceRootLong) <path>: (required)",
        "    Path to the folder containing the Bazel WORKSPACE file.",
        "  \(ParamHelpLong): Show this help message.",
        "  \(ParamVerboseLong): Show verbose info messages.",
        "  \(ParamWarnMissingSources): Treat missing source rules as warnings rather than errors.",
    ]
    print(usage.joinWithSeparator("\n") + "\n")
  }
}


// MARK: - Application entrypoint

// Parse the commandline parameters to see if the app should operate in headless mode or not.
let commandlineParser = CommandlineParser()

if !commandlineParser.commandlineSentinalFound {
  NSApplicationMain(Process.argc, Process.unsafeArgv)
  exit(0)
}

let queue = dispatch_queue_create("com.google.Tulsi.xcodeProjectGenerator", DISPATCH_QUEUE_SERIAL)
dispatch_async(queue) {
  let generator = HeadlessXcodeProjectGenerator(arguments: commandlineParser.arguments)
  do {
    try generator.generate()
    exit(0)
  } catch HeadlessXcodeProjectGenerator.Error.MissingConfigOption(let option) {
    print("Missing required \(option) param.")
    exit(10)
  } catch HeadlessXcodeProjectGenerator.Error.InvalidConfigPath(let reason) {
    print("Invalid \(CommandlineParser.ParamGeneratorConfigLong) param: \(reason)")
    exit(11)
  } catch HeadlessXcodeProjectGenerator.Error.InvalidConfigFileContents(let reason) {
    print("Failed to read the given generator config: \(reason)")
    exit(12)
  } catch HeadlessXcodeProjectGenerator.Error.ExplicitOutputOptionRequired {
    print("The \(CommandlineParser.ParamOutputFolderLong) option is required for the selected config")
    exit(13)
  } catch HeadlessXcodeProjectGenerator.Error.InvalidBazelPath {
    print("The path to the bazel binary is invalid")
    exit(14)
  } catch HeadlessXcodeProjectGenerator.Error.GenerationFailed(let reason) {
    print("Generation failed: \(reason)")
    exit(15)
  } catch let e as NSError {
    print("An unexpected exception occurred: \(e.localizedDescription)")
    exit(126)
  } catch {
    print("An unexpected exception occurred")
    exit(127)
  }
}

dispatch_main()
