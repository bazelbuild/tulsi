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


// Tests for the tulsi_sources_aspect aspect.
class TulsiSourcesAspectTests: BazelIntegrationTestCase {
  var aspectInfoExtractor: BazelAspectInfoExtractor! = nil

  override func setUp() {
    super.setUp()
    aspectInfoExtractor = BazelAspectInfoExtractor(bazelURL: bazelURL,
                                                   workspaceRootURL: workspaceRootURL!,
                                                   localizedMessageLogger: localizedMessageLogger)
  }

  func testSimple() {
    installBUILDFile("Simple", intoSubdirectory: "tulsi_test")
    makeTestXCDataModel("SimpleDataModelsTestv1", inSubdirectory: "tulsi_test/SimpleTest.xcdatamodeld")
    makeTestXCDataModel("SimpleDataModelsTestv2", inSubdirectory: "tulsi_test/SimpleTest.xcdatamodeld")
    var buildOptions = bazelBuildOptions
    buildOptions.append("--copt=-DA_COMMANDLINE_DEFINE")
    buildOptions.append("--copt=-DA_COMMANDLINE_DEFINE_WITH_VALUE=1")
    buildOptions.append("--copt=-DA_COMMANDLINE_DEFINE_WITH_SPACE_VALUE='this has a space'")
    let ruleEntries = aspectInfoExtractor.extractRuleEntriesForLabels([BuildLabel("//tulsi_test:Application"),
                                                                       BuildLabel("//tulsi_test:XCTest")],
                                                                      startupOptions: bazelStartupOptions,
                                                                      buildOptions: buildOptions)
    XCTAssertEqual(ruleEntries.count, 4)

    let checker = InfoChecker(ruleEntries: ruleEntries)

    checker.assertThat("//tulsi_test:Application")
        .dependsOn("//tulsi_test:Binary")
        .hasAttribute(.defines, value: ["BINARY_ADDITIONAL_DEFINE", "BINARY_ANOTHER_DEFINE=2"] as NSArray)
        .hasListAttribute(.compiler_defines,
                          containing: ["A_COMMANDLINE_DEFINE",
                                       "A_COMMANDLINE_DEFINE_WITH_VALUE=1",
                                       "A_COMMANDLINE_DEFINE_WITH_SPACE_VALUE='this has a space'"])
        .hasAttribute(.includes, value: ["Binary/includes"] as NSArray)
        .hasAttribute(.launch_storyboard, value: ["is_dir": false,
                                                  "path": "tulsi_test/Application/Launch.storyboard",
                                                  "src": true] as NSDictionary)

    checker.assertThat("//tulsi_test:Binary")
        .dependsOn("//tulsi_test:Library")
        .hasSources(["tulsi_test/Binary/srcs/main.m"])
        .hasAttribute(.datamodels, value: [["is_dir": false,
                                            "path": "tulsi_test/SimpleTest.xcdatamodeld/SimpleDataModelsTestv1.xcdatamodel",
                                            "src": true],
                                           ["is_dir": false,
                                            "path": "tulsi_test/SimpleTest.xcdatamodeld/SimpleDataModelsTestv2.xcdatamodel",
                                            "src": true], ] as NSArray)
        .hasAttribute(.defines, value: ["BINARY_ADDITIONAL_DEFINE", "BINARY_ANOTHER_DEFINE=2"] as NSArray)
        .hasAttribute(.includes, value: ["Binary/includes"] as NSArray)
        .hasAttribute(.supporting_files,
                      value: [["is_dir": false,
                               "path": "tulsi_test/Binary/Base.lproj/One.storyboard",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Binary/Assets.xcassets",
                               "src": true],] as NSArray)

    checker.assertThat("//tulsi_test:Library")
        .hasSources(["tulsi_test/Library/srcs/src1.m",
                     "tulsi_test/Library/srcs/src2.m",
                     "tulsi_test/Library/srcs/src3.m",
                     "tulsi_test/Library/srcs/src4.m",
                     "tulsi_test/Library/srcs/SrcsHeader.h",
                     "tulsi_test/Library/hdrs/HdrsHeader.h",
                     "tulsi_test/Library/textual_hdrs/TextualHdrsHeader.h"])
        .hasAttribute(.copts, value: ["-DLIBRARY_COPT_DEFINE",
                                      "-I/Library/absolute/include/path",
                                      "-Irelative/Library/include/path"] as NSArray)
        .hasAttribute(.defines, value: ["LIBRARY_DEFINES_DEFINE=1"] as NSArray)
        .hasAttribute(.pch, value: ["is_dir": false,
                                    "path": "tulsi_test/Library/pch/PCHFile.pch",
                                    "src": true] as NSDictionary)
        .hasAttribute(.supporting_files,
                      value: [["is_dir": false,
                               "path": "tulsi_test/Library/xibs/xib.xib",
                               "src": true]] as NSArray)

    checker.assertThat("//tulsi_test:XCTest")
        .dependsOn("//tulsi_test:Library")
        .hasTestHost("//tulsi_test:Application")
        .hasAttribute(.xctest, value: true)
        .hasSources(["tulsi_test/XCTest/srcs/src1.mm"])
  }

