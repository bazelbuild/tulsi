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


// End to end tests that generate xcodeproj bundles and validate them against golden versions.
class EndToEndGenerationTests: EndToEndIntegrationTestCase {
  func test_SimpleProject() {
    let testDir = "tulsi_e2e_simple"
    installBUILDFile("Simple", intoSubdirectory: testDir)
    makeTestXCDataModel("SimpleDataModelsTestv1",
                        inSubdirectory: "\(testDir)/SimpleTest.xcdatamodeld")
    makeTestXCDataModel("SimpleDataModelsTestv2",
                        inSubdirectory: "\(testDir)/SimpleTest.xcdatamodeld")
    makePlistFileNamed(".xccurrentversion",
                       withContent: ["_XCCurrentVersionName": "SimpleDataModelsTestv1.xcdatamodel"],
                       inSubdirectory: "\(testDir)/SimpleTest.xcdatamodeld")

    let appLabel = BuildLabel("//\(testDir):Application")
    let hostLabels = Set<BuildLabel>([appLabel])
    let buildTargets = [RuleInfo(label: appLabel,
                                 type: "ios_application",
                                 linkedTargetLabels: Set<BuildLabel>()),
                        RuleInfo(label: BuildLabel("//\(testDir):XCTest"),
                                 type: "ios_test",
                                 linkedTargetLabels: hostLabels)]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    guard let projectURL = generateProjectNamed("SimpleProject",
                                                buildTargets: buildTargets,
                                                pathFilters: ["\(testDir)/..."],
                                                additionalFilePaths: additionalFilePaths,
                                                outputDir: "tulsi_e2e_output/") else {
      // The test has already been marked as failed.
      return
    }

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: "SimpleProject")
    validateDiff(diffLines)
  }

  func test_ComplexSingleProject() {
    let testDir = "tulsi_e2e_complex"
    installBUILDFile("ComplexSingle", intoSubdirectory: testDir)
    makeTestXCDataModel("DataModelsTestv1", inSubdirectory: "\(testDir)/Test.xcdatamodeld")
    makeTestXCDataModel("DataModelsTestv2", inSubdirectory: "\(testDir)/Test.xcdatamodeld")
    makePlistFileNamed(".xccurrentversion",
                       withContent: ["_XCCurrentVersionName": "DataModelsTestv2.xcdatamodel"],
                       inSubdirectory: "\(testDir)/Test.xcdatamodeld")

    let appLabel = BuildLabel("//\(testDir):Application")
    let hostLabels = Set<BuildLabel>([appLabel])
    let buildTargets = [RuleInfo(label: appLabel,
                                 type: "ios_application",
                                 linkedTargetLabels: Set<BuildLabel>()),
                        RuleInfo(label: BuildLabel("//\(testDir):XCTest"),
                                 type: "ios_test",
                                 linkedTargetLabels: hostLabels),
                        RuleInfo(label: BuildLabel("//\(testDir):TodayExtension"),
                                 type: "ios_extension",
                                 linkedTargetLabels: Set<BuildLabel>()),
                        RuleInfo(label: BuildLabel("//\(testDir):WatchExtension"),
                                 type: "apple_watch1_extension",
                                 linkedTargetLabels: Set<BuildLabel>())]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    guard let projectURL = generateProjectNamed("ComplexSingleProject",
                                                buildTargets: buildTargets,
                                                pathFilters: ["\(testDir)/...",
                                                              "bazel-bin/...",
                                                              "bazel-genfiles/..."],
                                                additionalFilePaths: additionalFilePaths,
                                                outputDir: "tulsi_e2e_output/") else {
      // The test has already been marked as failed.
      return
    }

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: "ComplexSingleProject")
    validateDiff(diffLines)
  }
}

// End to end tests that generate xcodeproj bundles and validate them against golden versions.
class TestSuiteEndToEndGenerationTests: EndToEndIntegrationTestCase {
  let testDir = "TestSuite"
  let appRule = RuleInfo(label: BuildLabel("//TestSuite:TestApplication"),
                         type: "ios_application",
                         linkedTargetLabels: Set<BuildLabel>())

  override func setUp() {
    super.setUp()

    installBUILDFile("TestSuiteRoot",
                     intoSubdirectory: testDir,
                     fromResourceDirectory: "TestSuite")
    installBUILDFile("TestOne",
                     intoSubdirectory: "\(testDir)/One",
                     fromResourceDirectory: "TestSuite/One")
    installBUILDFile("TestTwo",
                     intoSubdirectory: "\(testDir)/Two",
                     fromResourceDirectory: "TestSuite/Two")
    installBUILDFile("TestThree",
                     intoSubdirectory: "\(testDir)/Three",
                     fromResourceDirectory: "TestSuite/Three")
  }

  func test_ExplicitXCTestsProject() {
    let buildTargets = [
        appRule,
        RuleInfo(label: BuildLabel("//\(testDir):explicit_XCTests"),
                 type: "test_suite",
                 linkedTargetLabels: Set<BuildLabel>()),
    ]

    guard let projectURL = generateProjectNamed("TestSuiteExplicitXCTestsProject",
                                                buildTargets: buildTargets,
                                                pathFilters: ["\(testDir)/..."],
                                                outputDir: "tulsi_e2e_output/") else {
      // The test has already been marked as failed.
      return
    }

    let diffLines = diffProjectAt(projectURL,
                                  againstGoldenProject: "TestSuiteExplicitXCTestsProject")
    validateDiff(diffLines)
  }

  func test_TestSuiteLocalTaggedTestsProject() {
    let buildTargets = [
        appRule,
        RuleInfo(label: BuildLabel("//\(testDir):local_tagged_tests"),
                 type: "test_suite",
                 linkedTargetLabels: Set<BuildLabel>()),
    ]

    guard let projectURL = generateProjectNamed("TestSuiteLocalTaggedTestsProject",
                                                buildTargets: buildTargets,
                                                pathFilters: ["\(testDir)/..."],
                                                outputDir: "tulsi_e2e_output/") else {
      // The test has already been marked as failed.
      return
    }

    let diffLines = diffProjectAt(projectURL,
                                  againstGoldenProject: "TestSuiteLocalTaggedTestsProject")
    validateDiff(diffLines)
  }

  func test_TestSuiteRecursiveTestSuiteProject() {
    let buildTargets = [
        appRule,
        RuleInfo(label: BuildLabel("//\(testDir):recursive_test_suite"),
                 type: "test_suite",
                 linkedTargetLabels: Set<BuildLabel>()),
    ]

    guard let projectURL = generateProjectNamed("TestSuiteRecursiveTestSuiteProject",
                                                buildTargets: buildTargets,
                                                pathFilters: ["\(testDir)/..."],
                                                outputDir: "tulsi_e2e_output/") else {
      // The test has already been marked as failed.
      return
    }

    let diffLines = diffProjectAt(projectURL,
                                  againstGoldenProject: "TestSuiteRecursiveTestSuiteProject")
    validateDiff(diffLines)
  }
}
