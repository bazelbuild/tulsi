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

  func testInheritance() {
    let parentValue = "ParentValue"
    let parent = TulsiOptionSet()
    parent[.BazelBuildOptionsDebug].projectValue = parentValue
    parent[.BazelBuildOptionsFastbuild].projectValue = parentValue
    parent[.BazelBuildOptionsRelease].projectValue = parentValue
    parent[.BazelBuildStartupOptionsDebug].projectValue = parentValue
    parent[.BazelBuildStartupOptionsFastbuild].projectValue = parentValue
    parent[.BazelBuildStartupOptionsRelease].projectValue = parentValue
    parent[.ALWAYS_SEARCH_USER_PATHS].projectValue = "YES"
    parent[.SuppressSwiftUpdateCheck].projectValue = "NO"


    let childValue = "ChildValue"
    let child = TulsiOptionSet(withInheritanceEnabled: true)
    child[.BazelBuildOptionsDebug].projectValue = childValue
    child[.BazelBuildOptionsFastbuild].projectValue = "$(inherited) \(childValue)"
    child[.BazelBuildOptionsRelease].projectValue = "\(childValue) $(inherited)"
    child[.BazelBuildStartupOptionsDebug].targetValues?["test"] = childValue
    child[.BazelBuildStartupOptionsFastbuild].targetValues?["test"] = "\(childValue) $(inherited)"
    child[.SuppressSwiftUpdateCheck].projectValue = "YES"

    let merged = child.optionSetByInheritingFrom(parent)
    XCTAssertEqual(merged[.BazelBuildOptionsDebug].commonValue, childValue)
    XCTAssertEqual(merged[.BazelBuildOptionsFastbuild].commonValue, "\(parentValue) \(childValue)")
    XCTAssertEqual(merged[.BazelBuildOptionsRelease].commonValue, "\(childValue) \(parentValue)")
    XCTAssertEqual(merged[.BazelBuildStartupOptionsDebug].targetValues?["test"], childValue)
    XCTAssertEqual(merged[.BazelBuildStartupOptionsFastbuild].targetValues?["test"], "\(childValue) \(parentValue)")
    XCTAssertEqual(merged[.BazelBuildStartupOptionsFastbuild].commonValue, parentValue)
    XCTAssertEqual(merged[.ALWAYS_SEARCH_USER_PATHS].commonValueAsBool, true)
    XCTAssertEqual(merged[.SuppressSwiftUpdateCheck].commonValueAsBool, true)
  }
}
