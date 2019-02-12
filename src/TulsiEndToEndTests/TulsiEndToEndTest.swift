
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


// Parent class for end to end tests that generate an xcodeproj with the Tulsi binary and verify the
// generated xcodeproj by running the projects unit tests.
class TulsiEndToEndTest: BazelIntegrationTestCase {
  fileprivate static let simulatorName = "tulsie2e-\(UUID().uuidString.prefix(8))"

  let fileManager = FileManager.default
  var runfilesWorkspaceURL: URL! = nil

  // Creates a new simulator, for use with testing generated projects, before any tests run.
  override class func setUp() {
    super.setUp()

    let targetDevice = "iPhone XS"
    let targetVersion = "12.1"
    let deviceName = targetDevice.replacingOccurrences(of: " ", with: "-")
    let deviceVersion = targetVersion.replacingOccurrences(of: ".", with: "-")
    let typeId = "com.apple.CoreSimulator.SimDeviceType.\(deviceName)"
    let runtimeId = "com.apple.CoreSimulator.SimRuntime.iOS-\(deviceVersion)"
    let completionInfo = ProcessRunner.launchProcessSync("/usr/bin/xcrun",
                                                         arguments: ["simctl",
                                                                     "create",
                                                                     TulsiEndToEndTest.simulatorName,
                                                                     typeId,
                                                                     runtimeId])

    if completionInfo.terminationStatus != 0 {
      if let stderr = String(data: completionInfo.stderr, encoding: .utf8), !stderr.isEmpty {
        XCTFail("\(completionInfo.commandlineString) failed with error: \(stderr)")
      } else {
        XCTFail("\(completionInfo.commandlineString) encountered an error. Exit code \(completionInfo.terminationStatus).")
      }
    }

    // 'simctl' should output the UUID of the new simulator if it was created succesfully.
    if let stdout = String(data: completionInfo.stdout, encoding: .utf8), stdout.isEmpty {
      XCTFail("No UUID was ouputted for newly created simulator.")
    }
  }

  // Deletes the simulator created after all tests have run.
  override class func tearDown() {
    super.tearDown()

    let completionInfo = ProcessRunner.launchProcessSync("/usr/bin/xcrun",
                                                         arguments: ["simctl",
                                                                     "delete",
                                                                     TulsiEndToEndTest.simulatorName])

    if let error = String(data: completionInfo.stderr, encoding: .utf8), !error.isEmpty {
      print("""
            \(completionInfo.commandlineString) failed with exit code: \(completionInfo.terminationStatus)
            Error: \(error)
            """)
    }
  }

  // Unzips Tulsi and boots the simulator before each test case.
  override func setUp() {
    super.setUp()
    super.continueAfterFailure = false
    runfilesWorkspaceURL = fakeBazelWorkspace.runfilesWorkspaceURL
    XCTAssertNotNil(runfilesWorkspaceURL, "runfilesWorkspaceURL must be not be nil after setup.")

    // Extracting only needs to be done once but we can't do this during the class 'setUp' function
    // because we need access to instance variables. Instead, check here if Tulsi has already been
    // extracted.
    if !fileManager.fileExists(atPath: workspaceRootURL.appendingPathComponent("Tulsi.app").path) {
      // Unzip the Tulsi.app bundle to the temp space.
      let tulsiZipPath = "tulsi.zip"
      let tulsiZipURL = runfilesWorkspaceURL.appendingPathComponent(tulsiZipPath, isDirectory: false)
      let completionInfo = ProcessRunner.launchProcessSync("/usr/bin/unzip",
                                                           arguments: [tulsiZipURL.path,
                                                                       "-d",
                                                                       workspaceRootURL.path])

      if let error = String(data: completionInfo.stderr, encoding: .utf8), !error.isEmpty {
        XCTFail(error)
      }
    }

    // Boots the simulator in the background.
    self.runSimctlCommand("boot", onSimulator: TulsiEndToEndTest.simulatorName)
  }

  // Shuts down and erases the simulator after each test case.
  override func tearDown() {
    super.tearDown()
    self.runSimctlCommand("shutdown", onSimulator: TulsiEndToEndTest.simulatorName)
    self.runSimctlCommand("erase", onSimulator: TulsiEndToEndTest.simulatorName)
  }

