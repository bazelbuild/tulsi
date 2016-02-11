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
    case SerializationFailed(info: String)
    /// The give input file does not exist or cannot be read.
    case BadInputFilePath
    /// Deserialization failed with the given debug info.
    case DeserializationFailed(info: String)
  }

  /// NSUserDefaults key for the default Bazel path if one is not found in the opened project's
  /// workspace.
  // TODO(abaire): Move this out of the generator.
  public static let DefaultBazelURLKey = "defaultBazelURL"

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

  // MARK: - Shared project values.

  /// The name of this project.
  public let projectName: String

  /// The path to this project's bundle directory on the filesystem.
  public var projectBundleURL: NSURL

  /// The directory containing this project's workspace file.
  public let workspaceRootURL: NSURL

  /// The Bazel packages contained in this project.
  public var bazelPackages: [String]

  // MARK: - Per-user project values.

  /// The Bazel binary to be used for this project.
  public var bazel: NSURL?

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
              bazelPackages: [String] = []) {
    self.projectName = projectName
    self.projectBundleURL = projectBundleURL
    self.workspaceRootURL = workspaceRootURL
    self.bazelPackages = bazelPackages
    bazel = TulsiProject.findBazelForWorkspaceRoot(workspaceRootURL)
  }

  public convenience init(data: NSData, projectBundleURL: NSURL) throws {
    do {
      let dict = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions())

      let projectName = dict[TulsiProject.ProjectNameKey] as? String ?? "Unnamed Tulsi Project"
      guard let relativeWorkspaceURL = dict[TulsiProject.WorkspaceRootKey] as? String else {
        throw Error.DeserializationFailed(info: "Missing required value for \(TulsiProject.WorkspaceRootKey)")
      }
      var workspaceRootURL = projectBundleURL.URLByAppendingPathComponent(relativeWorkspaceURL,
                                                                          isDirectory: true)
      // Get rid of any ..'s if possible.
      if let standardizedWorkspaceRootURL = workspaceRootURL.standardizedURL {
        workspaceRootURL = standardizedWorkspaceRootURL
      }
      let bazelPackages = dict[TulsiProject.PackagesKey] as? [String] ?? []

      self.init(projectName: projectName,
                projectBundleURL: projectBundleURL,
                workspaceRootURL: workspaceRootURL,
                bazelPackages: bazelPackages)
    } catch let e as Error {
      throw e
    } catch let e as NSError {
      throw Error.DeserializationFailed(info: e.localizedDescription)
    } catch {
      assertionFailure("Unexpected exception")
      throw Error.SerializationFailed(info: "Unexpected exception")
    }
  }

  public func workspaceRelativePathForURL(absoluteURL: NSURL) -> String? {
    return workspaceRootURL.relativePathTo(absoluteURL)
  }

  public func save() throws -> NSData {
    let dict: [String: AnyObject] = [
        TulsiProject.ProjectNameKey: projectName,
        TulsiProject.WorkspaceRootKey: projectBundleURL.relativePathTo(workspaceRootURL)!,
        TulsiProject.PackagesKey: bazelPackages
    ]

    do {
      return try NSJSONSerialization.dataWithJSONObject(dict, options: .PrettyPrinted)
    } catch let e as NSError {
      throw Error.SerializationFailed(info: e.localizedDescription)
    } catch {
      assertionFailure("Unexpected exception")
      throw Error.SerializationFailed(info: "Unexpected exception")
    }
  }

  // MARK: - Private methods

  private static func findBazelForWorkspaceRoot(workspaceRoot: NSURL?) -> NSURL? {
    // TODO(abaire): Consider removing this as it's unlikley to be a standard for all users.
    guard let bazelURL = workspaceRoot?.URLByAppendingPathComponent("tools/osx/blaze/bazel") else {
      return nil
    }

    if NSFileManager.defaultManager().fileExistsAtPath(bazelURL.path!) {
      return bazelURL
    }
    return nil
  }
}
