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
// TODO(abaire): Add link to aspect documentation when it becomes available.
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

  /// Fetcher object from which a workspace's path info may be obtained.
  private let workspacePathInfoFetcher: BazelWorkspacePathInfoFetcher

  private let aspectExtractor: BazelAspectInfoExtractor
  private let queryExtractor: BazelQueryInfoExtractor

  // Cache of all RuleEntry instances loaded for the associated project.
  private var ruleEntryCache = [BuildLabel: RuleEntry]()
  // The set of labels for which a test_suite query has been run (to prevent duplicate queries).
  private var attemptedTestSuiteLabels = Set<BuildLabel>()

  init(bazelURL: URL, workspaceRootURL: URL, localizedMessageLogger: LocalizedMessageLogger) {

    workspacePathInfoFetcher = BazelWorkspacePathInfoFetcher(bazelURL: bazelURL,
                                                             workspaceRootURL: workspaceRootURL,
                                                             localizedMessageLogger: localizedMessageLogger)
    aspectExtractor = BazelAspectInfoExtractor(bazelURL: bazelURL,
                                               workspaceRootURL: workspaceRootURL,
                                               localizedMessageLogger: localizedMessageLogger)
    queryExtractor = BazelQueryInfoExtractor(bazelURL: bazelURL,
                                             workspaceRootURL: workspaceRootURL,
                                             localizedMessageLogger: localizedMessageLogger)
  }

  // MARK: - BazelWorkspaceInfoExtractorProtocol

  func extractRuleInfoFromProject(_ project: TulsiProject) -> [RuleInfo] {
    return queryExtractor.extractTargetRulesFromPackages(project.bazelPackages)
  }

  func ruleEntriesForLabels(_ labels: [BuildLabel],
                            startupOptions: TulsiOption,
                            buildOptions: TulsiOption) -> [BuildLabel: RuleEntry] {
    func isLabelMissing(_ label: BuildLabel) -> Bool { return ruleEntryCache[label] == nil }
    let missingLabels = labels.filter(isLabelMissing)
    if missingLabels.isEmpty { return ruleEntryCache }

    let commandLineSplitter = CommandLineSplitter()
    func splitOptionString(_ options: String?) -> [String] {
      guard let options = options else { return [] }
      return commandLineSplitter.splitCommandLine(options) ?? []
    }

    // TODO(abaire): Support per-target and per-config options during aspect lookups.
    let startupOptions = splitOptionString(startupOptions.commonValue)
    let buildOptions = splitOptionString(buildOptions.commonValue)
    let ruleEntries = aspectExtractor.extractRuleEntriesForLabels(labels,
                                                                  startupOptions: startupOptions,
                                                                  buildOptions: buildOptions)
    for (label, entry) in ruleEntries {
      ruleEntryCache[label] = entry
    }

    // Because certain label types are expanded by Bazel prior to aspect invocation (most notably
    // test_suite rules), an additional pass is attempted if any of the requested labels are still
    // missing after the aspect run.
    let remainingMissingLabels = missingLabels.filter() {
      return isLabelMissing($0) && !attemptedTestSuiteLabels.contains($0)
    }
    if !remainingMissingLabels.isEmpty {
      extractTestSuiteRules(remainingMissingLabels)
      attemptedTestSuiteLabels.forEach() { attemptedTestSuiteLabels.insert($0) }
    }

    return ruleEntryCache
  }

  func resolveExternalReferencePath(_ path: String) -> String? {
    let execRoot = workspacePathInfoFetcher.getExecutionRoot()
    let fullURL = NSURL.fileURL(withPathComponents: [execRoot, path])?.resolvingSymlinksInPath()
    return fullURL?.path
  }

  func extractBuildfiles<T: Collection>(_ forTargets: T) -> Set<BuildLabel> where T.Iterator.Element == BuildLabel {
    return queryExtractor.extractBuildfiles(forTargets)
  }

  // MARK: - Private methods

  private func extractTestSuiteRules(_ labels: [BuildLabel]) {
    let testSuiteDependencies = queryExtractor.extractTestSuiteRules(labels)
    for (ruleInfo, possibleExpansions) in testSuiteDependencies {
      ruleEntryCache[ruleInfo.label] = RuleEntry(label: ruleInfo.label,
                                                 type: ruleInfo.type,
                                                 attributes: [:],
                                                 weakDependencies: possibleExpansions)
    }
  }
}
