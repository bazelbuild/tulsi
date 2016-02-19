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


/// View controller for the editor that allows selection of BUILD files and high level options.
final class ProjectEditorPackageManagerViewController: NSViewController, NewProjectViewControllerDelegate {

  /// Indices into the Add/Remove SegmentedControl (as built by Interface Builder).
  private enum SegmentedControlButtonIndex: Int {
    case Add = 0
    case Remove = 1
  }

  // Checkbox in the Bazel path open panel's accessory view.
  @IBOutlet weak var bazelSelectorUseAsDefaultCheckbox: NSButton!
  @IBOutlet var packageArrayController: NSArrayController!
  @IBOutlet weak var addRemoveSegmentedControl: NSSegmentedControl!

  var newProjectSheet: NewProjectViewController! = nil
  private var newProjectNeedsSaveAs = false

  dynamic var numSelectedPackagePaths: Int = 0 {
    didSet {
      let enableRemoveButton = numSelectedPackagePaths > 0
      addRemoveSegmentedControl.setEnabled(enableRemoveButton,
                                           forSegment: SegmentedControlButtonIndex.Remove.rawValue)
    }
  }

  deinit {
    unbind("numSelectedPackagePaths")
  }

  override func loadView() {
    NSValueTransformer.setValueTransformer(PackagePathValueTransformer(),
                                           forName: "PackagePathValueTransformer")
    super.loadView()
    bind("numSelectedPackagePaths",
         toObject: packageArrayController,
         withKeyPath: "selectedObjects.@count",
         options: nil)
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    let document = representedObject as! TulsiProjectDocument

    // Start the new project flow if the associated document is not linked to a project.
    if document.fileURL != nil || document.project != nil { return }
    newProjectSheet = NewProjectViewController()
    newProjectSheet.delegate = self
    presentViewControllerAsSheet(newProjectSheet)
  }

  @IBAction func didClickAddRemoveSegmentedControl(sender: NSSegmentedCell) {
    // Ignore mouse up messages.
    if sender.selectedSegment < 0 { return }

    guard let button = SegmentedControlButtonIndex(rawValue: sender.selectedSegment) else {
      assertionFailure("Unexpected add/remove button index \(sender.selectedSegment)")
      return
    }

    switch button {
      case .Add:
        didClickAddBUILDFile(sender)
      case .Remove:
        didClickRemoveSelectedBUILDFiles(sender)
    }
  }

  func didClickAddBUILDFile(sender: AnyObject?) {
    // TODO(abaire): Disallow BUILD files outside of the project's workspace.
    // TODO(abaire): Filter out any BUILD files that are already part of the project.
    let panel = FilteredOpenPanel.filteredOpenPanelAcceptingNonPackageDirectoriesAndFilesNamed(["BUILD"])
    panel.prompt = NSLocalizedString("ProjectEditor_AddBUILDFilePrompt",
                                     comment: "Label for the button used to confirm adding the selected BUILD file to the Tulsi project.")
    panel.canChooseDirectories = false
    panel.beginSheetModalForWindow(self.view.window!) { value in
      if value == NSFileHandlingPanelOKButton {
        guard let URL = panel.URL, document = self.representedObject as? TulsiProjectDocument else {
          return
        }
        if !document.addBUILDFileURL(URL) {
          NSBeep()
        }
      }
    }
  }

  func didClickRemoveSelectedBUILDFiles(sender: AnyObject?) {
    let document = representedObject as! TulsiProjectDocument
    if document.hasChildConfigDocuments {
      let alert = NSAlert()
      alert.messageText = NSLocalizedString("ProjectEditor_CloseOpenedConfigDocumentsMessage",
                                            comment: "Message asking the user if they want to continue with an operation that requires that all opened TulsiGeneratorConfig documents be closed.")
      alert.addButtonWithTitle(NSLocalizedString("ProjectEditor_CloseOpenedConfigDocumentsButtonOK",
                                                 comment: "Title for a button that will proceed with an operation that requires that all opened TulsiGeneratorConfig documents be closed."))
      alert.addButtonWithTitle(NSLocalizedString("ProjectEditor_CloseOpenedConfigDocumentsButtonCancel",
                                                 comment: "Title for a button that will cancel an operation that requires that all opened TulsiGeneratorConfig documents be closed."))
      alert.beginSheetModalForWindow(self.view.window!) { value in
        if value == NSAlertFirstButtonReturn {
          document.closeChildConfigDocuments()
          self.didClickRemoveSelectedBUILDFiles(sender)
        }
      }
      return
    }

    packageArrayController.removeObjectsAtArrangedObjectIndexes(packageArrayController.selectionIndexes)
    let remainingObjects = packageArrayController.arrangedObjects as! [String]
    document.bazelPackages = remainingObjects
  }

