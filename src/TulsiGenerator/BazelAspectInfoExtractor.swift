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


// Provides methods utilizing Bazel aspects to extract information from a workspace.
final class BazelAspectInfoExtractor {
  enum Error: ErrorType {
    /// Parsing an aspect's output failed with the given debug info.
    case ParsingFailed(String)
  }

  /// The location of the bazel binary.
  var bazelURL: NSURL
  /// The location of the Bazel workspace to be examined.
  let workspaceRootURL: NSURL

  /// Fetcher object from which a workspace's package_path may be obtained.
  private let packagePathFetcher: BazelWorkspacePathInfoFetcher

  private let bundle: NSBundle
  // Absolute path to the workspace containing the Tulsi aspect bzl file.
  private let aspectWorkspacePath: String
  // Relative path from aspectWorkspacePath to the actual Tulsi aspect bzl file.
  private let aspectFileWorkspaceRelativePath: String
  private let localizedMessageLogger: LocalizedMessageLogger

  private typealias CompletionHandler = (bazelTask: NSTask,
                                         generatedArtifacts: [String]?,
                                         debugInfo: String) -> Void

  init(bazelURL: NSURL,
       workspaceRootURL: NSURL,
       packagePathFetcher: BazelWorkspacePathInfoFetcher,
       localizedMessageLogger: LocalizedMessageLogger) {
    self.bazelURL = bazelURL
    self.workspaceRootURL = workspaceRootURL
    self.packagePathFetcher = packagePathFetcher
    self.localizedMessageLogger = localizedMessageLogger

    bundle = NSBundle(forClass: self.dynamicType)

    let workspaceFilePath = bundle.pathForResource("WORKSPACE", ofType: "")! as NSString
    aspectWorkspacePath = workspaceFilePath.stringByDeletingLastPathComponent
    let aspectFilePath = bundle.pathForResource("tulsi_aspects",
                                                ofType: "bzl",
                                                inDirectory: "tulsi")!
    let startIndex = aspectFilePath.startIndex.advancedBy(aspectWorkspacePath.characters.count + 1)
    aspectFileWorkspaceRelativePath = aspectFilePath.substringFromIndex(startIndex)
  }

  /// Builds a map of RuleEntry instances keyed by their labels with information extracted from the
  /// Bazel workspace for the given set of Bazel targets.
  func extractRuleEntriesForLabels(targets: [BuildLabel],
                                   startupOptions: [String] = [],
                                   buildOptions: [String] = []) -> [BuildLabel: RuleEntry] {
    guard !targets.isEmpty, let path = workspaceRootURL.path else {
      return [:]
    }

    let progressNotifier = ProgressNotifier(name: SourceFileExtraction,
                                            maxValue: targets.count,
                                            startIndeterminate: true)

    let profilingStart = localizedMessageLogger.startProfiling("extract_source_info",
                                                               message: "Extracting info for \(targets.count) rules")

    let semaphore = dispatch_semaphore_create(0)
    var extractedEntries = [BuildLabel: RuleEntry]()
    let task = bazelAspectTaskForTargets(targets.map({ $0.value }),
                                         aspect: "tulsi_sources_aspect",
                                         startupOptions: startupOptions,
                                         buildOptions: buildOptions) {
      (task: NSTask, generatedArtifacts: [String]?, debugInfo: String) -> Void in
        defer { dispatch_semaphore_signal(semaphore) }
        if task.terminationStatus == 0,
           let artifacts = generatedArtifacts where !artifacts.isEmpty {
          extractedEntries = self.extractRuleEntriesFromArtifacts(artifacts,
                                                                  progressNotifier: progressNotifier)
        } else {
          self.localizedMessageLogger.infoMessage(debugInfo)
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
          self.localizedMessageLogger.error("BazelInfoExtractionFailed",
                                            comment: "Error message for when a Bazel extractor did not complete successfully. Details are logged separately.",
                                            details: errorMessage)
        }
    }

    if let task = task {
      task.currentDirectoryPath = path
      task.launch()
      dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    }
    localizedMessageLogger.logProfilingEnd(profilingStart)

    return extractedEntries
  }

  // MARK: - Private methods

