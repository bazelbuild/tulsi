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

  /// Indices into the Add/Remove/Action SegmentedControl (as built by Interface Builder).
  private enum SegmentedControlButtonIndex: Int {
    case add = 0
    case remove = 1
    case action = 2
  }

  // Context indicating that a new config should be added after a document save completes.
  private static var PostSaveContextAddConfig = 0

  @IBOutlet var configArrayController: NSArrayController!
  @IBOutlet weak var addRemoveSegmentedControl: NSSegmentedControl!
  @IBOutlet var generateButton: NSButton!

  @objc dynamic var numBazelPackages: Int = 0 {
    didSet {
      let enableAddButton = numBazelPackages > 0 && infoExtractorInitialized
      addRemoveSegmentedControl.setEnabled(enableAddButton,
                                           forSegment: SegmentedControlButtonIndex.add.rawValue)
    }
  }

  // Whether or not the Tulsi project document is still initializing components required for
  // generation.
  @objc dynamic var infoExtractorInitialized: Bool = false {
    didSet {
      updateButtonsState()
      Thread.doOnMainQueue() {
        self.generateButton.title = self.infoExtractorInitialized ? "Generate" : "Initializing..."
      }
    }
  }

  @objc dynamic var numSelectedConfigs: Int = 0 {
    didSet {
      updateButtonsState()
    }
  }

  override var representedObject: Any? {
    didSet {
      if let concreteRepresentedObject = representedObject {
        bind(NSBindingName(rawValue: "numBazelPackages"),
             to: concreteRepresentedObject,
             withKeyPath: "bazelPackages.@count",
             options: nil)
        bind(NSBindingName(rawValue: "infoExtractorInitialized"),
             to: concreteRepresentedObject,
             withKeyPath: "infoExtractorInitialized",
             options: nil)
      }
    }
  }

  deinit {
    NSObject.unbind(NSBindingName(rawValue: "infoExtractorInitialized"))
    NSObject.unbind(NSBindingName(rawValue: "numBazelPackages"))
    NSObject.unbind(NSBindingName(rawValue: "numSelectedConfigs"))
  }

  override func loadView() {
    ValueTransformer.setValueTransformer(IsOneValueTransformer(),
                                           forName: NSValueTransformerName(rawValue: "IsOneValueTransformer"))
    super.loadView()
    bind(NSBindingName(rawValue: "numSelectedConfigs"),
         to: configArrayController!,
         withKeyPath: "selectedObjects.@count",
         options: nil)
    self.generateButton.keyEquivalent = "\r"
  }

  // Toggle the state of the buttons depending on the current selection as well as if any required
  // components are still being initialized.
  func updateButtonsState() {
    Thread.doOnMainQueue() {
      let numSelectedConfigs = self.numSelectedConfigs
      let infoExtractorInitialized = self.infoExtractorInitialized
      self.addRemoveSegmentedControl.setEnabled(self.numBazelPackages > 0 && infoExtractorInitialized,
                                           forSegment: SegmentedControlButtonIndex.add.rawValue)
      self.addRemoveSegmentedControl.setEnabled(numSelectedConfigs > 0 && infoExtractorInitialized,
                                           forSegment: SegmentedControlButtonIndex.remove.rawValue)
      self.addRemoveSegmentedControl.setEnabled(numSelectedConfigs == 1 && infoExtractorInitialized,
                                           forSegment: SegmentedControlButtonIndex.action.rawValue)
      self.generateButton.isEnabled = (numSelectedConfigs == 1 && infoExtractorInitialized)
    }
  }

  @IBAction func didClickAddRemoveSegmentedControl(_ sender: NSSegmentedCell) {
    // Ignore mouse up messages.
    if sender.selectedSegment < 0 { return }

    guard let button = SegmentedControlButtonIndex(rawValue: sender.selectedSegment) else {
      assertionFailure("Unexpected add/remove button index \(sender.selectedSegment)")
      return
    }

    switch button {
      case .add:
        didClickAddConfig(sender)
      case .remove:
        didClickRemoveSelectedConfigs(sender)
      case .action:
        didClickAction(sender)
    }
  }

  @IBAction func doGenerate(_ sender: AnyObject?) {
    guard let configName = configArrayController.selectedObjects.first as? String else { return }
    guard requireValidBazel({ self.doGenerate(sender) }) else { return }

    let generatorController = XcodeProjectGenerationProgressViewController()
    generatorController.representedObject = representedObject
    presentAsSheet(generatorController)

    let projectDocument = representedObject as! TulsiProjectDocument
    generatorController.generateProjectForConfigName(configName) { (projectURL: URL?) in
      self.dismiss(generatorController)
      if let projectURL = projectURL {
        LogMessage.postInfo("Opening generated project in Xcode",
                            context: projectDocument.projectName)
        NSWorkspace.shared.open(projectURL)
      }
    }
  }

  @IBAction func didDoubleClickConfigRow(_ sender: NSTableView) {
    guard requireValidBazel({ self.didDoubleClickConfigRow(sender) }) else { return }
    let clickedRow = sender.clickedRow
    guard clickedRow >= 0 else { return }
    let configName = (configArrayController.arrangedObjects as! [String])[clickedRow]
    editConfigNamed(configName)
  }

  @objc func document(_ doc:NSDocument, didSave:Bool, contextInfo: UnsafeMutableRawPointer) {
    if contextInfo == &ProjectEditorConfigManagerViewController.PostSaveContextAddConfig {
      if didSave {
        didClickAddConfig(nil)
      }
    }
  }

  // MARK: - Private methods

  private func didClickAddConfig(_ sender: AnyObject?) {
    guard requireValidBazel({ self.didClickAddConfig(sender) }) else { return }

    let projectDocument = representedObject as! TulsiProjectDocument

    // Adding a config to a project with no bazel packages is disallowed.
    guard let bazelPackages = projectDocument.bazelPackages, !bazelPackages.isEmpty else {
      // This should be prevented by the UI, so spawn a bug message and beep.
      LogMessage.postInfo("Bug: Add config invoked on a project with no packages.")
      NSSound.beep()
      return
    }

    let errorInfo: String
    do {
      let additionalFilePaths = bazelPackages.map() { "\($0)/BUILD" }
      guard let projectName = projectDocument.projectName,
                let generatorConfigFolderURL = projectDocument.generatorConfigFolderURL else {
        projectDocument.save(withDelegate: self,
                             didSave: #selector(ProjectEditorConfigManagerViewController.document(_:didSave:contextInfo:)),
                             contextInfo: &ProjectEditorConfigManagerViewController.PostSaveContextAddConfig)
        return
      }
      let optionSet = projectDocument.optionSet ?? TulsiOptionSet()
      let configDocument = try TulsiGeneratorConfigDocument.makeDocumentWithProjectRuleEntries(projectDocument.ruleInfos,
                                                                                               optionSet: optionSet,
                                                                                               projectName: projectName,
                                                                                               saveFolderURL: generatorConfigFolderURL,
                                                                                               infoExtractor: projectDocument.infoExtractor,
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

    let msg = NSLocalizedString("Error_GeneralCriticalFailure",
                                comment: "A general, critical failure without a more fitting descriptive message.")
    LogMessage.postError(msg, details: errorInfo, context: projectDocument.projectName)
    LogMessage.displayPendingErrors()
  }


  /// Verifies that the project's Bazel URL seems valid, forcing the user to select a valid path if
  /// necessary and invoking the given retryHandler once they've finished selection.
  /// Returns true if Bazel is already valid, false if the Bazel picker is being shown.
  private func requireValidBazel(_ retryHandler: @escaping () -> Void) -> Bool {
    let projectDocument = representedObject as! TulsiProjectDocument
    guard let bazelURL = projectDocument.bazelURL,
              FileManager.default.isExecutableFile(atPath: bazelURL.path) else {
      BazelSelectionPanel.beginSheetModalBazelSelectionPanelForWindow(self.view.window!,
                                                                      document: projectDocument) {
        (bazelURL: URL?) in
          if bazelURL != nil {
            retryHandler()
          }
      }
      return false
    }
    return true
  }

  private func didClickRemoveSelectedConfigs(_ sender: AnyObject?) {
    let document = representedObject as! TulsiProjectDocument
    let selectedConfigNames = configArrayController.selectedObjects as! [String]
    document.deleteConfigsNamed(selectedConfigNames)
  }

  private func didClickAction(_ sender: AnyObject?) {
    let selectedConfigNames = configArrayController.selectedObjects as! [String]
    if let configName = selectedConfigNames.first {
      editConfigNamed(configName)
    }
  }

  private func editConfigNamed(_ name: String) {
    let projectDocument = representedObject as! TulsiProjectDocument
    let errorInfo: String
    do {
      let configDocument = try projectDocument.loadConfigDocumentNamed(name) { (_) in
        // Nothing in particular has to be done when the config doc is loaded, the editor UI already
        // handles this via the document's processing state.
      }
      configDocument.makeWindowControllers()
      configDocument.showWindows()
      return
    } catch TulsiProjectDocument.DocumentError.noSuchConfig {
      errorInfo = "No URL for config named '\(name)'"
    } catch TulsiProjectDocument.DocumentError.configLoadFailed(let info) {
      errorInfo = info
    } catch TulsiProjectDocument.DocumentError.invalidWorkspace(let info) {
      errorInfo = "Invalid workspace: \(info)"
    } catch {
      errorInfo = "An unexpected exception occurred while loading config named '\(name)'"
    }
    let msg = NSLocalizedString("Error_ConfigLoadFailed",
                                comment: "Error when a TulsiGeneratorConfig failed to be reloaded.")
    LogMessage.postError(msg, details: errorInfo)
    LogMessage.displayPendingErrors()
  }
}


/// Transformer that returns true if the value is equal to 1.
final class IsOneValueTransformer : ValueTransformer {
  override class func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override class func allowsReverseTransformation() -> Bool  {
    return false
  }

  override func transformedValue(_ value: Any?) -> Any? {
    if let intValue = value as? Int, intValue == 1 {
      return true
    }
    return false
  }
}
