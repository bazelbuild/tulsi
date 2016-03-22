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
///   -testBazelStartupOptions <string>: Options to be passed to Bazel before the "build" command.
///   -testBazelBuildOptions <string>: Options to be passed to Bazel after the "build" command.
///   -keep_test_output (0 or 1): Retain the test's temporary workspace directory rather than
///       cleaning it up after the test completes.
///   -use_hosted_workspace <path>: Path to a Bazel workspace inside which the test files will be
///       executed. A WORKSPACE file must be present in the given directory.
class BazelIntegrationTestCase: XCTestCase {

  var bazelURL: NSURL! = nil
  var bazelStartupOptions = [String]()
  var bazelBuildOptions = [String]()
  var workspaceRootURL: NSURL! = nil
  var packagePathFetcher: BazelWorkspacePackagePathFetcher! = nil
  var localizedMessageLogger: LocalizedMessageLogger! = nil

  private var pathsToCleanOnTeardown = Set<NSURL>()

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
    if let startupOptions = userDefaults.stringForKey("testBazelStartupOptions") {
      guard let splitOptions = commandLineSplitter.splitCommandLine(startupOptions) else {
        XCTFail("Failed to split bazelStartupOptions '\(startupOptions)'")
        return
      }
      bazelStartupOptions = splitOptions
    }
    if let buildOptions = userDefaults.stringForKey("testBazelBuildOptions") {
      guard let splitOptions = commandLineSplitter.splitCommandLine(buildOptions) else {
        XCTFail("Failed to split bazelBuildOptions '\(buildOptions)'")
        return
      }
      bazelBuildOptions = splitOptions
    }

