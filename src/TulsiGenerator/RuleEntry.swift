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

/// Models the label and type of a single supported Bazel target.
/// See http://bazel.build/docs/build-ref.html#targets.
public class RuleInfo: Equatable, Hashable, CustomDebugStringConvertible {
  public let label: BuildLabel
  public let type: String
  /// Set of BuildLabels referencing targets that are required by this RuleInfo. For example, test
  /// hosts for XCTest targets.
  public let linkedTargetLabels: Set<BuildLabel>

  public var hashValue: Int {
    return label.hashValue ^ type.hashValue
  }

  public var debugDescription: String {
    return "\(type(of: self))(\(label) \(type))"
  }

  init(label: BuildLabel, type: String, linkedTargetLabels: Set<BuildLabel>) {
    self.label = label
    self.type = type
    self.linkedTargetLabels = linkedTargetLabels
  }
}


/// Encapsulates data about a file that may be a Bazel input or output.
public class BazelFileInfo: Equatable, Hashable, CustomDebugStringConvertible {
  public enum TargetType: Int {
    case sourceFile
    case generatedFile
  }

  /// The path to this file relative to rootPath.
  public let subPath: String

  /// The root of this file's path (typically used to indicate the path to a generated file's root).
  public let rootPath: String

  /// The type of this file.
  public let targetType: TargetType

  /// Whether or not this file object is a directory.
  public let isDirectory: Bool

  public lazy var fullPath: String = { [unowned self] in
    return NSString.path(withComponents: [self.rootPath, self.subPath])
  }()

  public lazy var uti: String? = { [unowned self] in
    return self.subPath.pbPathUTI
  }()

  public lazy var hashValue: Int = { [unowned self] in
    return self.subPath.hashValue &+
        self.rootPath.hashValue &+
        self.targetType.hashValue &+
        self.isDirectory.hashValue
  }()

  init?(info: AnyObject?) {
    guard let info = info as? [String: AnyObject] else {
      return nil
    }

    guard let subPath = info["path"] as? String,
              let isSourceFile = info["src"] as? Bool else {
      assertionFailure("Aspect provided a file info dictionary but was missing required keys")
      return nil
    }

    self.subPath = subPath
    if let rootPath = info["root"] as? String {
      // Patch up
      self.rootPath = rootPath
    } else {
      self.rootPath = ""
    }
    self.targetType = isSourceFile ? .sourceFile : .generatedFile

    self.isDirectory = info["is_dir"] as? Bool ?? false
  }

  init(rootPath: String, subPath: String, isDirectory: Bool, targetType: TargetType) {
    self.rootPath = rootPath
    self.subPath = subPath
    self.isDirectory = isDirectory
    self.targetType = targetType
  }

  // MARK: - CustomDebugStringConvertible
  public lazy var debugDescription: String = { [unowned self] in
    return "{\(self.fullPath) \(self.isDirectory ? "<DIR> " : "")\(self.targetType)}"
  }()
}

public func ==(lhs: BazelFileInfo, rhs: BazelFileInfo) -> Bool {
  return lhs.targetType == rhs.targetType &&
      lhs.rootPath == rhs.rootPath &&
      lhs.subPath == rhs.subPath &&
      lhs.isDirectory == rhs.isDirectory
}


/// Models the full metadata of a single supported Bazel target.
/// See http://bazel.build/docs/build-ref.html#targets.
public final class RuleEntry: RuleInfo {
  // Include paths are represented by a string and a boolean indicating whether they should be
  // searched recursively or not.
  public typealias IncludePath = (String, Bool)

  /// Mapping of BUILD file type to Xcode Target type.
  static let BuildTypeToTargetType = [
      "apple_ui_test": PBXTarget.ProductType.UIUnitTest,
      "apple_unit_test": PBXTarget.ProductType.UnitTest,
      "cc_binary": PBXTarget.ProductType.Application,
      "cc_library": PBXTarget.ProductType.StaticLibrary,
      "ios_application": PBXTarget.ProductType.Application,
      "ios_extension": PBXTarget.ProductType.AppExtension,
      "ios_framework": PBXTarget.ProductType.Framework,
      "ios_test": PBXTarget.ProductType.UnitTest,
      "macos_application": PBXTarget.ProductType.Application,
      "macos_command_line_application": PBXTarget.ProductType.Tool,
      "macos_extension": PBXTarget.ProductType.AppExtension,
      "objc_binary": PBXTarget.ProductType.Application,
      "objc_library": PBXTarget.ProductType.StaticLibrary,
      "swift_library": PBXTarget.ProductType.StaticLibrary,
      "tvos_application": PBXTarget.ProductType.Application,
      "tvos_extension": PBXTarget.ProductType.TVAppExtension,
      "watchos_application": PBXTarget.ProductType.Watch2App,
      "watchos_extension": PBXTarget.ProductType.Watch2Extension,

      // A Tulsi-internal generic "test host", used to generate build targets that act as hosts for
      // XCTest test rules.
      "_test_host_": PBXTarget.ProductType.Application,
  ]