  // Takes a short path to data files and adds them to the fake Bazel workspace.
  func copyDataToFakeWorkspace(_ path: String) -> Bool {
    let sourceURL = runfilesWorkspaceURL.appendingPathComponent(path, isDirectory: false)
    let destURL = workspaceRootURL.appendingPathComponent(path, isDirectory: false)
    do {
      if(!fileManager.fileExists(atPath: sourceURL.path)) {
        XCTFail("Source file  \(sourceURL.path) does not exist.")
      }
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

  // Runs the Tulsi binary with the given Tulsi project and config to generate an Xcode project.
  func generateXcodeProject(tulsiProject path: String, config: String) -> URL{
    let tulsiBinURL = workspaceRootURL.appendingPathComponent("Tulsi.app/Contents/MacOS/Tulsi", isDirectory: false)
    XCTAssert(fileManager.fileExists(atPath: tulsiBinURL.path), "Tulsi binary is missing.")

    let projectURL = workspaceRootURL.appendingPathComponent(path, isDirectory: true)
    XCTAssert(fileManager.fileExists(atPath: projectURL.path), "Tulsi project is missing.")
    let configPath = projectURL.path + ":" + config

    // Generate Xcode project with Tulsi.
    let completionInfo = ProcessRunner.launchProcessSync(tulsiBinURL.path,
                                                         arguments: ["--",
                                                                     "--genconfig",
                                                                     configPath,
                                                                     "--outputfolder",
                                                                     workspaceRootURL.path,
                                                                     "--bazel",
                                                                     bazelURL.path,
                                                                     "--no-open-xcode"])

    if let stdoutput = String(data: completionInfo.stdout, encoding: .utf8) {
      print(stdoutput)
    }
    if let erroutput = String(data: completionInfo.stderr, encoding: .utf8) {
      print(erroutput)
    }

    let filename = TulsiGeneratorConfig.sanitizeFilename("\(config).xcodeproj")
    let xcodeProjectURL = workspaceRootURL.appendingPathComponent(filename, isDirectory: true)

    // Remove Xcode project after each test method.
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

  // Runs Xcode tests on the given Xcode project and scheme.
  func testXcodeProject(_ xcodeProjectURL: URL, scheme: String) {
    let destination = "platform=iOS Simulator,name=\(TulsiEndToEndTest.simulatorName)"
    let completionInfo = ProcessRunner.launchProcessSync("/usr/bin/xcodebuild",
                                                         arguments: ["test",
                                                                     "-project",
                                                                     xcodeProjectURL.path,
                                                                     "-scheme",
                                                                     scheme,
                                                                     "-destination",
                                                                     destination])

    if let stdoutput = String(data: completionInfo.stdout, encoding: .utf8),
      let result = stdoutput.split(separator: "\n").last {
      if (String(result) != "** TEST SUCCEEDED **") {
        print(stdoutput)
        XCTFail("\(completionInfo.commandlineString) did not return test sucess. Exit code: \(completionInfo.terminationStatus)")
      }
    } else if let error = String(data: completionInfo.stderr, encoding: .utf8), !error.isEmpty {
      XCTFail(error)
    } else {
      XCTFail("Xcode project tests did not return  success.")
    }
  }

  // Runs 'simctl' in a subprocess with whatever command (i.e. boot, shutdown, delete, etc) and
  // target simulator specified.
  fileprivate func runSimctlCommand(_ command: String, onSimulator target: String) {
    let completionInfo = ProcessRunner.launchProcessSync("/usr/bin/xcrun",
                                              arguments: ["simctl",
                                                          command,
                                                          target])

    if let error = String(data: completionInfo.stderr, encoding: .utf8), !error.isEmpty {
      print("""
            \(completionInfo.commandlineString) failed with exit code: \(completionInfo.terminationStatus)
            Error: \(error)
            """)
    }
  }
}

extension FileManager {
  // Performs a deep copy of the item at sourceURL, resolving any symlinks along the way.
  func deepCopyItem(at sourceURL: URL, to destURL: URL) throws {
    do {
      try self.createDirectory(atPath: destURL.deletingLastPathComponent().path, withIntermediateDirectories: true)
      let rootPath = sourceURL.path
      if let rootAttributes = try? self.attributesOfItem(atPath: rootPath) {
        if rootAttributes[FileAttributeKey.type] as? FileAttributeType == FileAttributeType.typeSymbolicLink {
          let resolvedRootPath = try self.destinationOfSymbolicLink(atPath: rootPath)
          try self.copyItem(atPath: resolvedRootPath, toPath: destURL.path)
        } else {
          try self.copyItem(at: sourceURL, to: destURL)
        }
      }

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

