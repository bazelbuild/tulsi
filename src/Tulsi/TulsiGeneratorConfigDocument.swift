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


protocol TulsiGeneratorConfigDocumentDelegate: class {
  /// Called when the TulsiGeneratorConfigDocument is saved successfully with a new name.
  func didNameTulsiGeneratorConfigDocument(document: TulsiGeneratorConfigDocument)
}


/// Document encapsulating a Tulsi generator configuration.
final class TulsiGeneratorConfigDocument: NSDocument,
                                          NSWindowDelegate,
                                          OptionsEditorModelProtocol,
                                          NewGeneratorConfigViewControllerDelegate,
                                          MessageLoggerProtocol,
                                          MessageLogProtocol {

  /// Status of an Xcode project generation action.
  enum GenerationResult {
    /// Generation succeeded. The associated URL points at the generated Xcode project.
    case Success(NSURL)
    /// Generation failed. The associated String provides error info.
    case Failure(String)
  }

  /// The type for Tulsi generator config documents.
  // Keep in sync with Info.plist.
  static let FileType = "com.google.tulsi.generatorconfig"

  /// The type for Tulsi generator per-user config documents.
  static let PerUserFileType = "com.google.tulsi.generatorconfig.user"

  weak var delegate: TulsiGeneratorConfigDocumentDelegate? = nil

  /// Whether or not the document is currently performing a long running operation.
  dynamic var processing: Bool = false

  // The number of tasks that need to complete before processing is finished.
  private var processingTaskCount = 0 {
    didSet {
      assert(NSThread.isMainThread(), "Must be mutated on the main thread")
      assert(processingTaskCount >= 0, "Processing task count may never be negative")
      processing = processingTaskCount > 0
    }
  }

  // The folder into which the generated Xcode project will be written.
  dynamic var outputFolderURL: NSURL? = nil

  /// The set of all RuleInfo instances from which the user can select build targets.
  // Maps the given RuleInfo instances to UIRuleInfo's, preserving this config's selections if
  // possible.
  var projectRuleInfos = [RuleInfo]() {
    didSet {
      let selectedEntryLabels = Set<String>(selectedUIRuleInfos.map({ $0.fullLabel }))
      var uiRuleInfoMap = [BuildLabel: UIRuleInfo]()
      var infosWithLinkages = [UIRuleInfo]()
      uiRuleInfos = projectRuleInfos.map() {
        let info = UIRuleInfo(ruleInfo: $0)
        info.selected = selectedEntryLabels.contains(info.fullLabel)
        uiRuleInfoMap[info.ruleInfo.label] = info
        if !info.ruleInfo.linkedTargetLabels.isEmpty {
          infosWithLinkages.append(info)
        }
        return info
      }

      for info in infosWithLinkages {
        info.resolveLinkages(uiRuleInfoMap)
      }
    }
  }

  /// The UIRuleEntry instances that are acted on by the associated UI.
  dynamic var uiRuleInfos = [UIRuleInfo]() {
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
  var selectedUIRuleInfos: [UIRuleInfo] {
    return uiRuleInfos.filter { $0.selected }
  }

  private var selectedRuleInfos: [RuleInfo] {
    return selectedUIRuleInfos.map { $0.ruleInfo }
  }

  /// The number of selected items in ruleEntries.
  dynamic var selectedRuleInfoCount: Int = 0 {
    didSet {
      updateChangeCount(.ChangeDone)  // TODO(abaire): Implement undo functionality.
    }
  }

  /// Array of paths containing source files related to the selectedUIRuleEntries.
  private var sourcePaths = [UISourcePath]()

  private var selectedSourcePaths: [UISourcePath] {
    return sourcePaths.filter { $0.selected || $0.recursive }
  }

  // The display name for this config.
  var configName: String? = nil {
    didSet {
      setDisplayName(configName)
      updateChangeCount(.ChangeDone)  // TODO(abaire): Implement undo functionality.
    }
  }

  var messages: [UIMessage] {
    if let messageLog = messageLog {
      return messageLog.messages
    }
    return []
  }

  // Information inherited from the project.
  var bazelURL: NSURL? = nil
  var additionalFilePaths: [String]? = nil
  var saveFolderURL: NSURL! = nil
  var infoExtractor: TulsiProjectInfoExtractor! = nil
  var messageLogger: MessageLoggerProtocol? = nil
  var messageLog: MessageLogProtocol? = nil

  override var entireFileLoaded: Bool {
    return _entireFileLoaded
  }
  /// Whether or not this document contains buildTargetLabels that have not been resolved to
  /// RuleInfos. Since the doc is initialized without any buildTargetLabels, it starts fully loaded.
  var _entireFileLoaded = true

  // Labels from a serialized config that must be resolved in order to fully load this config.
  private var buildTargetLabels: [BuildLabel]? = nil

  // Closure to be invoked when a save operation completes.
  private var saveCompletionHandler: ((canceled: Bool, error: NSError?) -> Void)? = nil

  private static var KVOContext: Int = 0

  static func isGeneratorConfigFilename(filename: String) -> Bool {
    return (filename as NSString).pathExtension == TulsiGeneratorConfig.FileExtension
  }

  /// Builds a new TulsiGeneratorConfigDocument from the given data and adds it to the document
  /// controller.
  static func makeDocumentWithProjectRuleEntries(ruleInfos: [RuleInfo],
                                                 optionSet: TulsiOptionSet,
                                                 projectName: String,
                                                 saveFolderURL: NSURL,
                                                 infoExtractor: TulsiProjectInfoExtractor,
                                                 messageLogger: MessageLoggerProtocol,
                                                 messageLog: MessageLogProtocol?,
                                                 additionalFilePaths: [String]? = nil,
                                                 bazelURL: NSURL? = nil,
                                                 name: String? = nil) throws -> TulsiGeneratorConfigDocument {
    let documentController = NSDocumentController.sharedDocumentController()
    guard let doc = try documentController.makeUntitledDocumentOfType(TulsiGeneratorConfigDocument.FileType) as? TulsiGeneratorConfigDocument else {
      throw TulsiError(errorMessage: "Document for type \(TulsiGeneratorConfigDocument.FileType) was not the expected type.")
    }

    doc.projectRuleInfos = ruleInfos
    doc.additionalFilePaths = additionalFilePaths
    doc.optionSet = optionSet
    doc.projectName = projectName
    doc.saveFolderURL = saveFolderURL
    doc.infoExtractor = infoExtractor
    doc.messageLogger = messageLogger
    doc.messageLog = messageLog
    doc.bazelURL = bazelURL
    doc.configName = name

    documentController.addDocument(doc)
    return doc
  }

  /// Builds a TulsiGeneratorConfigDocument by loading data from the given persisted config and adds
  /// it to the document controller. The returned document may be incomplete; completionHandler is
  /// invoked on the main thread when the document is fully loaded.
  static func makeDocumentWithContentsOfURL(url: NSURL,
                                            infoExtractor: TulsiProjectInfoExtractor,
                                            messageLogger: MessageLoggerProtocol,
                                            messageLog: MessageLogProtocol?,
                                            bazelURL: NSURL? = nil,
                                            completionHandler: (TulsiGeneratorConfigDocument -> Void)) throws -> TulsiGeneratorConfigDocument {
    let doc = try makeSparseDocumentWithContentsOfURL(url,
                                                      infoExtractor: infoExtractor,
                                                      messageLogger: messageLogger,
                                                      messageLog: messageLog,
                                                      bazelURL: bazelURL)
    doc.finishLoadingDocument(completionHandler)
    return doc
  }

  /// Builds a skeletal TulsiGeneratorConfigDocument by loading data from the given persisted config
  /// and adds it to the document controller. The returned document will not contain fully resolved
  /// label references and is not suitable for UI display in an editor.
  static func makeSparseDocumentWithContentsOfURL(url: NSURL,
                                                  infoExtractor: TulsiProjectInfoExtractor,
                                                  messageLogger: MessageLoggerProtocol,
                                                  messageLog: MessageLogProtocol?,
                                                  bazelURL: NSURL? = nil) throws -> TulsiGeneratorConfigDocument {
    let documentController = NSDocumentController.sharedDocumentController()
    guard let doc = try documentController.makeDocumentWithContentsOfURL(url,
                                                                         ofType: TulsiGeneratorConfigDocument.FileType) as? TulsiGeneratorConfigDocument else {
      throw TulsiError(errorMessage: "Document for type \(TulsiGeneratorConfigDocument.FileType) was not the expected type.")
    }

    doc.infoExtractor = infoExtractor
    doc.messageLogger = messageLogger
    doc.messageLog = messageLog
    doc.bazelURL = bazelURL
    doc._entireFileLoaded = false
    return doc
  }

  static func urlForConfigNamed(name: String, inFolderURL folderURL: NSURL?) -> NSURL? {
    let filename = TulsiGeneratorConfig.sanitizeFilename("\(name).\(TulsiGeneratorConfig.FileExtension)")
    return folderURL?.URLByAppendingPathComponent(filename)
  }

  /// Generates an Xcode project.
  static func generateXcodeProjectInFolder(outputFolderURL: NSURL,
                                           withGeneratorConfig config: TulsiGeneratorConfig,
                                           workspaceRootURL: NSURL,
                                           messageLogger: MessageLoggerProtocol,
                                           messageLog: MessageLogProtocol?,
                                           projectInfoExtractor: TulsiProjectInfoExtractor? = nil) -> GenerationResult {
    let tulsiVersion: String
    if let cfBundleVersion = NSBundle.mainBundle().infoDictionary?["CFBundleVersion"] as? String {
      tulsiVersion = cfBundleVersion
    } else {
      tulsiVersion = ""
    }
    let projectGenerator = TulsiXcodeProjectGenerator(workspaceRootURL: workspaceRootURL,
                                                      config: config,
                                                      tulsiVersion: tulsiVersion,
                                                      messageLogger: messageLogger)
    let errorInfo: String
    do {
      let url = try projectGenerator.generateXcodeProjectInFolder(outputFolderURL)
      return .Success(url)
    } catch TulsiXcodeProjectGenerator.Error.UnsupportedTargetType(let targetType) {
      errorInfo = "Unsupported target type: \(targetType)"
    } catch TulsiXcodeProjectGenerator.Error.SerializationFailed(let details) {
      errorInfo = "General failure: \(details)"
    } catch _ {
      errorInfo = "Unexpected failure"
    }
    return .Failure(errorInfo)
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

  func revert() throws {
    guard let url = fileURL else { return }
    try revertToContentsOfURL(url, ofType: TulsiGeneratorConfigDocument.FileType)
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
        self.warning(String(format: fmt, error.localizedDescription))

        let alert = NSAlert(error: error)
        alert.runModal()
      }

      completionHandler(error)

      if let concreteCompletionHandler = self.saveCompletionHandler {
        concreteCompletionHandler(canceled: false, error: error)
        self.saveCompletionHandler = nil
      }

      if error == nil {
        self.delegate?.didNameTulsiGeneratorConfigDocument(self)
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
    additionalFilePaths = config.additionalFilePaths
    optionSet = config.options
    bazelURL = config.bazelURL

    sourcePaths = []
    for sourceFilter in config.pathFilters {
      let sourcePath: UISourcePath
      if sourceFilter.hasSuffix("/...") {
        let path = sourceFilter.substringToIndex(sourceFilter.endIndex.advancedBy(-4))
        sourcePath = UISourcePath(path: path, selected: false, recursive: true)
      } else {
        sourcePath = UISourcePath(path: sourceFilter, selected: true, recursive: false)
      }
      sourcePaths.append(sourcePath)
    }
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
        selectedRuleInfoCount += 1
      } else {
        selectedRuleInfoCount -= 1
      }
    }
  }

  // Regenerates the sourcePaths array based on the currently selected ruleEntries.
  func updateSourcePaths(callback: ([UISourcePath]) -> Void) {
    var sourcePathMap = [String: UISourcePath]()
    selectedSourcePaths.forEach() { sourcePathMap[$0.path] = $0 }
    processingTaskStarted()

    let selectedLabels = self.selectedRuleInfos.map() { $0.label }
    let optionSet = self.optionSet!
    NSThread.doOnQOSUserInitiatedThread() {
      let resolvedLabels = self.infoExtractor.ruleEntriesForLabels(selectedLabels,
                                                                   startupOptions: optionSet[.BazelBuildStartupOptionsDebug],
                                                                   buildOptions: optionSet[.BazelBuildOptionsDebug])

      var unresolvedLabels = Set<BuildLabel>()
      var sourceRuleEntries = [RuleEntry]()
      for label in selectedLabels {
        if let entry = resolvedLabels[label] {
          sourceRuleEntries.append(entry)
        } else {
          unresolvedLabels.insert(label)
        }
      }

      if !unresolvedLabels.isEmpty {
        let fmt = NSLocalizedString("Warning_LabelResolutionFailed",
                                    comment: "A non-critical failure to restore some Bazel labels when loading a document. Details are provided as %1$@.")
        self.warning(String(format: fmt, "Missing labels: \(unresolvedLabels.map({$0.description}))"))
      }

      var selectedRuleEntries = [RuleEntry]()
      for selectedRuleInfo in self.selectedRuleInfos {
        if let entry = resolvedLabels[selectedRuleInfo.label] {
          selectedRuleEntries.append(entry)
        }
      }

      var processedEntries = Set<BuildLabel>()

      func extractSourcePaths(ruleEntry: RuleEntry) {
        if processedEntries.contains(ruleEntry.label) {
          // Rules that have already been processed will already have all of their transitive
          // sources captured.
          return
        }
        processedEntries.insert(ruleEntry.label)
        for dep in ruleEntry.dependencies {
          guard let depRuleEntry = resolvedLabels[BuildLabel(dep)] else {
            // Some dependencies are expected to be unresolved, e.g., those that rely on implicit
            // outputs of other rules.
            continue
          }
          extractSourcePaths(depRuleEntry)
        }

        let componentDelimiters = NSCharacterSet(charactersInString: "/:")
        for fileInfo in ruleEntry.projectArtifacts {
          let path = (fileInfo.fullPath as NSString).stringByDeletingLastPathComponent
          if path.isEmpty { continue }

          let pathComponents = path.componentsSeparatedByCharactersInSet(componentDelimiters)
          var cumulativePathComponents = [String]()
          for component in pathComponents {
            cumulativePathComponents.append(component)
            let componentPath = cumulativePathComponents.joinWithSeparator("/")
            if sourcePathMap[componentPath] == nil {
              sourcePathMap[componentPath] = UISourcePath(path: componentPath)
            }
          }
        }
      }
      for entry in sourceRuleEntries {
        extractSourcePaths(entry)
      }

      NSThread.doOnMainThread() {
        defer { self.processingTaskFinished() }
        self.sourcePaths = [UISourcePath](sourcePathMap.values)
        callback(self.sourcePaths)
      }
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

    let result = TulsiGeneratorConfigDocument.generateXcodeProjectInFolder(outputFolderURL,
                                                                           withGeneratorConfig: config,
                                                                           workspaceRootURL: workspaceRootURL,
                                                                           messageLogger: self,
                                                                           messageLog: self,
                                                                           projectInfoExtractor: infoExtractor)
    switch result {
      case .Success(let url):
        return url
      case .Failure(let errorInfo):
        let fmt = NSLocalizedString("Error_GeneralProjectGenerationFailure",
                                    comment: "A general, critical failure during project generation. Details are provided as %1$@.")
        let errorMessage = String(format: fmt, errorInfo)
        self.error(errorMessage)
        return nil
    }
  }

  /// Resolves any outstanding uncached label references, converting a sparsely loaded document into
  /// a fully loaded one. completionHandler is invoked on the main thread when the document is fully
  /// loaded.
  func finishLoadingDocument(completionHandler: (TulsiGeneratorConfigDocument -> Void)) {
    processingTaskStarted()
    NSThread.doOnQOSUserInitiatedThread() {
      // Resolve labels to UIRuleEntries, warning on any failures.
      self.resolveLabelReferences() {
        assert(NSThread.isMainThread())
        if let concreteBuildTargetLabels = self.buildTargetLabels {
          let fmt = NSLocalizedString("Warning_LabelResolutionFailed",
                                      comment: "A non-critical failure to restore some Bazel labels when loading a document. Details are provided as %1$@.")
          self.warning(String(format: fmt, concreteBuildTargetLabels.map({ $0.description })))
        }
        self.processingTaskFinished()
        self._entireFileLoaded = true
        completionHandler(self)
      }
    }
  }

  func addProcessingTaskCount(taskCount: Int) {
    NSThread.doOnMainThread() { self.processingTaskCount += taskCount }
  }

  func processingTaskStarted() {
    NSThread.doOnMainThread() { self.processingTaskCount += 1 }
  }

  func processingTaskFinished() {
    NSThread.doOnMainThread() { self.processingTaskCount -= 1 }
  }

  // MARK: - NSWindowDelegate

  func windowWillClose(notification: NSNotification) {
    stopObservingRuleEntries()
  }

  // MARK: - OptionsEditorModelProtocol

  var projectName: String? = nil

  var optionSet: TulsiOptionSet? = TulsiOptionSet()

  var optionsTargetUIRuleEntries: [UIRuleInfo]? {
    return selectedUIRuleInfos
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

    // Ensure that the output folder exists to prevent saveToURL from freezing.
    do {
      try NSFileManager.defaultManager().createDirectoryAtURL(saveFolderURL,
                                                              withIntermediateDirectories: true,
                                                              attributes: nil)
    } catch let e as NSError {
      if let completionHandler = saveCompletionHandler {
        completionHandler(canceled: false, error: e)
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

  func error(message: String, details: String? = nil) {
    messageLogger?.error(message, details: details)
  }

  func info(message: String) {
    messageLogger?.info(message)
  }

  // MARK: - Private methods
  private func stopObservingRuleEntries() {
    for entry in uiRuleInfos {
      entry.removeObserver(self, forKeyPath: "selected", context: &TulsiGeneratorConfigDocument.KVOContext)
    }
  }

  private func makeConfig() -> TulsiGeneratorConfig? {
    guard let concreteProjectName = projectName,
              concreteOptionSet = optionSet else {
      return nil
    }

    let pathFilters = Set<String>(selectedSourcePaths.map() {
      if $0.recursive {
        return $0.path + "/..."
      }
      return $0.path
    })

    // Check to see if the document is sparsely loaded or not.
    if entireFileLoaded {
      return TulsiGeneratorConfig(projectName: concreteProjectName,
                                  buildTargets: selectedRuleInfos,
                                  pathFilters: pathFilters,
                                  additionalFilePaths: additionalFilePaths,
                                  options: concreteOptionSet,
                                  bazelURL: bazelURL)
    } else {
      return TulsiGeneratorConfig(projectName: concreteProjectName,
                                  buildTargetLabels: buildTargetLabels ?? [],
                                  pathFilters: pathFilters,
                                  additionalFilePaths: additionalFilePaths,
                                  options: concreteOptionSet,
                                  bazelURL: bazelURL)
    }
  }

  /// Resolves buildTargetLabels, leaving them populated with any labels that failed to be resolved.
  /// The given completion handler is invoked on the main thread once the labels are fully resolved.
  private func resolveLabelReferences(completionHandler: (Void -> Void)) {
    guard let concreteBuildTargetLabels = buildTargetLabels
        where !concreteBuildTargetLabels.isEmpty else {
      buildTargetLabels = nil
      NSThread.doOnMainThread() {
        completionHandler()
      }
      return
    }

    let resolvedLabels = infoExtractor.ruleEntriesForLabels(concreteBuildTargetLabels,
                                                            startupOptions: optionSet![.BazelBuildStartupOptionsDebug],
                                                            buildOptions: optionSet![.BazelBuildOptionsDebug])
    var unresolvedLabels = Set<BuildLabel>()
    var ruleInfos = [UIRuleInfo]()
    for label in concreteBuildTargetLabels {
      guard let info = resolvedLabels[label] else {
        unresolvedLabels.insert(label)
        continue
      }
      let uiRuleEntry = UIRuleInfo(ruleInfo: info)
      uiRuleEntry.selected = true
      ruleInfos.append(uiRuleEntry)
    }

    // Add in any of the previously loaded rule infos that were not resolved as selected targets.
    let existingInfos = self.uiRuleInfos.filter() {
      !concreteBuildTargetLabels.contains($0.ruleInfo.label)
    }
    for existingInfo in existingInfos {
      existingInfo.selected = false
      ruleInfos.append(existingInfo)
    }

    NSThread.doOnMainThread() {
      self.uiRuleInfos = ruleInfos
      self.buildTargetLabels = unresolvedLabels.isEmpty ? nil : [BuildLabel](unresolvedLabels)
      self.selectedRuleInfoCount = self.selectedRuleInfos.count
      completionHandler()
    }
  }
}
