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

class BuildSettingsTests: XCTestCase {

  func testBazelFlagsEmpty() {
    XCTAssert(BazelFlags().isEmpty)
    XCTAssertEqual(BazelFlags().toPython(""), "BazelFlags()")
  }

  func testBazelFlagsOperators() {
    let a = BazelFlags(startupStr: "a b", buildStr: "x y")
    let b = BazelFlags(startupStr: "c d", buildStr: "z 1")
    let aExplicit = BazelFlags(startup: ["a", "b"], build: ["x", "y"])
    let bExplicit = BazelFlags(startup: ["c", "d"], build: ["z", "1"])

    XCTAssertEqual(a, aExplicit)
    XCTAssertEqual(b, bExplicit)

    let c = a + b
    XCTAssertEqual(c.startup, ["a", "b", "c", "d"])
    XCTAssertEqual(c.build, ["x", "y", "z", "1"])
    XCTAssertNotEqual(c, b + a)
  }

  func testBazelFlagsPythonable() {
    let startup = ["--startup-flag"]
    let build = ["--build-flag"]
    XCTAssertEqual(
      BazelFlags(startup: startup, build: build).toPython(""),
      """
BazelFlags(
    startup = [
        '--startup-flag',
    ],
    build = [
        '--build-flag',
    ],
)
"""
    )
  }

  func testBazelFlagsSetEmpty() {
    XCTAssert(BazelFlagsSet().isEmpty)
    XCTAssertEqual(BazelFlagsSet().toPython(""), "BazelFlagsSet()")
  }

  func testBazelFlagsSetInitializers() {
    let basicFlagsSet = BazelFlagsSet(startupFlags: ["a"], buildFlags: ["b"])
    let basicFlags = BazelFlags(startup: ["a"], build: ["b"])
    XCTAssertEqual(basicFlagsSet.release, basicFlags)
    XCTAssertEqual(basicFlagsSet.debug, basicFlags)
    XCTAssertEqual(basicFlagsSet.getFlags(forDebug: true), basicFlagsSet.debug)
    XCTAssertEqual(basicFlagsSet.getFlags(forDebug: false), basicFlagsSet.release)

    let complexFlagSet = BazelFlagsSet(
      debug: BazelFlags(startup: ["a"], build: ["b"]),
      release: BazelFlags(startup: ["x"], build: ["y"]),
      common: BazelFlags(startup: ["1"], build: ["2"]))
    XCTAssertEqual(complexFlagSet.debug, BazelFlags(startup: ["a", "1"], build: ["b", "2"]))
    XCTAssertEqual(complexFlagSet.release, BazelFlags(startup: ["x", "1"], build: ["y", "2"]))
  }

  func testBazelFlagsSetPythonable() {
    let basicFlagsSet = BazelFlagsSet(startupFlags: ["a"], buildFlags: ["b"])
    XCTAssertEqual(
      basicFlagsSet.toPython(""),
      """
BazelFlagsSet(
    flags = BazelFlags(
        startup = [
            'a',
        ],
        build = [
            'b',
        ],
    ),
)
"""
    )
    let complexFlagSet = BazelFlagsSet(
      debug: BazelFlags(startup: ["a"], build: ["b"]),
      release: BazelFlags(startup: ["x"], build: ["y"]),
      common: BazelFlags(startup: ["1"], build: ["2"]))
    XCTAssertEqual(
      complexFlagSet.toPython(""),
      """
BazelFlagsSet(
    debug = BazelFlags(
        startup = [
            'a',
            '1',
        ],
        build = [
            'b',
            '2',
        ],
    ),
    release = BazelFlags(
        startup = [
            'x',
            '1',
        ],
        build = [
            'y',
            '2',
        ],
    ),
)
"""
    )
  }

  func testBazelBuildSettingsPythonable() {
    let bazel = "/path/to/bazel"
    let bazelExecRoot = "__MOCK_EXEC_ROOT__"
    let bazelOutputBase = "__MOCK_OUTPUT_BASE__"
    let defaultIdentifier = "fake_config"
    let platformConfigurationFlags = [
      "fake_config": ["a", "b"],
      "another_one": ["--x", "-c"],
    ]

    let swiftTargets: Set<String> = [
      "//dir/swiftTarget:swiftTarget",
      "//dir/nested/depOnswift:depOnswift",
    ]
    let cacheAffecting = BazelFlagsSet(
      startupFlags: ["--nocacheStartup"],
      buildFlags: ["--nocacheBuild"])
    let cacheSafe = BazelFlagsSet(
      startupFlags: ["--cacheSafeStartup"],
      buildFlags: ["--cacheSafeBuild"])
    let swift = BazelFlagsSet(buildFlags: ["--swift-only"])
    let nonSwift = BazelFlagsSet(startupFlags: ["--non-swift-only"])
    let projDefaults = BazelFlagsSet()
    let projTargetFlags = [
      "//dir/some/customized:target": BazelFlagsSet(buildFlags: ["a", "b"]),
    ]
    let swiftFeatures = [BazelSettingFeature.DebugPathNormalization.stringValue]
    let nonSwiftFeatures = [BazelSettingFeature.DebugPathNormalization.stringValue]
    let settings = BazelBuildSettings(
      bazel: bazel,
      bazelExecRoot: bazelExecRoot,
      bazelOutputBase: bazelOutputBase,
      defaultPlatformConfigIdentifier: defaultIdentifier,
      platformConfigurationFlags: platformConfigurationFlags,
      swiftTargets: swiftTargets,
      tulsiCacheAffectingFlagsSet: cacheAffecting,
      tulsiCacheSafeFlagSet: cacheSafe,
      tulsiSwiftFlagSet: swift,
      tulsiNonSwiftFlagSet: nonSwift,
      swiftFeatures: swiftFeatures,
      nonSwiftFeatures: nonSwiftFeatures,
      projDefaultFlagSet: projDefaults,
      projTargetFlagSets: projTargetFlags)
    XCTAssertEqual(
      settings.toPython(""),
      """
BazelBuildSettings(
    '\(bazel)',
    '\(bazelExecRoot)',
    '\(bazelOutputBase)',
    '\(defaultIdentifier)',
    \(platformConfigurationFlags.toPython("    ")),
    \(swiftTargets.toPython("    ")),
    \(cacheAffecting.toPython("    ")),
    \(cacheSafe.toPython("    ")),
    \(swift.toPython("    ")),
    \(nonSwift.toPython("    ")),
    \(swiftFeatures.toPython("    ")),
    \(nonSwiftFeatures.toPython("    ")),
    \(projDefaults.toPython("    ")),
    \(projTargetFlags.toPython("    ")),
)
"""
    )
  }
}
