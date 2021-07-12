// Copyright 2018 The Tulsi Authors. All rights reserved.
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

/// Bazel feature settings that map to Bazel flags (start up or build options). These flags may
/// affect Bazel analysis/action caching and therefore should be kept consistent between all
/// invocations from Tulsi.
///
/// If adding a flag that does not impact Bazel caching, it can be added directly to
/// BazelSettingsProvider directly (either as a cacheableFlag or a configBasedFlag).
public enum BazelSettingFeature: Hashable, Pythonable {

  /// Feature flag to normalize paths present in debug information via a Clang flag for distributed
  /// builds (e.g. multiple distinct paths).
  ///
  /// The use of this flag does not affect any sources built by swiftc. At present time, all Swift
  /// compiled sources will be built with uncacheable, absolute paths, as the Swift compiler does
  /// not provide an easy means of similarly normalizing all debug information.
  case DebugPathNormalization

  /// Presence of Swift forces dSYMs to be enabled. dSYMS were previously required for debugging.
  /// See https://forums.swift.org/t/improving-swift-lldb-support-for-path-remappings/22694.
  case SwiftForcesdSYMs

  /// Build using tree artifact outputs (--define=apple.experimental.tree_artifact_outputs=1).
  /// Should only be disabled if it causes errors.
  /// Known issues:
  /// - Bundles with spaces in the name
  /// - When enabled, the working directory of the `ipa_post_processor` tool for `ios_application` is
  ///   the `Payload` directory, not its parent directory.
  ///   See https://github.com/bazelbuild/rules_apple/issues/733.
  case TreeArtifactOutputs

  /// TODO(b/111928007): Remove this and/or BazelSettingFeature once DebugPathNormalization is
  /// supported by all builds.
  public var stringValue: String {
    switch self {
      case .DebugPathNormalization:
        return "DebugPathNormalization"
      case .SwiftForcesdSYMs:
        return "SwiftForcesdSYMs"
      case .TreeArtifactOutputs:
        return "TreeArtifactOutputs"
    }
  }

  public var hashValue: Int {
    return stringValue.hashValue
  }

  public static func ==(lhs: BazelSettingFeature, rhs: BazelSettingFeature) -> Bool {
    return lhs.stringValue == rhs.stringValue
  }

  public var supportsSwift: Bool {
    switch self {
      case .DebugPathNormalization:
        /// Technically this doesn't support swiftc, but we now support this feature for
        /// Cxx compilation alongside swift compilation.
        return true
      case .SwiftForcesdSYMs:
        return true
      case .TreeArtifactOutputs:
        return true
    }
  }

  public var supportsNonSwift: Bool {
    switch self {
      case .DebugPathNormalization:
        return true
      case .SwiftForcesdSYMs:
        return false
      case .TreeArtifactOutputs:
        return true
    }
  }

  /// Start up flags for this feature.
  public var startupFlags: [String] {
    return []
  }

  /// Build flags for this feature.
  public var buildFlags: [String] {
    switch self {
      case .DebugPathNormalization: return ["--features=debug_prefix_map_pwd_is_dot"]
      case .SwiftForcesdSYMs: return ["--apple_generate_dsym"]
      case .TreeArtifactOutputs: return ["--define=apple.experimental.tree_artifact_outputs=1"]
    }
  }

  func toPython(_ indentation: String) -> String {
    return stringValue.toPython(indentation)
  }
}

/// Defines an object that provides flags for Bazel invocations.
protocol BazelSettingsProviderProtocol {
  /// Universal flags for all Bazel invocations.
  var universalFlags: BazelFlags { get }

  /// All general-Tulsi flags, varying based on whether the project has Swift or not.
  func tulsiFlags(hasSwift: Bool,
                  options: TulsiOptionSet?,
                  features: Set<BazelSettingFeature>) -> BazelFlagsSet

  /// Bazel build settings, used during Xcode/user Bazel builds.
  func buildSettings(bazel: String,
                     bazelExecRoot: String,
                     bazelOutputBase: String,
                     options: TulsiOptionSet,
                     features: Set<BazelSettingFeature>,
                     buildRuleEntries: Set<RuleEntry>) -> BazelBuildSettings
}

class BazelSettingsProvider: BazelSettingsProviderProtocol {

  /// Non-cacheable flags added by Tulsi for dbg (Debug) builds.
  static let tulsiDebugFlags = BazelFlags(build: ["--compilation_mode=dbg"])

  /// Non-cacheable flags added by Tulsi for opt (Release) builds.
  static let tulsiReleaseFlags = BazelFlags(build: [
      "--compilation_mode=opt",
      "--strip=always",
      "--apple_generate_dsym",
  ])

  /// Non-cacheable flags added by Tulsi for all builds.
  static let tulsiCommonNonCacheableFlags = BazelFlags(build: [
      "--define=apple.add_debugger_entitlement=1",
      "--define=apple.propagate_embedded_extra_outputs=1",
  ])

