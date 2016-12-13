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


class XcodeProjectGeneratorTests: XCTestCase {
  static let outputFolderPath = "/dev/null/project"
  static let projectName = "ProjectName"

  let outputFolderURL = NSURL(fileURLWithPath: XcodeProjectGeneratorTests.outputFolderPath)
  let xcodeProjectPath = "\(XcodeProjectGeneratorTests.outputFolderPath)/\(XcodeProjectGeneratorTests.projectName).xcodeproj"

  let workspaceRoot = NSURL(fileURLWithPath: "/workspace")
  let testTulsiVersion = "9.99.999.9999"

  let buildTargetLabels = ["//test:MainTarget", "//test/path/to/target:target"].map({ BuildLabel($0) })
  let pathFilters = Set<String>(["test", "additional"])

  let additionalFilePaths = ["additional/File1", "additional/File2"]

  let bazelURL = NSURL(fileURLWithPath: "/test/dir/testBazel")

  let resourceURLs = XcodeProjectGenerator.ResourceSourcePathURLs(
      buildScript: NSURL(fileURLWithPath: "/scripts/Build"),
      cleanScript: NSURL(fileURLWithPath: "/scripts/Clean"),
      postProcessor: NSURL(fileURLWithPath: "/utils/covmap_patcher"),
      stubInfoPlist: NSURL(fileURLWithPath: "/generatedProjectResources/StubInfoPlist.plist"),
      stubIOSAppExInfoPlist: NSURL(fileURLWithPath: "/generatedProjectResources/stubIOSAppExInfoPlist.plist"),
      stubWatchOS2InfoPlist: NSURL(fileURLWithPath: "/generatedProjectResources/StubWatchOS2InfoPlist.plist"),
      stubWatchOS2AppExInfoPlist: NSURL(fileURLWithPath: "/generatedProjectResources/StubWatchOS2AppExInfoPlist.plist"))

  var config: TulsiGeneratorConfig! = nil
  var mockLocalizedMessageLogger: MockLocalizedMessageLogger! = nil
  var mockFileManager: MockFileManager! = nil
  var mockExtractor: MockWorkspaceInfoExtractor! = nil
  var generator: XcodeProjectGenerator! = nil

  var writtenFiles = Set<String>()

  override func setUp() {
    super.setUp()
    mockLocalizedMessageLogger = MockLocalizedMessageLogger()
    mockFileManager = MockFileManager()
    mockExtractor = MockWorkspaceInfoExtractor()
    writtenFiles.removeAll()
  }

  func testSuccessfulGeneration() {
    let ruleEntries = XcodeProjectGeneratorTests.labelToRuleEntryMapForLabels(buildTargetLabels)
    prepareGenerator(ruleEntries)
    do {
      try generator.generateXcodeProjectInFolder(outputFolderURL)
      mockLocalizedMessageLogger.assertNoErrors()
      mockLocalizedMessageLogger.assertNoWarnings()

      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/project.pbxproj"))
      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings"))
      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/project.xcworkspace/xcuserdata/USER.xcuserdatad/WorkspaceSettings.xcsettings"))
      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/test-path-to-target-target.xcscheme"))
      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/test-MainTarget.xcscheme"))
    } catch let e {
      XCTFail("Unexpected exception \(e)")
    }
  }

  func testUnresolvedLabelsThrows() {
    let ruleEntries = XcodeProjectGeneratorTests.labelToRuleEntryMapForLabels(buildTargetLabels)
    prepareGenerator(ruleEntries)
    mockExtractor.labelToRuleEntry = [:]
    do {
      try generator.generateXcodeProjectInFolder(outputFolderURL)
      XCTFail("Generation succeeded unexpectedly")
    } catch XcodeProjectGenerator.Error.LabelResolutionFailed(let missingLabels) {
      for label in buildTargetLabels {
        XCTAssert(missingLabels.contains(label), "Expected missing label \(label) not found")
      }
    } catch let e {
      XCTFail("Unexpected exception \(e)")
    }
  }

