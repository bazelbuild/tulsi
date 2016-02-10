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

import Cocoa

/// Models a single user-facing message.
class UIMessage: NSObject, NSPasteboardWriting {
  @objc
  enum MessageType: Int {
    case Info, Warning, Error
  }

  dynamic let text: String
  dynamic let messageType: MessageType
  let timestamp = NSDate()

  init(text: String, type: MessageType) {
    self.text = text
    self.messageType = type
  }

  // MARK: - NSPasteboardWriting

  func writableTypesForPasteboard(pasteboard: NSPasteboard) -> [String] {
    return [NSPasteboardTypeString]
  }

  func pasteboardPropertyListForType(type: String) -> AnyObject? {
    if type == NSPasteboardTypeString {
      let timeString = NSDateFormatter.localizedStringFromDate(timestamp,
                                                               dateStyle: .NoStyle,
                                                               timeStyle: .MediumStyle)
      return "[\(timeString)](\(messageType.rawValue)): \(text)"
    }
    return nil
  }
}
