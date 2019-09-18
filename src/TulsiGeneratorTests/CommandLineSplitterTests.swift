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

class CommandLineSplitterTests: XCTestCase {
  var splitter: CommandLineSplitter! = nil

  override func setUp() {
    super.setUp()
    splitter = CommandLineSplitter()
  }

  func testSimpleArgs() {
    checkSplit("", [])

    checkSplit("'broken \"", nil)
    checkSplit("\"broken ", nil)

    checkSplit("\"\"", [""])
    checkSplit("Single", ["Single"])
    checkSplit("one two", ["one", "two"])
  }

  func testQuotedArgs() {
    checkSplit("one 'two single quoted'", ["one", "two single quoted"])
    checkSplit("one \"two double quoted\"", ["one", "two double quoted"])
    checkSplit("one \"two double quoted\"", ["one", "two double quoted"])

    checkSplit("one=one \"two double quoted\"", ["one=one", "two double quoted"])
    checkSplit("\"a=b=c\" \"two double quoted\"", ["a=b=c", "two double quoted"])
    checkSplit("\"a=\\\"b = c\\\"\" \"two double quoted\"", ["a=\"b = c\"", "two double quoted"])

    checkSplit("\"quoted text       \"", ["quoted text       "])
    checkSplit("'quoted text       '", ["quoted text       "])
  }

  // MARK: - Private methods

  private func checkSplit(_ commandLine: String, _ expected: [String]?, line: UInt = #line) {
    let split = splitter.splitCommandLine(commandLine)
    if expected == nil {
      XCTAssertNil(split, line: line)
      return
    }
    XCTAssertNotNil(split, line: line)
    if let split = split {
      XCTAssertEqual(split, expected!, line: line)
    }
  }
}
