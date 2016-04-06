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
  dynamic var indeterminate: Bool

  init(notifier: AnyObject?, values: [NSObject: AnyObject]) {
    let taskName = values[ProgressUpdatingTaskName] as! String
    label = NSLocalizedString(taskName,
                              value: taskName,
                              comment: "User friendly version of \(taskName)")
    maxValue = values[ProgressUpdatingTaskMaxValue] as! Int
    value = 0
    indeterminate = values[ProgressUpdatingTaskStartIndeterminate] as? Bool ?? false

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
    indeterminate = false
    if let newValue = notification.userInfo?[ProgressUpdatingTaskProgressValue] as? Int {
      value = newValue
    }
  }
}


/// Handles generation of an Xcode project and displaying progress.
class XcodeProjectGenerationProgressViewController: NSViewController {
  dynamic var progressItems = [ProgressItem]()

  weak var outputFolderOpenPanel: NSOpenPanel? = nil

  var outputFolderURL: NSURL? = nil

  deinit {
    NSNotificationCenter.defaultCenter().removeObserver(self)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    let notificationCenter = NSNotificationCenter.defaultCenter()
    notificationCenter.addObserver(self,
                                   selector: Selector("progressUpdatingTaskDidStart:"),
                                   name: ProgressUpdatingTaskDidStart,
                                   object: nil)
  }

  // Extracts source paths for selected source rules, generates a PBXProject and opens it.
  func generateProjectForConfigName(name: String, completionHandler: (NSURL?) -> Void) {
    assert(view.window != nil, "Must not be called until after the view controller is presented.")
    if outputFolderURL == nil {
      showOutputFolderPicker() { (url: NSURL?) in
        guard let url = url else {
          completionHandler(nil)
          return
        }
        self.outputFolderURL = url
        self.generateProjectForConfigName(name, completionHandler: completionHandler)
      }
      return
    }

    generateXcodeProjectForConfigName(name) { (projectURL: NSURL?) in
      completionHandler(projectURL)
    }
  }

  func progressUpdatingTaskDidStart(notification: NSNotification) {
    guard let values = notification.userInfo else {
      assertionFailure("Progress task notification received without parameters.")
      return
    }
    progressItems.append(ProgressItem(notifier: notification.object, values: values))
  }

  // MARK: - Private methods

  private func showOutputFolderPicker(completionHandler: (NSURL?) -> Void) {
    let panel = NSOpenPanel()
    panel.title = NSLocalizedString("ProjectGeneration_SelectProjectOutputFolderTitle",
                                    comment: "Title for open panel through which the user should select where to generate the Xcode project.")
    panel.message = NSLocalizedString("ProjectGeneration_SelectProjectOutputFolderMessage",
                                      comment: "Message to show at the top of the Xcode output folder sheet, explaining what to do.")

    panel.prompt = NSLocalizedString("ProjectGeneration_SelectProjectOutputFolderAndGeneratePrompt",
                                     comment: "Label for the button used to confirm the selected output folder for the generated Xcode project which will also start generating immediately.")
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.beginSheetModalForWindow(view.window!) {
      let url: NSURL?
      if $0 == NSFileHandlingPanelOKButton {
        url = panel.URL
      } else {
        url = nil
      }
      completionHandler(url)
    }
  }

  /// Asynchronously generates an Xcode project, invoking the given completionHandler on the main
  /// thread with an URL to the generated project (or nil to indicate failure).
  private func generateXcodeProjectForConfigName(name: String, completionHandler: (NSURL? -> Void)) {
    let document = self.representedObject as! TulsiProjectDocument
    guard let workspaceRootURL = document.workspaceRootURL else {
      document.error(NSLocalizedString("Error_BadWorkspace",
                                       comment: "General error when project does not have a valid Bazel workspace."))
      NSThread.doOnMainThread() {
        completionHandler(nil)
      }
      return
    }
    guard let concreteOutputFolderURL = outputFolderURL else {
      // This should never actually happen and indicates an unexpected path through the UI.
      document.error(NSLocalizedString("Error_NoOutputFolder",
                                       comment: "Error for a generation attempt without a valid target output folder"))
      NSThread.doOnMainThread() {
        completionHandler(nil)
      }
      return
    }

    guard let configDocument = getConfigDocumentNamed(name) else {
      // Error messages have already been displayed.
      completionHandler(nil)
      return
    }

    NSThread.doOnQOSUserInitiatedThread() {
      let url = configDocument.generateXcodeProjectInFolder(concreteOutputFolderURL,
                                                            withWorkspaceRootURL: workspaceRootURL)
      NSThread.doOnMainThread() {
        completionHandler(url)
      }
    }
  }

  /// Loads a previously created config with the given name as a sparse document.
  private func getConfigDocumentNamed(name: String) -> TulsiGeneratorConfigDocument? {
    let document = self.representedObject as! TulsiProjectDocument

    let errorInfo: String
    do {
      return try document.loadSparseConfigDocumentNamed(name)
    } catch TulsiProjectDocument.Error.NoSuchConfig {
      errorInfo = "No URL for config named '\(name)'"
    } catch TulsiProjectDocument.Error.ConfigLoadFailed(let info) {
      errorInfo = info
    } catch {
      errorInfo = "An unexpected exception occurred while loading config named '\(name)'"
    }

    let fmt = NSLocalizedString("Error_GeneralProjectGenerationFailure",
                                comment: "A general, critical failure during project generation. Details are provided as %1$@.")
    document.error(String(format: fmt, errorInfo))
    return nil
  }
}
