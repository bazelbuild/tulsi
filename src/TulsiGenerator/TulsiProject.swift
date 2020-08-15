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


/// Models a Tulsi project, containing general data about the build targets available in order to
/// build Tulsi generator configs.
public final class TulsiProject {
  public enum ProjectError: Error {
    /// Serialization failed with the given debug info.
    case serializationFailed(String)
    /// The give input file does not exist or cannot be read.
    case badInputFilePath
    /// Deserialization failed with the given debug info.
    case deserializationFailed(String)
    /// A per-user config was found but could not be read.
    case failedToReadAdditionalOptionsData(String)
  }

  /// The filename into which a TulsiProject instance is saved.
  public static let ProjectFilename = "project.tulsiconf"

  /// Subdirectory within a TulsiProject bundle containing generated configs that have been
  /// identified as shareable by the user.
  public static let SharedConfigsPath = "sharedConfigs"

  /// Subdirectory within a TulsiProject bundle containing generated configs that are specific to
  /// the current user.
  public static let UserConfigsPath = "userConfigs"

  static let ProjectNameKey = "projectName"
  static let WorkspaceRootKey = "workspaceRoot"
  static let PackagesKey = "packages"
  static let ConfigDefaultsKey = "configDefaults"

  // MARK: - Shared project values.

  /// The name of this project.
  public let projectName: String

  /// The path to this project's bundle directory on the filesystem.
  public var projectBundleURL: URL

  /// The directory containing this project's workspace file.
  public let workspaceRootURL: URL

  /// The Bazel packages contained in this project.
  public var bazelPackages: [String]

  public let options: TulsiOptionSet
  public let hasExplicitOptions: Bool

  // MARK: - Per-user project values.

  /// The Bazel binary to be used for this project.
  public var bazelURL: URL? {
    didSet {
      options[.BazelPath].projectValue = bazelURL?.path
    }
  }

  /// Filename to be used when writing out user-specific values.
  public static var perUserFilename: String {
    return "\(NSUserName()).tulsiconf-user"
  }

  public static func load(_ projectBundleURL: URL) throws -> TulsiProject {
    let fileManager = FileManager.default
    let projectFileURL = projectBundleURL.appendingPathComponent(TulsiProject.ProjectFilename)
    guard let data = fileManager.contents(atPath: projectFileURL.path) else {
      throw ProjectError.badInputFilePath
    }
    return try TulsiProject(data: data, projectBundleURL: projectBundleURL)
  }

  public init(projectName: String,
              projectBundleURL: URL,
              workspaceRootURL: URL,
              bazelPackages: [String] = [],
              options: TulsiOptionSet? = nil) {
    self.projectName = projectName
    self.projectBundleURL = projectBundleURL
    self.workspaceRootURL = workspaceRootURL
    self.bazelPackages = bazelPackages

    if let options = options {
      self.options = options
      hasExplicitOptions = true
    } else {
      self.options = TulsiOptionSet()
      hasExplicitOptions = false
    }
    if let bazelPath = self.options[.BazelPath].projectValue {
      self.bazelURL = URL(fileURLWithPath: bazelPath)
    } else {
      self.bazelURL = BazelLocator.bazelURL
      self.options[.BazelPath].projectValue = self.bazelURL?.path
    }
    self.options[.WorkspaceRootPath].projectValue = workspaceRootURL.path
  }

