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


// Concrete extractor that utilizes Bazel query (http://bazel.io/docs/query.html) and aspects to
// extract information from a workspace.
// TODO(abaire): Add link to aspect documentation when it becomes available.
final class BazelWorkspaceInfoExtractor: WorkspaceInfoExtractorProtocol {
  var bazelURL: NSURL {
    get { return queryExtractor.bazelURL }
    set {
      queryExtractor.bazelURL = newValue
      aspectExtractor.bazelURL = newValue
    }
  }

  /// Fetcher object from which a workspace's package_path may be obtained.
  private let packagePathFetcher: BazelWorkspacePackagePathFetcher

  private let aspectExtractor: BazelAspectInfoExtractor
  private let queryExtractor: BazelQueryInfoExtractor

  // Cache of all RuleEntry instances loaded for the associated project.
  private var ruleEntryCache = [BuildLabel: RuleEntry]()

  init(bazelURL: NSURL, workspaceRootURL: NSURL, localizedMessageLogger: LocalizedMessageLogger) {

    packagePathFetcher = BazelWorkspacePackagePathFetcher(bazelURL: bazelURL,
                                                          workspaceRootURL: workspaceRootURL,
                                                          localizedMessageLogger: localizedMessageLogger)
    aspectExtractor = BazelAspectInfoExtractor(bazelURL: bazelURL,
                                               workspaceRootURL: workspaceRootURL,
                                               packagePathFetcher: packagePathFetcher,
                                               localizedMessageLogger: localizedMessageLogger)
    queryExtractor = BazelQueryInfoExtractor(bazelURL: bazelURL,
                                             workspaceRootURL: workspaceRootURL,
                                             localizedMessageLogger: localizedMessageLogger)
  }

  // MARK: - WorkspaceInfoExtractorProtocol

  func extractRuleInfoFromProject(project: TulsiProject) -> [RuleInfo] {
    return queryExtractor.extractTargetRulesFromProject(project)
  }

  func ruleEntriesForLabels(labels: [BuildLabel],
                            startupOptions: TulsiOption,
                            buildOptions: TulsiOption) -> [BuildLabel: RuleEntry] {
    let missingLabels = labels.filter() { ruleEntryCache[$0] == nil }
    if missingLabels.isEmpty { return ruleEntryCache }

    let commandLineSplitter = CommandLineSplitter()
    func splitOptionString(options: String?) -> [String] {
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
    return ruleEntryCache
  }
}
