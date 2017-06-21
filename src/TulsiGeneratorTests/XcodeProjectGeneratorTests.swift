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

  let outputFolderURL = URL(fileURLWithPath: XcodeProjectGeneratorTests.outputFolderPath)
  let xcodeProjectPath = "\(XcodeProjectGeneratorTests.outputFolderPath)/\(XcodeProjectGeneratorTests.projectName).xcodeproj"

  let workspaceRoot = URL(fileURLWithPath: "/workspace")
  let testTulsiVersion = "9.99.999.9999"

  let buildTargetLabels = ["//test:MainTarget", "//test/path/to/target:target"].map({ BuildLabel($0) })
  let pathFilters = Set<String>(["test", "additional"])

  let additionalFilePaths = ["additional/File1", "additional/File2"]

  let bazelURL = URL(fileURLWithPath: "/test/dir/testBazel")

  let resourceURLs = XcodeProjectGenerator.ResourceSourcePathURLs(
      buildScript: URL(fileURLWithPath: "/scripts/Build"),
      cleanScript: URL(fileURLWithPath: "/scripts/Clean"),
      extraBuildScripts: [URL(fileURLWithPath: "/scripts/Logging")],
      postProcessor: URL(fileURLWithPath: "/utils/covmap_patcher"),
      uiRunnerEntitlements: URL(fileURLWithPath: "/generatedProjectResources/XCTRunner.entitlements"),
      stubInfoPlist: URL(fileURLWithPath: "/generatedProjectResources/StubInfoPlist.plist"),
      stubIOSAppExInfoPlistTemplate: URL(fileURLWithPath: "/generatedProjectResources/stubIOSAppExInfoPlist.plist"),
      stubWatchOS2InfoPlist: URL(fileURLWithPath: "/generatedProjectResources/StubWatchOS2InfoPlist.plist"),
      stubWatchOS2AppExInfoPlist: URL(fileURLWithPath: "/generatedProjectResources/StubWatchOS2AppExInfoPlist.plist"),
      bazelWorkspaceFile: URL(fileURLWithPath: "/WORKSPACE"),
      tulsiPackageFiles: [URL(fileURLWithPath: "/tulsi/tulsi_aspects.bzl")])

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
      _ = try generator.generateXcodeProjectInFolder(outputFolderURL)
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

  func testExtensionPlistGeneration() {
    @discardableResult
    func addRule(_ labelName: String,
                 type: String,
                 attributes: [String: AnyObject] = [:],
                 weakDependencies: Set<BuildLabel>? = nil,
                 extensions: Set<BuildLabel>? = nil,
                 extensionType: String? = nil) -> BuildLabel {
      let label = BuildLabel(labelName)
      mockExtractor.labelToRuleEntry[label] = type(of: self).makeRuleEntry(label,
                                                                           type: type,
                                                                           attributes: attributes,
                                                                           weakDependencies: weakDependencies,
                                                                           extensions: extensions,
                                                                           extensionType: extensionType)
      return label
    }

    let test1 = addRule("//test:ExtFoo", type: "ios_extension", extensionType: "com.apple.extension-foo")
    let test2 = addRule("//test:ExtBar", type: "ios_extension", extensionType: "com.apple.extension-bar")
    addRule("//test:Application", type: "ios_application", extensions: [test1, test2])
    prepareGenerator(mockExtractor.labelToRuleEntry)

    func assertPlist(withData data: Data, equalTo value: NSDictionary) {
      let content = try! PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions.mutableContainers, format: nil) as! NSDictionary
      XCTAssertEqual(content, value)
    }

    do {
      _ = try generator.generateXcodeProjectInFolder(outputFolderURL)
      mockLocalizedMessageLogger.assertNoErrors()
      mockLocalizedMessageLogger.assertNoWarnings()

      XCTAssert(mockFileManager.writeOperations.keys.contains("\(xcodeProjectPath)/.tulsi/Resources/Stub_test-ExtFoo.plist"))
      assertPlist(withData: mockFileManager.writeOperations["\(xcodeProjectPath)/.tulsi/Resources/Stub_test-ExtFoo.plist"]!,
                  equalTo: ["NSExtension": ["NSExtensionPointIdentifier": "com.apple.extension-foo"]])

      XCTAssert(mockFileManager.writeOperations.keys.contains("\(xcodeProjectPath)/.tulsi/Resources/Stub_test-ExtBar.plist"))
      assertPlist(withData: mockFileManager.writeOperations["\(xcodeProjectPath)/.tulsi/Resources/Stub_test-ExtBar.plist"]!,
                  equalTo: ["NSExtension": ["NSExtensionPointIdentifier": "com.apple.extension-bar"]])
    } catch let e {
      XCTFail("Unexpected exception \(e)")
    }
  }

  func testUnresolvedLabelsThrows() {
    let ruleEntries = XcodeProjectGeneratorTests.labelToRuleEntryMapForLabels(buildTargetLabels)
    prepareGenerator(ruleEntries)
    mockExtractor.labelToRuleEntry = [:]
    do {
      _ = try generator.generateXcodeProjectInFolder(outputFolderURL)
      XCTFail("Generation succeeded unexpectedly")
    } catch XcodeProjectGenerator.ProjectGeneratorError.labelResolutionFailed(let missingLabels) {
      for label in buildTargetLabels {
        XCTAssert(missingLabels.contains(label), "Expected missing label \(label) not found")
      }
    } catch let e {
      XCTFail("Unexpected exception \(e)")
    }
  }

  func testTestSuiteSchemeGeneration() {
    checkTestSuiteSchemeGeneration("ios_test", testHostAttributeName: "xctest_app")
  }

  func testTestSuiteSchemeGenerationWithSkylarkUnitTest() {
    checkTestSuiteSchemeGeneration("apple_unit_test", testHostAttributeName: "test_host")
  }

  func testTestSuiteSchemeGenerationWithSkylarkUITest() {
    checkTestSuiteSchemeGeneration("apple_ui_test", testHostAttributeName: "test_host")
  }

  func checkTestSuiteSchemeGeneration(_ testRuleType: String, testHostAttributeName: String) {
    @discardableResult
    func addRule(_ labelName: String,
                 type: String,
                 attributes: [String: AnyObject] = [:],
                 weakDependencies: Set<BuildLabel>? = nil) -> BuildLabel {
      let label = BuildLabel(labelName)
      mockExtractor.labelToRuleEntry[label] = type(of: self).makeRuleEntry(label,
                                                                             type: type,
                                                                             attributes: attributes,
                                                                             weakDependencies: weakDependencies)
      return label
    }

    let app = addRule("//test:Application", type: "ios_application")
    let test1 = addRule("//test:TestOne", type: testRuleType, attributes: [testHostAttributeName: app.value as AnyObject])
    let test2 = addRule("//test:TestTwo", type: testRuleType, attributes: [testHostAttributeName: app.value as AnyObject])
    addRule("//test:UnusedTest", type: testRuleType)
    addRule("//test:TestSuite", type: "test_suite", weakDependencies: Set([test1, test2]))
    prepareGenerator(mockExtractor.labelToRuleEntry)

    do {
      _ = try generator.generateXcodeProjectInFolder(outputFolderURL)
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
    func validate(_ types: [String], _ expectedSDKROOT: String?, line: UInt = #line) {
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

  private static func labelToRuleEntryMapForLabels(_ labels: [BuildLabel]) -> [BuildLabel: RuleEntry] {
    var ret = [BuildLabel: RuleEntry]()
    for label in labels {
      ret[label] = makeRuleEntry(label, type: "ios_application")
    }
    return ret
  }

  private static func makeRuleEntry(_ label: BuildLabel,
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
                                    implicitIPATarget: BuildLabel? = nil,
                                    extensions: Set<BuildLabel>? = nil,
                                    extensionType: String? = nil) -> RuleEntry {
    return RuleEntry(label: label,
                     type: type,
                     attributes: attributes,
                     artifacts: artifacts,
                     sourceFiles: sourceFiles,
                     nonARCSourceFiles: nonARCSourceFiles,
                     dependencies: dependencies,
                     secondaryArtifacts: secondaryArtifacts,
                     weakDependencies: weakDependencies,
                     extensions: extensions,
                     buildFilePath: buildFilePath,
                     generatedIncludePaths: generatedIncludePaths,
                     implicitIPATarget: implicitIPATarget,
                     extensionType: extensionType)
  }

  private func prepareGenerator(_ ruleEntries: [BuildLabel: RuleEntry]) {
    config = TulsiGeneratorConfig(projectName: XcodeProjectGeneratorTests.projectName,
                                  buildTargetLabels: Array(ruleEntries.keys),
                                  pathFilters: pathFilters,
                                  additionalFilePaths: additionalFilePaths,
                                  options: TulsiOptionSet(),
                                  bazelURL: bazelURL)
    let projectURL = URL(fileURLWithPath: xcodeProjectPath, isDirectory: true)
    mockFileManager.allowedDirectoryCreates.insert(projectURL.path)

    let xcshareddata = projectURL.appendingPathComponent("project.xcworkspace/xcshareddata")
    mockFileManager.allowedDirectoryCreates.insert(xcshareddata.path)

    let xcuserdata = projectURL.appendingPathComponent("project.xcworkspace/xcuserdata/USER.xcuserdatad")
    mockFileManager.allowedDirectoryCreates.insert(xcuserdata.path)

    let xcschemes = projectURL.appendingPathComponent("xcshareddata/xcschemes")
    mockFileManager.allowedDirectoryCreates.insert(xcschemes.path)

    let scripts = projectURL.appendingPathComponent(".tulsi/Scripts")
    mockFileManager.allowedDirectoryCreates.insert(scripts.path)

    let utils = projectURL.appendingPathComponent(".tulsi/Utils")
    mockFileManager.allowedDirectoryCreates.insert(utils.path)

    let resources = projectURL.appendingPathComponent(".tulsi/Resources")
    mockFileManager.allowedDirectoryCreates.insert(resources.path)

    let tulsiBazelRoot = projectURL.appendingPathComponent(".tulsi/Bazel")
    mockFileManager.allowedDirectoryCreates.insert(tulsiBazelRoot.path)

    let tulsiBazelPackage = projectURL.appendingPathComponent(".tulsi/Bazel/tulsi")
    mockFileManager.allowedDirectoryCreates.insert(tulsiBazelPackage.path)

    let mockTemplate = ["NSExtension": ["NSExtensionPointIdentifier": "com.apple.intents-service"]]
    let templateData = try! PropertyListSerialization.data(fromPropertyList: mockTemplate, format: .xml, options: 0)
    mockFileManager.mockContent[resourceURLs.stubIOSAppExInfoPlistTemplate.path] = templateData

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
      self.writtenFiles.insert(url.path)
    }
    generator.usernameFetcher = { "USER" }
  }
}


class MockFileManager: FileManager {
  var filesThatExist = Set<String>()
  var allowedDirectoryCreates = Set<String>()
  var copyOperations = [String: String]()
  var writeOperations = [String: Data]()
  var mockContent = [String: Data]()

  override func fileExists(atPath path: String) -> Bool {
    return filesThatExist.contains(path)
  }

  override func createDirectory(at url: URL,
                                     withIntermediateDirectories createIntermediates: Bool,
                                     attributes: [String:Any]?) throws {
    if allowedDirectoryCreates.contains(url.path) { return }
    throw NSError(domain: "MockFileManager: Directory creation disallowed",
                  code: 0,
                  userInfo: nil)
  }

  override func createDirectory(atPath path: String,
                                      withIntermediateDirectories createIntermediates: Bool,
                                      attributes: [String:Any]?) throws {
    if allowedDirectoryCreates.contains(path) { return }
    throw NSError(domain: "MockFileManager: Directory creation disallowed",
                  code: 0,
                  userInfo: nil)
  }

  override func removeItem(at URL: URL) throws {
    throw NSError(domain: "MockFileManager: removeItem disallowed", code: 0, userInfo: nil)
  }

  override func removeItem(atPath path: String) throws {
    throw NSError(domain: "MockFileManager: removeItem disallowed", code: 0, userInfo: nil)
  }

  override func copyItem(at srcURL: URL, to dstURL: URL) throws {
    copyOperations[dstURL.path] = srcURL.path
  }

  override func copyItem(atPath srcPath: String, toPath dstPath: String) throws {
    copyOperations[dstPath] = srcPath
  }

  override func contents(atPath path: String) -> Data? {
    return mockContent[path]
  }

  override func createFile(atPath path: String, contents data: Data?, attributes attr: [String : Any]? = nil) -> Bool {
    if writeOperations.keys.contains(path) {
      fatalError("Attempting to overwrite an existing file at \(path)")
    }
    writeOperations[path] = data
    return true
  }
}


final class MockPBXTargetGenerator: PBXTargetGeneratorProtocol {
  var project: PBXProject

  static func getRunTestTargetBuildConfigPrefix() -> String {
    return "TestRunner__"
  }

  static func workingDirectoryForPBXGroup(_ group: PBXGroup) -> String {
    return ""
  }

  static func mainGroupForOutputFolder(_ outputFolderURL: URL, workspaceRootURL: URL) -> PBXGroup {
    return PBXGroup(name: "mainGroup",
                    path: "/A/Test/Path",
                    sourceTree: .Absolute,
                    parent: nil)
  }

  required init(bazelURL: URL,
                bazelBinPath: String,
                project: PBXProject,
                buildScriptPath: String,
                stubInfoPlistPaths: StubInfoPlistPaths,
                tulsiVersion: String,
                options: TulsiOptionSet,
                localizedMessageLogger: LocalizedMessageLogger,
                workspaceRootURL: URL,
                suppressCompilerDefines: Bool,
                redactWorkspaceSymlink: Bool) {
    self.project = project
  }

  func generateFileReferencesForFilePaths(_ paths: [String], pathFilters: Set<String>?) {
  }

  func registerRuleEntryForIndexer(_ ruleEntry: RuleEntry,
                                   ruleEntryMap: [BuildLabel:RuleEntry],
                                   pathFilters: Set<String>) {
  }

  func generateIndexerTargets() -> [String: PBXTarget] {
    return [:]
  }

  func generateBazelCleanTarget(_ scriptPath: String, workingDirectory: String) {
  }

  func generateTopLevelBuildConfigurations(_ buildSettingOverrides: [String: String]) {
  }

  func generateBuildTargetsForRuleEntries(_ ruleEntries: Set<RuleEntry>,
                                          ruleEntryMap: [BuildLabel: RuleEntry]) throws -> [String: [String]] {
    let namedRuleEntries = ruleEntries.map() { (e: RuleEntry) -> (String, RuleEntry) in
      return (e.label.asFullPBXTargetName!, e)
    }

    var testTargetLinkages = [(PBXTarget, BuildLabel)]()
    for (name, entry) in namedRuleEntries {
      let target = project.createNativeTarget(name, targetType: entry.pbxTargetType!)

      for attribute in [.xctest_app, .test_host] as [RuleEntry.Attribute] {
        if let hostLabelString = entry.attributes[attribute] as? String {
          let hostLabel = BuildLabel(hostLabelString)
          testTargetLinkages.append((target, hostLabel))
        }
      }
    }

    for (testTarget, testHostLabel) in testTargetLinkages {
      let hostTarget = project.targetByName(testHostLabel.asFullPBXTargetName!) as! PBXNativeTarget
      project.linkTestTarget(testTarget, toHostTarget: hostTarget)
    }

    return [:]
  }
}
