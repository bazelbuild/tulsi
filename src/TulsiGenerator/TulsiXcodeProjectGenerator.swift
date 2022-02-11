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
    case unsupportedTargetType(String, String)
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
                            bundle.url(forResource: "bazel_options", withExtension: "py")!,
                            bundle.url(forResource: "apfs_clone_copy", withExtension: "py")!,
                            bundle.url(forResource: "bazel_build_events", withExtension: "py")!,
                            bundle.url(forResource: "bootstrap_lldbinit", withExtension: "py")!,
                            bundle.url(forResource: "symbol_cache_schema", withExtension: "py")!,
                            bundle.url(forResource: "update_symbol_cache", withExtension: "py")!,
                            bundle.url(forResource: "install_genfiles", withExtension: "py")!,
                            bundle.url(forResource: "user_build", withExtension: "py")!],
        iOSUIRunnerEntitlements: bundle.url(forResource: "iOSXCTRunner", withExtension: "entitlements")!,
        macOSUIRunnerEntitlements: bundle.url(forResource: "macOSXCTRunner", withExtension: "entitlements")!,
        stubInfoPlist: bundle.url(forResource: "StubInfoPlist", withExtension: "plist")!,
        stubIOSAppExInfoPlistTemplate: bundle.url(forResource: "StubIOSAppExtensionInfoPlist", withExtension: "plist")!,
        stubWatchOS2InfoPlist: bundle.url(forResource: "StubWatchOS2InfoPlist", withExtension: "plist")!,
        stubWatchOS2AppExInfoPlist: bundle.url(forResource: "StubWatchOS2AppExtensionInfoPlist", withExtension: "plist")!,
        stubClang: bundle.url(forResource: "clang_stub", withExtension: "sh")!,
        stubSwiftc: bundle.url(forResource: "swiftc_stub", withExtension: "py")!,
        stubLd: bundle.url(forResource: "ld_stub", withExtension: "sh")!,
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
  public func generateXcodeProjectInFolder(
    _ outputFolderURL: URL) throws -> URL {
    do {
      return try xcodeProjectGenerator.generateXcodeProjectInFolder(
        outputFolderURL)
    } catch let e {
      LogMessage.postError("Project generation failed.")
      xcodeProjectGenerator.logPendingMessages()
      switch e {
      case PBXTargetGenerator.ProjectSerializationError.unsupportedTargetType(let targetType,
                                                                              let label):
        throw GeneratorError.unsupportedTargetType(targetType, label)
      case PBXTargetGenerator.ProjectSerializationError.generalFailure(let info):
        throw GeneratorError.serializationFailed(info)
      case XcodeProjectGenerator.ProjectGeneratorError.serializationFailed(let info):
        throw GeneratorError.serializationFailed(info)
      case XcodeProjectGenerator.ProjectGeneratorError.labelAspectFailure(let info):
        throw GeneratorError.serializationFailed(info)
      case XcodeProjectGenerator.ProjectGeneratorError.labelResolutionFailed(let labels):
        throw GeneratorError.serializationFailed("Failed to resolve labels: \(labels)")
      case XcodeProjectGenerator.ProjectGeneratorError.invalidXcodeProjectPath(let path,
                                                                               let reason):
        throw GeneratorError.serializationFailed("Xcode project cannot be generated in " +
            "\(path) because it lies within \(reason).")
      case let e as NSError:
        throw GeneratorError.serializationFailed("Unexpected exception \(e.localizedDescription)")
      default:
        throw GeneratorError.serializationFailed("Unexpected exception \(e)")
      }
    }
  }
}
