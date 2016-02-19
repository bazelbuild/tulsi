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


final class TulsiGeneratorConfigDocument: NSDocument,
                                          NSWindowDelegate,
                                          OptionsEditorModelProtocol,
                                          NewGeneratorConfigViewControllerDelegate,
                                          MessageLoggerProtocol {

  /// The type for Tulsi generator config documents.
  // Keep in sync with Info.plist.
  static let FileType = "com.google.tulsi.generatorconfig"

  /// The type for Tulsi generator per-user config documents.
  static let PerUserFileType = "com.google.tulsi.generatorconfig.user"

  /// Whether or not the document is currently performing a long running operation.
  dynamic var processing: Bool = false

  // Whether or not this object has any rule entries (used to display a spinner while the parent
  // TulsiProjectDocument project is loading).
  private var hasRuleEntries = false {
    didSet {
      updateProcessingState()
    }
  }

  // The number of tasks that need to complete before processing is finished.
  private var processingTaskCount = 0 {
    didSet {
      assert(NSThread.isMainThread(), "Must be mutated on the main thread")
      assert(processingTaskCount >= 0, "Processing task count may never be negative")
      updateProcessingState()
    }
  }

  // The folder into which the generated Xcode project will be written.
  dynamic var outputFolderURL: NSURL? = nil

  /// The set of all RuleEntry instances from which the user can select build targets.
  // Maps the given RuleEntry instances to UIRuleEntry's, preserving this config's selections if
  // possible.
  var projectRuleEntries = [RuleEntry]() {
    didSet {
      let selectedEntryLabels = Set<String>(selectedUIRuleEntries.map({ $0.fullLabel }))
      uiRuleEntries = projectRuleEntries.map() {
        let entry = UIRuleEntry(ruleEntry: $0)
        entry.selected = selectedEntryLabels.contains(entry.fullLabel)
        return entry
      }
      hasRuleEntries = !projectRuleEntries.isEmpty
    }
  }

  /// The UIRuleEntry instances that are acted on by the associated UI.
  dynamic var uiRuleEntries = [UIRuleEntry]() {
    willSet {
      stopObservingRuleEntries()

      for entry in newValue {
        entry.addObserver(self,
                          forKeyPath: "selected",
                          options: .New,
                          context: &TulsiGeneratorConfigDocument.KVOContext)
      }
    }
  }

  /// The currently selected UIRuleEntry's. Computed in linear time.
  var selectedUIRuleEntries: [UIRuleEntry] {
    return uiRuleEntries.filter { $0.selected }
  }

  private var selectedRuleEntries: [RuleEntry] {
    return selectedUIRuleEntries.map { $0.ruleEntry }
  }

  /// The number of selected items in ruleEntries.
  dynamic var selectedRuleEntryCount: Int = 0 {
    didSet {
      updateChangeCount(.ChangeDone)  // TODO(abaire): Implement undo functionality.
    }
  }

  /// Array of source rules. One per dependency of selectedUIRuleEntries.
  private var sourceUIRuleEntries: [UIRuleEntry] = []

  private var selectedSourceUIRuleEntries: [UIRuleEntry] {
    return sourceUIRuleEntries.filter { $0.selected }
  }

  private var selectedSourceRuleEntries: [RuleEntry] {
    return selectedSourceUIRuleEntries.map { $0.ruleEntry }
  }

  // The display name for this config.
  var configName: String? = nil {
    didSet {
      setDisplayName(configName)
      updateChangeCount(.ChangeDone)  // TODO(abaire): Implement undo functionality.
    }
  }

  // Information inherited from the project.
  var bazelURL: NSURL? = nil
  var additionalFilePaths: [String]? = nil
  var saveFolderURL: NSURL! = nil
  var infoExtractor: TulsiProjectInfoExtractor! = nil
  var messageLogger: MessageLoggerProtocol? = nil

  // Labels from a serialized config that must be resolved in order to fully load this config.
  private var buildTargetLabels: [String]? = nil
  private var sourceTargetLabels: [String]? = nil

  // Closure to be invoked when a save operation completes.
  private var saveCompletionHandler: ((canceled: Bool, error: NSError?) -> Void)? = nil

  private static var KVOContext: Int = 0

  static func isGeneratorConfigFilename(filename: String) -> Bool {
    return (filename as NSString).pathExtension == TulsiGeneratorConfig.FileExtension
  }

  /// Builds a new TulsiGeneratorConfigDocument from the given data and adds it to the document
  /// controller.
  static func makeDocumentWithProjectRuleEntries(ruleEntries: [RuleEntry],
                                                 optionSet: TulsiOptionSet,
                                                 projectName: String,
                                                 saveFolderURL: NSURL,
                                                 infoExtractor: TulsiProjectInfoExtractor,
                                                 messageLogger: MessageLoggerProtocol,
                                                 additionalFilePaths: [String]? = nil,
                                                 bazelURL: NSURL? = nil,
                                                 name: String? = nil) throws -> TulsiGeneratorConfigDocument {
    let documentController = NSDocumentController.sharedDocumentController()
    guard let doc = try documentController.makeUntitledDocumentOfType(TulsiGeneratorConfigDocument.FileType) as? TulsiGeneratorConfigDocument else {
      throw TulsiError(errorMessage: "Document for type \(TulsiGeneratorConfigDocument.FileType) was not the expected type.")
    }

    doc.projectRuleEntries = ruleEntries
    doc.additionalFilePaths = additionalFilePaths
    doc.optionSet = optionSet
    doc.projectName = projectName
    doc.saveFolderURL = saveFolderURL
    doc.infoExtractor = infoExtractor
    doc.messageLogger = messageLogger
    doc.bazelURL = bazelURL
    doc.configName = name

    documentController.addDocument(doc)
    return doc
  }

  /// Builds a TulsiGeneratorConfigDocument by loading data from the given persisted config and adds
  /// it to the document controller.
  static func makeDocumentWithContentsOfURL(url: NSURL,
                                            infoExtractor: TulsiProjectInfoExtractor,
                                            messageLogger: MessageLoggerProtocol,
                                            bazelURL: NSURL? = nil) throws -> TulsiGeneratorConfigDocument {
    let documentController = NSDocumentController.sharedDocumentController()
    guard let doc = try documentController.makeDocumentWithContentsOfURL(url,
                                                                         ofType: TulsiGeneratorConfigDocument.FileType) as? TulsiGeneratorConfigDocument else {
      throw TulsiError(errorMessage: "Document for type \(TulsiGeneratorConfigDocument.FileType) was not the expected type.")
    }

    doc.infoExtractor = infoExtractor
    doc.messageLogger = messageLogger
    doc.bazelURL = bazelURL

    // Resolve labels to UIRuleEntries, warning on any failures.
    func warnUnresolvedLabels(labels: [String]) {
      let fmt = NSLocalizedString("Warning_LabelResolutionFailed",
                                  comment: "A non-critical failure to restore some Bazel labels when loading a document. Details are provided as %1$@.")
      doc.warning(String(format: fmt, labels))
    }

    doc.resolveLabelReferences()
    if let concreteBuildTargetLabels = doc.buildTargetLabels {
      warnUnresolvedLabels(concreteBuildTargetLabels)
    }
    if let concreteSourceTargetLabels = doc.sourceTargetLabels {
      warnUnresolvedLabels(concreteSourceTargetLabels)
    }

    return doc
  }

  static func urlForConfigNamed(name: String, inFolderURL folderURL: NSURL?) -> NSURL? {
    let filename = TulsiGeneratorConfig.sanitizeFilename("\(name).\(TulsiGeneratorConfig.FileExtension)")
    return folderURL?.URLByAppendingPathComponent(filename)
  }

  deinit {
    unbind("projectRuleEntries")
    stopObservingRuleEntries()
    assert(saveCompletionHandler == nil)
  }

  /// Saves the document, invoking the given completion handler on completion/cancelation.
  func save(completionHandler: ((Bool, NSError?) -> Void)) {
    assert(saveCompletionHandler == nil)
    saveCompletionHandler = completionHandler
    saveDocument(nil)
  }

  override func makeWindowControllers() {
    let storyboard = NSStoryboard(name: "Main", bundle: nil)
    let windowController = storyboard.instantiateControllerWithIdentifier("TulsiGeneratorConfigDocumentWindow") as! NSWindowController
    windowController.contentViewController?.representedObject = self
    // TODO(abaire): Consider supporting restoration of config subwindows.
    windowController.window?.restorable = false
    addWindowController(windowController)
  }

  override func saveToURL(url: NSURL,
                          ofType typeName: String,
                          forSaveOperation saveOperation: NSSaveOperationType,
                          completionHandler: (NSError?) -> Void) {
    super.saveToURL(url,
                    ofType: typeName,
                    forSaveOperation: saveOperation) { (error: NSError?) in
      if let error = error {
        let fmt = NSLocalizedString("Error_ConfigSaveFailed",
                                    comment: "Error when a TulsiGeneratorConfig failed to save. Details are provided as %1$@.")
        self.error(String(format: fmt, error.localizedDescription))
      }

      completionHandler(error)

      if let concreteCompletionHandler = self.saveCompletionHandler {
        concreteCompletionHandler(canceled: false, error: error)
        self.saveCompletionHandler = nil
      }
    }
  }

  override func dataOfType(typeName: String) throws -> NSData {
    guard let config = makeConfig() else {
      throw TulsiError(code: .ConfigNotSaveable)
    }
    if typeName == TulsiGeneratorConfigDocument.FileType {
      return try config.save()
    } else if typeName == TulsiGeneratorConfigDocument.PerUserFileType {
      if let userSettings = try config.savePerUserSettings() {
        return userSettings
      }
      return NSData()
    }
    throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: nil)
  }

  override func readFromURL(url: NSURL, ofType typeName: String) throws {
    guard let filename = url.lastPathComponent else {
      throw TulsiError(code: .ConfigNotLoadable)
    }
    configName = (filename as NSString).stringByDeletingPathExtension
    let config = try TulsiGeneratorConfig.load(url)

    projectName = config.projectName
    buildTargetLabels = config.buildTargetLabels
    sourceTargetLabels = config.sourceTargetLabels
    additionalFilePaths = config.additionalFilePaths
    optionSet = config.options
    bazelURL = config.bazelURL
  }

  override class func autosavesInPlace() -> Bool {
    // TODO(abaire): Enable autosave when undo behavior is implemented.
    return false
  }

  override func prepareSavePanel(panel: NSSavePanel) -> Bool {
    // As configs are always relative to some other object, the NSSavePanel is never appropriate.
    assertionFailure("Save panel should never be invoked.")
    return false
  }

  override func observeValueForKeyPath(keyPath: String?,
                              ofObject object: AnyObject?,
                              change: [String : AnyObject]?,
                              context: UnsafeMutablePointer<Void>) {
    if context != &TulsiGeneratorConfigDocument.KVOContext {
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
    let selectedRuleLabels = Set<String>(selectedSourceUIRuleEntries.map({ $0.fullLabel }))
    sourceUIRuleEntries.removeAll()
    processingTaskStarted()

    infoExtractor.extractSourceRulesForRuleEntries(selectedRuleEntries) {
      (sourceRuleEntries: [RuleEntry]) -> Void in
        defer { self.processingTaskFinished() }
        self.sourceUIRuleEntries = sourceRuleEntries.map {
          let entry = UIRuleEntry(ruleEntry: $0)
          entry.selected = selectedRuleLabels.contains(entry.fullLabel)
          return entry
        }
        callback(self.sourceUIRuleEntries)
    }
  }

  @IBAction override func saveDocument(sender: AnyObject?) {
    if fileURL != nil {
      super.saveDocument(sender)
      return
    }
    saveDocumentAs(sender)
  }

  @IBAction override func saveDocumentAs(sender: AnyObject?) {
    let newConfigSheet = NewGeneratorConfigViewController()
    newConfigSheet.configName = configName
    newConfigSheet.delegate = self
    windowForSheet?.contentViewController?.presentViewControllerAsSheet(newConfigSheet)
  }

  /// Generates an Xcode project, returning an NSURL to the project on success.
  func generateXcodeProjectInFolder(outputFolderURL: NSURL,
                                    withWorkspaceRootURL workspaceRootURL: NSURL) -> NSURL? {
    assert(!NSThread.isMainThread(), "Must not be called from the main thread")

    guard let config = makeConfig() else {
      let fmt = NSLocalizedString("Error_GeneralProjectGenerationFailure",
                                  comment: "A general, critical failure during project generation. Details are provided as %1$@.")
      self.error(String(format: fmt, "Generator config is not fully populated."))
      return nil
    }

    let projectGenerator = TulsiXcodeProjectGenerator(workspaceRootURL: workspaceRootURL,
                                                      config: config,
                                                      messageLogger: messageLogger)
    let errorInfo: String
    do {
      return try projectGenerator.generateXcodeProjectInFolder(outputFolderURL)
    } catch TulsiXcodeProjectGenerator.Error.UnsupportedTargetType(let targetType) {
      errorInfo = "Unsupported target type: \(targetType)"
    } catch TulsiXcodeProjectGenerator.Error.SerializationFailed(let details) {
      errorInfo = "General failure: \(details)"
    } catch _ {
      errorInfo = "Unexpected failure"
    }

    let fmt = NSLocalizedString("Error_GeneralProjectGenerationFailure",
                                comment: "A general, critical failure during project generation. Details are provided as %1$@.")
    let errorMessage = String(format: fmt, errorInfo)
    self.error(errorMessage)
    return nil
  }

  // MARK: - NSWindowDelegate

  func windowWillClose(notification: NSNotification) {
    stopObservingRuleEntries()
  }

  // MARK: - OptionsEditorModelProtocol

  var projectName: String? = nil

  var optionSet: TulsiOptionSet? = TulsiOptionSet()

  var optionsTargetUIRuleEntries: [UIRuleEntry]? {
    return selectedUIRuleEntries
  }

  // MARK: - NSUserInterfaceValidations

  override func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
    switch item.action() {
      case Selector("saveDocument:"):
        return true

      case Selector("saveDocumentAs:"):
        return windowForSheet?.contentViewController != nil

      // Unsupported actions.
      case Selector("duplicateDocument:"):
        return false
      case Selector("renameDocument:"):
        return false
      case Selector("moveDocument:"):
        return false

      default:
        print("Unhandled menu action: \(item.action())")
    }
    return false
  }

  // MARK: - NewGeneratorConfigViewControllerDelegate

  func viewController(vc: NewGeneratorConfigViewController,
                      didCompleteWithReason reason: NewGeneratorConfigViewController.CompletionReason) {
    windowForSheet?.contentViewController?.dismissViewController(vc)
    guard reason == .Create else {
      if let completionHandler = saveCompletionHandler {
        completionHandler(canceled: true, error: nil)
        saveCompletionHandler = nil
      }
      return
    }

    configName = vc.configName!
    guard let targetURL = TulsiGeneratorConfigDocument.urlForConfigNamed(configName!,
                                                                         inFolderURL: saveFolderURL) else {
      if let completionHandler = saveCompletionHandler {
        completionHandler(canceled: false, error: TulsiError(code: .ConfigNotSaveable))
        saveCompletionHandler = nil
      }
      return
    }

    saveToURL(targetURL,
              ofType: TulsiGeneratorConfigDocument.FileType,
              forSaveOperation: .SaveOperation) { (error: NSError?) in
      // Note that saveToURL handles invocation/clearning of saveCompletionHandler.
    }
  }

  // MARK: - MessageLoggerProtocol

  func warning(message: String) {
    messageLogger?.warning(message)
  }

  func error(message: String) {
    messageLogger?.error(message)
  }

  func info(message: String) {
    messageLogger?.info(message)
  }

  // MARK: - Private methods

  private func processingTaskStarted() {
    NSThread.doOnMainThread() { self.processingTaskCount += 1 }
  }

  private func processingTaskFinished() {
    NSThread.doOnMainThread() { self.processingTaskCount -= 1 }
  }

  private func updateProcessingState() {
    processing = processingTaskCount > 0 || !hasRuleEntries
  }

  private func stopObservingRuleEntries() {
    for entry in uiRuleEntries {
      entry.removeObserver(self, forKeyPath: "selected", context: &TulsiGeneratorConfigDocument.KVOContext)
    }
  }

  private func makeConfig() -> TulsiGeneratorConfig? {
    guard let concreteProjectName = projectName,
              concreteOptionSet = optionSet else {
      return nil
    }

    return TulsiGeneratorConfig(projectName: concreteProjectName,
                                buildTargets: selectedRuleEntries,
                                sourceTargets: selectedSourceRuleEntries,
                                additionalFilePaths: additionalFilePaths,
                                options: concreteOptionSet,
                                bazelURL: bazelURL)
  }

  /// Resolves buildTargetLabels and sourceTargetLabels, leaving them populated with any labels that
  /// failed to be resolved.
  private func resolveLabelReferences() {
    var labels = [String]()
    if let concreteBuildTargetLabels = buildTargetLabels {
      labels += concreteBuildTargetLabels
    }
    if let concreteSourceTargetLabels = sourceTargetLabels {
      labels += concreteSourceTargetLabels
    }

    if labels.isEmpty {
      buildTargetLabels = nil
      sourceTargetLabels = nil
      return
    }

    let resolvedLabels = infoExtractor.ruleEntriesForLabels(labels)

    // Converts the given array of labels to an array of selected UIRuleEntry instances, adding any
    // labels that failed to resolve to the unresolvedLabels set.
    func ruleEntriesForLabels(labels: [String]) -> ([UIRuleEntry], Set<String>) {
      var unresolvedLabels = Set<String>()
      var ruleEntries = [UIRuleEntry]()
      for label in labels {
        guard let entry = resolvedLabels[label] else {
          unresolvedLabels.insert(label)
          continue
        }
        let uiRuleEntry = UIRuleEntry(ruleEntry: entry)
        uiRuleEntry.selected = true
        ruleEntries.append(uiRuleEntry)
      }
      return (ruleEntries, unresolvedLabels)
    }

    if let concreteBuildTargetLabels = buildTargetLabels {
      let (ruleEntries, unresolvedLabels) = ruleEntriesForLabels(concreteBuildTargetLabels)
      uiRuleEntries = ruleEntries
      buildTargetLabels = unresolvedLabels.isEmpty ? nil : [String](unresolvedLabels)
      selectedRuleEntryCount = selectedRuleEntries.count
    }

    if let concreteSourceTargetLabels = sourceTargetLabels {
      let (ruleEntries, unresolvedLabels) = ruleEntriesForLabels(concreteSourceTargetLabels)
      sourceUIRuleEntries = ruleEntries
      sourceTargetLabels = unresolvedLabels.isEmpty ? nil : [String](unresolvedLabels)
    }
  }
}