  func testComplexSingle_DefaultConfig() {
    installBUILDFile("ComplexSingle", intoSubdirectory: "tulsi_test")
    makeTestXCDataModel("DataModelsTestv1", inSubdirectory: "tulsi_test/Test.xcdatamodeld")
    makeTestXCDataModel("DataModelsTestv2", inSubdirectory: "tulsi_test/Test.xcdatamodeld")
    let ruleEntries = aspectInfoExtractor.extractRuleEntriesForLabels([BuildLabel("//tulsi_test:Application"),
                                                                       BuildLabel("//tulsi_test:XCTest")],
                                                                      startupOptions: bazelStartupOptions,
                                                                      buildOptions: bazelBuildOptions)
    XCTAssertEqual(ruleEntries.count, 18)

    let checker = InfoChecker(ruleEntries: ruleEntries)

    checker.assertThat("//tulsi_test:Application")
        .dependsOn("//tulsi_test:Binary")
        .hasAttribute(.defines, value: ["A=BINARY_DEFINE"] as NSArray)
        .hasAttribute(.includes, value: ["Binary/includes/first/include",
                                         "Binary/includes/second/include"] as NSArray)
        .hasAttribute(.supporting_files,
                      value: [["is_dir": false,
                               "path": "tulsi_test/Application/entitlements.entitlements",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Application/structured_resources.file1",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Application/structured_resources.file2",
                               "src": true]] as NSArray)

    checker.assertThat("//tulsi_test:Binary")
        .dependsOn("//tulsi_test:Library")
        .dependsOn("//tulsi_test:NonPropagatedLibrary")
        .dependsOn("//tulsi_test:ObjCBundle")
        .hasSources(["tulsi_test/Binary/srcs/main.m",
                     "blaze-genfiles/tulsi_test/SrcGenerator/outs/output.m"
                    ])
        .hasNonARCSources(["tulsi_test/Binary/non_arc_srcs/NonARCFile.mm"])
        .hasAttribute(.defines, value: ["A=BINARY_DEFINE"] as NSArray)
        .hasAttribute(.includes, value: ["Binary/includes/first/include",
                                         "Binary/includes/second/include"] as NSArray)
        .hasAttribute(.supporting_files,
                      value: [["is_dir": false,
                               "path": "tulsi_test/Binary/Info.plist",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Binary/Base.lproj/Localizable.strings",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Binary/Base.lproj/Localized.strings",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Binary/en.lproj/Localized.strings",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Binary/en.lproj/EN.strings",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Binary/es.lproj/Localized.strings",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Binary/NonLocalized.strings",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Binary/Base.lproj/One.storyboard",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/StoryboardGenerator/outs/Two.storyboard",
                               "root": "blaze-genfiles",
                               "src": false],
                              ["is_dir": false,
                               "path": "tulsi_test/Binary/AssetsOne.xcassets",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Binary/AssetsTwo.xcassets",
                               "src": true]] as NSArray)

    checker.assertThat("//tulsi_test:ObjCBundle")
        .hasAttribute(.supporting_files,
                      value: [["is_dir": false,
                               "path": "tulsi_test/ObjCBundle.bundle",
                               "src": true]] as NSArray)

    checker.assertThat("//tulsi_test:CoreDataResources")
        .hasAttribute(.datamodels,
                      value: [["is_dir": false,
                               "path": "tulsi_test/Test.xcdatamodeld/DataModelsTestv1.xcdatamodel",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/Test.xcdatamodeld/DataModelsTestv2.xcdatamodel",
                               "src": true], ] as NSArray)

    checker.assertThat("//tulsi_test:Library")
        .hasSources(["tulsi_test/LibrarySources/srcs/src1.m",
                     "tulsi_test/LibrarySources/srcs/src2.m",
                     "tulsi_test/LibrarySources/srcs/src3.m",
                     "tulsi_test/LibrarySources/srcs/src4.m",
                     "tulsi_test/Library/srcs/src5.mm",
                     "tulsi_test/Library/srcs/SrcsHeader.h",
                     "tulsi_test/Library/hdrs/HdrsHeader.h"])
        .hasAttribute(.copts, value: ["-DLIBRARY_COPT_DEFINE"] as NSArray)
        .hasAttribute(.defines, value: ["LIBRARY_DEFINES_DEFINE=1",
                                        "'LIBRARY SECOND DEFINE'=2",
                                        "LIBRARY_VALUE_WITH_SPACES=\"Value with spaces\""] as NSArray)
        .hasAttribute(.pch, value: ["is_dir": false,
                                    "path": "tulsi_test/PCHGenerator/outs/PCHFile.pch",
                                    "root": "blaze-genfiles",
                                    "src": false] as NSDictionary)
        .hasAttribute(.supporting_files,
                      value: [["is_dir": false, "path": "tulsi_test/Library/xib.xib", "src": true]] as NSArray)

    checker.assertThat("//tulsi_test:SubLibrary")
        .hasSources(["tulsi_test/SubLibrary/srcs/src.mm"])
        .hasAttribute(.pch, value: ["is_dir": false,
                                    "path": "tulsi_test/SubLibrary/pch/AnotherPCHFile.pch",
                                    "src": true] as NSDictionary)
        .hasAttribute(.enable_modules, value: true)

    checker.assertThat("//tulsi_test:SubLibraryWithDefines")
        .hasSources(["tulsi_test/SubLibraryWithDefines/srcs/src.mm"])
        .hasAttribute(.copts, value: ["-menable-no-nans",
                                      "-menable-no-infs",
                                      "-I/SubLibraryWithDefines/local/includes",
                                      "-Irelative/SubLibraryWithDefines/local/includes"] as NSArray)
        .hasAttribute(.defines, value: ["SubLibraryWithDefines=1",
                                        "SubLibraryWithDefines_DEFINE=SubLibraryWithDefines"] as NSArray)

    checker.assertThat("//tulsi_test:SubLibraryWithDifferentDefines")
        .hasSources(["tulsi_test/SubLibraryWithDifferentDefines/srcs/src.mm"])
        .hasAttribute(.copts, value: ["-DSubLibraryWithDifferentDefines_LocalDefine",
                                      "-DSubLibraryWithDifferentDefines_INTEGER_DEFINE=1",
                                      "-DSubLibraryWithDifferentDefines_STRING_DEFINE=Test",
                                      "-DSubLibraryWithDifferentDefines_STRING_WITH_SPACES='String with spaces'",
                                      "-D'SubLibraryWithDifferentDefines Define with spaces'",
                                      "-D'SubLibraryWithDifferentDefines Define with spaces and value'=1"] as NSArray)
        .hasAttribute(.defines, value: ["SubLibraryWithDifferentDefines=1"] as NSArray)
        .hasAttribute(.includes, value: ["SubLibraryWithDifferentDefines/includes"] as NSArray)

    checker.assertThat("//tulsi_test:NonPropagatedLibrary")
        .hasSources(["tulsi_test/NonPropagatedLibrary/srcs/non_propagated.m"])

    checker.assertThat("//tulsi_test:ObjCFramework")
        .hasFrameworks(["tulsi_test/ObjCFramework/test.framework"])

    checker.assertThat("//tulsi_test:TodayExtensionBinary")
        .hasSources(["tulsi_test/TodayExtensionBinary/srcs/today_extension_binary.m"])

    checker.assertThat("//tulsi_test:TodayExtension")
        .dependsOn("//tulsi_test:TodayExtensionBinary")

    checker.assertThat("//tulsi_test:WatchExtensionBinary")
        .hasSources(["tulsi_test/WatchExtensionBinary/srcs/watch_extension_binary.m"])

    checker.assertThat("//tulsi_test:WatchExtension")
        .dependsOn("//tulsi_test:WatchExtensionBinary")
        .hasAttribute(.supporting_files,
                      value: [["is_dir": false,
                               "path": "tulsi_test/WatchExtension/app_entitlements.entitlements",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/WatchExtension/app_infoplists/Info.plist",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/WatchExtension/app_resources.file",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/WatchExtension/app_structured_resources.file",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/WatchExtension/ext_entitlements.entitlements",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/WatchExtension/ext_infoplists/Info.plist",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/WatchExtension/ext_resources.file",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/WatchExtension/ext_structured_resources.file",
                               "src": true],
                              ["is_dir": false,
                               "path": "tulsi_test/WatchExtension/app_asset_catalogs.xcassets",
                               "src": true]] as NSArray)

    checker.assertThat("//tulsi_test:XCTest")
        .dependsOn("//tulsi_test:Library")
        .hasTestHost("//tulsi_test:Application")
        .hasAttribute(.xctest, value: true)
        .hasSources(["tulsi_test/XCTest/srcs/defaultTestSource.m"])
  }