  /// Keys for a RuleEntry's attributes map. Definitions may be found in the Bazel Build
  /// Encyclopedia (see http://bazel.build/docs/be/overview.html).
  // Note: This set of must be kept in sync with the tulsi_aspects aspect.
  public enum Attribute: String {
    case binary
    case bridging_header
    // Contains defines that were specified by the user on the commandline or are built into
    // Bazel itself.
    case compiler_defines
    case copts
    case datamodels
    case enable_modules
    case has_swift_dependency
    case launch_storyboard
    case pch
    case swift_language_version
    case swift_toolchain
    // Contains various files that are used as part of the build process but need no special
    // handling in the generated Xcode project. For example, asset_catalog, storyboard, and xibs
    // attributes all end up as supporting_files.
    case supporting_files
    // For the apple_unit_test and apple_ui_test rules, contains a label reference to the .xctest
    // bundle packaging target.
    case test_bundle
    // For the apple_unit_test and apple_ui_test rules, contains a label reference to the
    // ios_application target to be used as the test host when running the tests.
    case test_host
    // For the ios_test rule, specifies whether the test is XCTest based or not (i.e. KIF).
    case xctest
    // For the ios_test rule, contains a label reference to the ios_application target to be used as
    // the test host when running the tests.
    case xctest_app
  }

  /// Bazel attributes for this rule (e.g., "binary": <some label> on an ios_application).
  public let attributes: [Attribute: AnyObject]

  /// Artifacts produced by Bazel when this rule is built.
  public let artifacts: [BazelFileInfo]

  /// Defines to be applied to this rule by Bazel.
  public let defines: [String]?

  /// Source files associated with this rule.
  public let sourceFiles: [BazelFileInfo]

  /// Non-ARC source files associated with this rule.
  public let nonARCSourceFiles: [BazelFileInfo]

  /// Paths to directories that will include header files.
  public let includePaths: [IncludePath]?

  /// Set of the labels that this rule depends on.
  public let dependencies: Set<String>

  /// Set of ios_application extension labels that this rule utilizes.
  public let extensions: Set<BuildLabel>

  /// .framework bundles provided by this rule.
  public let frameworkImports: [BazelFileInfo]

  /// List of implicit artifacts that are generated by this rule.
  public let secondaryArtifacts: [BazelFileInfo]

  /// The Swift language version used by this target.
  public let swiftLanguageVersion: String?

  /// The swift toolchain argument used by this target.
  // TODO(abaire): It is hoped that this may be removed when support for Swift 2.3 is dropped.
  public let swiftToolchain: String?

  /// List containing the transitive swiftmodules on which this rule depends.
  public let swiftTransitiveModules: [BazelFileInfo]

  /// List containing the transitive ObjC modulemaps on which this rule depends.
  public let objCModuleMaps: [BazelFileInfo]

  /// The deployment platform target for this target.
  public let deploymentTarget: DeploymentTarget?

  /// Set of labels that this rule depends on but does not require.
  // NOTE(abaire): This is a hack used for test_suite rules, where the possible expansions retrieved
  // via queries are filtered by the existence of the selected labels extracted via the normal
  // aspect path. Ideally the aspect would be able to directly express the relationship between the
  // test_suite and the test rules themselves, but that expansion is done prior to the application
  // of the aspect.
  public var weakDependencies = Set<BuildLabel>()

  /// Transitive set of artifacts produced by the dependencies of this RuleEntry. Note that this
  /// must be populated via the discoverIntermediateArtifacts method.
  private(set) public var intermediateArtifacts: Set<BazelFileInfo>? = nil

  /// The BUILD file that this rule was defined in.
  public let buildFilePath: String?

  // The CFBundleIdentifier associated with the target for this rule, if any.
  public let bundleID: String?

  /// The bundle name associated with the target for this rule, if any.
  public let bundleName: String?

  /// The CFBundleIdentifier of the watchOS extension target associated with this rule, if any.
  public let extensionBundleID: String?

  /// The NSExtensionPointIdentifier of the extension associated with this rule, if any.
  public let extensionType: String?

