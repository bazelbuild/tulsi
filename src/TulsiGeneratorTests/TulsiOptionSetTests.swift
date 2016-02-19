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

class TulsiOptionSetTests: XCTestCase {
  var optionKeys = [TulsiOptionKey]()

  override func setUp() {
    super.setUp()
    let optionSet = TulsiOptionSet()
    optionKeys = Array(optionSet.options.keys)
  }

  // MARK: - Tests

  func testPersistenceIsReversible() {
    let target1 = "Target1"
    let target2 = "Target2"
    let optionSet = TulsiOptionSet()
    optionSet[.SDKROOT].projectValue = "SDKROOT!"
    optionSet[.ALWAYS_SEARCH_USER_PATHS].projectValue = "YES"
    optionSet[.BazelBuildOptionsDebug].targetValues = [
        target1: "Target-Value1",
        target2: "Target-Value2",
    ]
    optionSet[.BazelBuildOptionsRelease].projectValue = "releaseProjectValue"
    optionSet[.BazelBuildOptionsRelease].targetValues = [
        target1: "Target-Release-Value1",
    ]
    var dict = [String: AnyObject]()
    optionSet.saveAllOptionsIntoDictionary(&dict)

    let optionsDict = TulsiOptionSet.getOptionsFromContainerDictionary(dict) ?? [:]
    let deserializedSet = TulsiOptionSet(fromDictionary: optionsDict)
    XCTAssertEqual(deserializedSet, optionSet)
  }

  func testPerUserOptionsAreOmitted() {
    let optionSet = TulsiOptionSet()
    var i = 0
    for (_, option) in optionSet.options {
      option.projectValue = String(i)
      i += 10
    }
    var dict = [String: AnyObject]()
    optionSet.saveShareableOptionsIntoDictionary(&dict)

    let optionsDict = TulsiOptionSet.getOptionsFromContainerDictionary(dict) ?? [:]
    let deserializedSet = TulsiOptionSet(fromDictionary: optionsDict)
    for (key, option) in optionSet.options.filter({ !$1.optionType.contains(.PerUserOnly) }) {
      XCTAssertEqual(deserializedSet[key], option)
    }
  }

  func testOnlyPerUserOptionsArePersisted() {
    let optionSet = TulsiOptionSet()
    var i = 0
    for (_, option) in optionSet.options {
      option.projectValue = String(i)
      i += 10
    }
    var dict = [String: AnyObject]()
    optionSet.savePerUserOptionsIntoDictionary(&dict)

    let perUserOptions = optionSet.options.filter({ $1.optionType.contains(.PerUserOnly) })
    let serializedValues = dict[TulsiOptionSet.PersistenceKey] as! [String: TulsiOption.PersistenceType]
    XCTAssertEqual(serializedValues.count, perUserOptions.count)

    let optionsDict = TulsiOptionSet.getOptionsFromContainerDictionary(dict) ?? [:]
    let deserializedSet = TulsiOptionSet(fromDictionary: optionsDict)
    for (key, option) in perUserOptions {
      XCTAssertEqual(deserializedSet[key], option)
    }
  }
}