  func testComplexSingle_ConfigTestEnabled() {
    bazelBuildOptions.append("--define=TEST=1")

    installBUILDFile("ComplexSingle", intoSubdirectory: "tulsi_test")
    let ruleEntries = aspectInfoExtractor.extractRuleEntriesForLabels([BuildLabel("//tulsi_test:XCTest")],
                                                                      startupOptions: bazelStartupOptions,
                                                                      buildOptions: bazelBuildOptions)
    XCTAssertEqual(ruleEntries.count, 18)

    let checker = InfoChecker(ruleEntries: ruleEntries)

    checker.assertThat("//tulsi_test:XCTest")
        .dependsOn("//tulsi_test:Library")
        .hasTestHost("//tulsi_test:Application")
        .hasAttribute(.xctest, value: true)
        .hasSources(["tulsi_test/XCTest/srcs/configTestSource.m"])
  }

  func testPlatformDependent() {
    installBUILDFile("PlatformDependent", intoSubdirectory: "tulsi_test")
    let ruleEntries = aspectInfoExtractor.extractRuleEntriesForLabels([BuildLabel("//tulsi_test:Application")],
                                                                      startupOptions: bazelStartupOptions,
                                                                      buildOptions: bazelBuildOptions)
    XCTAssertEqual(ruleEntries.count, 6)
    let checker = InfoChecker(ruleEntries: ruleEntries)

    checker.assertThat("//tulsi_test:Application")
        .dependsOn("//tulsi_test:Binary")

    checker.assertThat("//tulsi_test:Binary")
        .dependsOn("//tulsi_test:ObjCLibrary")
        .dependsOn("//tulsi_test:J2ObjCLibrary")
        .hasSources(["tulsi_test/Binary/srcs/main.m"])

    checker.assertThat("//tulsi_test:J2ObjCLibrary")
        .exists()

    checker.assertThat("//tulsi_test:ObjCProtoLibrary")
        .containsNonARCSources(["blaze-bin/tulsi_test/_generated_protos/ObjCProtoLibrary/tulsi_test/Protolibrary.pb.m",
                                "blaze-bin/tulsi_test/_generated_protos/ObjCProtoLibrary/tulsi_test/Protolibrary.pb.h"])

    checker.assertThat("//tulsi_test:ProtoLibrary")
        .hasSources(["tulsi_test/protolibrary.proto"])

    checker.assertThat("//tulsi_test:JavaLibrary")
        .hasSources(["tulsi_test/file.java"])
  }

