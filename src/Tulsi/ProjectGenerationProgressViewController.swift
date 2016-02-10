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


/// Models a Tulsi generator action whose progress should be monitored.
class ProgressItem: NSObject {
  dynamic let label: String
  dynamic let maxValue: Int
  dynamic var value: Int

  init(notifier: AnyObject?, values: [NSObject: AnyObject]) {
    let taskName = values[ProgressUpdatingTaskName] as! String
    label = NSLocalizedString(taskName,
                              value: taskName,
                              comment: "User friendly version of \(taskName)")
    maxValue = values[ProgressUpdatingTaskMaxValue] as! Int
    value = 0

    super.init()

    let notificationCenter = NSNotificationCenter.defaultCenter()
    notificationCenter.addObserver(self,
                                   selector: Selector("progressUpdate:"),
                                   name: ProgressUpdatingTaskProgress,
                                   object: notifier)
  }

  deinit {
    NSNotificationCenter.defaultCenter().removeObserver(self)
  }

  func progressUpdate(notification: NSNotification) {
    if let newValue = notification.userInfo?[ProgressUpdatingTaskProgressValue] as? Int {
      value = newValue
    }
  }
}


/// Wizard subview that kicks off project generation and displays progress.
class ProjectGenerationProgressViewController: NSViewController, WizardSubviewProtocol {
  dynamic var progressItems = [ProgressItem]()
  weak var outputFolderOpenPanel: NSOpenPanel? = nil

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    let notificationCenter = NSNotificationCenter.defaultCenter()
    notificationCenter.addObserver(self,
                                   selector: Selector("progressUpdatingTaskDidStart:"),
                                   name: ProgressUpdatingTaskDidStart,
                                   object: nil)
  }

  deinit {
    NSNotificationCenter.defaultCenter().removeObserver(self)
  }

  func progressUpdatingTaskDidStart(notification: NSNotification) {
    guard let values = notification.userInfo else {
      assertionFailure("Progress task notification received without parameters.")
      return
    }

    progressItems.append(ProgressItem(notifier: notification.object, values: values))
  }

  override func viewDidAppear() {
    super.viewDidAppear()

    // If the user hasn't selected an output path yet, force them to do so now.
    let document = representedObject as! TulsiDocument
    guard document.outputFolderURL == nil && !ProjectOutputFolderPanel.displaying else {
      return
    }
    ProjectOutputFolderPanel.beginSheetModalForWindow(self.view.window!,
                                                      document: document,
                                                      initialURL: nil,
                                                      generationAction: true) { value in
      if value == NSFileHandlingPanelOKButton {
        document.generateAndOpenProject()
      } else {
        // Treat this as though the user navigated back to the options page.
        self.presentingWizardViewController?.previous()
      }
    }
  }

  // MARK: - WizardSubviewProtocol

  weak var presentingWizardViewController: WizardViewController? = nil

  func wizardSubviewWillActivateMovingForward() {
    progressItems = []
    let document = representedObject as! TulsiDocument
    // If the user has selected an output path, start generating now, if not, an open panel will be
    // displayed when the view becomes visible.
    if document.outputFolderURL != nil {
      document.generateAndOpenProject()
    }
  }
}
