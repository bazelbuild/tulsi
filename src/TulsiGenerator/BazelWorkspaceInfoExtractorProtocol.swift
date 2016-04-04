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
  func extractRuleInfoFromProject(project: TulsiProject) -> [RuleInfo]

  /// Retrieves RuleEntry information for the given list of labels, returning a dictionary mapping
  /// each given label to the resolved RuleEntry if it resolved correctly (invalid labels will be
  /// omitted from the returned dictionary).
  func ruleEntriesForLabels(labels: [BuildLabel],
                            startupOptions: TulsiOption,
                            buildOptions: TulsiOption) -> [BuildLabel: RuleEntry]

  /// URL to the Bazel binary used by this extractor.
  var bazelURL: NSURL {get set}
}
