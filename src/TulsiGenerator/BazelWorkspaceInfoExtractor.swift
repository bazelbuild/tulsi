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
// TODO(abaire): Remove LabelResolverProtocol when aspects are default enabled.
final class BazelWorkspaceInfoExtractor: WorkspaceInfoExtractorProtocol, LabelResolverProtocol {
  var bazelURL: NSURL {
    get { return queryExtractor.bazelURL }
    set {
      queryExtractor.bazelURL = newValue
      if let aspectExtractor = aspectExtractor {
        aspectExtractor.bazelURL = newValue
      }
    }
  }

  // TODO(abaire): Make concrete once aspects are rolled out.
  private let aspectExtractor: BazelAspectInfoExtractor!
  private let queryExtractor: BazelQueryInfoExtractor

  /// Fetcher object from which a workspace's package_path may be obtained.
  private let packagePathFetcher: BazelWorkspacePackagePathFetcher!

  init(bazelURL: NSURL, workspaceRootURL: NSURL, localizedMessageLogger: LocalizedMessageLogger) {

    // TODO(abaire): Remove this when aspects become the default.
    if NSUserDefaults.standardUserDefaults().boolForKey("use_aspects") {
      packagePathFetcher = BazelWorkspacePackagePathFetcher(bazelURL: bazelURL,
                                                            workspaceRootURL: workspaceRootURL,
                                                            localizedMessageLogger: localizedMessageLogger)

      // TODO(abaire): Take TulsiOptions and use the CommandLineSplitter to pull out relevant data.
      //               This work should be delayed until it's actually needed, however.
      aspectExtractor = BazelAspectInfoExtractor(bazelURL: bazelURL,
                                                              workspaceRootURL: workspaceRootURL,
                                                              packagePathFetcher: packagePathFetcher,
                                                              localizedMessageLogger: localizedMessageLogger)
    } else {
      packagePathFetcher = nil
      aspectExtractor = nil
    }

    queryExtractor = BazelQueryInfoExtractor(bazelURL: bazelURL,
                                             workspaceRootURL: workspaceRootURL,
                                             localizedMessageLogger: localizedMessageLogger)
  }

  // MARK: - WorkspaceInfoExtractorProtocol

  func extractTargetRulesFromProject(project: TulsiProject) -> [RuleEntry] {
    return queryExtractor.extractTargetRulesFromProject(project)
  }

  func extractSourceRulesForRuleEntries(ruleEntries: [RuleEntry],
                                        startupOptions: TulsiOption,
                                        buildOptions: TulsiOption) -> [RuleEntry] {
    if aspectExtractor != nil {
      let labels: [String] = ruleEntries.map() { $0.label.value }
      let labelToRuleEntry = ruleEntriesForLabels(labels,
                                                  startupOptions: startupOptions,
                                                  buildOptions: buildOptions)
      return labelToRuleEntry.map() { $0.1 }
    }
    return queryExtractor.extractSourceRulesForRuleEntries(ruleEntries)
  }

  // TODO(abaire): Remove when aspects are the default.
  // Callers should just use the source info on the extracted RuleEntry's.
  func extractSourceFilePathsForSourceRules(ruleEntries: [RuleEntry]) -> [RuleEntry:[String]] {
    var sourcePaths = [RuleEntry: [String]]()
    var rulesWithoutSources = [RuleEntry]()
    for ruleEntry in ruleEntries {
      if ruleEntry.sourceFiles.isEmpty {
        // Note: This will erroneously add things that just don't have source files. Switching to
        //       aspects as the default will allow this to be removed.
        rulesWithoutSources.append(ruleEntry)
        continue
      }
      sourcePaths[ruleEntry] = ruleEntry.sourceFiles
    }

    // If aspects are being used, any rule without sources doesn't have sources to load.
    if aspectExtractor != nil {
      for ruleEntry in rulesWithoutSources {
        sourcePaths[ruleEntry] = []
      }
      return sourcePaths
    }

    let additionalPaths = queryExtractor.extractSourceFilePathsForSourceRules(ruleEntries)
    for (ruleEntry, paths) in additionalPaths {
      sourcePaths[ruleEntry] = paths
    }
    return sourcePaths
  }

  func extractExplicitIncludePathsForRuleEntries(ruleEntries: [RuleEntry]) -> Set<String>? {
    return nil
  }

  func extractDefinesForRuleEntries(ruleEntries: [RuleEntry]) -> Set<String>? {
    return nil
  }

  func ruleEntriesForLabels(labels: [String],
                            startupOptions: TulsiOption,
                            buildOptions: TulsiOption) -> [String:RuleEntry] {
    if let aspectExtractor = aspectExtractor {
      let commandLineSplitter = CommandLineSplitter()
      func splitOptionString(options: String?) -> [String] {
        guard let options = options else { return [] }
        return commandLineSplitter.splitCommandLine(options) ?? []
      }

      // TODO(abaire): Support per-target and per-config options during aspect lookups.
      let startupOptions = splitOptionString(startupOptions.commonValue)
      let buildOptions = splitOptionString(buildOptions.commonValue)
      let ruleEntries = aspectExtractor.extractInfoForTargetLabels(labels,
                                                                                startupOptions: startupOptions,
                                                                                buildOptions: buildOptions)
      var labelMap = [String: RuleEntry]()
      for entry in ruleEntries {
        labelMap[entry.label.value] = entry
      }
      return labelMap
    }
    return queryExtractor.ruleEntriesForLabels(labels)
  }

  // MARK: - LabelResolverProtocol

  func resolveFilesForLabels(labels: [String]) -> [String:BazelFileTarget?]? {
    return queryExtractor.resolveFilesForLabels(labels)
  }
}
