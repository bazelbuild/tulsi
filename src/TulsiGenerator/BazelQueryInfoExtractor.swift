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

  func extractTargetRulesFromProject(project: TulsiProject) -> [RuleInfo] {
    let projectPackages = project.bazelPackages
    guard !projectPackages.isEmpty else {
      return []
    }

    var infos = [RuleInfo]()
    let query = projectPackages.map({ "kind(rule, \($0):all)"}).joinWithSeparator("+")
    let profilingStart = localizedMessageLogger.startProfiling("fetch_rules",
                                                               message: "Fetching rules for packages \(projectPackages)")

    let (_, data, debugInfo) = self.bazelSynchronousQueryTask(query, outputKind: "xml")
    if let entries = self.extractRuleInfosFromBazelXMLOutput(data) {
      infos = entries
    } else {
      localizedMessageLogger.infoMessage(debugInfo)
    }
    localizedMessageLogger.logProfilingEnd(profilingStart)
    return infos
  }

  // MARK: - Private methods

  // Generates an NSTask that will perform a bazel query, capturing the output data and passing it
  // to the terminationHandler.
  private func bazelQueryTask(query: String,
                              outputKind: String? = nil,
                              message: String = "",
                              terminationHandler: CompletionHandler) -> NSTask {
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

    var message = message
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

  private func extractRuleInfosFromBazelXMLOutput(bazelOutput: NSData) -> [RuleInfo]? {
    do {
      var infos = [RuleInfo]()
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

        let entry = RuleInfo(label: BuildLabel(ruleLabel), type: ruleType)
        infos.append(entry)
      }
      return infos
    } catch let e as NSError {
      localizedMessageLogger.error("BazelResponseXMLParsingFailed",
                                   comment: "Extractor Bazel output failed to be parsed as XML with error %1$@. This may be a Bazel bug or a bad BUILD file.",
                                   values: e.localizedDescription)
      return nil
    }
  }
}
