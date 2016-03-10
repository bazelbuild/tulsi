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
  let workspaceRoot = NSURL(fileURLWithPath: "/path/to/workspace")
  let projectName = "ProjectName"

  let buildTargetLabels = ["target", "path/to/target"].map({ BuildLabel($0) })
  let pathFilters = Set<String>(["target", "path/to/target", "sourceTarget"])
  var buildTargetLabelToRuleEntries = [BuildLabel: RuleEntry]()

  let additionalFilePaths = ["additionalFile1", "path/to/additionalFile2"]

  let bazelURL = NSURL(fileURLWithPath: "/test/dir/testBazel")

  let buildScriptURL = NSURL(fileURLWithPath: "/scripts/Build")
  let cleanScriptURL = NSURL(fileURLWithPath: "/scripts/Clean")
  let envScriptURL = NSURL(fileURLWithPath: "/scripts/Env")

  let outputFolderURL = NSURL(fileURLWithPath: "/dev/null/project")

  var options: TulsiOptionSet! = nil
  var config: TulsiGeneratorConfig! = nil
  var mockFileManager: MockFileManager! = nil
  var mockExtractor: MockWorkspaceInfoExtractor! = nil
  var generator: XcodeProjectGenerator! = nil

  override func setUp() {
    super.setUp()

    buildTargetLabelToRuleEntries = XcodeProjectGeneratorTests.labelToRuleEntryMapForLabels(buildTargetLabels)

    options = TulsiOptionSet()
    config = TulsiGeneratorConfig(projectName: projectName,
                                  buildTargetLabels: buildTargetLabels,
                                  pathFilters: pathFilters,
                                  additionalFilePaths: additionalFilePaths,
                                  options: options,
                                  bazelURL: bazelURL)

    mockFileManager = MockFileManager()
    let projectURL = outputFolderURL.URLByAppendingPathComponent("\(projectName).xcodeproj")
    mockFileManager.allowedDirectoryCreates.insert(projectURL.path!)
    let xcsharedData = projectURL.URLByAppendingPathComponent("project.xcworkspace/xcshareddata")
    mockFileManager.allowedDirectoryCreates.insert(xcsharedData.path!)
    let xcschemes = projectURL.URLByAppendingPathComponent("xcshareddata/xcschemes")
    mockFileManager.allowedDirectoryCreates.insert(xcschemes.path!)
    let scripts = projectURL.URLByAppendingPathComponent(".tulsi/Scripts")
    mockFileManager.allowedDirectoryCreates.insert(scripts.path!)

    mockExtractor = MockWorkspaceInfoExtractor()
    mockExtractor.labelToRuleEntry = buildTargetLabelToRuleEntries
    generator = XcodeProjectGenerator(workspaceRootURL: workspaceRoot,
                                      config: config,
                                      localizedMessageLogger: MockLocalizedMessageLogger(),
                                      fileManager: mockFileManager,
                                      workspaceInfoExtractor: mockExtractor,
                                      buildScriptURL: buildScriptURL,
                                      envScriptURL: envScriptURL,
                                      cleanScriptURL: cleanScriptURL)
    generator.writeDataHandler = {(_, _) in }
  }

  func testUnresolvedLabelsThrows() {
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

  func testGeneration() {
    do {
      try generator.generateXcodeProjectInFolder(outputFolderURL)
    } catch let e {
      XCTFail("Unexpected exception \(e)")
    }
  }

  // MARK: - Private methods

  private static func labelToRuleEntryMapForLabels(labels: [BuildLabel]) -> [BuildLabel: RuleEntry] {
    var ret = [BuildLabel: RuleEntry]()
    for label in labels {
      ret[label] = RuleEntry(label: label,
                             type: "ios_application",
                             attributes: [:],
                             sourceFiles: [],
                             dependencies: Set<String>())
    }
    return ret
  }
}


class MockFileManager: NSFileManager {
  var filesThatExist = Set<String>()
  var allowedDirectoryCreates = Set<String>()

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
    throw NSError(domain: "MockFileManager: copyItem disallowed", code: 0, userInfo: nil)
  }

  override func copyItemAtPath(srcPath: String, toPath dstPath: String) throws {
    throw NSError(domain: "MockFileManager: copyItem disallowed", code: 0, userInfo: nil)
  }
}
