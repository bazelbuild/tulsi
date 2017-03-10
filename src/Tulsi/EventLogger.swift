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
import TulsiGenerator


/// Writes events to the console.
final class EventLogger {
  private let verbose: Bool
  private var observer: NSObjectProtocol? = nil

  init(verbose: Bool) {
    self.verbose = verbose
  }

  deinit {
    if let observer = self.observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func startLogging() {
    observer = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: TulsiMessageNotification),
                                                      object: nil,
                                                      queue: nil) {
      [weak self] (notification: Notification) in
        guard let item = LogMessage(notification: notification),
              let verbose = self?.verbose, verbose || item.level != .Info else {
          return
        }

        let level: String = item.level.rawValue
        let details: String
        if let itemDetails = item.details {
          details = " \(itemDetails)"
        } else {
          details = ""
        }
        print("[\(level)] \(item.message)\(details)")
    }
  }
}