  func testTestSuiteSchemeGeneration() {
    func addRule(labelName: String,
                 type: String,
                 attributes: [String: AnyObject] = [:],
                 weakDependencies: Set<BuildLabel>? = nil) -> BuildLabel {
      let label = BuildLabel(labelName)
      mockExtractor.labelToRuleEntry[label] = self.dynamicType.makeRuleEntry(label,
                                                                             type: type,
                                                                             attributes: attributes,
                                                                             weakDependencies: weakDependencies)
      return label
    }

    let app = addRule("//test:Application", type: "ios_application")
    let test1 = addRule("//test:TestOne", type: "ios_test", attributes: ["xctest_app": app.value])
    let test2 = addRule("//test:TestTwo", type: "ios_test", attributes: ["xctest_app": app.value])
    addRule("//test:UnusedTest", type: "ios_test")
    addRule("//test:TestSuite", type: "test_suite", weakDependencies: Set([test1, test2]))
    prepareGenerator(mockExtractor.labelToRuleEntry)

    do {
      try generator.generateXcodeProjectInFolder(outputFolderURL)
      mockLocalizedMessageLogger.assertNoErrors()
      mockLocalizedMessageLogger.assertNoWarnings()

      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/project.pbxproj"))
      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings"))
      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/project.xcworkspace/xcuserdata/USER.xcuserdatad/WorkspaceSettings.xcsettings"))
      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/test-Application.xcscheme"))
      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/test-TestOne.xcscheme"))
      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/test-TestTwo.xcscheme"))
      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/test-UnusedTest.xcscheme"))
      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/TestSuite_Suite.xcscheme"))
    } catch let e {
      XCTFail("Unexpected exception \(e)")
    }
  }

  func testProjectSDKROOT() {
    func validate(types: [String], _ expectedSDKROOT: String?, line: UInt = #line) {
      let rules = types.map() {
        XcodeProjectGeneratorTests.makeRuleEntry(BuildLabel($0), type: $0)
      }
      let sdkroot = XcodeProjectGenerator.projectSDKROOT(rules)
      XCTAssertEqual(sdkroot, expectedSDKROOT, line: line)
    }

    validate(["ios_application"], "iphoneos")
    validate(["ios_application", "ios_application"], "iphoneos")
    validate(["ios_application", "apple_watch2_extension"], "iphoneos")
    validate(["apple_watch2_extension"], "watchos")
    validate(["apple_watch2_extension", "apple_watch2_extension"], "watchos")
    validate(["apple_watch2_extension", "_tvos_extension"], nil)
    validate(["ios_application", "apple_watch2_extension", "_tvos_extension"], nil)
    validate(["ios_application", "_tvos_extension"], nil)
    validate(["_tvos_extension"], "appletvos")
  }

  // MARK: - Private methods

  private static func labelToRuleEntryMapForLabels(labels: [BuildLabel]) -> [BuildLabel: RuleEntry] {
    var ret = [BuildLabel: RuleEntry]()
    for label in labels {
      ret[label] = makeRuleEntry(label, type: "ios_application")
    }
    return ret
  }

  private static func makeRuleEntry(label: BuildLabel,
                                    type: String,
                                    attributes: [String: AnyObject] = [:],
                                    artifacts: [BazelFileInfo] = [],
                                    sourceFiles: [BazelFileInfo] = [],
                                    nonARCSourceFiles: [BazelFileInfo] = [],
                                    dependencies: Set<String> = Set(),
                                    secondaryArtifacts: [BazelFileInfo] = [],
                                    weakDependencies: Set<BuildLabel>? = nil,
                                    buildFilePath: String? = nil,
                                    generatedIncludePaths: [RuleEntry.IncludePath]? = nil,
                                    implicitIPATarget: BuildLabel? = nil) -> RuleEntry {
    return RuleEntry(label: label,
                     type: type,
                     attributes: attributes,
                     artifacts: artifacts,
                     sourceFiles: sourceFiles,
                     nonARCSourceFiles: nonARCSourceFiles,
                     dependencies: dependencies,
                     secondaryArtifacts: secondaryArtifacts,
                     weakDependencies: weakDependencies,
                     buildFilePath: buildFilePath,
                     generatedIncludePaths: generatedIncludePaths,
                     implicitIPATarget: implicitIPATarget)
  }

