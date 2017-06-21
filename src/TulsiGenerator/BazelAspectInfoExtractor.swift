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
  enum ExtractorError: Error {
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
  // Absolute path to the workspace containing the Tulsi aspect bzl file.
  private let aspectWorkspacePath: String
  private let localizedMessageLogger: LocalizedMessageLogger

  private typealias CompletionHandler = (Process, [String]?, String) -> Void

  init(bazelURL: URL,
       workspaceRootURL: URL,
       localizedMessageLogger: LocalizedMessageLogger) {
    self.bazelURL = bazelURL
    self.workspaceRootURL = workspaceRootURL
    self.localizedMessageLogger = localizedMessageLogger

    bundle = Bundle(for: type(of: self))

    let workspaceFilePath = bundle.path(forResource: "WORKSPACE", ofType: "")! as NSString
    aspectWorkspacePath = workspaceFilePath.deletingLastPathComponent
  }

  /// Builds a map of RuleEntry instances keyed by their labels with information extracted from the
  /// Bazel workspace for the given set of Bazel targets.
  func extractRuleEntriesForLabels(_ targets: [BuildLabel],
                                   startupOptions: [String] = [],
                                   buildOptions: [String] = []) -> [BuildLabel: RuleEntry] {
    guard !targets.isEmpty else {
      return [:]
    }

    let progressNotifier = ProgressNotifier(name: SourceFileExtraction,
                                            maxValue: targets.count,
                                            indeterminate: false,
                                            suppressStart: true)

    let profilingStart = localizedMessageLogger.startProfiling("extract_source_info",
                                                               message: "Extracting info for \(targets.count) rules")

    let semaphore = DispatchSemaphore(value: 0)
    var extractedEntries = [BuildLabel: RuleEntry]()
    let task = bazelAspectTaskForTargets(targets.map({ $0.value }),
                                         aspect: "tulsi_sources_aspect",
                                         startupOptions: startupOptions,
                                         buildOptions: buildOptions,
                                         progressNotifier: progressNotifier) {
      (task: Process, generatedArtifacts: [String]?, debugInfo: String) -> Void in
        defer { semaphore.signal() }
        let artifacts = generatedArtifacts?.filter { $0.hasSuffix(".tulsiinfo") }

        if task.terminationStatus == 0,
          let artifacts = artifacts, !artifacts.isEmpty {
          extractedEntries = self.extractRuleEntriesFromArtifacts(artifacts,
                                                                  progressNotifier: progressNotifier)
        } else {
          self.localizedMessageLogger.infoMessage(debugInfo)
          self.localizedMessageLogger.error("BazelInfoExtractionFailed",
                                            comment: "Error message for when a Bazel extractor did not complete successfully. Details are logged separately.",
                                            details: BazelErrorExtractor.firstErrorLinesFromString(debugInfo))
        }
    }

    if let task = task {
      task.currentDirectoryPath = workspaceRootURL.path
      task.launch()
      _ = semaphore.wait(timeout: DispatchTime.distantFuture)
    }
    localizedMessageLogger.logProfilingEnd(profilingStart)

    return extractedEntries
  }

  // MARK: - Private methods

  // Generates an NSTask that will run the given aspect against the given Bazel targets, capturing
  // the output data and passing it to the terminationHandler.
  private func bazelAspectTaskForTargets(_ targets: [String],
                                         aspect: String,
                                         startupOptions: [String] = [],
                                         buildOptions: [String] = [],
                                         progressNotifier: ProgressNotifier? = nil,
                                         terminationHandler: @escaping CompletionHandler) -> Process? {

    let infoExtractionNotifier = ProgressNotifier(name: WorkspaceInfoExtraction,
                                                  maxValue: 1,
                                                  indeterminate: true)

    infoExtractionNotifier.incrementValue()

    if let progressNotifier = progressNotifier {
      progressNotifier.start()
    }

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
        "--experimental_show_artifacts",  // Print the artifacts generated by the aspect.
    ])
    arguments.append(contentsOf: buildOptions)
    arguments.append(contentsOf: targets)
    localizedMessageLogger.infoMessage("Running \(bazelURL.path) with arguments: \(arguments)")

    let task = TulsiTaskRunner.createTask(bazelURL.path, arguments: arguments) {
      completionInfo in
        let debugInfoFormatString = NSLocalizedString("DebugInfoForBazelCommand",
                                                      bundle: Bundle(for: type(of: self)),
                                                      comment: "Provides general information about a Bazel failure; a more detailed error may be reported elsewhere. The Bazel command is %1$@, exit code is %2$d, stderr %3$@.")
        let stderr = NSString(data: completionInfo.stderr, encoding: String.Encoding.utf8.rawValue) ?? "<No STDERR>"
        let debugInfo = String(format: debugInfoFormatString,
                               completionInfo.commandlineString,
                               completionInfo.terminationStatus,
                               stderr)

        let artifacts = BazelAspectInfoExtractor.extractBuildArtifactsFromOutput(stderr)
        self.removeGeneratedSymlinks()
        terminationHandler(completionInfo.task, artifacts, debugInfo)
    }

    return task
  }

  // Parses Bazel stderr for "Build artifacts:" followed by >>>(artifact_path). This is a hacky and
  // hopefully a temporary solution (based on --experimental_show_artifacts).
  private static func extractBuildArtifactsFromOutput(_ output: NSString) -> [String]? {
    let lines = output.components(separatedBy: CharacterSet.newlines)

    let splitLines = lines.split(separator: "Build artifacts:")
    if splitLines.count < 2 {
      return nil
    }
    assert(splitLines.count == 2, "Unexpectedly found multiple 'Build artifacts:' lines.")

    var artifacts = [String]()
    for l: String in splitLines[1] {
      if l.hasPrefix(">>>") {
        artifacts.append(l.substring(from: l.characters.index(l.startIndex, offsetBy: 3)))
      }
    }

    return artifacts
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
  private func extractRuleEntriesFromArtifacts(_ files: [String],
                                               progressNotifier: ProgressNotifier? = nil) -> [BuildLabel: RuleEntry] {
    let fileManager = FileManager.default

    func parseTulsiTargetFile(_ filename: String) throws -> RuleEntry {
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

      let generatedIncludePaths: [RuleEntry.IncludePath]?
      if let includes = dict["generated_includes"] as? [String] {
        generatedIncludePaths = includes.map() {
          RuleEntry.IncludePath($0, directoryArtifacts.contains($0))
        }
      } else {
        generatedIncludePaths = nil
      }
      let dependencies = Set(dict["deps"] as? [String] ?? [])
      let frameworkImports = MakeBazelFileInfos("framework_imports")
      let buildFilePath = dict["build_file"] as? String
      let iPhoneOSDeploymentTarget = dict["iphoneos_deployment_target"] as? String
      let macOSDeploymentTarget = dict["macos_deployment_target"] as? String
      let tvOSDeploymentTarget = dict["tvos_deployment_target"] as? String
      let watchOSDeploymentTarget = dict["watchos_deployment_target"] as? String
      let implicitIPATarget: BuildLabel?
      if let ipaLabel = dict["ipa_output_label"] as? String {
        implicitIPATarget = BuildLabel(ipaLabel)
      } else {
        implicitIPATarget = nil
      }
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
      let extensionBundleID = dict["ext_bundle_id"] as? String

      var extensionType: String?
      if ruleType == "ios_extension", let infoplistPath = dict["infoplist"] as? String {
        // TODO(dmishe): This relies on the fact the Plist will be located next to the .tulsiinfo
        // file for the same target. It would be better to get an absolute path to the plist from
        // bazel.
        let plistPath = URL(fileURLWithPath: filename)
            .deletingLastPathComponent()
            .appendingPathComponent(infoplistPath).path
        guard let info = NSDictionary(contentsOfFile: plistPath) else {
          throw ExtractorError.parsingFailed("Unable to load ios_extension plist file: \(plistPath)")
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
                                dependencies: dependencies,
                                frameworkImports: frameworkImports,
                                secondaryArtifacts: secondaryArtifacts,
                                extensions: extensions,
                                bundleID: bundleID,
                                extensionBundleID: extensionBundleID,
                                iPhoneOSDeploymentTarget: iPhoneOSDeploymentTarget,
                                macOSDeploymentTarget: macOSDeploymentTarget,
                                tvOSDeploymentTarget: tvOSDeploymentTarget,
                                watchOSDeploymentTarget: watchOSDeploymentTarget,
                                buildFilePath: buildFilePath,
                                generatedIncludePaths: generatedIncludePaths,
                                swiftLanguageVersion: swiftLanguageVersion,
                                swiftToolchain: swiftToolchain,
                                swiftTransitiveModules: swiftTransitiveModules,
                                objCModuleMaps: objCModuleMaps,
                                implicitIPATarget: implicitIPATarget,
                                extensionType: extensionType)
      progressNotifier?.incrementValue()
      return ruleEntry
    }

    var ruleMap = [BuildLabel: RuleEntry]()
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
          ruleMap[ruleEntry.label] = ruleEntry
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

    return ruleMap
  }
}
