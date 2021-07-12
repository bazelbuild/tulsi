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
  let bazelOutputBase = "__MOCK_OUTPUT_BASE__"
  let features = Set<BazelSettingFeature>()
  let buildRuleEntries = Set<RuleEntry>()
  let bazelSettingsProvider = BazelSettingsProvider(universalFlags: BazelFlags())

  func testBazelBuildSettingsProviderForWatchOS() {
    let options = TulsiOptionSet()
    let settings = bazelSettingsProvider.buildSettings(
      bazel: bazel,
      bazelExecRoot: bazelExecRoot,
      bazelOutputBase: bazelOutputBase,
      options: options,
      features: features,
      buildRuleEntries: buildRuleEntries)

    let expectedFlag = "--watchos_cpus=armv7k,arm64_32"
    let expectedIdentifiers = Set(["watchos_armv7k", "watchos_arm64_32", "ios_arm64", "ios_arm64e"])
    // Check that both watchos flags are set for both architectures.
    for (identifier, flags) in settings.platformConfigurationFlags {
      if expectedIdentifiers.contains(identifier) {
        XCTAssert(
          flags.contains(expectedFlag),
          "\(expectedFlag) flag was not set for \(identifier).")
      } else {
        XCTAssert(
          !flags.contains(expectedFlag),
          "\(expectedFlag) flag was unexpectedly set for \(identifier).")
      }
    }
  }
}
