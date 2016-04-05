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


/// Handles fetching of a package_path for a Bazel workspace.
class BazelWorkspacePackagePathFetcher {
  /// The Bazel package_path as defined by the target workspace.
  private var packagePath: String? = nil

  /// The location of the bazel binary.
  private let bazelURL: NSURL
  /// The location of the Bazel workspace to be examined.
  private let workspaceRootURL: NSURL
  private let localizedMessageLogger: LocalizedMessageLogger
  private let semaphore: dispatch_semaphore_t

  init(bazelURL: NSURL, workspaceRootURL: NSURL, localizedMessageLogger: LocalizedMessageLogger) {
    self.bazelURL = bazelURL
    self.workspaceRootURL = workspaceRootURL
    self.localizedMessageLogger = localizedMessageLogger

    semaphore = dispatch_semaphore_create(0)
    fetchWorkspacePackagePath()
  }

  /// Returns the package_path for this fetcher's workspace, blocking until it is available.
  func getPackagePath() -> String {
    if let packagePath = packagePath { return packagePath }
    waitForCompletion()
    return packagePath!
  }

  // MARK: - Private methods

  // Waits for the workspace fetcher to signal the
  private func waitForCompletion() {
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    dispatch_semaphore_signal(semaphore)
  }

  // Fetches Bazel package_path info from the registered workspace URL.
  private func fetchWorkspacePackagePath() {
    let profilingStart = localizedMessageLogger.startProfiling("get_package_path",
                                                               message: "Fetching bazel package_path info")
    let task = TaskRunner.standardRunner().createTask(bazelURL.path!,
                                                      arguments: ["info", "package_path"]) {
      completionInfo in
        defer {
          self.localizedMessageLogger.logProfilingEnd(profilingStart)
          dispatch_semaphore_signal(self.semaphore)
        }
        if completionInfo.task.terminationStatus == 0 {
          if let stdout = NSString(data: completionInfo.stdout, encoding: NSUTF8StringEncoding) {
            self.packagePath = stdout.stringByTrimmingCharactersInSet(NSCharacterSet.newlineCharacterSet()) as String
            return
          }
        }

        self.packagePath = ""
        self.localizedMessageLogger.error("BazelWorkspaceInfoQueryFailed",
                                          comment: "Extracting package_path info from bazel failed. The exit code is %1$d.",
                                          values: completionInfo.task.terminationStatus)

        let debugInfoFormatString = NSLocalizedString("DebugInfoForBazelCommand",
                                                      bundle: NSBundle(forClass: self.dynamicType),
                                                      comment: "Provides general information about a Bazel failure; a more detailed error may be reported elsewhere. The Bazel command is %1$@, exit code is %2$d, stderr %3$@.")
        let stderr = NSString(data: completionInfo.stderr, encoding: NSUTF8StringEncoding) ?? "<No STDERR>"
        let debugInfo = String(format: debugInfoFormatString,
                               completionInfo.commandlineString,
                               completionInfo.terminationStatus,
                               stderr)
        self.localizedMessageLogger.infoMessage(debugInfo)
    }
    task.currentDirectoryPath = workspaceRootURL.path!
    task.launch()
  }
}
