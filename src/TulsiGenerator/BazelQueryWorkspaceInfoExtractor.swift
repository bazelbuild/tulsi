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

import Foundation


// Concrete extractor that utilizes Bazel query (http://bazel.io/docs/query.html) to extract
// information about a BUILD file.
class BazelQueryWorkspaceInfoExtractor: WorkspaceInfoExtractorProtocol, LabelResolverProtocol {
  /// The maximum number of bazel tasks that any logical action may run in parallel.
  // Note that multiple logical actions may execute concurrently, so the actual number of bazel
  // tasks could be higher than this.
  static let bazelQueryConcurrentChunkSize = 8

  /// The location of the bazel binary.
  let bazelURL: NSURL
  /// The location of the directory in which the workspace enclosing this BUILD file can be found.
  let workspaceRootURL: NSURL

  private let localizedMessageLogger: LocalizedMessageLogger

  private typealias BazelQueryCompletionHandler = (bazelTask: NSTask,
                                                   returnedData: NSData,
                                                   debugInfo: String) -> Void

  init(bazelURL: NSURL, workspaceRootURL: NSURL, localizedMessageLogger: LocalizedMessageLogger) {
    self.bazelURL = bazelURL
    self.workspaceRootURL = workspaceRootURL
    self.localizedMessageLogger = localizedMessageLogger
  }

  // MARK: - WorkspaceInfoExtractorProtocol

  func extractTargetRulesFromProject(project: TulsiProject, callback: ([RuleEntry]) -> Void) {
    guard let path = workspaceRootURL.path else {
      dispatch_async(dispatch_get_main_queue()) { callback([]) }
      return
    }

    let projectPackages = project.bazelPackages
    let query = projectPackages.map({ "kind(rule, \($0):all)"}).joinWithSeparator("+")
    let profilingStart = localizedMessageLogger.startProfiling("fetch_rules",
                                                               message: "Fetching rules for packages \(projectPackages)")
    let task = bazelQueryTask(query, outputKind: "xml") {
      (task: NSTask, data: NSData, debugInfo: String) -> Void in
        let ruleEntries = self.extractRuleEntriesFromBazelXMLOutput(data)
        if ruleEntries == nil {
          self.localizedMessageLogger.infoMessage(debugInfo)
        }
        self.localizedMessageLogger.logProfilingEnd(profilingStart)
        dispatch_async(dispatch_get_main_queue()) {
          assert(ruleEntries != nil, "Extraction failed")
          callback(ruleEntries!)
        }
    }

    task.currentDirectoryPath = path
    task.launch()
  }

  func extractSourceRulesForRuleEntries(ruleEntries: [RuleEntry], callback: ([RuleEntry]) -> Void) {
    var sourceRuleEntries = [RuleEntry]()
    guard let path = workspaceRootURL.path else {
      dispatch_async(dispatch_get_main_queue()) { callback(sourceRuleEntries) }
      return
    }

    let sourceRuleEntriesSempahore = dispatch_semaphore_create(1)
    let dispatchGroup = dispatch_group_create()
    let profilingStart = localizedMessageLogger.startProfiling("extract_source_rules",
                                                               message: "Extracting source rules")
    for entry in ruleEntries {
      let task = bazelQueryTask("kind(rule, deps(" +  entry.label.value + "))",
                                outputKind: "xml",
                                message: "Fetching source rules for rule \(entry)") {
        (task: NSTask, data: NSData, debugInfo: String) -> Void in
          let dependencies = self.extractRuleEntriesFromBazelXMLOutput(data)

          if let validDependencies = dependencies {
            entry.addDependencies(validDependencies)
            dispatch_semaphore_wait(sourceRuleEntriesSempahore, DISPATCH_TIME_FOREVER)
            sourceRuleEntries.appendContentsOf(validDependencies)
            dispatch_semaphore_signal(sourceRuleEntriesSempahore)
          } else {
            self.localizedMessageLogger.warning("SourceRuleExtractionFailed",
                                                comment: "The Bazel query for dependencies of rule %1$@ failed XML parsing. As a result, the user won't be able to add affected source files to the project unless they happen to be dependencies of another target that succeeds.",
                                                values: entry.description)
            self.localizedMessageLogger.infoMessage(debugInfo)
          }
          dispatch_group_leave(dispatchGroup)
      }

      dispatch_group_enter(dispatchGroup)
      task.currentDirectoryPath = path
      task.launch()
    }

    dispatch_group_notify(dispatchGroup, dispatch_get_main_queue()) {
      sourceRuleEntries.sortInPlace {$0.label < $1.label}
      self.localizedMessageLogger.logProfilingEnd(profilingStart)
      callback(sourceRuleEntries)
    }
  }

