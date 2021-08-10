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
@testable import BazelIntegrationTestCase
@testable import EndToEndIntegrationTestCase
@testable import TulsiGenerator


// End to end tests that generate xcodeproj bundles and validate them against golden versions.
class EndToEndGenerationTests: EndToEndIntegrationTestCase {
  func test_SimpleProject() throws {
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
    let targetLabel = BuildLabel("//\(testDir):TargetApplication")
    let buildTargets = [RuleInfo(label: appLabel,
                                 type: "ios_application",
                                 linkedTargetLabels: []),
                        RuleInfo(label: targetLabel,
                                 type: "ios_application",
                                 linkedTargetLabels: []),
                        RuleInfo(label: BuildLabel("//\(testDir):AllTests"),
                                 type: "test_suite",
                                 linkedTargetLabels: [])]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    let projectName = "SimpleProject"

    let options = TulsiOptionSet()
    options.options[.BazelContinueBuildingAfterError]?.projectValue = "YES"

    options.options[.CommandlineArguments]?.projectValue = "--project-flag"
    options.options[.CommandlineArguments]?.targetValues?[targetLabel.value] = "--target-specific-test-flag"

    options.options[.EnvironmentVariables]?.projectValue = "projectKey=projectValue"
    options.options[.EnvironmentVariables]?.targetValues?[targetLabel.value] =
        "targetKey1=targetValue1\ntargetKey2=targetValue2=\ntargetKey3="

    options.options[.BuildActionPreActionScript]?.projectValue = "This is a build pre action script"
    options.options[.BuildActionPreActionScript]?.targetValues?[targetLabel.value] = "This is a target specific build pre action script"
    options.options[.BuildActionPostActionScript]?.projectValue = "This is a build post action script"
    options.options[.BuildActionPostActionScript]?.targetValues?[targetLabel.value] = "This is a target specific build post action script"

    options.options[.LaunchActionPreActionScript]?.projectValue = "This is a lauch pre action script"
    options.options[.LaunchActionPreActionScript]?.targetValues?[targetLabel.value] = "This is a target specific launch pre action script"
    options.options[.LaunchActionPostActionScript]?.projectValue = "This is a launch post action script"
    options.options[.LaunchActionPostActionScript]?.targetValues?[targetLabel.value] = "This is a target specific launch post action script"

    options.options[.TestActionPreActionScript]?.projectValue = "This is a test pre action script"
    options.options[.TestActionPreActionScript]?.targetValues?[targetLabel.value] = "This is a target specific test pre action script"
    options.options[.TestActionPostActionScript]?.projectValue = "This is a test post action script"
    options.options[.TestActionPostActionScript]?.targetValues?[targetLabel.value] = "This is a target specific test post action script"

    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/..."],
                                              additionalFilePaths: additionalFilePaths,
                                              outputDir: "tulsi_e2e_output",
                                              options: options)

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }

  func test_MultiExtensionProject() throws {
    let testDir = "tulsi_e2e_multi_extension"
    installBUILDFile("MultiExtension", intoSubdirectory: testDir)

    let appLabelOne = BuildLabel("//\(testDir):ApplicationOne")
    let appLabelTwo = BuildLabel("//\(testDir):ApplicationTwo")
    let buildTargets = [RuleInfo(label: appLabelOne,
                                 type: "ios_application",
                                 linkedTargetLabels: []),
                        RuleInfo(label: appLabelTwo,
                                 type: "ios_application",
                                 linkedTargetLabels: [])]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    makePlistFileNamed("Plist1.plist",
                       withContent: ["NSExtension": ["NSExtensionPointIdentifier": "com.apple.extension-foo"],
                                     "CFBundleVersion": "1.0",
                                     "CFBundleShortVersionString": "1.0"],
                       inSubdirectory: "\(testDir)/TodayExtension")

    let projectName = "MultiExtensionProject"
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/...",
                                                "bazel-bin/...",
                                                "bazel-genfiles/..."],
                                              additionalFilePaths: additionalFilePaths,
                                              outputDir: "tulsi_e2e_output")

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }

  func test_AppClipProject() throws {
    let testDir = "tulsi_e2e_app_clip"
    installBUILDFile("AppClip", intoSubdirectory: testDir)

    let appLabel = BuildLabel("//\(testDir):Application")
    let buildTargets = [RuleInfo(label: appLabel,
                                 type: "ios_application",
                                 linkedTargetLabels: [])]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    let projectName = "AppClipProject"
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/...",
                                                            "bazel-bin/...",
                                                            "bazel-genfiles/..."],
                                              additionalFilePaths: additionalFilePaths,
                                              outputDir: "tulsi_e2e_output")

    try validateBuildCommandForProject(projectURL, targets: [appLabel.value])

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }

  func test_BrokenSourceBUILD() {
    let aspectLogExpectation = expectation(description:
      "Should see a statement that Bazel aspect info is being printed to our logs."
    )
    let observerName = NSNotification.Name(rawValue: TulsiMessageNotification)
    let observer = NotificationCenter.default.addObserver(forName: observerName,
                                                          object: nil,
                                                          queue: nil) {
      notification in
      guard let item = LogMessage(notification: notification),
          item.message == "Log of Bazel aspect info output follows:" &&
          item.level == .Info else {
        return
      }
      aspectLogExpectation.fulfill()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let testDir = "tulsi_e2e_broken_build"
    installBUILDFile("SimpleBad", intoSubdirectory: testDir)

    let appLabel = BuildLabel("//\(testDir):Application")
    let buildTargets = [RuleInfo(label: appLabel,
                                 type: "ios_application",
                                 linkedTargetLabels: [])]

    do {
      _ = try generateProjectNamed("BrokenSourceBuildProject",
                                   buildTargets: buildTargets,
                                   pathFilters: ["\(testDir)/...",
                                                 "bazel-bin/...",
                                                 "bazel-genfiles/..."],
                                   outputDir: "tulsi_e2e_output")
    } catch Error.projectGenerationFailure(let info) {
      // Expected failure on malformed BUILD file.
      XCTAssertEqual(info, "General failure: Bazel aspects could not be built.")
      waitForExpectations(timeout: 0.0, handler: nil)
      return
    } catch Error.testSubdirectoryNotCreated {
      XCTFail("Failed to create output folder, aborting test.")
    } catch Error.userBuildScriptInvocationFailure(let info) {
      XCTFail("Failed to invoke user_build.py script. Context: \(info)")
    } catch let error {
      XCTFail("Unexpected failure: \(error)")
    }
    XCTFail("Expected exception of type 'BazelAspectInfoExtractor.ExtractorError.buildFailed' " +
      "to be thrown for bazel aspect build error.")
  }

  func test_ComplexSingleProject() throws {
    let testDir = "tulsi_e2e_complex"
    installBUILDFile("ComplexSingle", intoSubdirectory: testDir)
    makeTestXCDataModel("DataModelsTestv1", inSubdirectory: "\(testDir)/Test.xcdatamodeld")
    makeTestXCDataModel("DataModelsTestv2", inSubdirectory: "\(testDir)/Test.xcdatamodeld")
    makePlistFileNamed(".xccurrentversion",
                       withContent: ["_XCCurrentVersionName": "DataModelsTestv2.xcdatamodel"],
                       inSubdirectory: "\(testDir)/Test.xcdatamodeld")
    // iOS extension's Info.plist is generated by the Aspect after reading the infoplists listed in
    // the attribute, so we'll need to generate them otherwise extraction will fail.
    makePlistFileNamed("Plist1.plist",
                       withContent: ["NSExtension": ["NSExtensionPointIdentifier": "com.apple.extension-foo"],
                                     "CFBundleVersion": "1.0",
                                     "CFBundleShortVersionString": "1.0"],
                       inSubdirectory: "\(testDir)/TodayExtension")

    let appLabel = BuildLabel("//\(testDir):Application")
    let hostLabels = Set<BuildLabel>([appLabel])
    let buildTargets = [RuleInfo(label: appLabel,
                                 type: "ios_application",
                                 linkedTargetLabels: []),
                        RuleInfo(label: BuildLabel("//\(testDir):XCTest"),
                                 type: "ios_unit_test",
                                 linkedTargetLabels: hostLabels)]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    let projectName = "ComplexSingleProject"

    let projectOptions = TulsiOptionSet()
    projectOptions[.IncludeBuildSources].projectValue = "YES"
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/...",
                                                            "bazel-bin/...",
                                                            "bazel-genfiles/..."],
                                              additionalFilePaths: additionalFilePaths,
                                              outputDir: "tulsi_e2e_output",
                                              options: projectOptions)

    try validateBuildCommandForProject(projectURL, options: projectOptions, targets: [appLabel.value])

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }

  func test_SwiftProject() throws {
    let testDir = "tulsi_e2e_swift"
    installBUILDFile("Swift", intoSubdirectory: testDir)

    let appLabel = BuildLabel("//\(testDir):Application")
    let buildTargets = [RuleInfo(label: appLabel,
                                 type: "ios_application",
                                 linkedTargetLabels: [])]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    let projectName = "SwiftProject"
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/...",
                                                            "bazel-bin/...",
                                                            "bazel-genfiles/..."],
                                              additionalFilePaths: additionalFilePaths,
                                              outputDir: "tulsi_e2e_output")

    try validateBuildCommandForProject(projectURL, swift: true, targets: [appLabel.value])

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }

  func test_watchProject() throws {
    let testDir = "tulsi_e2e_watch"
    installBUILDFile("Watch", intoSubdirectory: testDir)

    let appLabel = BuildLabel("//\(testDir):Application")
    let buildTargets = [RuleInfo(label: appLabel,
                                 type: "ios_application",
                                 linkedTargetLabels: [])]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    let projectName = "WatchProject"
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/...",
                                                            "bazel-bin/...",
                                                            "bazel-genfiles/..."],
                                              additionalFilePaths: additionalFilePaths,
                                              outputDir: "tulsi_e2e_output")

    try validateBuildCommandForProject(projectURL, targets: [appLabel.value])

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }

  func test_tvOSProject() throws {
    let testDir = "tulsi_e2e_tvos_project"
    installBUILDFile("ComplexSingle", intoSubdirectory: testDir)

    let appLabel = BuildLabel("//\(testDir):tvOSApplication")
    let buildTargets = [RuleInfo(label: appLabel,
                                 type: "tvos_application",
                                 linkedTargetLabels: [])
    ]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    let projectName = "SkylarkBundlingProject"
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/...",
                                                            "bazel-bin/\(testDir)/...",
                                                            "bazel-genfiles/\(testDir)/..."],
                                              additionalFilePaths: additionalFilePaths,
                                              outputDir: "tulsi_e2e_output")

    try validateBuildCommandForProject(projectURL, targets: [appLabel.value])

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }

  func test_macProject() throws {
    let testDir = "tulsi_e2e_mac"
    installBUILDFile("Mac", intoSubdirectory: testDir)

    let appLabel = BuildLabel("//\(testDir):MyMacOSApp")
    let commandLineAppLabel = BuildLabel("//\(testDir):MyCommandLineApp")
    let buildTargets = [RuleInfo(label: appLabel,
                                 type: "macos_application",
                                 linkedTargetLabels: []),
                        RuleInfo(label: commandLineAppLabel,
                                 type: "macos_command_line_application",
                                 linkedTargetLabels: [])]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    let projectName = "MacOSProject"
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/...",
                                                            "bazel-bin/...",
                                                            "bazel-genfiles/..."],
                                              additionalFilePaths: additionalFilePaths,
                                              outputDir: "tulsi_e2e_output")

    try validateBuildCommandForProject(projectURL, targets: [appLabel.value])

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }

  func test_macTestsProject() throws {
    let testDir = "tulsi_e2e_mac"
    installBUILDFile("Mac", intoSubdirectory: testDir)

    let appLabel = BuildLabel("//\(testDir):MyMacOSApp")
    let unitTestsLabel = BuildLabel("//\(testDir):UnitTests")
    let unitTestsNoHostLabel = BuildLabel("//\(testDir):UnitTestsNoHost")
    let uiTestsLabel = BuildLabel("//\(testDir):UITests")
    let hostLabels = Set<BuildLabel>([appLabel])
    let buildTargets = [RuleInfo(label: unitTestsLabel,
                                 type: "macos_unit_test",
                                 linkedTargetLabels: hostLabels),
                        RuleInfo(label: unitTestsNoHostLabel,
                                 type: "macos_unit_test",
                                 linkedTargetLabels: []),
                        RuleInfo(label: uiTestsLabel,
                                 type: "macos_ui_test",
                                 linkedTargetLabels: hostLabels)]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    let projectName = "MacOSTestsProject"
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/...",
                                                            "bazel-bin/...",
                                                            "bazel-genfiles/..."],
                                              additionalFilePaths: additionalFilePaths,
                                              outputDir: "tulsi_e2e_output")

    try validateBuildCommandForProject(projectURL, targets: [appLabel.value])

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }

  func test_simpleCCProject() throws {
    let testDir = "tulsi_e2e_ccsimple"
    let appLabel = BuildLabel("//\(testDir):ccBinary")
    installBUILDFile("Simple", intoSubdirectory: testDir)
    let buildTargets = [RuleInfo(label: appLabel,
                                 type: "cc_binary",
                                 linkedTargetLabels: [])]
    let additionalFilePaths = ["\(testDir)/BUILD"]

    let projectName = "SimpleCCProject"
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/..."],
                                              additionalFilePaths: additionalFilePaths,
                                              outputDir: "tulsi_e2e_output")

    try validateBuildCommandForProject(projectURL, targets: [appLabel.value])

    let diffLines = diffProjectAt(projectURL, againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }
}

