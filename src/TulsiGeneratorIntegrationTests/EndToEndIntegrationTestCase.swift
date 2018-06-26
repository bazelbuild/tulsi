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
@testable import BazelIntegrationTestCase
@testable import TulsiGenerator


// Base class for end-to-end tests that generate xcodeproj bundles and validate them against golden
// versions.
class EndToEndIntegrationTestCase : BazelIntegrationTestCase {
  enum Error: Swift.Error {
    /// A subdirectory for the Xcode project could not be created.
    case testSubdirectoryNotCreated
    /// The Xcode project could not be generated.
    case projectGenerationFailure(String)
  }

  let fakeBazelURL = URL(fileURLWithPath: "/fake/tulsi_test_bazel", isDirectory: false)
  let testTulsiVersion = "9.99.999.9999"

  final func validateDiff(_ diffLines: [String], file: StaticString = #file, line: UInt = #line) {
    for diff in diffLines {
      XCTFail(diff, file: file, line: line)
    }
  }

  final func diffProjectAt(_ projectURL: URL,
                           againstGoldenProject resourceName: String,
                           file: StaticString = #file,
                           line: UInt = #line) -> [String] {
    let bundle = Bundle(for: type(of: self))
    let goldenProjectURL = workspaceRootURL.appendingPathComponent(fakeBazelWorkspace
                                                                       .resourcesPathBase,
                                                                   isDirectory: true)
        .appendingPathComponent("GoldenProjects/\(resourceName).xcodeproj", isDirectory: true)
    guard FileManager.default.fileExists(atPath: goldenProjectURL.path) else {
      assertionFailure("Missing required test resource file \(resourceName).xcodeproj")
      XCTFail("Missing required test resource file \(resourceName).xcodeproj",
              file: file,
              line: line)
      return []
    }

    var diffOutput = [String]()
    let semaphore = DispatchSemaphore(value: 0)
    let process = ProcessRunner.createProcess("/usr/bin/diff",
                                              arguments: ["-r",
                                                          // For the sake of simplicity in
                                                          // maintaining the golden data, copied
                                                          // Tulsi artifacts are assumed to have
                                                          // been installed correctly.
                                                          "--exclude=.tulsi",
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
    process.currentDirectoryPath = workspaceRootURL.path
    process.launch()

    _ = semaphore.wait(timeout: DispatchTime.distantFuture)
    return diffOutput
  }

  final func copyOutput(source: URL, outputDir: String) throws {
    if testUndeclaredOutputsDir != nil {
      guard let testOutputURL = makeTestSubdirectory(outputDir,
                                                     rootDirectory: testUndeclaredOutputsDir,
                                                     cleanupOnTeardown: false) else {
        throw Error.testSubdirectoryNotCreated
      }
      let testOutputProjURL = testOutputURL.appendingPathComponent(source.lastPathComponent)
      if FileManager.default.fileExists(atPath: testOutputProjURL.path) {
        try FileManager.default.removeItem(at: testOutputProjURL)
      }
      try FileManager.default.copyItem(at: source, to: testOutputProjURL)
    }
  }

  final func generateProjectNamed(_ projectName: String,
                                  buildTargets: [RuleInfo],
                                  pathFilters: [String],
                                  additionalFilePaths: [String] = [],
                                  outputDir: String,
                                  options: TulsiOptionSet = TulsiOptionSet()) throws -> URL {
    if !bazelStartupOptions.isEmpty {
      options[.BazelBuildStartupOptionsDebug].projectValue =
          bazelStartupOptions.joined(separator: " ")
    }

    let debugBuildOptions = ["--define=TULSI_TEST=dbg"] + bazelBuildOptions
    let releaseBuildOptions = ["--define=TULSI_TEST=rel"] + bazelBuildOptions

    options[.BazelBuildOptionsDebug].projectValue = debugBuildOptions.joined(separator: " ")
    options[.BazelBuildOptionsRelease].projectValue = releaseBuildOptions.joined(separator: " ")

    let bazelURLParam = TulsiParameter(value: fakeBazelURL, source: .explicitlyProvided)
    let config = TulsiGeneratorConfig(projectName: projectName,
                                      buildTargets: buildTargets,
                                      pathFilters: Set<String>(pathFilters),
                                      additionalFilePaths: additionalFilePaths,
                                      options: options,
                                      bazelURL: bazelURLParam)

    guard let outputFolderURL = makeXcodeProjPath(outputDir) else {
      throw Error.testSubdirectoryNotCreated
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
    // Don't modify any user defaults.
    projectGenerator.xcodeProjectGenerator.suppressModifyingUserDefaults = true
    // The username is forced to a known value.
    projectGenerator.xcodeProjectGenerator.usernameFetcher = { "_TEST_USER_" }
    // The workspace symlink is forced to a known value.
    projectGenerator.xcodeProjectGenerator.redactWorkspaceSymlink = true
    let errorInfo: String
    do {
      let generatedProjURL = try projectGenerator.generateXcodeProjectInFolder(outputFolderURL)
      try copyOutput(source: generatedProjURL, outputDir: outputDir)
      return generatedProjURL
    } catch TulsiXcodeProjectGenerator.GeneratorError.unsupportedTargetType(let targetType) {
      errorInfo = "Unsupported target type: \(targetType)"
    } catch TulsiXcodeProjectGenerator.GeneratorError.serializationFailed(let details) {
      errorInfo = "General failure: \(details)"
    } catch let error {
      errorInfo = "Unexpected failure: \(error)"
    }
    throw Error.projectGenerationFailure(errorInfo)
  }
}
