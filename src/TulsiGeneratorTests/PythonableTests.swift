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

class PythonableTests: XCTestCase {

  func testStringSimple() {
    XCTAssertEqual("foobar".toPython(""), "'foobar'")
    XCTAssertEqual("foobar".toPython("  "), "'foobar'")
    XCTAssertEqual("this is a string".toPython(""), "'this is a string'")
  }

  func testStringEscapesSingleQuotes() {
    XCTAssertEqual("foo'bar".toPython(""), "'foo\\'bar'")
    XCTAssertEqual("foo'bar".toPython("  "), "'foo\\'bar'")
    XCTAssertEqual("this''string".toPython(""), "'this\\'\\'string'")
  }

  func testArrayEmpty() {
    XCTAssertEqual([String]().toPython(""), "[]")
  }

  func testArrayOfStrings() {
    let arr = [
      "Hello",
      "Goodbye",
      "'Escape'",
    ]
    XCTAssertEqual(arr.toPython(""), """
[
    'Hello',
    'Goodbye',
    '\\'Escape\\'',
]
""")
    XCTAssertEqual(
      arr.toPython("  "), """
[
      'Hello',
      'Goodbye',
      '\\'Escape\\'',
  ]
""")
  }

  func testSetEmpty() {
    XCTAssertEqual(Set<String>().toPython(""), "set()")
  }

  func testStringSet() {
    let set: Set<String> = ["Hello"]
    XCTAssertEqual(set.toPython(""), """
set([
    'Hello',
])
""")
    XCTAssertEqual(set.toPython("  "), """
set([
      'Hello',
  ])
""")
  }

  func testDictionaryEmpty() {
    XCTAssertEqual([String: String]().toPython(""), "{}")
  }

  func testStringDictionary() {
    let dict = ["Type": "A"]
    XCTAssertEqual(dict.toPython(""), """
{
    'Type': 'A',
}
""")
    XCTAssertEqual(dict.toPython(" "), """
{
     'Type': 'A',
 }
""")
  }
}