  /// Returns the set of non-versioned artifacts that are not source files.
  public var normalNonSourceArtifacts: [BazelFileInfo] {
    var artifacts = [BazelFileInfo]()
    if let description = attributes[.launch_storyboard] as? [String: AnyObject],
           let fileTarget = BazelFileInfo(info: description as AnyObject?) {
      artifacts.append(fileTarget)
    }

    if let fileTargets = parseFileDescriptionListAttribute(.supporting_files) {
      artifacts.append(contentsOf: fileTargets)
    }

    return artifacts
  }

  /// Returns the set of artifacts for which a versioned group should be created in the generated
  /// Xcode project.
  public var versionedNonSourceArtifacts: [BazelFileInfo] {
    if let fileTargets = parseFileDescriptionListAttribute(.datamodels) {
      return fileTargets
    }
    return []
  }

  /// The full set of input and output artifacts for this rule.
  public var projectArtifacts: [BazelFileInfo] {
    var artifacts = sourceFiles
    artifacts.append(contentsOf: nonARCSourceFiles)
    artifacts.append(contentsOf: frameworkImports)
    artifacts.append(contentsOf: normalNonSourceArtifacts)
    artifacts.append(contentsOf: versionedNonSourceArtifacts)
    return artifacts
  }

  private(set) lazy var pbxTargetType: PBXTarget.ProductType? = { [unowned self] in
    if self.type == "ios_test",
       let xctestOpt = self.attributes[.xctest] as? Bool, !xctestOpt {
      return BuildTypeToTargetType["ios_application"]
    }

    return BuildTypeToTargetType[self.type]
  }()

  /// Returns the value to be used as the Xcode SDKROOT for the build target generated for this
  /// RuleEntry.
  private(set) lazy var XcodeSDKRoot: String? = { [unowned self] in
    if let platformType = self.deploymentTarget?.platform {
      return platformType.deviceSDK
    }
    return PlatformType.ios.deviceSDK
  }()

  init(label: BuildLabel,
       type: String,
       attributes: [String: AnyObject],
       artifacts: [BazelFileInfo] = [],
       sourceFiles: [BazelFileInfo] = [],
       nonARCSourceFiles: [BazelFileInfo] = [],
       dependencies: Set<String> = Set(),
       frameworkImports: [BazelFileInfo] = [],
       secondaryArtifacts: [BazelFileInfo] = [],
       weakDependencies: Set<BuildLabel>? = nil,
       extensions: Set<BuildLabel>? = nil,
       bundleID: String? = nil,
       bundleName: String? = nil,
       extensionBundleID: String? = nil,
       platformType: String? = nil,
       osDeploymentTarget: String? = nil,
       buildFilePath: String? = nil,
       defines: [String]? = nil,
       includePaths: [IncludePath]? = nil,
       swiftLanguageVersion: String? = nil,
       swiftToolchain: String? = nil,
       swiftTransitiveModules: [BazelFileInfo] = [],
       objCModuleMaps: [BazelFileInfo] = [],
       extensionType: String? = nil) {

    var checkedAttributes = [Attribute: AnyObject]()
    for (key, value) in attributes {
      guard let checkedKey = Attribute(rawValue: key) else {
        print("Tulsi rule \(label.value) - Ignoring unknown attribute key \(key)")
        assertionFailure("Unknown attribute key \(key)")
        continue
      }
      checkedAttributes[checkedKey] = value
    }
    self.attributes = checkedAttributes
    let parsedPlatformType: PlatformType?
    if let platformTypeStr = platformType {
      parsedPlatformType = PlatformType(rawValue: platformTypeStr)
    } else {
      parsedPlatformType = nil
    }

    self.artifacts = artifacts
    self.sourceFiles = sourceFiles
    self.nonARCSourceFiles = nonARCSourceFiles
    self.dependencies = dependencies
    self.frameworkImports = frameworkImports
    self.secondaryArtifacts = secondaryArtifacts
    if let weakDependencies = weakDependencies {
      self.weakDependencies = weakDependencies
    }
    if let extensions = extensions {
      self.extensions = extensions
    } else {
      self.extensions = Set()
    }
    self.bundleID = bundleID
    self.bundleName = bundleName
    self.extensionBundleID = extensionBundleID
    var deploymentTarget: DeploymentTarget? = nil
    if let platform = parsedPlatformType, let osVersion = osDeploymentTarget {
        deploymentTarget = DeploymentTarget(platform: platform, osVersion: osVersion)
    }
    self.deploymentTarget = deploymentTarget
    self.buildFilePath = buildFilePath
    self.defines = defines
    self.includePaths = includePaths
    self.swiftLanguageVersion = swiftLanguageVersion
    self.swiftToolchain = swiftToolchain
    self.swiftTransitiveModules = swiftTransitiveModules
    self.objCModuleMaps = objCModuleMaps
    self.extensionType = extensionType

    var linkedTargetLabels = Set<BuildLabel>()
    for attribute in [.xctest_app, .test_host] as [RuleEntry.Attribute] {
      if let hostLabelString = self.attributes[attribute] as? String {
        linkedTargetLabels.insert(BuildLabel(hostLabelString))
      }
    }

    super.init(label: label, type: type, linkedTargetLabels: linkedTargetLabels)
  }

