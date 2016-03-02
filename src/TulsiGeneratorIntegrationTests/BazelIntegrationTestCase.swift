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


/// Base class for test cases utilizing an external Bazel instance.
/// Command line options:
///   -test_bazel: (Required) Path to the Bazel binary to use for testing.
///   -bazelStartupOptions <string>: Options to be passed to Bazel before the "build" command.
///   -bazelBuildOptions <string>: Options to be passed to Bazel after the "build" command.
///   -keep_test_output (0 or 1): Retain the test's temporary workspace directory rather than
///       cleaning it up after the test completes.
///   -use_hosted_workspace_subdir <path>: Path to a subdirectory within a Bazel workspace inside
///       which the test files will be executed. The WORKSPACE file must be present in the parent
///       of the given directory.
class BazelIntegrationTestCase: XCTestCase {

  var bazelURL: NSURL! = nil
  var bazelStartupOptions = [String]()
  var bazelBuildOptions = [String]()
  var workspaceRootURL: NSURL! = nil
  var packagePathFetcher: BazelWorkspacePackagePathFetcher! = nil
  var localizedMessageLogger: LocalizedMessageLogger! = nil

  var directoryToCleanOnTeardown: NSURL? = nil

  override func setUp() {
    super.setUp()

    let userDefaults = NSUserDefaults.standardUserDefaults()
    guard let bazelPath = userDefaults.stringForKey("test_bazel") else {
      XCTFail("This test must be launched with test_bazel set to a path to Bazel " +
                  "(e.g., via -test_bazel as a command-line argument)")
      return
    }
    bazelURL = NSURL(fileURLWithPath: bazelPath)

    let commandLineSplitter = CommandLineSplitter()
    if let startupOptions = userDefaults.stringForKey("bazelStartupOptions") {
      guard let splitOptions = commandLineSplitter.splitCommandLine(startupOptions) else {
        XCTFail("Failed to split bazelStartupOptions '\(startupOptions)'")
        return
      }
      bazelStartupOptions = splitOptions
    }
    if let buildOptions = userDefaults.stringForKey("bazelBuildOptions") {
      guard let splitOptions = commandLineSplitter.splitCommandLine(buildOptions) else {
        XCTFail("Failed to split bazelBuildOptions '\(buildOptions)'")
        return
      }
      bazelBuildOptions = splitOptions
    }

    if let hostedWorkspaceSubdirectory = userDefaults.stringForKey("use_hosted_workspace_subdir") {
      directoryToCleanOnTeardown = NSURL(fileURLWithPath: hostedWorkspaceSubdirectory,
                                         isDirectory: true)
      workspaceRootURL = directoryToCleanOnTeardown!.URLByDeletingLastPathComponent!
    } else {
      let globalTempDir = NSURL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      let dirName = "tulsi_\(NSUUID().UUIDString)"
      workspaceRootURL = globalTempDir.URLByAppendingPathComponent(dirName, isDirectory: true)
      directoryToCleanOnTeardown = workspaceRootURL

      do {
        try NSFileManager.defaultManager().createDirectoryAtURL(workspaceRootURL,
                                                                withIntermediateDirectories: true,
                                                                attributes: nil)

        // Create an empty WORKSPACE file in the temp directory.
        let workspaceURL = workspaceRootURL!.URLByAppendingPathComponent("WORKSPACE", isDirectory: false)
        XCTAssertTrue(NSData().writeToURL(workspaceURL, atomically: true),
                      "Failed to create WORKSPACE file at \(workspaceURL.path!)")
      } catch let e as NSError {
        XCTFail("Failed to create temp directory '\(workspaceRootURL!.path!)' for test. Error: \(e.localizedDescription)")
      }
    }

    localizedMessageLogger = DirectLocalizedMessageLogger()
    packagePathFetcher = MockBazelWorkspacePackagePathFetcher(bazelURL: bazelURL,
                                                              workspaceRootURL: workspaceRootURL ?? NSURL(),
                                                              localizedMessageLogger: localizedMessageLogger)
  }

  override func tearDown() {
    super.tearDown()

    if let tempDirectory = directoryToCleanOnTeardown {
      let userDefaults = NSUserDefaults.standardUserDefaults()
      if userDefaults.boolForKey("keep_test_output") {
        print("Retaining working directory at '\(tempDirectory.path)' for test \(name)")
      } else {
        do {
          try NSFileManager.defaultManager().removeItemAtURL(tempDirectory)
        } catch let e as NSError {
          XCTFail(String(format: "Failed to remove test's temp directory at '%@'. Error: %@",
                         tempDirectory.path!,
                         e.localizedDescription))
        }
      }
    }
  }

