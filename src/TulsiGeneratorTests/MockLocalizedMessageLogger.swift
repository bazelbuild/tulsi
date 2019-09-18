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

@testable import TulsiGenerator

// Stub LocalizedMessageLogger that does nothing.
class MockLocalizedMessageLogger: LocalizedMessageLogger {
  var syslogMessages = [String]()
  var infoMessages = [String]()
  var warningMessageKeys = [String]()

  let nonFatalWarningKeys = Set([
    "BootstrapLLDBInitFailed",
    "CleanCachedDsymsFailed",
  ])

  var errorMessageKeys = [String]()

  init() {
    super.init(bundle: nil)
  }

  override func error(
    _ key: String, comment: String, details: String?, context: String?, values: CVarArg...
  ) {
    errorMessageKeys.append(key)
  }

  override func warning(
    _ key: String, comment: String, details: String?, context: String?, values: CVarArg...
  ) {
    warningMessageKeys.append(key)
  }

  override func infoMessage(_ message: String, details: String?, context: String?) {
    infoMessages.append(message)
  }

  override func syslogMessage(_ message: String, details: String?, context: String?) {
    syslogMessages.append(message)
  }

  func assertNoErrors(_ file: StaticString = #file, line: UInt = #line) {
    XCTAssert(
      errorMessageKeys.isEmpty,
      "Unexpected error messages printed: \(errorMessageKeys)",
      file: file,
      line: line)
  }

  func assertNoWarnings(_ file: StaticString = #file, line: UInt = #line) {
    let hasOnlyNonFatalWarnings = Set(warningMessageKeys).isSubset(of: nonFatalWarningKeys)
    XCTAssert(
      warningMessageKeys.isEmpty || hasOnlyNonFatalWarnings,
      "Unexpected warning messages printed: \(warningMessageKeys)",
      file: file,
      line: line)
  }
}
