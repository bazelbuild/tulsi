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


// Concrete extractor that utilizes Bazel query (http://bazel.build/docs/query.html) and aspects to
// extract information from a workspace.
final class BazelWorkspaceInfoExtractor: BazelWorkspaceInfoExtractorProtocol {
  var bazelURL: URL {
    get { return queryExtractor.bazelURL as URL }
    set {
      queryExtractor.bazelURL = newValue
      aspectExtractor.bazelURL = newValue
    }
  }

  /// Returns the workspace relative path to the bazel bin symlink. Note that this may block.
  var bazelBinPath: String {
    return workspacePathInfoFetcher.getBazelBinPath()
  }

  /// Returns the absolute path to the execution root for this Bazel workspace. This may block.
  var bazelExecutionRoot: String {
    return workspacePathInfoFetcher.getExecutionRoot()
  }

  /// Returns the absolute path to the output base for this Bazel workspace. This may block.
  var bazelOutputBase: String {
    return workspacePathInfoFetcher.getOutputBase()
  }

  /// Bazel settings provider for all invocations.
  let bazelSettingsProvider: BazelSettingsProviderProtocol

  /// Bazel workspace root URL.
  let workspaceRootURL: URL

  /// Fetcher object from which a workspace's path info may be obtained.
  private let workspacePathInfoFetcher: BazelWorkspacePathInfoFetcher

  private let aspectExtractor: BazelAspectInfoExtractor
  private let queryExtractor: BazelQueryInfoExtractor

  // Cache of all RuleEntry instances loaded for the associated project.
  private var ruleEntryCache = RuleEntryMap()

  init(bazelURL: URL, workspaceRootURL: URL, localizedMessageLogger: LocalizedMessageLogger) {
    let universalFlags: BazelFlags
    // Install to ~/Library/Application Support when not running inside a test.
    if let applicationSupport = ApplicationSupport() {
      let tulsiVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "UNKNOWN"
      let aspectPath = try! applicationSupport.copyTulsiAspectFiles(tulsiVersion: tulsiVersion)
      universalFlags = BazelFlags(
        // TODO(tulsi-team): See if we can avoid using --override_repository.
        build: ["--override_repository=tulsi=\(aspectPath)"]
      )
    } else {  // Running inside a test, just refer to the files directly from TulsiGenerator.
      let bundle = Bundle(for: type(of: self))
      let bazelWorkspace =
        bundle.url(forResource: "WORKSPACE", withExtension: nil)!.deletingLastPathComponent()
      universalFlags = BazelFlags(build: ["--override_repository=tulsi=\(bazelWorkspace.path)"])
    }

    bazelSettingsProvider = BazelSettingsProvider(universalFlags: universalFlags)
    workspacePathInfoFetcher = BazelWorkspacePathInfoFetcher(bazelURL: bazelURL,
                                                             workspaceRootURL: workspaceRootURL,
                                                             bazelUniversalFlags: universalFlags,
                                                             localizedMessageLogger: localizedMessageLogger)

    let executionRootURL =  URL(fileURLWithPath: workspacePathInfoFetcher.getExecutionRoot(),
                                isDirectory: false)
    aspectExtractor = BazelAspectInfoExtractor(bazelURL: bazelURL,
                                               workspaceRootURL: workspaceRootURL,
                                               executionRootURL: executionRootURL,
                                               bazelSettingsProvider: bazelSettingsProvider,
                                               localizedMessageLogger: localizedMessageLogger)
    queryExtractor = BazelQueryInfoExtractor(bazelURL: bazelURL,
                                             workspaceRootURL: workspaceRootURL,
                                             bazelUniversalFlags: universalFlags,
                                             localizedMessageLogger: localizedMessageLogger)
    self.workspaceRootURL = workspaceRootURL
  }

  // MARK: - BazelWorkspaceInfoExtractorProtocol

  func extractRuleInfoFromProject(_ project: TulsiProject) -> [RuleInfo] {
    return queryExtractor.extractTargetRulesFromPackages(project.bazelPackages)
  }

  func ruleEntriesForLabels(_ labels: [BuildLabel],
                            startupOptions: TulsiOption,
                            extraStartupOptions: TulsiOption,
                            buildOptions: TulsiOption,
                            compilationModeOption: TulsiOption,
                            platformConfigOption: TulsiOption,
                            prioritizeSwiftOption: TulsiOption,
                            use64BitWatchSimulatorOption: TulsiOption,
                            features: Set<BazelSettingFeature>) throws -> RuleEntryMap {
    func isLabelMissing(_ label: BuildLabel) -> Bool {
      return !ruleEntryCache.hasAnyRuleEntry(withBuildLabel: label)
    }
    let missingLabels = labels.filter(isLabelMissing)
    if missingLabels.isEmpty { return ruleEntryCache }

    let commandLineSplitter = CommandLineSplitter()
    func splitOptionString(_ options: String?) -> [String] {
      guard let options = options else { return [] }
      return commandLineSplitter.splitCommandLine(options) ?? []
    }

    let startupOptions = splitOptionString(startupOptions.commonValue) + splitOptionString(extraStartupOptions.commonValue)
    let buildOptions = splitOptionString(buildOptions.commonValue)
    let compilationMode = compilationModeOption.commonValue
    let platformConfig = platformConfigOption.commonValue
    let prioritizeSwift = prioritizeSwiftOption.commonValueAsBool

    if let use64BitWatchSimulatorOption = use64BitWatchSimulatorOption.commonValueAsBool {
      PlatformConfiguration.use64BitWatchSimulator = use64BitWatchSimulatorOption
    }

    do {
      let ruleEntryMap =
        try aspectExtractor.extractRuleEntriesForLabels(labels,
                                                        startupOptions: startupOptions,
                                                        buildOptions: buildOptions,
                                                        compilationMode: compilationMode,
                                                        platformConfig: platformConfig,
                                                        prioritizeSwift: prioritizeSwift,
                                                        features: features)
      ruleEntryCache = RuleEntryMap(ruleEntryMap)
    } catch BazelAspectInfoExtractor.ExtractorError.buildFailed {
      throw BazelWorkspaceInfoExtractorError.aspectExtractorFailed("Bazel aspects could not be built.")
    }

    return ruleEntryCache
  }

  func extractBuildfiles<T: Collection>(_ forTargets: T) -> Set<BuildLabel> where T.Iterator.Element == BuildLabel {
    return queryExtractor.extractBuildfiles(forTargets)
  }

  func logQueuedInfoMessages() {
    queryExtractor.logQueuedInfoMessages()
    aspectExtractor.logQueuedInfoMessages()
  }

  func hasQueuedInfoMessages() -> Bool {
    return aspectExtractor.hasQueuedInfoMessages || queryExtractor.hasQueuedInfoMessages
  }
}