  func testPlatformDependentXCTestWithDefaultApp() {
    installBUILDFile("PlatformDependent", intoSubdirectory: "tulsi_test")
    let ruleEntries = aspectInfoExtractor.extractRuleEntriesForLabels([BuildLabel("//tulsi_test:XCTestWithDefaultHost")],
                                                                      startupOptions: bazelStartupOptions,
                                                                      buildOptions: bazelBuildOptions)
    let checker = InfoChecker(ruleEntries: ruleEntries)
    checker.assertThat("//tulsi_test:XCTestWithDefaultHost")
        .hasTestHost("//tools/objc:xctest_app")
        .hasAttribute(.xctest, value: true)
        .hasSources(["tulsi_test/XCTestWithDefaultHost/srcs/src1.mm"])
  }
}

// Tests for test_suite support.
class TulsiSourcesAspect_TestSuiteTests: BazelIntegrationTestCase {
  var aspectInfoExtractor: BazelAspectInfoExtractor! = nil
  let testDir = "TestSuite"

  override func setUp() {
    super.setUp()
    aspectInfoExtractor = BazelAspectInfoExtractor(bazelURL: bazelURL,
                                                   workspaceRootURL: workspaceRootURL!,
                                                   localizedMessageLogger: localizedMessageLogger)
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

  func testTestSuite_ExplicitXCTests() {
    let ruleEntries = aspectInfoExtractor.extractRuleEntriesForLabels([BuildLabel("//\(testDir):explicit_XCTests")],
                                                                      startupOptions: bazelStartupOptions,
                                                                      buildOptions: bazelBuildOptions)
    XCTAssertEqual(ruleEntries.count, 5)
    let checker = InfoChecker(ruleEntries: ruleEntries)

    checker.assertThat("//\(testDir)/One:XCTest")
        .hasTestHost("//\(testDir):TestApplication")
        .hasAttribute(.xctest, value: true)
        .hasSources(["\(testDir)/One/XCTest.m"])
    checker.assertThat("//\(testDir)/Two:XCTest")
        .hasTestHost("//\(testDir):TestApplication")
        .hasAttribute(.xctest, value: true)
        .hasSources(["\(testDir)/Two/XCTest.m"])
    checker.assertThat("//\(testDir)/Three:XCTest")
        .hasTestHost("//\(testDir):TestApplication")
        .hasAttribute(.xctest, value: true)
        .hasSources(["\(testDir)/Three/XCTest.m"])

  }

  func testTestSuite_ExplicitNonXCTests() {
    let ruleEntries = aspectInfoExtractor.extractRuleEntriesForLabels([BuildLabel("//\(testDir):explicit_NonXCTests")],
                                                                      startupOptions: bazelStartupOptions,
                                                                      buildOptions: bazelBuildOptions)
    XCTAssertEqual(ruleEntries.count, 3)
    let checker = InfoChecker(ruleEntries: ruleEntries)

    checker.assertThat("//\(testDir)/One:NonXCTest")
        .hasAttribute(.xctest, value: false)
        .hasSources(["\(testDir)/One/nonXCTest.m"])
    checker.assertThat("//\(testDir)/Two:NonXCTest")
        .hasAttribute(.xctest, value: false)
        .hasSources(["\(testDir)/Two/nonXCTest.m"])
    checker.assertThat("//\(testDir)/Three:NonXCTest")
        .hasAttribute(.xctest, value: false)
        .hasSources(["\(testDir)/Three/nonXCTest.m"])
  }

  func testTestSuite_TaggedTests() {
    let ruleEntries = aspectInfoExtractor.extractRuleEntriesForLabels([BuildLabel("//\(testDir):local_tagged_tests")],
                                                                      startupOptions: bazelStartupOptions,
                                                                      buildOptions: bazelBuildOptions)
    XCTAssertEqual(ruleEntries.count, 4)
    let checker = InfoChecker(ruleEntries: ruleEntries)

    checker.assertThat("//\(testDir):TestSuiteXCTest")
        .hasTestHost("//\(testDir):TestApplication")
        .hasAttribute(.xctest, value: true)
        .hasSources(["\(testDir)/TestSuite/TestSuiteXCTest.m"])

    checker.assertThat("//\(testDir):TestSuiteNonXCTest")
        .hasAttribute(.xctest, value: false)
        .hasSources(["\(testDir)/TestSuite/TestSuiteNonXCTest.m"])
  }
}


private class InfoChecker {
  let ruleEntries: [BuildLabel: RuleEntry]

