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

  var bazelURL: URL! = nil
  var bazelStartupOptions = [String]()
  var bazelBuildOptions = [String]()
  var workspaceRootURL: URL! = nil
  var workspaceInfoFetcher: BazelWorkspacePathInfoFetcher! = nil
  var localizedMessageLogger: DirectLocalizedMessageLogger! = nil

  private var pathsToCleanOnTeardown = Set<URL>()

  override func setUp() {
    super.setUp()

    let userDefaults = UserDefaults.standard
    guard let bazelPath = userDefaults.string(forKey: "test_bazel") else {
      XCTFail("This test must be launched with test_bazel set to a path to Bazel " +
                  "(e.g., via -test_bazel as a command-line argument)")
      return
    }
    bazelURL = URL(fileURLWithPath: bazelPath)

    let commandLineSplitter = CommandLineSplitter()
    if let startupOptions = userDefaults.string(forKey: "testBazelStartupOptions") {
      guard let splitOptions = commandLineSplitter.splitCommandLine(startupOptions) else {
        XCTFail("Failed to split bazelStartupOptions '\(startupOptions)'")
        return
      }
      bazelStartupOptions = splitOptions
    }
    if let buildOptions = userDefaults.string(forKey: "testBazelBuildOptions") {
      guard let splitOptions = commandLineSplitter.splitCommandLine(buildOptions) else {
        XCTFail("Failed to split bazelBuildOptions '\(buildOptions)'")
        return
      }
      bazelBuildOptions = splitOptions
    }

    if let hostedWorkspaceDirectory = userDefaults.string(forKey: "use_hosted_workspace") {
      workspaceRootURL = URL(fileURLWithPath: hostedWorkspaceDirectory,
                                         isDirectory: true)
    } else {
      let globalTempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      let dirName = "tulsi_\(UUID().uuidString)"
      workspaceRootURL = globalTempDir.appendingPathComponent(dirName, isDirectory: true)

      installWorkspaceFile()
    }

    // Prevent any custom --blazerc startup option to be specified. It should always be /dev/null.
    for startupOption in bazelStartupOptions {
      if (startupOption.hasPrefix("--blazerc") && startupOption != "--blazerc=/dev/null") {
        fatalError("testBazelStartupOptions includes custom blazerc, which is not allowed '\(startupOption)'")
      }
    }
    bazelStartupOptions.append("--blazerc=/dev/null")

    // Prevent any custom --*_minimum_os build option to be specified for tests, as this will
    // effectively remove the reproduceability of the generated projects.
    for bazelBuildOption in bazelBuildOptions {
      if (bazelBuildOption.hasPrefix("--ios_minimum_os") ||
        bazelBuildOption.hasPrefix("--macos_minimum_os") ||
        bazelBuildOption.hasPrefix("--tvos_minimum_os")  ||
        bazelBuildOption.hasPrefix("--watchos_minimum_os")) {
        fatalError("testBazelBuildOptions includes minimum deployment " +
            "version '\(bazelBuildOption)'. Setting this value is not allowed.")
      }
    }

    // Set the default deployment versions for all platforms to prevent different Xcode from
    // producing different generated projects that only differ on *_DEPLOYMENT_VERSION values.
    bazelBuildOptions.append("--ios_minimum_os=7.0")
    bazelBuildOptions.append("--macos_minimum_os=10.10")
    bazelBuildOptions.append("--tvos_minimum_os=10.0")
    bazelBuildOptions.append("--watchos_minimum_os=3.0")

    guard let workspaceRootURL = workspaceRootURL else {
      fatalError("Failed to find workspaceRootURL.")
    }

    localizedMessageLogger = DirectLocalizedMessageLogger()
    localizedMessageLogger.startLogging()
    workspaceInfoFetcher = BazelWorkspacePathInfoFetcher(bazelURL: bazelURL,
                                                         workspaceRootURL: workspaceRootURL,
                                                         localizedMessageLogger: localizedMessageLogger)
  }

  override func tearDown() {
    super.tearDown()
    cleanCreatedFiles()
    workspaceInfoFetcher = nil
    if localizedMessageLogger != nil {
      localizedMessageLogger.stopLogging()
    }
    localizedMessageLogger = nil
  }

  /// Copies the .BUILD file bundled under the given name into the test workspace, as well as any
  /// .bzl file with the same root name.
  @discardableResult
  func installBUILDFile(_ fileResourceName: String,
                        intoSubdirectory subdirectory: String? = nil,
                        fromResourceDirectory resourceDirectory: String? = nil,
                        file: StaticString = #file,
                        line: UInt = #line) -> URL? {
    let bundle = Bundle(for: type(of: self))
    guard let buildFileURL = bundle.url(forResource: fileResourceName,
                                                   withExtension: "BUILD",
                                                   subdirectory: resourceDirectory) else {
      XCTFail("Missing required test resource file \(fileResourceName).BUILD",
              file: file,
              line: line)
      return nil
    }

    guard let directoryURL = getWorkspaceDirectory(subdirectory) else { return nil }

    @discardableResult
    func copyFile(_ sourceFileURL: URL, toFileNamed targetName: String) -> URL? {
      let destinationURL = directoryURL.appendingPathComponent(targetName, isDirectory: false)
      do {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
          try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceFileURL, to: destinationURL)
        pathsToCleanOnTeardown.insert(destinationURL)
      } catch let e as NSError {
        XCTFail("Failed to install '\(sourceFileURL)' to '\(destinationURL)' for test. Error: \(e.localizedDescription)",
                file: file,
                line: line)
        return nil
      }
      return destinationURL
    }

    guard let destinationURL = copyFile(buildFileURL, toFileNamed: "BUILD") else {
      return nil
    }

    if let skylarkFileURL = bundle.url(forResource: fileResourceName,
                                                     withExtension: "bzl",
                                                     subdirectory: resourceDirectory) {
      copyFile(skylarkFileURL, toFileNamed: skylarkFileURL.lastPathComponent)
    }

    return destinationURL
  }

  /// Creates a file in the test workspace with the given contents.
  func makeFileNamed(_ name: String,
                     withData data: Data,
                     inSubdirectory subdirectory: String? = nil,
                     file: StaticString = #file,
                     line: UInt = #line) -> URL? {
    guard let directoryURL = getWorkspaceDirectory(subdirectory,
                                                   file: file,
                                                   line: line) else {
      return nil
    }

    let fileURL = directoryURL.appendingPathComponent(name, isDirectory: false)
    XCTAssertTrue((try? data.write(to: fileURL, options: [.atomic])) != nil,
                  "Failed to write to file at '\(fileURL.path)'",
                  file: file,
                  line: line)
    pathsToCleanOnTeardown.insert(fileURL)
    return fileURL
  }

  /// Creates a file in the test workspace with the given contents.
  func makeFileNamed(_ name: String,
                     withContent content: String = "",
                     inSubdirectory subdirectory: String? = nil,
                     file: StaticString = #file,
                     line: UInt = #line) -> URL? {
    guard let data = (content as NSString).data(using: String.Encoding.utf8.rawValue) else {
      XCTFail("Failed to convert file contents '\(content)' to UTF8-encoded NSData",
              file: file,
              line: line)
      return nil
    }
    return makeFileNamed(name, withData: data, inSubdirectory: subdirectory, file: file, line: line)
  }

  /// Creates a plist file in the test workspace with the given contents.
  @discardableResult
  func makePlistFileNamed(_ name: String,
                          withContent content: [String: Any],
                          inSubdirectory subdirectory: String? = nil,
                          file: StaticString = #file,
                          line: UInt = #line) -> URL? {
    do {
      let data = try PropertyListSerialization.data(fromPropertyList: content,
                                                                      format: .xml,
                                                                      options: 0)
      return makeFileNamed(name, withData: data, inSubdirectory: subdirectory, file: file, line: line)
    } catch let e {
      XCTFail("Failed to serialize content: \(e)", file: file, line: line)
      return nil
    }
  }

  /// Creates a mock xcdatamodel bundle in the given subdirectory.
  @discardableResult
  func makeTestXCDataModel(_ name: String,
                           inSubdirectory subdirectory: String,
                           file: StaticString = #file,
                           line: UInt = #line) -> URL? {
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
          let _ = makeFileNamed("layout",
                                withContent: "",
                                inSubdirectory: dataModelPath,
                                file: file,
                                line: line) else {
      return nil
    }

    return datamodelURL
  }

  /// Creates a workspace-relative directory that will be cleaned up by the test on exit.
  func makeTestSubdirectory(_ subdirectory: String,
                            file: StaticString = #file,
                            line: UInt = #line) -> URL? {
    return getWorkspaceDirectory(subdirectory, file: file, line: line)
  }

  // MARK: - Private methods

  fileprivate func installWorkspaceFile() {
    do {
      try FileManager.default.createDirectory(at: workspaceRootURL,
                                                              withIntermediateDirectories: true,
                                                              attributes: nil)
      pathsToCleanOnTeardown.insert(workspaceRootURL)

      let bundle = Bundle(for: type(of: self))
      guard let fileURL = bundle.url(forResource: "test",
                                                withExtension: "WORKSPACE") else {
        XCTFail("Missing required test.WORKSPACE file")
        return
      }


      let destinationURL = workspaceRootURL.appendingPathComponent("WORKSPACE",
                                                                        isDirectory: false)
      do {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
          try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: fileURL, to: destinationURL)
        pathsToCleanOnTeardown.insert(destinationURL)
      } catch let e as NSError {
        XCTFail("Failed to install WORKSPACE file '\(fileURL)' to '\(destinationURL)' for test. Error: \(e.localizedDescription)")
        return
      }
    } catch let e as NSError {
      XCTFail("Failed to create temp directory '\(workspaceRootURL!.path)' for test. Error: \(e.localizedDescription)")
    }
  }

  fileprivate func getWorkspaceDirectory(_ subdirectory: String? = nil,
                                     file: StaticString = #file,
                                     line: UInt = #line) -> URL? {
    guard let tempDirectory = workspaceRootURL else {
      XCTFail("Cannot create test workspace directory, workspaceRootURL is nil",
              file: file,
              line: line)
      return nil
    }

    if let subdirectory = subdirectory, !subdirectory.isEmpty {
      let directoryURL = tempDirectory.appendingPathComponent(subdirectory, isDirectory: true)
      pathsToCleanOnTeardown.insert(directoryURL)
      do {
        try FileManager.default.createDirectory(at: directoryURL,
                                                                withIntermediateDirectories: true,
                                                                attributes: nil)
        return directoryURL
      } catch let e as NSError {
        XCTFail("Failed to create directory '\(directoryURL.path)'. Error: \(e.localizedDescription)",
                file: file,
                line: line)
      }
      return nil
    }

    return tempDirectory
  }

  fileprivate func cleanCreatedFiles() {
    if UserDefaults.standard.bool(forKey: "keep_test_output") {
      print("Retaining working files for test \(String(describing: name))")
      for url in pathsToCleanOnTeardown.sorted(by: { $0.path < $1.path }) {
        print("\t\(url)")
      }
      return
    }

    let fileManager = FileManager.default
    // Sort such that deeper paths are removed before their parents.
    let sortedPaths = pathsToCleanOnTeardown.sorted(by: { $1.path < $0.path })
    for url in sortedPaths {
      do {
        try fileManager.removeItem(at: url)
      } catch let e as NSError {
        XCTFail(String(format: "Failed to remove test's temp directory at '%@'. Error: %@",
                       url.path,
                       e))
      }
    }
  }


  /// Override for LocalizedMessageLogger that prints immediately rather than bouncing to the main
  /// thread.
  final class DirectLocalizedMessageLogger: LocalizedMessageLogger {
    var observer: NSObjectProtocol? = nil

    init() {
      super.init(bundle: nil)
    }

    deinit {
      stopLogging()
    }

    func startLogging() {
      observer = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: TulsiMessageNotification),
                                                        object: nil,
                                                        queue: nil) {
        [weak self] (notification: Notification) in
          guard let item = LogMessage(notification: notification) else {
            XCTFail("Invalid message notification received (failed to conver to LogMessage)")
            return
          }
          self?.handleMessage(item)
      }
    }

    func stopLogging() {
      if let observer = self.observer {
        NotificationCenter.default.removeObserver(observer)
      }
    }

    override func warning(_ key: String,
                          comment: String,
                          details: String?,
                          context: String?,
                          values: CVarArg...) {
      LogMessage.postWarning("\(key) - \(values)")
    }

    override func error(_ key: String,
                        comment: String,
                        details: String?,
                        context: String?,
                        values: CVarArg...) {
      XCTFail("> Critical error logged: \(key) - \(values)")
    }

    fileprivate func handleMessage(_ item: LogMessage) {
      switch item.level {
        case .Error:
          XCTFail("> Critical error logged: \(item.message)\nDetails:\n\(String(describing: item.details))")
        case .Warning:
          print("> W: \(item.message)")
        case .Info:
          print("> I: \(item.message)")
        case .Syslog:
          print("> S: \(item.message)")
      }
    }
  }
}
