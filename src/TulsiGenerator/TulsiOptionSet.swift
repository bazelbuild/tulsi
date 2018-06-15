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


/// Keys for all user modifiable Tulsi options.
// Style note: Entries that map directly to Xcode Build Settings values are all caps (matching
// Xcode's use) while entries handled in Tulsi are camel case.
public enum TulsiOptionKey: String {
  case
      // Whether or not to search user header paths first when resolving angle bracket includes.
      ALWAYS_SEARCH_USER_PATHS,
      // The path to the Bazel binary.
      BazelPath,
      // Whether or not to claim Swift code was created at the same version as Tulsi itself.
      // Suppresses the Xcode warning and automated update on first opening of the generated
      // project.
      SuppressSwiftUpdateCheck,
      // The path from a config file to its associated workspace root.
      WorkspaceRootPath,

      // Commandline Arguments used by the run phase of the generated scheme.
      CommandlineArguments,

      // Environment Variables used by the run phase of the generated scheme.
      EnvironmentVariables,

      // Option to enable compilation after error.
      BazelContinueBuildingAfterError,

      // Include all .bzl files related to the build in the generated Xcodeproj.
      IncludeBuildSources,

      // Include the following build options only during project generation; can override config
      // from default (simulator) to device.
      BazelBuildOptionsProjectGenerationOnly,

      // Improve auto-completion for include/import statements.
      ImprovedImportAutocompletionFix

  // Options for build invocations.
  case BazelBuildOptionsDebug,
       BazelBuildOptionsRelease

  // Startup options for build invocations.
  case BazelBuildStartupOptionsDebug,
       BazelBuildStartupOptionsRelease

  // Pre action scripts for build, launch, and test actions.
  case BuildActionPreActionScript,
       LaunchActionPreActionScript,
       TestActionPreActionScript

  // Post action scripts for build, launch, and test actions.
  case BuildActionPostActionScript,
       LaunchActionPostActionScript,
       TestActionPostActionScript
}


/// Logical groupings for TulsiOptionKeys.
public enum TulsiOptionKeyGroup: String {
  case BazelBuildOptions,
       BazelBuildStartupOptions,
       PreActionScriptOptions,
       PostActionScriptOptions
}


/// Models the set of all user-modifiable options supported by Tulsi.
public class TulsiOptionSet: Equatable {
  /// Suffix added to string keys in order to resolve an option's description.
  static let DescriptionStringKeySuffix = "_DESC"

  /// The key under which option sets are serialized.
  static let PersistenceKey = "optionSet"

  typealias PersistenceType = [String: TulsiOption.PersistenceType]

  static let OptionKeyGroups: [TulsiOptionKey: TulsiOptionKeyGroup] = [
      .BazelBuildOptionsDebug: .BazelBuildOptions,
      .BazelBuildOptionsRelease: .BazelBuildOptions,
      .BazelBuildStartupOptionsDebug: .BazelBuildStartupOptions,
      .BazelBuildStartupOptionsRelease: .BazelBuildStartupOptions,
      .BuildActionPreActionScript: .PreActionScriptOptions,
      .LaunchActionPreActionScript: .PreActionScriptOptions,
      .TestActionPreActionScript: .PreActionScriptOptions,
      .BuildActionPostActionScript: .PostActionScriptOptions,
      .LaunchActionPostActionScript: .PostActionScriptOptions,
      .TestActionPostActionScript: .PostActionScriptOptions
  ]

  public var allVisibleOptions = [TulsiOptionKey: TulsiOption]()
  var options = [TulsiOptionKey: TulsiOption]() {
    didSet {
      allVisibleOptions = [TulsiOptionKey: TulsiOption]()
      for (key, option) in options {
        if !option.optionType.contains(.Hidden) {
          allVisibleOptions[key] = option
        }
      }
    }
  }
  var optionKeyGroupInfo = [TulsiOptionKeyGroup: (displayName: String, description: String)]()

  public subscript(optionKey: TulsiOptionKey) -> TulsiOption {
    return options[optionKey]!
  }

  public subscript(optionKey: TulsiOptionKey, target: String) -> String? {
    return options[optionKey]?.valueForTarget(target)
  }

  static func getOptionsFromContainerDictionary(_ dict: [String: Any]) -> PersistenceType? {
    return dict[TulsiOptionSet.PersistenceKey] as? PersistenceType
  }

