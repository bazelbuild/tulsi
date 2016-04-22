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


/// View controller for the editor that allows management of Generator Configs associated with a
/// project.
final class ProjectEditorConfigManagerViewController: NSViewController {

  /// Indices into the Add/Remove SegmentedControl (as built by Interface Builder).
  private enum SegmentedControlButtonIndex: Int {
    case Add = 0
    case Remove = 1
  }

  // Context indicating that a new config should be added after a document save completes.
  private static var PostSaveContextAddConfig = 0

  @IBOutlet var configArrayController: NSArrayController!
  @IBOutlet weak var addRemoveSegmentedControl: NSSegmentedControl!

  dynamic var numBazelPackages: Int = 0 {
    didSet {
      let enableAddButton = numBazelPackages > 0
      addRemoveSegmentedControl.setEnabled(enableAddButton,
                                           forSegment: SegmentedControlButtonIndex.Add.rawValue)
    }
  }

  dynamic var numSelectedConfigs: Int = 0 {
    didSet {
      let enableRemoveButton = numSelectedConfigs > 0
      addRemoveSegmentedControl.setEnabled(enableRemoveButton,
                                           forSegment: SegmentedControlButtonIndex.Remove.rawValue)
    }
  }

  override var representedObject: AnyObject? {
    didSet {
      if let concreteRepresentedObject = representedObject {
        bind("numBazelPackages",
             toObject: concreteRepresentedObject,
             withKeyPath: "bazelPackages.@count",
             options: nil)
      }
    }
  }

  deinit {
    unbind("numBazelPackages")
    unbind("numSelectedConfigs")
  }

