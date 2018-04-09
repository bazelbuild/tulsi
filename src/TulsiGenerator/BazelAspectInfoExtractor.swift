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
final class BazelAspectInfoExtractor: QueuedLogging {
  enum ExtractorError: Error {
    /// Failed to build aspects.
    case buildFailed
    /// Parsing an aspect's output failed with the given debug info.
    case parsingFailed(String)
  }

  /// Prefix to be used by Bazel for the output of the Tulsi aspect.
  private static let SymlinkPrefix = "tulsigen-"
  /// Suffixes used by Bazel when creating output symlinks.
  private static let BazelOutputSymlinks = [
      "bin", "genfiles", "out", "testlogs"].map({ SymlinkPrefix + $0 })

  /// The location of the bazel binary.
  var bazelURL: URL
  /// The location of the Bazel workspace to be examined.
  let workspaceRootURL: URL

  private let bundle: Bundle
  /// Absolute path to the workspace containing the Tulsi aspect bzl file.
  private let aspectWorkspacePath: String
  private let localizedMessageLogger: LocalizedMessageLogger
  private var queuedInfoMessages: [String] = []

  /// Path to the build events JSON file.
  private let buildEventsFilePath: String

  private typealias CompletionHandler = (Process, String) -> Void

  init(bazelURL: URL,
       workspaceRootURL: URL,
       localizedMessageLogger: LocalizedMessageLogger) {
    self.bazelURL = bazelURL
    self.workspaceRootURL = workspaceRootURL
    self.localizedMessageLogger = localizedMessageLogger

    let buildEventsFileName = "build_events_\(getpid()).json"
    self.buildEventsFilePath =
        (NSTemporaryDirectory() as NSString).appendingPathComponent(buildEventsFileName)

    bundle = Bundle(for: type(of: self))

    let workspaceFilePath = bundle.path(forResource: "WORKSPACE", ofType: "")! as NSString
    aspectWorkspacePath = workspaceFilePath.deletingLastPathComponent
  }

  /// Builds a map of RuleEntry instances keyed by their labels with information extracted from the
  /// Bazel workspace for the given set of Bazel targets.
  func extractRuleEntriesForLabels(_ targets: [BuildLabel],
                                   startupOptions: [String] = [],
                                   buildOptions: [String] = [],
                                   useAspectForTestSuites: Bool = true,
                                   projectGenerationOptions: [String] = []) throws -> RuleEntryMap {
    guard !targets.isEmpty else {
      return RuleEntryMap()
    }
    return try extractRuleEntriesUsingBEP(targets,
                                          startupOptions: startupOptions,
                                          buildOptions: buildOptions,
                                          useAspectForTestSuites: useAspectForTestSuites,
                                          projectGenerationOptions: projectGenerationOptions)
  }

  // MARK: - Private methods

  private func extractRuleEntriesUsingBEP(_ targets: [BuildLabel],
                                          startupOptions: [String],
                                          buildOptions: [String],
                                          useAspectForTestSuites: Bool,
                                          projectGenerationOptions: [String]) throws -> RuleEntryMap {
    localizedMessageLogger.infoMessage("Build Events JSON file at \"\(buildEventsFilePath)\"")

    let progressNotifier = ProgressNotifier(name: SourceFileExtraction,
                                            maxValue: targets.count,
                                            indeterminate: false,
                                            suppressStart: true)

    let profilingStart = localizedMessageLogger.startProfiling("extract_source_info",
                                                               message: "Extracting info for \(targets.count) rules")

    let semaphore = DispatchSemaphore(value: 0)
    var extractedEntries = RuleEntryMap()
    var processDebugInfo: String? = nil
    let process = bazelAspectProcessForTargets(targets.map({ $0.value }),
                                               aspect: "tulsi_sources_aspect",
                                               startupOptions: startupOptions,
                                               buildOptions: buildOptions,
                                               useAspectForTestSuites: useAspectForTestSuites,
                                               projectGenerationOptions: projectGenerationOptions,
                                               progressNotifier: progressNotifier) {
                                                (process: Process, debugInfo: String) -> Void in
       defer { semaphore.signal() }
       processDebugInfo = debugInfo
    }

    if let process = process {
      process.currentDirectoryPath = workspaceRootURL.path
      process.launch()
      _ = semaphore.wait(timeout: DispatchTime.distantFuture)

      guard process.terminationStatus == 0 else {
        let debugInfo = processDebugInfo ?? "<No Debug Info>"
        queuedInfoMessages.append(debugInfo)
        localizedMessageLogger.error("BazelInfoExtractionFailed",
                                     comment: "Error message for when a Bazel extractor did not complete successfully. Details are logged separately.",
                                     details: BazelErrorExtractor.firstErrorLinesFromString(debugInfo))
        throw ExtractorError.buildFailed
      }

      let reader = BazelBuildEventsReader(filePath: buildEventsFilePath,
                                          localizedMessageLogger: localizedMessageLogger)
      do {
        let events = try reader.readAllEvents()
        let artifacts = Set(events.flatMap { $0.files.lazy.filter { $0.hasSuffix(".tulsiinfo") } })

        if !artifacts.isEmpty {
          extractedEntries = self.extractRuleEntriesFromArtifacts(artifacts,
                                                                  progressNotifier: progressNotifier)
          try? FileManager.default.removeItem(atPath: buildEventsFilePath)
        } else {
          let debugInfo = processDebugInfo ?? "<No Debug Info>"
          queuedInfoMessages.append(debugInfo)
          self.localizedMessageLogger.error("BazelInfoExtractionFailed",
                                            comment: "Error message for when a Bazel extractor did not complete successfully. Details are logged separately.",
                                            details: BazelErrorExtractor.firstErrorLinesFromString(debugInfo))
          throw ExtractorError.buildFailed
        }
      } catch let e as NSError {
        self.localizedMessageLogger.error("BazelInfoExtractionFailed",
                                          comment: "Error message for when a Bazel extractor did not complete successfully. Details are logged separately.",
                                          details: "Failed to read all build events. Error: \(e.localizedDescription)")
        throw ExtractorError.buildFailed
      }
    }
    localizedMessageLogger.logProfilingEnd(profilingStart)
    return extractedEntries
  }