  public init(withInheritanceEnabled inherit: Bool = false) {
    let bundle = Bundle(for: type(of: self))
    populateOptionsWithBundle(bundle, withInheritAsDefault: inherit)
    populateOptionGroupInfoWithBundle(bundle)
  }

  public convenience init(fromDictionary dict: [String: Any]) {
    self.init()

    guard let persistedOptions = dict as? PersistenceType else {
      assertionFailure("Options dictionary is not of the expected type")
      return
    }

    for (key, option) in options {
      if let value = persistedOptions[key.rawValue] {
        option.deserialize(value)
      }
    }
  }

  /// Returns a new TulsiOptionSet by using the given parent as a base and applying this option
  /// set's options as overrides.
  public func optionSetByInheritingFrom(_ parent: TulsiOptionSet) -> TulsiOptionSet {
    var resolvedOptions = [TulsiOptionKey: TulsiOption]()
    for (key, opt) in options {
      guard let parentOption = parent.options[key] else {
        resolvedOptions[key] = opt
        continue
      }
      resolvedOptions[key] = TulsiOption(resolvingValuesFrom: opt, byInheritingFrom: parentOption)
    }

    let resolvedSet = TulsiOptionSet()
    resolvedSet.options = resolvedOptions
    return resolvedSet
  }

  func saveShareableOptionsIntoDictionary(_ dict: inout [String: Any]) {
    let serialized = saveToDictionary() {
      !$1.optionType.contains(.PerUserOnly)
    }
    dict[TulsiOptionSet.PersistenceKey] = serialized
  }

  func savePerUserOptionsIntoDictionary(_ dict: inout [String: Any]) {
    let serialized = saveToDictionary() {
      return $1.optionType.contains(.PerUserOnly)
    }
    dict[TulsiOptionSet.PersistenceKey] = serialized
  }

  func saveAllOptionsIntoDictionary(_ dict: inout [String: AnyObject]) {
    let serialized = saveToDictionary() { (_, _) in return true }
    dict[TulsiOptionSet.PersistenceKey] = serialized as AnyObject?
  }

  public func groupInfoForOptionKey(_ key: TulsiOptionKey) -> (TulsiOptionKeyGroup, displayName: String, description: String)? {
    guard let keyGroup = TulsiOptionSet.OptionKeyGroups[key] else { return nil }
    guard let (displayName, description) = optionKeyGroupInfo[keyGroup] else {
      assertionFailure("Missing group information for group key \(keyGroup)")
      return (keyGroup, "\(keyGroup)", "")
    }
    return (keyGroup, displayName, description)
  }

  /// Returns a dictionary of build settings without applying any specializations.
  func commonBuildSettings() -> [String: String] {
    // These values come from AppleToolchain.java in Bazel
    // https://github.com/bazelbuild/bazel/blob/master/src/main/java/com/google/devtools/build/lib/rules/apple/AppleToolchain.java
    var buildSettings = [
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
    ]

    for (key, opt) in options.filter({ $1.optionType.contains(.BuildSetting) }) {
      buildSettings[key.rawValue] = opt.commonValue!
    }
    return buildSettings
  }

  /// Returns a dictionary of build settings specialized for the given target without inheriting any
  /// defaults.
  func buildSettingsForTarget(_ target: String) -> [String: String] {
    var buildSettings = [String: String]()
    for (key, opt) in options.filter({ $1.optionType.contains(.TargetSpecializableBuildSetting) }) {
      if let val = opt.valueForTarget(target, inherit: false) {
        buildSettings[key.rawValue] = val
      }
    }
    return buildSettings
  }

  // MARK: - Private methods.

  private func saveToDictionary(_ filter: (TulsiOptionKey, TulsiOption) -> Bool) -> PersistenceType {
    var serialized = PersistenceType()
    for (key, option) in options.filter(filter) {
      if let value = option.serialize() {
        serialized[key.rawValue] = value
      }
    }
    return serialized
  }

