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


/// Encapsulates posting progress update notifications.
final class ProgressNotifier {
  private let name: String
  private let maxValue: Int
  private let indeterminate: Bool

  var value: Int = 0 {
    didSet {
      Thread.doOnMainQueue() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.post(name: Notification.Name(rawValue: ProgressUpdatingTaskProgress),
                                                object: self,
                                                userInfo: [
                                                    ProgressUpdatingTaskProgressValue: self.value,
                                                ])
      }
    }
  }

  /// Initializes a new instance with the given name and maximum value.
  init(name: String, maxValue: Int, indeterminate: Bool = false, suppressStart: Bool = false) {
    self.name = name
    self.maxValue = maxValue
    self.indeterminate = indeterminate

    if !suppressStart {
      start()
    }
  }

  func start() {
    Thread.doOnMainQueue() {
      let notificationCenter = NotificationCenter.default
      notificationCenter.post(name: Notification.Name(rawValue: ProgressUpdatingTaskDidStart),
                                              object: self,
                                              userInfo: [
                                                  ProgressUpdatingTaskName: self.name,
                                                  ProgressUpdatingTaskMaxValue: self.maxValue,
                                                  ProgressUpdatingTaskStartIndeterminate: self.indeterminate,
                                              ])
    }
  }

  func incrementValue() {
    Thread.doOnMainQueue() {
      self.value += 1
    }
  }
}
