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
  var persister: MockPersister! = nil
  var optionKeys = [TulsiOptionKey]()

  override func setUp() {
    super.setUp()

    persister = MockPersister()

    let optionSet = TulsiOptionSet()
    optionKeys = Array(optionSet.options.keys)
  }

  // MARK: - Tests

  func testProjectValuesAreLoaded() {
    let expectedValues = generateTestValues()
    persister.projectValuesPerOption = expectedValues
    let optionSet = TulsiOptionSet(persister: persister)
    for (key, option) in optionSet.options {
      XCTAssertEqual(option.projectValue, expectedValues[key.rawValue]!, "Mismatch for option \(key)")
    }
  }

  func testTargetValuesAreLoaded() {
    let testTargets = ["one", "two", "three"]
    let expectedValues = generatePerTargetTestValues(testTargets)
    persister.targetValuesPerOption = expectedValues
    let optionSet = TulsiOptionSet(persister: persister)
    for (key, option) in optionSet.options {
      guard let targetValues = option.targetValues else {
        XCTFail("Target values not set for option \(key)")
        continue
      }
      let expectedValuesForOption = expectedValues[key.rawValue]!!
      for (target, value) in targetValues {
        XCTAssertNotNil(expectedValuesForOption[target],
                        "Target \(target) not expected for option \(key)")
        XCTAssertEqual(value,
                       expectedValuesForOption[target]!,
                       "Mismatch for target \(target) in option \(key)")
      }
    }
  }

  func testCommonBuildSettings() {
    persister.setProjectValue("100", forOptionKey: .IPHONEOS_DEPLOYMENT_TARGET)
    persister.setProjectValue("Hello", forOptionKey: .SDKROOT)
    let expectedBuildSettings = [
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "IPHONEOS_DEPLOYMENT_TARGET": "100",
        "SDKROOT": "Hello",
    ]

    let optionSet = TulsiOptionSet(persister: persister)
    let buildSettings = optionSet.commonBuildSettings()

    for (key, expectedValue) in expectedBuildSettings {
      XCTAssertEqual(buildSettings[key], expectedValue, "Mismatch for build setting \(key)")
    }
  }

  /// Returns a dictionary of build settings specialized for the given target.
  func testBuildSettingsForTarget() {
    let target = "Target"
    persister.setValue("path!", forTarget: target, optionKey: .USER_HEADER_SEARCH_PATHS)

    // IPHONEOS_DEPLOYMENT_TARGET is not target-specializable so any persisted target value
    // should be ignored.
    persister.setValue("1000", forTarget: target, optionKey: .IPHONEOS_DEPLOYMENT_TARGET)

    let expectedBuildSettings: [String: String?] = [
        "USER_HEADER_SEARCH_PATHS": "path!",
        "IPHONEOS_DEPLOYMENT_TARGET": nil,
    ]

    let optionSet = TulsiOptionSet(persister: persister)
    let buildSettings = optionSet.buildSettingsForTarget(target)

    for (key, expectedValue) in expectedBuildSettings {
      XCTAssertEqual(buildSettings[key], expectedValue, "Mismatch for build setting \(key)")
    }
  }

  func testDoesNotPersistDefaults() {
    class AssertingPersister: OptionPersisterProtocol {
      var loadProjectValuesCalled = false
      var loadTargetValuesCalled = false

      func saveProjectValue(value: String?, forStorageKey: String) {
        XCTFail("saveProjectValue:forStorageKey: was called")
      }

      func saveTargetValues(values: [String:String]?, forStorageKey: String) {
        XCTFail("saveTargetValues:forStorageKey: was called")
      }

      func loadProjectValueForStorageKey(storageKey: String) -> String? {
        loadProjectValuesCalled = true
        return nil
      }

      func loadTargetValueForStorageKey(storageKey: String) -> [String:String]? {
        loadTargetValuesCalled = true
        return nil
      }
    }

    let persister = AssertingPersister()
    let _ = TulsiOptionSet(persister: persister)
    XCTAssertTrue(persister.loadProjectValuesCalled, "loadProjectValueForStorageKey: must be called")
    XCTAssertTrue(persister.loadTargetValuesCalled, "loadTargetValueForStorageKey: must be called")
  }

  // MARK: - Private methods

  private func generateTestValues() -> [String: String?] {
    var expectedValues = [String: String?]()
    var value = 500
    for key in optionKeys {
      expectedValues[key.rawValue] = String(value)
      value += 1
    }

    return expectedValues
  }

  private func generatePerTargetTestValues(targets: [String]) -> [String: [String: String]?] {
    var expectedValues = [String: [String: String]?]()
    var value = 1000
    for key in optionKeys {
      var targetToValueMap = [String: String]()
      for target in targets {
        targetToValueMap[target] = String(value)
        value += 1
      }
      expectedValues[key.rawValue] = targetToValueMap
    }
    return expectedValues
  }
}


class MockPersister: OptionPersisterProtocol{
  var projectValuesPerOption = [String: String?]()
  var targetValuesPerOption = [String: [String: String]?]()

  func setProjectValue(value: String?, forOptionKey opt: TulsiOptionKey) {
    projectValuesPerOption[opt.rawValue] = value
  }

  func setValue(value: String, forTarget target: String, optionKey opt: TulsiOptionKey) {
    let optString = opt.rawValue
    if var targetValues = targetValuesPerOption[optString] where targetValues != nil {
      targetValues![target] = value
      targetValuesPerOption[optString] = targetValues
    } else {
      targetValuesPerOption[optString] = [target: value]
    }
  }

  // MARK: - OptionPersisterProtocol

  func saveProjectValue(value: String?, forStorageKey key: String) {
    projectValuesPerOption[key] = value
  }

  func saveTargetValues(values: [String:String]?, forStorageKey key: String) {
    targetValuesPerOption[key] = values
  }

  func loadProjectValueForStorageKey(storageKey: String) -> String? {
    return projectValuesPerOption[storageKey] ?? nil
  }

  func loadTargetValueForStorageKey(storageKey: String) -> [String:String]? {
    return targetValuesPerOption[storageKey] ?? nil
  }
}