  public convenience init(data: Data,
                          projectBundleURL: URL,
                          additionalOptionData: Data? = nil) throws {
    do {
      guard let dict = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions()) as? [String: AnyObject] else {
        throw ProjectError.deserializationFailed("File is not of dictionary type")
      }

      let projectName = dict[TulsiProject.ProjectNameKey] as? String ?? "Unnamed Tulsi Project"
      guard let relativeWorkspacePath = dict[TulsiProject.WorkspaceRootKey] as? String else {
        throw ProjectError.deserializationFailed("Missing required value for \(TulsiProject.WorkspaceRootKey)")
      }
      if (relativeWorkspacePath as NSString).isAbsolutePath {
        throw ProjectError.deserializationFailed("\(TulsiProject.WorkspaceRootKey) may not be an absolute path")
      }

      var workspaceRootURL = projectBundleURL.appendingPathComponent(relativeWorkspacePath,
                                                                     isDirectory: true)
      // Get rid of any ..'s and //'s if possible.
      workspaceRootURL = workspaceRootURL.standardizedFileURL

      let bazelPackages = dict[TulsiProject.PackagesKey] as? [String] ?? []

      let options: TulsiOptionSet?
      if let configDefaults = dict[TulsiProject.ConfigDefaultsKey] as? [String: AnyObject] {
        var optionsDict = TulsiOptionSet.getOptionsFromContainerDictionary(configDefaults) ?? [:]
        if let additionalOptionData = additionalOptionData {
          try TulsiProject.updateOptionsDict(&optionsDict,
                                             withAdditionalOptionData: additionalOptionData)
        }
        options = TulsiOptionSet(fromDictionary: optionsDict)
      } else {
        options = nil
      }

      self.init(projectName: projectName,
                projectBundleURL: projectBundleURL,
                workspaceRootURL: workspaceRootURL,
                bazelPackages: bazelPackages,
                options: options)
    } catch let e as ProjectError {
      throw e
    } catch let e as NSError {
      throw ProjectError.deserializationFailed(e.localizedDescription)
    } catch {
      assertionFailure("Unexpected exception")
      throw ProjectError.serializationFailed("Unexpected exception")
    }
  }

  public func workspaceRelativePathForURL(_ absoluteURL: URL) -> String? {
    return workspaceRootURL.relativePathTo(absoluteURL)
  }

  public func save() throws -> NSData {
    var configDefaults = [String: Any]()
    // Save the default project options.
    options.saveShareableOptionsIntoDictionary(&configDefaults)

    let dict: [String: Any] = [
        TulsiProject.ProjectNameKey: projectName,
        TulsiProject.WorkspaceRootKey: projectBundleURL.relativePathTo(workspaceRootURL)!,
        TulsiProject.PackagesKey: bazelPackages.sorted(),
        TulsiProject.ConfigDefaultsKey: configDefaults,
    ]

    do {
      return try JSONSerialization.tulsi_newlineTerminatedUnescapedData(jsonObject: dict,
                                                                        options: [.prettyPrinted, .sortedKeys])
    } catch let e as NSError {
      throw ProjectError.serializationFailed(e.localizedDescription)
    } catch {
      assertionFailure("Unexpected exception")
      throw ProjectError.serializationFailed("Unexpected exception")
    }
  }

  public func savePerUserSettings() throws -> NSData? {
    var dict = [String: Any]()
    options.savePerUserOptionsIntoDictionary(&dict)
    if dict.isEmpty { return nil }
    do {
      return try JSONSerialization.tulsi_newlineTerminatedUnescapedData(jsonObject: dict,
                                                                        options: [.prettyPrinted, .sortedKeys])
    } catch let e as NSError {
      throw ProjectError.serializationFailed(e.localizedDescription)
    } catch {
      throw ProjectError.serializationFailed("Unexpected exception")
    }
  }

  // MARK: - Private methods

  private static func updateOptionsDict(_ optionsDict: inout TulsiOptionSet.PersistenceType,
                                        withAdditionalOptionData data: Data) throws {
    do {
      guard let jsonDict = try JSONSerialization.jsonObject(with: data,
                                                                      options: JSONSerialization.ReadingOptions()) as? [String: AnyObject] else {
        throw ProjectError.failedToReadAdditionalOptionsData("File contents are invalid")
      }
      guard let newOptions = TulsiOptionSet.getOptionsFromContainerDictionary(jsonDict) else {
        return
      }
      for (key, value) in newOptions {
        optionsDict[key] = value
      }
    } catch let e as ProjectError {
      throw e
    } catch let e as NSError {
      throw ProjectError.failedToReadAdditionalOptionsData(e.localizedDescription)
    } catch {
      assertionFailure("Unexpected exception")
      throw ProjectError.failedToReadAdditionalOptionsData("Unexpected exception")
    }
  }
}
