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


/// Provides functionality to log messages using a localized string table.
class LocalizedMessageLogger {

  /// Structure representing a logging session in process.
  struct LogSessionHandle {
    /// A name for this process, visible to the user via logging.
    let name: String
    /// When this logging session began.
    var startTime: Date
    /// Additional contextual information about this logging session, to be visible via logging.
    let context: String?

    init(_ name: String, context: String?) {
      self.name = name
      self.startTime = Date()
      self.context = context
    }

    /// Reset the start time for this logging session to the moment when method was called.
    mutating func resetStartTime() {
      startTime = Date()
    }
  }

  let bundle: Bundle?

  init(bundle: Bundle?) {
    self.bundle = bundle
  }

  func startProfiling(_ name: String,
                      message: String? = nil,
                      context: String? = nil) -> LogSessionHandle {
    if let concreteMessage = message {
      syslogMessage(concreteMessage, context: context)
    }
    return LogSessionHandle(name, context: context)
  }

  func logProfilingEnd(_ token: LogSessionHandle) {
    let timeTaken = Date().timeIntervalSince(token.startTime)
    syslogMessage(String(format: "** Completed %@ in %.4fs",
                         token.name,
                         timeTaken),
                  context: token.context)
  }

  func error(_ key: String,
             comment: String,
             details: String? = nil,
             context: String? = nil,
             values: CVarArg...) {
    if bundle == nil { return }

    let formatString = NSLocalizedString(key, bundle: self.bundle!, comment: comment)
    let message = String(format: formatString, arguments: values)
    LogMessage.postError(message, details: details, context: context)
  }

  func warning(_ key: String,
               comment: String,
               details: String? = nil,
               context: String? = nil,
               values: CVarArg...) {
    if bundle == nil { return }

    let formatString = NSLocalizedString(key, bundle: self.bundle!, comment: comment)
    let message = String(format: formatString, arguments: values)
    LogMessage.postWarning(message, details: details, context: context)
  }

  func infoMessage(_ message: String, details: String? = nil, context: String? = nil) {
    LogMessage.postInfo(message, details: details, context: context)
  }

  func syslogMessage(_ message: String, details: String? = nil, context: String? = nil) {
    LogMessage.postSyslog(message, details: details, context: context)
  }

  func debugMessage(_ message: String, details: String? = nil, context: String? = nil) {
    LogMessage.postDebug(message, details: details, context: context)
  }

  static func bugWorthyComment(_ comment: String) -> String {
    return "\(comment). The resulting project will most likely be broken. A bug should be reported."
  }
}
