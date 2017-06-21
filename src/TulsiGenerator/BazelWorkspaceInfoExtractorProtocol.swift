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


/// Defines an object that can extract information from a Bazel workspace.
protocol BazelWorkspaceInfoExtractorProtocol {
  /// Extracts information about the set of top level target rules from the given project.
  func extractRuleInfoFromProject(_ project: TulsiProject) -> [RuleInfo]

  /// Retrieves RuleEntry information for the given list of labels, returning a dictionary mapping
  /// each given label to the resolved RuleEntry if it resolved correctly (invalid labels will be
  /// omitted from the returned dictionary).
  func ruleEntriesForLabels(_ labels: [BuildLabel],
                            startupOptions: TulsiOption,
                            buildOptions: TulsiOption) -> [BuildLabel: RuleEntry]

  /// Resolves the given Bazel path (which is expected to begin with external/) to a filesystem
  /// path. This is intended to be used to resolve "@external_repo" style labels to paths usable by
  /// Xcode. Returns nil if the path could not be resolved for any reason.
  func resolveExternalReferencePath(_ path: String) -> String?

  /// Extracts labels for the files referenced by the build infrastructure for the given set of
  /// BUILD targets.
  func extractBuildfiles<T: Collection>(_ forTargets: T) -> Set<BuildLabel> where T.Iterator.Element == BuildLabel

  /// URL to the Bazel binary used by this extractor.
  var bazelURL: URL {get set}

  /// Workspace-relative path to the directory in which Bazel will install generated artifacts.
  var bazelBinPath: String {get}
}