  init(ruleEntries: [BuildLabel: RuleEntry]) {
    self.ruleEntries = ruleEntries
  }

  func assertThat(_ targetLabel: String, line: UInt = #line) -> Context {
    let ruleEntry = ruleEntries[BuildLabel(targetLabel)]
    XCTAssertNotNil(ruleEntry,
                    "No rule entry with the label \(targetLabel) was found",
                    line: line)

    return Context(ruleEntry: ruleEntry, ruleEntries: ruleEntries)
  }

  /// Context allowing checks against a single rule entry instance.
  class Context {
    let ruleEntry: RuleEntry?
    let ruleEntries: [BuildLabel: RuleEntry]
    let resolvedSourceFiles: Set<String>
    let resolvedNonARCSourceFiles: Set<String>
    let resolvedFrameworkFiles: Set<String>

    init(ruleEntry: RuleEntry?, ruleEntries: [BuildLabel: RuleEntry]) {
      self.ruleEntry = ruleEntry
      self.ruleEntries = ruleEntries

      if let ruleEntry = ruleEntry {
        resolvedSourceFiles = Set(ruleEntry.sourceFiles.map() { $0.fullPath })
        resolvedNonARCSourceFiles = Set(ruleEntry.nonARCSourceFiles.map() { $0.fullPath })
        resolvedFrameworkFiles = Set(ruleEntry.frameworkImports.map() { $0.fullPath })
      } else {
        resolvedSourceFiles = []
        resolvedNonARCSourceFiles = []
        resolvedFrameworkFiles = []
      }
    }

