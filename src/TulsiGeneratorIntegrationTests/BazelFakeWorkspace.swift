// Copyright 2018 The Tulsi Authors. All rights reserved.
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
import TulsiGenerator

class BazelFakeWorkspace {
  let resourcesPathBase = "src/TulsiGeneratorIntegrationTests/Resources"
  let extraBuildFlags: [String]
  var runfilesURL: URL
  var runfilesWorkspaceURL: URL
  var fakeExecroot: URL
  var workspaceRootURL: URL
  var bazelURL: URL
  var canaryBazelURL: URL?
  var pathsToCleanOnTeardown = Set<URL>()

  init(runfilesURL: URL, tempDirURL: URL) {
    self.runfilesURL = runfilesURL
    self.runfilesWorkspaceURL = runfilesURL.appendingPathComponent("__main__", isDirectory: true)
    self.fakeExecroot = tempDirURL.appendingPathComponent("fake_execroot", isDirectory: true)
    self.workspaceRootURL = fakeExecroot.appendingPathComponent("__main__", isDirectory: true)
    self.bazelURL = BazelLocator.bazelURL!
    self.extraBuildFlags = []
  }

  private func addExportsFiles(buildFilePath: String,
                               exportedFile: String) throws {
    try createDummyFile(path: "\(buildFilePath)/BUILD",
                        content: "exports_files([\"\(exportedFile)\"])\n")
  }

  private func addFilegroup(buildFilePath: String,
                            filegroup: String) throws {
    try createDummyFile(path: "\(buildFilePath)/BUILD",
                        content: """
filegroup(
    name = "\(filegroup)",
    visibility = ["//visibility:public"],
)
"""
    )
  }

  private func createDummyFile(path: String,
                               content: String) throws {
    let fileURL = workspaceRootURL.appendingPathComponent(path)
    let fileManager = FileManager.default
    let containingDirectory = fileURL.deletingLastPathComponent()
    if !fileManager.fileExists(atPath: containingDirectory.path) {
      try fileManager.createDirectory(at: containingDirectory,
                                      withIntermediateDirectories: true,
                                      attributes: nil)
    }
    if fileManager.fileExists(atPath: fileURL.path) {
      try fileManager.removeItem(at: fileURL)
    }
    try content.write(to: fileURL,
                      atomically: false,
                      encoding: String.Encoding.utf8)
  }

  private func installWorkspaceFile() {
    do {
      try FileManager.default.createDirectory(at: workspaceRootURL,
                                              withIntermediateDirectories: true,
                                              attributes: nil)

      do {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fakeExecroot.path) {
          try fileManager.removeItem(at: fakeExecroot)
        }
        try fileManager.copyItem(at: runfilesURL, to: fakeExecroot)
        pathsToCleanOnTeardown.insert(workspaceRootURL)
      } catch let e as NSError {
        XCTFail("Failed to copy workspace '\(runfilesURL)' to '\(workspaceRootURL)' for test. Error: \(e.localizedDescription)")
        return
      }
    } catch let e as NSError {
      XCTFail("Failed to create temp directory '\(workspaceRootURL.path)' for test. Error: \(e.localizedDescription)")
    }
  }

  func setup() -> BazelFakeWorkspace? {
    installWorkspaceFile()
    do {
      try createDummyFile(path: "tools/objc/objc_dummy.mm", content: "")
      try addExportsFiles(buildFilePath: "tools/objc", exportedFile: "objc_dummy.mm")
    } catch let e as NSError {
      XCTFail("Failed to set up fake workspace. Error: \(e.localizedDescription)")
    }
    return self
  }
}
