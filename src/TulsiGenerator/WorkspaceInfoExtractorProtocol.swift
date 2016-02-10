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
protocol WorkspaceInfoExtractorProtocol {
  // TODO(abaire): Make all of these synchronous calls and pull the threading up to the app layer.

  /// Extracts the set of target rule entries from the given project and invokes the given callback
  /// asynchronously on the main queue.
  func extractTargetRulesFromProject(project: TulsiProject, callback: ([RuleEntry]) -> Void)

  /// Extracts source file RuleEntry's for the given set of target rules and invokes callback
  /// asynchronously on the main queue.
  func extractSourceRulesForRuleEntries(ruleEntries: [RuleEntry], callback: ([RuleEntry]) -> Void)

  /// Extracts source file paths for the given set of source rules and provides a dictionary mapping
  /// each RuleEntry to the set of source files needed by that rule.
  func extractSourceFilePathsForSourceRules(ruleEntries: [RuleEntry]) -> [RuleEntry: [String]]

  /// Retrieves RuleEntry information for the given list of labels, returning a dictionary mapping
  /// each given label to the resolved RuleEntry if it resolved correctly (invalid labels will be
  /// omitted from the returned dictionary).
  func ruleEntriesForLabels(labels: [String]) -> [String: RuleEntry]
}
