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
/// See http://bazel.io/docs/build-ref.html#targets.
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
    return "\(self.dynamicType)(\(label) \(type))"
  }

  init(label: BuildLabel, type: String, linkedTargetLabels: Set<BuildLabel>) {
    self.label = label
    self.type = type
    self.linkedTargetLabels = linkedTargetLabels
  }
}


/// Encapsulates data about a file that may be a Bazel input or output.
public class BazelFileInfo: Equatable {
  public enum TargetType {
    case SourceFile
    case GeneratedFile
  }

  /// The path to this file relative to rootPath.
  public let subPath: String

  /// The root of this file's path (typically used to indicate the path to a generated file's root).
  public let rootPath: String

  /// The type of this file.
  public let targetType: TargetType

  public lazy var fullPath: String = { [unowned self] in
    return NSString.pathWithComponents([self.rootPath, self.subPath])
  }()

  public lazy var uti: String? = { [unowned self] in
    return self.subPath.pbPathUTI
  }()

  init?(info: AnyObject?) {
    guard let info = info as? [String: AnyObject] else {
      return nil
    }

    guard let subPath = info["path"] as? String,
              isSourceFile = info["src"] as? Bool else {
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
    self.targetType = isSourceFile ? .SourceFile : .GeneratedFile
  }

  init(rootPath: String, subPath: String, targetType: TargetType) {
    self.rootPath = rootPath
    self.subPath = subPath
    self.targetType = targetType
  }
}

public func ==(lhs: BazelFileInfo, rhs: BazelFileInfo) -> Bool {
  return lhs.targetType == rhs.targetType &&
      lhs.rootPath == rhs.rootPath &&
      lhs.subPath == rhs.subPath
}


/// Models the full metadata of a single supported Bazel target.
/// See http://bazel.io/docs/build-ref.html#targets.
public final class RuleEntry: RuleInfo {
  /// Mapping of BUILD file type to Xcode Target type.
  static let BuildTypeToTargetType = [
      "apple_watch1_extension": PBXTarget.ProductType.AppExtension,
      "ios_application": PBXTarget.ProductType.Application,
      "ios_extension": PBXTarget.ProductType.AppExtension,
      "ios_framework": PBXTarget.ProductType.Framework,
      "ios_test": PBXTarget.ProductType.UnitTest,
      "objc_binary": PBXTarget.ProductType.Application,
      "objc_library": PBXTarget.ProductType.StaticLibrary,
      "swift_library": PBXTarget.ProductType.StaticLibrary,

      // A Tulsi-internal generic "test host", used to generate build targets that act as hosts for
      // XCTest test rules.
      "_test_host_": PBXTarget.ProductType.Application,
  ]

  /// Keys for a RuleEntry's attributes map. Definitions may be found in the Bazel Build
  /// Encyclopedia (see http://bazel.io/docs/be/overview.html).
  // Note: This set of must be kept in sync with the tulsi_aspects aspect.
  public enum Attribute: String {
    case binary
    case bridging_header
    // Contains defines that were specified by the user on the commandline or are built into
    // Bazel itself.
    case compiler_defines
    case copts
    case datamodels
    case defines
    case enable_modules
    case includes
    case launch_storyboard
    case pch
    // Contains various files that are used as part of the build process but need no special
    // handling in the generated Xcode project. For example, asset_catalog, storyboard, and xibs
    // attributes all end up as supporting_files.
    case supporting_files
    case xctest
    case xctest_app
  }

  /// Bazel attributes for this rule (e.g., "binary": <some label> on an ios_application).
  public let attributes: [Attribute: AnyObject]

  /// Artifacts produced by Bazel when this rule is built.
  public let artifacts: [BazelFileInfo]

  /// Source files associated with this rule.
  public let sourceFiles: [BazelFileInfo]

  /// Non-ARC source files associated with this rule.
  public let nonARCSourceFiles: [BazelFileInfo]

  public let generatedIncludePaths: [String]?

  /// Set of the labels that this rule depends on.
  public let dependencies: Set<String>

  /// .framework bundles provided by this rule.
  public let frameworkImports: [BazelFileInfo]

  /// List of implicit artifacts that are generated by this rule.
  public let secondaryArtifacts: [BazelFileInfo]

  /// The minimum iOS version supported by this target.
  public let iPhoneOSDeploymentTarget: String?

  /// Set of labels that this rule depends on but does not require.
  // NOTE(abaire): This is a hack used for test_suite rules, where the possible expansions retrieved
  // via queries are filtered by the existence of the selected labels extracted via the normal
  // aspect path. Ideally the aspect would be able to directly express the relationship between the
  // test_suite and the test rules themselves, but that expansion is done prior to the application
  // of the aspect.
  public var weakDependencies = Set<BuildLabel>()

