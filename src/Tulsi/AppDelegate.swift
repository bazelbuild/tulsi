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


final class AppDelegate: NSObject, NSApplicationDelegate {

  var splashScreenWindowController: SplashScreenWindowController! = nil

  @IBAction func fileBugReport(sender: NSMenuItem) {
    BugReporter.fileBugReport()
  }

  // MARK: - NSApplicationDelegate

  func applicationWillFinishLaunching(notification: NSNotification) {
    // Create the shared document controller.
    let _ = TulsiDocumentController()
  }

  func applicationDidFinishLaunching(notification: NSNotification) {
    splashScreenWindowController = SplashScreenWindowController()
    splashScreenWindowController.window?.contentView?.layer?.backgroundColor = NSColor.whiteColor().CGColor
    splashScreenWindowController.showWindow(self)
  }

  func applicationShouldOpenUntitledFile(sender: NSApplication) -> Bool {
    return false
  }

  func applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication) -> Bool {
    return true
  }
}
