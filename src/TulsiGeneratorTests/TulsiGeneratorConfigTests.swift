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
  let projectBundleURL = URL(fileURLWithPath: "/test/project/tulsiproject/")
  let projectBazelURL = URL(fileURLWithPath: "/test/project/path/to/bazel")
  let workspaceRootURL = URL(fileURLWithPath: "/test/project/root/")

  let bazelPackages = [
    "a/package",
    "b/where/are/we",
    "missingno/c",
  ]

  let buildTargetLabels = ["build/target/label:1", "build/target/label:2"]

  let pathFilters = Set<String>([
    "build/target/path/1",
    "build/target/path/2",
    "source/target/path"
  ])

  let additionalFilePaths = ["path/to/file", "path/to/another/file"]

  var project: TulsiProject! = nil

  override func setUp() {
    super.setUp()
    project = TulsiProject(
      projectName: projectName,
      projectBundleURL: projectBundleURL,
      workspaceRootURL: workspaceRootURL,
      bazelPackages: bazelPackages)
    project.bazelURL = projectBazelURL
  }

  func testSave() {
    do {
      let bazelURL = TulsiParameter(
        value: URL(fileURLWithPath: ""),
        source: .explicitlyProvided)
      let config = TulsiGeneratorConfig(
        projectName: projectName,
        buildTargetLabels: buildTargetLabels.map({ BuildLabel($0) }),
        pathFilters: pathFilters,
        additionalFilePaths: additionalFilePaths,
        options: TulsiOptionSet(),
        bazelURL: bazelURL)
      let data = try config.save()
      let dict = try JSONSerialization.jsonObject(
        with: data as Data, options: JSONSerialization.ReadingOptions()) as! [String: Any]
      XCTAssertEqual(dict["additionalFilePaths"] as! [String], additionalFilePaths)
      XCTAssertEqual(dict["buildTargets"] as! [String], buildTargetLabels)
      XCTAssertEqual(dict["projectName"] as! String, projectName)
      XCTAssertEqual(dict["sourceFilters"] as! [String], [String](pathFilters).sorted())
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
      ] as [String: Any]
      let data = try JSONSerialization.data(
        withJSONObject: dict, options: JSONSerialization.WritingOptions())
      let bazelURL = URL(fileURLWithPath: "/path/to/bazel")
      let config = try TulsiGeneratorConfig(data: data, bazelURL: bazelURL)

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
      let sourceFilters = pathFilters.map { "//\($0)" }
      let dict = [
        "additionalFilePaths": additionalFilePaths,
        "buildTargets": buildTargetLabels,
        "projectName": projectName,
        "sourceFilters": sourceFilters,
      ] as [String: Any]
      let data = try JSONSerialization.data(
        withJSONObject: dict, options: JSONSerialization.WritingOptions())
      let bazelURL = URL(fileURLWithPath: "/path/to/bazel")
      let config = try TulsiGeneratorConfig(data: data, bazelURL: bazelURL)

      XCTAssertEqual(config.additionalFilePaths ?? [], additionalFilePaths)
      XCTAssertEqual(config.buildTargetLabels, buildTargetLabels.map({ BuildLabel($0) }))
      XCTAssertEqual(config.projectName, projectName)
      XCTAssertEqual(config.pathFilters, pathFilters)
    } catch {
      XCTFail("Unexpected assertion")
    }
  }

  func testLoadWithInvalidAdditionalFilePaths() {
    do {
      let dict = [
        "additionalFilePaths": ["//path/to/file"],
        "buildTargets": buildTargetLabels,
        "projectName": projectName,
      ] as [String: Any]
      let data = try JSONSerialization.data(
        withJSONObject: dict, options: JSONSerialization.WritingOptions())
      _ = try TulsiGeneratorConfig(data: data)

      XCTFail("Unexpectedly succeeded with an invalid file path")
    } catch TulsiGeneratorConfig.ConfigError.deserializationFailed(let message) {
      XCTAssert(message.contains("//path/to/file"))
    } catch {
      XCTFail("Unexpected assertion")
    }
  }

  func testExplicitlyProvidedURL() {
    do {
      let dict = [
        "projectName": projectName,
      ] as [String: Any]
      let data = try JSONSerialization.data(
        withJSONObject: dict, options: JSONSerialization.WritingOptions())
      let bazelURL = URL(fileURLWithPath: "/path/to/bazel")
      let config = try TulsiGeneratorConfig(data: data, bazelURL: bazelURL)

      XCTAssertEqual(config.bazelURL, bazelURL)
    } catch {
      XCTFail("Unexpected assertion")
    }
  }

  func testExplicitlyProvidedURLOverridesProjectAndOptionsSetting() {
    do {
      let dict = [
        "projectName": projectName,
      ] as [String: Any]
      let data = try JSONSerialization.data(
        withJSONObject: dict, options: JSONSerialization.WritingOptions())
      let bazelURL = URL(fileURLWithPath: "/path/to/bazel")
      let optionsURL = URL(fileURLWithPath: "/options/path/to/bazel")
      let options = [
        "optionSet": ["BazelPath": ["p": optionsURL.path]],
      ] as [String: Any]
      let optionData = try JSONSerialization.data(
        withJSONObject: options, options: JSONSerialization.WritingOptions())

      var config = try TulsiGeneratorConfig(
        data: data,
        additionalOptionData: optionData,
        bazelURL: bazelURL)
      config = config.configByResolvingInheritedSettingsFromProject(project)

      XCTAssertEqual(config.bazelURL, bazelURL)
    } catch {
      XCTFail("Unexpected assertion")
    }
  }

  func testOptionsURL() {
    do {
      let dict = [
        "projectName": projectName,
      ] as [String: Any]
      let data = try JSONSerialization.data(
        withJSONObject: dict, options: JSONSerialization.WritingOptions())

      let optionsURL = URL(fileURLWithPath: "/options/path/to/bazel")
      let options = [
        "optionSet": ["BazelPath": ["p": optionsURL.path]],
      ] as [String: Any]
      let optionData = try JSONSerialization.data(
        withJSONObject: options, options: JSONSerialization.WritingOptions())

      let config = try TulsiGeneratorConfig(
        data: data,
        additionalOptionData: optionData)
      XCTAssertEqual(config.bazelURL, optionsURL)
    } catch {
      XCTFail("Unexpected assertion")
    }
  }

  func testOptionsURLOverridesProjectSetting() {
    do {
      let dict = [
        "projectName": projectName,
      ] as [String: Any]
      let data = try JSONSerialization.data(
        withJSONObject: dict, options: JSONSerialization.WritingOptions())

      let optionsURL = URL(fileURLWithPath: "/options/path/to/bazel")
      let options = [
        "optionSet": ["BazelPath": ["p": optionsURL.path]],
      ] as [String: Any]
      let optionData = try JSONSerialization.data(
        withJSONObject: options, options: JSONSerialization.WritingOptions())

      var config = try TulsiGeneratorConfig(
        data: data,
        additionalOptionData: optionData)
      config = config.configByResolvingInheritedSettingsFromProject(project)
      XCTAssertEqual(config.bazelURL, optionsURL)
    } catch {
      XCTFail("Unexpected assertion")
    }
  }
}