  // Generates an NSTask that will run the given aspect against the given Bazel targets, capturing
  // the output data and passing it to the terminationHandler.
  private func bazelAspectTaskForTargets(targets: [String],
                                         aspect: String,
                                         startupOptions: [String] = [],
                                         buildOptions: [String] = [],
                                         terminationHandler: CompletionHandler) -> NSTask? {
    let workspacePackagePath = packagePathFetcher.getPackagePath()
    let augmentedPackagePath = "\(workspacePackagePath):\(aspectWorkspacePath)"

    var arguments = startupOptions
    arguments.appendContentsOf([
        "build",
        "--show_result=0",  // Don't bother printing the build results.
        "--no_show_loading_progress",  // Don't show Bazel's loading progress.
        "--no_show_progress",  // Don't show Bazel's build progress.
        "--package_path=\(augmentedPackagePath)",
        "--aspects",
        "//\(aspectFileWorkspaceRelativePath)%\(aspect)",
        "--output_groups=tulsi-info,-_,-default",  // Build only the aspect artifacts.
        "--experimental_show_artifacts"  // Print the artifacts generated by the aspect.
    ])
    arguments.appendContentsOf(buildOptions)
    arguments.appendContentsOf(targets)
    localizedMessageLogger.infoMessage("Running \(bazelURL.path!) with arguments: \(arguments)")

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

        let artifacts = BazelAspectInfoExtractor.extractBuildArtifactsFromOutput(stderr)
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

  /// Builds a list of RuleEntry instances using the data in the given set of .tulsiinfo files.
  private func extractRuleEntriesFromArtifacts(files: [String],
                                               progressNotifier: ProgressNotifier? = nil) -> [BuildLabel: RuleEntry] {
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
      let attributes = dict["attr"] as? [String: AnyObject] ?? [:]
      let sourceInfos = dict["srcs"] as? [[String: AnyObject]] ?? []
      var sources = [BazelFileInfo]()
      for info in sourceInfos {
        if let pathInfo = BazelFileInfo(info: info) {
          sources.append(pathInfo)
        }
      }
      let generatedSourceInfos = dict["generated_files"] as? [[String: AnyObject]] ?? []
      for info in generatedSourceInfos {
        guard let pathInfo = BazelFileInfo(info: info),
                  fileUTI = pathInfo.uti
              where fileUTI.hasPrefix("sourcecode.") else {
          continue
        }
        sources.append(pathInfo)
      }
      let generatedIncludePaths = dict["generated_includes"] as? [String]
      let dependencies = dict["deps"] as? [String] ?? []
      let buildFilePath = dict["build_file"] as? String

      let ruleEntry = RuleEntry(label: ruleLabel,
                                type: ruleType,
                                attributes: attributes,
                                sourceFiles: sources,
                                dependencies: Set<String>(dependencies),
                                buildFilePath: buildFilePath,
                                generatedIncludePaths: generatedIncludePaths)
      progressNotifier?.incrementValue()
      return ruleEntry
    }

    var ruleMap = [BuildLabel: RuleEntry]()
    let semaphore = dispatch_semaphore_create(1)
    let queue = dispatch_queue_create("com.google.Tulsi.ruleEntryArtifactExtractor",
                                      DISPATCH_QUEUE_CONCURRENT)
    var hasErrors = false

    for filename in files {
      dispatch_async(queue) {
        let errorInfo: String
        do {
          let ruleEntry = try parseTulsiTargetFile(filename)
          dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
          ruleMap[ruleEntry.label] = ruleEntry
          dispatch_semaphore_signal(semaphore)
          return
        } catch Error.ParsingFailed(let info) {
          errorInfo = info
        } catch let e as NSError {
          errorInfo = e.localizedDescription
        } catch {
          errorInfo = "Unexpected exception"
        }
        self.localizedMessageLogger.warning("BazelAspectSupportedTargetParsingFailed",
                                            comment: "Error to show when tulsi_supported_targets_aspect produced data that could not be parsed. The artifact filename is in %1$@, additional information is in %2$@.",
                                            values: filename, errorInfo)
        hasErrors = true
      }
    }

    // Wait for everything to be processed.
    dispatch_barrier_sync(queue) {}

    if hasErrors {
      localizedMessageLogger.error("BazelAspectParsingFailedNotification",
                                   comment: "Error to show as an alert when the output generated by an aspect failed in some way. Details about the failure are available in the message log.")
    }

    return ruleMap
  }
}
