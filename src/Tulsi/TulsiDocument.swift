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

final class TulsiDocument: NSDocument, NSWindowDelegate, MessageLoggerProtocol {

  /// Prefix used to access the persisted output folder for a given BUILD file path.
  static let ProjectOutputPathKeyPrefix = "projectOutput_"

  /// The project model.
  var project: TulsiProject! = nil

  /// Whether or not the document is currently performing a long running operation.
  dynamic var processing: Bool = false

  /// The set of Bazel packages associated with this project.
  dynamic var bazelPackages: [String]? {
    set {
      project!.bazelPackages = newValue ?? [String]()
      updateChangeCount(.ChangeDone)  // TODO(abaire): Implement undo functionality.
    }
    get {
      return project?.bazelPackages
    }
  }

  /// Location of the bazel binary.
  dynamic var bazelURL: NSURL? {
    set {
      project.bazel = newValue
      updateChangeCount(.ChangeDone)  // TODO(abaire): Implement undo functionality.
    }
    get {
      return project?.bazel
    }
  }

  /// Binding point for the directory containing the project's WORKSPACE file.
  dynamic var workspaceRootURL: NSURL? {
    get {
      return project?.workspaceRootURL
    }
  }

  private static var KVOContext: Int = 0

  /// Array of user-facing messages, generally output by the Tulsi generator.
  dynamic var messages = [UIMessage]()

  /// One rule per target in the BUILD file.
  dynamic var ruleEntries = [UIRuleEntry]()

  /// The currently selected UIRuleEntry's. Computed in linear time.
  var selectedUIRuleEntries: [UIRuleEntry] {
    return ruleEntries.filter { $0.selected }
  }

  private var selectedRuleEntries: [RuleEntry] {
    return selectedUIRuleEntries.map { $0.ruleEntry }
  }

  /// The number of selected items in ruleEntries.
  dynamic var selectedRuleEntryCount: Int = 0

  /// Array of source rules. One per dependency of the ruleEntries selected by the user.
  private var sourceRuleEntries: [UIRuleEntry] = []

  private var selectedSourceRuleEntries: [RuleEntry] {
    let selectedSourceUIRuleEntries = sourceRuleEntries.filter { $0.selected }
    return selectedSourceUIRuleEntries.map { $0.ruleEntry }
  }

  private var infoExtractor: TulsiProjectInfoExtractor! = nil
  var options: TulsiOptionSet! = nil

  // The folder into which the generated Xcode project will be written.
  dynamic var outputFolderURL: NSURL? = nil {
    didSet {
      if outputFolderURL == nil { return }
      let key = TulsiDocument.ProjectOutputPathKeyPrefix + fileURL!.absoluteString
      NSUserDefaults.standardUserDefaults().setURL(outputFolderURL, forKey: key)
    }
  }

  var defaultOutputFolderURL: NSURL? {
    if let workspaceRoot = project?.workspaceRootURL {
      return workspaceRoot
    }
    return nil
  }

  lazy var bundleExtension: String = {
    let bundle = NSBundle(forClass: self.dynamicType)
    let documentTypes = bundle.infoDictionary!["CFBundleDocumentTypes"] as! [[String: AnyObject]]
    let extensions = documentTypes.first!["CFBundleTypeExtensions"] as! [String]
    return extensions.first!
  }()

  deinit {
    stopObservingRuleEntries()
  }

  func addBUILDFileURL(buildFile: NSURL) -> Bool {
    guard let package = packageForBUILDFile(buildFile) else {
      return false
    }
    bazelPackages!.append(package)
    return true
  }

  func createNewProject(projectName: String, workspaceFileURL: NSURL) {
    willChangeValueForKey("bazelURL")
    willChangeValueForKey("bazelPackages")
    willChangeValueForKey("workspaceRootURL")

    // Default the bundleURL to a sibling of the selected workspace file.
    let bundleName = "\(projectName).\(bundleExtension)"
    let workspaceRootURL = workspaceFileURL.URLByDeletingLastPathComponent!
    let tempProjectBundleURL = workspaceRootURL.URLByAppendingPathComponent(bundleName)

    project = TulsiProject(projectName: projectName,
                           projectBundleURL: tempProjectBundleURL,
                           workspaceRootURL: workspaceRootURL)
    updateChangeCount(.ChangeDone)  // TODO(abaire): Implement undo functionality.

    didChangeValueForKey("bazelURL")
    didChangeValueForKey("bazelPackages")
    didChangeValueForKey("workspaceRootURL")
  }

