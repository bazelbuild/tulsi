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

import XCTest

@testable import BazelIntegrationTestCase
@testable import TulsiEndToEndTestBase
@testable import TulsiGenerator

// End to end test that generates the Buttons project and runs its unit tests.
class ButtonsEndToEndTest: TulsiEndToEndTest {
  fileprivate let buttonsProjectPath =
    "src/TulsiEndToEndTests/Resources/Buttons.tulsiproj"

  override func setUp() {
    super.setUp()

    if !copyDataToFakeWorkspace("src/TulsiEndToEndTests/Resources") {
      XCTFail("Failed to copy Buttons files to fake execroot.")
    }
  }

  func testButtons() throws {
    let xcodeProjectURL = generateXcodeProject(
      tulsiProject: buttonsProjectPath,
      config: "Buttons")
    XCTAssert(
      fileManager.fileExists(atPath: xcodeProjectURL.path), "Xcode project was not generated.")

    testXcodeProject(xcodeProjectURL, scheme: "ButtonsTests")

    let installingDsymBundlesOutput = "Installing dSYM bundles completed"

    let releaseBuildOutput = buildXcodeTarget(
      xcodeProjectURL, target: "Buttons", configuration: "Release")
    XCTAssert(releaseBuildOutput.contains(installingDsymBundlesOutput))

    let debugBuildOutput = buildXcodeTarget(
      xcodeProjectURL, target: "Buttons", configuration: "Debug")
    XCTAssertFalse(debugBuildOutput.contains(installingDsymBundlesOutput))
  }

  func indexXcodeScheme(_ xcodeProjectURL: URL, _ scheme: String) {
    let completionInfo = ProcessRunner.launchProcessSync(
      "/usr/bin/xcrun",
      arguments: [
        "xcindex-test",
        "-project",
        xcodeProjectURL.path,
        "--",
        "create-build-description",
        "-scheme",
        scheme,
        "--",
        "index-files",
        "-targets-of-scheme",
        scheme,
        "--",
        "quit",
      ])

    let stdout = String(data: completionInfo.stdout, encoding: .utf8) ?? ""
    let stderr = String(data: completionInfo.stderr, encoding: .utf8) ?? ""
    print("Index exit code \(completionInfo.terminationStatus), output:\n\(stdout)\nerror:\n\(stderr)")
    if (completionInfo.terminationStatus != 0) {
      XCTFail("Indexing operation failed for \(xcodeProjectURL):\(scheme).")
    }
  }

  /// Verifies that all of the indexer targets in the project can be indexed.
  func testIndexingTargetsIndexInvocations() throws {
    let xcodeProjectURL = generateXcodeProject(
      tulsiProject: buttonsProjectPath,
      config: "Buttons")
    XCTAssert(
      fileManager.fileExists(atPath: xcodeProjectURL.path), "Xcode project was not generated.")
    let targets = targetsOfXcodeProject(xcodeProjectURL)
    let indexTargets = targets.filter { $0.hasPrefix("_idx_") }
    XCTAssertEqual(indexTargets.count, 6)
    indexXcodeScheme(xcodeProjectURL, "_idx_Scheme")
  }

  func testInvalidConfig() throws {
    let xcodeProjectURL = generateXcodeProject(
      tulsiProject: buttonsProjectPath,
      config: "InvalidConfig")
    XCTAssertFalse(
      fileManager.fileExists(atPath: xcodeProjectURL.path),
      "Xcode project was generated despite invalid config.")
  }
}