// End to end tests that generate xcodeproj bundles and validate them against golden versions.
class TestSuiteEndToEndGenerationTests: EndToEndIntegrationTestCase {
  let testDir = "TestSuite"
  let appRule = RuleInfo(label: BuildLabel("//TestSuite:TestApplication"),
                         type: "ios_application",
                         linkedTargetLabels: [])

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

  func test_ExplicitXCTestsProject() throws {
    let buildTargets = [
        appRule,
        RuleInfo(label: BuildLabel("//\(testDir):explicit_XCTests"),
                 type: "test_suite",
                 linkedTargetLabels: []),
    ]

    let projectName = "TestSuiteExplicitXCTestsProject"
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/..."],
                                              outputDir: "tulsi_e2e_output")

    let diffLines = diffProjectAt(projectURL,
                                  againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }

  func test_TestSuiteLocalTaggedTestsProject() throws {
    let buildTargets = [
        appRule,
        RuleInfo(label: BuildLabel("//\(testDir):local_tagged_tests"),
                 type: "test_suite",
                 linkedTargetLabels: []),
    ]

    let projectName = "TestSuiteLocalTaggedTestsProject"
    let options = TulsiOptionSet()
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/..."],
                                              outputDir: "tulsi_e2e_output",
                                              options: options)

    let diffLines = diffProjectAt(projectURL,
                                  againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }

  func test_TestSuiteRecursiveTestSuiteProject() throws {
    let buildTargets = [
        appRule,
        RuleInfo(label: BuildLabel("//\(testDir):recursive_test_suite"),
                 type: "test_suite",
                 linkedTargetLabels: []),
    ]

    let projectName = "TestSuiteRecursiveTestSuiteProject"
    let options = TulsiOptionSet()
    let projectURL = try generateProjectNamed(projectName,
                                              buildTargets: buildTargets,
                                              pathFilters: ["\(testDir)/..."],
                                              outputDir: "tulsi_e2e_output",
                                              options: options)

    let diffLines = diffProjectAt(projectURL,
                                  againstGoldenProject: projectName)
    validateDiff(diffLines, for: projectName)
  }
}
