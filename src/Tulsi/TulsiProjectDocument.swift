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


final class TulsiProjectDocument: NSDocument,
                                  NSWindowDelegate,
                                  MessageLogProtocol,
                                  OptionsEditorModelProtocol,
                                  TulsiGeneratorConfigDocumentDelegate {

  enum DocumentError: Error {
    /// No config exists with the given name.
    case noSuchConfig
    /// The config failed to load with the given debug info.
    case configLoadFailed(String)
    /// The workspace used by the project is invalid due to the given debug info.
    case invalidWorkspace(String)
  }

  /// Prefix used to access the persisted output folder for a given BUILD file path.
  static let ProjectOutputPathKeyPrefix = "projectOutput_"

  /// The subdirectory within a project bundle into which shareable generator configs will be
  /// stored.
  static let ProjectConfigsSubpath = "Configs"

  /// Override for headless project generation (in which messages should not spawn alert dialogs).
  static var showAlertsOnErrors = true

  /// Override to prevent rule entries from being extracted immediately during loading of project
  /// documents. This is only useful if the Bazel binary is expected to be set after the project
  /// document is loaded but before any other actions.
  static var suppressRuleEntryUpdateOnLoad = false

  /// The project model.
  var project: TulsiProject! = nil

  /// Whether or not the document is currently performing a long running operation.
  @objc dynamic var processing: Bool = false

  // The number of tasks that need to complete before processing is finished. May only be mutated on
  // the main queue.
  private var processingTaskCount: Int = 0 {
    didSet {
      assert(processingTaskCount >= 0, "Processing task count may never be negative")
      processing = processingTaskCount > 0
    }
  }

  /// The display names of generator configs associated with this project.
  @objc dynamic var generatorConfigNames = [String]()

  /// Whether or not there are any opened generator config documents associated with this project.
  var hasChildConfigDocuments: Bool {
    return childConfigDocuments.count > 0
  }

  /// Documents controlling the generator configs associated with this project.
  private var childConfigDocuments = NSHashTable<AnyObject>.weakObjects()

  /// One rule per target in the BUILD files associated with this project.
  var ruleInfos: [RuleInfo] {
    return _ruleInfos
  }

  private var _ruleInfos = [RuleInfo]() {
    didSet {
      // Update the associated config documents.
      let childDocuments = childConfigDocuments.allObjects as! [TulsiGeneratorConfigDocument]
      for configDoc in childDocuments {
        configDoc.projectRuleInfos = ruleInfos
      }
    }
  }

  /// The set of Bazel packages associated with this project.
  @objc dynamic var bazelPackages: [String]? {
    set {
      project!.bazelPackages = newValue ?? [String]()
      updateChangeCount(.changeDone)
      updateRuleEntries()
    }
    get {
      return project?.bazelPackages
    }
  }

  /// Location of the bazel binary.
  @objc dynamic var bazelURL: URL? {
    set {
      project.bazelURL = newValue
      if newValue != nil && infoExtractor != nil {
        infoExtractor.bazelURL = newValue!
      }
      updateChangeCount(.changeDone)
      updateRuleEntries()
    }
    get {
      return project?.bazelURL
    }
  }

  /// Binding point for the directory containing the project's WORKSPACE file.
  @objc dynamic var workspaceRootURL: URL? {
    return project?.workspaceRootURL
  }

  /// URL to the folder into which generator configs are saved.
  var generatorConfigFolderURL: URL? {
    return fileURL?.appendingPathComponent(TulsiProjectDocument.ProjectConfigsSubpath)
  }

  /// Whether or not the document has finished initializing the info extractor.
  @objc dynamic var infoExtractorInitialized: Bool = false

  var infoExtractor: TulsiProjectInfoExtractor! = nil {
    didSet {
      infoExtractorInitialized = (infoExtractor != nil)
    }
  }
  private var logEventObserver: NSObjectProtocol! = nil

  /// Array of user-facing messages, generally output by the Tulsi generator.
  @objc dynamic var messages = [UIMessage]()
  var errors = [LogMessage]()

  lazy var bundleExtension: String = {
    TulsiProjectDocument.getTulsiBundleExtension()
  }()

  static func getTulsiBundleExtension() -> String {
    let bundle = Bundle(for: self)
    let documentTypes = bundle.infoDictionary!["CFBundleDocumentTypes"] as! [[String: AnyObject]]
    let extensions = documentTypes.first!["CFBundleTypeExtensions"] as! [String]
    return extensions.first!
  }

  override init() {
    super.init()
    logEventObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: TulsiMessageNotification),
                                                                               object: nil,
                                                                               queue: OperationQueue.main) {
      [weak self] (notification: Notification) in
        guard let item = LogMessage(notification: notification) else {
          if let showModal = notification.userInfo?["displayErrors"] as? Bool, showModal {
            self?.displayErrorModal()
          }
          return
        }
        self?.handleLogMessage(item)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(logEventObserver!)
  }

  func clearMessages() {
    messages.removeAll(keepingCapacity: true)
  }

  func addBUILDFileURL(_ buildFile: URL) -> Bool {
    guard let package = packageForBUILDFile(buildFile) else {
      return false
    }
    bazelPackages!.append(package)
    return true
  }

  func containsBUILDFileURL(_ buildFile: URL) -> Bool {
    guard let package = packageForBUILDFile(buildFile),
              let concreteBazelPackages = bazelPackages else {
      return false
    }
    return concreteBazelPackages.contains(package)
  }

  func createNewProject(_ projectName: String, workspaceFileURL: URL) {
    willChangeValue(for: \.bazelURL)
    defer { didChangeValue(for: \.bazelURL) }
    willChangeValue(for: \.bazelPackages)
    defer { didChangeValue(for: \.bazelPackages) }
    willChangeValue(for: \.workspaceRootURL)
    defer { didChangeValue(for: \.workspaceRootURL) }

    // Default the bundleURL to a sibling of the selected workspace file.
    let bundleName = "\(projectName).\(bundleExtension)"
    let workspaceRootURL = workspaceFileURL.deletingLastPathComponent()
    let tempProjectBundleURL = workspaceRootURL.appendingPathComponent(bundleName)

    project = TulsiProject(projectName: projectName,
                           projectBundleURL: tempProjectBundleURL,
                           workspaceRootURL: workspaceRootURL)
    updateChangeCount(.changeDone)

    LogMessage.postSyslog("Create project: \(projectName)")
  }

  override func writeSafely(to url: URL,
                            ofType typeName: String,
                            for saveOperation: NSDocument.SaveOperationType) throws {
    // Ensure that the project's URL is set to the location in which this document is being saved so
    // that relative paths can be set properly.
    project.projectBundleURL = url
    // Create any parent directories if they don't yet exist.
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
  }

  override class var autosavesInPlace: Bool {
    return true
  }

  override func prepareSavePanel(_ panel: NSSavePanel) -> Bool {
    panel.message = NSLocalizedString("Document_SelectTulsiProjectOutputFolderMessage",
                                      comment: "Message to show at the top of the Tulsi project save as panel, explaining what to do.")
    panel.canCreateDirectories = true
    panel.allowedFileTypes = ["com.google.tulsi.project"]
    panel.nameFieldStringValue = project.projectBundleURL.lastPathComponent
    return true
  }

  override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
    let contents = [String: FileWrapper]()
    let bundleFileWrapper = FileWrapper(directoryWithFileWrappers: contents)
    bundleFileWrapper.addRegularFile(withContents: try project.save() as Data,
                                     preferredFilename: TulsiProject.ProjectFilename)

    if let perUserData = try project.savePerUserSettings() {
      bundleFileWrapper.addRegularFile(withContents: perUserData as Data,
                                       preferredFilename: TulsiProject.perUserFilename)
    }

    let configsFolder: FileWrapper
    let reachableError: NSErrorPointer = nil
    if let existingConfigFolderURL = generatorConfigFolderURL, (existingConfigFolderURL as NSURL).checkResourceIsReachableAndReturnError(reachableError) {
      // Preserve any existing config documents.
      configsFolder = try FileWrapper(url: existingConfigFolderURL,
                                        options:  FileWrapper.ReadingOptions())
    } else {
      // Add a placeholder Configs directory.
      configsFolder = FileWrapper(directoryWithFileWrappers: [:])
    }
    configsFolder.preferredFilename = TulsiProjectDocument.ProjectConfigsSubpath
    bundleFileWrapper.addFileWrapper(configsFolder)
    return bundleFileWrapper
  }

  override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
    guard let concreteFileURL = fileURL,
              let projectFileWrapper = fileWrapper.fileWrappers?[TulsiProject.ProjectFilename],
              let fileContents = projectFileWrapper.regularFileContents else {
      return
    }

    let additionalOptionData: Data?
    if let perUserDataFileWrapper = fileWrapper.fileWrappers?[TulsiProject.perUserFilename] {
      additionalOptionData = perUserDataFileWrapper.regularFileContents
    } else {
      additionalOptionData = nil
    }
    project = try TulsiProject(data: fileContents,
                               projectBundleURL: concreteFileURL,
                               additionalOptionData: additionalOptionData)

    if let configsDir = fileWrapper.fileWrappers?[TulsiProjectDocument.ProjectConfigsSubpath],
           let configFileWrappers = configsDir.fileWrappers, configsDir.isDirectory {
      var configNames = [String]()
      for (_, fileWrapper) in configFileWrappers {
        if let filename = fileWrapper.filename, fileWrapper.isRegularFile &&
                TulsiGeneratorConfigDocument.isGeneratorConfigFilename(filename) {
          let name = (filename as NSString).deletingPathExtension
          configNames.append(name)
        }
      }

      generatorConfigNames = configNames.sorted()
    }

    // Verify that the workspace is a valid one.
    let workspaceFile = project.workspaceRootURL.appendingPathComponent("WORKSPACE",
                                                                        isDirectory: false)
    var isDirectory = ObjCBool(false)
    if !FileManager.default.fileExists(atPath: workspaceFile.path,
                                       isDirectory: &isDirectory) || isDirectory.boolValue {
      let fmt = NSLocalizedString("Error_NoWORKSPACEFile",
                                  comment: "Error when project does not have a valid Bazel WORKSPACE file at %1$@.")
      LogMessage.postError(String(format: fmt, workspaceFile.path))
      LogMessage.displayPendingErrors()
      throw DocumentError.invalidWorkspace("Missing WORKSPACE file at \(workspaceFile.path)")
    }

    if !TulsiProjectDocument.suppressRuleEntryUpdateOnLoad {
      updateRuleEntries()
    }
  }

  override func makeWindowControllers() {
    let storyboard = NSStoryboard(name: "Main", bundle: nil)
    let windowController = storyboard.instantiateController(withIdentifier: "TulsiProjectDocumentWindow") as! NSWindowController
    windowController.contentViewController?.representedObject = self
    addWindowController(windowController)
  }

  override func willPresentError(_ error: Error) -> Error {
    // Track errors shown to the user for bug reporting purposes.
    LogMessage.postInfo("Presented error: \(error)", context: projectName)
    return super.willPresentError(error)
  }

  /// Tracks the given document as a child of this project.
  func trackChildConfigDocument(_ document: TulsiGeneratorConfigDocument) {
    childConfigDocuments.add(document)
    // Ensure that the child document is aware of the project-level processing tasks.
    document.addProcessingTaskCount(processingTaskCount)
  }

  /// Closes any generator config documents associated with this project.
  func closeChildConfigDocuments() {
    let childDocuments = childConfigDocuments.allObjects as! [TulsiGeneratorConfigDocument]
    for configDoc in childDocuments {
      configDoc.close()
    }
    childConfigDocuments.removeAllObjects()
  }

  func deleteConfigsNamed(_ configNamesToRemove: [String]) {
    let fileManager = FileManager.default

    var nameToDoc = [String: TulsiGeneratorConfigDocument]()
    for doc in childConfigDocuments.allObjects as! [TulsiGeneratorConfigDocument] {
      guard let name = doc.configName else { continue }
      nameToDoc[name] = doc
    }
    var configNames = Set<String>(generatorConfigNames)

    for name in configNamesToRemove {
      configNames.remove(name)
      if let doc = nameToDoc[name] {
        childConfigDocuments.remove(doc)
        doc.close()
      }
      if let url = urlForConfigNamed(name, sanitized: false) {
        let errorInfo: String?
        do {
          try fileManager.removeItem(at: url)
          errorInfo = nil
        } catch let e as NSError {
          errorInfo = "Unexpected exception \(e.localizedDescription)"
        } catch {
          errorInfo = "Unexpected exception"
        }
        if let errorInfo = errorInfo {
          let fmt = NSLocalizedString("Error_ConfigDeleteFailed",
                                      comment: "Error when a TulsiGeneratorConfig named %1$@ could not be deleted.")
          LogMessage.postError(String(format: fmt, name), details: errorInfo)
          LogMessage.displayPendingErrors()
        }
      }
    }

    generatorConfigNames = configNames.sorted()
  }

  func urlForConfigNamed(_ name: String, sanitized: Bool = true) -> URL? {
     return TulsiGeneratorConfigDocument.urlForConfigNamed(name,
                                                           inFolderURL: generatorConfigFolderURL,
                                                           sanitized: sanitized)
  }

  /// Asynchronously loads a previously created config with the given name, invoking the given
  /// completionHandler on the main thread when the document is fully loaded.
  func loadConfigDocumentNamed(_ name: String,
                               completionHandler: @escaping ((TulsiGeneratorConfigDocument?) -> Void)) throws -> TulsiGeneratorConfigDocument {
    let doc = try loadSparseConfigDocumentNamed(name)
    doc.finishLoadingDocument(completionHandler)
    return doc
  }

  /// Sparsely loads a previously created config with the given name. The returned document may have
  /// unresolved label references.
  func loadSparseConfigDocumentNamed(_ name: String) throws -> TulsiGeneratorConfigDocument {
    guard let configURL = urlForConfigNamed(name, sanitized: false) else {
      throw DocumentError.noSuchConfig
    }

    let documentController = NSDocumentController.shared
    if let configDocument = documentController.document(for: configURL) as? TulsiGeneratorConfigDocument {
      return configDocument
    }

    do {
      let configDocument = try TulsiGeneratorConfigDocument.makeSparseDocumentWithContentsOfURL(configURL,
                                                                                                infoExtractor: infoExtractor,
                                                                                                messageLog: self,
                                                                                                bazelURL: bazelURL)
      configDocument.projectRuleInfos = ruleInfos
      configDocument.delegate = self
      trackChildConfigDocument(configDocument)
      return configDocument
    } catch let e as NSError {
      throw DocumentError.configLoadFailed("Failed to load config from '\(configURL.path)' with error \(e.localizedDescription)")
    } catch {
      throw DocumentError.configLoadFailed("Unexpected exception loading config from '\(configURL.path)'")
    }
  }

  /// Displays a generic critical error message to the user with the given debug message.
  /// This should be used sparingly and only for messages that would indicate bugs in Tulsi.
  func generalError(_ debugMessage: String) {
    let msg = NSLocalizedString("Error_GeneralCriticalFailure",
                                comment: "A general, critical failure without a more fitting descriptive message.")
    LogMessage.postError(msg, details: debugMessage)
  }

  // MARK: - NSUserInterfaceValidations

  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    let itemAction = item.action
    switch itemAction {
      case .some(#selector(TulsiProjectDocument.save(_:))):
        return true
      case .some(#selector(TulsiProjectDocument.saveAs(_:))):
        return true
      case .some(#selector(TulsiProjectDocument.rename(_:))):
        return true
      case .some(#selector(TulsiProjectDocument.move(_:))):
        return true

      // Unsupported actions.
      case .some(#selector(TulsiProjectDocument.duplicate(_:))):
        return false

      default:
        Swift.print("Unhandled menu action: \(String(describing: itemAction))")
    }
    return false
  }

  // MARK: - TulsiGeneratorConfigDocumentDelegate

  func didNameTulsiGeneratorConfigDocument(_ document: TulsiGeneratorConfigDocument, configName: String) {
    if !generatorConfigNames.contains(configName) {
      let configNames = (generatorConfigNames + [configName]).sorted()
      generatorConfigNames = configNames
    }
  }

  func parentOptionSetForConfigDocument(_: TulsiGeneratorConfigDocument) -> TulsiOptionSet? {
    return optionSet
  }

  // MARK: - OptionsEditorModelProtocol

  var projectName: String? {
    guard let concreteProject = project else { return nil }
    return concreteProject.projectName
  }

  var optionSet: TulsiOptionSet? {
    guard let concreteProject = project else { return nil }
    return concreteProject.options
  }

  var projectValueColumnTitle: String {
    return NSLocalizedString("OptionsEditor_ColumnTitle_Project",
                             comment: "Title for the options editor column used to edit per-tulsiproj values.")
  }

  var defaultValueColumnTitle: String {
    return NSLocalizedString("OptionsEditor_ColumnTitle_Default",
                             comment: "Title for the options editor column used to display the built-in default values.")
  }

  var optionsTargetUIRuleEntries: [UIRuleInfo]? {
    return nil
  }

  // MARK: - Private methods

  // Idempotent function to gather all error messages that have been logged and create a single
  // error modal to present to the user.
  private func displayErrorModal() {
    guard TulsiProjectDocument.showAlertsOnErrors else {
      return
    }

    var errorMessages = [String]()
    var details = [String]()

    for error in errors {
      errorMessages.append(error.message)
      if let detail = error.details {
        details.append(detail)
      }
    }
    errors.removeAll()

    if !errorMessages.isEmpty {
      ErrorAlertView.displayModalError(errorMessages.joined(separator: "\n"), details: details.joined(separator: "\n"))
    }
  }

  private func handleLogMessage(_ item: LogMessage) {
    let fullMessage: String
    if let details = item.details {
      fullMessage = "\(item.message) [Details]: \(details)"
    } else {
      fullMessage = item.message
    }

    switch item.level {
      case .Error:
        messages.append(UIMessage(text: fullMessage, type: .error))
        errors.append(item)

      case .Warning:
        messages.append(UIMessage(text: fullMessage, type: .warning))

      case .Info:
        messages.append(UIMessage(text: fullMessage, type: .info))

      case .Syslog:
        break

      case .Debug:
        messages.append(UIMessage(text: fullMessage, type: .debug))
    }
  }

  private func processingTaskStarted() {
    Thread.doOnMainQueue() {
      self.processingTaskCount += 1
      let childDocuments = self.childConfigDocuments.allObjects as! [TulsiGeneratorConfigDocument]
      for configDoc in childDocuments {
        configDoc.processingTaskStarted()
      }
    }
  }

  private func processingTaskFinished() {
    Thread.doOnMainQueue() {
      self.processingTaskCount -= 1
      let childDocuments = self.childConfigDocuments.allObjects as! [TulsiGeneratorConfigDocument]
      for configDoc in childDocuments {
        configDoc.processingTaskFinished()
      }
    }
  }

  private func packageForBUILDFile(_ buildFile: URL) -> String? {
    let packageURL = buildFile.deletingLastPathComponent()

    // If the relative path is a child of the workspace root return it.
    if let relativePath = project.workspaceRelativePathForURL(packageURL), !relativePath.hasPrefix("/") && !relativePath.hasPrefix("..") {
      return relativePath
    }
    return nil
  }

  // Fetches target rule entries from the project's BUILD documents.
  private func updateRuleEntries() {
    guard let concreteBazelURL = bazelURL else {
      return
    }

    processingTaskStarted()

    Thread.doOnQOSUserInitiatedThread() {
      self.infoExtractor = TulsiProjectInfoExtractor(bazelURL: concreteBazelURL,
                                                     project: self.project)
      let updatedRuleEntries = self.infoExtractor.extractTargetRules()
      Thread.doOnMainQueue() {
        self._ruleInfos = updatedRuleEntries
        self.processingTaskFinished()
      }
    }
  }
}


/// Convenience class for displaying an error message with an optional detail accessory view.
class ErrorAlertView: NSAlert {
  @objc dynamic var text = ""

  static func displayModalError(_ message: String, details: String? = nil) {
    let alert = ErrorAlertView()
    alert.messageText = "\(message)\n\nA fatal error occurred. Please check the message window " +
        "and file a bug if appropriate."
    alert.alertStyle = .critical

    if let details = details, !details.isEmpty {
      alert.text = details

      var views: NSArray?
      Bundle.main.loadNibNamed("ErrorAlertDetailView",
                               owner: alert,
                               topLevelObjects: &views)
      // Note: topLevelObjects will contain the accessory view and an NSApplication object in a
      // non-deterministic order.
      if let views = views {
        let viewsFound = views.filter() { $0 is NSView } as NSArray
        if let accessoryView = viewsFound.firstObject as? NSScrollView {
          alert.accessoryView = accessoryView

          // Fix text color for dark mode.
          //
          // Text color is set to nil for the text view (which defaults to black) and Interface
          // Builder can't seem to correctly assign the color, so the text color needs to be
          // assigned at runtime.
          for view in accessoryView.subviews {
            for subview in view.subviews {
              if let textView = subview as? NSTextView {
                textView.textColor = NSColor.textColor
              }
            }
          }
        } else {
          assertionFailure("Failed to load accessory view for error alert.")
        }
      }
    }
    alert.runModal()
  }
}