  @IBAction func selectBazelPath(sender: AnyObject?) {
    let document = representedObject as! TulsiProjectDocument
    let panel = FilteredOpenPanel.filteredOpenPanelAcceptingNonPackageDirectoriesAndFilesNamed(["bazel", "blaze"])
    panel.message = NSLocalizedString("ProjectEditor_SelectBazelPathMessage",
                                      comment: "Message to show at the top of the Bazel selector sheet, explaining what to do.")
    panel.prompt = NSLocalizedString("ProjectEditor_SelectBazelPathPrompt",
                                     comment: "Label for the button used to confirm the selected Bazel file in the Bazel selector sheet.")

    var views: NSArray?
    NSBundle.mainBundle().loadNibNamed("BazelOpenSheetAccessoryView",
                                       owner: self,
                                       topLevelObjects: &views)
    // Note: topLevelObjects will contain the accessory view and an NSApplication object in a
    // non-deterministic order.
    views = views?.filter() { $0 is NSView }
    if let accessoryView = views?.firstObject as? NSView {
      panel.accessoryView = accessoryView
      if #available(OSX 10.11, *) {
        panel.accessoryViewDisclosed = true
      }
    } else {
      assertionFailure("Failed to load accessory view for Bazel open sheet.")
    }
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.beginSheetModalForWindow(self.view.window!) { value in
      if value == NSFileHandlingPanelOKButton {
        document.bazelURL = panel.URL
        if self.bazelSelectorUseAsDefaultCheckbox.state == NSOnState {
          NSUserDefaults.standardUserDefaults().setURL(document.bazelURL!,
                                                       forKey: TulsiProject.DefaultBazelURLKey)
        }
      }
    }
  }

  @IBAction func didClickClearBazelButton(sender: AnyObject) {
    let document = representedObject as! TulsiProjectDocument
    document.bazelURL = nil
  }

  @IBAction func didDoubleClickPackage(sender: NSTableView) {
    let clickedRow = sender.clickedRow
    guard clickedRow >= 0,
        let package = packageArrayController.arrangedObjects[clickedRow] as? String else {
      return
    }
    let document = representedObject as! TulsiProjectDocument
    let buildFile = package + "/BUILD"
    if let url = document.workspaceRootURL?.URLByAppendingPathComponent(buildFile) {
      NSWorkspace.sharedWorkspace().openURL(url)
    }
  }

  func document(document: NSDocument, didSave: Bool, contextInfo: AnyObject) {
    if !didSave {
      // Nothing useful can be done if the initial save failed so close this window.
      self.view.window!.close()
      return
    }
  }

  // MARK: - NewProjectViewControllerDelegate

  func viewController(vc: NewProjectViewController,
                      didCompleteWithReason reason: NewProjectViewController.CompletionReason) {
    defer {newProjectSheet = nil}
    dismissViewController(newProjectSheet)

    guard reason == .Create else {
      // Nothing useful can be done if the user doesn't wish to create a new project, so close this
      // window.
      self.view.window!.close()
      return
    }

    let document = representedObject as! TulsiProjectDocument
    document.createNewProject(newProjectSheet.projectName!,
                              workspaceFileURL: newProjectSheet.workspacePath!)
    newProjectNeedsSaveAs = true
  }
}


/// Transformer that converts a Bazel package path to an item displayable in the package table view
/// This is primarily necessary to support BUILD files colocated with the workspace root.
final class PackagePathValueTransformer : NSValueTransformer {
  override class func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override class func allowsReverseTransformation() -> Bool  {
    return false
  }

  override func transformedValue(value: AnyObject?) -> AnyObject? {
    guard let value = value as? String else { return nil }
    return "//\(value)"
  }
}
