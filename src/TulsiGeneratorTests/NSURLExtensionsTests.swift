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
@testable import TulsiGenerator


class NSURLExtensionsTests: XCTestCase {
  func testRelativePathOfEqualPaths() {
    let rootURL = NSURL(fileURLWithPath: "/test")
    XCTAssertEqual(rootURL.relativePathTo(rootURL), "")
  }

  func testRelativePathOfSiblingsAtRoot() {
    let rootURL = NSURL(fileURLWithPath: "/root")
    let targetURL = NSURL(fileURLWithPath: "/target")
    XCTAssertEqual(rootURL.relativePathTo(targetURL), "../target")
  }

  func testRelativePathOfSiblingPaths() {
    let rootURL = NSURL(fileURLWithPath: "/test/root")
    let targetURL = NSURL(fileURLWithPath: "/test/target")
    XCTAssertEqual(rootURL.relativePathTo(targetURL), "../target")
  }

  func testRelativePathOfChildPath() {
    let rootURL = NSURL(fileURLWithPath: "/test/root")
    do {
      let targetURL = NSURL(fileURLWithPath: "/test/root/target")
      XCTAssertEqual(rootURL.relativePathTo(targetURL), "target")
    }
    do {
      let targetURL = NSURL(fileURLWithPath: "/test/root/deeply/nested/target")
      XCTAssertEqual(rootURL.relativePathTo(targetURL), "deeply/nested/target")
    }
  }

  func testRelativePathOfParentPath() {
    let rootURL = NSURL(fileURLWithPath: "/test/deep/path/to/root")
    do {
      let targetURL = NSURL(fileURLWithPath: "/test/deep/path/to")
      XCTAssertEqual(rootURL.relativePathTo(targetURL), "..")
    }
    do {
      let targetURL = NSURL(fileURLWithPath: "/test")
      XCTAssertEqual(rootURL.relativePathTo(targetURL), "../../../..")
    }
  }

  func testRelativePathOfNonFileURL() {
    let rootURL = NSURL(string: "http://this/is/not/a/path")!
    let targetURL = NSURL(fileURLWithPath: "/path")
    XCTAssertNil(rootURL.relativePathTo(targetURL))
  }
}
