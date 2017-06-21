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

// Note: Rather than test the serializer's output, we make use of the knowledge that
// buildSerializerWithRuleEntries modifies a project directly.
class PBXTargetGeneratorTests: XCTestCase {
  let bazelURL = URL(fileURLWithPath: "__BAZEL_BINARY_")
  let workspaceRootURL = URL(fileURLWithPath: "/workspaceRootURL", isDirectory: true)
  let stubPlistPaths = StubInfoPlistPaths(resourcesDirectory: "${PROJECT_FILE_PATH}/.tulsi/Resources",
                                          defaultStub: "TestInfo.plist",
                                          watchOSStub: "TestWatchOS2Info.plist",
                                          watchOSAppExStub: "TestWatchOS2AppExInfo.plist")
  let testTulsiVersion = "9.99.999.9999"
  var project: PBXProject! = nil
  var targetGenerator: PBXTargetGenerator! = nil

  override func setUp() {
    super.setUp()
    project = PBXProject(name: "TestProject")
    targetGenerator = PBXTargetGenerator(bazelURL: bazelURL,
                                         bazelBinPath: "bazel-bin",
                                         project: project,
                                         buildScriptPath: "",
                                         stubInfoPlistPaths: stubPlistPaths,
                                         tulsiVersion: testTulsiVersion,
                                         options: TulsiOptionSet(),
                                         localizedMessageLogger: MockLocalizedMessageLogger(),
                                         workspaceRootURL: workspaceRootURL)

  }

  // MARK: - Tests

  func testGenerateFileReferenceForSingleBUILDFilePath() {
    let buildFilePath = "some/path/BUILD"
    targetGenerator.generateFileReferencesForFilePaths([buildFilePath])
    XCTAssertEqual(project.mainGroup.children.count, 1)

    let fileRef = project.mainGroup.allSources.first!
    let sourceRelativePath = fileRef.sourceRootRelativePath
    XCTAssertEqual(sourceRelativePath, buildFilePath)
    XCTAssertEqual(fileRef.sourceTree, SourceTree.Group, "SourceTree mismatch for generated BUILD file \(buildFilePath)")
  }

  func testGenerateFileReferenceForBUILDFilePaths() {
    let buildFilePaths = ["BUILD", "some/path/BUILD", "somewhere/else/BUILD"]
    targetGenerator.generateFileReferencesForFilePaths(buildFilePaths)
    XCTAssertEqual(project.mainGroup.children.count, buildFilePaths.count)

    for fileRef in project.mainGroup.allSources {
      XCTAssert(buildFilePaths.contains(fileRef.sourceRootRelativePath), "Path mismatch for generated BUILD file \(String(describing: fileRef.path))")
      XCTAssertEqual(fileRef.sourceTree, SourceTree.Group, "SourceTree mismatch for generated BUILD file \(String(describing: fileRef.path))")
    }
  }

  func testMainGroupForOutputFolder() {
    func assertOutputFolder(_ output: String,
                            workspace: String,
                            generatesSourceTree sourceTree: SourceTree,
                            path: String?,
                            line: UInt = #line) {
      let outputURL = URL(fileURLWithPath: output, isDirectory: true)
      let workspaceURL = URL(fileURLWithPath: workspace, isDirectory: true)
      let group = PBXTargetGenerator.mainGroupForOutputFolder(outputURL,
                                                              workspaceRootURL: workspaceURL)
      XCTAssertEqual(group.sourceTree, sourceTree, line: line)
      XCTAssertEqual(group.path, path, line: line)
    }

    assertOutputFolder("/", workspace: "/", generatesSourceTree: .SourceRoot, path: nil)
    assertOutputFolder("/output", workspace: "/output", generatesSourceTree: .SourceRoot, path: nil)
    assertOutputFolder("/output/", workspace: "/output", generatesSourceTree: .SourceRoot, path: nil)
    assertOutputFolder("/output", workspace: "/output/", generatesSourceTree: .SourceRoot, path: nil)
    assertOutputFolder("/", workspace: "/output", generatesSourceTree: .SourceRoot, path: "output")
    assertOutputFolder("/output", workspace: "/output/workspace", generatesSourceTree: .SourceRoot, path: "workspace")
    assertOutputFolder("/output/", workspace: "/output/workspace", generatesSourceTree: .SourceRoot, path: "workspace")
    assertOutputFolder("/output", workspace: "/output/workspace/", generatesSourceTree: .SourceRoot, path: "workspace")
    assertOutputFolder("/output", workspace: "/output/deep/path/workspace", generatesSourceTree: .SourceRoot, path: "deep/path/workspace")
    assertOutputFolder("/path/to/workspace/output", workspace: "/path/to/workspace", generatesSourceTree: .SourceRoot, path: "..")
    assertOutputFolder("/output", workspace: "/", generatesSourceTree: .SourceRoot, path: "..")
    assertOutputFolder("/output/", workspace: "/", generatesSourceTree: .SourceRoot, path: "..")
    assertOutputFolder("/path/to/workspace/three/deep/output", workspace: "/path/to/workspace", generatesSourceTree: .SourceRoot, path: "../../..")
    assertOutputFolder("/path/to/output", workspace: "/elsewhere/workspace", generatesSourceTree: .Absolute, path: "/elsewhere/workspace")
  }
}


class PBXTargetGeneratorTestsWithFiles: XCTestCase {
  let bazelURL = URL(fileURLWithPath: "__BAZEL_BINARY_")
  let workspaceRootURL = URL(fileURLWithPath: "/workspaceRootURL", isDirectory: true)
  let sdkRoot = "sdkRoot"
  let stubPlistPaths = StubInfoPlistPaths(resourcesDirectory:"${PROJECT_ROOT}/asd",
                                          defaultStub: "TestInfo.plist",
                                          watchOSStub: "TestWatchOS2Info.plist",
                                          watchOSAppExStub: "TestWatchOS2AppExInfo.plist")
  let testTulsiVersion = "9.99.999.9999"

  var project: PBXProject! = nil
  var targetGenerator: PBXTargetGenerator! = nil
  var messageLogger: MockLocalizedMessageLogger! = nil

  var sourceFileNames = [String]()
  var pathFilters = Set<String>()
  var sourceFileReferences = [PBXFileReference]()
  var pchFile: PBXFileReference! = nil

  override func setUp() {
    super.setUp()

    project = PBXProject(name: "TestProject")
    sourceFileNames = ["test.swift", "test.cc"]
    pathFilters = Set<String>([""])
    rebuildSourceFileReferences()
    pchFile = project.mainGroup.getOrCreateFileReferenceBySourceTree(.Group, path: "pch.pch")
    let options = TulsiOptionSet()
    messageLogger = MockLocalizedMessageLogger()
    targetGenerator = PBXTargetGenerator(bazelURL: bazelURL,
                                         bazelBinPath: "bazel-bin",
                                         project: project,
                                         buildScriptPath: "",
                                         stubInfoPlistPaths: stubPlistPaths,
                                         tulsiVersion: testTulsiVersion,
                                         options: options,
                                         localizedMessageLogger: messageLogger,
                                         workspaceRootURL: workspaceRootURL)
  }

  // MARK: - Tests

  func testGenerateBazelCleanTarget() {
    let scriptPath = "scriptPath"
    let workingDirectory = "/directory/of/work"
    targetGenerator.generateBazelCleanTarget(scriptPath, workingDirectory: workingDirectory)
    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)

    XCTAssertNotNil(targets[PBXTargetGenerator.BazelCleanTarget] as? PBXLegacyTarget)
    let target = targets[PBXTargetGenerator.BazelCleanTarget] as! PBXLegacyTarget

    XCTAssertEqual(target.buildToolPath, scriptPath)

