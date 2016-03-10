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

  public var hashValue: Int {
    return label.hashValue ^ type.hashValue
  }

  public var debugDescription: String {
    return "\(self.dynamicType)(\(label) \(type))"
  }

  init(label: BuildLabel, type: String) {
    self.label = label
    self.type = type
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
  ]

  static let BuildTypesWithImplicitIPAs = Set<String>([
      "ios_application",
      "ios_extension",
      "ios_test",
      "objc_binary",
  ])

  /// Bazel attributes for this rule (e.g., "binary": <some label> on an ios_application).
  public let attributes: [String: AnyObject]

  /// Source files associated with this rule.
  public let sourceFiles: [String]

  /// Set of the labels that this rule depends on.
  public let dependencies: Set<String>

  var pbxTargetType: PBXTarget.ProductType? {
    if type == "ios_test",
       let xctestOpt = attributes["xctest"] as? Bool where !xctestOpt {
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
       dependencies: Set<String>) {
    self.attributes = attributes
    self.sourceFiles = sourceFiles
    self.dependencies = dependencies

    super.init(label: label, type: type)
  }

  convenience init(label: String,
                   type: String,
                   attributes: [String: AnyObject],
                   sourceFiles: [String],
                   dependencies: Set<String>) {
    self.init(label: BuildLabel(label),
              type: type,
              attributes: attributes,
              sourceFiles: sourceFiles,
              dependencies: dependencies)
  }
}

// MARK: - Equatable

public func ==(lhs: RuleInfo, rhs: RuleInfo) -> Bool {
  return lhs.type == rhs.type && lhs.label == rhs.label
}