  /// Cache-able flags added by Tulsi for builds.
  static let tulsiCacheableFlags = BazelFlagsSet(buildFlags: ["--announce_rc"])

  /// Non-cacheable flags added by Tulsi for builds.
  static let tulsiNonCacheableFlags = BazelFlagsSet(debug: tulsiDebugFlags,
                                                    release: tulsiReleaseFlags,
                                                    common: tulsiCommonNonCacheableFlags)

  /// Universal flags that apply to all Bazel invocations (even queries).
  let universalFlags: BazelFlags

  /// Cache-able flags for builds.
  let cacheableFlags: BazelFlagsSet

  /// Non-cacheable flags for builds. Avoid changing these if possible.
  let nonCacheableFlags: BazelFlagsSet

  /// Flags used for targets which depend on Swift.
  let swiftFlags: BazelFlagsSet

  /// Flags used for targets which do not depend on Swift.
  let nonSwiftFlags: BazelFlagsSet

  public convenience init(universalFlags: BazelFlags) {
    self.init(universalFlags: universalFlags,
              cacheableFlags: BazelSettingsProvider.tulsiCacheableFlags,
              nonCacheableFlags: BazelSettingsProvider.tulsiNonCacheableFlags,
              swiftFlags: BazelFlagsSet(),
              nonSwiftFlags: BazelFlagsSet())
  }

  public init(universalFlags: BazelFlags,
              cacheableFlags: BazelFlagsSet,
              nonCacheableFlags: BazelFlagsSet,
              swiftFlags: BazelFlagsSet,
              nonSwiftFlags: BazelFlagsSet) {
    self.universalFlags = universalFlags
    self.cacheableFlags = cacheableFlags
    self.nonCacheableFlags = nonCacheableFlags
    self.swiftFlags = swiftFlags
    self.nonSwiftFlags = nonSwiftFlags
  }

  func tulsiFlags(hasSwift: Bool,
                  options: TulsiOptionSet?,
                  features: Set<BazelSettingFeature>) -> BazelFlagsSet {
    let optionFlags: BazelFlagsSet
    if let options = options {
      optionFlags = optionsBasedFlags(options)
    } else {
      optionFlags = BazelFlagsSet()
    }
    let languageFlags = (hasSwift ? swiftFlags : nonSwiftFlags) + featureFlags(features,
                                                                               hasSwift: hasSwift)
    return cacheableFlags + optionFlags + BazelFlagsSet(common: universalFlags) +
      nonCacheableFlags + languageFlags
  }

  /// Non-cacheable Bazel flags based off of BazelSettingFeatures for the project.
  func featureFlags(_ features: Set<BazelSettingFeature>, hasSwift: Bool) -> BazelFlagsSet {
    let validFeatures = features.filter { return hasSwift ? $0.supportsSwift : $0.supportsNonSwift }
    let sortedFeatures = validFeatures.sorted { (a, b) -> Bool in
      return a.stringValue > b.stringValue
    }

    let startupFlags = sortedFeatures.reduce(into: []) { (arr, feature) in
      arr.append(contentsOf: feature.startupFlags)
    }
    let buildFlags = sortedFeatures.reduce(into: []) { (arr, feature) in
      arr.append(contentsOf: feature.buildFlags)
    }
    return BazelFlagsSet(startupFlags: startupFlags, buildFlags: buildFlags)
  }

  /// Returns an array of the enabled features' names.
  func featureNames(_ features: Set<BazelSettingFeature>, hasSwift: Bool) -> [String] {
    let validFeatures = features.filter { return hasSwift ? $0.supportsSwift : $0.supportsNonSwift }
    return validFeatures.sorted { (a, b) -> Bool in
      return a.stringValue > b.stringValue
    }.map { $0.stringValue }
  }

  /// Cache-able Bazel flags based off TulsiOptions, used to generate BazelBuildSettings. This
  /// should only add flags that do not affect Bazel analysis/action caching; flags that are based
  /// off of TulsiOptions but do affect Bazel caching should instead be added to as
  /// BazelSettingFeatures.
  func optionsBasedFlags(_ options: TulsiOptionSet) -> BazelFlagsSet {
    var configBasedTulsiFlags = [String]()
    if let continueBuildingAfterError = options[.BazelContinueBuildingAfterError].commonValueAsBool,
      continueBuildingAfterError {
      configBasedTulsiFlags.append("--keep_going")
    }
    return BazelFlagsSet(buildFlags: configBasedTulsiFlags)
  }

