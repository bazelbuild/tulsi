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
      // The iPhone deployment target.
      IPHONEOS_DEPLOYMENT_TARGET,
      // The SDK to use.
      // TODO(abaire): This can probably be inferred from the BUILD file or better exposed through
      //     more specific flags.
      SDKROOT,
      // Whether or not to claim Swift code was created at the same version as Tulsi itself.
      // Suppresses the Xcode warning and automated update on first opening of the generated
      // project.
      SuppressSwiftUpdateCheck,
      // The path from a config file to its associated workspace root.
      WorkspaceRootPath

  // Options for build invocations.
  case BazelBuildOptionsDebug,
       BazelBuildOptionsFastbuild,
       BazelBuildOptionsRelease

  // Startup options for build invocations.
  case BazelBuildStartupOptionsDebug,
       BazelBuildStartupOptionsFastbuild,
       BazelBuildStartupOptionsRelease
}


/// Logical groupings for TulsiOptionKeys.
public enum TulsiOptionKeyGroup: String {
  case BazelBuildOptions,
       BazelBuildStartupOptions
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
      .BazelBuildOptionsFastbuild: .BazelBuildOptions,
      .BazelBuildOptionsRelease: .BazelBuildOptions,
      .BazelBuildStartupOptionsDebug: .BazelBuildStartupOptions,
      .BazelBuildStartupOptionsFastbuild: .BazelBuildStartupOptions,
      .BazelBuildStartupOptionsRelease: .BazelBuildStartupOptions
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

  public static func areOptionsSerializedInDict(dict: [String: AnyObject]) -> Bool {
    let persistedOptions = dict[TulsiOptionSet.PersistenceKey] as? PersistenceType ?? [:]
    return !persistedOptions.isEmpty
  }

  init() {
    let bundle = NSBundle(forClass: self.dynamicType)
    populateOptionsWithBundle(bundle)
    populateOptionGroupInfoWithBundle(bundle)
  }

  convenience init(fromDictionary dict: [String: AnyObject]) {
    self.init()

    let persistedOptions = dict[TulsiOptionSet.PersistenceKey] as? PersistenceType ?? [:]
    for (key, option) in options {
      if let value = persistedOptions[key.rawValue] {
        option.deserialize(value)
      }
    }
  }

  func saveToShareableDictionary(inout dict: [String: AnyObject]) {
    saveToDictionary(&dict) {
      !$1.optionType.contains(.PerUserOnly)
    }
  }

  func saveToPerUserDictionary(inout dict: [String: AnyObject], perUserOnly: Bool = true) {
    saveToDictionary(&dict) {
      if !perUserOnly { return true }
      return $1.optionType.contains(.PerUserOnly)
    }
  }

  public func groupInfoForOptionKey(key: TulsiOptionKey) -> (TulsiOptionKeyGroup, displayName: String, description: String)? {
    guard let keyGroup = TulsiOptionSet.OptionKeyGroups[key] else { return nil }
    guard let (displayName, description) = optionKeyGroupInfo[keyGroup] else {
      assertionFailure("Missing group information for group key \(keyGroup)")
      return (keyGroup, "\(keyGroup)", "")
    }
    return (keyGroup, displayName, description)
  }

  /// Returns a dictionary of build settings without applying any specializations.
  func commonBuildSettings() -> [String: String] {
    var buildSettings = [String: String]()
    for (key, opt) in options.filter({ $1.optionType.contains(.BuildSetting) }) {
      buildSettings[key.rawValue] = opt.commonValue!
    }
    return buildSettings
  }

  /// Returns a dictionary of build settings specialized for the given target without inheriting any
  /// defaults.
  func buildSettingsForTarget(target: String) -> [String: String] {
    var buildSettings = [String: String]()
    for (key, opt) in options.filter({ $1.optionType.contains(.TargetSpecializableBuildSetting) }) {
      if let val = opt.valueForTarget(target, inherit: false) {
        buildSettings[key.rawValue] = val
      }
    }
    return buildSettings
  }

  // MARK: - Private methods.

  private func saveToDictionary(inout dict: [String: AnyObject],
                                withFilter filter: (TulsiOptionKey, TulsiOption) -> Bool) {
    var serialized = PersistenceType()
    for (key, option) in options.filter(filter) {
      if let value = option.serialize() {
        serialized[key.rawValue] = value
      }
    }
    dict[TulsiOptionSet.PersistenceKey] = serialized
  }

  private func populateOptionsWithBundle(bundle: NSBundle) {
    func addOption(optionKey: TulsiOptionKey, valueType: TulsiOption.ValueType, optionType: TulsiOption.OptionType, defaultValue: String?) {
      let key = optionKey.rawValue
      let displayName = bundle.localizedStringForKey(key, value: nil, table: "Options")
      let descriptionKey = key + TulsiOptionSet.DescriptionStringKeySuffix
      var description = bundle.localizedStringForKey(descriptionKey, value: nil, table: "Options")
      if description == descriptionKey { description = "" }

      options[optionKey] = TulsiOption(displayName: displayName,
                                       userDescription: description,
                                       valueType: valueType,
                                       optionType: optionType,
                                       defaultValue: defaultValue)
    }

    func addBoolOption(optionKey: TulsiOptionKey, _ optionType: TulsiOption.OptionType, _ defaultValue: Bool = false) {
      let val = defaultValue ? TulsiOption.BooleanTrueValue : TulsiOption.BooleanFalseValue
      addOption(optionKey, valueType: .Bool, optionType: optionType, defaultValue: val)
    }

    func addStringOption(optionKey: TulsiOptionKey, _ optionType: TulsiOption.OptionType, _ defaultValue: String? = nil) {
      addOption(optionKey, valueType: .String, optionType: optionType, defaultValue: defaultValue)
    }

    addBoolOption(.ALWAYS_SEARCH_USER_PATHS, .BuildSetting, false)
    addStringOption(.BazelBuildOptionsDebug, .TargetSpecializable)
    addStringOption(.BazelBuildOptionsFastbuild, .TargetSpecializable)
    addStringOption(.BazelBuildOptionsRelease, .TargetSpecializable)
    addStringOption(.BazelBuildStartupOptionsDebug, .TargetSpecializable)
    addStringOption(.BazelBuildStartupOptionsFastbuild, .TargetSpecializable)
    addStringOption(.BazelBuildStartupOptionsRelease, .TargetSpecializable)
    addStringOption(.IPHONEOS_DEPLOYMENT_TARGET, .BuildSetting, "8.4")
    addStringOption(.SDKROOT, .TargetSpecializableBuildSetting, "iphoneos")
    addBoolOption(.SuppressSwiftUpdateCheck, .Generic, true)


    addStringOption(.BazelPath, [.Hidden, .PerUserOnly])
    addStringOption(.WorkspaceRootPath, [.Hidden, .PerUserOnly])
  }

  private func populateOptionGroupInfoWithBundle(bundle: NSBundle) {
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
