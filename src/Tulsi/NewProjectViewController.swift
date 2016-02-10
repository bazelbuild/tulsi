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


/// The reason that a NewProjectViewController exited.
enum NewProjectViewControllerCompletionReason {
  case Cancel, Create
}


/// Protocol used to inform receiver of a NewProjectViewController's exit status.
protocol NewProjectViewControllerDelegate: class {
  func viewController(vc: NewProjectViewController,
                      didCompleteWithReason: NewProjectViewControllerCompletionReason)
}


/// View controller for the new project sheet.
class NewProjectViewController: NSViewController {
  dynamic var projectName: String? = nil
  dynamic var workspacePath: NSURL? = nil

  weak var delegate: NewProjectViewControllerDelegate?

  @IBAction func didClickCancelButton(sender: NSButton) {
    delegate?.viewController(self, didCompleteWithReason: .Cancel)
  }

  @IBAction func didClickNextButton(sender: NSButton) {
    self.delegate?.viewController(self, didCompleteWithReason: .Create)
  }

  @IBAction func didClickWorkspacePathControl(sender: NSPathControl) {
    if let clickedCell = sender.clickedPathComponentCell() {
      // Set the value to the clicked folder.
      sender.URL = clickedCell.URL
    } else {
      // The user clicked on the "Choose..." placeholder; treat this as a double click.
      didDoubleClickWorkspacePathControl(sender)
    }
  }

  @IBAction func didDoubleClickWorkspacePathControl(sender: NSPathControl) {
    let panel = FilteredOpenPanel.filteredOpenPanel() {
      (sender: AnyObject, shouldEnableURL url: NSURL) -> Bool in
        var value: AnyObject?
        do {
          try url.getResourceValue(&value, forKey: NSURLIsDirectoryKey)
          return url.lastPathComponent == "WORKSPACE";
        } catch _ {
        }
        return false
    }

    if let clickedCell = sender.clickedPathComponentCell() {
      panel.directoryURL = clickedCell.URL
    }

    panel.message = NSLocalizedString("NewProject_SetProjectWorkspaceMessage",
                                      comment: "Message to show at the top of WORKSPACE file selector sheet, explaining what to do.")
    panel.prompt = NSLocalizedString("NewProject_SetProjectWorkspacePrompt",
                                     comment: "Label for the button used to confirm the selected WORKSPACE.")

    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.beginSheetModalForWindow(self.view.window!) { value in
      if value == NSFileHandlingPanelOKButton {
        self.workspacePath = panel.URL
      }
    }
  }
}
