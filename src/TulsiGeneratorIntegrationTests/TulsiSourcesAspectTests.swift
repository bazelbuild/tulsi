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
                                                   packagePathFetcher: packagePathFetcher,
                                                   localizedMessageLogger: localizedMessageLogger)
  }

  func testSimple() {
    installBUILDFile("Simple", intoSubdirectory: "tulsi_test")
    makeTestXCDataModel("SimpleDataModelsTestv1", inSubdirectory: "tulsi_test/SimpleTest.xcdatamodeld")
    makeTestXCDataModel("SimpleDataModelsTestv2", inSubdirectory: "tulsi_test/SimpleTest.xcdatamodeld")
    let ruleEntries = aspectInfoExtractor.extractRuleEntriesForLabels([BuildLabel("//tulsi_test:Application"),
                                                                       BuildLabel("//tulsi_test:XCTest")],
                                                                      startupOptions: bazelStartupOptions,
                                                                      buildOptions: bazelBuildOptions)
    XCTAssertEqual(ruleEntries.count, 4)

    let checker = InfoChecker(ruleEntries: ruleEntries)

    checker.assertThat("//tulsi_test:Application")
        .dependsOn("//tulsi_test:Binary")
        .hasAttribute(.bridging_header,
                      value: ["path": "tulsi_test/Binary/bridging_header/bridging_header.h",
                              "src": true])
        .hasAttribute(.defines, value: ["BINARY_ADDITIONAL_DEFINE", "BINARY_ANOTHER_DEFINE=2"])
        .hasAttribute(.includes, value: ["Binary/includes"])
        .hasAttribute(.storyboards, value: [["path": "tulsi_test/Binary/Base.lproj/One.storyboard",
                                            "src": true]])

    checker.assertThat("//tulsi_test:Binary")
        .dependsOn("//tulsi_test:Library")
        .hasSources(["tulsi_test/Binary/srcs/main.m"])
        .hasAttribute(.bridging_header,
                      value: ["path": "tulsi_test/Binary/bridging_header/bridging_header.h",
                              "src": true])
        .hasAttribute(.datamodels, value: [["path": "tulsi_test/SimpleTest.xcdatamodeld/SimpleDataModelsTestv1.xcdatamodel",
                                            "src": true],
                                           ["path": "tulsi_test/SimpleTest.xcdatamodeld/SimpleDataModelsTestv2.xcdatamodel",
                                            "src": true], ])
        .hasAttribute(.defines, value: ["BINARY_ADDITIONAL_DEFINE", "BINARY_ANOTHER_DEFINE=2"])
        .hasAttribute(.includes, value: ["Binary/includes"])
        .hasAttribute(.storyboards, value: [["path": "tulsi_test/Binary/Base.lproj/One.storyboard",
                                            "src": true]])

    checker.assertThat("//tulsi_test:Library")
        .hasSources(["tulsi_test/Library/srcs/src1.m",
                     "tulsi_test/Library/srcs/src2.m",
                     "tulsi_test/Library/srcs/src3.m",
                     "tulsi_test/Library/srcs/src4.m",
                     "tulsi_test/Library/srcs/SrcsHeader.h",
                     "tulsi_test/Library/hdrs/HdrsHeader.h"])
        .hasAttribute(.copts, value: ["-DLIBRARY_COPT_DEFINE",
                                      "-I/Library/absolute/include/path",
                                      "-Irelative/Library/include/path"])
        .hasAttribute(.defines, value: ["LIBRARY_DEFINES_DEFINE=1"])
        .hasAttribute(.pch, value: ["path": "tulsi_test/Library/pch/PCHFile.pch", "src": true])

    checker.assertThat("//tulsi_test:XCTest")
        .dependsOn("//tulsi_test:Library")
        .hasTestHost("//tulsi_test:Application")
        .hasAttribute(.xctest, value: true)
        .hasSources(["tulsi_test/XCTest/srcs/src1.mm"])
  }

  func testSimpleXCTestWithDefaultApp() {
    installBUILDFile("Simple", intoSubdirectory: "tulsi_test")
    let ruleEntries = aspectInfoExtractor.extractRuleEntriesForLabels([BuildLabel("//tulsi_test:XCTestWithDefaultHost")],
                                                                      startupOptions: bazelStartupOptions,
                                                                      buildOptions: bazelBuildOptions)
    let checker = InfoChecker(ruleEntries: ruleEntries)
    checker.assertThat("//tulsi_test:XCTestWithDefaultHost")
        .hasTestHost("//tools/objc:xctest_app")
        .hasAttribute(.xctest, value: true)
        .hasSources(["tulsi_test/XCTestWithDefaultHost/srcs/src1.mm"])
  }

  func testComplexSingle_DefaultConfig() {
    installBUILDFile("ComplexSingle", intoSubdirectory: "tulsi_test")
    makeTestXCDataModel("DataModelsTestv1", inSubdirectory: "tulsi_test/Test.xcdatamodeld")
    makeTestXCDataModel("DataModelsTestv2", inSubdirectory: "tulsi_test/Test.xcdatamodeld")
    let ruleEntries = aspectInfoExtractor.extractRuleEntriesForLabels([BuildLabel("//tulsi_test:Application"),
                                                                       BuildLabel("//tulsi_test:XCTest")],
                                                                      startupOptions: bazelStartupOptions,
                                                                      buildOptions: bazelBuildOptions)
    XCTAssertEqual(ruleEntries.count, 8)

    let checker = InfoChecker(ruleEntries: ruleEntries)

    checker.assertThat("//tulsi_test:Application")
        .dependsOn("//tulsi_test:Binary")
        .hasAttribute(.bridging_header,
                      value: ["path": "tulsi_test/BridgingHeaderGenerator/outs/bridging_header.h",
                              "rootPath": "bazel-out/darwin_x86_64-fastbuild/genfiles",
                              "src": false])
        .hasAttribute(.defines, value: ["A=BINARY_DEFINE"])
        .hasAttribute(.includes, value: ["Binary/includes/first/include",
                                         "Binary/includes/second/include"])
        .hasAttribute(.storyboards,
                      value: [["path": "tulsi_test/Binary/Base.lproj/One.storyboard",
                               "src": true],
                              ["path": "tulsi_test/StoryboardGenerator/outs/Two.storyboard",
                               "rootPath": "bazel-out/darwin_x86_64-fastbuild/genfiles",
                               "src": false]])

    checker.assertThat("//tulsi_test:Binary")
        .dependsOn("//tulsi_test:Library")
        .hasSources(["tulsi_test/Binary/non_arc_srcs/NonARCFile.mm",
                     "tulsi_test/Binary/srcs/main.m",
                     "tulsi_test/SrcGenerator/outs/output.m"
                    ])
        .hasAttribute(.bridging_header,
                      value: ["path": "tulsi_test/BridgingHeaderGenerator/outs/bridging_header.h",
                              "rootPath": "bazel-out/darwin_x86_64-fastbuild/genfiles",
                              "src": false])
        .hasAttribute(.defines, value: ["A=BINARY_DEFINE"])
        .hasAttribute(.includes, value: ["Binary/includes/first/include",
                                         "Binary/includes/second/include"])
        .hasAttribute(.storyboards,
                      value: [["path": "tulsi_test/Binary/Base.lproj/One.storyboard",
                               "src": true],
                              ["path": "tulsi_test/StoryboardGenerator/outs/Two.storyboard",
                               "rootPath": "bazel-out/darwin_x86_64-fastbuild/genfiles",
                               "src": false]])

    checker.assertThat("//tulsi_test:CoreDataResources")
        .hasAttribute(.datamodels,
                      value: [["path": "tulsi_test/Test.xcdatamodeld/DataModelsTestv1.xcdatamodel",
                               "src": true],
                              ["path": "tulsi_test/Test.xcdatamodeld/DataModelsTestv2.xcdatamodel",
                               "src": true], ])

    checker.assertThat("//tulsi_test:Library")
        .hasSources(["tulsi_test/LibrarySources/srcs/src1.m",
                     "tulsi_test/LibrarySources/srcs/src2.m",
                     "tulsi_test/LibrarySources/srcs/src3.m",
                     "tulsi_test/LibrarySources/srcs/src4.m",
                     "tulsi_test/Library/srcs/src5.mm",
                     "tulsi_test/Library/srcs/SrcsHeader.h",
                     "tulsi_test/Library/hdrs/HdrsHeader.h"])
        .hasAttribute(.copts, value: ["-DLIBRARY_COPT_DEFINE"])
        .hasAttribute(.defines, value: ["LIBRARY_DEFINES_DEFINE=1",
                                        "'LIBRARY SECOND DEFINE'=2",
                                        "LIBRARY_VALUE_WITH_SPACES=\"Value with spaces\""])
        .hasAttribute(.pch, value: ["path": "tulsi_test/PCHGenerator/outs/PCHFile.pch",
                                    "rootPath": "bazel-out/darwin_x86_64-fastbuild/genfiles",
                                    "src": false])

    checker.assertThat("//tulsi_test:SubLibrary")
        .hasSources(["tulsi_test/SubLibrary/srcs/src.mm"])
        .hasAttribute(.pch, value: ["path": "tulsi_test/SubLibrary/pch/AnotherPCHFile.pch",
                                    "src": true])

    checker.assertThat("//tulsi_test:SubLibraryWithDefines")
        .hasSources(["tulsi_test/SubLibraryWithDefines/srcs/src.mm"])
        .hasAttribute(.copts, value: ["-menable-no-nans",
                                      "-menable-no-infs",
                                      "-I/SubLibraryWithDefines/local/includes",
                                      "-Irelative/SubLibraryWithDefines/local/includes"])
        .hasAttribute(.defines, value: ["SubLibraryWithDefines=1",
                                        "SubLibraryWithDefines_DEFINE=SubLibraryWithDefines"])

    checker.assertThat("//tulsi_test:SubLibraryWithDifferentDefines")
        .hasSources(["tulsi_test/SubLibraryWithDifferentDefines/srcs/src.mm"])
        .hasAttribute(.copts, value: ["-DSubLibraryWithDifferentDefines_LocalDefine",
                                      "-DSubLibraryWithDifferentDefines_INTEGER_DEFINE=1",
                                      "-DSubLibraryWithDifferentDefines_STRING_DEFINE=Test",
                                      "-DSubLibraryWithDifferentDefines_STRING_WITH_SPACES='String with spaces'",
                                      "-D'SubLibraryWithDifferentDefines Define with spaces'",
                                      "-D'SubLibraryWithDifferentDefines Define with spaces and value'=1"])
        .hasAttribute(.defines, value: ["SubLibraryWithDifferentDefines=1"])
        .hasAttribute(.includes, value: ["SubLibraryWithDifferentDefines/includes"])

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
    XCTAssertEqual(ruleEntries.count, 8)

    let checker = InfoChecker(ruleEntries: ruleEntries)

    checker.assertThat("//tulsi_test:XCTest")
        .dependsOn("//tulsi_test:Library")
        .hasTestHost("//tulsi_test:Application")
        .hasAttribute(.xctest, value: true)
        .hasSources(["tulsi_test/XCTest/srcs/configTestSource.m"])
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
                                                   packagePathFetcher: packagePathFetcher,
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

  func assertThat(targetLabel: String, line: UInt = #line) -> Context {
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

    init(ruleEntry: RuleEntry?, ruleEntries: [BuildLabel: RuleEntry]) {
      self.ruleEntry = ruleEntry
      self.ruleEntries = ruleEntries
    }

    // Does nothing as "assertThat" already asserted the existence of the associated ruleEntry.
    func exists() -> Context {
      return self
    }

    /// Asserts that the contextual RuleEntry is linked to a rule identified by the given
    /// targetLabel as a dependency.
    func dependsOn(targetLabel: String, line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      XCTAssertNotNil(ruleEntry.dependencies.contains(targetLabel),
                      "\(ruleEntry) must depend on \(targetLabel)",
                      line: line)
      return self
    }

    /// Asserts that the contextual RuleEntry contains the given list of sources (but may have
    /// others as well).
    func containsSources(sources: [String], line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      for s in sources {
        XCTAssert(ruleEntry.sourceFiles.contains(s),
                  "\(ruleEntry) missing expected source file '\(s)' from \(ruleEntry.sourceFiles)",
                  line: line)
      }
      return self
    }

    /// Asserts that the contextual RuleEntry has exactly the given list of sources.
    func hasSources(sources: [String], line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      containsSources(sources, line: line)
      XCTAssertEqual(ruleEntry.sourceFiles.count,
                     sources.count,
                     "\(ruleEntry) expected to have exactly \(sources.count) source files but has \(ruleEntry.sourceFiles.count)",
                     line: line)
      return self
    }

    /// Asserts that the contextual RuleEntry is an ios_test with an xctest_app identified by the
    /// given label.
    func hasTestHost(targetLabel: String, line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      let hostLabelString = ruleEntry.attributes[.xctest_app] as? String
      XCTAssertEqual(hostLabelString,
                     targetLabel,
                     "\(ruleEntry) expected to have an xctest_app of \(targetLabel)",
                     line: line)
      return self
    }

    /// Asserts that the contextual RuleEntry has an attribute with the given name and value.
    func hasAttribute<T where T: Equatable>(attribute: RuleEntry.Attribute, value: T, line: UInt = #line) -> Context {
      guard let ruleEntry = ruleEntry else { return self }
      if let attributeValue = ruleEntry.attributes[attribute] as? T {
        XCTAssertEqual(attributeValue, value, line: line)
      } else if let attributeValue = ruleEntry.attributes[attribute] {
        XCTFail("\(ruleEntry) expected to have an attribute named '\(attribute)' of type \(T.self) " +
                    "but it is of type \(attributeValue.dynamicType)",
                line: line)
      } else {
        XCTFail("\(ruleEntry) expected to have an attribute named '\(attribute)'", line: line)
      }
      return self
    }
  }
}
