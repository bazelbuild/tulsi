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


/// Processes Tulsi command-line options.
class TulsiCommandlineParser {

  /// Operational modes that may be indicated by the command-line options.
  enum OperationMode {
    /// An unspecified or multi-specified mode.
    case invalid
    /// A tulsiproj bundle should be created.
    case tulsiProjectCreator
    /// An xcodeproj bundle should be created.
    case xcodeProjectGenerator
  }

  struct Arguments {
    let bazel: String?
    let generatorConfig: String?
    let tulsiprojName: String?
    let outputFolder: String?
    let workspaceRootOverride: String?
    let verboseLevel: TulsiMessageLevel
    let openXcodeOnSuccess: Bool
    let additionalPathFilters: Set<String>
    let buildStartupOptions: String?
    let buildOptions: String?
    let buildTargets: [String]?
    let logToFile: Bool

    init() {
      bazel = nil
      generatorConfig = nil
      tulsiprojName = nil
      outputFolder = nil
      workspaceRootOverride = nil
      verboseLevel = .Info
      openXcodeOnSuccess = true
      additionalPathFilters = Set()
      buildStartupOptions = nil
      buildOptions = nil
      buildTargets = nil
      logToFile = false
    }

    init(dict: [String: Any]) {

      func standardizedPath(_ key: String) -> String? {
        if let path = dict[key] as? NSString {
          return path.standardizingPath
        }
        return nil
      }

      bazel = standardizedPath(TulsiCommandlineParser.ParamBazel)
      generatorConfig = standardizedPath(TulsiCommandlineParser.ParamGeneratorConfigLong)
      tulsiprojName = standardizedPath(TulsiCommandlineParser.ParamCreateTulsiProj)
      outputFolder = standardizedPath(TulsiCommandlineParser.ParamOutputFolderLong)

      if (dict[TulsiCommandlineParser.ParamVerboseLong] as? Bool == true) {
        verboseLevel = .Debug
      } else if (dict[TulsiCommandlineParser.ParamQuietLong] as? Bool == true) {
        verboseLevel = .Syslog
      } else {
        verboseLevel = .Info
      }

      workspaceRootOverride = standardizedPath(TulsiCommandlineParser.ParamWorkspaceRootLong)
      openXcodeOnSuccess = !(dict[TulsiCommandlineParser.ParamNoOpenXcode] as? Bool == true)
      additionalPathFilters = dict[TulsiCommandlineParser.ParamAdditionalPathFilters] as? Set<String> ?? Set()
      buildStartupOptions = dict[TulsiCommandlineParser.ParamBuildStartupOptions] as? String
      buildOptions = dict[TulsiCommandlineParser.ParamBuildOptions] as? String
      buildTargets = dict[TulsiCommandlineParser.ParamBuildTargetLong] as? [String]
      logToFile = dict[TulsiCommandlineParser.ParamLogToFile] as? Bool == true
    }
  }

  /// Commandline argument indicating that the following arguments are meant to be consumed as
  /// commandline arguments.
  static let ParamCommandlineArgumentSentinal = "--"

  // Common options:
  static let ParamHelpShort = "-h"
  static let ParamHelpLong = "--help"
  static let ParamOutputFolderShort = "-o"
  static let ParamOutputFolderLong = "--outputfolder"
  static let ParamVerboseShort = "-v"
  static let ParamVerboseLong = "--verbose"
  static let ParamQuietShort = "-q"
  static let ParamQuietLong = "--quiet"
  static let ParamWorkspaceRootShort = "-w"
  static let ParamWorkspaceRootLong = "--workspaceroot"

  static let ParamAdditionalPathFilters = "--additionalSourceFilters"
  static let ParamBazel = "--bazel"
  static let ParamBuildOptions = "--build-options"

  // Xcode project generation mode:
  static let ParamGeneratorConfigShort = "-c"
  static let ParamGeneratorConfigLong = "--genconfig"
  static let ParamNoOpenXcode = "--no-open-xcode"

  // Tulsi project creation mode:
  static let ParamCreateTulsiProj = "--create-tulsiproj"
  static let ParamBuildStartupOptions = "--startup-options"
  static let ParamBuildTargetShort = "-t"
  static let ParamBuildTargetLong = "--target"

  static let ParamLogToFile = "--log-to-file"

  let arguments: Arguments
  let commandlineSentinalFound: Bool

  var mode: OperationMode {
    if arguments.generatorConfig != nil && arguments.tulsiprojName != nil { return .invalid }
    if arguments.generatorConfig != nil { return .xcodeProjectGenerator }
    if arguments.tulsiprojName != nil { return .tulsiProjectCreator }
    return .invalid
  }

