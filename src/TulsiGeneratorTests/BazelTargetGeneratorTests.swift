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
class BazelTargetGeneratorTests: XCTestCase {
  let bazelURL = NSURL(fileURLWithPath: "__BAZEL_BINARY_")
  let rootURL = NSURL.fileURLWithPath("/root", isDirectory: true)
  var project: PBXProject! = nil
  var targetGenerator: BazelTargetGenerator! = nil

  override func setUp() {
    super.setUp()
    project = PBXProject(name: "TestProject")
    targetGenerator = BazelTargetGenerator(bazelURL: bazelURL,
                                           project: project,
                                           buildScriptPath: "",
                                           labelResolver: MockLabelResolver(),
                                           options: TulsiOptionSet(),
                                           localizedMessageLogger: MockLocalizedMessageLogger())

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
                            line: UInt = __LINE__) {
      let outputURL = NSURL(fileURLWithPath: output, isDirectory: true)
      let workspaceURL = NSURL(fileURLWithPath: workspace, isDirectory: true)
      let group = BazelTargetGenerator.mainGroupForOutputFolder(outputURL,
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


class BazelTargetGeneratorTestsWithFiles: XCTestCase {
  let bazelURL = NSURL(fileURLWithPath: "__BAZEL_BINARY_")
  let sdkRoot = "sdkRoot"
  var project: PBXProject! = nil
  var targetGenerator: BazelTargetGenerator! = nil
  var labelResolver: MockLabelResolver! = nil

  var sourceFileNames = ["test.swift", "test.cc"]
  var sourceFileReferences = [PBXFileReference]()
  var pchFile: PBXFileReference! = nil

  override func setUp() {
    super.setUp()

    project = PBXProject(name: "TestProject")
    let mainGroup = project.mainGroup
    sourceFileReferences = []
    for file in sourceFileNames {
      sourceFileReferences.append(mainGroup.getOrCreateFileReferenceBySourceTree(.Group, path: file))
    }
    pchFile = mainGroup.getOrCreateFileReferenceBySourceTree(.Group, path: "pch.pch")
    labelResolver = MockLabelResolver()
    let options = TulsiOptionSet()
    options[.SDKROOT]!.projectValue = sdkRoot
    targetGenerator = BazelTargetGenerator(bazelURL: bazelURL,
                                           project: project,
                                           buildScriptPath: "",
                                           labelResolver: labelResolver,
                                           options: options,
                                           localizedMessageLogger: MockLocalizedMessageLogger())
  }

  // MARK: - Tests

  func testGenerateBazelCleanTarget() {
    let scriptPath = "scriptPath"
    let workingDirectory = "/directory/of/work"
    targetGenerator.generateBazelCleanTarget(scriptPath, workingDirectory: workingDirectory)
    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)

    XCTAssertNotNil(targets[BazelTargetGenerator.BazelCleanTarget] as? PBXLegacyTarget)
    let target = targets[BazelTargetGenerator.BazelCleanTarget] as! PBXLegacyTarget

    XCTAssertEqual(target.buildToolPath, scriptPath)

    // The script should launch the test scriptPath with bazelURL's path as the only argument.
    let expectedScriptArguments = "\"\(bazelURL.path!)\""
    XCTAssertEqual(target.buildArgumentsString, expectedScriptArguments)
  }

  func testGenerateBazelCleanTargetAppliesToRulesAddedBeforeAndAfter() {
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([RuleEntry(label: BuildLabel("before"), type: "ios_application")],
                                                             sourcePaths: nil)
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    targetGenerator.generateBazelCleanTarget("scriptPath")

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([RuleEntry(label: BuildLabel("after"), type: "ios_application")],
                                                             sourcePaths: nil)
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 3)

    XCTAssertNotNil(targets[BazelTargetGenerator.BazelCleanTarget] as? PBXLegacyTarget)
    let integrationTarget = targets[BazelTargetGenerator.BazelCleanTarget] as! PBXLegacyTarget

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
    XCTAssertEqual(topLevelConfigs.count, 3)

    let topLevelBuildSettings = [
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CODE_SIGN_IDENTITY": "",
        "CODE_SIGNING_REQUIRED": "NO",
        "ENABLE_TESTABILITY": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "8.4",
        "ONLY_ACTIVE_ARCH": "YES",
        "SDKROOT": sdkRoot,
        "USER_HEADER_SEARCH_PATHS": "$(PROJECT_DIR)",
    ]
    XCTAssertNotNil(topLevelConfigs["Debug"])
    XCTAssertEqual(topLevelConfigs["Debug"]!.buildSettings, topLevelBuildSettings)
    XCTAssertNotNil(topLevelConfigs["Release"])
    XCTAssertEqual(topLevelConfigs["Release"]!.buildSettings, topLevelBuildSettings)
    XCTAssertNotNil(topLevelConfigs["Fastbuild"])
    XCTAssertEqual(topLevelConfigs["Fastbuild"]!.buildSettings, topLevelBuildSettings)
  }

  func testGenerateTargetsForRuleEntriesWithNoEntries() {
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries([], sourcePaths: nil)
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
    let rules = [
      RuleEntry(label: BuildLabel(rule1BuildTarget), type: "ios_application"),
      RuleEntry(label: BuildLabel(rule2BuildTarget), type: "objc_library"),
    ]

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, sourcePaths: nil)
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 0)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)

    do {
      let expectedBuildSettings = [
          "BUILD_PATH": rule1BuildPath,
          "PRODUCT_NAME": rule1TargetName,
      ]
      let expectedTarget = TargetDefinition(
          name: rule1TargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
          "BUILD_PATH": rule2BuildPath,
          "PRODUCT_NAME": rule2TargetName,
      ]
      let expectedTarget = TargetDefinition(
          name: rule2TargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
    let rules = [
      RuleEntry(label: BuildLabel(rule1BuildTarget), type: "ios_application"),
      RuleEntry(label: BuildLabel(rule2BuildTarget), type: "ios_test", attributes: rule2Attributes),
    ]

    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, sourcePaths: nil)
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 0)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)

    do {
      let expectedBuildSettings = [
          "BUILD_PATH": rule1BuildPath,
          "PRODUCT_NAME": rule1TargetName,
      ]
      let expectedTarget = TargetDefinition(
          name: rule1TargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
          "BUILD_PATH": rule2BuildPath,
          "BUNDLE_LOADER": "$(TEST_HOST)",
          "PRODUCT_NAME": rule2TargetName,
          "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(rule1TargetName).app/\(rule1TargetName)",
      ]
      let expectedTarget = TargetDefinition(
          name: rule2TargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
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
    let testRule = RuleEntry(label: BuildLabel(testRuleBuildTarget),
                             type: "ios_test",
                             attributes: testRuleAttributes)
    let rules = [
      RuleEntry(label: BuildLabel(rule1BuildTarget), type: "ios_application"),
      testRule,
    ]
    let testSources = ["sourceFile1.m", "sourceFile2.mm"]
    let sourcePaths = [testRule: testSources]
    do {
      try targetGenerator.generateBuildTargetsForRuleEntries(rules, sourcePaths: sourcePaths)
    } catch let e as NSError {
      XCTFail("Failed to generate build targets with error \(e.localizedDescription)")
    }

    // Configs will be minimally generated for Debug and the test runner dummy.
    let topLevelConfigs = project.buildConfigurationList.buildConfigurations
    XCTAssertEqual(topLevelConfigs.count, 2)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 2)
    do {
      let expectedBuildSettings = [
          "BUILD_PATH": rule1BuildPath,
          "PRODUCT_NAME": rule1TargetName,
      ]
      var testRunnerExpectedBuildSettings = expectedBuildSettings
      testRunnerExpectedBuildSettings["DEBUG_INFORMATION_FORMAT"] = "dwarf"
      testRunnerExpectedBuildSettings["ONLY_ACTIVE_ARCH"] = "YES"
      testRunnerExpectedBuildSettings["OTHER_CFLAGS"] = "-help"
      testRunnerExpectedBuildSettings["OTHER_LDFLAGS"] = "-help"
      let expectedTarget = TargetDefinition(
          name: rule1TargetName,
          buildConfigurations: [
              BuildConfigurationDefinition(
                  name: "Debug",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunnerConfig_DO_NOT_USE_MANUALLY",
                  expectedBuildSettings: testRunnerExpectedBuildSettings
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
          "BUILD_PATH": testRuleBuildPath,
          "BUNDLE_LOADER": "$(TEST_HOST)",
          "PRODUCT_NAME": testRuleTargetName,
          "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(rule1TargetName).app/\(rule1TargetName)",
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
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Release",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "Fastbuild",
                  expectedBuildSettings: expectedBuildSettings
              ),
              BuildConfigurationDefinition(
                  name: "__TulsiTestRunnerConfig_DO_NOT_USE_MANUALLY",
                  expectedBuildSettings: testRunnerExpectedBuildSettings
              ),
          ],
          expectedBuildPhases: [
              SourcesBuildPhaseDefinition(files: testSources),
              ShellScriptBuildPhaseDefinition(bazelURL: bazelURL,
                                              buildTarget: testRuleBuildTarget)
          ]
      )
      assertTarget(expectedTarget, inTargets: targets)
    }
  }

  func testGenerateIndexerWithNoSources() {
    let ruleEntry = RuleEntry(label: BuildLabel("test/app:TestApp"), type: "ios_application")
    targetGenerator.generateIndexerTargetForRuleEntry(ruleEntry, sourcePaths: [])
    let targets = project.targetByName
    XCTAssert(targets.isEmpty)
  }

  func testGenerateIndexerWithNoPCHFile() {
    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = RuleEntry(label: buildLabel, type: "ios_application")
    let indexerTargetName = "_indexer_TestApp_\(buildLabel.hashValue)"

    targetGenerator.generateIndexerTargetForRuleEntry(ruleEntry, sourcePaths: sourceFileNames)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName, sourceFileNames: sourceFileNames, inTargets: targets)
  }

  func testGenerateIndexer() {
    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = RuleEntry(label: BuildLabel("test/app:TestApp"), type: "ios_application")
    let indexerTargetName = "_indexer_TestApp_\(buildLabel.hashValue)"

    let sourcesAndPCHFile = sourceFileNames + [pchFile.path!]
    targetGenerator.generateIndexerTargetForRuleEntry(ruleEntry, sourcePaths: sourcesAndPCHFile)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName, sourceFileNames: sourceFileNames, pchFile: pchFile, inTargets: targets)
  }

  func testGenerateIndexerWithBridgingHeader() {
    let bridgingHeaderLabel = "//some/place:bridging-header.h"
    let bridgingHeaderFilePath = "some/place/bridging-header.h"
    labelResolver.registerPath(bridgingHeaderFilePath,
        targetType: BazelFileTarget.TargetType.SourceFile,
        forLabel: BuildLabel(bridgingHeaderLabel))
    let ruleAttributes = ["bridging_header": bridgingHeaderLabel]

    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = RuleEntry(label: buildLabel, type: "ios_binary", attributes: ruleAttributes)
    let indexerTargetName = "_indexer_TestApp_\(buildLabel.hashValue)"

    targetGenerator.generateIndexerTargetForRuleEntry(ruleEntry, sourcePaths: sourceFileNames)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName,
        sourceFileNames: sourceFileNames,
        bridgingHeader: "$(SRCROOT)/\(bridgingHeaderFilePath)",
        inTargets: targets)
  }

  func testGenerateIndexerWithGeneratedBridgingHeader() {
    let bridgingHeaderLabel = "//some/place:bridging-header.h"
    let bridgingHeaderFilePath = "some/place/bridging-header.h"
    labelResolver.registerPath(bridgingHeaderFilePath,
        targetType: BazelFileTarget.TargetType.GeneratedFile,
        forLabel: BuildLabel(bridgingHeaderLabel))
    let ruleAttributes = ["bridging_header": bridgingHeaderLabel]

    let buildLabel = BuildLabel("test/app:TestApp")
    let ruleEntry = RuleEntry(label: buildLabel, type: "ios_binary", attributes: ruleAttributes)
    let indexerTargetName = "_indexer_TestApp_\(buildLabel.hashValue)"

    targetGenerator.generateIndexerTargetForRuleEntry(ruleEntry, sourcePaths: sourceFileNames)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName,
        sourceFileNames: sourceFileNames,
        bridgingHeader: "bazel-genfiles/\(bridgingHeaderFilePath)",
        inTargets: targets)
  }

  func testGenerateIndexerWithNestedBridgingHeader() {
    let nestedRuleLabel = "//nested/rule:label"
    let bridgingHeaderLabel = "//some/place:bridging-header.h"
    let bridgingHeaderFilePath = "some/place/bridging-header.h"
    let nestedRuleAttributes = ["bridging_header": bridgingHeaderLabel]
    labelResolver.registerPath(bridgingHeaderFilePath,
        targetType: BazelFileTarget.TargetType.SourceFile,
        forLabel: BuildLabel(bridgingHeaderLabel))
    let nestedRule = RuleEntry(label: BuildLabel(nestedRuleLabel), type: "ios_binary", attributes: nestedRuleAttributes)

    let topLevelRuleAttributes = ["binary": nestedRuleLabel]
    let buildLabel = BuildLabel("test/app:TestApp")
    let topLevelRule = RuleEntry(label: buildLabel, type: "ios_application", attributes: topLevelRuleAttributes)
    topLevelRule.dependencies[nestedRuleLabel] = nestedRule
    let indexerTargetName = "_indexer_TestApp_\(buildLabel.hashValue)"

    targetGenerator.generateIndexerTargetForRuleEntry(topLevelRule, sourcePaths: sourceFileNames)

    let targets = project.targetByName
    XCTAssertEqual(targets.count, 1)
    validateIndexerTarget(indexerTargetName,
        sourceFileNames: sourceFileNames,
        bridgingHeader: "$(SRCROOT)/\(bridgingHeaderFilePath)",
        inTargets: targets)
  }

  // MARK: - Helper methods

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

    init (isa: String, files: [String]) {
      self.isa = isa
      self.files = files
      self.fileSet = Set(files)
    }

    func validate(phase: PBXBuildPhase, file: String = __FILE__, line: UInt = __LINE__) {
      // Validate the file set.
      XCTAssertEqual(phase.files.count,
                     fileSet.count,
                     "Mismatch in file count in build phase",
                     file: file,
                     line: line)
      for buildFile in phase.files {
        let path = buildFile.fileRef.path!
        XCTAssert(fileSet.contains(path),
                  "Found unexpected file '\(path)' in build phase",
                  file: file,
                  line: line)
      }
    }
  }

  private class SourcesBuildPhaseDefinition: BuildPhaseDefinition {
    let settings: [String: String]?

    init(files: [String], settings: [String: String]? = nil) {
      self.settings = settings
      super.init(isa: "PBXSourcesBuildPhase", files: files)
    }

    override func validate(phase: PBXBuildPhase, file: String = __FILE__, line: UInt = __LINE__) {
      super.validate(phase, file: file, line: line)

      for buildFile in phase.files {
        if settings != nil {
          XCTAssertNotNil(buildFile.settings, "Settings for file \(buildFile) must == \(settings)",
                          file: file,
                          line: line)
          if buildFile.settings != nil {
            XCTAssertEqual(buildFile.settings!, settings!, file: file, line: line)
          }
        } else {
          XCTAssertNil(buildFile.settings, "Settings for file \(buildFile) must be nil",
                       file: file,
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

    override func validate(phase: PBXBuildPhase, file: String = __FILE__, line: UInt = __LINE__) {
      super.validate(phase, file: file, line: line)

      // Guaranteed by the test infrastructure below, failing this indicates a programming error in
      // the test fixture, not in the code being tested.
      let scriptBuildPhase = phase as! PBXShellScriptBuildPhase

      let script = scriptBuildPhase.shellScript

      // TODO(abaire): Consider doing deeper validation of the script.
      XCTAssert(script.containsString(bazelURL.path!), file: file, line: line)
      XCTAssert(script.containsString(buildTarget), file: file, line: line)
    }
  }

  private func validateIndexerTarget(indexerTargetName: String,
                                     sourceFileNames: [String]?,
                                     pchFile: PBXFileReference? = nil,
                                     bridgingHeader: String? = nil,
                                     inTargets targets: Dictionary<String, PBXTarget> = Dictionary<String, PBXTarget>(),
                                     file: String = __FILE__,
                                     line: UInt = __LINE__) {
    var expectedBuildSettings = [
        "PRODUCT_NAME": indexerTargetName,
    ]
    if pchFile != nil {
      expectedBuildSettings["GCC_PREFIX_HEADER"] = pchFile!.path!
    }
    if bridgingHeader != nil {
        expectedBuildSettings["SWIFT_OBJC_BRIDGING_HEADER"] = bridgingHeader!
    }

    var expectedBuildPhases = [BuildPhaseDefinition]()
    if sourceFileNames != nil {
      expectedBuildPhases.append(SourcesBuildPhaseDefinition(files: sourceFileNames!))
    }

    let expectedTarget = TargetDefinition(
        name: indexerTargetName,
        buildConfigurations: [
            BuildConfigurationDefinition(
              name: "Debug",
              expectedBuildSettings: expectedBuildSettings
            ),
            BuildConfigurationDefinition(
              name: "Release",
              expectedBuildSettings: expectedBuildSettings
            ),
            BuildConfigurationDefinition(
              name: "Fastbuild",
              expectedBuildSettings: expectedBuildSettings
            ),
        ],
        expectedBuildPhases: expectedBuildPhases
    )
    assertTarget(expectedTarget, inTargets: targets, file: file, line: line)
  }

  private func assertTarget(targetDef: TargetDefinition,
                            inTargets targets: Dictionary<String, PBXTarget>,
                            file: String = __FILE__,
                            line: UInt = __LINE__) {
    guard let target = targets[targetDef.name] else {
      XCTFail("Missing expected target '\(targetDef.name)'", file: file, line: line)
      return
    }

    let buildConfigs = target.buildConfigurationList.buildConfigurations
    XCTAssertEqual(buildConfigs.count,
                   targetDef.buildConfigurations.count,
                   "Build config mismatch in target '\(targetDef.name)'",
                   file: file,
                   line: line)

    for buildConfigDef in targetDef.buildConfigurations {
      let config: XCBuildConfiguration? = buildConfigs[buildConfigDef.name]
      XCTAssertNotNil(config,
                      "Missing expected build configuration '\(buildConfigDef.name)' in target '\(targetDef.name)'",
                      file: file,
                      line: line)

      if buildConfigDef.expectedBuildSettings != nil {
        XCTAssertEqual(config!.buildSettings,
                       buildConfigDef.expectedBuildSettings!,
                       "Build config mismatch for configuration '\(buildConfigDef.name)' in target '\(targetDef.name)'",
                       file: file,
                       line: line)
      } else {
        XCTAssert(config!.buildSettings.isEmpty, file: file, line: line)
      }
    }

    validateExpectedBuildPhases(targetDef.expectedBuildPhases,
                                inTarget: target,
                                file: file,
                                line: line)
  }

  private func validateExpectedBuildPhases(phaseDefs: [BuildPhaseDefinition],
                                           inTarget target: PBXTarget,
                                           file: String = __FILE__,
                                           line: UInt = __LINE__) {
    let buildPhases = target.buildPhases
    XCTAssertEqual(buildPhases.count,
                   phaseDefs.count,
                   "Build phase count mismatch in target '\(target.name)'",
                   file: file,
                   line: line)

    for phaseDef in phaseDefs {
      for phase in buildPhases {
        if phase.isa != phaseDef.isa {
          continue
        }
        phaseDef.validate(phase, file: file, line: line)
      }
    }
  }
}


