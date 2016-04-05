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

/// Models the full metadata of a single supported Bazel target.
/// See http://bazel.io/docs/build-ref.html#targets.
public final class RuleEntry: RuleInfo {
  /// Mapping of BUILD file type to Xcode Target type.
  static let BuildTypeToTargetType = [
      "objc_binary": PBXTarget.ProductType.Application,
      "objc_library": PBXTarget.ProductType.StaticLibrary,
      "ios_application": PBXTarget.ProductType.Application,
      "ios_extension_binary": PBXTarget.ProductType.AppExtension,
      "ios_framework_binary": PBXTarget.ProductType.Framework,
      "ios_test": PBXTarget.ProductType.UnitTest,

      // A Tulsi-internal generic "test host", used to generate build targets that act as hosts for
      // XCTest test rules.
      "_test_host_": PBXTarget.ProductType.Application,
  ]

  static let BuildTypesWithImplicitIPAs = Set<String>([
      "ios_application",
      "ios_extension",
      "ios_test",
      "objc_binary",
  ])

  /// Keys for a RuleEntry's attributes map. Definitions may be found in the Bazel Build
  /// Encyclopedia (see http://bazel.io/docs/be/overview.html).
  // Note: This set of must be kept in sync with the tulsi_aspects aspect.
  public enum Attribute: String {
    case asset_catalogs
    case binary
    case bridging_header
    case copts
    case datamodels
    case defines
    // Contains defines that were specified by the user on the commandline or are built into
    // Bazel itself.
    case compiler_defines
    case includes
    case launch_storyboard
    case pch
    case storyboards
    case xctest
    case xctest_app
  }

  /// Bazel attributes for this rule (e.g., "binary": <some label> on an ios_application).
  public let attributes: [Attribute: AnyObject]

  /// Source files associated with this rule.
  public let sourceFiles: [String]

  /// Set of the labels that this rule depends on.
  public let dependencies: Set<String>

  /// The BUILD file that this rule was defined in.
  public let buildFilePath: String?

  var pbxTargetType: PBXTarget.ProductType? {
    if type == "ios_test",
       let xctestOpt = attributes[.xctest] as? Bool where !xctestOpt {
      return RuleEntry.BuildTypeToTargetType["ios_application"]
    }
    return RuleEntry.BuildTypeToTargetType[type]
  }

  /// For rule types that generate an implicit name.ipa target, returns a BuildLabel usable to
  /// generate the IPA.
  var implicitIPATarget: BuildLabel? {
    if RuleEntry.BuildTypesWithImplicitIPAs.contains(type) {
      return BuildLabel(label.value + ".ipa")
    }
    return nil
  }

  init(label: BuildLabel,
       type: String,
       attributes: [String: AnyObject],
       sourceFiles: [String],
       dependencies: Set<String>,
       buildFilePath: String? = nil) {

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

    self.sourceFiles = sourceFiles
    self.dependencies = dependencies
    self.buildFilePath = buildFilePath

    var linkedTargetLabels = Set<BuildLabel>()
    if let hostLabelString = self.attributes[.xctest_app] as? String {
      linkedTargetLabels.insert(BuildLabel(hostLabelString))
    }

    super.init(label: label, type: type, linkedTargetLabels: linkedTargetLabels)
  }

  convenience init(label: String,
                   type: String,
                   attributes: [String: AnyObject],
                   sourceFiles: [String],
                   dependencies: Set<String>,
                   buildFilePath: String? = nil) {
    self.init(label: BuildLabel(label),
              type: type,
              attributes: attributes,
              sourceFiles: sourceFiles,
              dependencies: dependencies,
              buildFilePath: buildFilePath)
  }
}

// MARK: - Equatable

public func ==(lhs: RuleInfo, rhs: RuleInfo) -> Bool {
  return lhs.type == rhs.type && lhs.label == rhs.label
}