  override func loadView() {
    NSValueTransformer.setValueTransformer(IsOneValueTransformer(),
                                           forName: "IsOneValueTransformer")
    super.loadView()
    bind("numSelectedConfigs",
         toObject: configArrayController,
         withKeyPath: "selectedObjects.@count",
         options: nil)
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
        didClickAddConfig(sender)
      case .Remove:
        didClickRemoveSelectedConfigs(sender)
    }
  }

  @IBAction func doGenerate(sender: AnyObject?) {
    // TODO(abaire): Make it clear to the user that only the first selection is generated.
    guard let configName = configArrayController.selectedObjects.first as? String else { return }
    guard requireValidBazel({ self.doGenerate(sender) }) else { return }

    let generatorController = XcodeProjectGenerationProgressViewController()
    generatorController.representedObject = representedObject
    presentViewControllerAsSheet(generatorController)

    generatorController.generateProjectForConfigName(configName) { (projectURL: NSURL?) in
      self.dismissViewController(generatorController)
      if let projectURL = projectURL {
        let projectDocument = self.representedObject as! TulsiProjectDocument
        projectDocument.info("Opening generated project in Xcode")
        NSWorkspace.sharedWorkspace().openURL(projectURL)
      }
    }
  }

  @IBAction func didDoubleClickConfigRow(sender: NSTableView) {
    guard requireValidBazel({ self.didDoubleClickConfigRow(sender) }) else { return }

    let projectDocument = representedObject as! TulsiProjectDocument
    let clickedRow = sender.clickedRow
    guard clickedRow >= 0 else { return }
    let configName = (configArrayController.arrangedObjects as! [String])[clickedRow]
    let errorInfo: String
    do {
      let configDocument = try projectDocument.loadConfigDocumentNamed(configName) { (_) in
        // Nothing in particular has to be done when the config doc is loaded, the editor UI already
        // handles this via the document's processing state.
      }
      configDocument.makeWindowControllers()
      configDocument.showWindows()
      return
    } catch TulsiProjectDocument.Error.NoSuchConfig {
      errorInfo = "No URL for config named '\(configName)'"
    } catch TulsiProjectDocument.Error.ConfigLoadFailed(let info) {
      errorInfo = info
    } catch {
      errorInfo = "An unexpected exception occurred while loading config named '\(configName)'"
    }
    let fmt = NSLocalizedString("Error_ConfigLoadFailed",
                                comment: "Error when a TulsiGeneratorConfig failed to be reloaded. Details are provided as %1$@.")
    projectDocument.error(String(format: fmt, errorInfo))
  }

  func document(doc:NSDocument, didSave:Bool, contextInfo: UnsafeMutablePointer<Void>) {
    if contextInfo == &ProjectEditorConfigManagerViewController.PostSaveContextAddConfig {
      if didSave {
        didClickAddConfig(nil)
      }
    }
  }

  // MARK: - Private methods

  private func didClickAddConfig(sender: AnyObject?) {
    guard requireValidBazel({ self.didClickAddConfig(sender) }) else { return }

    let projectDocument = representedObject as! TulsiProjectDocument

    // Adding a config to a project with no bazel packages is disallowed.
    guard let bazelPackages = projectDocument.bazelPackages where !bazelPackages.isEmpty else {
      // This should be prevented by the UI, so spawn a bug message and beep.
      projectDocument.info("Bug: Add config invoked on a project with no packages.")
      NSBeep()
      return
    }

    let errorInfo: String
    do {
      let additionalFilePaths = bazelPackages.map() { "\($0)/BUILD" }
      guard let projectName = projectDocument.projectName,
                generatorConfigFolderURL = projectDocument.generatorConfigFolderURL else {
        projectDocument.saveDocumentWithDelegate(self,
                                                 didSaveSelector: Selector("document:didSave:contextInfo:"),
                                                 contextInfo: &ProjectEditorConfigManagerViewController.PostSaveContextAddConfig)
        return
      }

      let optionSet = projectDocument.optionSet ?? TulsiOptionSet()
      let configDocument = try TulsiGeneratorConfigDocument.makeDocumentWithProjectRuleEntries(projectDocument.ruleInfos,
                                                                                               optionSet: optionSet,
                                                                                               projectName: projectName,
                                                                                               saveFolderURL: generatorConfigFolderURL,
                                                                                               infoExtractor: projectDocument.infoExtractor,
                                                                                               messageLogger: projectDocument,
                                                                                               messageLog: projectDocument,
                                                                                               additionalFilePaths: additionalFilePaths,
                                                                                               bazelURL: projectDocument.bazelURL)
      projectDocument.trackChildConfigDocument(configDocument)
      configDocument.delegate = projectDocument
      configDocument.makeWindowControllers()
      configDocument.showWindows()
      return
    } catch let e as NSError {
      errorInfo = e.localizedDescription
    } catch {
      errorInfo = "Unexpected exception"
    }

    let fmt = NSLocalizedString("Error_GeneralCriticalFailure",
                                comment: "A general, critical failure without a more fitting descriptive message. Details are provided as %1$@.")
    projectDocument.error(String(format: fmt, errorInfo))
  }


  /// Verifies that the project's Bazel URL seems valid, forcing the user to select a valid path if
  /// necessary and invoking the given retryHandler once they've finished selection.
  /// Returns true if Bazel is already valid, false if the Bazel picker is being shown.
  private func requireValidBazel(retryHandler: () -> Void) -> Bool {
    let projectDocument = representedObject as! TulsiProjectDocument
    guard let bazelURL = projectDocument.bazelURL,
              bazelPath = bazelURL.path
        where NSFileManager.defaultManager().isExecutableFileAtPath(bazelPath) else {
      BazelSelectionPanel.beginSheetModalBazelSelectionPanelForWindow(self.view.window!,
                                                                      document: projectDocument) {
        (bazelURL: NSURL?) in
          if bazelURL != nil {
            retryHandler()
          }
      }
      return false
    }
    return true
  }

  private func didClickRemoveSelectedConfigs(sender: AnyObject?) {
    let document = representedObject as! TulsiProjectDocument
    let selectedConfigNames = configArrayController.selectedObjects as! [String]
    document.deleteConfigsNamed(selectedConfigNames)
  }
}


/// Transformer that returns true if the value is equal to 1.
final class IsOneValueTransformer : NSValueTransformer {
  override class func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override class func allowsReverseTransformation() -> Bool  {
    return false
  }

  override func transformedValue(value: AnyObject?) -> AnyObject? {
    if let intValue = value as? Int where intValue == 1 {
      return true
    }
    return false
  }
}
