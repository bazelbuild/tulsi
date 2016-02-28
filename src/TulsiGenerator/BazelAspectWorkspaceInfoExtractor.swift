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


// Concrete extractor that utilizes Bazel aspects to extract information from a workspace.
final class BazelAspectWorkspaceInfoExtractor: WorkspaceInfoExtractorProtocol, LabelResolverProtocol {
  enum Error: ErrorType {
    /// Parsing an aspect's output failed with the given debug info.
    case ParsingFailed(String)
  }

  /// The location of the bazel binary.
  var bazelURL: NSURL
  /// The location of the Bazel workspace to be examined.
  let workspaceRootURL: NSURL

  /// Additional startup options for the Bazel aspect invocations.
  let bazelStartupOptions: [String]
  /// Additional options for the Bazel "build" aspect invocation.
  let bazelBuildOptions: [String]

  /// Fetcher object from which a workspace's package_path may be obtained.
  private let packagePathFetcher: WorkspacePackagePathFetcher

  private let bundle: NSBundle
  // Absolute path to the workspace containing the Tulsi aspect bzl file.
  private let aspectWorkspacePath: String
  // Relative path from aspectWorkspacePath to the actual Tulsi aspect bzl file.
  private let aspectFileWorkspaceRelativePath: String
  private let localizedMessageLogger: LocalizedMessageLogger

  static let debugInfoFormatString: String = {
    NSLocalizedString("DebugInfoForBazelCommand",
                      bundle: NSBundle(forClass: BazelAspectWorkspaceInfoExtractor.self),
                      comment: "Provides general information about a Bazel failure; a more detailed error may be reported elsewhere. The Bazel command is %1$@, exit code is %2$d, stderr %3$@.")
  }()

  private typealias CompletionHandler = (bazelTask: NSTask,
                                         generatedArtifacts: [String]?,
                                         debugInfo: String) -> Void

  static func debugInfoForTaskCompletion(completionInfo: TaskRunner.CompletionInfo) -> String {
    let stderr = NSString(data: completionInfo.stderr, encoding: NSUTF8StringEncoding)
    return String(format: debugInfoFormatString,
                  completionInfo.commandlineString,
                  completionInfo.terminationStatus,
                  stderr ?? "<No STDERR>")
  }

  init(bazelURL: NSURL,
       workspaceRootURL: NSURL,
       localizedMessageLogger: LocalizedMessageLogger,
       bazelStartupOptions: [String] = [],
       bazelBuildOptions: [String] = []) {
    self.bazelURL = bazelURL
    self.bazelStartupOptions = bazelStartupOptions
    self.bazelBuildOptions = bazelBuildOptions
    self.workspaceRootURL = workspaceRootURL
    self.localizedMessageLogger = localizedMessageLogger
    self.packagePathFetcher = WorkspacePackagePathFetcher(bazelURL: bazelURL,
                                                          workspaceRootURL: workspaceRootURL,
                                                          localizedMessageLogger: localizedMessageLogger)
    bundle = NSBundle(forClass: self.dynamicType)

    let workspaceFilePath = bundle.pathForResource("WORKSPACE", ofType: "")! as NSString
    aspectWorkspacePath = workspaceFilePath.stringByDeletingLastPathComponent
    let aspectFilePath = bundle.pathForResource("tulsi_aspects",
                                                ofType: "bzl",
                                                inDirectory: "tulsi")!
    let startIndex = aspectFilePath.startIndex.advancedBy(aspectWorkspacePath.characters.count + 1)
    aspectFileWorkspaceRelativePath = aspectFilePath.substringFromIndex(startIndex)
  }

  // MARK: - WorkspaceInfoExtractorProtocol

  func extractTargetRulesFromProject(project: TulsiProject) -> [RuleEntry] {
    let projectPackages = project.bazelPackages
    guard !projectPackages.isEmpty, let path = workspaceRootURL.path else {
      return []
    }

    let profilingStart = localizedMessageLogger.startProfiling("fetch_rules",
                                                               message: "Fetching rules for packages \(projectPackages)")
    // TODO(abaire): Figure out multiple package support.
    let semaphore = dispatch_semaphore_create(0)
    var ruleEntries = [RuleEntry]()
    let task = bazelAspectTaskForTarget("\(projectPackages.first!):all",
                                        aspect: "tulsi_supported_targets_aspect") {
      (task: NSTask, generatedArtifacts: [String]?, debugInfo: String) -> Void in
        defer{ dispatch_semaphore_signal(semaphore) }
        if let artifacts = generatedArtifacts {
          ruleEntries = self.extractRuleEntriesFromArtifacts(artifacts)
        } else {
          self.localizedMessageLogger.error("BazelAspectFailed",
                                            comment: "Error message for when a Bazel aspect did not complete successfully.")
          self.localizedMessageLogger.infoMessage(debugInfo)
        }
    }

    if let task = task {
      task.currentDirectoryPath = path
      task.launch()
      dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    }
    localizedMessageLogger.logProfilingEnd(profilingStart)
    return ruleEntries
  }

