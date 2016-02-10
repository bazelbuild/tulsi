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

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationOpenUntitledFile(sender: NSApplication) -> Bool {
    // Go through openDocument instead of standard new handling as new and open are equivalent.
    NSDocumentController.sharedDocumentController().openDocument(sender)
    return true
  }

  // MARK: - NSApplicationDelegate

  func applicationShouldHandleReopen(sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // If the apple event that opened us contains an Xcode URL, we want to treat this as an
    // "Open..." rather than simply restoring focus as it came from the Tulsi Plugin
    // "Open Tulsi Project…" invocation.
    if let _ = GetXcodeURLFromCurrentAppleEvent() {
      NSDocumentController.sharedDocumentController().openDocument(sender)
      return false
    }
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication) -> Bool {
    return true
  }
}
