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


/// Splits a string containing commandline arguments into an array of strings suitable for use by
/// Process.
class CommandLineSplitter {
  let scriptPath: String

  init() {
    scriptPath = Bundle(for: type(of: self)).path(forResource: "command_line_splitter",
                                                                      ofType: "sh")!
  }

  /// WARNING: This method utilizes a shell instance to evaluate the commandline and may have side
  /// effects.
  func splitCommandLine(_ commandLine: String) -> [String]? {
    if commandLine.isEmpty { return [] }

    var splitCommands: [String]? = nil
    let semaphore = DispatchSemaphore(value: 0)
    let process = ProcessRunner.createProcess(scriptPath, arguments: [commandLine]) {
      completionInfo in
        defer { semaphore.signal() }

        guard completionInfo.terminationStatus == 0,
            let stdout = NSString(data: completionInfo.stdout, encoding: String.Encoding.utf8.rawValue) else {
          return
        }
        let split = stdout.components(separatedBy: CharacterSet.newlines)
        splitCommands = [String](split.dropLast())
    }
    process.launch()
    _ = semaphore.wait(timeout: DispatchTime.distantFuture)

    return splitCommands
  }
}
