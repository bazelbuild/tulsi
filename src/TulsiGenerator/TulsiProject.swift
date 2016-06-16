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
  public enum Error: ErrorType {
    /// Serialization failed with the given debug info.
    case SerializationFailed(String)
    /// The give input file does not exist or cannot be read.
    case BadInputFilePath
    /// Deserialization failed with the given debug info.
    case DeserializationFailed(String)
    /// A per-user config was found but could not be read.
    case FailedToReadAdditionalOptionsData(String)
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
  public var projectBundleURL: NSURL

  /// The directory containing this project's workspace file.
  public let workspaceRootURL: NSURL

  /// The Bazel packages contained in this project.
  public var bazelPackages: [String]

  public let options: TulsiOptionSet
  public let hasExplicitOptions: Bool

  // MARK: - Per-user project values.

  /// The Bazel binary to be used for this project.
  public var bazelURL: NSURL? {
    didSet {
      options[.BazelPath].projectValue = bazelURL?.path
    }
  }

  /// Filename to be used when writing out user-specific values.
  public static var perUserFilename: String {
    return "\(NSUserName()).tulsiconf-user"
  }

  public static func load(projectBundleURL: NSURL) throws -> TulsiProject {
    let fileManager = NSFileManager.defaultManager()
    let projectFileURL = projectBundleURL.URLByAppendingPathComponent(TulsiProject.ProjectFilename)
    guard let path = projectFileURL.path, data = fileManager.contentsAtPath(path) else {
      throw Error.BadInputFilePath
    }
    return try TulsiProject(data: data, projectBundleURL: projectBundleURL)
  }

  public init(projectName: String,
              projectBundleURL: NSURL,
              workspaceRootURL: NSURL,
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
      self.bazelURL = NSURL(fileURLWithPath: bazelPath)
    } else {
      self.bazelURL = BazelLocator.findBazelForWorkspaceRoot(workspaceRootURL)
      self.options[.BazelPath].projectValue = self.bazelURL?.path
    }
    self.options[.WorkspaceRootPath].projectValue = workspaceRootURL.path
  }

  public convenience init(data: NSData,
                          projectBundleURL: NSURL,
                          additionalOptionData: NSData? = nil) throws {
    do {
      guard let dict = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) as? [String: AnyObject] else {
        throw Error.DeserializationFailed("File is not of dictionary type")
      }

      let projectName = dict[TulsiProject.ProjectNameKey] as? String ?? "Unnamed Tulsi Project"
      guard let relativeWorkspacePath = dict[TulsiProject.WorkspaceRootKey] as? String else {
        throw Error.DeserializationFailed("Missing required value for \(TulsiProject.WorkspaceRootKey)")
      }
      if (relativeWorkspacePath as NSString).absolutePath {
        throw Error.DeserializationFailed("\(TulsiProject.WorkspaceRootKey) may not be an absolute path")
      }

      var workspaceRootURL = projectBundleURL.URLByAppendingPathComponent(relativeWorkspacePath,
                                                                          isDirectory: true)
      // Get rid of any ..'s and //'s if possible.
      if let standardizedWorkspaceRootURL = workspaceRootURL.URLByStandardizingPath {
        workspaceRootURL = standardizedWorkspaceRootURL
      }
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
    } catch let e as Error {
      throw e
    } catch let e as NSError {
      throw Error.DeserializationFailed(e.localizedDescription)
    } catch {
      assertionFailure("Unexpected exception")
      throw Error.SerializationFailed("Unexpected exception")
    }
  }

  public func workspaceRelativePathForURL(absoluteURL: NSURL) -> String? {
    return workspaceRootURL.relativePathTo(absoluteURL)
  }

  public func save() throws -> NSData {
    var configDefaults = [String: AnyObject]()
    // Save the default project options.
    options.saveShareableOptionsIntoDictionary(&configDefaults)

    let dict: [String: AnyObject] = [
        TulsiProject.ProjectNameKey: projectName,
        TulsiProject.WorkspaceRootKey: projectBundleURL.relativePathTo(workspaceRootURL)!,
        TulsiProject.PackagesKey: bazelPackages,
        TulsiProject.ConfigDefaultsKey: configDefaults,
    ]

    do {
      return try NSJSONSerialization.dataWithJSONObject(dict, options: .PrettyPrinted)
    } catch let e as NSError {
      throw Error.SerializationFailed(e.localizedDescription)
    } catch {
      assertionFailure("Unexpected exception")
      throw Error.SerializationFailed("Unexpected exception")
    }
  }

  public func savePerUserSettings() throws -> NSData? {
    var dict = [String: AnyObject]()
    options.savePerUserOptionsIntoDictionary(&dict)
    if dict.isEmpty { return nil }
    do {
      return try NSJSONSerialization.dataWithJSONObject(dict, options: .PrettyPrinted)
    } catch let e as NSError {
      throw Error.SerializationFailed(e.localizedDescription)
    } catch {
      throw Error.SerializationFailed("Unexpected exception")
    }
  }

  // MARK: - Private methods

  private static func updateOptionsDict(inout optionsDict: TulsiOptionSet.PersistenceType,
                                        withAdditionalOptionData data: NSData) throws {
    do {
      guard let jsonDict = try NSJSONSerialization.JSONObjectWithData(data,
                                                                      options: NSJSONReadingOptions()) as? [String: AnyObject] else {
        throw Error.FailedToReadAdditionalOptionsData("File contents are invalid")
      }
      guard let newOptions = TulsiOptionSet.getOptionsFromContainerDictionary(jsonDict) else {
        return
      }
      for (key, value) in newOptions {
        optionsDict[key] = value
      }
    } catch let e as Error {
      throw e
    } catch let e as NSError {
      throw Error.FailedToReadAdditionalOptionsData(e.localizedDescription)
    } catch {
      assertionFailure("Unexpected exception")
      throw Error.FailedToReadAdditionalOptionsData("Unexpected exception")
    }
  }
}