  // Generates a Process that will run the given aspect against the given Bazel targets, capturing
  // the output data and passing it to the terminationHandler.
  private func bazelAspectProcessForTargets(_ targets: [String],
                                            aspect: String,
                                            startupOptions: [String] = [],
                                            buildOptions: [String] = [],
                                            useAspectForTestSuites: Bool = true,
                                            projectGenerationOptions: [String] = [],
                                            progressNotifier: ProgressNotifier? = nil,
                                            terminationHandler: @escaping CompletionHandler) -> Process? {

    let infoExtractionNotifier = ProgressNotifier(name: WorkspaceInfoExtraction,
                                                  maxValue: 1,
                                                  indeterminate: true)

    infoExtractionNotifier.incrementValue()

    if let progressNotifier = progressNotifier {
      progressNotifier.start()
    }

    let tulsiVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "UNKNOWN"

    var arguments = startupOptions
    arguments.append(contentsOf: [
        "build",
        "-c",
        "dbg",  // The aspect is run in debug mode to match the default Xcode build configuration.
        "--symlink_prefix",  // Generate artifacts without overwriting the normal build symlinks.
        BazelAspectInfoExtractor.SymlinkPrefix,
        "--announce_rc",  // Print the RC files used by this operation.
        "--nocheck_visibility",  // Don't do package visibility enforcement during aspect runs.
        "--show_result=0",  // Don't bother printing the build results.
        "--noshow_loading_progress",  // Don't show Bazel's loading progress.
        "--noshow_progress",  // Don't show Bazel's build progress.
        "--override_repository=tulsi=\(aspectWorkspacePath)",
        "--aspects",
        "@tulsi//tulsi:tulsi_aspects.bzl%\(aspect)",
        "--output_groups=tulsi-info,-_,-default",  // Build only the aspect artifacts.
        "--tool_tag=tulsi_v\(tulsiVersion):generator", // Add a tag for tracking.
        "--build_event_json_file=\(self.buildEventsFilePath)",
        "--noexperimental_build_event_json_file_path_conversion",
    ])
    // Don't replace test_suites with their tests. This allows the Aspect to discover the structure
    // of the test_suite.
    if useAspectForTestSuites {
      arguments.append("--noexpand_test_suites")
    }
    arguments.append(contentsOf: projectGenerationOptions)
    arguments.append(contentsOf: buildOptions)
    arguments.append(contentsOf: targets)

    let process = TulsiProcessRunner.createProcess(bazelURL.path,
                                                   arguments: arguments,
                                                   messageLogger: localizedMessageLogger,
                                                   loggingIdentifier: "bazel_extract_source_info") {
      completionInfo in
        let debugInfoFormatString = NSLocalizedString("DebugInfoForBazelCommand",
                                                      bundle: Bundle(for: type(of: self)),
                                                      comment: "Provides general information about a Bazel failure; a more detailed error may be reported elsewhere. The Bazel command is %1$@, exit code is %2$d, stderr %3$@.")
        let stderr = NSString(data: completionInfo.stderr, encoding: String.Encoding.utf8.rawValue) ?? "<No STDERR>"
        let debugInfo = String(format: debugInfoFormatString,
                               completionInfo.commandlineString,
                               completionInfo.terminationStatus,
                               stderr)

        self.removeGeneratedSymlinks()
        terminationHandler(completionInfo.process, debugInfo)
    }

    return process
  }

