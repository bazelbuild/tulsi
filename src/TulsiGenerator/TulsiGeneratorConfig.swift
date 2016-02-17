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

import Foundation


/// Models a configuration which can be used to generate an Xcode project directly.
public class TulsiGeneratorConfig {

  public enum Error: ErrorType {
    /// The give input file does not exist or cannot be read.
    case BadInputFilePath
    /// A per-user config was found but could not be read.
    case FailedToReadAdditionalOptionsData(String)
    /// Deserialization failed with the given debug info.
    case DeserializationFailed(String)
    /// Serialization failed with the given debug info.
    case SerializationFailed(String)
  }

  /// The file extension used when saving generator configs.
  public static let FileExtension = "tulsigen"

  /// The name of the Xcode project.
  public let projectName: String

  public var filename: String {
    return TulsiGeneratorConfig.filenameForProjectName(projectName)
  }

  /// Filename to be used when writing out user-specific values.
  public static var perUserFilename: String {
    return "\(NSUserName()).tulsigen-user"
  }

  /// The Bazel targets to generate Xcode build targets for.
  public let buildTargetLabels: [String]
  /// The resolved build target labels.
  var buildTargets: [RuleEntry]? = nil

  /// The Bazel targets to generate Xcode indexer targets for.
  public let sourceTargetLabels: [String]
  var sourceTargets: [RuleEntry]? = nil

  /// Additional file paths to add to the Xcode project (e.g., BUILD file paths).
  public let additionalFilePaths: [String]?
  /// The options for this config.
  public let options: TulsiOptionSet

  /// Path to the Bazel binary.
  public let bazelURL: NSURL

  static let ProjectNameKey = "projectName"
  static let BuildTargetsKey = "buildTargets"
  static let SourceTargetsKey = "sourceTargets"
  static let AdditionalFilePathsKey = "additionalFilePaths"

