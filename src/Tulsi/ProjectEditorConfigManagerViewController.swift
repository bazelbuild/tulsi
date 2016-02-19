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

    let generatorController = XcodeProjectGenerationProgressViewController()
    generatorController.representedObject = representedObject
    presentViewControllerAsSheet(generatorController)

    generatorController.generateProjectForConfigName(configName) { (projectURL: NSURL?) in
      self.dismissViewController(generatorController)
      if let projectURL = projectURL {
        NSWorkspace.sharedWorkspace().openURL(projectURL)
      }
    }
  }

  @IBAction func didDoubleClickConfigRow(sender: NSTableView) {
    let projectDocument = representedObject as! TulsiProjectDocument
    let clickedRow = sender.clickedRow
    guard clickedRow >= 0,
        let configName = configArrayController.arrangedObjects[clickedRow] as? String else {
      return
    }

    let errorInfo: String
    do {
      let configDocument = try projectDocument.loadConfigDocumentNamed(configName)
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
      let configDocument = try TulsiGeneratorConfigDocument.makeDocumentWithProjectRuleEntries(projectDocument.ruleEntries,
                                                                                               optionSet: optionSet,
                                                                                               projectName: projectName,
                                                                                               saveFolderURL: generatorConfigFolderURL,
                                                                                               infoExtractor: projectDocument.infoExtractor,
                                                                                               messageLogger: projectDocument,
                                                                                               additionalFilePaths: additionalFilePaths,
                                                                                               bazelURL: projectDocument.bazelURL)
      projectDocument.trackChildConfigDocument(configDocument)
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

  private func didClickRemoveSelectedConfigs(sender: AnyObject?) {
    let document = representedObject as! TulsiProjectDocument
    let selectedConfigNames = configArrayController.selectedObjects as! [String]
    document.deleteConfigsNamed(selectedConfigNames)
  }
}
