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

import XCTest
@testable import TulsiGenerator

class BazelSettingsProviderTests: XCTestCase {
  let bazel = "/path/to/bazel"
  let bazelExecRoot = "__MOCK_EXEC_ROOT__"
  let features = Set<BazelSettingFeature>()
  let buildRuleEntries = Set<RuleEntry>()
  let bazelSettingsProvider = BazelSettingsProvider(universalFlags: BazelFlags())


  func testBazelBuildSettingsProviderWithoutArm64_32Flag() {
    let options = TulsiOptionSet()
    let settings = bazelSettingsProvider.buildSettings(bazel:bazel,
                                                       bazelExecRoot: bazelExecRoot,
                                                       options: options,
                                                       features: features,
                                                       buildRuleEntries: buildRuleEntries)

    let arm64_32Flag = "--watchos_cpus=arm64_32"
    // Check that the arm64_32 flag is not set anywhere it shouldn't be by default.
    for (identifier, flags) in settings.platformConfigurationFlags {
      if identifier != "watchos_arm64_32" {
        XCTAssert(!flags.contains(arm64_32Flag),
                  "arm64_32 flag was unexpectedly set for \(identifier) by default. \(flags)")
      }
    }
  }

  func testBazelBuildSettingsProviderWithArm64_32Flag() {
    let options = TulsiOptionSet()
    // Manually enable the Tulsi option to force use arm64_32.
    options.options[.UseArm64_32]?.projectValue = "YES"

    let settings = bazelSettingsProvider.buildSettings(bazel:bazel,
                                                        bazelExecRoot: bazelExecRoot,
                                                        options: options,
                                                        features: Set<BazelSettingFeature>(),
                                                        buildRuleEntries: Set<RuleEntry>())

    let arm64_32Flag = "--watchos_cpus=arm64_32"
    // The flags corresponding to these identifiers will contain '--watchos_cpus=armv7k' which
    // must be overidden.
    let identifiersToOverride = Set(["ios_armv7", "ios_arm64", "watchos_armv7k"])

    // Test that the arm64_32 flag is set in the proper locations.
    for (identifier, flags) in settings.platformConfigurationFlags {
      if identifier == "watchos_arm64_32" || identifiersToOverride.contains(identifier) {
        XCTAssert(flags.contains(arm64_32Flag),
                  "arm64_32 flag was not set for \(identifier) by the UseArm64_32 option. \(flags)")
      } else {
        XCTAssert(!flags.contains(arm64_32Flag),
                  "arm64_32 flag was unexpectedly set for \(identifier) by the UseArm64_32 option. \(flags)")
      }
    }
  }
}