  func extractSourceFilePathsForSourceRules(sourceRuleEntries: [RuleEntry]) -> [RuleEntry: [String]] {
    var sourcePaths = [RuleEntry: [String]]()
    let sourcePathsSempahore = dispatch_semaphore_create(1)
    let progressNotifier = ProgressNotifier(name: SourceFileExtraction,
                                            maxValue: sourceRuleEntries.count)

    let queue = dispatch_queue_create("com.google.Tulsi.sourceFilePathExtractor",
                                      DISPATCH_QUEUE_SERIAL)
    let profilingStart = localizedMessageLogger.startProfiling("extract_source_paths",
                                                               message: "Extracting source file paths")

    var stopExecution = false
    var i = 0
    for entry in sourceRuleEntries {
      dispatch_async(queue) {
        if stopExecution { return }
        let query = "kind(\"source file\", deps(" + entry.label.value + ", 1))"
        let (task, data, debugInfo) = self.bazelSynchronousQueryTask(query,
                                                                     message: "Fetching source files for entry \(entry)")
        guard let paths = self.extractPathsFromLabelData(data) else {
          self.localizedMessageLogger.error("BazelResponseLabelExtractionFailed",
                                            comment: "Extracting labels from Bazel query failed (likely a bad response from Bazel).",
                                            values: task.arguments!)
          self.localizedMessageLogger.infoMessage(debugInfo)
          stopExecution = true
          return
        }
        dispatch_semaphore_wait(sourcePathsSempahore, DISPATCH_TIME_FOREVER)
        sourcePaths[entry] = paths
        progressNotifier.value = sourcePaths.count
        dispatch_semaphore_signal(sourcePathsSempahore)
      }

      // Use barriers to limit the number of concurrent Bazel tasks.
      i += 1
      if (i & BazelQueryWorkspaceInfoExtractor.bazelQueryConcurrentChunkSize) == 0 {
        dispatch_barrier_async(queue) {}
      }
    }

    // Wait for all sources to be processed before logging completion and returning.
    dispatch_barrier_sync(queue) {}
    localizedMessageLogger.logProfilingEnd(profilingStart)
    return sourcePaths
  }

  func ruleEntriesForLabels(labels: [String]) -> [String: RuleEntry] {
    let query = labels.joinWithSeparator("+")
    let profilingStart = localizedMessageLogger.startProfiling("reload_rules",
                                                               message: "Loading \(labels.count) labels")
    let (_, data, debugInfo) = bazelSynchronousQueryTask(query, outputKind: "xml")

    let ruleEntries = self.extractRuleEntriesFromBazelXMLOutput(data)
    if ruleEntries == nil {
      self.localizedMessageLogger.infoMessage(debugInfo)
    }
    self.localizedMessageLogger.logProfilingEnd(profilingStart)

    var labelToRuleEntry = [String: RuleEntry]()
    for entry in ruleEntries! {
      labelToRuleEntry[entry.label.value] = entry
    }
    return labelToRuleEntry
  }

  // MARK: - LabelResolverProtocol

