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
  let bazelURL = NSURL(fileURLWithPath: "__BAZEL_BINARY_")
  let workspaceRootURL = NSURL(fileURLWithPath: "/workspaceRootURL", isDirectory: true)
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
                                         envScriptPath: "",
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
      XCTAssert(buildFilePaths.contains(fileRef.sourceRootRelativePath), "Path mismatch for generated BUILD file \(fileRef.path)")
      XCTAssertEqual(fileRef.sourceTree, SourceTree.Group, "SourceTree mismatch for generated BUILD file \(fileRef.path)")
    }
  }

  func testMainGroupForOutputFolder() {
    func assertOutputFolder(output: String,
                            workspace: String,
                            generatesSourceTree sourceTree: SourceTree,
                            path: String?,
                            line: UInt = #line) {
      let outputURL = NSURL(fileURLWithPath: output, isDirectory: true)
      let workspaceURL = NSURL(fileURLWithPath: workspace, isDirectory: true)
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
  let bazelURL = NSURL(fileURLWithPath: "__BAZEL_BINARY_")
  let workspaceRootURL = NSURL(fileURLWithPath: "/workspaceRootURL", isDirectory: true)
  let sdkRoot = "sdkRoot"
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
    options[.SDKROOT].projectValue = sdkRoot
    messageLogger = MockLocalizedMessageLogger()
    targetGenerator = PBXTargetGenerator(bazelURL: bazelURL,
                                         bazelBinPath: "bazel-bin",
                                         project: project,
                                         buildScriptPath: "",
                                         envScriptPath: "",
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
    let expectedScriptArguments = "\"\(bazelURL.path!)\" \"bazel-bin\""
    XCTAssertEqual(target.buildArgumentsString, expectedScriptArguments)
  }

  func testGenerateBazelCleanTargetAppliesToRulesAddedBeforeAndAfter() {
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([makeTestRuleEntry("before", type: "ios_application")])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    targetGenerator.generateBazelCleanTarget("scriptPath")

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([makeTestRuleEntry("after", type: "ios_application")])
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
          PBXContainerItemProxy.ProxyType.TargetReference,
          "Mismatch in target dependency type for target added \(target.name)")
    }
  }

  func testGenerateTopLevelBuildConfigurations() {
    targetGenerator.generateTopLevelBuildConfigurations()

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 5)

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
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "HEADER_SEARCH_PATHS": "$(TULSI_WR) $(TULSI_WR)/bazel-bin $(TULSI_WR)/bazel-genfiles",
        "IPHONEOS_DEPLOYMENT_TARGET": "8.4",
        "ONLY_ACTIVE_ARCH": "YES",
        "SDKROOT": sdkRoot,
        "TULSI_VERSION": testTulsiVersion,
        "TULSI_WR": "$(SRCROOT)",
    ]

    XCTAssertNotNil(topLevelConfigs["Debug"])
    XCTAssertEqual(topLevelConfigs["Debug"]!.buildSettings,
                   debugBuildSettingsFromSettings(topLevelBuildSettings))
    XCTAssertNotNil(topLevelConfigs["Release"])
    XCTAssertEqual(topLevelConfigs["Release"]!.buildSettings,
                   releaseBuildSettingsFromSettings(topLevelBuildSettings))
    XCTAssertNotNil(topLevelConfigs["Fastbuild"])
    XCTAssertEqual(topLevelConfigs["Fastbuild"]!.buildSettings, topLevelBuildSettings)
    XCTAssertNotNil(topLevelConfigs["__TulsiTestRunner_Debug"])
    XCTAssertEqual(topLevelConfigs["__TulsiTestRunner_Debug"]!.buildSettings,
                   debugTestRunnerBuildSettingsFromSettings(topLevelBuildSettings))
    XCTAssertNotNil(topLevelConfigs["__TulsiTestRunner_Release"])
    XCTAssertEqual(topLevelConfigs["__TulsiTestRunner_Release"]!.buildSettings,
                   releaseTestRunnerBuildSettingsFromSettings(topLevelBuildSettings))
  }

  func testGenerateTargetsForRuleEntriesWithNoEntries() {
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([])
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
      try targetGenerator.generateBuildTargetsForRuleEntries(rules)
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 0)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)

    do {
      let expectedBuildSettings = [
          "BAZEL_TARGET": "test/app:TestApplication",
          "BAZEL_TARGET_IPA": ipa.asFileName!,
          "PRODUCT_NAME": rule1TargetName,
          "TULSI_BUILD_PATH": rule1BuildPath,
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
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
              ShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule1BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
          "BAZEL_TARGET": "test/objclib:ObjectiveCLibrary",
          "PRODUCT_NAME": rule2TargetName,
          "TULSI_BUILD_PATH": rule2BuildPath,
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
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
              ShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule2BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateTargetsForLinkedRuleEntriesWithNoSources() {
    let rule1BuildPath = "test/app"
    let rule1TargetName = "TestApplication"
    let rule1BuildTarget = "\(rule1BuildPath):\(rule1TargetName)"
    let rule2BuildPath = "test/testbundle"
    let rule2TargetName = "TestBundle"
    let rule2BuildTarget = "\(rule2BuildPath):\(rule2TargetName)"
    let rule2Attributes = ["xctest_app": rule1BuildTarget]
    let ipa = BuildLabel("test/app:TestApplication.ipa")
    let rules = Set([
      makeTestRuleEntry(rule1BuildTarget, type: "ios_application", implicitIPATarget: ipa),
      makeTestRuleEntry(rule2BuildTarget,
                        type: "ios_test",
                        attributes: rule2Attributes,
                        implicitIPATarget: ipa),
    ])

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules)
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
          "BAZEL_TARGET": "test/app:TestApplication",
          "BAZEL_TARGET_IPA": ipa.asFileName!,
          "PRODUCT_NAME": rule1TargetName,
          "TULSI_BUILD_PATH": rule1BuildPath,
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
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
              ShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule1BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
          "BAZEL_TARGET": "test/testbundle:TestBundle",
          "BAZEL_TARGET_IPA": ipa.asFileName!,
          "BUNDLE_LOADER": "$(TEST_HOST)",
          "PRODUCT_NAME": rule2TargetName,
          "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(rule1TargetName).app/\(rule1TargetName)",
          "TULSI_BUILD_PATH": rule2BuildPath,
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
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
              ShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule2BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateTargetsForLinkedRuleEntriesWithSources() {
    let rule1BuildPath = "test/app"
    let rule1TargetName = "TestApplication"
    let rule1BuildTarget = "\(rule1BuildPath):\(rule1TargetName)"
    let testRuleBuildPath = "test/testbundle"
    let testRuleTargetName = "TestBundle"
    let testRuleBuildTarget = "\(testRuleBuildPath):\(testRuleTargetName)"
    let testRuleAttributes = ["xctest_app": rule1BuildTarget]
    let testSources = ["sourceFile1.m", "sourceFile2.mm"]
    let appIPA = BuildLabel("test/app:TestApplication.ipa")
    let testIPA = BuildLabel("test/testbundle/TestBundle.ipa")
    let testRule = makeTestRuleEntry(testRuleBuildTarget,
                                     type: "ios_test",
                                     attributes: testRuleAttributes,
                                     sourceFiles: testSources,
                                     implicitIPATarget: testIPA)
    let rules = Set([
      makeTestRuleEntry(rule1BuildTarget, type: "ios_application", implicitIPATarget: appIPA),
      testRule,
    ])
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules)
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }
    XCTAssert(!messageLogger.warningMessageKeys.contains("MissingTestHost"))

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)
    do {
      let expectedBuildSettings = [
          "BAZEL_TARGET": "test/app:TestApplication",
          "BAZEL_TARGET_IPA": appIPA.asFileName!,
          "PRODUCT_NAME": rule1TargetName,
          "TULSI_BUILD_PATH": rule1BuildPath,
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
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
              ShellScriptBuildPhaseDefinition(bazelURL: bazelURL,
                                              buildTarget: rule1BuildTarget),
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
          "BAZEL_TARGET": "test/testbundle:TestBundle",
          "BAZEL_TARGET_IPA": testIPA.asFileName!,
          "BUNDLE_LOADER": "$(TEST_HOST)",
          "PRODUCT_NAME": testRuleTargetName,
          "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(rule1TargetName).app/\(rule1TargetName)",
          "TULSI_BUILD_PATH": testRuleBuildPath,
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
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
              ShellScriptBuildPhaseDefinition(bazelURL: bazelURL,
                                              buildTarget: testRuleBuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateTargetsForLinkedRuleEntriesWithSameTestHostNameInDifferentPackages() {
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
                                      type: "ios_test",
                                      attributes: ["xctest_app": host1Target],
                                      sourceFiles: testSources)
    let test2Rule = makeTestRuleEntry(test2Target,
                                      type: "ios_test",
                                      attributes: ["xctest_app": host2Target],
                                      sourceFiles: testSources)
    let rules = Set([
      makeTestRuleEntry(host1Target, type: "ios_application"),
      makeTestRuleEntry(host2Target, type: "ios_application"),
      test1Rule,
      test2Rule,
    ])
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules)
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }
    XCTAssert(!messageLogger.warningMessageKeys.contains("MissingTestHost"))
  }

  func testGenerateTargetsForLinkedRuleEntriesWithoutIncludingTheHostWarns() {
    let rule1BuildPath = "test/app"
    let rule1TargetName = "TestApplication"
    let rule1BuildTarget = "\(rule1BuildPath):\(rule1TargetName)"
    let testRuleBuildPath = "test/testbundle"
    let testRuleTargetName = "TestBundle"
    let testRuleBuildTarget = "\(testRuleBuildPath):\(testRuleTargetName)"
    let testRuleAttributes = ["xctest_app": rule1BuildTarget]
    let testSources = ["sourceFile1.m", "sourceFile2.mm"]
    let ipa = BuildLabel("test/app:TestApplication.ipa")
    let testRule = makeTestRuleEntry(testRuleBuildTarget,
                                     type: "ios_test",
                                     attributes: testRuleAttributes,
                                     sourceFiles: testSources,
                                     implicitIPATarget: ipa)
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([testRule])
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
      return
    }

    XCTAssert(messageLogger.warningMessageKeys.contains("MissingTestHost"))
    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    do {
      let expectedBuildSettings = [
          "BAZEL_TARGET": "test/testbundle:TestBundle",
          "BAZEL_TARGET_IPA": ipa.asFileName!,
          "PRODUCT_NAME": testRuleTargetName,
          "TULSI_BUILD_PATH": testRuleBuildPath,
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
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
              ShellScriptBuildPhaseDefinition(bazelURL: bazelURL,
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
      try targetGenerator.generateBuildTargetsForRuleEntries(rules)
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 0)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)

    do {
      let expectedBuildSettings = [
          "BAZEL_TARGET": "test/test1:\(targetName)",
          "BAZEL_TARGET_IPA": rule1IPA.asFileName!,
          "PRODUCT_NAME": "test-test1-SameName",
          "TULSI_BUILD_PATH": rule1BuildPath,
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
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
              ShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule1BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
    do {
      let expectedBuildSettings = [
          "BAZEL_TARGET": "test/test2:\(targetName)",
          "BAZEL_TARGET_IPA": rule2IPA.asFileName!,
          "PRODUCT_NAME": "test-test2-SameName",
          "TULSI_BUILD_PATH": rule2BuildPath,
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
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
              ShellScriptBuildPhaseDefinition(bazelURL: bazelURL, buildTarget: rule2BuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateIndexerWithNoSources() {
    let ruleEntry = makeTestRuleEntry("test/app:TestApp", type: "ios_application")
    targetGenerator.generateIndexerTargetsForRuleEntry(ruleEntry,
                                                       ruleEntryMap: [:],
                                                       pathFilters: pathFilters)
    let targets = project.targetByName
    XCTAssert(targets.isEmpty)
  }

  func testGenerateIndexerWithNoPCHFile() {
    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry(buildLabel,
                                      type: "ios_application",
                                      sourceFiles: sourceFileNames)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.generateIndexerTargetsForRuleEntry(ruleEntry,
                                                       ruleEntryMap: [:],
                                                       pathFilters: pathFilters)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName, sourceFileNames: sourceFileNames, inTargets: targets)
  }

  func testGenerateIndexer() {
    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry("test/app:TestApp",
                                      type: "ios_application",
                                      attributes: ["pch": ["path": pchFile.path!, "src": true]],
                                      sourceFiles: sourceFileNames)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.generateIndexerTargetsForRuleEntry(ruleEntry,
                                                       ruleEntryMap: [:],
                                                       pathFilters: pathFilters)

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
                                      attributes: ruleAttributes,
                                      sourceFiles: sourceFileNames)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.generateIndexerTargetsForRuleEntry(ruleEntry,
                                                       ruleEntryMap: [:],
                                                       pathFilters: pathFilters)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName,
                          sourceFileNames: sourceFileNames,
                          bridgingHeader: "$(TULSI_WR)/\(bridgingHeaderFilePath)",
                          inTargets: targets)
  }

  func testGenerateIndexerWithGeneratedBridgingHeader() {
    let bridgingHeaderFilePath = "some/place/bridging-header.h"
    let bridgingHeaderInfo = ["path": bridgingHeaderFilePath,
                              "root": "bazel-genfiles",
                              "src": false]
    let ruleAttributes = ["bridging_header": bridgingHeaderInfo]

    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = makeTestRuleEntry(buildLabel,
                                      type: "ios_binary",
                                      attributes: ruleAttributes,
                                      sourceFiles: sourceFileNames)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.generateIndexerTargetsForRuleEntry(ruleEntry,
                                                       ruleEntryMap: [:],
                                                       pathFilters: pathFilters)

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
                                      attributes: ruleAttributes,
                                      sourceFiles: sourceFileNames)
    let indexerTargetName = String(format: "_idx_TestApp_%08X", buildLabel.hashValue)

    targetGenerator.generateIndexerTargetsForRuleEntry(ruleEntry,
                                                       ruleEntryMap: [:],
                                                       pathFilters: pathFilters.union(Set([dataModel])))

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

    targetGenerator.generateIndexerTargetsForRuleEntry(ruleEntry,
                                                       ruleEntryMap: [:],
                                                       pathFilters: pathFilters)

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

    targetGenerator.generateIndexerTargetsForRuleEntry(ruleEntry,
                                                       ruleEntryMap: [:],
                                                       pathFilters: pathFilters)

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
    targetGenerator.generateIndexerTargetsForRuleEntry(ruleEntry,
                                                       ruleEntryMap: [:],
                                                       pathFilters: pathFilters)
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
    targetGenerator.generateIndexerTargetsForRuleEntry(ruleEntry,
                                                       ruleEntryMap: [:],
                                                       pathFilters: pathFilters)
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
    targetGenerator.generateIndexerTargetsForRuleEntry(ruleEntry,
                                                       ruleEntryMap: [:],
                                                       pathFilters: pathFilters)
    XCTAssertNotNil(fileRefForPath(buildFilePath))
  }

  // MARK: - Helper methods

  private func debugBuildSettingsFromSettings(settings: [String: String]) -> [String: String] {
    var newSettings = settings
    newSettings["GCC_PREPROCESSOR_DEFINITIONS"] = "DEBUG=1"
    return newSettings
  }

  private func releaseBuildSettingsFromSettings(settings: [String: String]) -> [String: String] {
    var newSettings = settings
    newSettings["GCC_PREPROCESSOR_DEFINITIONS"] = "NDEBUG=1"
    return newSettings
  }

  private func debugTestRunnerBuildSettingsFromSettings(settings: [String: String]) -> [String: String] {
    let testRunnerSettings = addTestRunnerSettings(settings)
    return debugBuildSettingsFromSettings(testRunnerSettings)
  }

  private func releaseTestRunnerBuildSettingsFromSettings(settings: [String: String]) -> [String: String] {
    let testRunnerSettings = addTestRunnerSettings(settings)
    return releaseBuildSettingsFromSettings(testRunnerSettings)
  }

  private func addTestRunnerSettings(settings: [String: String]) -> [String: String] {
    var testRunnerSettings = settings
    testRunnerSettings["DEBUG_INFORMATION_FORMAT"] = "dwarf"
    testRunnerSettings["ONLY_ACTIVE_ARCH"] = "YES"
    testRunnerSettings["OTHER_CFLAGS"] = "-help"
    testRunnerSettings["OTHER_LDFLAGS"] = "-help"
    return testRunnerSettings
  }

  private func rebuildSourceFileReferences() {
    sourceFileReferences = []
    for file in sourceFileNames {
      sourceFileReferences.append(project.mainGroup.getOrCreateFileReferenceBySourceTree(.Group, path: file))
    }
  }

  private func makeTestRuleEntry(label: String,
                                 type: String,
                                 attributes: [String: AnyObject] = [:],
                                 sourceFiles: [String] = [],
                                 dependencies: Set<String> = Set(),
                                 buildFilePath: String? = nil,
                                 implicitIPATarget: BuildLabel? = nil) -> RuleEntry {
    return makeTestRuleEntry(BuildLabel(label),
                             type: type,
                             attributes: attributes,
                             sourceFiles: sourceFiles,
                             dependencies: dependencies,
                             buildFilePath: buildFilePath,
                             implicitIPATarget: implicitIPATarget)
  }

  private class TestBazelFileInfo : BazelFileInfo {
    init(fullPath: String) {
      super.init(rootPath: "", subPath: fullPath, targetType: .SourceFile)
    }
  }

  private func makeTestRuleEntry(label: BuildLabel,
                                 type: String,
                                 attributes: [String: AnyObject] = [:],
                                 sourceFiles: [String] = [],
                                 dependencies: Set<String> = Set(),
                                 buildFilePath: String? = nil,
                                 implicitIPATarget: BuildLabel? = nil) -> RuleEntry {
    let sourceInfos = sourceFiles.map() { TestBazelFileInfo(fullPath: $0) }
    return RuleEntry(label: label,
                     type: type,
                     attributes: attributes,
                     sourceFiles: sourceInfos,
                     nonARCSourceFiles: [],
                     dependencies: dependencies,
                     frameworkImports: [],
                     secondaryArtifacts: [],
                     buildFilePath: buildFilePath,
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

    init (isa: String, files: [String], mainGroup: PBXReference? = nil) {
      self.isa = isa
      self.files = files
      self.fileSet = Set(files)
      self.mainGroup = mainGroup
    }

    func validate(phase: PBXBuildPhase, line: UInt = #line) {
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
    }
  }

  private class SourcesBuildPhaseDefinition: BuildPhaseDefinition {
    let settings: [String: String]?

    init(files: [String], mainGroup: PBXReference, settings: [String: String]? = nil) {
      self.settings = settings
      super.init(isa: "PBXSourcesBuildPhase", files: files, mainGroup: mainGroup)
    }

    override func validate(phase: PBXBuildPhase, line: UInt = #line) {
      super.validate(phase, line: line)

      for buildFile in phase.files {
        if settings != nil {
          XCTAssertNotNil(buildFile.settings, "Settings for file \(buildFile) must == \(settings)",
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

  private class ShellScriptBuildPhaseDefinition: BuildPhaseDefinition {
    let bazelURL: NSURL
    let buildTarget: String

    init(bazelURL: NSURL, buildTarget: String) {
      self.bazelURL = bazelURL
      self.buildTarget = buildTarget
      super.init(isa: "PBXShellScriptBuildPhase", files: [])
    }

    override func validate(phase: PBXBuildPhase, line: UInt = #line) {
      super.validate(phase, line: line)

      // Guaranteed by the test infrastructure below, failing this indicates a programming error in
      // the test fixture, not in the code being tested.
      let scriptBuildPhase = phase as! PBXShellScriptBuildPhase

      let script = scriptBuildPhase.shellScript

      // TODO(abaire): Consider doing deeper validation of the script.
      XCTAssert(script.containsString(bazelURL.path!), line: line)
      XCTAssert(script.containsString(buildTarget), line: line)
    }
  }

  private func fileRefForPath(path: String) -> PBXReference? {
    let components = path.componentsSeparatedByString("/")
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

  private func validateIndexerTarget(indexerTargetName: String,
                                     sourceFileNames: [String]?,
                                     pchFile: PBXFileReference? = nil,
                                     bridgingHeader: String? = nil,
                                     inTargets targets: Dictionary<String, PBXTarget> = Dictionary<String, PBXTarget>(),
                                     line: UInt = #line) {
    var expectedBuildSettings = [
        "PRODUCT_NAME": indexerTargetName,
    ]
    if pchFile != nil {
      expectedBuildSettings["GCC_PREFIX_HEADER"] = "$(TULSI_WR)/\(pchFile!.path!)"
    }
    if bridgingHeader != nil {
        expectedBuildSettings["SWIFT_OBJC_BRIDGING_HEADER"] = bridgingHeader!
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
              expectedBuildSettings: releaseBuildSettingsFromSettings(expectedBuildSettings)
            ),
            BuildConfigurationDefinition(
              name: "Fastbuild",
              expectedBuildSettings: expectedBuildSettings
            ),
        ],
        expectedBuildPhases: expectedBuildPhases
    )
    assertTarget(expectedTarget, inTargets: targets, line: line)
  }

  private func assertTarget(targetDef: TargetDefinition,
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

  private func validateExpectedBuildPhases(phaseDefs: [BuildPhaseDefinition],
                                           inTarget target: PBXTarget,
                                           line: UInt = #line) {
    let buildPhases = target.buildPhases
    XCTAssertEqual(buildPhases.count,
                   phaseDefs.count,
                   "Build phase count mismatch in target '\(target.name)'",
                   line: line)

    for phaseDef in phaseDefs {
      for phase in buildPhases {
        if phase.isa != phaseDef.isa {
          continue
        }
        phaseDef.validate(phase, line: line)
      }
    }
  }
}


