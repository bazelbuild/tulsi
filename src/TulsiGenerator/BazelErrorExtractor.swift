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


/// Provides helper methods to extract meaningful error messages from Bazel stderr output.
struct BazelErrorExtractor {
  static let DefaultErrors = 3

  static func firstErrorLinesFromData(_ data: Data, maxErrors: Int = DefaultErrors) -> String? {
    guard let stderr = NSString(data: data, encoding: String.Encoding.utf8.rawValue) else { return nil }
    return firstErrorLinesFromString(stderr as String, maxErrors: maxErrors)
  }

  static func firstErrorLinesFromString(_ output: String, maxErrors: Int = DefaultErrors) -> String? {
    func isNewLogMessage(_ line: String) -> Bool {
      for newLogMessagePrefix in ["ERROR:", "INFO:", "WARNING:"] {
        if line.hasPrefix(newLogMessagePrefix) {
          return true
        }
      }
      return false
    }

    var errorMessages = [String]()
    var tracebackErrorMessages = Set<String>()
    var activeTraceback = [String]()

    for line in output.components(separatedBy: "\n") {
      if !activeTraceback.isEmpty {
        if isNewLogMessage(line) {
          if !errorMessages.isEmpty {
            let lastMessageIndex = errorMessages.count - 1
            errorMessages[lastMessageIndex].append(activeTraceback.joined(separator: "\n"))
            tracebackErrorMessages.insert(errorMessages[lastMessageIndex])
          }
          activeTraceback = []
        } else {
          activeTraceback.append(line)
        }
      } else if (line.hasPrefix("Traceback")) {
        activeTraceback.append(line)
      }

      if (line.hasPrefix("ERROR:")) {
        errorMessages.append(line)
      }
    }

    if !activeTraceback.isEmpty && !errorMessages.isEmpty {
      let lastMessageIndex = errorMessages.count - 1
      errorMessages[lastMessageIndex].append(activeTraceback.joined(separator: "\n"))
      tracebackErrorMessages.insert(errorMessages[lastMessageIndex])
    }

    // Display only up to 'maxErrors' number of errors to the user (including any
    // associated traceback), but also check if any remaining errors include a traceback.
    // Errors with a traceback should always be displayed regardless of how many errors are
    // already being printed.
    var errorSnippet = errorMessages.prefix(maxErrors).joined(separator: "\n")
    tracebackErrorMessages.subtract(errorMessages.prefix(maxErrors))
    errorSnippet.append(tracebackErrorMessages.joined(separator: "\n"))

    if maxErrors < errorMessages.count {
      errorSnippet += "\n..."
    }
    return errorSnippet
  }

  static func firstErrorLinesOrLastLinesFromString(_ output: String,
                                                   maxErrors: Int = DefaultErrors) -> String? {
    if let errorLines = firstErrorLinesFromString(output, maxErrors: maxErrors) {
      return errorLines
    }
    let errorLines = output.components(separatedBy: "\n").filter({ !$0.isEmpty })
    let numErrorLinesToShow = min(errorLines.count, maxErrors)
    var errorSnippet = errorLines.suffix(numErrorLinesToShow).joined(separator: "\n")
    if numErrorLinesToShow < errorLines.count {
      errorSnippet = "...\n" + errorSnippet
    }
    return errorSnippet
  }

  private init() {
  }
}
