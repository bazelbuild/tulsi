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


/// Provides functionality to generate an Xcode project from a TulsiGeneratorConfig.
public final class TulsiXcodeProjectGenerator {

  public enum Error: ErrorType {
    /// General Xcode project creation failure with associated debug info.
    case SerializationFailed(String)
    /// The project config included an entry with the associated unsupported type.
    case UnsupportedTargetType(String)
  }

  public static let ScriptDirectorySubpath = XcodeProjectGenerator.ScriptDirectorySubpath
  public static let ConfigDirectorySubpath = XcodeProjectGenerator.ConfigDirectorySubpath

  let xcodeProjectGenerator: XcodeProjectGenerator

  public convenience init (workspaceRootURL: NSURL,
                           config: TulsiGeneratorConfig,
                           tulsiVersion: String) {
    self.init(workspaceRootURL: workspaceRootURL,
              config: config,
              extractorBazelURL: config.bazelURL,
              tulsiVersion: tulsiVersion)
  }

  init(workspaceRootURL: NSURL,
       config: TulsiGeneratorConfig,
       extractorBazelURL: NSURL,
       tulsiVersion: String) {
    let bundle = NSBundle(forClass: self.dynamicType)
    let localizedMessageLogger = LocalizedMessageLogger(bundle: bundle)
    let buildScriptURL = bundle.URLForResource("bazel_build", withExtension: "py")!
    let cleanScriptURL = bundle.URLForResource("bazel_clean", withExtension: "sh")!
    let stubInfoPlistURL = bundle.URLForResource("StubInfoPlist", withExtension: "plist")!

    // Note: A new extractor is created on each generate in order to allow users to modify their
    // BUILD files (or add new files to glob's) and regenerate without restarting Tulsi.
    let extractor = BazelWorkspaceInfoExtractor(bazelURL: extractorBazelURL,
                                                workspaceRootURL: workspaceRootURL,
                                                localizedMessageLogger: localizedMessageLogger)

    xcodeProjectGenerator = XcodeProjectGenerator(workspaceRootURL: workspaceRootURL,
                                                  config: config,
                                                  localizedMessageLogger: localizedMessageLogger,
                                                  workspaceInfoExtractor: extractor,
                                                  buildScriptURL: buildScriptURL,
                                                  cleanScriptURL: cleanScriptURL,
                                                  stubInfoPlistURL: stubInfoPlistURL,
                                                  tulsiVersion: tulsiVersion)
  }

  /// Generates an Xcode project bundle in the given folder.
  /// NOTE: This may be a long running operation.
  public func generateXcodeProjectInFolder(outputFolderURL: NSURL) throws -> NSURL {
    do {
      return try xcodeProjectGenerator.generateXcodeProjectInFolder(outputFolderURL)
    } catch PBXTargetGenerator.ProjectSerializationError.UnsupportedTargetType(let targetType) {
      throw Error.UnsupportedTargetType(targetType)
    } catch PBXTargetGenerator.ProjectSerializationError.GeneralFailure(let info) {
      throw Error.SerializationFailed(info)
    } catch XcodeProjectGenerator.Error.SerializationFailed(let info) {
      throw Error.SerializationFailed(info)
    } catch XcodeProjectGenerator.Error.LabelResolutionFailed(let labels) {
      throw Error.SerializationFailed("Failed to resolve labels: \(labels)")
    } catch let e as NSError {
      throw Error.SerializationFailed("Unexpected exception \(e.localizedDescription)")
    } catch let e {
      throw Error.SerializationFailed("Unexpected exception \(e)")
    }
  }
}