    if let hostedWorkspaceDirectory = userDefaults.stringForKey("use_hosted_workspace") {
      workspaceRootURL = NSURL(fileURLWithPath: hostedWorkspaceDirectory,
                                         isDirectory: true)
    } else {
      let globalTempDir = NSURL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      let dirName = "tulsi_\(NSUUID().UUIDString)"
      workspaceRootURL = globalTempDir.URLByAppendingPathComponent(dirName, isDirectory: true)

      do {
        try NSFileManager.defaultManager().createDirectoryAtURL(workspaceRootURL,
                                                                withIntermediateDirectories: true,
                                                                attributes: nil)
        pathsToCleanOnTeardown.insert(workspaceRootURL)
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
    cleanCreatedFiles()
  }

  /// Copies the .BUILD file bundled under the given name into the test workspace.
  func installBUILDFile(fileResourceName: String,
                        inSubdirectory subdirectory: String? = nil,
                        file: StaticString = #file,
                        line: UInt = #line) -> NSURL? {
    let bundle = NSBundle(forClass: self.dynamicType)
    guard let buildFileURL = bundle.URLForResource(fileResourceName,
                                                   withExtension: "BUILD") else {
      XCTFail("Missing required test resource file \(fileResourceName).BUILD",
              file: file,
              line: line)
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
      pathsToCleanOnTeardown.insert(destinationURL)
    } catch let e as NSError {
      XCTFail("Failed to install BUILD file '\(buildFileURL)' to '\(destinationURL)' for test. Error: \(e.localizedDescription)",
              file: file,
              line: line)
      return nil
    }

    return destinationURL
  }

  /// Creates a file in the test workspace with the given contents.
  func makeFileNamed(name: String,
                     withData data: NSData,
                     inSubdirectory subdirectory: String? = nil,
                     file: StaticString = #file,
                     line: UInt = #line) -> NSURL? {
    guard let directoryURL = getWorkspaceDirectory(subdirectory,
                                                   file: file,
                                                   line: line) else {
      return nil
    }
    let fileURL = directoryURL.URLByAppendingPathComponent(name, isDirectory: false)
    XCTAssertTrue(data.writeToURL(fileURL, atomically: true),
                  "Failed to write to file at '\(fileURL.path!)'",
                  file: file,
                  line: line)
    pathsToCleanOnTeardown.insert(fileURL)
    return fileURL
  }

  /// Creates a file in the test workspace with the given contents.
  func makeFileNamed(name: String,
                     withContent content: String = "",
                     inSubdirectory subdirectory: String? = nil,
                     file: StaticString = #file,
                     line: UInt = #line) -> NSURL? {
    guard let data = (content as NSString).dataUsingEncoding(NSUTF8StringEncoding) else {
      XCTFail("Failed to convert file contents '\(content)' to UTF8-encoded NSData",
              file: file,
              line: line)
      return nil
    }
    return makeFileNamed(name, withData: data, inSubdirectory: subdirectory, file: file, line: line)
  }

  /// Creates a plist file in the test workspace with the given contents.
  func makePlistFileNamed(name: String,
                          withContent content: [String: AnyObject],
                          inSubdirectory subdirectory: String? = nil,
                          file: StaticString = #file,
                          line: UInt = #line) -> NSURL? {
    do {
      let data = try NSPropertyListSerialization.dataWithPropertyList(content,
                                                                      format: .XMLFormat_v1_0,
                                                                      options: 0)
      return makeFileNamed(name, withData: data, inSubdirectory: subdirectory, file: file, line: line)
    } catch let e {
      XCTFail("Failed to serialize content: \(e)", file: file, line: line)
      return nil
    }
  }

  /// Creates a mock xcdatamodel bundle in the given subdirectory.
  func makeTestXCDataModel(name: String,
                           inSubdirectory subdirectory: String,
                           file: StaticString = #file,
                           line: UInt = #line) -> NSURL? {
    guard let _ = getWorkspaceDirectory(subdirectory, file: file, line: line) else {
      return nil
    }

    let dataModelPath = "\(subdirectory)/\(name).xcdatamodel"
    guard let datamodelURL = getWorkspaceDirectory(dataModelPath, file: file, line: line) else {
      return nil
    }
    guard let _ = makeFileNamed("elements",
                                withContent: "",
                                inSubdirectory: dataModelPath,
                                file: file,
                                line: line),
              _ = makeFileNamed("layout",
                                withContent: "",
                                inSubdirectory: dataModelPath,
                                file: file,
                                line: line) else {
      return nil
    }

    return datamodelURL
  }

  /// Creates a workspace-relative directory that will be cleaned up by the test on exit.
  func makeTestSubdirectory(subdirectory: String,
                            file: StaticString = #file,
                            line: UInt = #line) -> NSURL? {
    return getWorkspaceDirectory(subdirectory, file: file, line: line)
  }

  // MARK: - Private methods

  private func getWorkspaceDirectory(subdirectory: String? = nil,
                                     file: StaticString = #file,
                                     line: UInt = #line) -> NSURL? {
    guard let tempDirectory = workspaceRootURL else {
      XCTFail("Cannot create test workspace directory, workspaceRootURL is nil",
              file: file,
              line: line)
      return nil
    }

    if let subdirectory = subdirectory where !subdirectory.isEmpty {
      let directoryURL = tempDirectory.URLByAppendingPathComponent(subdirectory, isDirectory: true)
      pathsToCleanOnTeardown.insert(directoryURL)
      do {
        try NSFileManager.defaultManager().createDirectoryAtURL(directoryURL,
                                                                withIntermediateDirectories: true,
                                                                attributes: nil)
        return directoryURL
      } catch let e as NSError {
        XCTFail("Failed to create directory '\(directoryURL.path!)'. Error: \(e.localizedDescription)",
                file: file,
                line: line)
      }
      return nil
    }

    return tempDirectory
  }

  private func cleanCreatedFiles() {
    if NSUserDefaults.standardUserDefaults().boolForKey("keep_test_output") {
      print("Retaining working files for test \(name)")
      for url in pathsToCleanOnTeardown.sort({ $0.path! < $1.path! }) {
        print("\t\(url)")
      }
      return
    }

    let fileManager = NSFileManager.defaultManager()
    // Sort such that deeper paths are removed before their parents.
    let sortedPaths = pathsToCleanOnTeardown.sort({ $1.path! < $0.path! })
    for url in sortedPaths {
      do {
        try fileManager.removeItemAtURL(url)
      } catch let e as NSError {
        XCTFail(String(format: "Failed to remove test's temp directory at '%@'. Error: %@",
                       url.path!,
                       e))
      }
    }
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