  private func populateOptionsWithBundle(_ bundle: Bundle, withInheritAsDefault inherit: Bool) {
    func addOption(_ optionKey: TulsiOptionKey, valueType: TulsiOption.ValueType, optionType: TulsiOption.OptionType, defaultValue: String?) {
      let key = optionKey.rawValue
      let displayName = bundle.localizedString(forKey: key, value: nil, table: "Options")
      let descriptionKey = key + TulsiOptionSet.DescriptionStringKeySuffix
      var description = bundle.localizedString(forKey: descriptionKey, value: nil, table: "Options")
      if description == descriptionKey { description = "" }

      let opt = TulsiOption(displayName: displayName,
                            userDescription: description,
                            valueType: valueType,
                            optionType: optionType,
                            defaultValue: defaultValue)
      if inherit && optionType.contains(.SupportsInheritKeyword) {
        opt.projectValue = TulsiOption.InheritKeyword
      }
      options[optionKey] = opt
    }

    func addBoolOption(_ optionKey: TulsiOptionKey, _ optionType: TulsiOption.OptionType, _ defaultValue: Bool = false) {
      let val = defaultValue ? TulsiOption.BooleanTrueValue : TulsiOption.BooleanFalseValue
      addOption(optionKey, valueType: .bool, optionType: optionType, defaultValue: val)
    }

    func addStringOption(_ optionKey: TulsiOptionKey, _ optionType: TulsiOption.OptionType, _ defaultValue: String? = nil) {
      addOption(optionKey, valueType: .string, optionType: optionType, defaultValue: defaultValue)
    }

    addBoolOption(.ALWAYS_SEARCH_USER_PATHS, .BuildSetting, false)
    addBoolOption(.BazelContinueBuildingAfterError, .Generic, false)
    addStringOption(.BazelBuildOptionsProjectGenerationOnly, .Generic)
    addStringOption(.BazelBuildOptionsDebug, [.TargetSpecializable, .SupportsInheritKeyword])
    addStringOption(.BazelBuildOptionsRelease, [.TargetSpecializable, .SupportsInheritKeyword])
    addStringOption(.BazelBuildStartupOptionsDebug, [.TargetSpecializable, .SupportsInheritKeyword])
    addStringOption(.BazelBuildStartupOptionsRelease, [.TargetSpecializable, .SupportsInheritKeyword])
    addBoolOption(.SuppressSwiftUpdateCheck, .Generic, true)
    addBoolOption(.IncludeBuildSources, .Generic, false)
    addBoolOption(.ImprovedImportAutocompletionFix, .Generic, true)

    addStringOption(.CommandlineArguments, [.TargetSpecializable, .SupportsInheritKeyword])
    addStringOption(.EnvironmentVariables, [.TargetSpecializable, .SupportsInheritKeyword])

    addStringOption(.BuildActionPreActionScript, [.TargetSpecializable, .SupportsInheritKeyword])
    addStringOption(.LaunchActionPreActionScript, [.TargetSpecializable, .SupportsInheritKeyword])
    addStringOption(.TestActionPreActionScript, [.TargetSpecializable, .SupportsInheritKeyword])
    addStringOption(.BuildActionPostActionScript, [.TargetSpecializable, .SupportsInheritKeyword])
    addStringOption(.LaunchActionPostActionScript, [.TargetSpecializable, .SupportsInheritKeyword])
    addStringOption(.TestActionPostActionScript, [.TargetSpecializable, .SupportsInheritKeyword])

    addStringOption(.BazelPath, [.Hidden, .PerUserOnly])
    addStringOption(.WorkspaceRootPath, [.Hidden, .PerUserOnly])
  }

  private func populateOptionGroupInfoWithBundle(_ bundle: Bundle) {
    for (_, keyGroup) in TulsiOptionSet.OptionKeyGroups {
      if optionKeyGroupInfo[keyGroup] == nil {
        let key = keyGroup.rawValue
        let displayName = NSLocalizedString(key, tableName: "Options", bundle: bundle, comment: "")
        let descriptionKey = key + TulsiOptionSet.DescriptionStringKeySuffix
        let description = NSLocalizedString(descriptionKey, tableName: "Options", bundle: bundle, comment: "")
        optionKeyGroupInfo[keyGroup] = (displayName, description)
      }
    }
  }
}

public func ==(lhs: TulsiOptionSet, rhs: TulsiOptionSet) -> Bool {
  for (key, option) in lhs.options {
    if rhs[key] != option {
      return false
    }
  }
  return true
}