  func extractSourceRulesForRuleEntries(ruleEntries: [RuleEntry]) -> [RuleEntry] {
    assertionFailure("TODO(abaire): Implement")
    return []
  }

  func extractSourceFilePathsForSourceRules(ruleEntries: [RuleEntry]) -> [RuleEntry:[String]] {
    assertionFailure("TODO(abaire): Implement")
    return [:]
  }

  func extractExplicitIncludePathsForRuleEntries(ruleEntries: [RuleEntry]) -> Set<String>? {
    assertionFailure("TODO(abaire): Implement")
    return nil
  }

  func extractDefinesForRuleEntries(ruleEntries: [RuleEntry]) -> Set<String>? {
    assertionFailure("TODO(abaire): Implement")
    return nil
  }

  func ruleEntriesForLabels(labels: [String]) -> [String:RuleEntry] {
    assertionFailure("TODO(abaire): Implement")
    return [:]
  }

  // MARK: - LabelResolverProtocol

  func resolveFilesForLabels(labels: [String]) -> [String:BazelFileTarget?]? {
    assertionFailure("TODO(abaire): Implement")
    return nil
  }

  // MARK: - Private methods

  // Generates an NSTask that will run the given aspect against the given Bazel target, capturing
  // the output data and passing it to the terminationHandler.
  private func bazelAspectTaskForTarget(target: String,
                                        aspect: String,
                                        var message: String = "",
                                        terminationHandler: CompletionHandler) -> NSTask? {
    let workspacePackagePath = packagePathFetcher.getPackagePath()
    let augmentedPackagePath = "\(workspacePackagePath):\(aspectWorkspacePath)"

    var arguments = bazelStartupOptions
    arguments.appendContentsOf([
        "build",
        "--keep_going",  // Continue as much as possible after errors.
        "--show_result=0",  // Don't bother printing the build results.
        "--no_show_loading_progress",  // Don't show Bazel's loading progress.
        "--no_show_progress",  // Don't show Bazel's build progress.
        "--package_path=\(augmentedPackagePath)",
        target,
        "--aspects",
        "//\(aspectFileWorkspaceRelativePath)%\(aspect)",
        "--output_groups=tulsi-info,-_,-default",  // Build only the aspect artifacts.
        "--experimental_show_artifacts"  // Print the artifacts generated by the aspect.
    ])
    arguments.appendContentsOf(bazelBuildOptions)

    if message != "" {
      message = "\(message)\n"
    }
    localizedMessageLogger.infoMessage("\(message)Running bazel command with arguments: \(arguments)")

    let task = TaskRunner.standardRunner().createTask(bazelURL.path!, arguments: arguments) {
      completionInfo in
        let debugInfoFormatString = NSLocalizedString("DebugInfoForBazelCommand",
                                                      bundle: NSBundle(forClass: self.dynamicType),
                                                      comment: "Provides general information about a Bazel failure; a more detailed error may be reported elsewhere. The Bazel command is %1$@, exit code is %2$d, stderr %3$@.")
        let stderr = NSString(data: completionInfo.stderr, encoding: NSUTF8StringEncoding) ?? "<No STDERR>"
        let debugInfo = String(format: debugInfoFormatString,
                               completionInfo.commandlineString,
                               completionInfo.terminationStatus,
                               stderr)

        let artifacts = BazelAspectWorkspaceInfoExtractor.extractBuildArtifactsFromOutput(stderr)
        terminationHandler(bazelTask: completionInfo.task,
                           generatedArtifacts: artifacts,
                           debugInfo: debugInfo)
    }

    return task
  }

  // Parses Bazel stderr for "Build artifacts:" followed by >>>(artifact_path). This is a hacky and
  // hopefully a temporary solution (based on --experimental_show_artifacts).
  private static func extractBuildArtifactsFromOutput(output: NSString) -> [String]? {
    let lines = output.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())

    let splitLines = lines.split("Build artifacts:")
    if splitLines.count < 2 {
      return nil
    }
    assert(splitLines.count == 2, "Unexpectedly found multiple 'Build artifacts:' lines.")

    var artifacts = [String]()
    for l: String in splitLines[1] {
      if l.hasPrefix(">>>") {
        artifacts.append(l.substringFromIndex(l.startIndex.advancedBy(3)))
      }
    }