  init() {
    var args = [String](CommandLine.arguments.dropFirst())
    // See if the arguments are intended to be interpreted as commandline args.
    if args.first != TulsiCommandlineParser.ParamCommandlineArgumentSentinal {
      commandlineSentinalFound = false
      arguments = Arguments()
      return
    }
    commandlineSentinalFound = true

    args = [String](args.dropFirst())

    var parsedArguments = [String: Any]()
    func storeValueAt(_ index: Int,
                      forArgument argumentName: String,
                      append: Bool = false,
                      transform: ((AnyObject) -> AnyObject) = { return $0 }) {
      guard index < args.count else {
        print("Missing required parameter for \(argumentName) option.")
        exit(1)
      }
      let value = transform(args[index] as AnyObject)
      if append {
        if var existingArgs: [AnyObject] = parsedArguments[argumentName] as? [AnyObject] {
          existingArgs.append(value)
          parsedArguments[argumentName] = existingArgs as AnyObject?
        } else {
          parsedArguments[argumentName] = [value]
        }
      } else {
        parsedArguments[argumentName] = value
      }
    }

    var i = 0
    while i < args.count {
      let arg = args[i]
      i += 1
      switch arg {

        // Commmon:

        case TulsiCommandlineParser.ParamHelpShort:
          fallthrough
        case TulsiCommandlineParser.ParamHelpLong:
          TulsiCommandlineParser.printUsage()
          exit(1)

        case TulsiCommandlineParser.ParamVerboseShort:
          fallthrough
        case TulsiCommandlineParser.ParamVerboseLong:
          parsedArguments[TulsiCommandlineParser.ParamVerboseLong] = true as AnyObject?
        case TulsiCommandlineParser.ParamQuietShort:
          fallthrough
        case TulsiCommandlineParser.ParamQuietLong:
          parsedArguments[TulsiCommandlineParser.ParamQuietLong] = true as AnyObject?

        case TulsiCommandlineParser.ParamBazel:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamBazel)
          i += 1

        case TulsiCommandlineParser.ParamBuildOptions:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamBuildOptions)
          i += 1

        case TulsiCommandlineParser.ParamOutputFolderShort:
          fallthrough
        case TulsiCommandlineParser.ParamOutputFolderLong:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamOutputFolderLong)
          i += 1

        case TulsiCommandlineParser.ParamWorkspaceRootShort:
          fallthrough
        case TulsiCommandlineParser.ParamWorkspaceRootLong:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamWorkspaceRootLong)
          i += 1

        case TulsiCommandlineParser.ParamAdditionalPathFilters:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamAdditionalPathFilters) { value -> AnyObject in
            guard let valueString = value as? String else { return Set<String>() as AnyObject }

            let pathFilters = valueString.components(separatedBy: " ").map() { path -> String in
              if path.hasPrefix("//") {
                let index = path.index(path.startIndex, offsetBy: 2)
                return String(path[index...])
              }
              return path
            }
            return Set(pathFilters) as AnyObject
          }
          i += 1

        // Xcode project generation:

        case TulsiCommandlineParser.ParamGeneratorConfigShort:
          fallthrough
        case TulsiCommandlineParser.ParamGeneratorConfigLong:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamGeneratorConfigLong)
          i += 1

        case TulsiCommandlineParser.ParamNoOpenXcode:
          parsedArguments[TulsiCommandlineParser.ParamNoOpenXcode] = true as AnyObject?

        // Tulsiproj creation:

        case TulsiCommandlineParser.ParamCreateTulsiProj:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamCreateTulsiProj)
          i += 1

        case TulsiCommandlineParser.ParamBuildStartupOptions:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamBuildStartupOptions)
          i += 1

        case TulsiCommandlineParser.ParamBuildTargetShort:
          fallthrough
        case TulsiCommandlineParser.ParamBuildTargetLong:
          storeValueAt(i, forArgument: TulsiCommandlineParser.ParamBuildTargetLong, append: true)
          i += 1

      case TulsiCommandlineParser.ParamLogToFile:
        parsedArguments[TulsiCommandlineParser.ParamLogToFile] = true as AnyObject?

        default:
          print("Ignoring unknown option \"\(arg)\"")
      }
    }

    arguments = Arguments(dict: parsedArguments)
  }

  // MARK: - Private methods

  private static func printUsage() {
    let usage = [
        "Usage: \(CommandLine.arguments[0]) -- <mode_option> [options]",
        "",
        "Tulsi will operate in one of two modes based on the mode_option:",
        "  - \(ParamGeneratorConfigLong): generates an Xcode project.",
        "  - \(ParamCreateTulsiProj): generates a basic Tulsi project.",
        "",
        "Xcode project generation specific options:",
        "  \(ParamGeneratorConfigLong) <config>:",
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
        "  \(ParamBuildOptions) <options>: Extra Bazel build options to add.",
        "",
        "  \(ParamCreateTulsiProj) <tulsiproj_bundle_name>:",
        "    Generates a Tulsi project suitable for building the given Bazel target.",
        "    \(ParamBazel) and \(ParamOutputFolderLong) MUST be provided with this option.",
        "  \(ParamBuildTargetLong) <target_label>: The Bazel build label for a target that should be built by this project.",
        "  \(ParamBuildStartupOptions) <options>: Uses the given options as Bazel build startup options.",
        "  \(ParamBuildOptions) <options>: Uses the given options as Bazel build options.",
        "",
        "Common options:",
        "  \(ParamHelpLong): Show this help message.",
        "  \(ParamBazel) <path>: Path to the Bazel binary.",
        "  \(ParamWorkspaceRootLong) <path>: Path to the folder containing the Bazel WORKSPACE file.",
        "  \(ParamOutputFolderLong) <path>: Sets the folder into which the generated content should be saved.",
        "  \(ParamVerboseLong): Show additional debug info, can be helpful for debugging bazel invocations.",
        "    Overrides \(ParamQuietLong) if both are present. ",
        "  \(ParamQuietLong): Hide all debug info messages (warning: may also hide some error details).",
        "  \(ParamAdditionalPathFilters) \"<paths>\": Space-delimited source filters to be included in the generated project.",
        "  \(ParamLogToFile): Enable logging to ~/Library/Application Support/Tulsi/*.txt.",
        "       Ignores specified verbosity; everything will be logged to file.",
        ""
    ]
    print(usage.joined(separator: "\n") + "\n")
  }
}
