
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


// End to end test that generates the Buttons project and runs its unit tests. This variation of the
// test uses the nightly Bazel binary.
class ButtonsNightlyEndToEndTest: TulsiEndToEndTest {
  override func setUp() {
    super.setUp()

    if (!copyDataToFakeWorkspace("third_party/bazel_rules/rules_apple/examples/multi_platform/Buttons")) {
      XCTFail("Failed to copy Buttons files to fake execroot.")
    }

    if (!copyDataToFakeWorkspace("third_party/tulsi/src/TulsiEndToEndTests/Resources")) {
      XCTFail("Failed to copy Buttons tulsiproj to fake execroot.")
    }
  }

  func testButtonsWithNightlyBazel() throws {
    guard let nightlyBazelURL = fakeBazelWorkspace.nightlyBazelURL else {
      XCTFail("Expected Bazel nightly URL.")
      return
    }
    XCTAssert(fileManager.fileExists(atPath: nightlyBazelURL.path), "Bazel nightly is missing.")

    bazelURL = nightlyBazelURL
    let buttonsProjectPath = "third_party/tulsi/src/TulsiEndToEndTests/Resources/Buttons.tulsiproj"
    let xcodeProjectURL = generateXcodeProject(tulsiProject: buttonsProjectPath,
                                               config: "Buttons")
    XCTAssert(fileManager.fileExists(atPath: xcodeProjectURL.path), "Xcode project was not generated.")
    testXcodeProject(xcodeProjectURL, scheme: "ButtonsLogicTests")
  }
}
