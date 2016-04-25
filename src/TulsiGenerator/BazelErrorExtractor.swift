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

  static func firstErrorLinesFromData(data: NSData, maxErrors: Int = DefaultErrors) -> String? {
    guard let stderr = NSString(data: data, encoding: NSUTF8StringEncoding) else { return nil }
    return firstErrorLinesFromString(stderr as String, maxErrors: maxErrors)
  }

  static func firstErrorLinesFromString(output: String, maxErrors: Int = DefaultErrors) -> String? {
    let errorLines = output.componentsSeparatedByString("\n").filter({ $0.hasPrefix("ERROR:") })
    if errorLines.isEmpty {
      return nil
    }

    let numErrorLinesToShow = min(errorLines.count, maxErrors)
    var errorSnippet = errorLines.prefix(numErrorLinesToShow).joinWithSeparator("\n")
    if numErrorLinesToShow < errorLines.count {
      errorSnippet += "\n..."
    }
    return errorSnippet
  }

  static func firstErrorLinesOrLastLinesFromString(output: String,
                                                   maxErrors: Int = DefaultErrors) -> String? {
    if let errorLines = firstErrorLinesFromString(output, maxErrors: maxErrors) {
      return errorLines
    }
    let errorLines = output.componentsSeparatedByString("\n").filter({ !$0.isEmpty })
    let numErrorLinesToShow = min(errorLines.count, maxErrors)
    var errorSnippet = errorLines.suffix(numErrorLinesToShow).joinWithSeparator("\n")
    if numErrorLinesToShow < errorLines.count {
      errorSnippet = "...\n" + errorSnippet
    }
    return errorSnippet
  }

  private init() {
  }
}
