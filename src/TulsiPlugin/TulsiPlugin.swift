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

import AppKit

// Simple plugin that installs the Tulsi "Open BUILD…" menu item.
class TulsiPlugin: NSObject {

  var bundle: NSBundle

  init(bundle: NSBundle) {
    self.bundle = bundle

    super.init()
    NSNotificationCenter.defaultCenter().addObserver(
        self, selector: Selector("createMenuItems"), name: NSApplicationDidFinishLaunchingNotification, object: nil)
  }

  deinit {
    removeObserver()
  }

  func removeObserver() {
    NSNotificationCenter.defaultCenter().removeObserver(self)
  }

  func createMenuItems() {
    removeObserver()

    let messageText = "Unable to load Tulsi Xcode Plugin"

    guard let item = NSApp.mainMenu!.itemWithTitle("File") else {
      let alert = NSAlert()
      alert.messageText = messageText
      alert.informativeText = "Unable to find 'File' menu."
      alert.runModal()
      return
    }

    guard let submenu = item.submenu else {
      let alert = NSAlert()
      alert.messageText = messageText
      alert.informativeText = "Unable to find 'File' submenu."
      alert.runModal()
      return
    }

    let index = submenu.indexOfItemWithTitle("Open…")
    if index == -1 {
      let alert = NSAlert()
      alert.messageText = messageText
      alert.informativeText = "Unable to find 'Open…' command in File menu."
      alert.runModal()
      return
    }

    let actionMenuItem = NSMenuItem(title:"Open BUILD…", action:"doMenuAction", keyEquivalent:"")
    actionMenuItem.target = self
    submenu.insertItem(actionMenuItem, atIndex: index + 1)
  }

  func doMenuAction() {
    let url = NSURL(fileURLWithPath:NSBundle.mainBundle().bundlePath)
    let recordDesc = CreateTulsiAppleEventRecord(url)
    if (!NSWorkspace.sharedWorkspace().launchAppWithBundleIdentifier(
        "com.google.Tulsi", options: NSWorkspaceLaunchOptions.Default, additionalEventParamDescriptor: recordDesc, launchIdentifier: nil)) {

      let alert = NSAlert()
      alert.messageText = "Unable to launch Tulsi"
      alert.informativeText = "Please make sure Tulsi.app is installed on your computer (com.google.Tulsi)."
      alert.runModal()
      return
    }
  }
}