  /// The project name sanitized for use as a filesystem path.
  public static func filenameForProjectName(projectName: String) -> String {
    let name = projectName.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.alphanumericCharacterSet())!
    return "\(name).\(TulsiGeneratorConfig.FileExtension)"
  }

  public static func load(inputFile: NSURL, bazelURL: NSURL? = nil) throws -> TulsiGeneratorConfig {
    let fileManager = NSFileManager.defaultManager()
    guard let path = inputFile.path, data = fileManager.contentsAtPath(path) else {
      throw Error.BadInputFilePath
    }

    let additionalOptionData: NSData?
    let optionsFolderURL = inputFile.URLByDeletingLastPathComponent!
    let additionalOptionsFileURL = optionsFolderURL.URLByAppendingPathComponent(TulsiGeneratorConfig.perUserFilename)
    if let perUserPath = additionalOptionsFileURL.path where fileManager.isReadableFileAtPath(perUserPath) {
      additionalOptionData = fileManager.contentsAtPath(perUserPath)
      if additionalOptionData == nil {
        throw Error.FailedToReadAdditionalOptionsData("Could not read file at path \(perUserPath)")
      }
    } else {
      additionalOptionData = nil
    }

    return try TulsiGeneratorConfig(data: data,
                                    additionalOptionData: additionalOptionData,
                                    bazelURL: bazelURL)
  }

  public init(projectName: String,
       buildTargetLabels: [String],
       sourceTargetLabels: [String],
       additionalFilePaths: [String]?,
       options: TulsiOptionSet,
       bazelURL: NSURL) {
    self.projectName = projectName
    self.buildTargetLabels = buildTargetLabels
    self.sourceTargetLabels = sourceTargetLabels
    self.additionalFilePaths = additionalFilePaths
    self.options = options
    self.bazelURL = bazelURL
  }

  public convenience init(projectName: String,
       buildTargets: [RuleEntry],
       sourceTargets: [RuleEntry],
       additionalFilePaths: [String]?,
       options: TulsiOptionSet,
       bazelURL: NSURL) {
    func labelsFromRules(rules: [RuleEntry]) -> [String] {
      return rules.map() { $0.label.value }
    }

    self.init(projectName: projectName,
              buildTargetLabels: labelsFromRules(buildTargets),
              sourceTargetLabels: labelsFromRules(sourceTargets),
              additionalFilePaths: additionalFilePaths,
              options: options,
              bazelURL: bazelURL)
    self.buildTargets = buildTargets
    self.sourceTargets = sourceTargets
  }

  convenience init(data: NSData,
                   additionalOptionData: NSData? = nil,
                   bazelURL: NSURL? = nil) throws {
    func extractJSONDict(data: NSData, errorBuilder: (String) -> Error) throws -> [String: AnyObject] {
      do {
        guard let jsonDict = try NSJSONSerialization.JSONObjectWithData(data,
                                                                        options: NSJSONReadingOptions()) as? [String: AnyObject] else {
          throw errorBuilder("Config file contents are invalid")
        }
        return jsonDict
      } catch let e as Error {
        throw e
      } catch let e as NSError {
        throw errorBuilder(e.localizedDescription)
      } catch {
        assertionFailure("Unexpected exception")
        throw errorBuilder("Unexpected exception")
      }
    }

    let dict = try extractJSONDict(data) { Error.DeserializationFailed($0)}

    let projectName = dict[TulsiGeneratorConfig.ProjectNameKey] as? String ?? "Unnamed Tulsi Project"
    let buildTargetLabels = dict[TulsiGeneratorConfig.BuildTargetsKey] as? [String] ?? []
    let sourceTargetLabels = dict[TulsiGeneratorConfig.SourceTargetsKey] as? [String] ?? []
    let additionalFilePaths = dict[TulsiGeneratorConfig.AdditionalFilePathsKey] as? [String]

    var optionsDict = dict[TulsiOptionSet.PersistenceKey] as? [String: AnyObject] ?? [:]
    if let additionalOptionData = additionalOptionData {
      let additionalOptions = try extractJSONDict(additionalOptionData) {
        Error.FailedToReadAdditionalOptionsData($0)
      }
      for (key, value) in additionalOptions {
        optionsDict[key] = value
      }
    }
    let options = TulsiOptionSet(fromDictionary: optionsDict)

    let resolvedBazelURL: NSURL
    if let bazelURL = bazelURL {
      resolvedBazelURL = bazelURL
    } else if let savedBazelPath = options[.BazelPath].commonValue {
      resolvedBazelURL = NSURL(fileURLWithPath: savedBazelPath)
    } else {
      // TODO(abaire): Fall back to searching for the binary.
      resolvedBazelURL = NSURL()
    }

    self.init(projectName: projectName,
              buildTargetLabels: buildTargetLabels,
              sourceTargetLabels: sourceTargetLabels,
              additionalFilePaths: additionalFilePaths,
              options: options,
              bazelURL: resolvedBazelURL)
  }

  public func save() throws -> NSData {
    var dict: [String: AnyObject] = [
        TulsiGeneratorConfig.ProjectNameKey: projectName,
        TulsiGeneratorConfig.BuildTargetsKey: buildTargetLabels,
        TulsiGeneratorConfig.SourceTargetsKey: sourceTargetLabels,
    ]
    if let additionalFilePaths = additionalFilePaths {
      dict[TulsiGeneratorConfig.AdditionalFilePathsKey] = additionalFilePaths
    }
    options.saveToShareableDictionary(&dict)

    do {
      return try NSJSONSerialization.dataWithJSONObject(dict, options: .PrettyPrinted)
    } catch let e as NSError {
      throw Error.SerializationFailed(e.localizedDescription)
    } catch {
      throw Error.SerializationFailed("Unexpected exception")
    }
  }

  public func savePerUserSettings() throws -> NSData? {
    var dict = [String: AnyObject]()
    options.saveToPerUserDictionary(&dict)
    if dict.isEmpty { return nil }
    do {
      return try NSJSONSerialization.dataWithJSONObject(dict, options: .PrettyPrinted)
    } catch let e as NSError {
      throw Error.SerializationFailed(e.localizedDescription)
    } catch {
      throw Error.SerializationFailed("Unexpected exception")
    }
  }
}
