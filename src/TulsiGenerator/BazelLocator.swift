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


/// Provides methods to locate the default Bazel instance.
public struct BazelLocator {

  /// NSUserDefaults key for the default Bazel path if one is not found in the opened project's
  /// workspace.
  public static let DefaultBazelURLKey = "defaultBazelURL"

  public static var bazelURL: URL? {
    if let bazelURL = UserDefaults.standard.url(forKey: BazelLocator.DefaultBazelURLKey),
      FileManager.default.fileExists(atPath: bazelURL.path) {
      return bazelURL
    }

    // If no default set, check for bazel on the user's PATH.

    let semaphore = DispatchSemaphore(value: 0)
    var completionInfo: ProcessRunner.CompletionInfo?
    let task = TulsiProcessRunner.createProcess("/bin/bash",
                                                arguments: ["-l", "-c", "which bazel"]) {
                                                  processCompletionInfo in
                                                  defer { semaphore.signal() }
                                                  completionInfo = processCompletionInfo
    }
    task.launch()
    _ = semaphore.wait(timeout: DispatchTime.distantFuture)

    guard let info = completionInfo else {
      return nil
    }
    guard info.terminationStatus == 0 else {
      return nil
    }

    guard let stdout = String(data: info.stdout, encoding: String.Encoding.utf8) else {
      return nil
    }
    let bazelURL = URL(fileURLWithPath: stdout.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                       isDirectory: false)
    guard FileManager.default.fileExists(atPath: bazelURL.path) else {
      return nil
    }

    UserDefaults.standard.set(bazelURL, forKey: BazelLocator.DefaultBazelURLKey)
    return bazelURL
  }

  // MARK: - Private methods

  private init() {
  }
}