  override func writeSafelyToURL(url: NSURL,
                                 ofType typeName: String,
                                 forSaveOperation saveOperation: NSSaveOperationType) throws {
    // Ensure that the project's URL is set to the location in which this document is being saved so
    // that relative paths can be set properly.
    project.projectBundleURL = url
    try super.writeSafelyToURL(url, ofType: typeName, forSaveOperation: saveOperation)
  }

  override class func autosavesInPlace() -> Bool {
    return true
  }

  override func prepareSavePanel(panel: NSSavePanel) -> Bool {
    panel.message = NSLocalizedString("Document_SelectTulsiProjectOutputFolderMessage",
                                      comment: "Message to show at the top of the Tulsi project save as panel, explaining what to do.")
    panel.canCreateDirectories = true
    panel.allowedFileTypes = ["com.google.tulsi.project"]
    panel.nameFieldStringValue = project.projectBundleURL.lastPathComponent!
    return true
  }

  override func fileWrapperOfType(typeName: String) throws -> NSFileWrapper {
    let contents = [String: NSFileWrapper]()
    let bundleFileWrapper = NSFileWrapper(directoryWithFileWrappers: contents)
    bundleFileWrapper.addRegularFileWithContents(try project.save(),
                                                 preferredFilename: TulsiProject.ProjectFilename)
    return bundleFileWrapper
  }

  override func readFromFileWrapper(fileWrapper: NSFileWrapper, ofType typeName: String) throws {
    guard let concreteFileURL = fileURL,
              projectFileWrapper = fileWrapper.fileWrappers?[TulsiProject.ProjectFilename],
              fileContents = projectFileWrapper.regularFileContents else {
      return
    }
    project = try TulsiProject(data: fileContents, projectBundleURL: concreteFileURL)
  }

  override func makeWindowControllers() {
    let storyboard = NSStoryboard(name: "Main", bundle: nil)
    let windowController = storyboard.instantiateControllerWithIdentifier("Tulsi Document Window Controller") as! NSWindowController
    let rootViewController = windowController.contentViewController as! RootViewController
    rootViewController.representedObject = self
    addWindowController(windowController)
  }

  func windowWillClose(notification: NSNotification) {
    stopObservingRuleEntries()
  }

  override func willPresentError(error: NSError) -> NSError {
    // Track errors shown to the user for bug reporting purposes.
    self.info("Presented error: \(error)")
    return super.willPresentError(error)
  }

  // Fetches target rule entries from the project's BUILD documents.
  func updateRuleEntries() {
    stopObservingRuleEntries()
    selectedRuleEntryCount = 0
    ruleEntries.removeAll(keepCapacity: true)

    guard let validBazelURL = bazelURL else {
      self.error(NSLocalizedString("Error_NoBazel",
                                   comment: "Critical error message when the Bazel binary cannot be found."))
      return
    }

    self.processing = true
    infoExtractor = TulsiProjectInfoExtractor(bazelURL: validBazelURL,
                                              project: project,
                                              messageLogger: self)
    infoExtractor.extractTargetRules() {
      (updatedRuleEntries: [RuleEntry]) -> Void in
        let updatedRange = Range(start: self.ruleEntries.startIndex, end: self.ruleEntries.endIndex)
        let updatedUIRuleEntries = updatedRuleEntries.map { UIRuleEntry(ruleEntry: $0) }
        self.ruleEntries.replaceRange(updatedRange, with: updatedUIRuleEntries)
        for entry in self.ruleEntries {
          entry.addObserver(self, forKeyPath: "selected", options: .New, context: &TulsiDocument.KVOContext)
        }
        self.processing = false
    }

    options = infoExtractor.createOptionSetForProjectFile(fileURL!)
  }

  override func observeValueForKeyPath(keyPath: String?,
                              ofObject object: AnyObject?,
                              change: [String : AnyObject]?,
                              context: UnsafeMutablePointer<Void>) {
    if context != &TulsiDocument.KVOContext {
      super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
      return
    }
    if keyPath == "selected", let newValue = change?[NSKeyValueChangeNewKey] as? Bool {
      if (newValue) {
        ++selectedRuleEntryCount
      } else {
        --selectedRuleEntryCount
      }
    }
  }

