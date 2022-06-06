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


/// Models the layered values for a single Tulsi option.
public class TulsiOption: Equatable, CustomStringConvertible {

  /// The string serialized for boolean options which are 'true'.
  public static let BooleanTrueValue = "YES"
  /// The string serialized for boolean options which are 'false'.
  public static let BooleanFalseValue = "NO"

  /// Special keyword that may be used in an option's value in order to inherit a parent option's
  /// value.
  public static let InheritKeyword = "$(inherited)"

  /// The valid value types for this option.
  public enum ValueType: Equatable {
    case bool, string
    case stringEnum(Set<String>)

    public static func ==(lhs: ValueType, rhs: ValueType) -> Bool {
      switch (lhs, rhs) {
        case (.bool, .bool): return true
        case (.string, .string): return true
        case (.stringEnum(let a), .stringEnum(let b)): return a == b
        default: return false
      }
    }
  }

  /// How this option is intended to be used.
  public struct OptionType: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    /// An option that is handled in Tulsi's code.
    static let Generic = OptionType([])

    /// An option that may be automatically encoded into a build setting.
    static let BuildSetting = OptionType(rawValue: 1 << 0)

    /// An option that may be specialized on a per-target basis.
    static let TargetSpecializable = OptionType(rawValue: 1 << 1)

    /// An option that may be automatically encoded into a build setting and overridden on a
    /// per-target basis.
    static let TargetSpecializableBuildSetting = OptionType([BuildSetting, TargetSpecializable])

    /// An option that is not visualized in the UI at all.
    static let Hidden = OptionType(rawValue: 1 << 16)

    /// An option that may only be persisted into per-user configs.
    static let PerUserOnly = OptionType(rawValue: 1 << 17)

    /// An option that merges its parent's value if the special InheritKeyword string appears.
    static let SupportsInheritKeyword = OptionType(rawValue: 1 << 18)
  }

  /// Name of this option as it should be displayed to the user.
  public let displayName: String
  /// Detailed description of what this option does.
  public let userDescription: String
  /// The type of value associated with this option.
  public let valueType: ValueType
  /// How this option is handled within Tulsi.
  public let optionType: OptionType

  /// Value of this option if the user does not provide any override.
  public let defaultValue: String?
  /// User-set value of this option for all targets within this project, unless overridden.
  public var projectValue: String? = nil
  /// Per-target values for this option.
  public var targetValues: [String: String]?

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

  /// Key under which this option's project-level value is stored.
  static let ProjectValueKey = "p"
  /// Key under which this option's target-level values are stored.
  static let TargetValuesKey = "t"
  typealias PersistenceType = [String: AnyObject]

  init(displayName: String,
       userDescription: String,
       valueType: ValueType,
       optionType: OptionType,
       defaultValue: String? = nil) {
    self.displayName = displayName
    self.userDescription = userDescription
    self.valueType = valueType
    self.optionType = optionType
    self.defaultValue = defaultValue

    if optionType.contains(.TargetSpecializable) {
      self.targetValues = [String: String]()
    } else {
      self.targetValues = nil
    }
  }

  /// Creates a new TulsiOption instance whose value is taken from an existing TulsiOption and may
  /// inherit parts/all of its values from another parent TulsiOption.
  init(resolvingValuesFrom opt: TulsiOption, byInheritingFrom parent: TulsiOption) {
    displayName = opt.displayName
    userDescription = opt.userDescription
    valueType = opt.valueType
    optionType = opt.optionType
    defaultValue = parent.commonValue
    projectValue = opt.projectValue
    targetValues = opt.targetValues

    let inheritValue = defaultValue ?? ""
    func resolveInheritKeyword(_ value: String?) -> String? {
      guard let value = value else { return nil }
      let newValue = value.replacingOccurrences(of: TulsiOption.InheritKeyword,
                                                with: inheritValue)
      return newValue.isEmpty ? nil : newValue
    }
    if optionType.contains(.SupportsInheritKeyword) {
      projectValue = resolveInheritKeyword(projectValue)
      if targetValues != nil {
        for (key, value) in targetValues! {
          targetValues![key] = resolveInheritKeyword(value)
        }
      }
    }
  }

  /// Provides the resolved value of this option, potentially specialized for the given target.
  public func valueForTarget(_ target: String, inherit: Bool = true) -> String? {
    if let val = targetValues?[target] {
      return val
    }

    if inherit {
      return commonValue
    }
    return nil
  }

  /// Append or set the project value of this option.
  public func appendProjectValue(_ value: String) {
    guard !value.isEmpty else { return }
    guard let previous = projectValue ?? defaultValue, !previous.isEmpty else {
      projectValue = value
      return
    }
    projectValue = "\(previous) \(value)"
  }

  public func sanitizeValue(_ value: String?) -> String? {
    switch (valueType) {
      case .bool:
        if value != TulsiOption.BooleanTrueValue {
          return TulsiOption.BooleanFalseValue
        }
        return value
      case .string:
        return value?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
      case .stringEnum(let values):
        guard let curValue = value else { return defaultValue }
        guard values.contains(curValue) else { return defaultValue }
        return curValue
    }
  }

  // Generates a serialized form of this option's user-defined values or nil if the value is
  // the default.
  func serialize() -> PersistenceType? {
    var serialized = PersistenceType()
    if let value = projectValue {
      serialized[TulsiOption.ProjectValueKey] = value as AnyObject?
    }

    if let values = targetValues, !values.isEmpty {
      serialized[TulsiOption.TargetValuesKey] = values as AnyObject?
    }
    if serialized.isEmpty { return nil }
    return serialized
  }

  func deserialize(_ serialized: PersistenceType) {
    if let value = serialized[TulsiOption.ProjectValueKey] as? String {
      projectValue = sanitizeValue(value)
    } else {
      projectValue = nil
    }

    if let values = serialized[TulsiOption.TargetValuesKey] as? [String: String] {
      var validValues = [String: String]()
      for (key, value) in values {
        if let sanitized = sanitizeValue(value) {
          validValues[key] = sanitized
        }
      }
      targetValues = validValues
    } else if optionType.contains(.TargetSpecializable) {
      self.targetValues = [String: String]()
    } else {
      self.targetValues = nil
    }
  }

  // MARK: - CustomStringConvertible

  public var description: String {
    return "\(displayName) - \(String(describing: commonValue)):\(String(describing: targetValues))"
  }
}

public func ==(lhs: TulsiOption, rhs: TulsiOption) -> Bool {
  if !(lhs.displayName == rhs.displayName &&
      lhs.userDescription == rhs.userDescription &&
      lhs.valueType == rhs.valueType &&
      lhs.optionType == rhs.optionType) {
    return false
  }

  func optionalsAreEqual<T>(_ a: T?, _ b: T?) -> Bool where T: Equatable {
    if a == nil { return b == nil }
    if b == nil { return false }
    return a! == b!
  }
  func optionalDictsAreEqual<K, V>(_ a: [K: V]?, _ b: [K: V]?) -> Bool where V: Equatable {
    if a == nil { return b == nil }
    if b == nil { return false }
    return a! == b!
  }
  return optionalsAreEqual(lhs.defaultValue, rhs.defaultValue) &&
      optionalsAreEqual(lhs.projectValue, rhs.projectValue) &&
      optionalDictsAreEqual(lhs.targetValues, rhs.targetValues)
}
