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

/// Defines an object that provides flags for Bazel invocations.
protocol BazelSettingsProviderProtocol {
  /// All general-Tulsi flags, varying based on whether the project has Swift or not.
  func tulsiFlags(hasSwift: Bool) -> BazelFlagsSet

  /// Cache-able Bazel flags based off TulsiOptions, used to generate BazelBuildSettings.
  func optionsBasedFlags(_ options: TulsiOptionSet) -> BazelFlagsSet

  /// Bazel build settings, used during Xcode/user Bazel builds.
  func buildSettings(bazel: String,
                     bazelExecRoot: String,
                     options: TulsiOptionSet,
                     buildRuleEntries: Set<RuleEntry>) -> BazelBuildSettings
}

class BazelSettingsProvider: BazelSettingsProviderProtocol {

  /// Non-cacheable flags added by Tulsi for dbg (Debug) builds.
  static let tulsiDebugFlags = BazelFlags(build: ["--compilation_mode=dbg"])

  /// Non-cacheable flags added by Tulsi for opt (Release) builds.
  static let tulsiReleaseFlags = BazelFlags(build: ["--compilation_mode=opt", "--strip=always"])

  /// Non-cacheable flags added by Tulsi for all builds.
  static let tulsiCommonNonCacheableFlags = BazelFlags(build:  [
      "--define=apple.add_debugger_entitlement=1",
      "--define=apple.propagate_embedded_extra_outputs=1",
  ])

  /// Cache-able flags added by Tulsi for builds.
  static let tulsiCacheableFlags = BazelFlagsSet(buildFlags: ["--announce_rc"])
  /// Non-cacheable flags added by Tulsi for builds.
  static let tulsiNonCacheableFlags = BazelFlagsSet(debug: tulsiDebugFlags,
                                                    release: tulsiReleaseFlags,
                                                    common: tulsiCommonNonCacheableFlags)

  /// Flags added by Tulsi for builds which contain Swift.
  /// - Always generate dSYMs for projects with Swift dependencies, as dSYMs are still required to
  ///   expr or print variables within Bazel-built Swift modules in LLDB.
  static let tulsiSwiftFlags = BazelFlagsSet(buildFlags: ["--apple_generate_dsym"])

  /// Flags added by Tulsi for builds which do not contain Swift.
  /// - Enable dSYMs only for Release builds.
  /// - Flag for remapping debug symbols.
  static let tulsiNonSwiftFlags = BazelFlagsSet(
      release: BazelFlags(build: ["--apple_generate_dsym"]),
      // TODO: Somehow support the open-source version of this which varies based on the exec-root.
      common: BazelFlags(build: ["--features=debug_prefix_map_pwd_is_dot"]))

  let universalFlags: BazelFlags
  let cacheableFlags: BazelFlagsSet
  let nonCacheableFlags: BazelFlagsSet

  let swiftFlags: BazelFlagsSet
  let nonSwiftFlags: BazelFlagsSet

  public convenience init(universalFlags: BazelFlags) {
    self.init(universalFlags: universalFlags,
              cacheableFlags: BazelSettingsProvider.tulsiCacheableFlags,
              nonCacheableFlags: BazelSettingsProvider.tulsiNonCacheableFlags,
              swiftFlags: BazelSettingsProvider.tulsiSwiftFlags,
              nonSwiftFlags: BazelSettingsProvider.tulsiNonSwiftFlags)
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

  func tulsiFlags(hasSwift: Bool) -> BazelFlagsSet {
    let languageFlags = hasSwift ? swiftFlags : nonSwiftFlags
    return BazelFlagsSet(common: universalFlags) + cacheableFlags + nonCacheableFlags + languageFlags
  }

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
                     options: TulsiOptionSet,
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

    return BazelBuildSettings(bazel: bazel,
                              bazelExecRoot: bazelExecRoot,
                              swiftTargets: swiftTargets,
                              tulsiCacheAffectingFlagsSet: BazelFlagsSet(common: universalFlags) + nonCacheableFlags,
                              tulsiCacheSafeFlagSet: cacheableFlags + optionsBasedFlags(options),
                              tulsiSwiftFlagSet: swiftFlags,
                              tulsiNonSwiftFlagSet: nonSwiftFlags,
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

