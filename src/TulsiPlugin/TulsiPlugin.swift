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
  // The text of the menu item before which the Tulsi group should be injected.
  private let TulsiMenuItemFollowingAnchor = "Save As Workspace…"

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

  func createMenuItems() {
    removeObserver()

    guard let fileItem = NSApp.mainMenu!.itemWithTitle("File") else {
      showInstallationFailureAlert("Unable to find 'File' menu.")
      return
    }

    guard let fileSubmenu = fileItem.submenu else {
      showInstallationFailureAlert("Unable to find 'File' submenu.")
      return
    }

    installFileMenuItems(fileSubmenu)
  }

  func doNewTulsiProjectMenuAction() {
    launchTulsiWithMode(.NewProject)
  }

  func doOpenTulsiProjectMenuAction() {
    launchTulsiWithMode(.OpenProject)
  }

  // MARK: - Private methods

  private func removeObserver() {
    NSNotificationCenter.defaultCenter().removeObserver(self)
  }

  private func showInstallationFailureAlert(informativeText: String) {
    let alert = NSAlert()
    alert.messageText = "Unable to load Tulsi Xcode Plugin"
    alert.informativeText = informativeText
    alert.runModal()
  }

  private func installFileMenuItems(fileSubmenu: NSMenu) {
    let anchorIndex = fileSubmenu.indexOfItemWithTitle(TulsiMenuItemFollowingAnchor)
    if anchorIndex < 0 {
      showInstallationFailureAlert("Unable to find '\(TulsiMenuItemFollowingAnchor)' in the File menu.")
      return
    }

    let tulsiMenuItem = NSMenuItem(title: "Tulsi", action: nil, keyEquivalent: "")
    tulsiMenuItem.submenu = createTulsiSubmenu()
    fileSubmenu.insertItem(tulsiMenuItem, atIndex: anchorIndex - 1)
  }

  private func createTulsiSubmenu() -> NSMenu? {
    let submenu = NSMenu(title: "Tulsi")

    func addItemWithTitle(title: String, action: Selector) {
      guard let item = submenu.addItemWithTitle(title, action: action, keyEquivalent: "") else {
        showInstallationFailureAlert("Unable to create '\(title)' submenu item.")
        return
      }
      item.target = self
    }

    addItemWithTitle("New project…", action: "doNewTulsiProjectMenuAction")
    addItemWithTitle("Open project…", action: "doOpenTulsiProjectMenuAction")

    return submenu
  }

  private func launchTulsiWithMode(mode: TulsiLaunchMode) {
    let url = NSURL(fileURLWithPath:NSBundle.mainBundle().bundlePath)
    let recordDesc = CreateTulsiAppleEventRecord(url, mode: mode)
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