  func buildSettings(bazel: String,
                     bazelExecRoot: String,
                     bazelOutputBase: String,
                     options: TulsiOptionSet,
                     features: Set<BazelSettingFeature>,
                     buildRuleEntries: Set<RuleEntry>) -> BazelBuildSettings {
    let projDefaultSettings = getProjDefaultSettings(options)
    var targetSettings = [String: BazelFlagsSet]()

    // Create a Set of all targets which have specialized Bazel settings.
    var labels = Set<String>()
    labels.formUnion(getTargets(options, .BazelBuildOptionsDebug))
    labels.formUnion(getTargets(options, .BazelBuildOptionsRelease))
    labels.formUnion(getTargets(options, .BazelBuildStartupOptionsDebug))
    labels.formUnion(getTargets(options, .BazelBuildStartupOptionsRelease))

    for lbl in labels {
      guard let settings = getTargetSettings(options, lbl, defaultValue: projDefaultSettings) else {
        continue
      }
      targetSettings[lbl] = settings
    }

    let swiftRuleEntries = buildRuleEntries.filter {
        $0.attributes[.has_swift_dependency] as? Bool ?? false
    }
    let swiftTargets = Set(swiftRuleEntries.map { $0.label.value })

    let tulsiSwiftFlags = swiftFlags + featureFlags(features, hasSwift: true)
    let tulsiNonSwiftFlagSet = nonSwiftFlags + featureFlags(features, hasSwift: false)
    let swiftFeatures = featureNames(features, hasSwift: true)
    let nonSwiftFeatures = featureNames(features, hasSwift: false)

    let defaultConfig: PlatformConfiguration
    if let identifier = options[.ProjectGenerationPlatformConfiguration].commonValue,
       let parsedConfig = PlatformConfiguration(identifier: identifier) {
      defaultConfig = parsedConfig
    } else {
      defaultConfig = PlatformConfiguration.defaultConfiguration
    }

    return BazelBuildSettings(bazel: bazel,
                              bazelExecRoot: bazelExecRoot,
                              bazelOutputBase: bazelOutputBase,
                              defaultPlatformConfigIdentifier: defaultConfig.identifier,
                              platformConfigurationFlags: nil,
                              swiftTargets: swiftTargets,
                              tulsiCacheAffectingFlagsSet: BazelFlagsSet(common: universalFlags) + nonCacheableFlags,
                              tulsiCacheSafeFlagSet: cacheableFlags + optionsBasedFlags(options),
                              tulsiSwiftFlagSet: tulsiSwiftFlags,
                              tulsiNonSwiftFlagSet: tulsiNonSwiftFlagSet,
                              swiftFeatures: swiftFeatures,
                              nonSwiftFeatures: nonSwiftFeatures,
                              projDefaultFlagSet: projDefaultSettings,
                              projTargetFlagSets: targetSettings)
  }


  private func getValue(_ options: TulsiOptionSet, _ key: TulsiOptionKey, defaultValue: String)
      -> String {
    return options[key].commonValue ?? defaultValue
  }

  private func getTargets(_ options: TulsiOptionSet, _ key: TulsiOptionKey) -> [String] {
    guard let targetValues = options[key].targetValues else { return [String]() }
    return Array(targetValues.keys)
  }

  private func getTargetValue(_ options: TulsiOptionSet,
                              _ key: TulsiOptionKey,
                              _ target: String,
                              defaultValue: String) -> String {
    return options[key, target] ?? defaultValue
  }

  private func getProjDefaultSettings(_ options: TulsiOptionSet) -> BazelFlagsSet {
    let debugStartup = getValue(options, .BazelBuildStartupOptionsDebug, defaultValue: "")
    let debugBuild = getValue(options, .BazelBuildOptionsDebug, defaultValue: "")
    let releaseStartup = getValue(options, .BazelBuildStartupOptionsRelease, defaultValue: "")
    let releaseBuild = getValue(options, .BazelBuildOptionsRelease, defaultValue: "")

    let debugFlags = BazelFlags(startupStr: debugStartup, buildStr: debugBuild)
    let releaseFlags = BazelFlags(startupStr: releaseStartup, buildStr: releaseBuild)

    return BazelFlagsSet(debug: debugFlags, release: releaseFlags)
  }

  private func getTargetSettings(_ options: TulsiOptionSet,
                                 _ label: String,
                                 defaultValue: BazelFlagsSet) -> BazelFlagsSet? {
    let debugStartup = getTargetValue(options, .BazelBuildStartupOptionsDebug, label, defaultValue: "")
    let debugBuild = getTargetValue(options, .BazelBuildOptionsDebug, label, defaultValue: "")
    let releaseStartup = getTargetValue(options, .BazelBuildStartupOptionsRelease, label, defaultValue: "")
    let releaseBuild = getTargetValue(options, .BazelBuildOptionsRelease, label, defaultValue: "")

    let debugFlags = BazelFlags(startupStr: debugStartup, buildStr: debugBuild)
    let releaseFlags = BazelFlags(startupStr: releaseStartup, buildStr: releaseBuild)

    // Return nil if we have the same settings as the defaultValue.
    guard debugFlags != defaultValue.debug
      && releaseFlags != defaultValue.release else {
        return nil
    }
    return BazelFlagsSet(debug: debugFlags, release: releaseFlags)
  }

}