    return artifacts
  }

  /// Builds a list of RuleEntry instances using the data in the given set of .tulsitarget files.
  private func extractRuleEntriesFromArtifacts(files: [String]) -> [RuleEntry] {
    let fileManager = NSFileManager.defaultManager()

    func parseTulsiTargetFile(filename: String) throws -> RuleEntry {
      guard let data = fileManager.contentsAtPath(filename) else {
        throw Error.ParsingFailed("The file could not be read")
      }
      guard let dict = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) as? [String: AnyObject] else {
        throw Error.ParsingFailed("Contents are not a dictionary")
      }

      func getRequiredField(field: String) throws -> String {
        guard let value = dict[field] as? String else {
          throw Error.ParsingFailed("Missing required '\(field)' field")
        }
        return value
      }

      let ruleLabel = try getRequiredField("label")
      let ruleType = try getRequiredField("type")
      let attributes = dict["attributes"] as? [String: String] ?? [:]
      return RuleEntry(label: BuildLabel(ruleLabel), type: ruleType, attributes: attributes)
    }

    var ruleEntries = [RuleEntry]()
    let semaphore = dispatch_semaphore_create(1)
    let queue = dispatch_queue_create("com.google.Tulsi.ruleEntryArtifactExtractor",
                                      DISPATCH_QUEUE_CONCURRENT)
    for filename in files {
      dispatch_async(queue) {
        let errorInfo: String
        do {
          let ruleEntry = try parseTulsiTargetFile(filename)
          dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
          ruleEntries.append(ruleEntry)
          dispatch_semaphore_signal(semaphore)
          return
        } catch Error.ParsingFailed(let info) {
          errorInfo = info
        } catch let e as NSError {
          errorInfo = e.localizedDescription
        } catch {
          errorInfo = "Unexpected exception"
        }
        self.localizedMessageLogger.error("BazelAspectSupportedTargetParsingFailed",
                                          comment: "Error to show when tulsi_supported_targets_aspect produced data that could not be parsed. The artifact filename is in %1$@, additional information is in %2$@.",
                                          values: filename, errorInfo)
      }
    }

    // Wait for everything to be processed.
    dispatch_barrier_sync(queue) {}
    return ruleEntries
  }
}


/// Handles fetching of a package_path for a Bazel workspace.
class WorkspacePackagePathFetcher {
  /// The Bazel package_path as defined by the target workspace.
  private var packagePath: String? = nil

  /// The location of the bazel binary.
  private let bazelURL: NSURL
  /// The location of the Bazel workspace to be examined.
  private let workspaceRootURL: NSURL
  private let localizedMessageLogger: LocalizedMessageLogger
  private let semaphore: dispatch_semaphore_t

  init(bazelURL: NSURL, workspaceRootURL: NSURL, localizedMessageLogger: LocalizedMessageLogger) {
    self.bazelURL = bazelURL
    self.workspaceRootURL = workspaceRootURL
    self.localizedMessageLogger = localizedMessageLogger

    semaphore = dispatch_semaphore_create(0)
    fetchWorkspacePackagePath()
  }

  /// Returns the package_path for this fetcher's workspace, blocking until it is available.
  func getPackagePath() -> String {
    if let packagePath = packagePath { return packagePath }
    waitForCompletion()
    return packagePath!
  }

  // MARK: - Private methods

  // Waits for the workspace fetcher to signal the
  private func waitForCompletion() {
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    dispatch_semaphore_signal(semaphore)
  }

  // Fetches Bazel package_path info from the registered workspace URL.
  private func fetchWorkspacePackagePath() {
    let profilingStart = localizedMessageLogger.startProfiling("get_package_path",
                                                               message: "Fetching bazel package_path info")
    let task = TaskRunner.standardRunner().createTask(bazelURL.path!,
                                                      arguments: ["info", "package_path"]) {
      completionInfo in
        defer {
          self.localizedMessageLogger.logProfilingEnd(profilingStart)
          dispatch_semaphore_signal(self.semaphore)
        }
        if completionInfo.task.terminationStatus == 0 {
          if let stdout = NSString(data: completionInfo.stdout, encoding: NSUTF8StringEncoding) {
            self.packagePath = stdout.stringByTrimmingCharactersInSet(NSCharacterSet.newlineCharacterSet()) as String
            return
          }
        }

        self.packagePath = ""
        self.localizedMessageLogger.error("BazelWorkspaceInfoQueryFailed",
                                          comment: "Extracting package_path info from bazel failed. The exit code is %1$d.",
                                          values: completionInfo.task.terminationStatus)
        let debugInfo = BazelAspectWorkspaceInfoExtractor.debugInfoForTaskCompletion(completionInfo)
        self.localizedMessageLogger.infoMessage(debugInfo)
    }
    task.currentDirectoryPath = workspaceRootURL.path!
    task.launch()
  }
}
