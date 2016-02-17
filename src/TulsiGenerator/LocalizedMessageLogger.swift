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


class LocalizedMessageLogger {
  let messageLogger: MessageLoggerProtocol?
  let bundle: NSBundle?

  init(messageLogger: MessageLoggerProtocol?, bundle: NSBundle?) {
    self.messageLogger = messageLogger
    self.bundle = bundle
  }

  func startProfiling(name: String, message: String? = nil) -> (String, NSDate) {
    if let concreteMessage = message {
      infoMessage(concreteMessage)
    }
    return (name, NSDate())
  }

  func logProfilingEnd(token: (String, NSDate)) {
    let timeTaken = NSDate().timeIntervalSinceDate(token.1)
    infoMessage(String(format: "** Completed %@ in %.4fs", token.0, timeTaken))
  }

  func infoMessage(message: String) {
    if messageLogger == nil { return }

    NSThread.doOnMainThread() { self.messageLogger!.info(message) }
  }

  func warning(key: String, comment: String, values: CVarArgType...) {
    if messageLogger == nil || bundle == nil { return }

    NSThread.doOnMainThread() {
      let formatString = NSLocalizedString(key, bundle: self.bundle!, comment: comment)
      let message = String(format: formatString, arguments: values)
      self.messageLogger!.warning(message)
    }
  }

  func error(key: String, comment: String, values: CVarArgType...) {
    if messageLogger == nil || bundle == nil { return }

    NSThread.doOnMainThread() {
      let formatString = NSLocalizedString(key, bundle: self.bundle!, comment: comment)
      let message = String(format: formatString, arguments: values)
      self.messageLogger!.error(message)
    }
  }
}