    // Does nothing as "assertThat" already asserted the existence of the associated ruleEntry.
    @discardableResult
    func exists() -> Context {
      return self
    }

    /// Asserts that the contextual RuleEntry is linked to a rule identified by the given
    /// targetLabel as a dependency.
    @discardableResult
    func dependsOn(_ targetLabel: String, line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      XCTAssertNotNil(ruleEntry.dependencies.contains(targetLabel),
                      "\(ruleEntry) must depend on \(targetLabel)",
                      line: line)
      return self
    }

    /// Asserts that the contextual RuleEntry contains the given list of sources (but may have
    /// others as well).
    @discardableResult
    func containsSources(_ sources: [String], line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      for s in sources {
        XCTAssert(resolvedSourceFiles.contains(s),
                  "\(ruleEntry) missing expected source file '\(s)'",
                  line: line)
      }
      return self
    }

    /// Asserts that the contextual RuleEntry has exactly the given list of sources.
    @discardableResult
    func hasSources(_ sources: [String], line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      containsSources(sources, line: line)
      XCTAssertEqual(ruleEntry.sourceFiles.count,
                     sources.count,
                     "\(ruleEntry) expected to have exactly \(sources.count) source files but has \(ruleEntry.sourceFiles.count)",
                     line: line)
      return self
    }