  private func removeGeneratedSymlinks() {
    let fileManager = FileManager.default
    for outputSymlink in BazelAspectInfoExtractor.BazelOutputSymlinks {

      let symlinkURL = workspaceRootURL.appendingPathComponent(outputSymlink, isDirectory: true)
      do {
        let attributes = try fileManager.attributesOfItem(atPath: symlinkURL.path)
        guard let type = attributes[FileAttributeKey.type] as? String, type == FileAttributeType.typeSymbolicLink.rawValue else {
          continue
        }
      } catch {
        // Any exceptions are expected to indicate that the file does not exist.
        continue
      }

      do {
        try fileManager.removeItem(at: symlinkURL)
      } catch let e as NSError {
        localizedMessageLogger.infoMessage("Failed to remove symlink at \(symlinkURL). \(e)")
      }
    }
  }

  /// Builds a list of RuleEntry instances using the data in the given set of .tulsiinfo files.
  private func extractRuleEntriesFromArtifacts(_ files: Set<String>,
                                               progressNotifier: ProgressNotifier? = nil) -> RuleEntryMap {
    let fileManager = FileManager.default

    func parseTulsiTargetFile(_ filename: String) throws -> RuleEntry {
      return try autoreleasepool {
        return try parseTulsiTargetFileImpl(filename)
      }
    }

    func parseTulsiTargetFileImpl(_ filename: String) throws -> RuleEntry {
      guard let data = fileManager.contents(atPath: filename) else {
        throw ExtractorError.parsingFailed("The file could not be read")
      }
      guard let dict = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions()) as? [String: AnyObject] else {
        throw ExtractorError.parsingFailed("Contents are not a dictionary")
      }

      func getRequiredField(_ field: String) throws -> String {
        guard let value = dict[field] as? String else {
          throw ExtractorError.parsingFailed("Missing required '\(field)' field")
        }
        return value
      }

      let ruleLabel = try getRequiredField("label")
      let ruleType = try getRequiredField("type")
      let attributes = dict["attr"] as? [String: AnyObject] ?? [:]

      func MakeBazelFileInfos(_ attributeName: String) -> [BazelFileInfo] {
        let infos = dict[attributeName] as? [[String: AnyObject]] ?? []
        var bazelFileInfos = [BazelFileInfo]()
        for info in infos {
          if let pathInfo = BazelFileInfo(info: info as AnyObject?) {
            bazelFileInfos.append(pathInfo)
          }
        }
        return bazelFileInfos
      }

      let artifacts = MakeBazelFileInfos("artifacts")
      var sources = MakeBazelFileInfos("srcs")

      // Appends BazelFileInfo objects to the given array for any info dictionaries representing
      // source code or (potential) source code containers. The directoryArtifacts set is also
      // populated as a side effect.
      var directoryArtifacts = Set<String>()
      func appendGeneratedSourceArtifacts(_ infos: [[String: AnyObject]],
                                          to artifacts: inout [BazelFileInfo]) {
        for info in infos {
          guard let pathInfo = BazelFileInfo(info: info as AnyObject?) else {
            continue
          }
          if pathInfo.isDirectory {
            directoryArtifacts.insert(pathInfo.fullPath)
          } else {
            guard let fileUTI = pathInfo.uti, fileUTI.hasPrefix("sourcecode.") else {
              continue
            }
          }
          artifacts.append(pathInfo)
        }
      }

      let generatedSourceInfos = dict["generated_files"] as? [[String: AnyObject]] ?? []
      appendGeneratedSourceArtifacts(generatedSourceInfos, to: &sources)

      var nonARCSources = MakeBazelFileInfos("non_arc_srcs")
      let generatedNonARCSourceInfos = dict["generated_non_arc_files"] as? [[String: AnyObject]] ?? []
      appendGeneratedSourceArtifacts(generatedNonARCSourceInfos, to: &nonARCSources)

      let includePaths: [RuleEntry.IncludePath]?
      if let includes = dict["includes"] as? [String] {
        includePaths = includes.map() {
          RuleEntry.IncludePath($0, directoryArtifacts.contains($0))
        }
      } else {
        includePaths = nil
      }
      let defines = dict["defines"] as? [String]
      let deps = dict["deps"] as? [String] ?? []
      let dependencyLabels = Set(deps.map({ BuildLabel($0) }))
      let frameworkImports = MakeBazelFileInfos("framework_imports")
      let buildFilePath = dict["build_file"] as? String
      let osDeploymentTarget = dict["os_deployment_target"] as? String
      let secondaryArtifacts = MakeBazelFileInfos("secondary_product_artifacts")
      let swiftLanguageVersion = dict["swift_language_version"] as? String
      let swiftToolchain = dict["swift_toolchain"] as? String
      let swiftTransitiveModules = MakeBazelFileInfos("swift_transitive_modules")
      let objCModuleMaps = MakeBazelFileInfos("objc_module_maps")
      let extensions: Set<BuildLabel>?
      if let extensionList = dict["extensions"] as? [String] {
        extensions = Set(extensionList.map({ BuildLabel($0) }))
      } else {
        extensions = nil
      }
      let bundleID = dict["bundle_id"] as? String
      let bundleName = dict["bundle_name"] as? String
      let productType = dict["product_type"] as? String

      let platformType = dict["platform_type"] as? String

      let targetProductType: PBXTarget.ProductType?

      if let productTypeStr = productType {
        // Better be a type that we support, otherwise it's an error on our end.
        if let actualProductType = PBXTarget.ProductType(rawValue: productTypeStr) {
          targetProductType = actualProductType
        } else {
          throw ExtractorError.parsingFailed("Unsupported product type: \(productTypeStr)")
        }
      } else {
        targetProductType = nil
      }

      var extensionType: String?
      if targetProductType?.isiOSAppExtension ?? false, let infoplistPath = dict["infoplist"] as? String {
        // TODO(b/73349137): This relies on the fact the Plist will be located next to the
        // .tulsiinfo file for the same target. It would be better to get an absolute path to the
        // plist from bazel.
        let plistPath = URL(fileURLWithPath: filename)
          .deletingLastPathComponent()
          .appendingPathComponent(infoplistPath).path
        guard let info = NSDictionary(contentsOfFile: plistPath) else {
          throw ExtractorError.parsingFailed("Unable to load extension plist file: \(plistPath)")
        }

        guard let _extensionType = info.value(forKeyPath: "NSExtension.NSExtensionPointIdentifier") as? String else {
          throw ExtractorError.parsingFailed("Missing NSExtensionPointIdentifier in extension plist: \(plistPath)")
        }

        extensionType = _extensionType
      }

      let ruleEntry = RuleEntry(label: ruleLabel,
                                type: ruleType,
                                attributes: attributes,
                                artifacts: artifacts,
                                sourceFiles: sources,
                                nonARCSourceFiles: nonARCSources,
                                dependencies: dependencyLabels,
                                frameworkImports: frameworkImports,
                                secondaryArtifacts: secondaryArtifacts,
                                extensions: extensions,
                                bundleID: bundleID,
                                bundleName: bundleName,
                                productType: targetProductType,
                                platformType: platformType,
                                osDeploymentTarget: osDeploymentTarget,
                                buildFilePath: buildFilePath,
                                defines: defines,
                                includePaths: includePaths,
                                swiftLanguageVersion: swiftLanguageVersion,
                                swiftToolchain: swiftToolchain,
                                swiftTransitiveModules: swiftTransitiveModules,
                                objCModuleMaps: objCModuleMaps,
                                extensionType: extensionType)
      progressNotifier?.incrementValue()
      return ruleEntry
    }

