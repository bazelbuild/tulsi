
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


// End to end tests that generate an xcodeproj with the Tulsi binary and runs tests on the xcodeproj
// to verify it was generated correctly.
class TulsiEndToEndTest: BazelIntegrationTestCase {
  let fileManager = FileManager.default

  override func setUp() {
    super.setUp()

    let runfilesWorkspaceURL = fakeBazelWorkspace.runfilesWorkspaceURL

    // Takes a short path to data files and adds them to the correct location in the workspace.
    func copyDataToFakeWorkspace(_ path: String) -> Bool {
      let sourceURL = runfilesWorkspaceURL.appendingPathComponent(path, isDirectory: true)
      let destURL = workspaceRootURL.appendingPathComponent(path, isDirectory: true)
      do {
        if fileManager.fileExists(atPath: destURL.path) {
          try fileManager.removeItem(at: destURL)
        }
        // Symlinks cause issues with Tulsi and Storyboards so must deep copy any data files.
        try fileManager.deepCopyItem(at: sourceURL, to: destURL)
        return true
      } catch let e as NSError {
        print(e.localizedDescription)
        return false
      }
    }

    if (!copyDataToFakeWorkspace("build_bazel_rules_apple/examples/multi_platform/Buttons")) {
      XCTFail("Failed to copy Buttons files to fake execroot.")
    }

    if (!copyDataToFakeWorkspace("src/TulsiEndToEndTests/Resources")) {
      XCTFail("Failed to copy Buttons tulsiproj to fake execroot.")
    }

    // Unzip the Tulsi.app bundle to the temp space.
    let semaphore = DispatchSemaphore(value: 0)
    let tulsiZipPath = "tulsi.zip"
    let tulsiZipURL = runfilesWorkspaceURL.appendingPathComponent(tulsiZipPath, isDirectory: false)
    let process = TulsiProcessRunner.createProcess("/usr/bin/unzip",
                                                   arguments: [tulsiZipURL.path,
                                                               "-d",
                                                               workspaceRootURL.path]) {
      completionInfo in
        if let error = String(data: completionInfo.stderr, encoding: .utf8), !error.isEmpty {
          XCTFail(error)
        }
        semaphore.signal()
    }
    process.launch()
    _ = semaphore.wait(timeout: DispatchTime.distantFuture)
  }

  func generateXcodeProject(tulsiProject path: String, config: String) -> URL{
    let tulsiBinURL = workspaceRootURL.appendingPathComponent("Tulsi.app/Contents/MacOS/Tulsi", isDirectory: false)
    XCTAssert(fileManager.fileExists(atPath: tulsiBinURL.path), "Tulsi binary is missing.")

    let projectURL = workspaceRootURL.appendingPathComponent(path, isDirectory: true)
    XCTAssert(fileManager.fileExists(atPath: projectURL.path), "Tulsi project is missing.")
    let configPath = projectURL.path + ":" + config

    // Generate Xcode project with Tulsi.
    let semaphore = DispatchSemaphore(value: 0)
    let process = TulsiProcessRunner.createProcess(tulsiBinURL.path,
                                                   arguments: ["--",
                                                               "--genconfig",
                                                               configPath,
                                                               "--outputfolder",
                                                               workspaceRootURL.path,
                                                               "--bazel",
                                                               bazelURL.path,
                                                               "--no-open-xcode"]) {
      completionInfo in
        if let stdoutput = String(data: completionInfo.stdout, encoding: .utf8) {
          print(stdoutput)
        }
        if let erroutput = String(data: completionInfo.stderr, encoding: .utf8) {
          print(erroutput)
        }
        semaphore.signal()
    }
    process.launch()
    _ = semaphore.wait(timeout: DispatchTime.distantFuture)

    let filename = TulsiGeneratorConfig.sanitizeFilename("\(config).xcodeproj")
    let xcodeProjectURL = workspaceRootURL.appendingPathComponent(filename, isDirectory: true)

    addTeardownBlock {
      do {
        if self.fileManager.fileExists(atPath: xcodeProjectURL.path) {
          try self.fileManager.removeItem(at: xcodeProjectURL)
          XCTAssertFalse(self.fileManager.fileExists(atPath: xcodeProjectURL.path))
        }
      } catch {
          XCTFail("Error while deleting generated Xcode project: \(error)")
      }
    }

    return xcodeProjectURL
  }

