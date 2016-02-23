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

@testable import TulsiGenerator


class MockWorkspaceInfoExtractor: WorkspaceInfoExtractorProtocol {

  var ruleEntryToSourcePaths = [RuleEntry: [String]]()

  var labelToRuleEntry = [String: RuleEntry]()
  /// The set of labels passed to ruleEntriesForLabels that could not be found in the
  /// labelToRuleEntry dictionary.
  var invalidLabels = Set<String>()

  var explicitIncludePaths: Set<String>? = nil
  var defines: Set<String>? = nil

  func extractTargetRulesFromProject(project: TulsiProject, callback: ([RuleEntry]) -> Void) {
  }

  func extractSourceRulesForRuleEntries(ruleEntries: [RuleEntry], callback: ([RuleEntry]) -> Void) {
  }

  func extractBUILDFilePathsForRules(ruleEntries: [RuleEntry], callback: ([String]) -> Void) {
  }

  func extractSourceFilePathsForSourceRules(ruleEntries: [RuleEntry]) -> [RuleEntry: [String]] {
    var ret = [RuleEntry: [String]]()
    for entry in ruleEntries {
      if let paths = ruleEntryToSourcePaths[entry] {
        ret[entry] = paths
      }
    }
    return ret
  }

  func extractExplicitIncludePathsForRuleEntries(ruleEntries: [RuleEntry]) -> Set<String>? {
    return explicitIncludePaths
  }

  func extractDefinesForRuleEntries(ruleEntries: [RuleEntry]) -> Set<String>? {
    return defines
  }

  func ruleEntriesForLabels(labels: [String]) -> [String: RuleEntry] {
    invalidLabels.removeAll(keepCapacity: true)
    var ret = [String: RuleEntry]()
    for label in labels {
      guard let entry = labelToRuleEntry[label] else {
        invalidLabels.insert(label)
        continue
      }
      ret[label] = entry
    }
    return ret
  }
}