    let ruleEntryMap = RuleEntryMap(localizedMessageLogger: localizedMessageLogger)
    let semaphore = DispatchSemaphore(value: 1)
    let queue = DispatchQueue(label: "com.google.Tulsi.ruleEntryArtifactExtractor",
                                      attributes: DispatchQueue.Attributes.concurrent)
    var hasErrors = false

    for filename in files {
      queue.async {
        let errorInfo: String
        do {
          let ruleEntry = try parseTulsiTargetFile(filename)
          _ = semaphore.wait(timeout: DispatchTime.distantFuture)
          ruleEntryMap.insert(ruleEntry: ruleEntry)
          semaphore.signal()
          return
        } catch ExtractorError.parsingFailed(let info) {
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
    queue.sync(flags: .barrier, execute: {})

    if hasErrors {
      localizedMessageLogger.error("BazelAspectParsingFailedNotification",
                                   comment: "Error to show as an alert when the output generated by an aspect failed in some way. Details about the failure are available in the message log.")
    }

    return ruleEntryMap
  }

  // MARK: - QueuedLogging

  func logQueuedInfoMessages() {
    guard !self.queuedInfoMessages.isEmpty else {
      return
    }
    localizedMessageLogger.infoMessage("Log of Bazel aspect info output follows:")
    for message in self.queuedInfoMessages {
      localizedMessageLogger.infoMessage(message)
    }
    self.queuedInfoMessages.removeAll()
  }

  var hasQueuedInfoMessages: Bool {
    return !self.queuedInfoMessages.isEmpty
  }
}
