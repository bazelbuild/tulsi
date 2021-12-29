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

  /// The location of the bazel binary.
  var bazelURL: URL
  /// The location of the Bazel workspace to be examined.
  let workspaceRootURL: URL
  /// The execution root URL.
  let executionRootURL: URL
  /// Stores Tulsi-specific Bazel settings.
  let bazelSettingsProvider: BazelSettingsProviderProtocol

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
       executionRootURL: URL,
       bazelSettingsProvider: BazelSettingsProviderProtocol,
       localizedMessageLogger: LocalizedMessageLogger) {
    self.bazelURL = bazelURL
    self.workspaceRootURL = workspaceRootURL
    self.executionRootURL = executionRootURL
    self.bazelSettingsProvider = bazelSettingsProvider
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
                                   compilationMode: String? = nil,
                                   platformConfig: String? = nil,
                                   prioritizeSwift: Bool? = nil,
                                   features: Set<BazelSettingFeature> = []) throws -> RuleEntryMap {
    guard !targets.isEmpty else {
      return RuleEntryMap()
    }

    return try extractRuleEntriesUsingBEP(targets,
                                          startupOptions: startupOptions,
                                          buildOptions: buildOptions,
                                          compilationMode: compilationMode,
                                          platformConfig: platformConfig,
                                          prioritizeSwift: prioritizeSwift,
                                          features: features)
  }

  // MARK: - Private methods

  private func extractRuleEntriesUsingBEP(_ targets: [BuildLabel],
                                          startupOptions: [String],
                                          buildOptions: [String],
                                          compilationMode: String?,
                                          platformConfig: String?,
                                          prioritizeSwift: Bool?,
                                          features: Set<BazelSettingFeature>) throws -> RuleEntryMap {
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
                                               compilationMode: compilationMode,
                                               platformConfig: platformConfig,
                                               prioritizeSwift: prioritizeSwift,
                                               features: features,
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
                                            compilationMode: String?,
                                            platformConfig: String?,
                                            prioritizeSwift: Bool?,
                                            features: Set<BazelSettingFeature>,
                                            progressNotifier: ProgressNotifier? = nil,
                                            terminationHandler: @escaping CompletionHandler) -> Process? {

    let infoExtractionNotifier = ProgressNotifier(name: WorkspaceInfoExtraction,
                                                  maxValue: 1,
                                                  indeterminate: true)

    infoExtractionNotifier.incrementValue()

    if let progressNotifier = progressNotifier {
      progressNotifier.start()
    }

    let hasSwift = prioritizeSwift ?? false
    let isDbg = (compilationMode ?? "dbg") == "dbg"

    let config: PlatformConfiguration
    if let identifier = platformConfig,
       let parsedConfig = PlatformConfiguration(identifier: identifier) {
      config = parsedConfig
    } else {
      config = PlatformConfiguration.defaultConfiguration
    }

    let tulsiFlags = bazelSettingsProvider.tulsiFlags(hasSwift: hasSwift,
                                                      options: nil,
                                                      features: features).getFlags(forDebug: isDbg)
    var arguments = startupOptions
    arguments.append(contentsOf: tulsiFlags.startup)
    arguments.append("build")
    arguments.append(contentsOf: [
        // The following flags control Bazel console output and should not affect Bazel analysis
        // caching.
        "--announce_rc",  // Print the RC files used by this operation.
        "--show_result=0",  // Don't bother printing the build results.
        "--noshow_loading_progress",  // Don't show Bazel's loading progress.
        "--noshow_progress",  // Don't show Bazel's build progress.
        "--symlink_prefix=/",  // Generate artifacts without overwriting the normal build symlinks.
    ])
    arguments.append(contentsOf: buildOptions)
    arguments.append(contentsOf: config.bazelFlags)
    arguments.append(contentsOf: tulsiFlags.build)
    arguments.append(contentsOf: [
        // The following flags are used by Tulsi to identify itself and read build information from
        // Bazel. They should not affect Bazel analysis caching.
        "--tool_tag=tulsi:generator",  // Add a tag for tracking.
        "--build_event_json_file=\(self.buildEventsFilePath)",
        "--noexperimental_build_event_json_file_path_conversion",
        // Don't replace test_suites with their tests. This allows the Aspect to discover the
        // structure of test_suites instead of just the tests they resolve to.
        "--noexpand_test_suites",
        // Don't generate parse headers actions.  They are not needed and would consume memory.
        "--features=-parse_headers",
        // Don't run validation actions during project generation; validation actions could
        // slow down the project generation or fail it.
        // TODO: Switch to --norun_validations when we no longer need to support Bazel 4.
        "--noexperimental_run_validations",
        // The following flags WILL affect Bazel analysis caching.
        // Keep this consistent with bazel_build.py.
        "--aspects",
        "@tulsi//:tulsi/tulsi_aspects.bzl%\(aspect)",
        // Build only the aspect artifacts. We explicitly disable the
        // rules_apple `dsyms` output group since it may trigger a full build
        // and we've seen some folks enabling it in their rc file.
        "--output_groups=tulsi_info,-dsyms",
    ])
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
        terminationHandler(completionInfo.process, debugInfo)
    }

    return process
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
      let objcDefines = dict["objc_defines"] as? [String]
      let swiftDefines = dict["swift_defines"] as? [String]
      let deps = dict["deps"] as? [String] ?? []
      let dependencyLabels = Set(deps.map({ BuildLabel($0) }))
      let testDeps = dict["test_deps"] as? [String] ?? []
      let testDependencyLabels = Set(testDeps.map { BuildLabel($0) })
      let frameworkImports = MakeBazelFileInfos("framework_imports")
      let buildFilePath = dict["build_file"] as? String
      let osDeploymentTarget = dict["os_deployment_target"] as? String
      let secondaryArtifacts = MakeBazelFileInfos("secondary_product_artifacts")
      let swiftLanguageVersion = dict["swift_language_version"] as? String
      let swiftToolchain = dict["swift_toolchain"] as? String
      let swiftTransitiveModules = MakeBazelFileInfos("swift_transitive_modules")
      let objCModuleMaps = MakeBazelFileInfos("objc_module_maps")
      let moduleName = dict["module_name"] as? String
      let extensions: Set<BuildLabel>?
      if let extensionList = dict["extensions"] as? [String] {
        extensions = Set(extensionList.map({ BuildLabel($0) }))
      } else {
        extensions = nil
      }
      let appClips: Set<BuildLabel>?
      if let appClipsList = dict["app_clips"] as? [String] {
        appClips = Set(appClipsList.map({ BuildLabel($0) }))
      } else {
        appClips = nil
      }
      let bundleID = dict["bundle_id"] as? String
      let bundleName = dict["bundle_name"] as? String
      let productType = dict["product_type"] as? String

      let platformType = dict["platform_type"] as? String
      let xcodeVersion = dict["xcode_version"] as? String

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
        let plistPath = executionRootURL.appendingPathComponent(infoplistPath).path
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
                                testDependencies: testDependencyLabels,
                                frameworkImports: frameworkImports,
                                secondaryArtifacts: secondaryArtifacts,
                                extensions: extensions,
                                appClips: appClips,
                                bundleID: bundleID,
                                bundleName: bundleName,
                                productType: targetProductType,
                                platformType: platformType,
                                osDeploymentTarget: osDeploymentTarget,
                                buildFilePath: buildFilePath,
                                objcDefines: objcDefines,
                                swiftDefines: swiftDefines,
                                includePaths: includePaths,
                                swiftLanguageVersion: swiftLanguageVersion,
                                swiftToolchain: swiftToolchain,
                                swiftTransitiveModules: swiftTransitiveModules,
                                objCModuleMaps: objCModuleMaps,
                                moduleName: moduleName,
                                extensionType: extensionType,
                                xcodeVersion: xcodeVersion)
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
