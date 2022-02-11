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
  let xcodeProjectPath
    = "\(XcodeProjectGeneratorTests.outputFolderPath)/\(XcodeProjectGeneratorTests.projectName).xcodeproj"

  let workspaceRoot = URL(fileURLWithPath: "/workspace")
  let testTulsiVersion = "9.99.999.9999"

  let buildTargetLabels = ["//test:MainTarget", "//test/path/to/target:target"].map({
    BuildLabel($0)
  })
  let pathFilters = Set<String>(["test", "additional"])

  let additionalFilePaths = ["additional/File1", "additional/File2"]

  let bazelURL = TulsiParameter(
    value: URL(fileURLWithPath: "/test/dir/testBazel"),
    source: .explicitlyProvided)

  let resourceURLs = XcodeProjectGenerator.ResourceSourcePathURLs(
    buildScript: URL(fileURLWithPath: "/scripts/Build"),
    cleanScript: URL(fileURLWithPath: "/scripts/Clean"),
    extraBuildScripts: [URL(fileURLWithPath: "/scripts/Logging")],
    iOSUIRunnerEntitlements: URL(
      fileURLWithPath: "/generatedProjectResources/iOSXCTRunner.entitlements"),
    macOSUIRunnerEntitlements: URL(
      fileURLWithPath: "/generatedProjectResources/macOSXCTRunner.entitlements"),
    stubInfoPlist: URL(fileURLWithPath: "/generatedProjectResources/StubInfoPlist.plist"),
    stubIOSAppExInfoPlistTemplate: URL(
      fileURLWithPath: "/generatedProjectResources/stubIOSAppExInfoPlist.plist"),
    stubWatchOS2InfoPlist: URL(
      fileURLWithPath: "/generatedProjectResources/StubWatchOS2InfoPlist.plist"),
    stubWatchOS2AppExInfoPlist: URL(
      fileURLWithPath: "/generatedProjectResources/StubWatchOS2AppExInfoPlist.plist"),
    stubClang: URL(fileURLWithPath:  "/generatedProjectResources/stub_clang"),
    stubSwiftc: URL(fileURLWithPath:  "/generatedProjectResources/stub_swiftc"),
    stubLd: URL(fileURLWithPath:  "/generatedProjectResources/stub_ld"),
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
      XCTAssert(
        writtenFiles.contains(
          "\(xcodeProjectPath)/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings"))
      XCTAssert(
        writtenFiles.contains(
          "\(xcodeProjectPath)/project.xcworkspace/xcuserdata/USER.xcuserdatad/WorkspaceSettings.xcsettings"
        ))
      XCTAssert(
        writtenFiles.contains(
          "\(xcodeProjectPath)/xcshareddata/xcschemes/test-path-to-target-target.xcscheme"))
      XCTAssert(
        writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/test-MainTarget.xcscheme")
      )

      let supportScriptsURL = mockFileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/Tulsi/Scripts", isDirectory: true)
      XCTAssert(mockFileManager.directoryOperations.contains(supportScriptsURL.path))

      let cacheReaderURL = supportScriptsURL.appendingPathComponent(
        "bazel_cache_reader",
        isDirectory: false)
      XCTAssertFalse(mockFileManager.copyOperations.keys.contains(cacheReaderURL.path))

      let xcp = "\(xcodeProjectPath)/xcuserdata/USER.xcuserdatad/xcschemes/xcschememanagement.plist"
      XCTAssert(!mockFileManager.attributesMap.isEmpty)
      mockFileManager.attributesMap.forEach { (path, attrs) in
        XCTAssertNotNil(attrs[.modificationDate])
      }
      XCTAssert(mockFileManager.writeOperations.keys.contains(xcp))
    } catch let e {
      XCTFail("Unexpected exception \(e)")
    }
  }

  func testSuccessfulGenerationWithBazelCacheReader() {
    let ruleEntries = XcodeProjectGeneratorTests.labelToRuleEntryMapForLabels(buildTargetLabels)
    let options = TulsiOptionSet()
    options[.UseBazelCacheReader].projectValue = "YES"
    prepareGenerator(ruleEntries, options: options)
    do {
      _ = try generator.generateXcodeProjectInFolder(outputFolderURL)
      mockLocalizedMessageLogger.assertNoErrors()
      mockLocalizedMessageLogger.assertNoWarnings()

      let cacheReaderURL = mockFileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/Tulsi/Scripts/bazel_cache_reader", isDirectory: false)
      XCTAssert(mockFileManager.copyOperations.keys.contains(cacheReaderURL.path))
    } catch let e {
      XCTFail("Unexpected exception \(e)")
    }
  }

  func testExtensionPlistGeneration() {
    @discardableResult
    func addRule(
      _ labelName: String,
      type: String,
      attributes: [String: AnyObject] = [:],
      weakDependencies: Set<BuildLabel>? = nil,
      extensions: Set<BuildLabel>? = nil,
      extensionType: String? = nil,
      productType: PBXTarget.ProductType? = nil
    ) -> BuildLabel {
      let label = BuildLabel(labelName)
      mockExtractor.labelToRuleEntry[label] = Swift.type(of: self).makeRuleEntry(
        label,
        type: type,
        attributes: attributes,
        weakDependencies: weakDependencies,
        extensions: extensions,
        productType: productType,
        extensionType: extensionType)
      return label
    }

    let test1 = addRule(
      "//test:ExtFoo", type: "ios_extension", extensionType: "com.apple.extension-foo",
      productType: .AppExtension)
    let test2 = addRule(
      "//test:ExtBar", type: "ios_extension", extensionType: "com.apple.extension-bar",
      productType: .AppExtension)
    addRule(
      "//test:Application", type: "ios_application", extensions: [test1, test2],
      productType: .Application)
    prepareGenerator(mockExtractor.labelToRuleEntry)

    func assertPlist(withData data: Data, equalTo value: NSDictionary) {
      let content = try! PropertyListSerialization.propertyList(
        from: data, options: PropertyListSerialization.ReadOptions.mutableContainers, format: nil)
        as! NSDictionary
      XCTAssertEqual(content, value)
    }

    do {
      _ = try generator.generateXcodeProjectInFolder(outputFolderURL)
      mockLocalizedMessageLogger.assertNoErrors()
      mockLocalizedMessageLogger.assertNoWarnings()

      XCTAssert(
        mockFileManager.writeOperations.keys.contains(
          "\(xcodeProjectPath)/.tulsi/Resources/Stub_test-ExtFoo.plist"))
      assertPlist(
        withData: mockFileManager.writeOperations[
          "\(xcodeProjectPath)/.tulsi/Resources/Stub_test-ExtFoo.plist"]!,
        equalTo: ["NSExtension": ["NSExtensionPointIdentifier": "com.apple.extension-foo"]])

      XCTAssert(
        mockFileManager.writeOperations.keys.contains(
          "\(xcodeProjectPath)/.tulsi/Resources/Stub_test-ExtBar.plist"))
      assertPlist(
        withData: mockFileManager.writeOperations[
          "\(xcodeProjectPath)/.tulsi/Resources/Stub_test-ExtBar.plist"]!,
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

  func testInvalidPathThrows() {
    let ruleEntries = XcodeProjectGeneratorTests.labelToRuleEntryMapForLabels(buildTargetLabels)
    prepareGenerator(ruleEntries)
    let invalidOutputFolderString = "/dev/null/bazel-build"
    let invalidOutputFolderURL = URL(fileURLWithPath: invalidOutputFolderString)

    do {
      _ = try generator.generateXcodeProjectInFolder(invalidOutputFolderURL)
      XCTFail("Generation succeeded unexpectedly")
    } catch XcodeProjectGenerator.ProjectGeneratorError.invalidXcodeProjectPath(
      let pathFound,
      let reason)
    {
      // Expected failure on path with a /bazel-* directory.
      XCTAssertEqual(pathFound, invalidOutputFolderString)
      XCTAssertEqual(reason, "a Bazel generated temp directory (\"/bazel-\")")
    } catch let e {
      XCTFail("Unexpected exception \(e)")
    }
  }

  func testTestSuiteSchemeGenerationWithSkylarkUnitTest() {
    checkTestSuiteSchemeGeneration(
      "ios_unit_test",
      testProductType: .UnitTest,
      testHostAttributeName: "test_host")
  }

  func testTestSuiteSchemeGenerationWithSkylarkUITest() {
    checkTestSuiteSchemeGeneration(
      "ios_ui_test",
      testProductType: .UIUnitTest,
      testHostAttributeName: "test_host")
  }

  func checkTestSuiteSchemeGeneration(
    _ testRuleType: String,
    testProductType: PBXTarget.ProductType,
    testHostAttributeName: String
  ) {
    @discardableResult
    func addRule(
      _ labelName: String,
      type: String,
      attributes: [String: AnyObject] = [:],
      weakDependencies: Set<BuildLabel>? = nil,
      productType: PBXTarget.ProductType? = nil
    ) -> BuildLabel {
      let label = BuildLabel(labelName)
      mockExtractor.labelToRuleEntry[label] = Swift.type(of: self).makeRuleEntry(
        label,
        type: type,
        attributes: attributes,
        weakDependencies: weakDependencies,
        productType: productType)
      return label
    }

    let app = addRule("//test:Application", type: "ios_application", productType: .Application)
    let test1 = addRule(
      "//test:TestOne",
      type: testRuleType,
      attributes: [testHostAttributeName: app.value as AnyObject],
      productType: testProductType)
    let test2 = addRule(
      "//test:TestTwo",
      type: testRuleType,
      attributes: [testHostAttributeName: app.value as AnyObject],
      productType: testProductType)
    addRule("//test:UnusedTest", type: testRuleType, productType: testProductType)
    addRule("//test:TestSuite", type: "test_suite", weakDependencies: Set([test1, test2]))
    prepareGenerator(mockExtractor.labelToRuleEntry)

    do {
      _ = try generator.generateXcodeProjectInFolder(outputFolderURL)
      mockLocalizedMessageLogger.assertNoErrors()
      mockLocalizedMessageLogger.assertNoWarnings()

      XCTAssert(writtenFiles.contains("\(xcodeProjectPath)/project.pbxproj"))
      XCTAssert(
        writtenFiles.contains(
          "\(xcodeProjectPath)/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings"))
      XCTAssert(
        writtenFiles.contains(
          "\(xcodeProjectPath)/project.xcworkspace/xcuserdata/USER.xcuserdatad/WorkspaceSettings.xcsettings"
        ))
      XCTAssert(
        writtenFiles.contains(
          "\(xcodeProjectPath)/xcshareddata/xcschemes/test-Application.xcscheme"))
      XCTAssert(
        writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/test-TestOne.xcscheme"))
      XCTAssert(
        writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/test-TestTwo.xcscheme"))
      XCTAssert(
        writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/test-UnusedTest.xcscheme")
      )
      XCTAssert(
        writtenFiles.contains("\(xcodeProjectPath)/xcshareddata/xcschemes/TestSuite_Suite.xcscheme")
      )
    } catch let e {
      XCTFail("Unexpected exception \(e)")
    }
  }

  func testProjectSDKROOT() {
    func validate(_ types: [(String, String)], _ expectedSDKROOT: String?, line: UInt = #line) {
      let rules = types.map { tuple in
        // Both the platform and osDeploymentTarget must be set in order to create a valid
        // deploymentTarget for the RuleEntry.
        XcodeProjectGeneratorTests.makeRuleEntry(
          BuildLabel(tuple.0), type: tuple.0, platformType: tuple.1,
          osDeploymentTarget: "this_must_not_be_nil")
      }
      let sdkroot = XcodeProjectGenerator.projectSDKROOT(rules)
      XCTAssertEqual(sdkroot, expectedSDKROOT, line: line)
    }

    let iosAppTuple = ("ios_application", "ios")
    let tvExtensionTuple = ("tvos_extension", "tvos")
    validate([iosAppTuple], "iphoneos")
    validate([iosAppTuple, iosAppTuple], "iphoneos")
    validate([iosAppTuple, tvExtensionTuple], nil)
    validate([tvExtensionTuple], "appletvos")
  }

  // MARK: - Private methods

  private static func labelToRuleEntryMapForLabels(_ labels: [BuildLabel]) -> [BuildLabel:
    RuleEntry]
  {
    var ret = [BuildLabel: RuleEntry]()
    for label in labels {
      ret[label] = makeRuleEntry(label, type: "ios_application", productType: .Application)
    }
    return ret
  }

  private static func makeRuleEntry(
    _ label: BuildLabel,
    type: String,
    attributes: [String: AnyObject] = [:],
    artifacts: [BazelFileInfo] = [],
    sourceFiles: [BazelFileInfo] = [],
    nonARCSourceFiles: [BazelFileInfo] = [],
    dependencies: Set<BuildLabel> = Set(),
    secondaryArtifacts: [BazelFileInfo] = [],
    weakDependencies: Set<BuildLabel>? = nil,
    buildFilePath: String? = nil,
    objcDefines: [String]? = nil,
    swiftDefines: [String]? = nil,
    includePaths: [RuleEntry.IncludePath]? = nil,
    extensions: Set<BuildLabel>? = nil,
    productType: PBXTarget.ProductType? = nil,
    extensionType: String? = nil,
    platformType: String? = nil,
    osDeploymentTarget: String? = nil
  ) -> RuleEntry {
    return RuleEntry(
      label: label,
      type: type,
      attributes: attributes,
      artifacts: artifacts,
      sourceFiles: sourceFiles,
      nonARCSourceFiles: nonARCSourceFiles,
      dependencies: dependencies,
      secondaryArtifacts: secondaryArtifacts,
      weakDependencies: weakDependencies,
      extensions: extensions,
      productType: productType,
      platformType: platformType,
      osDeploymentTarget: osDeploymentTarget,
      buildFilePath: buildFilePath,
      objcDefines: objcDefines,
      swiftDefines: swiftDefines,
      includePaths: includePaths,
      extensionType: extensionType)
  }

  private func prepareGenerator(_ ruleEntries: [BuildLabel: RuleEntry], options: TulsiOptionSet = TulsiOptionSet()) {
    // To avoid creating ~/Library folders and changing UserDefaults during CI testing.
    config = TulsiGeneratorConfig(
      projectName: XcodeProjectGeneratorTests.projectName,
      buildTargetLabels: Array(ruleEntries.keys),
      pathFilters: pathFilters,
      additionalFilePaths: additionalFilePaths,
      options: options,
      bazelURL: bazelURL)
    let projectURL = URL(fileURLWithPath: xcodeProjectPath, isDirectory: true)
    mockFileManager.allowedDirectoryCreates.insert(projectURL.path)

    let tulsiExecRoot = projectURL.appendingPathComponent(PBXTargetGenerator.TulsiExecutionRootSymlinkPath)
    mockFileManager.allowedDirectoryCreates.insert(tulsiExecRoot.path)

    let tulsiLegacyExecRoot = projectURL.appendingPathComponent(PBXTargetGenerator.TulsiExecutionRootSymlinkLegacyPath)
    mockFileManager.allowedDirectoryCreates.insert(tulsiLegacyExecRoot.path)

    let tulsiOutputBase = projectURL.appendingPathComponent(PBXTargetGenerator.TulsiOutputBaseSymlinkPath)
    mockFileManager.allowedDirectoryCreates.insert(tulsiOutputBase.path)

    let bazelCacheReaderURL = mockFileManager.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/Tulsi/Scripts", isDirectory: true)
    mockFileManager.allowedDirectoryCreates.insert(bazelCacheReaderURL.path)

    let xcshareddata = projectURL.appendingPathComponent("project.xcworkspace/xcshareddata")
    mockFileManager.allowedDirectoryCreates.insert(xcshareddata.path)

    let xcuserdata = projectURL.appendingPathComponent(
      "project.xcworkspace/xcuserdata/USER.xcuserdatad")
    mockFileManager.allowedDirectoryCreates.insert(xcuserdata.path)

    let xcschemes = projectURL.appendingPathComponent("xcshareddata/xcschemes")
    mockFileManager.allowedDirectoryCreates.insert(xcschemes.path)

    let userXcschemes = projectURL.appendingPathComponent("xcuserdata/USER.xcuserdatad/xcschemes")
    mockFileManager.allowedDirectoryCreates.insert(userXcschemes.path)

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
    let templateData = try! PropertyListSerialization.data(
      fromPropertyList: mockTemplate, format: .xml, options: 0)
    mockFileManager.mockContent[resourceURLs.stubIOSAppExInfoPlistTemplate.path] = templateData

    mockExtractor.labelToRuleEntry = ruleEntries

    generator = XcodeProjectGenerator(
      workspaceRootURL: workspaceRoot,
      config: config,
      localizedMessageLogger: mockLocalizedMessageLogger,
      workspaceInfoExtractor: mockExtractor,
      resourceURLs: resourceURLs,
      tulsiVersion: testTulsiVersion,
      fileManager: mockFileManager,
      pbxTargetGeneratorType: MockPBXTargetGenerator.self)
    generator.redactSymlinksToBazelOutput = true
    generator.suppressModifyingUserDefaults = true
    generator.suppressGeneratingBuildSettings = true
    generator.writeDataHandler = { (url, _) in
      self.writtenFiles.insert(url.path)
    }
    generator.usernameFetcher = { "USER" }
  }
}

class MockFileManager: FileManager {
  var filesThatExist = Set<String>()
  var allowedDirectoryCreates = Set<String>()
  var directoryOperations = [String]()
  var copyOperations = [String: String]()
  var writeOperations = [String: Data]()
  var removeOperations = [String]()
  var mockContent = [String: Data]()
  var attributesMap = [String: [FileAttributeKey: Any]]()

  override open var homeDirectoryForCurrentUser: URL {
    return URL(fileURLWithPath: "/Users/__MOCK_USER__", isDirectory: true)
  }

  override func fileExists(atPath path: String) -> Bool {
    return filesThatExist.contains(path)
  }

  override func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool,
    attributes: [FileAttributeKey: Any]?
  ) throws {
    guard !allowedDirectoryCreates.contains(url.path) else {
      directoryOperations.append(url.path)
      if let attributes = attributes {
        self.setAttributes(attributes, path: url.path)
      }
      return
    }
    throw NSError(
      domain: "MockFileManager: Directory creation disallowed",
      code: 0,
      userInfo: nil)
  }

  override func createDirectory(
    atPath path: String,
    withIntermediateDirectories createIntermediates: Bool,
    attributes: [FileAttributeKey: Any]?
  ) throws {
    guard !allowedDirectoryCreates.contains(path) else {
      directoryOperations.append(path)
      if let attributes = attributes {
        self.setAttributes(attributes, path: path)
      }
      return
    }
    throw NSError(
      domain: "MockFileManager: Directory creation disallowed",
      code: 0,
      userInfo: nil)
  }

  override func removeItem(at URL: URL) throws {
    removeOperations.append(URL.path)
  }

  override func removeItem(atPath path: String) throws {
    removeOperations.append(path)
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

  override func createFile(
    atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey: Any]? = nil
  ) -> Bool {
    if writeOperations.keys.contains(path) {
      fatalError("Attempting to overwrite an existing file at \(path)")
    }
    writeOperations[path] = data
    if let attr = attr {
      self.setAttributes(attr, path: path)
    }
    return true
  }

  fileprivate func setAttributes(_ attributes: [FileAttributeKey: Any], path: String) {
    var currentAttributes = attributesMap[path] ?? [FileAttributeKey: Any]()
    attributes.forEach { (k, v) in
      currentAttributes[k] = v
    }
    attributesMap[path] = currentAttributes
  }

  override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String)
    throws
  {
    self.setAttributes(attributes, path: path)
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
    return PBXGroup(
      name: "mainGroup",
      path: "/A/Test/Path",
      sourceTree: .Absolute,
      parent: nil)
  }

  required init(
    bazelPath: String,
    bazelBinPath: String,
    project: PBXProject,
    buildScriptPath: String,
    stubInfoPlistPaths: StubInfoPlistPaths,
    stubBinaryPaths: StubBinaryPaths,
    tulsiVersion: String,
    options: TulsiOptionSet,
    localizedMessageLogger: LocalizedMessageLogger,
    workspaceRootURL: URL,
    suppressCompilerDefines: Bool
  ) {
    self.project = project
  }

  func generateFileReferencesForFilePaths(_ paths: [String], pathFilters: Set<String>?) {
  }

  func registerRuleEntryForIndexer(
    _ ruleEntry: RuleEntry,
    ruleEntryMap: RuleEntryMap,
    pathFilters: Set<String>,
    processedEntries: inout [RuleEntry: (NSOrderedSet)]
  ) {
  }

  func generateIndexerTargets() -> [String: PBXTarget] {
    return [:]
  }

  func generateBazelCleanTarget(
    _ scriptPath: String, workingDirectory: String,
    startupOptions: [String]
  ) {
  }

  func generateTopLevelBuildConfigurations(_ buildSettingOverrides: [String: String]) {
  }

  func generateBuildTargetsForRuleEntries(
    _ ruleEntries: Set<RuleEntry>,
    ruleEntryMap: RuleEntryMap,
    pathFilters: Set<String>?
  ) throws -> [BuildLabel: PBXNativeTarget] {
    // This works as this file only tests native targets that don't have multiple configurations.
    let namedRuleEntries = ruleEntries.map { (e: RuleEntry) -> (String, RuleEntry) in
      return (e.label.asFullPBXTargetName!, e)
    }

    var targetsByLabel = [BuildLabel: PBXNativeTarget]()
    var testTargetLinkages = [(PBXTarget, BuildLabel)]()
    for (name, entry) in namedRuleEntries {
      let target = project.createNativeTarget(
        name,
        deploymentTarget: entry.deploymentTarget,
        targetType: entry.pbxTargetType!)
      targetsByLabel[entry.label] = target


      if let hostLabelString = entry.attributes[.test_host] as? String {
        let hostLabel = BuildLabel(hostLabelString)
        testTargetLinkages.append((target, hostLabel))
      }
    }

    for (testTarget, testHostLabel) in testTargetLinkages {
      let hostTarget = project.targetByName(testHostLabel.asFullPBXTargetName!) as! PBXNativeTarget
      project.linkTestTarget(testTarget, toHostTarget: hostTarget)
    }
    return targetsByLabel
  }
}