  // Regenerates the sourceRuleEntries array based on the currently selected ruleEntries.
  func updateSourceRuleEntries(callback: ([UIRuleEntry]) -> Void) {
    sourceRuleEntries.removeAll()
    self.processing = true

    infoExtractor.extractSourceRulesForRuleEntries(selectedRuleEntries) {
      (sourceRuleEntries: [RuleEntry]) -> Void in
        self.sourceRuleEntries = sourceRuleEntries.map { UIRuleEntry(ruleEntry: $0) }
        self.processing = false
        callback(self.sourceRuleEntries)
    }
  }

  // Extracts source paths for selected source rules, generates a PBXProject and opens it.
  func generateAndOpenProject() {
    self.processing = true
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)) {
      let additionalFiles: [String]
      if let bazelPackages = self.bazelPackages {
        additionalFiles = bazelPackages.map() { "\($0)/BUILD" }
      } else {
        additionalFiles = []
      }
      self.generateConfigWithAdditionalFiles(additionalFiles)
    }
  }

  // MARK: - MessageLoggerProtocol

  func warning(message: String) {
    #if DEBUG
    print("W: \(message)")
    #endif

    messages.append(UIMessage(text: message, type: .Warning))
  }

  func error(message: String) {
    #if DEBUG
    print("E: \(message)")
    #endif

    messages.append(UIMessage(text: message, type: .Error))
    // TODO(abaire): Implement better error handling, allowing recovery of a good state.
    let alert = NSAlert()
    alert.messageText = "A fatal error occurred. Please check the message window and file a bug " +
        "if appropriate. You should restart Tulsi, but if you're feeling lucky you could " +
        "navigate back one step and retry this one."
    alert.informativeText = "TODO(abaire): finish error handling."
    alert.alertStyle = .CriticalAlertStyle
    alert.runModal()
  }

  func info(message: String) {
    #if DEBUG
    print("I: \(message)")
    #endif

    messages.append(UIMessage(text: message, type: .Info))
  }

  // MARK: - Private methods

  private func generateConfigWithAdditionalFiles(files: [String]?) {
    guard let concreteWorkspaceRootURL = workspaceRootURL else {
      self.error(NSLocalizedString("Error_BadWorkspace",
                                   comment: "General error when project does not have a valid Bazel workspace."))
      return
    }
    guard let concreteOutputFolderURL = outputFolderURL else {
      // This should never actually happen and indicates an unexpected path through the UI.
      self.error(NSLocalizedString("Error_NoOutputFolder",
                                   comment: "Error for a save attempt without a valid target output folder"))
      return
    }

    let config = TulsiGeneratorConfig(projectName: project.projectName,
                                      buildTargets: selectedRuleEntries,
                                      sourceTargets: selectedSourceRuleEntries,
                                      additionalFilePaths: files,
                                      options: options,
                                      bazelURL: bazelURL!)
    // TODO(abaire): Refactor the UI and write out the config before kicking off generation.
    let projectGenerator = TulsiXcodeProjectGenerator(workspaceRootURL: concreteWorkspaceRootURL,
                                                      config: config,
                                                      messageLogger: self)
    // Resolve source file paths.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)) {
      defer { self.processing = false }

      let errorData: String?
      do {
        let projectURL = try projectGenerator.generateXcodeProjectInFolder(concreteOutputFolderURL)
        NSWorkspace.sharedWorkspace().openURL(projectURL)
        errorData = nil
      } catch TulsiXcodeProjectGenerator.Error.UnsupportedTargetType(let targetType) {
        errorData = "Unsupported target type: \(targetType)"
      } catch TulsiXcodeProjectGenerator.Error.SerializationFailed(let details) {
        errorData = "General failure: \(details)"
      } catch _ {
        errorData = "Unexpected failure"
      }
      if let concreteErrorData = errorData {
        let fmt = NSLocalizedString("Error_GeneralProjectGenerationFailure",
                                    comment: "A general, critical failure during project generation. Details are provided as %1$@.")
        let errorMessage = String(format: fmt, concreteErrorData)
        dispatch_async(dispatch_get_main_queue()) {
          self.error(errorMessage)
        }
      }
    }
  }

  private func stopObservingRuleEntries() {
    for entry in ruleEntries {
      entry.removeObserver(self, forKeyPath: "selected", context: &TulsiDocument.KVOContext)
    }
  }

  private func packageForBUILDFile(buildFile: NSURL) -> String? {
    guard let packageURL = buildFile.URLByDeletingLastPathComponent else {
      return nil
    }

    // If the relative path is a child of the workspace root return it.
    if let relativePath = project.workspaceRelativePathForURL(packageURL)
        where !relativePath.hasPrefix("/") && !relativePath.hasPrefix("..") {
      return relativePath
    }
    return nil
  }
}
