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


// Provides methods utilizing Bazel query (http://bazel.io/docs/query.html) to extract
// information from a workspace.
final class BazelQueryInfoExtractor {
  /// The location of the bazel binary.
  var bazelURL: NSURL
  /// The location of the directory in which the workspace enclosing this BUILD file can be found.
  let workspaceRootURL: NSURL

  private let localizedMessageLogger: LocalizedMessageLogger

  private typealias CompletionHandler = (bazelTask: NSTask,
                                         returnedData: NSData,
                                         debugInfo: String) -> Void

  init(bazelURL: NSURL, workspaceRootURL: NSURL, localizedMessageLogger: LocalizedMessageLogger) {
    self.bazelURL = bazelURL
    self.workspaceRootURL = workspaceRootURL
    self.localizedMessageLogger = localizedMessageLogger
  }

  func extractTargetRulesFromPackages(packages: [String]) -> [RuleInfo] {
    guard !packages.isEmpty else {
      return []
    }

    let profilingStart = localizedMessageLogger.startProfiling("fetch_rules",
                                                               message: "Fetching rules for packages \(packages)")
    var infos = [RuleInfo]()
    let query = packages.map({ "kind(rule, \($0):all)"}).joinWithSeparator("+")
    let (task, data, debugInfo) = self.bazelSynchronousQueryTask(query, outputKind: "xml")
    if let entries = self.extractRuleInfosFromBazelXMLOutput(data) {
      infos = entries
    }

    if task.terminationStatus != 0 {
      showExtractionError(debugInfo)
    }
    localizedMessageLogger.logProfilingEnd(profilingStart)
    return infos
  }

  /// Extracts a map of RuleInfo to considered expansions for the given test_suite targets.
  // The information provided represents the full possible set of tests for each test_suite; the
  // actual expansion by Bazel may not include all of the returned labels and will be done
  // recursively such that a test_suite whose expansion contains another test_suite would expand to
  // the contents of the incldued suite.
  func extractTestSuiteRules(testSuiteLabels: [BuildLabel]) -> [RuleInfo: Set<BuildLabel>] {
    if testSuiteLabels.isEmpty { return [:] }
    let profilingStart = localizedMessageLogger.startProfiling("expand_test_suite_rules",
                                                               message: "Expanding \(testSuiteLabels.count) test suites")

    var infos = [RuleInfo: Set<BuildLabel>]()
    let labelDeps = testSuiteLabels.map {"deps(\($0.value))"}
    let joinedLabelDeps = labelDeps.joinWithSeparator("+")
    let query = "kind(\"test_suite rule\",\(joinedLabelDeps))"
    let (_, data, debugInfo) = self.bazelSynchronousQueryTask(query, outputKind: "xml")
    if let entries = self.extractRuleInfosWithRuleInputsFromBazelXMLOutput(data) {
      infos = entries
    }
    // Note that this query is expected to return a non-zero exit code on occasion, so no error
    // message is logged.
    localizedMessageLogger.infoMessage(debugInfo)
    localizedMessageLogger.logProfilingEnd(profilingStart)
    return infos
  }

  // MARK: - Private methods

  private func showExtractionError(debugInfo: String) {
    localizedMessageLogger.infoMessage(debugInfo)

    let errorMessage: String?
    let errorLines = debugInfo.componentsSeparatedByString("\n").filter({ $0.hasPrefix("ERROR:") })
    if errorLines.isEmpty {
      errorMessage = nil
    } else {
      let numErrorLinesToShow = min(errorLines.count, 3)
      var errorSnippet = errorLines.prefix(numErrorLinesToShow).joinWithSeparator("\n")
      if numErrorLinesToShow < errorLines.count {
        errorSnippet += "\n..."
      }
      errorMessage = errorSnippet
    }
    localizedMessageLogger.error("BazelInfoExtractionFailed",
                                 comment: "Error message for when a Bazel extractor did not complete successfully. Details are logged separately.",
                                 details: errorMessage)
  }

  // Generates an NSTask that will perform a bazel query, capturing the output data and passing it
  // to the terminationHandler.
  private func bazelQueryTask(query: String,
                              outputKind: String? = nil,
                              message: String = "",
                              terminationHandler: CompletionHandler) -> NSTask {
    var arguments = [
        "--max_idle_secs=60",
        "query",
        "--noimplicit_deps",
        "--order_output=no",
        "--noshow_loading_progress",
        "--noshow_progress",
        query
    ]
    if let kind = outputKind {
      arguments.appendContentsOf(["--output", kind])
    }

    var message = message
    if message != "" {
      message = "\(message)\n"
    }
    localizedMessageLogger.infoMessage("\(message)Running \(bazelURL.path!) with arguments: \(arguments)")

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

  private func extractRuleInfosWithRuleInputsFromBazelXMLOutput(bazelOutput: NSData) -> [RuleInfo: Set<BuildLabel>]? {
    do {
      var infos = [RuleInfo: Set<BuildLabel>]()
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

        func extractLabelsFromXpath(xpath: String) throws -> Set<BuildLabel> {
          var labelSet = Set<BuildLabel>()
          let nodes = try ruleElement.nodesForXPath(xpath)
          for node in nodes {
            guard let label = node.stringValue else {
              localizedMessageLogger.error("BazelResponseLabelAttributeInvalid",
                                           comment: "Bazel response XML element %1$@ should have a valid string value but does not.",
                                           values: node)
              continue
            }
            labelSet.insert(BuildLabel(label))
          }
          return labelSet
        }

        let linkedTargetLabels = try extractLabelsFromXpath("./label[@name='xctest_app']/@value")

        let entry = RuleInfo(label: BuildLabel(ruleLabel),
                             type: ruleType,
                             linkedTargetLabels: linkedTargetLabels)

        infos[entry] = try extractLabelsFromXpath("./rule-input/@name")
      }
      return infos
    } catch let e as NSError {
      localizedMessageLogger.error("BazelResponseXMLParsingFailed",
                                   comment: "Extractor Bazel output failed to be parsed as XML with error %1$@. This may be a Bazel bug or a bad BUILD file.",
                                   values: e.localizedDescription)
      return nil
    }
  }

  private func extractRuleInfosFromBazelXMLOutput(bazelOutput: NSData) -> [RuleInfo]? {
    if let infoMap = extractRuleInfosWithRuleInputsFromBazelXMLOutput(bazelOutput) {
      return [RuleInfo](infoMap.keys)
    }
    return nil
  }
}
