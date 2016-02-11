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


/// Protocol for an object that can preserve a TulsiOption's values across application restarts.
protocol OptionPersisterProtocol: class {
  func saveProjectValue(value: String?, forStorageKey: String)
  func saveTargetValues(values: [String: String]?, forStorageKey: String)

  func loadProjectValueForStorageKey(storageKey: String) -> String?
  func loadTargetValueForStorageKey(storageKey: String) -> [String: String]?
}


/// Models the layered values for a single Tulsi option.
public class TulsiOption {

  /// The string serialized for boolean options which are 'true'.
  public static let BooleanTrueValue = "YES"
  /// The string serialized for boolean options which are 'false'.
  public static let BooleanFalseValue = "NO"

  /// The valid value types for this option.
  public enum ValueType {
    case Bool, String
  }

  /// How this option is intended to be used.
  public struct OptionType: OptionSetType {
    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    /// An option that is handled in Tulsi's code.
    static let Generic = OptionType(rawValue: 0)

    /// An option that may be automatically encoded into a build setting.
    static let BuildSetting = OptionType(rawValue: 1 << 0)

    /// An option that may be specialized on a per-target basis.
    static let TargetSpecializable = OptionType(rawValue: 1 << 1)

    /// An option that may be automatically encoded into a build setting and overridden on a
    /// per-target basis.
    static let TargetSpecializableBuildSetting = OptionType([BuildSetting, TargetSpecializable])
  }

  /// Name of this option as it should be displayed to the user.
  public let displayName: String
  /// Detailed description of what this option does.
  public let description: String
  /// The type of value associated with this option.
  public let valueType: ValueType
  /// How this option is handled within Tulsi.
  public let optionType: OptionType

  /// Value of this option if the user does not provide any override.
  public let defaultValue: String?
  /// User-set value of this option for all targets within this project, unless overridden.
  public var projectValue: String? = nil {
    didSet {
      persister?.saveProjectValue(projectValue, forStorageKey: storageKey)
    }
  }
  /// Per-target values for this option.
  public var targetValues: [String: String]? {
    didSet {
      persister?.saveTargetValues(targetValues, forStorageKey: storageKey)
    }
  }

  /// Provides the value of this option with no target specialization.
  public var commonValue: String? {
    if projectValue != nil { return projectValue }
    return defaultValue
  }

  /// Returns true if the value of this option with no target specialization is the serialization
  /// string equivalent to true. Returns nil if there is no common value for this option.
  public var commonValueAsBool: Bool? {
    guard let val = commonValue else {
      return nil
    }
    return val == TulsiOption.BooleanTrueValue
  }

  /// Opaque key used to persist/load values of this option.
  let storageKey: String!
  private weak var persister: OptionPersisterProtocol?

  init(storageKey: String?,
       persister: OptionPersisterProtocol?,
       displayName: String,
       description: String,
       valueType: ValueType,
       optionType: OptionType,
       defaultValue: String? = nil) {
    self.storageKey = storageKey
    self.displayName = displayName
    self.description = description
    self.valueType = valueType
    self.optionType = optionType
    self.defaultValue = defaultValue

    if optionType.contains(.TargetSpecializable) {
      self.targetValues = [String: String]()
    } else {
      self.targetValues = nil
    }

    // Intentionally set last to prevent values set in the initializer from being persisted
    // needlessly.
    self.persister = persister
  }

  /// Provides the resolved value of this option, potentially specialized for the given target.
  public func valueForTarget(target: String, inherit: Bool = true) -> String? {
    if let val = targetValues?[target] {
      return val
    }

    if inherit {
      return commonValue
    }
    return nil
  }

  public func sanitizeValue(value: String?) -> String? {
    if valueType == .Bool {
      if value != TulsiOption.BooleanTrueValue {
        return TulsiOption.BooleanFalseValue
      }
      return value
    }
    return value?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
  }

  func load() {
    guard let concretePersister = persister else { return }
    // Nil out the persister during the load to prevent storing values as they're loaded.
    persister = nil
    defer { persister = concretePersister }

    projectValue = concretePersister.loadProjectValueForStorageKey(storageKey)

    if let values = concretePersister.loadTargetValueForStorageKey(storageKey) {
      targetValues = values
    } else if optionType.contains(.TargetSpecializable) {
      targetValues = [String: String]()
    } else {
      targetValues = nil
    }
  }
}
