// Copyright 2017 The Tulsi Authors. All rights reserved.
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

class DottedVersionTests: XCTestCase {
  let a1 = DottedVersion("9.0")!
  let a2 = DottedVersion("9.0.0")!
  let b1 = DottedVersion("10.0.1")!
  let b2 = DottedVersion("10.00.1")!
  let b3 = DottedVersion("10.0.1.0")!
  let c1 = DottedVersion("10.0.1.0.")!
  let c2 = DottedVersion("10..1.0")!
  let d1 = DottedVersion("9.0.1")!
  let invalidName = DottedVersion("1.this_should_be_nil.0.beta")

  func testEquality() {
    XCTAssertEqual(a1, a1)
    XCTAssertEqual(a1, a2)
    XCTAssertNotEqual(a1, b1)
    XCTAssertEqual(b1, b1)
    XCTAssertEqual(b1, b2)
    XCTAssertEqual(b1, b3)
    XCTAssertEqual(c1, c2)
    XCTAssertNotEqual(d1, a1)
  }

  func testComparison() {
    XCTAssertLessThan(a1, b3)
    XCTAssertGreaterThan(b1, a2)
    XCTAssertGreaterThan(d1, a1)
  }

  func testDescription() {
    XCTAssertEqual(a1.description, "9.0")
    XCTAssertEqual(a2.description, "9.0.0")
    XCTAssertEqual(b1.description, "10.0.1")
    XCTAssertEqual(b2.description, "10.0.1")
    XCTAssertEqual(b3.description, "10.0.1.0")
    XCTAssertEqual(c1.description, "10.0.1.0.0")
    XCTAssertEqual(c2.description, "10.0.1.0")
  }

  func testInvalidName() {
    XCTAssertNil(invalidName)
  }
}
