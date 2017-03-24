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
  let bundle: Bundle?

  init(bundle: Bundle?) {
    self.bundle = bundle
  }

  func startProfiling(_ name: String,
                      message: String? = nil,
                      context: String? = nil) -> (String, Date, String?) {
    if let concreteMessage = message {
      syslogMessage(concreteMessage, context: context)
    }
    return (name, Date(), context)
  }

  func logProfilingEnd(_ token: (String, Date, String?)) {
    let timeTaken = Date().timeIntervalSince(token.1)
    syslogMessage(String(format: "** Completed %@ in %.4fs", token.0, timeTaken), context: token.2)
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

  static func bugWorthyComment(_ comment: String) -> String {
    return "\(comment). The resulting project will most likely be broken. A bug should be reported."
  }
}
