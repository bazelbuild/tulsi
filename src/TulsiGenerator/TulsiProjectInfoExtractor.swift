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


// Provides functionality to generate a TulsiGeneratorConfig from a TulsiProject.
public final class TulsiProjectInfoExtractor {
  public enum ExtractorError: Error {
    case ruleEntriesFailed(String)
  }
  private let project: TulsiProject
  private let localizedMessageLogger: LocalizedMessageLogger
  var workspaceInfoExtractor: BazelWorkspaceInfoExtractorProtocol

  public var bazelURL: URL {
    get { return workspaceInfoExtractor.bazelURL as URL }
    set { workspaceInfoExtractor.bazelURL = newValue }
  }

  public var bazelExecutionRoot: String {
    return workspaceInfoExtractor.bazelExecutionRoot
  }

  public var bazelOutputBase: String {
    return workspaceInfoExtractor.bazelOutputBase
  }

  public var workspaceRootURL: URL {
    return workspaceInfoExtractor.workspaceRootURL
  }

  public init(bazelURL: URL,
              project: TulsiProject) {
    self.project = project
    let bundle = Bundle(for: type(of: self))
    localizedMessageLogger = LocalizedMessageLogger(bundle: bundle)

    workspaceInfoExtractor = BazelWorkspaceInfoExtractor(bazelURL: bazelURL,
                                                         workspaceRootURL: project.workspaceRootURL,
                                                         localizedMessageLogger: localizedMessageLogger)
  }

  public func extractTargetRules() -> [RuleInfo] {
    return workspaceInfoExtractor.extractRuleInfoFromProject(project)
  }

  public func ruleEntriesForInfos(_ infos: [RuleInfo],
                                  startupOptions: TulsiOption,
                                  extraStartupOptions: TulsiOption,
                                  buildOptions: TulsiOption,
                                  compilationModeOption: TulsiOption,
                                  platformConfigOption: TulsiOption,
                                  prioritizeSwiftOption: TulsiOption,
                                  use64BitWatchSimulatorOption: TulsiOption,
                                  features: Set<BazelSettingFeature>) throws -> RuleEntryMap {
    return try ruleEntriesForLabels(infos.map({ $0.label }),
                                    startupOptions: startupOptions,
                                    extraStartupOptions: extraStartupOptions,
                                    buildOptions: buildOptions,
                                    compilationModeOption: compilationModeOption,
                                    platformConfigOption: platformConfigOption,
                                    prioritizeSwiftOption: prioritizeSwiftOption,
                                    use64BitWatchSimulatorOption: use64BitWatchSimulatorOption,
                                    features: features)
  }

  public func ruleEntriesForLabels(_ labels: [BuildLabel],
                                   startupOptions: TulsiOption,
                                   extraStartupOptions: TulsiOption,
                                   buildOptions: TulsiOption,
                                   compilationModeOption: TulsiOption,
                                   platformConfigOption: TulsiOption,
                                   prioritizeSwiftOption: TulsiOption,
                                   use64BitWatchSimulatorOption: TulsiOption,
                                   features: Set<BazelSettingFeature>) throws -> RuleEntryMap {
    do {
      return try workspaceInfoExtractor.ruleEntriesForLabels(labels,
                                                             startupOptions: startupOptions,
                                                             extraStartupOptions: extraStartupOptions,
                                                             buildOptions: buildOptions,
                                                             compilationModeOption: compilationModeOption,
                                                             platformConfigOption: platformConfigOption,
                                                             prioritizeSwiftOption: prioritizeSwiftOption,
                                                             use64BitWatchSimulatorOption: use64BitWatchSimulatorOption,
                                                             features: features)
    } catch BazelWorkspaceInfoExtractorError.aspectExtractorFailed(let info) {
      throw ExtractorError.ruleEntriesFailed(info)
    }
  }

  public func extractBuildfiles(_ targets: [BuildLabel]) -> Set<BuildLabel> {
    return workspaceInfoExtractor.extractBuildfiles(targets)
  }
}