  /// The BUILD file that this rule was defined in.
  public let buildFilePath: String?

  /// Returns the set of non-versioned artifacts that are not source files.
  public var normalNonSourceArtifacts: [BazelFileInfo] {
    var artifacts = [BazelFileInfo]()
    if let description = attributes[.launch_storyboard] as? [String: AnyObject],
           fileTarget = BazelFileInfo(info: description) {
      artifacts.append(fileTarget)
    }

    if let fileTargets = parseFileDescriptionListAttribute(.supporting_files) {
      artifacts.appendContentsOf(fileTargets)
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
    artifacts.appendContentsOf(nonARCSourceFiles)
    artifacts.appendContentsOf(frameworkImports)
    artifacts.appendContentsOf(normalNonSourceArtifacts)
    artifacts.appendContentsOf(versionedNonSourceArtifacts)
    return artifacts
  }

  private(set) lazy var pbxTargetType: PBXTarget.ProductType? = { [unowned self] in
    if self.type == "ios_test",
       let xctestOpt = self.attributes[.xctest] as? Bool where !xctestOpt {
      return BuildTypeToTargetType["ios_application"]
    }

    return BuildTypeToTargetType[self.type]
  }()

  /// For rule types that generate an implicit name.ipa target, returns a BuildLabel usable to
  /// generate the IPA.
  let implicitIPATarget: BuildLabel?

  init(label: BuildLabel,
       type: String,
       attributes: [String: AnyObject],
       artifacts: [BazelFileInfo],
       sourceFiles: [BazelFileInfo],
       nonARCSourceFiles: [BazelFileInfo],
       dependencies: Set<String>,
       frameworkImports: [BazelFileInfo],
       secondaryArtifacts: [BazelFileInfo],
       iPhoneOSDeploymentTarget: String? = nil,
       weakDependencies: Set<BuildLabel>? = nil,
       buildFilePath: String? = nil,
       generatedIncludePaths: [String]? = nil,
       implicitIPATarget: BuildLabel? = nil) {

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

    self.artifacts = artifacts
    self.sourceFiles = sourceFiles
    self.nonARCSourceFiles = nonARCSourceFiles
    self.dependencies = dependencies
    self.frameworkImports = frameworkImports
    self.secondaryArtifacts = secondaryArtifacts
    self.iPhoneOSDeploymentTarget = iPhoneOSDeploymentTarget
    if let weakDependencies = weakDependencies {
      self.weakDependencies = weakDependencies
    }
    self.buildFilePath = buildFilePath
    self.generatedIncludePaths = generatedIncludePaths
    self.implicitIPATarget = implicitIPATarget

    var linkedTargetLabels = Set<BuildLabel>()
    if let hostLabelString = self.attributes[.xctest_app] as? String {
      linkedTargetLabels.insert(BuildLabel(hostLabelString))
    }

    super.init(label: label, type: type, linkedTargetLabels: linkedTargetLabels)
  }

  convenience init(label: String,
                   type: String,
                   attributes: [String: AnyObject],
                   artifacts: [BazelFileInfo],
                   sourceFiles: [BazelFileInfo],
                   nonARCSourceFiles: [BazelFileInfo],
                   dependencies: Set<String>,
                   frameworkImports: [BazelFileInfo],
                   secondaryArtifacts: [BazelFileInfo],
                   iPhoneOSDeploymentTarget: String? = nil,
                   weakDependencies: Set<BuildLabel>? = nil,
                   buildFilePath: String? = nil,
                   generatedIncludePaths: [String]? = nil,
                   implicitIPATarget: BuildLabel? = nil) {
    self.init(label: BuildLabel(label),
              type: type,
              attributes: attributes,
              artifacts: artifacts,
              sourceFiles: sourceFiles,
              nonARCSourceFiles: nonARCSourceFiles,
              dependencies: dependencies,
              frameworkImports: frameworkImports,
              secondaryArtifacts: secondaryArtifacts,
              iPhoneOSDeploymentTarget: iPhoneOSDeploymentTarget,
              weakDependencies: weakDependencies,
              buildFilePath: buildFilePath,
              generatedIncludePaths: generatedIncludePaths,
              implicitIPATarget: implicitIPATarget)
  }

  // MARK: Private methods

  private func parseFileDescriptionListAttribute(attribute: RuleEntry.Attribute) -> [BazelFileInfo]? {
    guard let descriptions = attributes[attribute] as? [[String: AnyObject]] else {
      return nil
    }

    var fileTargets = [BazelFileInfo]()
    for description in descriptions {
      guard let target = BazelFileInfo(info: description) else {
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
