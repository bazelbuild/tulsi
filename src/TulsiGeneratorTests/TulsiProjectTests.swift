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


class TulsiProjectTests: XCTestCase {
  let projectName = "TestProject"
  let projectBundleURL = NSURL(fileURLWithPath: "/test/project/tulsiproject/")
  let workspaceRootURL = NSURL(fileURLWithPath: "/test/project/root/")
  // Relative path from projectBundleURL to workspaceRootURL.
  let relativeRootPath = "../root"
  let bazelPackages = [
      "some/package",
      "another/package",
      "package",
  ]

  var project: TulsiProject! = nil

  override func setUp() {
    super.setUp()
    project = TulsiProject(projectName: projectName,
                           projectBundleURL: projectBundleURL,
                           workspaceRootURL: workspaceRootURL,
                           bazelPackages: bazelPackages)
  }


  func testSave() {
    do {
      let data = try project.save()
      let dict = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions())
      XCTAssertEqual(dict["packages"], bazelPackages)
      XCTAssertEqual(dict["projectName"], projectName)
      XCTAssertEqual(dict["workspaceRoot"], relativeRootPath)
    } catch {
      XCTFail("Unexpected assertion")
    }
  }

  func testLoad() {
    do {
      let dict = [
        "packages": bazelPackages,
        "projectName": projectName,
        "workspaceRoot": relativeRootPath,
      ]
      let data = try NSJSONSerialization.dataWithJSONObject(dict, options: NSJSONWritingOptions())
      project = try TulsiProject(data: data, projectBundleURL: projectBundleURL)

      XCTAssertEqual(project.bazelPackages, bazelPackages)
      XCTAssertEqual(project.projectName, projectName)
      XCTAssertEqual(project.workspaceRootURL, workspaceRootURL)
    } catch {
      XCTFail("Unexpected assertion")
    }
  }

  func testLoadWithTrailingSlash() {
    do {
      let dict = [
        "packages": bazelPackages,
        "projectName": projectName,
        "workspaceRoot": relativeRootPath + "/",
      ]
      let data = try NSJSONSerialization.dataWithJSONObject(dict, options: NSJSONWritingOptions())
      project = try TulsiProject(data: data, projectBundleURL: projectBundleURL)

      XCTAssertEqual(project.bazelPackages, bazelPackages)
      XCTAssertEqual(project.projectName, projectName)
      XCTAssertEqual(project.workspaceRootURL, workspaceRootURL)
    } catch {
      XCTFail("Unexpected assertion")
    }
  }
}
