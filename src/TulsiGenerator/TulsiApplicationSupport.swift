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

class ApplicationSupport {

  private let fileManager: FileManager
  let tulsiFolder: URL

  init?(fileManager: FileManager = .default) {
    // Fail if we are running in a test so that we don't install files to ~/Library/Application Support.
    if ProcessInfo.processInfo.environment["TEST_SRCDIR"] != nil {
      return nil
    }
    /// Fetching the appName this way will result in failure for our tests, which is intentional as
    /// we don't want to install files to ~/Library/Application Support when testing.
    guard let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String else { return nil }
    guard let folder = fileManager.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first else {
      return nil
    }

    self.fileManager = fileManager
    self.tulsiFolder = folder.appendingPathComponent(appName, isDirectory: true)
  }

  /// Copies Tulsi aspect files over to ~/Library/Application\ Support/Tulsi/<version>/Bazel and
  /// returns the folder.
  func copyTulsiAspectFiles(tulsiVersion: String) throws -> String {
    let bundle = Bundle(for: type(of: self))
    let aspectWorkspaceFile = bundle.url(forResource: "WORKSPACE", withExtension: nil)!
    let aspectBuildFile = bundle.url(forResource: "BUILD", withExtension: nil)!
    let tulsiFiles = bundle.urls(forResourcesWithExtension: nil, subdirectory: "tulsi")!

    let bazelSubpath = (tulsiVersion as NSString).appendingPathComponent("Bazel")
    let bazelPath = try installFiles([aspectWorkspaceFile, aspectBuildFile], toSubpath: bazelSubpath)

    let tulsiAspectsSubpath = (bazelSubpath as NSString).appendingPathComponent("tulsi")
    try installFiles(tulsiFiles, toSubpath: tulsiAspectsSubpath)

    return bazelPath.path
  }

  @discardableResult
  private func installFiles(_ files: [URL],
                            toSubpath subpath: String) throws -> URL {
    let folder = tulsiFolder.appendingPathComponent(subpath, isDirectory: true)

    try createDirectory(atURL: folder)

    for sourceURL in files {
      let filename = sourceURL.lastPathComponent

      guard let targetURL = URL(string: filename, relativeTo: folder) else {
        throw TulsiXcodeProjectGenerator.GeneratorError.serializationFailed(
            "Unable to resolve URL for \(filename) in \(folder.path).")
      }
      do {
        try copyFileIfNeeded(fromURL: sourceURL, toURL: targetURL)
      }
    }
    return folder
  }

  private func copyFileIfNeeded(fromURL: URL, toURL: URL) throws {
    do {
      // Only over-write if needed.
      if fileManager.fileExists(atPath: toURL.path) {
        guard !fileManager.contentsEqual(atPath: fromURL.path, andPath: toURL.path) else {
          return;
        }
        print("Overwriting \(toURL.path) as its contents changed.")
        try fileManager.removeItem(at: toURL)
      }
      try fileManager.copyItem(at: fromURL, to: toURL)
    }
  }

  private func createDirectory(atURL url: URL) throws {
    var isDirectory: ObjCBool = false
    let fileExists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)

    guard !fileExists || !isDirectory.boolValue else { return }

    try fileManager.createDirectory(at: url,
                                    withIntermediateDirectories: true,
                                    attributes: nil)
  }
}
