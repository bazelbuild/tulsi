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

/// Models a single supported Bazel target (http://bazel.io/docs/build-ref.html#targets).
public class RuleEntry: Equatable, Hashable, CustomStringConvertible {
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
      "objc_binary",
  ])

  public let label: BuildLabel
  public let type: String

  /// Bazel attributes for this rule (e.g., "binary": <some label> on an ios_application).
  let attributes: [String: String]

  /// Map of this rule's build dependencies, indexed by their labels.
  var dependencies = [String: RuleEntry]()

  var pbxTargetType: PBXTarget.ProductType? {
    // ios_test rules with the xctest attribute set to false are actually applications.
    if type == "ios_test",
       let xctestOpt = self.attributes["xctest"] where xctestOpt == String(false) {
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

  public var hashValue: Int {
    return label.hashValue ^ type.hashValue
  }

  init(label: BuildLabel, type: String, attributes: [String: String] = [String: String]()) {
    self.label = label
    self.type = type
    self.attributes = attributes
  }

  convenience init(label: String, type: String, attributes: [String: String] = [String: String]()) {
    self.init(label: BuildLabel(label), type: type, attributes: attributes)
  }

  func addDependencies(ruleEntries: [RuleEntry]) {
    for rule in ruleEntries {
      dependencies[rule.label.value] = rule
    }
  }

  // MARK: - CustomStringConvertible

  public var description: String {
    return "\(NSStringFromClass(self.dynamicType))(\(self.label) \(self.type))"
  }
}

// MARK: - Equatable

public func ==(lhs: RuleEntry, rhs: RuleEntry) -> Bool {
  return lhs.type == rhs.type && lhs.label == rhs.label
}