  private func prepareGenerator(ruleEntries: [BuildLabel: RuleEntry]) {
    config = TulsiGeneratorConfig(projectName: XcodeProjectGeneratorTests.projectName,
                                  buildTargetLabels: Array(ruleEntries.keys),
                                  pathFilters: pathFilters,
                                  additionalFilePaths: additionalFilePaths,
                                  options: TulsiOptionSet(),
                                  bazelURL: bazelURL)
    let projectURL = NSURL(fileURLWithPath: xcodeProjectPath, isDirectory: true)
    mockFileManager.allowedDirectoryCreates.insert(projectURL.path!)
#if swift(>=2.3)
    let xcshareddata = projectURL.URLByAppendingPathComponent("project.xcworkspace/xcshareddata")!
#else
    let xcshareddata = projectURL.URLByAppendingPathComponent("project.xcworkspace/xcshareddata")
#endif
    mockFileManager.allowedDirectoryCreates.insert(xcshareddata.path!)
#if swift(>=2.3)
    let xcuserdata = projectURL.URLByAppendingPathComponent("project.xcworkspace/xcuserdata/USER.xcuserdatad")!
#else
    let xcuserdata = projectURL.URLByAppendingPathComponent("project.xcworkspace/xcuserdata/USER.xcuserdatad")
#endif
    mockFileManager.allowedDirectoryCreates.insert(xcuserdata.path!)
#if swift(>=2.3)
    let xcschemes = projectURL.URLByAppendingPathComponent("xcshareddata/xcschemes")!
#else
    let xcschemes = projectURL.URLByAppendingPathComponent("xcshareddata/xcschemes")
#endif
    mockFileManager.allowedDirectoryCreates.insert(xcschemes.path!)
#if swift(>=2.3)
    let scripts = projectURL.URLByAppendingPathComponent(".tulsi/Scripts")!
#else
    let scripts = projectURL.URLByAppendingPathComponent(".tulsi/Scripts")
#endif
    mockFileManager.allowedDirectoryCreates.insert(scripts.path!)
#if swift(>=2.3)
    let utils = projectURL.URLByAppendingPathComponent(".tulsi/Utils")!
#else
    let utils = projectURL.URLByAppendingPathComponent(".tulsi/Utils")
#endif
    mockFileManager.allowedDirectoryCreates.insert(utils.path!)
#if swift(>=2.3)
    let resources = projectURL.URLByAppendingPathComponent(".tulsi/Resources")!
#else
    let resources = projectURL.URLByAppendingPathComponent(".tulsi/Resources")
#endif
    mockFileManager.allowedDirectoryCreates.insert(resources.path!)

    mockExtractor.labelToRuleEntry = ruleEntries

    generator = XcodeProjectGenerator(workspaceRootURL: workspaceRoot,
                                      config: config,
                                      localizedMessageLogger: mockLocalizedMessageLogger,
                                      workspaceInfoExtractor: mockExtractor,
                                      resourceURLs: resourceURLs,
                                      tulsiVersion: testTulsiVersion,
                                      fileManager: mockFileManager,
                                      pbxTargetGeneratorType: MockPBXTargetGenerator.self)
    generator.writeDataHandler = { (url, _) in
      self.writtenFiles.insert(url.path!)
    }
    generator.usernameFetcher = { "USER" }
  }
}


class MockFileManager: NSFileManager {
  var filesThatExist = Set<String>()
  var allowedDirectoryCreates = Set<String>()
  var copyOperations = [String: String]()

  override func fileExistsAtPath(path: String) -> Bool {
    return filesThatExist.contains(path)
  }

