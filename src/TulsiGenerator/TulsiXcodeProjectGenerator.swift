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

  public enum GeneratorError: Error {
    /// General Xcode project creation failure with associated debug info.
    case serializationFailed(String)
    /// The project config included an entry with the associated unsupported type.
    case unsupportedTargetType(String)
  }

  public static let ScriptDirectorySubpath = XcodeProjectGenerator.ScriptDirectorySubpath
  public static let ConfigDirectorySubpath = XcodeProjectGenerator.ConfigDirectorySubpath

  let xcodeProjectGenerator: XcodeProjectGenerator

  public convenience init (workspaceRootURL: URL,
                           config: TulsiGeneratorConfig,
                           tulsiVersion: String) {
    self.init(workspaceRootURL: workspaceRootURL,
              config: config,
              extractorBazelURL: config.bazelURL as URL,
              tulsiVersion: tulsiVersion)
  }

  init(workspaceRootURL: URL,
       config: TulsiGeneratorConfig,
       extractorBazelURL: URL,
       tulsiVersion: String) {
    let bundle = Bundle(for: type(of: self))
    let localizedMessageLogger = LocalizedMessageLogger(bundle: bundle)

    let resourceURLs = XcodeProjectGenerator.ResourceSourcePathURLs(
        buildScript: bundle.url(forResource: "bazel_build", withExtension: "py")!,
        cleanScript: bundle.url(forResource: "bazel_clean", withExtension: "sh")!,
        extraBuildScripts: [bundle.url(forResource: "tulsi_logging", withExtension: "py")!,
                            bundle.url(forResource: "bazel_options", withExtension: "py")!],
        postProcessor: bundle.url(forResource: "post_processor",
                                             withExtension: "",
                                             subdirectory: "Utilities")!,
        uiRunnerEntitlements: bundle.url(forResource: "XCTRunner", withExtension: "entitlements")!,
        stubInfoPlist: bundle.url(forResource: "StubInfoPlist", withExtension: "plist")!,
        stubIOSAppExInfoPlistTemplate: bundle.url(forResource: "StubIOSAppExtensionInfoPlist", withExtension: "plist")!,
        stubWatchOS2InfoPlist: bundle.url(forResource: "StubWatchOS2InfoPlist", withExtension: "plist")!,
        stubWatchOS2AppExInfoPlist: bundle.url(forResource: "StubWatchOS2AppExtensionInfoPlist", withExtension: "plist")!,
        bazelWorkspaceFile: bundle.url(forResource: "WORKSPACE", withExtension: nil)!,
        tulsiPackageFiles: bundle.urls(forResourcesWithExtension: nil, subdirectory: "tulsi")!)

    // Note: A new extractor is created on each generate in order to allow users to modify their
    // BUILD files (or add new files to glob's) and regenerate without restarting Tulsi.
    let extractor = BazelWorkspaceInfoExtractor(bazelURL: extractorBazelURL,
                                                workspaceRootURL: workspaceRootURL,
                                                localizedMessageLogger: localizedMessageLogger)

    xcodeProjectGenerator = XcodeProjectGenerator(workspaceRootURL: workspaceRootURL,
                                                  config: config,
                                                  localizedMessageLogger: localizedMessageLogger,
                                                  workspaceInfoExtractor: extractor,
                                                  resourceURLs: resourceURLs,
                                                  tulsiVersion: tulsiVersion)
  }

  /// Generates an Xcode project bundle in the given folder.
  /// NOTE: This may be a long running operation.
  public func generateXcodeProjectInFolder(_ outputFolderURL: URL) throws -> URL {
    do {
      return try xcodeProjectGenerator.generateXcodeProjectInFolder(outputFolderURL)
    } catch PBXTargetGenerator.ProjectSerializationError.unsupportedTargetType(let targetType) {
      throw GeneratorError.unsupportedTargetType(targetType)
    } catch PBXTargetGenerator.ProjectSerializationError.generalFailure(let info) {
      throw GeneratorError.serializationFailed(info)
    } catch XcodeProjectGenerator.ProjectGeneratorError.serializationFailed(let info) {
      throw GeneratorError.serializationFailed(info)
    } catch XcodeProjectGenerator.ProjectGeneratorError.labelResolutionFailed(let labels) {
      throw GeneratorError.serializationFailed("Failed to resolve labels: \(labels)")
    } catch let e as NSError {
      throw GeneratorError.serializationFailed("Unexpected exception \(e.localizedDescription)")
    } catch let e {
      throw GeneratorError.serializationFailed("Unexpected exception \(e)")
    }
  }
}