  /// Writes a BUILD file into the temporary test workspace with the given contents.
  func makeBUILDFileWithContentLines(contentLines: [String],
                                     inSubdirectory subdirectory: String? = nil) -> NSURL? {
    return makeBUILDFileWithContent(contentLines.joinWithSeparator("\n"),
                                    inSubdirectory: subdirectory)
  }

  /// Writes a BUILD file into the temporary test workspace with the given contents.
  func makeBUILDFileWithContent(content: String,
                                inSubdirectory subdirectory: String? = nil) -> NSURL? {
    guard let directoryURL = getWorkspaceDirectory(subdirectory) else { return nil }
    let fileURL = directoryURL.URLByAppendingPathComponent("BUILD", isDirectory: false)
    guard let data = (content as NSString).dataUsingEncoding(NSUTF8StringEncoding) else {
      XCTFail("Failed to convert BUILD contents '\(content)' to UTF8-encoded NSData")
      return nil
    }

    XCTAssertTrue(data.writeToURL(fileURL, atomically: true),
                  "Failed to write to BUILD file at '\(fileURL.path!)'")
    return fileURL
  }

  /// Copies the .BUILD file bundled under the given name into the test workspace.
  func installBUILDFile(buildFileResourceName: String,
                        inSubdirectory subdirectory: String? = nil) -> NSURL? {
    let bundle = NSBundle(forClass: self.dynamicType)
    guard let buildFileURL = bundle.URLForResource(buildFileResourceName,
                                                   withExtension: "BUILD") else {
      assertionFailure("Missing required test resource file \(buildFileResourceName).BUILD")
      XCTFail("Missing required test resource file \(buildFileResourceName).BUILD")
      return nil
    }

    guard let directoryURL = getWorkspaceDirectory(subdirectory) else { return nil }
    let destinationURL = directoryURL.URLByAppendingPathComponent("BUILD", isDirectory: false)
    do {
      let fileManager = NSFileManager.defaultManager()
      if fileManager.fileExistsAtPath(destinationURL.path!) {
        try fileManager.removeItemAtURL(destinationURL)
      }
      try fileManager.copyItemAtURL(buildFileURL, toURL: destinationURL)
    } catch let e as NSError {
      XCTFail("Failed to install BUILD file '\(buildFileURL)' to '\(destinationURL)' for test. Error: \(e.localizedDescription)")
      return nil
    }

    return destinationURL
  }

  // MARK: - Private methods

  private func getWorkspaceDirectory(subdirectory: String? = nil) -> NSURL? {
    guard let tempDirectory = workspaceRootURL else {
      XCTFail("Cannot create test workspace directory, workspaceRootURL is nil")
      return nil
    }

    if let subdirectory = subdirectory where !subdirectory.isEmpty {
      let directoryURL = tempDirectory.URLByAppendingPathComponent(subdirectory)
      do {
        try NSFileManager.defaultManager().createDirectoryAtURL(directoryURL,
                                                                withIntermediateDirectories: true,
                                                                attributes: nil)
        return directoryURL
      } catch let e as NSError {
        XCTFail("Failed to create BUILD subdirectory '\(directoryURL.path!)'. Error: \(e.localizedDescription)")
      }
      return nil
    }

    return tempDirectory
  }


  /// Override for LocalizedMessageLogger that prints directly.
  private class DirectLocalizedMessageLogger: LocalizedMessageLogger {

    init() {
      super.init(messageLogger: nil, bundle: nil)
    }

    override func infoMessage(message: String) {
      print("I: \(message)")
    }

    override func warning(key: String, comment: String, values: CVarArgType...) {
      print("W: \(key) - \(values)")
    }

    override func error(key: String, comment: String, values: CVarArgType...) {
      XCTFail("Critical error logged: \(key) - \(values)")
    }
  }


  /// Hardcodes the package path to the default for an empty WORKSPACE file.
  private class MockBazelWorkspacePackagePathFetcher: BazelWorkspacePackagePathFetcher {
    override func getPackagePath() -> String {
      return "%workspace%"
    }
  }
}