  override func createDirectoryAtURL(url: NSURL,
                                     withIntermediateDirectories createIntermediates: Bool,
                                     attributes: [String:AnyObject]?) throws {
    if allowedDirectoryCreates.contains(url.path!) { return }
    throw NSError(domain: "MockFileManager: Directory creation disallowed",
                  code: 0,
                  userInfo: nil)
  }

  override func createDirectoryAtPath(path: String,
                                      withIntermediateDirectories createIntermediates: Bool,
                                      attributes: [String:AnyObject]?) throws {
    if allowedDirectoryCreates.contains(path) { return }
    throw NSError(domain: "MockFileManager: Directory creation disallowed",
                  code: 0,
                  userInfo: nil)
  }

  override func removeItemAtURL(URL: NSURL) throws {
    throw NSError(domain: "MockFileManager: removeItem disallowed", code: 0, userInfo: nil)
  }

  override func removeItemAtPath(path: String) throws {
    throw NSError(domain: "MockFileManager: removeItem disallowed", code: 0, userInfo: nil)
  }

  override func copyItemAtURL(srcURL: NSURL, toURL dstURL: NSURL) throws {
    copyOperations[dstURL.path!] = srcURL.path!
  }

  override func copyItemAtPath(srcPath: String, toPath dstPath: String) throws {
    copyOperations[dstPath] = srcPath
  }
}


final class MockPBXTargetGenerator: PBXTargetGeneratorProtocol {
  var project: PBXProject

  static func getRunTestTargetBuildConfigPrefix() -> String {
    return "TestRunner__"
  }

  static func workingDirectoryForPBXGroup(group: PBXGroup) -> String {
    return ""
  }

  static func mainGroupForOutputFolder(outputFolderURL: NSURL, workspaceRootURL: NSURL) -> PBXGroup {
    return PBXGroup(name: "mainGroup",
                    path: "/A/Test/Path",
                    sourceTree: .Absolute,
                    parent: nil)
  }

  required init(bazelURL: NSURL,
                bazelBinPath: String,
                project: PBXProject,
                buildScriptPath: String,
                stubInfoPlistPaths: StubInfoPlistPaths,
                tulsiVersion: String,
                options: TulsiOptionSet,
                localizedMessageLogger: LocalizedMessageLogger,
                workspaceRootURL: NSURL,
                suppressCompilerDefines: Bool,
                redactWorkspaceSymlink: Bool) {
    self.project = project
  }

  func generateFileReferencesForFilePaths(paths: [String], pathFilters: Set<String>?) {
  }

  func registerRuleEntryForIndexer(ruleEntry: RuleEntry,
                                   ruleEntryMap: [BuildLabel:RuleEntry],
                                   pathFilters: Set<String>) {
  }

  func generateIndexerTargets() -> [String: PBXTarget] {
    return [:]
  }

  func generateBazelCleanTarget(scriptPath: String, workingDirectory: String) {
  }

  func generateTopLevelBuildConfigurations(buildSettingOverrides: [String: String]) {
  }

  func generateBuildTargetsForRuleEntries(ruleEntries: Set<RuleEntry>,
                                          ruleEntryMap: [BuildLabel: RuleEntry]) throws -> [String: [String]] {
    let namedRuleEntries = ruleEntries.map() { (e: RuleEntry) -> (String, RuleEntry) in
      return (e.label.asFullPBXTargetName!, e)
    }

    var testTargetLinkages = [(PBXTarget, BuildLabel)]()
    for (name, entry) in namedRuleEntries {
      let target = project.createNativeTarget(name, targetType: entry.pbxTargetType!)

      if let hostLabelString = entry.attributes[.xctest_app] as? String {
        let hostLabel = BuildLabel(hostLabelString)
        testTargetLinkages.append((target, hostLabel))
      }
    }

    for (testTarget, testHostLabel) in testTargetLinkages {
      let hostTarget = project.targetByName(testHostLabel.asFullPBXTargetName!) as! PBXNativeTarget
      project.linkTestTarget(testTarget, toHostTarget: hostTarget)
    }

    return [:]
  }
}
