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


class TulsiGeneratorConfigTests: XCTestCase {
  let projectName = "TestProject"
  let buildTargetLabels = ["build/target/label:1", "build/target/label:2"]
  let pathFilters = Set<String>(["build/target/path/1",
                                 "build/target/path/2",
                                 "source/target/path"])
  let additionalFilePaths = ["path/to/file", "path/to/another/file"]

  var config: TulsiGeneratorConfig! = nil

  override func setUp() {
    super.setUp()
    config = TulsiGeneratorConfig(projectName: projectName,
                                  buildTargetLabels: buildTargetLabels.map({ BuildLabel($0) }),
                                  pathFilters: pathFilters,
                                  additionalFilePaths: additionalFilePaths,
                                  options: TulsiOptionSet(),
                                  bazelURL: NSURL())
  }

  func testSave() {
    do {
      let data = try config.save()
      let dict = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions())
      XCTAssertEqual(dict["additionalFilePaths"], additionalFilePaths)
      XCTAssertEqual(dict["buildTargets"], buildTargetLabels)
      XCTAssertEqual(dict["projectName"], projectName)
      XCTAssertEqual(dict["sourceFilters"], [String](pathFilters).sort())
    } catch {
      XCTFail("Unexpected assertion")
    }
  }

  func testLoad() {
    do {
      let dict = [
          "additionalFilePaths": additionalFilePaths,
          "buildTargets": buildTargetLabels,
          "projectName": projectName,
          "sourceFilters": [String](pathFilters),
      ]
      let data = try NSJSONSerialization.dataWithJSONObject(dict, options: NSJSONWritingOptions())
      config = try TulsiGeneratorConfig(data: data)

      XCTAssertEqual(config.additionalFilePaths ?? [], additionalFilePaths)
      XCTAssertEqual(config.buildTargetLabels, buildTargetLabels.map({ BuildLabel($0) }))
      XCTAssertEqual(config.projectName, projectName)
      XCTAssertEqual(config.pathFilters, pathFilters)
    } catch {
      XCTFail("Unexpected assertion")
    }
  }

  func testLoadWithBuildLabelSourceFilters() {
    do {
      var sourceFilters = pathFilters.map() { "//\($0)" }
      let dict = [
          "additionalFilePaths": additionalFilePaths,
          "buildTargets": buildTargetLabels,
          "projectName": projectName,
          "sourceFilters": sourceFilters,
      ]
      let data = try NSJSONSerialization.dataWithJSONObject(dict, options: NSJSONWritingOptions())
      config = try TulsiGeneratorConfig(data: data)

      XCTAssertEqual(config.additionalFilePaths ?? [], additionalFilePaths)
      XCTAssertEqual(config.buildTargetLabels, buildTargetLabels.map({ BuildLabel($0) }))
      XCTAssertEqual(config.projectName, projectName)
      XCTAssertEqual(config.pathFilters, pathFilters)
    } catch {
      XCTFail("Unexpected assertion")
    }
  }
}
