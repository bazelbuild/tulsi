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
  let bundle: NSBundle?

  init(bundle: NSBundle?) {
    self.bundle = bundle
  }

  func startProfiling(name: String,
                      message: String? = nil,
                      context: String? = nil) -> (String, NSDate, String?) {
    if let concreteMessage = message {
      syslogMessage(concreteMessage, context: context)
    }
    return (name, NSDate(), context)
  }

  func logProfilingEnd(token: (String, NSDate, String?)) {
    let timeTaken = NSDate().timeIntervalSinceDate(token.1)
    syslogMessage(String(format: "** Completed %@ in %.4fs", token.0, timeTaken), context: token.2)
  }

  func error(key: String,
             comment: String,
             details: String? = nil,
             context: String? = nil,
             values: CVarArgType...) {
    if bundle == nil { return }

    let formatString = NSLocalizedString(key, bundle: self.bundle!, comment: comment)
    let message = String(format: formatString, arguments: values)
    LogMessage.postError(message, details: details, context: context)
  }

  func warning(key: String,
               comment: String,
               details: String? = nil,
               context: String? = nil,
               values: CVarArgType...) {
    if bundle == nil { return }

    let formatString = NSLocalizedString(key, bundle: self.bundle!, comment: comment)
    let message = String(format: formatString, arguments: values)
    LogMessage.postWarning(message, details: details, context: context)
  }

  func infoMessage(message: String, details: String? = nil, context: String? = nil) {
    LogMessage.postInfo(message, details: details, context: context)
  }

  func syslogMessage(message: String, details: String? = nil, context: String? = nil) {
    LogMessage.postSyslog(message, details: details, context: context)
  }
}
