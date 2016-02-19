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
import TulsiGenerator


final class AppDelegate: NSObject, NSApplicationDelegate, NSUserInterfaceValidations {

  @IBAction func fileBugReport(sender: NSMenuItem) {
    BugReporter.fileBugReport()
  }

  // MARK: - NSApplicationDelegate

  func applicationShouldOpenUntitledFile(sender: NSApplication) -> Bool {
    if let (_, mode) = GetXcodeURLFromCurrentAppleEvent() where mode == .OpenProject {
      NSDocumentController.sharedDocumentController().openDocument(sender)
      return false
    }
    return true
  }

  func applicationShouldHandleReopen(sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // If the apple event that opened us contains an Xcode URL, we want to treat this as a menu
    // command rather than simply restoring focus.
    if let (_, mode) = GetXcodeURLFromCurrentAppleEvent() {
      switch mode {
        case .NewProject:
          NSDocumentController.sharedDocumentController().newDocument(sender)
        case .OpenProject:
          NSDocumentController.sharedDocumentController().openDocument(sender)
      }
      return false
    }
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication) -> Bool {
    return true
  }

  // MARK: - NSUserInterfaceValidations

  func validateUserInterfaceItem(anItem: NSValidatedUserInterfaceItem) -> Bool {
    // Nothing useful can be done if there is no current document.
    return NSDocumentController.sharedDocumentController().currentDocument as? TulsiProjectDocument != nil
  }
}