  func resolveFilesForLabels(labels: [String]) -> [String: BazelFileTarget?]? {
    assert(!NSThread.isMainThread(), "resolveFilesForLabels is long-running and must be called from a worker thread")
    guard let path = workspaceRootURL.path else {
      localizedMessageLogger.error("CriticalTulsiBug",
                                   comment: "A precondition failure that indicates a critical Tulsi " +
                                           "programming error in function %1$@ line %2$d and should be reported.",
                                   values: __FUNCTION__, __LINE__)
      return nil
    }

    let dispatchGroup = dispatch_group_create()
    let fileSempahore = dispatch_semaphore_create(1)
    var files = [String: BazelFileTarget?]()
    let progressNotifier = ProgressNotifier(name: LabelResolution, maxValue: labels.count)
    let profilingStart = localizedMessageLogger.startProfiling("resolve_labels",
                                                               message: "Resolving labels to files")
    for label in labels {
      let task = bazelQueryTask(label, outputKind: "xml", message: "Resolving label \(label)") {
        (task: NSTask, data: NSData, debugInfo: String) -> Void in
          let sourceFile = self.extractSourceFileFromLabelQueryBazelXMLOutput(data, label: label)
          if sourceFile == nil {
            self.localizedMessageLogger.infoMessage(debugInfo)
          }
          dispatch_semaphore_wait(fileSempahore, DISPATCH_TIME_FOREVER)
          files[label] = sourceFile
          progressNotifier.value = files.count
          dispatch_semaphore_signal(fileSempahore)
          dispatch_group_leave(dispatchGroup)
      }
      dispatch_group_enter(dispatchGroup)
      task.currentDirectoryPath = path
      task.launch()
    }

    dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER)
    localizedMessageLogger.logProfilingEnd(profilingStart)
    return files
  }

  // MARK: - Private methods

  // Generates an NSTask that will perform a bazel query, capturing the output data and passing it
  // to the terminationHandler.
  private func bazelQueryTask(query: String,
                              outputKind: String? = nil,
                              var message: String = "",
                              terminationHandler: BazelQueryCompletionHandler) -> NSTask {
    var arguments = [
        "--max_idle_secs=60",
        "query",
        "--keep_going",
        "--noimplicit_deps",
        "--order_output=no",
        "--noshow_loading_progress",
        "--noshow_progress",
        query
    ]
    if let kind = outputKind {
      arguments.appendContentsOf(["--output", kind])
    }

    if message != "" {
      message = "\(message)\n"
    }
    localizedMessageLogger.infoMessage("\(message)Running bazel command with arguments: \(arguments)")

    let task = TaskRunner.standardRunner().createTask(bazelURL.path!, arguments: arguments) {
      completionInfo in
        let debugInfoFormatString = NSLocalizedString("DebugInfoForBazelCommand",
                                                      bundle: NSBundle(forClass: self.dynamicType),
                                                      comment: "Provides general information about a Bazel failure; a more detailed error may be reported elsewhere. The Bazel command is %1$@, exit code is %2$d, stderr %3$@.")
        let stderr = NSString(data: completionInfo.stderr, encoding: NSUTF8StringEncoding)
        let debugInfo = String(format: debugInfoFormatString,
                               completionInfo.commandlineString,
                               completionInfo.terminationStatus,
                               stderr ?? "<No STDERR>")

        terminationHandler(bazelTask: completionInfo.task,
                           returnedData: completionInfo.stdout,
                           debugInfo: debugInfo)
    }

    return task
  }

  /// Performs the given Bazel query synchronously in the workspaceRootURL directory.
  private func bazelSynchronousQueryTask(query: String,
                                         outputKind: String? = nil,
                                         let message: String = "") -> (bazelTask: NSTask,
                                                                       returnedData: NSData,
                                                                       debugInfo: String) {
    let semaphore = dispatch_semaphore_create(0)
    var data: NSData! = nil
    var info: String! = nil

    let task = bazelQueryTask(query, outputKind: outputKind, message: message) {
      (_: NSTask, returnedData: NSData, debugInfo: String) in
        data = returnedData
        info = debugInfo
      dispatch_semaphore_signal(semaphore)
    }

    task.currentDirectoryPath = workspaceRootURL.path!
    task.launch()

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    return (task, data, info)
  }

  // Given the output of a query for some label, attempts to return a BazelFileTarget that maps to a
  // file that will be accessible to Xcode. Concretely, if query's output was a source-file, this
  // method will return that file. If the query's output was a rule, this method will return the
  // rule-output deemed most appropriate.
  private func extractSourceFileFromLabelQueryBazelXMLOutput(bazelOutput: NSData, label: String) -> BazelFileTarget? {
    do {
      let doc = try NSXMLDocument(data: bazelOutput, options: 0)
      if let (pathLabel, targetType) = try extractSourceFileFromLabelQueryXMLDoc(doc, label: label) {
        guard let filePath = BuildLabel(pathLabel).asFileName else {
          localizedMessageLogger.error("LabelResolverResolvedNonFilePath",
                                       comment: "label %1$@ resolved successfully to %2$@ which is unexpectedly not a file path.",
                                       values: label, pathLabel)
          return nil
        }
        return BazelFileTarget(label: BuildLabel(label), path: filePath, targetType: targetType)
      }
      return nil
    } catch let e as NSError {
      localizedMessageLogger.error("LabelResolverXMLParsingFailed",
                                   comment: "Label resolver Bazel output failed to be parsed as XML with error %1$@. This may be a Bazel bug or a bad BUILD file.",
                                   values: e.localizedDescription)
      return nil
    }
  }

  private func extractSourceFileFromLabelQueryXMLDoc(doc: NSXMLDocument, label: String) throws -> (path: String, targetType: BazelFileTarget.TargetType)? {

    func extractPathLabelFromXPathQueryResponse(response: [NSXMLNode], attribute: String) -> String? {
      assert(response.count == 1, "Unexpectedly received multiple elements resolving \(label).")
      guard let element = response.first! as? NSXMLElement else {
        localizedMessageLogger.error("BazelResponseXMLNonElementType",
                                     comment: "General error to show when the XML parser returns something other " +
                                             "than an NSXMLElement. This should never happen in practice.")
        return nil
      }

      if let pathLabel = element.attributeForName(attribute)?.stringValue {
        return pathLabel
      }
      localizedMessageLogger.error("BazelResponseMissingRequiredAttribute",
                                   comment: "Bazel response XML element %1$@ was found but was missing an attribute named %2$@.",
                                   values: element, attribute)
      return nil
    }

    let sourceFiles = try doc.nodesForXPath("/query/source-file")
    if !sourceFiles.isEmpty {
      guard let pathLabel = extractPathLabelFromXPathQueryResponse(sourceFiles, attribute: "name") else {
        return nil
      }
      return (pathLabel, .SourceFile)
    }

    let filegroupSrcs = try doc.nodesForXPath("/query/rule[@class='filegroup']/list[@name='srcs']/label")
    if !filegroupSrcs.isEmpty {
      guard let pathLabel = extractPathLabelFromXPathQueryResponse(filegroupSrcs, attribute: "value") else {
        return nil
      }
      return (pathLabel, .SourceFile)
    }

    let ruleOutputs = try doc.nodesForXPath("/query/rule[@class='genrule']/rule-output")
    if !ruleOutputs.isEmpty {
      guard let pathLabel = extractPathLabelFromXPathQueryResponse(ruleOutputs, attribute: "name") else {
        return nil
      }
      return (pathLabel, .GeneratedFile)
    }

    return nil
  }

  private func extractRuleEntriesFromBazelXMLOutput(bazelOutput: NSData) -> [RuleEntry]? {
    do {
      var ruleEntries = [RuleEntry]()
      let doc = try NSXMLDocument(data: bazelOutput, options: 0)
      let rules = try doc.nodesForXPath("/query/rule")
      for ruleNode in rules {
        guard let ruleElement = ruleNode as? NSXMLElement else {
          localizedMessageLogger.error("BazelResponseXMLNonElementType",
                                       comment: "General error to show when the XML parser returns something other " +
                                               "than an NSXMLElement. This should never happen in practice.")
          continue
        }
        guard let ruleLabel = ruleElement.attributeForName("name")?.stringValue else {
          localizedMessageLogger.error("BazelResponseMissingRequiredAttribute",
                                       comment: "Bazel response XML element %1$@ was found but was missing an attribute named %2$@.",
                                       values: ruleElement, "name")
          continue
        }
        guard let ruleType = ruleElement.attributeForName("class")?.stringValue else {
          localizedMessageLogger.error("BazelResponseMissingRequiredAttribute",
                                       comment: "Bazel response XML element %1$@ was found but was missing an attribute named %2$@.",
                                       values: ruleElement, "class")
          continue
        }

        var attributes = [String: String]()
        let topLevelRuleAttributes = try ruleElement.nodesForXPath("./(label|boolean)[@value]")
        for labelNode in topLevelRuleAttributes {
          guard let labelElement = labelNode as? NSXMLElement else {
            localizedMessageLogger.error("BazelResponseXMLNonElementType",
                                         comment: "General error to show when the XML parser returns something other " +
                                                 "than an NSXMLElement. This should never happen in practice.")
            continue
          }
          guard let attributeName = labelElement.attributeForName("name")?.stringValue else {
            localizedMessageLogger.error("BazelResponseMissingRequiredAttribute",
                                         comment: "Bazel response XML element %1$@ was found but was missing an attribute named %2$@.",
                                         values: labelElement, "name")
            continue
          }
          guard let attributeValue = labelElement.attributeForName("value")?.stringValue else {
            localizedMessageLogger.error("BazelResponseMissingRequiredAttribute",
                                         comment: "Bazel response XML element %1$@ was found but was missing an attribute named %2$@.",
                                         values: ruleElement, "value")
            continue
          }
          attributes[attributeName] = attributeValue
        }
        let entry = RuleEntry(label: BuildLabel(ruleLabel), type: ruleType, attributes: attributes)
        ruleEntries.append(entry)
      }
      return ruleEntries
    } catch let e as NSError {
      localizedMessageLogger.error("BazelResponseXMLParsingFailed",
                                   comment: "Extractor Bazel output failed to be parsed as XML with error %1$@. This may be a Bazel bug or a bad BUILD file.",
                                   values: e.localizedDescription)
      return nil
    }
  }

  private func extractPathsFromLabelData(bazelOutput: NSData) -> [String]? {
    guard let output = NSString(data: bazelOutput, encoding: NSUTF8StringEncoding) else {
      return nil
    }

    let labels = output.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
    return BazelQueryWorkspaceInfoExtractor.convertLabelsToPaths(labels)
  }

  // Convert Bazel labels to relative paths.
  // e.g., //my/app:file -> my/app/file
  private static func convertLabelsToPaths(labels: [String]) -> [String] {
    var paths = [String]()
    for label in labels {
      if label.isEmpty || label == "____Empty results" {
        continue
      }

      if let path = BuildLabel(label).asFileName {
        paths.append(path)
      }
    }

    return paths
  }
}


