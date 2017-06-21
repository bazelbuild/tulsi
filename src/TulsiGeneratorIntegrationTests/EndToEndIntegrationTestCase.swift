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


// Base class for end-to-end tests that generate xcodeproj bundles and validate them against golden
// versions.
class EndToEndIntegrationTestCase : BazelIntegrationTestCase {
  let fakeBazelURL = URL(fileURLWithPath: "/fake/tulsi_test_bazel", isDirectory: false)
  let testTulsiVersion = "9.99.999.9999"

  // For the sake of simplicity in maintaining the golden data, copied Tulsi artifacts are
  // assumed to have been installed correctly.
  private let copiedTulsiArtifactRegex = try! NSRegularExpression(pattern: "^Only in .*?\\.xcodeproj/\\.tulsi.+$",
                                                                  options: [])

  final func validateDiff(_ diffLines: [String], file: StaticString = #file, line: UInt = #line) {
    for diff in diffLines {
      let range = NSMakeRange(0, (diff as NSString).length)
      if copiedTulsiArtifactRegex.firstMatch(in: diff,
                                             options: NSRegularExpression.MatchingOptions.anchored,
                                             range: range) != nil {
        continue
      }
      XCTFail(diff, file: file, line: line)
    }
  }

  final func diffProjectAt(_ projectURL: URL,
                           againstGoldenProject resourceName: String,
                           file: StaticString = #file,
                           line: UInt = #line) -> [String] {
    let bundle = Bundle(for: type(of: self))
    guard let goldenProjectURL = bundle.url(forResource: resourceName,
                                                       withExtension: "xcodeproj",
                                                       subdirectory: "GoldenProjects") else {
      assertionFailure("Missing required test resource file \(resourceName).xcodeproj")
      XCTFail("Missing required test resource file \(resourceName).xcodeproj",
              file: file,
              line: line)
      return []
    }

    var diffOutput = [String]()
    let semaphore = DispatchSemaphore(value: 0)
    let task = TaskRunner.createTask("/usr/bin/diff",
                                     arguments: ["-rq",
                                                 projectURL.path,
                                                 goldenProjectURL.path]) {
      completionInfo in
        defer {
          semaphore.signal()
        }
        if let stdout = NSString(data: completionInfo.stdout, encoding: String.Encoding.utf8.rawValue) {
          diffOutput = stdout.components(separatedBy: "\n").filter({ !$0.isEmpty })
        } else {
          XCTFail("No output received for diff command", file: file, line: line)
        }
    }
    task.currentDirectoryPath = workspaceRootURL.path
    task.launch()

    _ = semaphore.wait(timeout: DispatchTime.distantFuture)
    return diffOutput
  }

  final func generateProjectNamed(_ projectName: String,
                                  buildTargets: [RuleInfo],
                                  pathFilters: [String],
                                  additionalFilePaths: [String] = [],
                                  outputDir: String,
                                  options: TulsiOptionSet = TulsiOptionSet()) -> URL? {
    if !bazelStartupOptions.isEmpty {
      options[.BazelBuildStartupOptionsDebug].projectValue =
          bazelStartupOptions.joined(separator: " ")
    }

    let debugBuildOptions = ["--define=TULSI_TEST=dbg"] + bazelBuildOptions
    let releaseBuildOptions = ["--define=TULSI_TEST=rel"] + bazelBuildOptions

    options[.BazelBuildOptionsDebug].projectValue = debugBuildOptions.joined(separator: " ")
    options[.BazelBuildOptionsRelease].projectValue = releaseBuildOptions.joined(separator: " ")

    let config = TulsiGeneratorConfig(projectName: projectName,
                                      buildTargets: buildTargets,
                                      pathFilters: Set<String>(pathFilters),
                                      additionalFilePaths: additionalFilePaths,
                                      options: options,
                                      bazelURL: fakeBazelURL)

    guard let outputFolderURL = makeTestSubdirectory(outputDir) else {
      XCTFail("Failed to create output folder, aborting test.")
      return nil
    }

    let projectGenerator = TulsiXcodeProjectGenerator(workspaceRootURL: workspaceRootURL,
                                                      config: config,
                                                      extractorBazelURL: bazelURL,
                                                      tulsiVersion: testTulsiVersion)
    // Bazel built-in preprocessor defines are suppressed in order to prevent any
    // environment-dependent variables from mismatching the golden data.
    projectGenerator.xcodeProjectGenerator.suppressCompilerDefines = true
    // Output directory generation is suppressed in order to prevent having to whitelist diffs of
    // empty directories.
    projectGenerator.xcodeProjectGenerator.suppressGeneratedArtifactFolderCreation = true
    // The username is forced to a known value.
    projectGenerator.xcodeProjectGenerator.usernameFetcher = { "_TEST_USER_" }
    // The workspace symlink is forced to a known value.
    projectGenerator.xcodeProjectGenerator.redactWorkspaceSymlink = true
    let errorInfo: String
    do {
      return try projectGenerator.generateXcodeProjectInFolder(outputFolderURL)
    } catch TulsiXcodeProjectGenerator.GeneratorError.unsupportedTargetType(let targetType) {
      errorInfo = "Unsupported target type: \(targetType)"
    } catch TulsiXcodeProjectGenerator.GeneratorError.serializationFailed(let details) {
      errorInfo = "General failure: \(details)"
    } catch _ {
      errorInfo = "Unexpected failure"
    }
    XCTFail(errorInfo)
    return nil
  }
}