  convenience init(label: String,
                   type: String,
                   attributes: [String: AnyObject],
                   artifacts: [BazelFileInfo] = [],
                   sourceFiles: [BazelFileInfo] = [],
                   nonARCSourceFiles: [BazelFileInfo] = [],
                   dependencies: Set<String> = Set(),
                   frameworkImports: [BazelFileInfo] = [],
                   secondaryArtifacts: [BazelFileInfo] = [],
                   weakDependencies: Set<BuildLabel>? = nil,
                   extensions: Set<BuildLabel>? = nil,
                   bundleID: String? = nil,
                   bundleName: String? = nil,
                   extensionBundleID: String? = nil,
                   platformType: String? = nil,
                   osDeploymentTarget: String? = nil,
                   buildFilePath: String? = nil,
                   defines: [String]? = nil,
                   includePaths: [IncludePath]? = nil,
                   swiftLanguageVersion: String? = nil,
                   swiftToolchain: String? = nil,
                   swiftTransitiveModules: [BazelFileInfo] = [],
                   objCModuleMaps: [BazelFileInfo] = [],
                   extensionType: String? = nil) {
    self.init(label: BuildLabel(label),
              type: type,
              attributes: attributes,
              artifacts: artifacts,
              sourceFiles: sourceFiles,
              nonARCSourceFiles: nonARCSourceFiles,
              dependencies: dependencies,
              frameworkImports: frameworkImports,
              secondaryArtifacts: secondaryArtifacts,
              weakDependencies: weakDependencies,
              extensions: extensions,
              bundleID: bundleID,
              bundleName: bundleName,
              extensionBundleID: extensionBundleID,
              platformType: platformType,
              osDeploymentTarget: osDeploymentTarget,
              buildFilePath: buildFilePath,
              defines: defines,
              includePaths: includePaths,
              swiftLanguageVersion: swiftLanguageVersion,
              swiftToolchain: swiftToolchain,
              swiftTransitiveModules: swiftTransitiveModules,
              objCModuleMaps: objCModuleMaps,
              extensionType: extensionType)
  }

  public func discoverIntermediateArtifacts(_ ruleEntryMap: [BuildLabel: RuleEntry]) -> Set<BazelFileInfo> {
    if intermediateArtifacts != nil { return intermediateArtifacts! }

    var collectedArtifacts = Set<BazelFileInfo>()
    for dep in dependencies {
      guard let dependentEntry = ruleEntryMap[BuildLabel(dep)] else {
        // TODO(abaire): Consider making this a standard Tulsi warning.
        // In theory it shouldn't happen and the unknown dep should be tracked elsewhere.
        print("Tulsi rule '\(label.value)' - Ignoring unknown dependency '\(dep)'")
        continue
      }

      collectedArtifacts.formUnion(dependentEntry.artifacts)
      collectedArtifacts.formUnion(dependentEntry.discoverIntermediateArtifacts(ruleEntryMap))
    }

    intermediateArtifacts = collectedArtifacts
    return intermediateArtifacts!
  }

  // MARK: Private methods

  private func parseFileDescriptionListAttribute(_ attribute: RuleEntry.Attribute) -> [BazelFileInfo]? {
    guard let descriptions = attributes[attribute] as? [[String: AnyObject]] else {
      return nil
    }

    var fileTargets = [BazelFileInfo]()
    for description in descriptions {
      guard let target = BazelFileInfo(info: description as AnyObject?) else {
        assertionFailure("Failed to resolve file description to a file target")
        continue
      }
      fileTargets.append(target)
    }
    return fileTargets
  }
}

// MARK: - Equatable

public func ==(lhs: RuleInfo, rhs: RuleInfo) -> Bool {
  return lhs.type == rhs.type && lhs.label == rhs.label
}