/// Encapsulates posting progress update notifications.
class ProgressNotifier {
  let name: String
  let maxValue: Int

  var value: Int = 0 {
    didSet {
      dispatch_async(dispatch_get_main_queue()) {
        let notificationCenter = NSNotificationCenter.defaultCenter()
        notificationCenter.postNotificationName(ProgressUpdatingTaskProgress,
                                                object: self,
                                                userInfo: [
                                                    ProgressUpdatingTaskProgressValue: self.value,
                                                ])
      }
    }
  }

  /// Initializes a new instance with the given name and maximum value. Note that a maxValue <= 0
  /// indicates an indeterminate progress item.
  init(name: String, maxValue: Int = 0) {
    self.name = name
    self.maxValue = maxValue

    dispatch_async(dispatch_get_main_queue()) {
      let notificationCenter = NSNotificationCenter.defaultCenter()
      notificationCenter.postNotificationName(ProgressUpdatingTaskDidStart,
                                              object: self,
                                              userInfo: [
                                                  ProgressUpdatingTaskName: name,
                                                  ProgressUpdatingTaskMaxValue: maxValue,
                                              ])
    }
  }

  /// For progress items that don't have intermediate updates, sends a notification that value =
  /// maxValue.
  func notifyCompleted() {
    value = maxValue
  }
}
