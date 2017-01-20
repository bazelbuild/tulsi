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


/// Handles fetching of interesting paths for a Bazel workspace.
class BazelWorkspacePathInfoFetcher {
  /// The Bazel package_path as defined by the target workspace.
  private var packagePath: String? = nil
  /// The Bazel execution_root as defined by the target workspace.
  private var executionRoot: String? = nil

  /// Optional path to the directory in which tulsi-* symlinks will be created.
  private var bazelSymlinkParentPathOverride: String? = nil

  /// The location of the bazel binary.
  private let bazelURL: NSURL
  /// The location of the Bazel workspace to be examined.
  private let workspaceRootURL: NSURL
  private let localizedMessageLogger: LocalizedMessageLogger
  private let semaphore: dispatch_semaphore_t
  private var fetchCompleted = false

  init(bazelURL: NSURL, workspaceRootURL: NSURL, localizedMessageLogger: LocalizedMessageLogger) {
    self.bazelURL = bazelURL
    self.workspaceRootURL = workspaceRootURL
    self.localizedMessageLogger = localizedMessageLogger

    semaphore = dispatch_semaphore_create(0)
    fetchWorkspaceInfo()
  }

  /// Returns the package_path for this fetcher's workspace, blocking until it is available.
  func getPackagePath() -> String {
    if fetchCompleted { return packagePath! }
    waitForCompletion()
    return packagePath!
  }

  /// Returns the execution_root for this fetcher's workspace, blocking until it is available.
  func getExecutionRoot() -> String {
    if fetchCompleted { return executionRoot! }
    waitForCompletion()
    return executionRoot!
  }

  /// Returns the tulsi_bazel_symlink_parent_path for this workspace (if it exists), blocking until
  /// the fetch is completed.
  func getBazelSymlinkParentPathOverride() -> String? {
    if fetchCompleted { return bazelSymlinkParentPathOverride }
    waitForCompletion()
    return bazelSymlinkParentPathOverride
  }

  /// Returns the tulsi-bin path for this workspace, blocking until the fetch is completed.
  func getBazelBinPath() -> String {
    let bazelBin = "tulsi-bin"
    if let parentPathOverride = getBazelSymlinkParentPathOverride() {
      return (parentPathOverride as NSString).stringByAppendingPathComponent(bazelBin)
    }
    return bazelBin
  }

  // MARK: - Private methods

  // Waits for the workspace fetcher to signal the
  private func waitForCompletion() {
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    dispatch_semaphore_signal(semaphore)
  }

  // Fetches Bazel package_path info from the registered workspace URL.
  private func fetchWorkspaceInfo() {
    let profilingStart = localizedMessageLogger.startProfiling("get_package_path",
                                                               message: "Fetching bazel path info")
    guard let bazelPath = bazelURL.path where NSFileManager.defaultManager().fileExistsAtPath(bazelPath) else {
      localizedMessageLogger.error("BazelBinaryNotFound",
                                   comment: "Error to show when the bazel binary cannot be found at the previously saved location %1$@.",
                                   values: bazelURL)
      return
    }

    let task = TulsiTaskRunner.createTask(bazelPath, arguments: ["info"]) {
      completionInfo in
        defer {
          self.localizedMessageLogger.logProfilingEnd(profilingStart)
          self.fetchCompleted = true
          dispatch_semaphore_signal(self.semaphore)
        }
        if completionInfo.task.terminationStatus == 0 {
          if let stdout = NSString(data: completionInfo.stdout, encoding: NSUTF8StringEncoding) {
            self.extractWorkspaceInfo(stdout)
            return
          }
        }

        self.packagePath = ""
        self.executionRoot = ""
        let stderr = NSString(data: completionInfo.stderr, encoding: NSUTF8StringEncoding)
        let debugInfoFormatString = NSLocalizedString("DebugInfoForBazelCommand",
                                                      bundle: NSBundle(forClass: self.dynamicType),
                                                      comment: "Provides general information about a Bazel failure; a more detailed error may be reported elsewhere. The Bazel command is %1$@, exit code is %2$d, stderr %3$@.")
        let debugInfo = String(format: debugInfoFormatString,
                               completionInfo.commandlineString,
                               completionInfo.terminationStatus,
                               stderr ?? "<No STDERR>")
        self.localizedMessageLogger.infoMessage(debugInfo)
        self.localizedMessageLogger.error("BazelWorkspaceInfoQueryFailed",
                                          comment: "Extracting path info from bazel failed. The exit code is %1$d.",
                                          details: stderr as String?,
                                          values: completionInfo.task.terminationStatus)
    }
    task.currentDirectoryPath = workspaceRootURL.path!
    task.launch()
  }

  private func extractWorkspaceInfo(output: NSString) {
    let lines = output.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
    for line in lines {
      let components = line.componentsSeparatedByString(": ")
      guard let key = components.first where !key.isEmpty else { continue }
      let valueComponents = components.dropFirst()
      let value = valueComponents.joinWithSeparator(": ")

      switch key {
        case "execution_root":
          executionRoot = value

        case "package_path":
          packagePath = value

        case "tulsi_bazel_symlink_parent_path":
          bazelSymlinkParentPathOverride = value

        default:
          break
      }
    }
  }
}