  func testXcodeProject(_ xcodeProjectURL: URL, scheme: String) {
    // Run Xcode tests.
    let semaphore = DispatchSemaphore(value: 0)
    let xcodeTest = TulsiProcessRunner.createProcess("/usr/bin/xcodebuild",
                                                       arguments: ["test",
                                                                   "-project",
                                                                   xcodeProjectURL.path,
                                                                   "-scheme",
                                                                   scheme,
                                                                   "-destination",
                                                                   "platform=iOS Simulator,name=iPhone 8,OS=11.2"]) {
      completionInfo in
        if let stdoutput = String(data: completionInfo.stdout, encoding: .utf8),
          let result = stdoutput.split(separator: "\n").last {
          XCTAssertEqual(String(result), "** TEST SUCCEEDED **", "xcodebuild did not return test success.")
        } else if let error = String(data: completionInfo.stderr, encoding: .utf8), !error.isEmpty {
          XCTFail(error)
        } else {
          XCTFail("Xcode project tests did not return  success.")
        }
        semaphore.signal()
    }
    xcodeTest.launch()
    _ = semaphore.wait(timeout: DispatchTime.distantFuture)
  }

  func testButtons() throws {
    let buttonsProjectPath = "src/TulsiEndToEndTests/Resources/Buttons.tulsiproj"
    let xcodeProjectURL = generateXcodeProject(tulsiProject: buttonsProjectPath,
                                               config: "Buttons")
    XCTAssert(fileManager.fileExists(atPath: xcodeProjectURL.path), "Xcode project was not generated.")
    testXcodeProject(xcodeProjectURL, scheme: "ButtonsTests")
  }

  func testButtonsWithCanaryBazel() throws {
    if let canaryBazelURL = fakeBazelWorkspace.canaryBazelURL {
      XCTAssert(fileManager.fileExists(atPath: canaryBazelURL.path), "Bazel canary is missing.")
      bazelURL = canaryBazelURL
      let buttonsProjectPath = "src/TulsiEndToEndTests/Resources/Buttons.tulsiproj"
      let xcodeProjectURL = generateXcodeProject(tulsiProject: buttonsProjectPath,
                                                 config: "Buttons")
      testXcodeProject(xcodeProjectURL, scheme: "ButtonsTests")
    }
  }

  func testInvalidConfig() throws {
    let buttonsProjectPath = "src/TulsiEndToEndTests/Resources/Buttons.tulsiproj"
    let xcodeProjectURL = generateXcodeProject(tulsiProject: buttonsProjectPath,
                                               config: "InvalidConfig")
    XCTAssertFalse(fileManager.fileExists(atPath: xcodeProjectURL.path), "Xcode project was generated despite invalid config.")
  }
}

extension FileManager {
  // Performs a deep copy of the item at sourceURL, resolving any symlinks along the way.
  func deepCopyItem(at sourceURL: URL, to destURL: URL) throws {
    do {
      try self.createDirectory(atPath: destURL.deletingLastPathComponent().path, withIntermediateDirectories: true)
      try self.copyItem(at: sourceURL, to: destURL)

      let path = destURL.path
      if let paths = self.subpaths(atPath: path) {
        for subpath in paths {
          let fullSubpath = path + "/" + subpath
          if let attributes = try? self.attributesOfItem(atPath: fullSubpath) {
            // If a file is a symbolic link, find the original file, remove the symlink, and copy
            // over the original file.
            if attributes[FileAttributeKey.type] as? FileAttributeType == FileAttributeType.typeSymbolicLink {
              let resolvedPath = try self.destinationOfSymbolicLink(atPath: fullSubpath)
              try self.removeItem(atPath: fullSubpath)
              try self.copyItem(atPath: resolvedPath, toPath: fullSubpath)
            }
          }
        }
      }
    }
  }
}

