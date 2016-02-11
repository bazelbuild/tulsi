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
    /// Serialization failed with the given debug info.
    case SerializationFailed(info: String)
    /// The give input file does not exist or cannot be read.
    case BadInputFilePath
    /// Deserialization failed with the given debug info.
    case DeserializationFailed(info: String)
  }

  /// The file extension used when saving generator configs.
  public static let FileExtension = "tulsigen"

  /// The name of the Xcode project.
  public let projectName: String

  public var filename: String {
    return TulsiGeneratorConfig.filenameForProjectName(projectName)
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
  /// Path to the bazelRC binary.
  public let bazelRCURL: NSURL!

  static let ProjectNameKey = "projectName"
  static let BuildTargetsKey = "buildTargets"
  static let SourceTargetsKey = "sourceTargets"
  static let AdditionalFilePathsKey = "additionalFilePaths"

  /// The project name sanitized for use as a filesystem path.
  public static func filenameForProjectName(projectName: String) -> String {
    let name = projectName.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.alphanumericCharacterSet())!
    return "\(name).\(TulsiGeneratorConfig.FileExtension)"
  }

  public static func load(inputFile: NSURL) throws -> TulsiGeneratorConfig {
    let fileManager = NSFileManager.defaultManager()
    guard let path = inputFile.path, data = fileManager.contentsAtPath(path) else {
      throw Error.BadInputFilePath
    }

    return try TulsiGeneratorConfig(data: data)
  }

  public init(projectName: String,
       buildTargetLabels: [String],
       sourceTargetLabels: [String],
       additionalFilePaths: [String]?,
       options: TulsiOptionSet,
       bazelURL: NSURL,
       bazelRCURL: NSURL? = nil) {
    self.projectName = projectName
    self.buildTargetLabels = buildTargetLabels
    self.sourceTargetLabels = sourceTargetLabels
    self.additionalFilePaths = additionalFilePaths
    self.options = options
    self.bazelURL = bazelURL
    self.bazelRCURL = bazelRCURL
  }

  public convenience init(projectName: String,
       buildTargets: [RuleEntry],
       sourceTargets: [RuleEntry],
       additionalFilePaths: [String]?,
       options: TulsiOptionSet,
       bazelURL: NSURL,
       bazelRCURL: NSURL? = nil) {
    func labelsFromRules(rules: [RuleEntry]) -> [String] {
      return rules.map() { $0.label.value }
    }

    self.init(projectName: projectName,
              buildTargetLabels: labelsFromRules(buildTargets),
              sourceTargetLabels: labelsFromRules(sourceTargets),
              additionalFilePaths: additionalFilePaths,
              options: options,
              bazelURL: bazelURL,
              bazelRCURL: bazelRCURL)
    self.buildTargets = buildTargets
    self.sourceTargets = sourceTargets
  }

  convenience init(data: NSData) throws {
    do {
      let dict = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions())

      let projectName = dict[TulsiGeneratorConfig.ProjectNameKey] as? String ?? "Unnamed Tulsi Project"
      let buildTargetLabels = dict[TulsiGeneratorConfig.BuildTargetsKey] as? [String] ?? []
      let sourceTargetLabels = dict[TulsiGeneratorConfig.SourceTargetsKey] as? [String] ?? []
      let additionalFilePaths = dict[TulsiGeneratorConfig.AdditionalFilePathsKey] as? [String]

      // TODO(abaire): Load options.
      let options = TulsiOptionSet()

      self.init(projectName: projectName,
                buildTargetLabels: buildTargetLabels,
                sourceTargetLabels: sourceTargetLabels,
                additionalFilePaths: additionalFilePaths,
                options: options,
                bazelURL: NSURL(fileURLWithPath: "bazel"),  // TODO(abaire): Wire up to options.
                bazelRCURL: nil)  // TODO(abaire): Wire up to options.
    } catch let e as Error {
      throw e
    } catch let e as NSError {
      throw Error.DeserializationFailed(info: e.localizedDescription)
    } catch {
      assertionFailure("Unexpected exception")
      throw Error.SerializationFailed(info: "Unexpected exception")
    }
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

    // TODO(abaire): Wire up serialization of options.
    //options.serializeToDictionary(dict)

    do {
      return try NSJSONSerialization.dataWithJSONObject(dict, options: .PrettyPrinted)
    } catch let e as NSError {
      throw Error.SerializationFailed(info: e.localizedDescription)
    }
  }
}
