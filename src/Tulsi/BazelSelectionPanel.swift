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


/// NSOpenPanel that allows the user to select a Bazel binary for a given project document.
class BazelSelectionPanel: FilteredOpenPanel {

  // Checkbox in the Bazel path open panel's accessory view.
  @IBOutlet weak var bazelSelectorUseAsDefaultCheckbox: NSButton!

  @discardableResult
  static func beginSheetModalBazelSelectionPanelForWindow(_ window: NSWindow,
                                                          document: TulsiProjectDocument,
                                                          completionHandler: ((URL?) -> Void)? = nil) -> BazelSelectionPanel {
    let panel = BazelSelectionPanel()
    panel.delegate = panel
    panel.message = NSLocalizedString("ProjectEditor_SelectBazelPathMessage",
                                      comment: "Message to show at the top of the Bazel selector sheet, explaining what to do.")
    panel.prompt = NSLocalizedString("ProjectEditor_SelectBazelPathPrompt",
                                     comment: "Label for the button used to confirm the selected Bazel file in the Bazel selector sheet.")

    var views: NSArray?
    Bundle.main.loadNibNamed("BazelOpenSheetAccessoryView",
                             owner: panel,
                             topLevelObjects: &views)
    // Note: topLevelObjects will contain the accessory view and an NSApplication object in a
    // non-deterministic order.
    if let views = views {
      let viewsFound = views.filter() { $0 is NSView } as NSArray
      if let accessoryView = viewsFound.firstObject as? NSView {
        panel.accessoryView = accessoryView
        if #available(OSX 10.11, *) {
          panel.isAccessoryViewDisclosed = true
        }
      } else {
        assertionFailure("Failed to load accessory view for Bazel open sheet.")
      }
    }
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.directoryURL = document.bazelURL?.deletingLastPathComponent()
    panel.beginSheetModal(for: window) { value in
      if value == NSApplication.ModalResponse.OK {
        document.bazelURL = panel.url
        if panel.bazelSelectorUseAsDefaultCheckbox.state == NSControl.StateValue.on {
          UserDefaults.standard.set(document.bazelURL!, forKey: BazelLocator.DefaultBazelURLKey)
        }
      }

      // Forcibly dismiss the panel before invoking the completion handler in case completion
      // spawns new sheet modals.
      panel.orderOut(panel)
      if let completionHandler = completionHandler {
        completionHandler(value == NSApplication.ModalResponse.OK ? panel.url : nil)
      }
    }
    return panel
  }
}
