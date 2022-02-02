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

import Foundation
import XCTest
@testable import TulsiGenerator

/// Base class for test cases utilizing an external Bazel instance.
class BazelIntegrationTestCase: XCTestCase {

  var bazelURL: URL! = nil
  var bazelStartupOptions = [String]()
  var bazelBuildOptions = [String]()
  var runfilesURL: URL! = nil
  var fakeBazelWorkspace: BazelFakeWorkspace! = nil
  var bazelUniversalFlags = BazelFlags()
  var workspaceRootURL: URL! = nil
  var testUndeclaredOutputsDir: URL? = nil
  var workspaceInfoFetcher: BazelWorkspacePathInfoFetcher! = nil
  var localizedMessageLogger: DirectLocalizedMessageLogger! = nil

  private var pathsToCleanOnTeardown = Set<URL>()

  override func setUp() {
    super.setUp()

    guard let test_srcdir = ProcessInfo.processInfo.environment["TEST_SRCDIR"] else {
      XCTFail("This test must be run as a bazel test and/or must define $TEST_SRCDIR.")
      return
    }
    runfilesURL = URL(fileURLWithPath: test_srcdir)

    let tempdir = ProcessInfo.processInfo.environment["TEST_TMPDIR"] ?? NSTemporaryDirectory()
    let tempdirURL = URL(fileURLWithPath: tempdir,
                         isDirectory: true)
    fakeBazelWorkspace = BazelFakeWorkspace(runfilesURL: runfilesURL,
                                            tempDirURL: tempdirURL).setup()
    pathsToCleanOnTeardown.formUnion(fakeBazelWorkspace.pathsToCleanOnTeardown)
    workspaceRootURL = fakeBazelWorkspace.workspaceRootURL
    bazelURL = fakeBazelWorkspace.bazelURL

    // Add any build options specific to the fakeBazelWorkspace.
    bazelBuildOptions.append(contentsOf: fakeBazelWorkspace.extraBuildFlags)

    if let testOutputPath = ProcessInfo.processInfo.environment["TEST_UNDECLARED_OUTPUTS_DIR"] {
      testUndeclaredOutputsDir = URL(fileURLWithPath: testOutputPath, isDirectory: true)
    }

    // Source is being copied outside of the normal workspace, so status commands won't work.
    bazelBuildOptions.append("--workspace_status_command=/usr/bin/true")

    // Prevent any custom --bazelrc startup option to be specified. It should always be /dev/null.
    for startupOption in bazelStartupOptions {
      if (startupOption.hasPrefix("--bazelrc") && startupOption != "--bazelrc=/dev/null") {
        fatalError("testBazelStartupOptions includes custom bazelrc, which is not allowed '\(startupOption)'")
      }
    }
    bazelStartupOptions.append("--bazelrc=/dev/null")

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
    bazelBuildOptions.append("--ios_minimum_os=8.0")
    bazelBuildOptions.append("--macos_minimum_os=10.10")
    bazelBuildOptions.append("--tvos_minimum_os=10.0")
    bazelBuildOptions.append("--watchos_minimum_os=3.0")

    // Explicitly set Xcode version to use. Must use the same version or the golden files
    // won't match.
    bazelBuildOptions.append("--xcode_version=13.2.1")

    // Disable the Swift worker as it adds extra dependencies.
    bazelBuildOptions.append("--define=RULES_SWIFT_BUILD_DUMMY_WORKER=1")
    bazelBuildOptions.append("--strategy=SwiftCompile=local")

    // We rely on dynamic execution in the tests, so we can't disable it for
    // the clean builds.
    // TODO(b/203094728): Remove this when it is removed from the ox bazelrc.
    bazelBuildOptions.append("--noexperimental_dynamic_skip_first_build")

    guard let workspaceRootURL = workspaceRootURL else {
      fatalError("Failed to find workspaceRootURL.")
    }

    let bundle = Bundle(for: TulsiXcodeProjectGenerator.self)
    let bazelWorkspace =
      bundle.url(forResource: "WORKSPACE", withExtension: nil)!.deletingLastPathComponent()

    bazelUniversalFlags = BazelFlags(build: [
        "--override_repository=tulsi=\(bazelWorkspace.path)"
    ])

    localizedMessageLogger = DirectLocalizedMessageLogger()
    localizedMessageLogger.startLogging()
    workspaceInfoFetcher = BazelWorkspacePathInfoFetcher(bazelURL: bazelURL,
                                                         workspaceRootURL: workspaceRootURL,
                                                         bazelUniversalFlags: bazelUniversalFlags,
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
    guard var resourceDirectoryURL = getWorkspaceDirectory(fakeBazelWorkspace.resourcesPathBase)
        else { return nil }
    if let resourceDirectory = resourceDirectory {
      resourceDirectoryURL.appendPathComponent(resourceDirectory, isDirectory: true)
    }
    let buildFileURL = resourceDirectoryURL.appendingPathComponent("\(fileResourceName).BUILD",
                                                                   isDirectory: false)

    guard let directoryURL = getWorkspaceDirectory(subdirectory) else { return nil }

    @discardableResult
    func copyFile(_ sourceFileURL: URL,
                  toFileNamed targetName: String) -> URL? {
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

    let skylarkFileURL = resourceDirectoryURL.appendingPathComponent("\(fileResourceName).bzl")
    if FileManager.default.fileExists(atPath: skylarkFileURL.path) {
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
  @discardableResult
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
                            rootDirectory: URL? = nil,
                            cleanupOnTeardown: Bool = true,
                            file: StaticString = #file,
                            line: UInt = #line) -> URL? {
    return getWorkspaceDirectory(subdirectory,
                                 rootDirectory: rootDirectory,
                                 cleanupOnTeardown: cleanupOnTeardown,
                                 file: file,
                                 line: line)
  }

  func makeXcodeProjPath(_ subdirectory: String,
                        file: StaticString = #file,
                        line: UInt = #line) -> URL? {
    return getWorkspaceDirectory(subdirectory, file: file, line: line)
  }

  // MARK: - Private methods

  fileprivate func getWorkspaceDirectory(_ subdirectory: String? = nil,
                                         rootDirectory: URL? = nil,
                                         cleanupOnTeardown: Bool = true,
                                         file: StaticString = #file,
                                         line: UInt = #line) -> URL? {
    guard let tempDirectory = rootDirectory ?? workspaceRootURL else {
      XCTFail("Cannot create test workspace directory, workspaceRootURL is nil",
              file: file,
              line: line)
      return nil
    }

    if let subdirectory = subdirectory, !subdirectory.isEmpty {
      let directoryURL = tempDirectory.appendingPathComponent(subdirectory, isDirectory: true)
      if cleanupOnTeardown {
        pathsToCleanOnTeardown.insert(directoryURL)
      }
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
      super.init(bundle: Bundle(for: TulsiXcodeProjectGenerator.self))
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
            guard !(notification.userInfo?["displayErrors"] as? Bool ?? false) else {
              return
            }

            XCTFail("Invalid message notification received (failed to convert to LogMessage)")
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

    fileprivate func handleMessage(_ item: LogMessage) {
      switch item.level {
        case .Error:
          if let details = item.details {
            print("> Critical error logged: \(item.message)\nDetails:\n\(details)")
          } else {
            print("> Critical error logged: \(item.message)")
          }
        case .Warning:
          print("> W: \(item.message)")
        case .Info:
          print("> I: \(item.message)")
        case .Syslog:
          print("> S: \(item.message)")
        case .Debug:
          print("> D: \(item.message)")
      }
    }
  }
}