    // The script should launch the test scriptPath with bazelURL's path as the only argument.
    let expectedScriptArguments = "\"\(bazelURL.path)\" \"bazel-bin\""
    XCTAssertEqual(target.buildArgumentsString, expectedScriptArguments)
  }

  func testGenerateBazelCleanTargetAppliesToRulesAddedBeforeAndAfter() {
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([makeTestRuleEntry("before", type: "ios_application")], ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    targetGenerator.generateBazelCleanTarget("scriptPath")

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([makeTestRuleEntry("after", type: "ios_application")], ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 3)

    XCTAssertNotNil(targets[PBXTargetGenerator.BazelCleanTarget] as? PBXLegacyTarget)
    let integrationTarget = targets[PBXTargetGenerator.BazelCleanTarget] as! PBXLegacyTarget

    for target in project.allTargets {
      if target === integrationTarget { continue }
      XCTAssertEqual(target.dependencies.count, 1, "Mismatch in dependency count for target added \(target.name)")
      let targetProxy = target.dependencies[0].targetProxy
      XCTAssert(targetProxy.containerPortal === project, "Mismatch in container for dependency in target added \(target.name)")
      XCTAssert(targetProxy.target === integrationTarget, "Mismatch in target dependency for target added \(target.name)")
      XCTAssertEqual(targetProxy.proxyType,
          PBXContainerItemProxy.ProxyType.targetReference,
          "Mismatch in target dependency type for target added \(target.name)")
    }
  }

  func testGenerateTopLevelBuildConfigurations() {
    targetGenerator.generateTopLevelBuildConfigurations()

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 4)

    let topLevelBuildSettings = [
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "CODE_SIGNING_REQUIRED": "NO",
        "CODE_SIGN_IDENTITY": "",
        "ENABLE_TESTABILITY": "YES",
        "FRAMEWORK_SEARCH_PATHS": "$(PLATFORM_DIR)/Developer/Library/Frameworks",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "HEADER_SEARCH_PATHS": "$(TULSI_BWRS) $(TULSI_WR)/bazel-bin $(TULSI_WR)/bazel-genfiles "
                               + "$(TULSI_WR)/tulsi-includes/x/x",
        "ONLY_ACTIVE_ARCH": "YES",
        "TULSI_VERSION": testTulsiVersion,
        "TULSI_WR": "$(SRCROOT)",
        "TULSI_BWRS": "${TULSI_WR}/bazel-workspaceRootURL",
    ]

    XCTAssertNotNil(topLevelConfigs["Debug"])
    XCTAssertEqual(topLevelConfigs["Debug"]!.buildSettings,
                   debugBuildSettingsFromSettings(topLevelBuildSettings))
    XCTAssertNotNil(topLevelConfigs["Release"])
    XCTAssertEqual(topLevelConfigs["Release"]!.buildSettings,
                   releaseBuildSettingsFromSettings(topLevelBuildSettings))
    XCTAssertNotNil(topLevelConfigs["__TulsiTestRunner_Debug"])
    XCTAssertEqual(topLevelConfigs["__TulsiTestRunner_Debug"]!.buildSettings,
                   debugTestRunnerBuildSettingsFromSettings(topLevelBuildSettings))
    XCTAssertNotNil(topLevelConfigs["__TulsiTestRunner_Release"])
    XCTAssertEqual(topLevelConfigs["__TulsiTestRunner_Release"]!.buildSettings,
                   releaseTestRunnerBuildSettingsFromSettings(topLevelBuildSettings))
  }

  func testGenerateTopLevelBuildConfigurationsWithAnSDKROOT() {
    let projectSDKROOT = "projectSDKROOT"
    targetGenerator.generateTopLevelBuildConfigurations(["SDKROOT": projectSDKROOT])

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 4)

    let topLevelBuildSettings = [
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "CODE_SIGNING_REQUIRED": "NO",
        "CODE_SIGN_IDENTITY": "",
        "ENABLE_TESTABILITY": "YES",
        "FRAMEWORK_SEARCH_PATHS": "$(PLATFORM_DIR)/Developer/Library/Frameworks",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "HEADER_SEARCH_PATHS": "$(TULSI_BWRS) $(TULSI_WR)/bazel-bin $(TULSI_WR)/bazel-genfiles "
                               + "$(TULSI_WR)/tulsi-includes/x/x",
        "SDKROOT": projectSDKROOT,
        "ONLY_ACTIVE_ARCH": "YES",
        "TULSI_VERSION": testTulsiVersion,
        "TULSI_WR": "$(SRCROOT)",
        "TULSI_BWRS": "${TULSI_WR}/bazel-workspaceRootURL",
    ]

    XCTAssertNotNil(topLevelConfigs["Debug"])
    XCTAssertEqual(topLevelConfigs["Debug"]!.buildSettings,
                   debugBuildSettingsFromSettings(topLevelBuildSettings))
    XCTAssertNotNil(topLevelConfigs["Release"])
    XCTAssertEqual(topLevelConfigs["Release"]!.buildSettings,
                   releaseBuildSettingsFromSettings(topLevelBuildSettings))
    XCTAssertNotNil(topLevelConfigs["__TulsiTestRunner_Debug"])
    XCTAssertEqual(topLevelConfigs["__TulsiTestRunner_Debug"]!.buildSettings,
                   debugTestRunnerBuildSettingsFromSettings(topLevelBuildSettings))
    XCTAssertNotNil(topLevelConfigs["__TulsiTestRunner_Release"])
    XCTAssertEqual(topLevelConfigs["__TulsiTestRunner_Release"]!.buildSettings,
                   releaseTestRunnerBuildSettingsFromSettings(topLevelBuildSettings))
  }

  func testGenerateTargetsForRuleEntriesWithNoEntries() {
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([], ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    let targets = project.targetByName
    XCTAssert(targets.isEmpty)
  }

  func testGenerateTargetsForRuleEntries() {
    let rule1BuildPath = "test/app"
    let rule1TargetName = "TestApplication"
    let rule1BuildTarget = "\(rule1BuildPath):\(rule1TargetName)"
    let rule2BuildPath = "test/objclib"
    let rule2TargetName = "ObjectiveCLibrary"
    let rule2BuildTarget = "\(rule2BuildPath):\(rule2TargetName)"
    let ipa = BuildLabel("test/app:TestApplication.ipa")
    let rules = Set([
      makeTestRuleEntry(rule1BuildTarget, type: "ios_application", implicitIPATarget: ipa),
      makeTestRuleEntry(rule2BuildTarget, type: "objc_library"),
    ])

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 0)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)

    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": "test/app:TestApplication",
          "BAZEL_TARGET_TYPE": "ios_application",
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.defaultStub,
          "PRODUCT_NAME": rule1TargetName,
          "SDKROOT": "iphoneos",
          "TULSI_BUILD_PATH": rule1BuildPath,
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      let expectedTarget = TargetDefinition(
          name: rule1TargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule1BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": "test/objclib:ObjectiveCLibrary",
          "BAZEL_TARGET_TYPE": "objc_library",
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.defaultStub,
          "PRODUCT_NAME": rule2TargetName,
          "SDKROOT": "iphoneos",
          "TULSI_BUILD_PATH": rule2BuildPath,
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      let expectedTarget = TargetDefinition(
          name: rule2TargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule2BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateTargetsForLinkedRuleEntriesWithNoSources() {
    checkGenerateTargetsForLinkedRuleEntriesWithNoSources("ios_test",
                                                          testHostAttributeName: "xctest_app")
  }

  func testGenerateTargetsForLinkedRuleEntriesWithNoSourcesAndSkylarkUnitTest() {
    checkGenerateTargetsForLinkedRuleEntriesWithNoSources("apple_unit_test",
                                                          testHostAttributeName: "test_host")
  }

  func checkGenerateTargetsForLinkedRuleEntriesWithNoSources(_ testRuleType: String,
                                                             testHostAttributeName: String) {
    let rule1BuildPath = "test/app"
    let rule1TargetName = "TestApplication"
    let rule1BuildTarget = "\(rule1BuildPath):\(rule1TargetName)"
    let rule2BuildPath = "test/testbundle"
    let rule2TargetName = "TestBundle"
    let rule2BuildTarget = "\(rule2BuildPath):\(rule2TargetName)"
    let rule2Attributes = [testHostAttributeName: rule1BuildTarget]
    let ipa = BuildLabel("test/app:TestApplication.ipa")
    let rules = Set([
      makeTestRuleEntry(rule1BuildTarget, type: "ios_application", implicitIPATarget: ipa),
      makeTestRuleEntry(rule2BuildTarget,
                        type: testRuleType,
                        attributes: rule2Attributes as [String: AnyObject],
                        implicitIPATarget: ipa),
    ])

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }
    XCTAssert(!messageLogger.warningMessageKeys.contains("MissingTestHost"))

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 0)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)

    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": "test/app:TestApplication",
          "BAZEL_TARGET_TYPE": "ios_application",
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.defaultStub,
          "PRODUCT_NAME": rule1TargetName,
          "SDKROOT": "iphoneos",
          "TULSI_BUILD_PATH": rule1BuildPath,
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      let expectedTarget = TargetDefinition(
          name: rule1TargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule1BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": "test/testbundle:TestBundle",
          "BAZEL_TARGET_TYPE": testRuleType,
          "BUNDLE_LOADER": "$(TEST_HOST)",
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.defaultStub,
          "PRODUCT_NAME": rule2TargetName,
          "SDKROOT": "iphoneos",
          "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(rule1TargetName).app/\(rule1TargetName)",
          "TULSI_BUILD_PATH": rule2BuildPath,
          "TULSI_TEST_RUNNER_ONLY": "YES",
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      let expectedTarget = TargetDefinition(
          name: rule2TargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule2BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateTargetsForLinkedRuleEntriesWithNoSourcesAndSkylarkUITest() {
    let testRuleType = "apple_ui_test"
    let testHostAttributeName = "test_host"
    let rule1BuildPath = "test/app"
    let rule1TargetName = "TestApplication"
    let rule1BuildTarget = "\(rule1BuildPath):\(rule1TargetName)"
    let rule2BuildPath = "test/testbundle"
    let rule2TargetName = "TestBundle"
    let rule2BuildTarget = "\(rule2BuildPath):\(rule2TargetName)"
    let rule2Attributes = [testHostAttributeName: rule1BuildTarget]
    let ipa = BuildLabel("test/app:TestApplication.ipa")
    let rules = Set([
      makeTestRuleEntry(rule1BuildTarget, type: "ios_application", implicitIPATarget: ipa),
      makeTestRuleEntry(rule2BuildTarget,
                        type: testRuleType,
                        attributes: rule2Attributes as [String: AnyObject],
                        implicitIPATarget: ipa),
      ])

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }
    XCTAssert(!messageLogger.warningMessageKeys.contains("MissingTestHost"))

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 0)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)

    do {
      let expectedBuildSettings = [
        "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
        "BAZEL_TARGET": "test/app:TestApplication",
        "BAZEL_TARGET_TYPE": "ios_application",
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "INFOPLIST_FILE": stubPlistPaths.defaultStub,
        "PRODUCT_NAME": rule1TargetName,
        "SDKROOT": "iphoneos",
        "TULSI_BUILD_PATH": rule1BuildPath,
        "TULSI_USE_DSYM": "NO",
        "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
        ]
      let expectedTarget = TargetDefinition(
        name: rule1TargetName,
        buildConfigurations: [
          BuildConfigurationDefinition(
            name: "Debug",
            expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "Release",
            expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "__TulsiTestRunner_Debug",
            expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "__TulsiTestRunner_Release",
            expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
          ),
          ],
        expectedBuildPhases: [
          BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule1BuildTarget)
        ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
        "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
        "BAZEL_TARGET": "test/testbundle:TestBundle",
        "BAZEL_TARGET_TYPE": testRuleType,
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "INFOPLIST_FILE": stubPlistPaths.defaultStub,
        "PRODUCT_NAME": rule2TargetName,
        "SDKROOT": "iphoneos",
        "TEST_TARGET_NAME": rule1TargetName,
        "TULSI_BUILD_PATH": rule2BuildPath,
        "TULSI_TEST_RUNNER_ONLY": "YES",
        "TULSI_USE_DSYM": "NO",
        "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
        ]
      let expectedTarget = TargetDefinition(
        name: rule2TargetName,
        buildConfigurations: [
          BuildConfigurationDefinition(
            name: "Debug",
            expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "Release",
            expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "__TulsiTestRunner_Debug",
            expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "__TulsiTestRunner_Release",
            expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
          ),
          ],
        expectedBuildPhases: [
          BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule2BuildTarget)
        ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateTargetsForLinkedRuleEntriesWithSources() {
    checkGenerateTargetsForLinkedRuleEntriesWithSources("ios_test",
                                                        testHostAttributeName: "xctest_app")
  }

  func testGenerateTargetsForLinkedRuleEntriesWithSourcesWithSkylarkUnitTest() {
    checkGenerateTargetsForLinkedRuleEntriesWithSources("apple_unit_test",
                                                        testHostAttributeName: "test_host")
  }

  func checkGenerateTargetsForLinkedRuleEntriesWithSources(_ testRuleType: String,
                                                           testHostAttributeName: String) {
    let rule1BuildPath = "test/app"
    let rule1TargetName = "TestApplication"
    let rule1BuildTarget = "\(rule1BuildPath):\(rule1TargetName)"
    let testRuleBuildPath = "test/testbundle"
    let testRuleTargetName = "TestBundle"
    let testRuleBuildTarget = "\(testRuleBuildPath):\(testRuleTargetName)"
    let testRuleAttributes = [testHostAttributeName: rule1BuildTarget]
    let testSources = ["sourceFile1.m", "sourceFile2.mm"]
    let appIPA = BuildLabel("test/app:TestApplication.ipa")
    let testIPA = BuildLabel("test/testbundle/TestBundle.ipa")
    let testRule = makeTestRuleEntry(testRuleBuildTarget,
                                     type: testRuleType,
                                     attributes: testRuleAttributes as [String: AnyObject],
                                     sourceFiles: testSources,
                                     implicitIPATarget: testIPA)
    let rules = Set([
      makeTestRuleEntry(rule1BuildTarget, type: "ios_application", implicitIPATarget: appIPA),
      testRule,
    ])
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }
    XCTAssert(!messageLogger.warningMessageKeys.contains("MissingTestHost"))

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)
    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": "test/app:TestApplication",
          "BAZEL_TARGET_TYPE": "ios_application",
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.defaultStub,
          "PRODUCT_NAME": rule1TargetName,
          "SDKROOT": "iphoneos",
          "TULSI_BUILD_PATH": rule1BuildPath,
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      let expectedTarget = TargetDefinition(
          name: rule1TargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL,
                                              buildTarget: rule1BuildTarget),
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": "test/testbundle:TestBundle",
          "BAZEL_TARGET_TYPE": testRuleType,
          "BUNDLE_LOADER": "$(TEST_HOST)",
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.defaultStub,
          "PRODUCT_NAME": testRuleTargetName,
          "SDKROOT": "iphoneos",
          "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(rule1TargetName).app/\(rule1TargetName)",
          "TULSI_BUILD_PATH": testRuleBuildPath,
          "TULSI_TEST_RUNNER_ONLY": "YES",
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      let expectedTarget = TargetDefinition(
          name: testRuleTargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              SourcesBuildPhaseDefinition(files: testSources, mainGroup: project.mainGroup),
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL,
                                              buildTarget: testRuleBuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateTestTargetWithObjectiveCSources() {
    let testRuleTargetName = "Tests"
    let testRuleType = "apple_unit_test"
    let testHostTargetName = "App"
    let testRulePackage = "test/app"
    let testSources = ["test/app/Tests.m"]
    let objcLibraryRuleEntry = makeTestRuleEntry("\(testRulePackage):ObjcLib",
      type: "objc_library",
      sourceFiles: testSources)
    let appleBinaryRuleEntry = makeTestRuleEntry("\(testRulePackage):Tests_test_binary",
      type: "apple_binary",
      dependencies: Set([objcLibraryRuleEntry.label.value]))
    let testBundleRuleEntry = makeTestRuleEntry("\(testRulePackage):Tests_test_bundle",
      type: "ios_test_bundle",
      attributes: ["binary": appleBinaryRuleEntry.label.value as AnyObject])
    let testHostRuleEntry = makeTestRuleEntry("\(testRulePackage):\(testHostTargetName)",
      type: "ios_application",
      implicitIPATarget: BuildLabel("test/app:App.ipa"))
    let testRuleEntry = makeTestRuleEntry("\(testRulePackage):\(testRuleTargetName)",
      type: "\(testRuleType)",
      attributes: ["test_bundle": testBundleRuleEntry.label.value as AnyObject,
                   "test_host": testHostRuleEntry.label.value as AnyObject])

    let ruleEntryMap = makeRuleEntryMap(withRuleEntries: [objcLibraryRuleEntry,
                                                          appleBinaryRuleEntry,
                                                          testBundleRuleEntry,
                                                          testHostRuleEntry,
                                                          testRuleEntry])

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([testRuleEntry, testHostRuleEntry],
                                                             ruleEntryMap: ruleEntryMap)
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }
    XCTAssert(!messageLogger.warningMessageKeys.contains("MissingTestHost"))

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)

    let expectedBuildSettings = [
      "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
      "BAZEL_TARGET": "test/app:Tests",
      "BAZEL_TARGET_TYPE": testRuleType,
      "BUNDLE_LOADER": "$(TEST_HOST)",
      "DEBUG_INFORMATION_FORMAT": "dwarf",
      "INFOPLIST_FILE": stubPlistPaths.defaultStub,
      "PRODUCT_NAME": testRuleTargetName,
      "SDKROOT": "iphoneos",
      "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(testHostTargetName).app/\(testHostTargetName)",
      "TULSI_BUILD_PATH": testRulePackage,
      "TULSI_TEST_RUNNER_ONLY": "YES",
      "TULSI_USE_DSYM": "NO",
      "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
    let expectedTarget = TargetDefinition(
      name: testRuleTargetName,
      buildConfigurations: [
        BuildConfigurationDefinition(
          name: "Debug",
          expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
        ),
        BuildConfigurationDefinition(
          name: "Release",
          expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
        ),
        BuildConfigurationDefinition(
          name: "__TulsiTestRunner_Debug",
          expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
        ),
        BuildConfigurationDefinition(
          name: "__TulsiTestRunner_Release",
          expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
        ),
        ],
      expectedBuildPhases: [
        SourcesBuildPhaseDefinition(files: testSources, mainGroup: project.mainGroup),
        BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL,
                                             buildTarget: "\(testRulePackage):\(testRuleTargetName)")
      ]
    )
    assertTarget(expectedTarget, inTargets: targets)
  }

  func testGenerateTestTargetWithSwiftSources() {
    let testRuleTargetName = "Tests"
    let testRuleType = "apple_unit_test"
    let testHostTargetName = "App"
    let testRulePackage = "test/app"
    let testSources = ["test/app/Tests.swift"]
    let swiftLibraryRuleEntry = makeTestRuleEntry("\(testRulePackage):SwiftLib",
                                                  type: "swift_library",
                                                  sourceFiles: testSources)
    let appleBinaryRuleEntry = makeTestRuleEntry("\(testRulePackage):Tests_test_binary",
                                                 type: "apple_binary",
                                                 dependencies: Set([swiftLibraryRuleEntry.label.value]))
    let testBundleRuleEntry = makeTestRuleEntry("\(testRulePackage):Tests_test_bundle",
                                                type: "ios_test_bundle",
                                                attributes: ["binary": appleBinaryRuleEntry.label.value as AnyObject])
    let testHostRuleEntry = makeTestRuleEntry("\(testRulePackage):\(testHostTargetName)",
                                              type: "ios_application",
                                              implicitIPATarget: BuildLabel("test/app:App.ipa"))
    let testRuleEntry = makeTestRuleEntry("\(testRulePackage):\(testRuleTargetName)",
                                          type: "\(testRuleType)",
                                          attributes: ["test_bundle": testBundleRuleEntry.label.value as AnyObject,
                                                       "test_host": testHostRuleEntry.label.value as AnyObject])

    let ruleEntryMap = makeRuleEntryMap(withRuleEntries: [swiftLibraryRuleEntry,
                                                          appleBinaryRuleEntry,
                                                          testBundleRuleEntry,
                                                          testHostRuleEntry,
                                                          testRuleEntry])

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([testRuleEntry, testHostRuleEntry],
                                                             ruleEntryMap: ruleEntryMap)
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }
    XCTAssert(!messageLogger.warningMessageKeys.contains("MissingTestHost"))

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)

    let expectedBuildSettings = [
      "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
      "BAZEL_TARGET": "test/app:Tests",
      "BAZEL_TARGET_TYPE": testRuleType,
      "BUNDLE_LOADER": "$(TEST_HOST)",
      "DEBUG_INFORMATION_FORMAT": "dwarf",
      "INFOPLIST_FILE": stubPlistPaths.defaultStub,
      "PRODUCT_NAME": testRuleTargetName,
      "SDKROOT": "iphoneos",
      "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(testHostTargetName).app/\(testHostTargetName)",
      "TULSI_BUILD_PATH": testRulePackage,
      "TULSI_TEST_RUNNER_ONLY": "YES",
      "TULSI_USE_DSYM": "NO",
      "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
    let expectedTarget = TargetDefinition(
      name: testRuleTargetName,
      buildConfigurations: [
        BuildConfigurationDefinition(
          name: "Debug",
          expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
        ),
        BuildConfigurationDefinition(
          name: "Release",
          expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
        ),
        BuildConfigurationDefinition(
          name: "__TulsiTestRunner_Debug",
          expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
        ),
        BuildConfigurationDefinition(
          name: "__TulsiTestRunner_Release",
          expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
        ),
        ],
      expectedBuildPhases: [
        SourcesBuildPhaseDefinition(files: testSources, mainGroup: project.mainGroup),
        BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL,
                                             buildTarget: "\(testRulePackage):\(testRuleTargetName)"),
        SwiftDummyShellScriptBuildPhaseDefinition()
      ]
    )
    assertTarget(expectedTarget, inTargets: targets)
  }

  private func makeRuleEntryMap(withRuleEntries ruleEntries: [RuleEntry]) -> [BuildLabel: RuleEntry] {
    var ruleEntryMap = [BuildLabel: RuleEntry]()
    for ruleEntry in ruleEntries {
      ruleEntryMap[BuildLabel(ruleEntry.label.value)] = ruleEntry
    }
    return ruleEntryMap
  }

  func testGenerateTargetsForLinkedRuleEntriesWithSourcesWithSkylarkUITest() {
    let testRuleType = "apple_ui_test"
    let testHostAttributeName = "test_host"
    let rule1BuildPath = "test/app"
    let rule1TargetName = "TestApplication"
    let rule1BuildTarget = "\(rule1BuildPath):\(rule1TargetName)"
    let testRuleBuildPath = "test/testbundle"
    let testRuleTargetName = "TestBundle"
    let testRuleBuildTarget = "\(testRuleBuildPath):\(testRuleTargetName)"
    let testRuleAttributes = [testHostAttributeName: rule1BuildTarget]
    let testSources = ["sourceFile1.m", "sourceFile2.mm"]
    let appIPA = BuildLabel("test/app:TestApplication.ipa")
    let testIPA = BuildLabel("test/testbundle/TestBundle.ipa")
    let testRule = makeTestRuleEntry(testRuleBuildTarget,
                                     type: testRuleType,
                                     attributes: testRuleAttributes as [String: AnyObject],
                                     sourceFiles: testSources,
                                     implicitIPATarget: testIPA)
    let rules = Set([
      makeTestRuleEntry(rule1BuildTarget, type: "ios_application", implicitIPATarget: appIPA),
      testRule,
      ])
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }
    XCTAssert(!messageLogger.warningMessageKeys.contains("MissingTestHost"))

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)
    do {
      let expectedBuildSettings = [
        "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
        "BAZEL_TARGET": "test/app:TestApplication",
        "BAZEL_TARGET_TYPE": "ios_application",
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "INFOPLIST_FILE": stubPlistPaths.defaultStub,
        "PRODUCT_NAME": rule1TargetName,
        "SDKROOT": "iphoneos",
        "TULSI_BUILD_PATH": rule1BuildPath,
        "TULSI_USE_DSYM": "NO",
        "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
        ]
      let expectedTarget = TargetDefinition(
        name: rule1TargetName,
        buildConfigurations: [
          BuildConfigurationDefinition(
            name: "Debug",
            expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "Release",
            expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "__TulsiTestRunner_Debug",
            expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "__TulsiTestRunner_Release",
            expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
          ),
          ],
        expectedBuildPhases: [
          BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL,
                                          buildTarget: rule1BuildTarget),
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
        "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
        "BAZEL_TARGET": "test/testbundle:TestBundle",
        "BAZEL_TARGET_TYPE": testRuleType,
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "INFOPLIST_FILE": stubPlistPaths.defaultStub,
        "PRODUCT_NAME": testRuleTargetName,
        "SDKROOT": "iphoneos",
        "TEST_TARGET_NAME": rule1TargetName,
        "TULSI_BUILD_PATH": testRuleBuildPath,
        "TULSI_TEST_RUNNER_ONLY": "YES",
        "TULSI_USE_DSYM": "NO",
        "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
        ]
      let expectedTarget = TargetDefinition(
        name: testRuleTargetName,
        buildConfigurations: [
          BuildConfigurationDefinition(
            name: "Debug",
            expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "Release",
            expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "__TulsiTestRunner_Debug",
            expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
          ),
          BuildConfigurationDefinition(
            name: "__TulsiTestRunner_Release",
            expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
          ),
          ],
        expectedBuildPhases: [
          SourcesBuildPhaseDefinition(files: testSources, mainGroup: project.mainGroup),
          BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL,
                                          buildTarget: testRuleBuildTarget)
        ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateTargetsForLinkedRuleEntriesWithSameTestHostNameInDifferentPackages() {
    checkGenerateTargetsForLinkedRuleEntriesWithSameTestHostNameInDifferentPackages(
        "ios_test", testHostAttributeName: "xctest_app")
  }

  func testGenerateTargetsForLinkedRuleEntriesWithSameTestHostNameInDifferentPackagesWithSkylarkUnitTest() {
    checkGenerateTargetsForLinkedRuleEntriesWithSameTestHostNameInDifferentPackages(
        "apple_unit_test", testHostAttributeName: "test_host")
  }

  func testGenerateTargetsForLinkedRuleEntriesWithSameTestHostNameInDifferentPackagesWithSkylarkUITest() {
    checkGenerateTargetsForLinkedRuleEntriesWithSameTestHostNameInDifferentPackages(
        "apple_ui_test", testHostAttributeName: "test_host")
  }

  func checkGenerateTargetsForLinkedRuleEntriesWithSameTestHostNameInDifferentPackages(
      _ testRuleType: String, testHostAttributeName: String) {
    let hostTargetName = "TestHost"
    let host1Package = "test/package/1"
    let host2Package = "test/package/2"
    let host1Target = "\(host1Package):\(hostTargetName)"
    let host2Target = "\(host2Package):\(hostTargetName)"

    let testSources = ["sourceFile1.m", "sourceFile2.mm"]
    let test1TargetName = "Test_1"
    let test2TargetName = "Test_2"

    let test1Target = "\(host1Package):\(test1TargetName)"
    let test2Target = "\(host2Package):\(test2TargetName)"
    let test1Rule = makeTestRuleEntry(test1Target,
                                      type: testRuleType,
                                      attributes: [testHostAttributeName: host1Target as AnyObject],
                                      sourceFiles: testSources)
    let test2Rule = makeTestRuleEntry(test2Target,
                                      type: testRuleType,
                                      attributes: [testHostAttributeName: host2Target as AnyObject],
                                      sourceFiles: testSources)
    let rules = Set([
      makeTestRuleEntry(host1Target, type: "ios_application"),
      makeTestRuleEntry(host2Target, type: "ios_application"),
      test1Rule,
      test2Rule,
    ])
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }
    XCTAssert(!messageLogger.warningMessageKeys.contains("MissingTestHost"))
  }

  func testGenerateTargetsForLinkedRuleEntriesWithoutIncludingTheHostWarns() {
    checkGenerateTargetsForLinkedRuleEntriesWithoutIncludingTheHostWarns(
        "ios_test", testHostAttributeName: "xctest_app")
  }

  func testGenerateTargetsForLinkedRuleEntriesWithoutIncludingTheHostWarnsWithSkylarkUnitTest() {
    checkGenerateTargetsForLinkedRuleEntriesWithoutIncludingTheHostWarns(
        "apple_unit_test", testHostAttributeName: "test_host")
  }

  func testGenerateTargetsForLinkedRuleEntriesWithoutIncludingTheHostWarnsWithSkylarkUITest() {
    checkGenerateTargetsForLinkedRuleEntriesWithoutIncludingTheHostWarns(
        "apple_ui_test", testHostAttributeName: "test_host")
  }

  func checkGenerateTargetsForLinkedRuleEntriesWithoutIncludingTheHostWarns(
      _ testRuleType: String, testHostAttributeName: String) {
    let rule1BuildPath = "test/app"
    let rule1TargetName = "TestApplication"
    let rule1BuildTarget = "\(rule1BuildPath):\(rule1TargetName)"
    let testRuleBuildPath = "test/testbundle"
    let testRuleTargetName = "TestBundle"
    let testRuleBuildTarget = "\(testRuleBuildPath):\(testRuleTargetName)"
    let testRuleAttributes = [testHostAttributeName: rule1BuildTarget]
    let testSources = ["sourceFile1.m", "sourceFile2.mm"]
    let ipa = BuildLabel("test/app:TestApplication.ipa")
    let testRule = makeTestRuleEntry(testRuleBuildTarget,
                                     type: testRuleType,
                                     attributes: testRuleAttributes as [String: AnyObject],
                                     sourceFiles: testSources,
                                     implicitIPATarget: ipa)
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([testRule], ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
      return
    }

    XCTAssert(messageLogger.warningMessageKeys.contains("MissingTestHost"))
    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": "test/testbundle:TestBundle",
          "BAZEL_TARGET_TYPE": testRuleType,
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.defaultStub,
          "PRODUCT_NAME": testRuleTargetName,
          "SDKROOT": "iphoneos",
          "TULSI_BUILD_PATH": testRuleBuildPath,
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      var testRunnerExpectedBuildSettings = expectedBuildSettings
      testRunnerExpectedBuildSettings["DEBUG_INFORMATION_FORMAT"] = "dwarf"
      testRunnerExpectedBuildSettings["ONLY_ACTIVE_ARCH"] = "YES"
      testRunnerExpectedBuildSettings["OTHER_CFLAGS"] = "-help"
      testRunnerExpectedBuildSettings["OTHER_LDFLAGS"] = "-help"
      let expectedTarget = TargetDefinition(
          name: testRuleTargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL,
                                              buildTarget: testRuleBuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateTargetsForRuleEntriesWithTheSameName() {
    let targetName = "SameName"
    let rule1BuildPath = "test/test1"
    let rule1BuildTarget = "\(rule1BuildPath):\(targetName)"
    let rule2BuildPath = "test/test2"
    let rule2BuildTarget = "\(rule2BuildPath):\(targetName)"
    let rule1IPA = BuildLabel("test/test1:\(targetName).ipa")
    let rule2IPA = BuildLabel("test/test2:\(targetName).ipa")
    let rules = Set([
      makeTestRuleEntry(rule1BuildTarget, type: "ios_application", implicitIPATarget: rule1IPA),
      makeTestRuleEntry(rule2BuildTarget, type: "ios_application", implicitIPATarget: rule2IPA),
    ])

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 0)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)

    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": "test/test1:\(targetName)",
          "BAZEL_TARGET_TYPE": "ios_application",
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.defaultStub,
          "PRODUCT_NAME": "test-test1-SameName",
          "SDKROOT": "iphoneos",
          "TULSI_BUILD_PATH": rule1BuildPath,
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      let expectedTarget = TargetDefinition(
          name: "test-test1-SameName",
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule1BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": "test/test2:\(targetName)",
          "BAZEL_TARGET_TYPE": "ios_application",
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.defaultStub,
          "PRODUCT_NAME": "test-test2-SameName",
          "SDKROOT": "iphoneos",
          "TULSI_BUILD_PATH": rule2BuildPath,
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      let expectedTarget = TargetDefinition(
          name: "test-test2-SameName",
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule2BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateTargetWithBundleID() {
    let targetName = "targetName"
    let buildPath = "test/test1"
    let buildTarget = "\(buildPath):\(targetName)"
    let ipa = BuildLabel("\(buildPath):\(targetName).ipa")
    let bundleID = "bundleID"
    let rules = Set([
      makeTestRuleEntry(buildTarget,
                        type: "ios_application",
                        bundleID: bundleID,
                        implicitIPATarget: ipa),
    ])

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 0)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)

    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": buildTarget,
          "BAZEL_TARGET_TYPE": "ios_application",
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.defaultStub,
          "PRODUCT_BUNDLE_IDENTIFIER": bundleID,
          "PRODUCT_NAME": targetName,
          "SDKROOT": "iphoneos",
          "TULSI_BUILD_PATH": buildPath,
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      let expectedTarget = TargetDefinition(
          name: targetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: buildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateWatchOS2TargetWithExtensionBundleID() {
    let appTargetName = "targetName"
    let appBuildPath = "test/app"
    let appBuildTarget = "\(appBuildPath):\(appTargetName)"
    let appIPA = BuildLabel("\(appBuildPath):\(appTargetName).ipa")
    let watchAppTargetName = "watchAppTargetName"
    let watchAppBuildPath = "test/watchapp"
    let watchAppBuildTarget = "\(watchAppBuildPath):\(watchAppTargetName)"
    let watchAppIPA = BuildLabel("\(watchAppBuildPath):\(watchAppTargetName).ipa")
    let watchExtTargetName = "_tulsi_appex_\(watchAppTargetName)"

    let appBundleID = "appBundleID"
    let watchAppBundleID = "watchAppBundleID"
    let watchExtBundleID = "watchAppExtBundleID"
    let rules = Set([
      makeTestRuleEntry(appBuildTarget,
                        type: "ios_application",
                        extensions: Set([BuildLabel(watchAppBuildTarget)]),
                        bundleID: appBundleID,
                        implicitIPATarget: appIPA),
      makeTestRuleEntry(watchAppBuildTarget,
                        type: "apple_watch2_extension",
                        bundleID: watchAppBundleID,
                        extensionBundleID: watchExtBundleID,
                        implicitIPATarget: watchAppIPA)
    ])

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 0)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 3)

    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": appBuildTarget,
          "BAZEL_TARGET_TYPE": "ios_application",
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.defaultStub,
          "PRODUCT_BUNDLE_IDENTIFIER": appBundleID,
          "PRODUCT_NAME": appTargetName,
          "SDKROOT": "iphoneos",
          "TULSI_BUILD_PATH": appBuildPath,
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      let expectedTarget = TargetDefinition(
          name: appTargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: appBuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
          "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
          "BAZEL_TARGET": watchAppBuildTarget,
          "BAZEL_TARGET_TYPE": "apple_watch2_extension",
          "DEBUG_INFORMATION_FORMAT": "dwarf",
          "INFOPLIST_FILE": stubPlistPaths.watchOSStub,
          "PRODUCT_BUNDLE_IDENTIFIER": watchAppBundleID,
          "PRODUCT_NAME": watchAppTargetName,
          "SDKROOT": "watchos",
          "TULSI_BUILD_PATH": watchAppBuildPath,
          "TULSI_USE_DSYM": "NO",
          "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
      ]
      let expectedTarget = TargetDefinition(
          name: watchAppTargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: [
              BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: watchAppBuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
          "INFOPLIST_FILE": stubPlistPaths.watchOSAppExStub,
          "PRODUCT_BUNDLE_IDENTIFIER": watchExtBundleID,
          "PRODUCT_NAME": watchExtTargetName,
          "SDKROOT": "watchos",
      ]
      let expectedTarget = TargetDefinition(
          name: watchExtTargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Debug",
                  expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunner_Release",
                  expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
              ),
          ],
          expectedBuildPhases: []
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateIndexerWithNoSources() {
    let ruleEntry = makeTestRuleEntry("test/app:TestApp", type: "ios_application")
    targetGenerator.registerRuleEntryForIndexer(ruleEntry,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()
    let targets = project.targetByName
    XCTAssert(targets.isEmpty)
  }

  func testGenerateIndexerWithNoPCHFile() {
    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry(buildLabel,
                                      type: "ios_application",
                                      sourceFiles: sourceFileNames)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.registerRuleEntryForIndexer(ruleEntry,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName, sourceFileNames: sourceFileNames, inTargets: targets)
  }

  func testGenerateIndexer() {
    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry("test/app:TestApp",
                                      type: "ios_application",
                                      attributes: ["pch": ["path": pchFile.path!, "src": true] as AnyObject],
                                      sourceFiles: sourceFileNames)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.registerRuleEntryForIndexer(ruleEntry,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName, sourceFileNames: sourceFileNames, pchFile: pchFile, inTargets: targets)
  }

  func testGenerateIndexerWithBridgingHeader() {
    let bridgingHeaderFilePath = "some/place/bridging-header.h"
    let ruleAttributes = ["bridging_header": ["path": bridgingHeaderFilePath, "src": true]]

    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry(buildLabel,
                                      type: "ios_binary",
                                      attributes: ruleAttributes as [String : AnyObject],
                                      sourceFiles: sourceFileNames)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.registerRuleEntryForIndexer(ruleEntry,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName,
                          sourceFileNames: sourceFileNames,
                          bridgingHeader: "$(TULSI_BWRS)/\(bridgingHeaderFilePath)",
                          inTargets: targets)
  }

  func testGenerateIndexerWithGeneratedBridgingHeader() {
    let bridgingHeaderFilePath = "some/place/bridging-header.h"
    let bridgingHeaderInfo = ["path": bridgingHeaderFilePath,
                              "root": "bazel-genfiles",
                              "src": false] as [String : Any]
    let ruleAttributes = ["bridging_header": bridgingHeaderInfo]

    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry(buildLabel,
                                      type: "ios_binary",
                                      attributes: ruleAttributes as [String : AnyObject],
                                      sourceFiles: sourceFileNames)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.registerRuleEntryForIndexer(ruleEntry,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName,
                          sourceFileNames: sourceFileNames,
                          bridgingHeader: "$(TULSI_WR)/bazel-genfiles/\(bridgingHeaderFilePath)",
                          inTargets: targets)
  }

  func testGenerateIndexerWithXCDataModel() {
    let dataModel = "test.xcdatamodeld"
    let ruleAttributes = ["datamodels": [["path": "\(dataModel)/v1.xcdatamodel", "src": true],
                                         ["path": "\(dataModel)/v2.xcdatamodel", "src": true]]]

    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry(buildLabel,
                                      type: "ios_binary",
                                      attributes: ruleAttributes as [String : AnyObject],
                                      sourceFiles: sourceFileNames)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.registerRuleEntryForIndexer(ruleEntry,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters.union(Set([dataModel])))
    targetGenerator.generateIndexerTargets()

    var allSourceFiles = sourceFileNames
    allSourceFiles.append(dataModel)
    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName,
                          sourceFileNames: allSourceFiles,
                          inTargets: targets)
  }

  func testGenerateIndexerWithSourceFilter() {
    sourceFileNames.append("this/file/should/appear.m")
    pathFilters.insert("this/file/should")
    rebuildSourceFileReferences()

    var allSourceFiles = sourceFileNames
    allSourceFiles.append("filtered/file.m")
    allSourceFiles.append("this/file/should/not/appear.m")

    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry(buildLabel,
                                      type: "ios_application",
                                      sourceFiles: allSourceFiles)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.registerRuleEntryForIndexer(ruleEntry,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName, sourceFileNames: sourceFileNames, inTargets: targets)
  }

  func testGenerateIndexerWithRecursiveSourceFilter() {
    sourceFileNames.append("this/file/should/appear.m")
    sourceFileNames.append("this/file/should/also/appear.m")
    pathFilters.insert("this/file/should/...")
    rebuildSourceFileReferences()

    var allSourceFiles = sourceFileNames
    allSourceFiles.append("filtered/file.m")

    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry(buildLabel,
                                      type: "ios_application",
                                      sourceFiles: allSourceFiles)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.registerRuleEntryForIndexer(ruleEntry,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName, sourceFileNames: sourceFileNames, inTargets: targets)
  }

  func testGenerateBUILDRefsWithoutSourceFilter() {
    let buildFilePath = "this/file/should/not/BUILD"
    pathFilters.insert("this/file/should")
    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry(buildLabel,
                                      type: "ios_application",
                                      sourceFiles: sourceFileNames,
                                      buildFilePath: buildFilePath)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()
    XCTAssertNil(fileRefForPath(buildFilePath))
  }

  func testGenerateBUILDRefsWithSourceFilter() {
    let buildFilePath = "this/file/should/BUILD"
    pathFilters.insert("this/file/should")
    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry(buildLabel,
                                      type: "ios_application",
                                      sourceFiles: sourceFileNames,
                                      buildFilePath: buildFilePath)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()
    XCTAssertNotNil(fileRefForPath(buildFilePath))
  }

  func testGenerateBUILDRefsWithRecursiveSourceFilter() {
    let buildFilePath = "this/file/should/BUILD"
    pathFilters.insert("this/file/...")
    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry(buildLabel,
                                      type: "ios_application",
                                      sourceFiles: sourceFileNames,
                                      buildFilePath: buildFilePath)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()
    XCTAssertNotNil(fileRefForPath(buildFilePath))
  }

  func testMergesCompatibleIndexers() {
    let sourceFiles1 = ["1.swift", "1.cc"]
    let buildLabel1 = BuildLabel("test/app:TestBinary")

    let ruleEntry1 = makeTestRuleEntry(buildLabel1,
                                       type: "ios_binary",
                                       attributes: ["pch": ["path": pchFile.path!, "src": true] as AnyObject],
                                       sourceFiles: sourceFiles1)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry1,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)

    let sourceFiles2 = ["2.swift"]
    let buildLabel2 = BuildLabel("test/app:TestLibrary")
    let ruleEntry2 = makeTestRuleEntry(buildLabel2,
                                       type: "objc_library",
                                       attributes: ["pch": ["path": pchFile.path!, "src": true] as AnyObject],
                                       sourceFiles: sourceFiles2)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry2,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)

    let indexerTargetName = String(format: "_idx_TestLibrary_TestBinary_%08X",
                                   buildLabel1.hashValue &+ buildLabel2.hashValue)
    validateIndexerTarget(indexerTargetName,
                          sourceFileNames: sourceFiles1 + sourceFiles2,
                          pchFile: pchFile,
                          inTargets: targets)
  }

  func testIndexerCharacterLimit() {
    let sourceFiles1 = ["1.swift", "1.cc"]
    let buildTargetName1 = String(repeating: "A", count: 300)
    let buildLabel1 = BuildLabel("test/app:" + buildTargetName1)
    let ruleEntry1 = makeTestRuleEntry(buildLabel1,
                                       type: "ios_binary",
                                       attributes: ["pch": ["path": pchFile.path!, "src": true] as AnyObject],
                                       sourceFiles: sourceFiles1)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry1,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)

    let resultingTarget = targets.values.first!
    XCTAssertLessThan(resultingTarget.name.characters.count, 200)

    validateIndexerTarget(resultingTarget.name,
                          sourceFileNames: sourceFiles1,
                          pchFile: pchFile,
                          inTargets: targets)
  }

  func testCompatibleIndexersMergeCharacterLimit() {
    let sourceFiles1 = ["1.swift", "1.cc"]
    let buildTargetName1 = String(repeating: "A", count: 200)
    let buildLabel1 = BuildLabel("test/app:" + buildTargetName1)
    let ruleEntry1 = makeTestRuleEntry(buildLabel1,
                                       type: "ios_binary",
                                       attributes: ["pch": ["path": pchFile.path!, "src": true] as AnyObject],
                                       sourceFiles: sourceFiles1)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry1,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)

    let sourceFiles2 = ["2.swift"]
    let buildTargetName2 = String(repeating: "B", count: 200)
    let buildLabel2 = BuildLabel("test/app:" + buildTargetName2)
    let ruleEntry2 = makeTestRuleEntry(buildLabel2,
                                       type: "objc_library",
                                       attributes: ["pch": ["path": pchFile.path!, "src": true] as AnyObject],
                                       sourceFiles: sourceFiles2)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry2,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)

    let resultingTarget = targets.values.first!
    XCTAssertLessThan(resultingTarget.name.characters.count, 200)

    validateIndexerTarget(resultingTarget.name,
                          sourceFileNames: sourceFiles1 + sourceFiles2,
                          pchFile: pchFile,
                          inTargets: targets)
  }

  func testDoesNotMergeIndexerWithPCHMismatch() {
    let buildLabel1 = BuildLabel("test/app:TestBinary")
    let ruleEntry1 = makeTestRuleEntry(buildLabel1,
                                       type: "ios_binary",
                                       attributes: ["pch": ["path": pchFile.path!, "src": true] as AnyObject],
                                       sourceFiles: sourceFileNames)
    let indexer1TargetName = String(format: "_idx_TestBinary_%08X", buildLabel1.hashValue)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry1,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)

    let buildLabel2 = BuildLabel("test/app:TestLibrary")
    let ruleEntry2 = makeTestRuleEntry(buildLabel2,
                                       type: "objc_library",
                                       attributes: [:],
                                       sourceFiles: sourceFileNames)
    let indexer2TargetName = String(format: "_idx_TestLibrary_%08X", buildLabel2.hashValue)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry2,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)
    validateIndexerTarget(indexer1TargetName,
                          sourceFileNames: sourceFileNames,
                          pchFile: pchFile,
                          inTargets: targets)
    validateIndexerTarget(indexer2TargetName,
                          sourceFileNames: sourceFileNames,
                          inTargets: targets)
  }

  func testDoesNotMergeIndexerWithGeneratedBridgingHeaderMismatch() {
    let bridgingHeaderFilePath = "some/place/bridging-header.h"
    let bridgingHeaderInfo = ["path": bridgingHeaderFilePath,
                              "root": "bazel-genfiles",
                              "src": false] as [String : Any]
    let ruleAttributes1 = ["bridging_header": bridgingHeaderInfo]

    let buildLabel1 = BuildLabel("test/app:TestBinary")
    let ruleEntry1 = makeTestRuleEntry(buildLabel1,
                                       type: "ios_binary",
                                       attributes: ruleAttributes1 as [String : AnyObject],
                                       sourceFiles: sourceFileNames)
    let indexer1TargetName = String(format: "_idx_TestBinary_%08X", buildLabel1.hashValue)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry1,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)

    let buildLabel2 = BuildLabel("test/app:TestLibrary")
    let ruleEntry2 = makeTestRuleEntry(buildLabel2,
                                       type: "objc_library",
                                       attributes: [:],
                                       sourceFiles: sourceFileNames)
    let indexer2TargetName = String(format: "_idx_TestLibrary_%08X", buildLabel2.hashValue)
    targetGenerator.registerRuleEntryForIndexer(ruleEntry2,
                                                ruleEntryMap: [:],
                                                pathFilters: pathFilters)
    targetGenerator.generateIndexerTargets()

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)
    validateIndexerTarget(indexer1TargetName,
                          sourceFileNames: sourceFileNames,
                          bridgingHeader: "$(TULSI_WR)/bazel-genfiles/\(bridgingHeaderFilePath)",
                          inTargets: targets)
    validateIndexerTarget(indexer2TargetName,
                          sourceFileNames: sourceFileNames,
                          inTargets: targets)
  }

  func testImplicitIPATargetListedAsFirstArtifact() {
    let targetName = "TestTarget"
    let package = "test/package/1"
    let target = "\(package):\(targetName)"
    let targetType = "ios_test"
    let ipa = BuildLabel("test/app:TestApplication.ipa")

    let testRule = makeTestRuleEntry(target,
                                     type: targetType,
                                     artifacts: ["some/path/to/an/ipa.ipa",
                                                 "test/app/TestApplication.ipa"],
                                     implicitIPATarget: ipa)
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([testRule], ruleEntryMap: [:])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }
    XCTAssert(!messageLogger.warningMessageKeys.contains("MissingTestHost"))

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)

    let expectedBuildSettings = [
        "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
        "BAZEL_OUTPUTS": "test/app/TestApplication.ipa\nsome/path/to/an/ipa.ipa",
        "BAZEL_TARGET": target,
        "BAZEL_TARGET_TYPE": targetType,
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "INFOPLIST_FILE": "TestInfo.plist",
        "PRODUCT_NAME": targetName,
        "SDKROOT": "iphoneos",
        "TULSI_BUILD_PATH": package,
        "TULSI_USE_DSYM": "NO",
        "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
    ]
    let expectedTarget = TargetDefinition(
        name: "TestTarget",
        buildConfigurations: [
            BuildConfigurationDefinition(
                name: "Debug",
                expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
            ),
            BuildConfigurationDefinition(
                name: "Release",
                expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
            ),
            BuildConfigurationDefinition(
                name: "__TulsiTestRunner_Debug",
                expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
            ),
            BuildConfigurationDefinition(
                name: "__TulsiTestRunner_Release",
                expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
            ),
        ],
        expectedBuildPhases: [
            BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: target)
        ]
    )
    assertTarget(expectedTarget, inTargets: targets)
  }

  func testSwiftTargetsGeneratedSYMBundles() {
    let targetName = "TestTarget"
    let package = "test/package"
    let target = "\(package):\(targetName)"
    let targetType = "ios_application"

    let swiftTargetName = "SwiftTarget"
    let swiftTarget = "\(package):\(swiftTargetName)"

    let testRule = makeTestRuleEntry(target,
                                     type: targetType,
                                     attributes: ["has_swift_dependency": true as AnyObject],
                                     dependencies: Set([swiftTarget]))
    let swiftLibraryRule = makeTestRuleEntry(swiftTarget, type: "swift_library")

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([testRule],
                                                             ruleEntryMap: [BuildLabel(swiftTarget): swiftLibraryRule])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }
    XCTAssert(!messageLogger.warningMessageKeys.contains("MissingTestHost"))

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)

    let expectedBuildSettings = [
        "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "Stub Launch Image",
        "BAZEL_TARGET": target,
        "BAZEL_TARGET_TYPE": targetType,
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "INFOPLIST_FILE": "TestInfo.plist",
        "PRODUCT_NAME": targetName,
        "SDKROOT": "iphoneos",
        "TULSI_BUILD_PATH": package,
        "TULSI_USE_DSYM": "YES",
        "TULSI_USE_DYNAMIC_OUTPUTS": "YES",
    ]
    let expectedTarget = TargetDefinition(
        name: "TestTarget",
        buildConfigurations: [
            BuildConfigurationDefinition(
                name: "Debug",
                expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
            ),
            BuildConfigurationDefinition(
                name: "Release",
                expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
            ),
            BuildConfigurationDefinition(
                name: "__TulsiTestRunner_Debug",
                expectedBuildSettings: debugTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
            ),
            BuildConfigurationDefinition(
                name: "__TulsiTestRunner_Release",
                expectedBuildSettings: releaseTestRunnerBuildSettingsFromSettings(expectedBuildSettings)
            ),
        ],
        expectedBuildPhases: [
            BazelShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: target)
        ]
    )
    assertTarget(expectedTarget, inTargets: targets)
  }

  // MARK: - Helper methods

  private func debugBuildSettingsFromSettings(_ settings: [String: String]) -> [String: String] {
    var newSettings = settings
    newSettings["GCC_PREPROCESSOR_DEFINITIONS"] = "DEBUG=1"
    return newSettings
  }

  private func releaseBuildSettingsFromSettings(_ settings: [String: String],
                                                indexerSettingsOnly: Bool = false) -> [String: String] {
    var newSettings = settings
    newSettings["GCC_PREPROCESSOR_DEFINITIONS"] = "NDEBUG=1"
    if !indexerSettingsOnly {
      newSettings["TULSI_USE_DSYM"] = "YES"
    }
    return newSettings
  }

  private func debugTestRunnerBuildSettingsFromSettings(_ settings: [String: String]) -> [String: String] {
    let testRunnerSettings = addTestRunnerSettings(settings)
    return debugBuildSettingsFromSettings(testRunnerSettings)
  }

  private func releaseTestRunnerBuildSettingsFromSettings(_ settings: [String: String]) -> [String: String] {
    let testRunnerSettings = addTestRunnerSettings(settings)
    return releaseBuildSettingsFromSettings(testRunnerSettings)
  }

  private func addTestRunnerSettings(_ settings: [String: String]) -> [String: String] {
    var testRunnerSettings = settings
    if let _ = testRunnerSettings["DEBUG_INFORMATION_FORMAT"] {
      testRunnerSettings["DEBUG_INFORMATION_FORMAT"] = "dwarf"
    }
    testRunnerSettings["ONLY_ACTIVE_ARCH"] = "YES"
    testRunnerSettings["OTHER_CFLAGS"] = "-help"
    testRunnerSettings["OTHER_LDFLAGS"] = "-help"
    testRunnerSettings["OTHER_SWIFT_FLAGS"] = "-help"
    testRunnerSettings["SWIFT_OBJC_INTERFACE_HEADER_NAME"] = "$(PRODUCT_NAME).h"
    testRunnerSettings["SWIFT_INSTALL_OBJC_HEADER"] = "NO"

    testRunnerSettings["FRAMEWORK_SEARCH_PATHS"] = ""
    testRunnerSettings["HEADER_SEARCH_PATHS"] = ""
    return testRunnerSettings
  }

  private func rebuildSourceFileReferences() {
    sourceFileReferences = []
    for file in sourceFileNames {
      sourceFileReferences.append(project.mainGroup.getOrCreateFileReferenceBySourceTree(.Group, path: file))
    }
  }

  private func makeTestRuleEntry(_ label: String,
                                 type: String,
                                 attributes: [String: AnyObject] = [:],
                                 artifacts: [String] = [],
                                 sourceFiles: [String] = [],
                                 dependencies: Set<String> = Set(),
                                 extensions: Set<BuildLabel>? = nil,
                                 bundleID: String? = nil,
                                 extensionBundleID: String? = nil,
                                 buildFilePath: String? = nil,
                                 swiftLanguageVersion: String? = nil,
                                 implicitIPATarget: BuildLabel? = nil) -> RuleEntry {
    return makeTestRuleEntry(BuildLabel(label),
                             type: type,
                             attributes: attributes,
                             artifacts: artifacts,
                             sourceFiles: sourceFiles,
                             dependencies: dependencies,
                             extensions: extensions,
                             bundleID: bundleID,
                             extensionBundleID: extensionBundleID,
                             buildFilePath: buildFilePath,
                             swiftLanguageVersion: swiftLanguageVersion,
                             implicitIPATarget: implicitIPATarget)
  }

  private class TestBazelFileInfo : BazelFileInfo {
    init(fullPath: String) {
      super.init(rootPath: "", subPath: fullPath, isDirectory: false, targetType: .sourceFile)
    }
  }

  private func makeTestRuleEntry(_ label: BuildLabel,
                                 type: String,
                                 attributes: [String: AnyObject] = [:],
                                 artifacts: [String] = [],
                                 sourceFiles: [String] = [],
                                 dependencies: Set<String> = Set(),
                                 extensions: Set<BuildLabel>? = nil,
                                 bundleID: String? = nil,
                                 extensionBundleID: String? = nil,
                                 buildFilePath: String? = nil,
                                 swiftLanguageVersion: String? = nil,
                                 implicitIPATarget: BuildLabel? = nil) -> RuleEntry {
    let artifactInfos = artifacts.map() { TestBazelFileInfo(fullPath: $0) }
    let sourceInfos = sourceFiles.map() { TestBazelFileInfo(fullPath: $0) }
    return RuleEntry(label: label,
                     type: type,
                     attributes: attributes,
                     artifacts: artifactInfos,
                     sourceFiles: sourceInfos,
                     dependencies: dependencies,
                     extensions: extensions,
                     bundleID: bundleID,
                     extensionBundleID: extensionBundleID,
                     buildFilePath: buildFilePath,
                     swiftLanguageVersion: swiftLanguageVersion,
                     implicitIPATarget: implicitIPATarget)
  }

  private struct TargetDefinition {
    let name: String
    let buildConfigurations: [BuildConfigurationDefinition]
    let expectedBuildPhases: [BuildPhaseDefinition]
  }

  private struct BuildConfigurationDefinition {
    let name: String
    let expectedBuildSettings: Dictionary<String, String>?
  }

  private class BuildPhaseDefinition {
    let isa: String
    let files: [String]
    let fileSet: Set<String>
    let mainGroup: PBXReference?
    let mnemonic: String

    init (isa: String, files: [String], mainGroup: PBXReference? = nil, mnemonic: String = "") {
      self.isa = isa
      self.files = files
      self.fileSet = Set(files)
      self.mainGroup = mainGroup
      self.mnemonic = mnemonic
    }

    func validate(_ phase: PBXBuildPhase, line: UInt = #line) {
      // Validate the file set.
      XCTAssertEqual(phase.files.count,
                     fileSet.count,
                     "Mismatch in file count in build phase:\n\(phase.files)\n\(fileSet)",
                     line: line)
      for buildFile in phase.files {
        let path = buildFile.fileRef.sourceRootRelativePath
        XCTAssert(fileSet.contains(path),
                  "Found unexpected file '\(path)' in build phase",
                  line: line)
      }
      XCTAssertEqual(phase.mnemonic, mnemonic, "Mismatch in mnemonics")
    }
  }

  private class SourcesBuildPhaseDefinition: BuildPhaseDefinition {
    let settings: [String: String]?

    init(files: [String], mainGroup: PBXReference, settings: [String: String]? = nil) {
      self.settings = settings
      super.init(isa: "PBXSourcesBuildPhase",
                 files: files,
                 mainGroup: mainGroup,
                 mnemonic: "CompileSources")
    }

    override func validate(_ phase: PBXBuildPhase, line: UInt = #line) {
      super.validate(phase, line: line)

      for buildFile in phase.files {
        if settings != nil {
          XCTAssertNotNil(buildFile.settings, "Settings for file \(buildFile) must == \(String(describing: settings))",
                          line: line)
          if buildFile.settings != nil {
            XCTAssertEqual(buildFile.settings!, settings!, line: line)
          }
        } else {
          XCTAssertNil(buildFile.settings, "Settings for file \(buildFile) must be nil",
                       line: line)
        }
      }
    }
  }

  private class BazelShellScriptBuildPhaseDefinition: BuildPhaseDefinition {
    let bazelURL: URL
    let buildTarget: String

    init(bazelURL: URL, buildTarget: String) {
      self.bazelURL = bazelURL
      self.buildTarget = buildTarget
      super.init(isa: "PBXShellScriptBuildPhase", files: [], mnemonic: "BazelBuild")
    }

    override func validate(_ phase: PBXBuildPhase, line: UInt = #line) {
      super.validate(phase, line: line)

      // Guaranteed by the test infrastructure below, failing this indicates a programming error in
      // the test fixture, not in the code being tested.
      let scriptBuildPhase = phase as! PBXShellScriptBuildPhase

      let script = scriptBuildPhase.shellScript

      // TODO(abaire): Consider doing deeper validation of the script.
      XCTAssert(script.contains(bazelURL.path),
                "Build script does not contain \(bazelURL.path)",
                line: line)
      XCTAssert(script.contains(buildTarget),
                "Build script does not contain build target \(buildTarget)",
                line: line)
    }
  }

  private class SwiftDummyShellScriptBuildPhaseDefinition: BuildPhaseDefinition {
    init() {
      super.init(isa: "PBXShellScriptBuildPhase", files: [], mnemonic: "SwiftDummy")
    }

    override func validate(_ phase: PBXBuildPhase, line: UInt = #line) {
      super.validate(phase, line: line)

      // Guaranteed by the test infrastructure below, failing this indicates a programming error in
      // the test fixture, not in the code being tested.
      let scriptBuildPhase = phase as! PBXShellScriptBuildPhase

      let script = scriptBuildPhase.shellScript
      XCTAssert(script.contains("touch"), "Build script does not contain 'touch'.",
                line: line)
    }
  }

  private func fileRefForPath(_ path: String) -> PBXReference? {
    let components = path.components(separatedBy: "/")
    var node = project.mainGroup
    componentLoop: for component in components {
      for child in node.children {
        if child.name == component {
          if let childGroup = child as? PBXGroup {
            node = childGroup
            continue componentLoop
          } else if component == components.last! {
            return child
          } else {
            return nil
          }
        }
      }
    }
    return nil
  }

  private func validateIndexerTarget(_ indexerTargetName: String,
                                     sourceFileNames: [String]?,
                                     pchFile: PBXFileReference? = nil,
                                     bridgingHeader: String? = nil,
                                     swiftLanguageVersion: String? = nil,
                                     inTargets targets: Dictionary<String, PBXTarget> = Dictionary<String, PBXTarget>(),
                                     line: UInt = #line) {
    var expectedBuildSettings = [
        "ARCHS": "x86_64",
        "HEADER_SEARCH_PATHS": "$(inherited) $(TULSI_BWRS)/tools/cpp/gcc3 ",
        "PRODUCT_NAME": indexerTargetName,
        "SDKROOT": "iphonesimulator",
        "VALID_ARCHS": "x86_64",
    ]
    if pchFile != nil {
      expectedBuildSettings["GCC_PREFIX_HEADER"] = "$(TULSI_BWRS)/\(pchFile!.path!)"
    }
    if bridgingHeader != nil {
        expectedBuildSettings["SWIFT_OBJC_BRIDGING_HEADER"] = bridgingHeader!
    }
    if let swiftLanguageVersion = swiftLanguageVersion {
      expectedBuildSettings["SWIFT_VERSION"] = swiftLanguageVersion
    }

    var expectedBuildPhases = [BuildPhaseDefinition]()
    if sourceFileNames != nil {
      expectedBuildPhases.append(SourcesBuildPhaseDefinition(files: sourceFileNames!,
                                                             mainGroup: project.mainGroup))
    }

    let expectedTarget = TargetDefinition(
        name: indexerTargetName,
        buildConfigurations: [
            BuildConfigurationDefinition(
              name: "Debug",
              expectedBuildSettings: debugBuildSettingsFromSettings(expectedBuildSettings)
            ),
            BuildConfigurationDefinition(
              name: "Release",
              expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings,
                                                                      indexerSettingsOnly: true)
            ),
        ],
        expectedBuildPhases: expectedBuildPhases
    )
    assertTarget(expectedTarget, inTargets: targets, line: line)
  }

  private func assertTarget(_ targetDef: TargetDefinition,
                            inTargets targets: Dictionary<String, PBXTarget>,
                            line: UInt = #line) {
    guard let target = targets[targetDef.name] else {
      XCTFail("Missing expected target '\(targetDef.name)'", line: line)
      return
    }

    let buildConfigs = target.buildConfigurationList.buildConfigurations
    XCTAssertEqual(buildConfigs.count,
                   targetDef.buildConfigurations.count,
                   "Build config mismatch in target '\(targetDef.name)'",
                   line: line)

    for buildConfigDef in targetDef.buildConfigurations {
      guard let config = buildConfigs[buildConfigDef.name] else {
        XCTFail("Missing expected build configuration '\(buildConfigDef.name)' in target '\(targetDef.name)'",
                line: line)
        continue
      }

      if buildConfigDef.expectedBuildSettings != nil {
        XCTAssertEqual(config.buildSettings,
                       buildConfigDef.expectedBuildSettings!,
                       "Build config mismatch for configuration '\(buildConfigDef.name)' in target '\(targetDef.name)'",
                       line: line)
      } else {
        XCTAssert(config.buildSettings.isEmpty, line: line)
      }
    }

    validateExpectedBuildPhases(targetDef.expectedBuildPhases,
                                inTarget: target,
                                line: line)
  }

  private func validateExpectedBuildPhases(_ phaseDefs: [BuildPhaseDefinition],
                                           inTarget target: PBXTarget,
                                           line: UInt = #line) {
    let buildPhases = target.buildPhases
    XCTAssertEqual(buildPhases.count,
                   phaseDefs.count,
                   "Build phase count mismatch in target '\(target.name)'",
                   line: line)

    var validationCount = 0
    for phaseDef in phaseDefs {
      for phase in buildPhases {
        if phase.isa != phaseDef.isa || phase.mnemonic != phaseDef.mnemonic {
          continue
        }
        phaseDef.validate(phase, line: line)
        validationCount += 1
      }
    }
    XCTAssertEqual(validationCount,
                   buildPhases.count,
                   "Validation count mismatch in target '\(target.name)'")
  }
}