    /// Asserts that the contextual RuleEntry contains the given list of non-ARC sources (but may
    /// have others as well).
    @discardableResult
    func containsNonARCSources(_ sources: [String], line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      for s in sources {
        XCTAssert(resolvedNonARCSourceFiles.contains(s),
                  "\(ruleEntry) missing expected non-ARC source file '\(s)'",
                  line: line)
      }
      return self
    }

    /// Asserts that the contextual RuleEntry has exactly the given list of non-ARC sources.
    func hasNonARCSources(_ sources: [String], line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      containsNonARCSources(sources, line: line)
      XCTAssertEqual(ruleEntry.nonARCSourceFiles.count,
                     sources.count,
                     "\(ruleEntry) expected to have exactly \(sources.count) non-ARC source files but has \(ruleEntry.nonARCSourceFiles.count)",
                     line: line)
      return self
    }

    /// Asserts that the contextual RuleEntry contains the given list of framework imports (but may
    /// have others as well).
    @discardableResult
    func containsFrameworks(_ frameworks: [String], line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      for s in frameworks {
        XCTAssert(resolvedFrameworkFiles.contains(s),
                  "\(ruleEntry) missing expected framework import '\(s)'",
                  line: line)
      }
      return self
    }

    /// Asserts that the contextual RuleEntry has exactly the given list of framework imports.
    @discardableResult
    func hasFrameworks(_ frameworks: [String], line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      containsFrameworks(frameworks, line: line)
      XCTAssertEqual(ruleEntry.frameworkImports.count,
                     frameworks.count,
                     "\(ruleEntry) expected to have exactly \(frameworks.count) framework imports but has \(ruleEntry.frameworkImports.count)",
                     line: line)
      return self
    }

    /// Asserts that the contextual RuleEntry is an ios_test with an xctest_app identified by the
    /// given label.
    func hasTestHost(_ targetLabel: String, line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      let hostLabelString = ruleEntry.attributes[.xctest_app] as? String
      XCTAssertEqual(hostLabelString,
                     targetLabel,
                     "\(ruleEntry) expected to have an xctest_app of \(targetLabel)",
                     line: line)
      return self
    }

    /// Asserts that the contextual RuleEntry has an attribute with the given name and value.
    @discardableResult
    func hasAttribute<T>(_ attribute: RuleEntry.Attribute, value: T, line: UInt = #line) -> Context where T: Equatable {
      guard let ruleEntry = ruleEntry else { return self }
      if let attributeValue = ruleEntry.attributes[attribute] as? T {
        XCTAssertEqual(attributeValue, value, line: line)
      } else if let attributeValue = ruleEntry.attributes[attribute] {
        XCTFail("\(ruleEntry) expected to have an attribute named '\(attribute)' of type \(T.self) " +
                    "but it is of type \(type(of: attributeValue))",
                line: line)
      } else {
        XCTFail("\(ruleEntry) expected to have an attribute named '\(attribute)'", line: line)
      }
      return self
    }

    /// Asserts that the contextual RuleEntry has an attribute with the given name and value.
    func hasListAttribute(_ attribute: RuleEntry.Attribute,
                          containing: [String],
                          line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      if let attributeValue = ruleEntry.attributes[attribute] as? [String] {
        for item in containing {
          XCTAssert(attributeValue.contains(item), line: line)
        }
      } else if let attributeValue = ruleEntry.attributes[attribute] {
        XCTFail("\(ruleEntry) expected to have an attribute named '\(attribute)' of type " +
                    "[String] but it is of type \(type(of: attributeValue))",
                line: line)
      } else {
        XCTFail("\(ruleEntry) expected to have an attribute named '\(attribute)'", line: line)
      }
      return self
    }
  }
}
