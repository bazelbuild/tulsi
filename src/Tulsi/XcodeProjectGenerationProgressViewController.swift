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

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)) {
      let projectURL = self.generateXcodeProjectForConfigName(name)
      NSThread.doOnMainThread() {
        completionHandler(projectURL)
      }
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

  private func generateXcodeProjectForConfigName(name: String) -> NSURL? {
    assert(!NSThread.isMainThread(), "Must not be called from the main thread")

    let document = self.representedObject as! TulsiProjectDocument
    guard let workspaceRootURL = document.workspaceRootURL else {
      document.error(NSLocalizedString("Error_BadWorkspace",
                                       comment: "General error when project does not have a valid Bazel workspace."))
      return nil
    }
    guard let concreteOutputFolderURL = outputFolderURL else {
      // This should never actually happen and indicates an unexpected path through the UI.
      document.error(NSLocalizedString("Error_NoOutputFolder",
                                       comment: "Error for a generation attempt without a valid target output folder"))
      return nil
    }

    guard let configDocument = getConfigDocumentNamed(name) else {
      // Error messages have already been displayed.
      return nil
    }

    return configDocument.generateXcodeProjectInFolder(concreteOutputFolderURL,
                                                       withWorkspaceRootURL: workspaceRootURL)
  }

  /// Loads a previously created config with the given name.
  private func getConfigDocumentNamed(name: String) -> TulsiGeneratorConfigDocument? {
    assert(!NSThread.isMainThread(), "Must not be called from the main thread")
    let document = self.representedObject as! TulsiProjectDocument

    guard let configURL = TulsiGeneratorConfigDocument.urlForConfigNamed(name,
                                                                         inFolderURL: document.generatorConfigFolderURL) else {
      let fmt = NSLocalizedString("Error_GeneralProjectGenerationFailure",
                                  comment: "A general, critical failure during project generation. Details are provided as %1$@.")
      document.error(String(format: fmt, "No URL for config named '\(name)'"))
      return nil
    }

    let documentController = NSDocumentController.sharedDocumentController()
    if let configDocument = documentController.documentForURL(configURL) as? TulsiGeneratorConfigDocument {
      return configDocument
    }

    let errorData: String
    do {
      return try TulsiGeneratorConfigDocument.makeDocumentWithContentsOfURL(configURL,
                                                                            infoExtractor: document.infoExtractor,
                                                                            messageLogger: document,
                                                                            bazelURL: document.bazelURL)
    } catch let e as NSError {
      errorData = "Failed to load config from '\(configURL.path)' with error \(e.localizedDescription)"
    } catch {
      errorData = "Unexpected exception loading config from '\(configURL.path)'"
    }

    let fmt = NSLocalizedString("Error_GeneralProjectGenerationFailure",
                                comment: "A general, critical failure during project generation. Details are provided as %1$@.")
    document.error(String(format: fmt, errorData))
    return nil
  }
}
