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
@testable import TulsiGenerator


class MockWorkspaceInfoExtractor: WorkspaceInfoExtractorProtocol {

  var labelToRuleEntry = [String: RuleEntry]()
  /// The set of labels passed to ruleEntriesForLabels that could not be found in the
  /// labelToRuleEntry dictionary.
  var invalidLabels = Set<String>()

  var bazelURL = NSURL()

  func extractTargetRulesFromProject(project: TulsiProject) -> [RuleEntry] {
    return []
  }

  func ruleEntriesForLabels(labels: [String],
                            startupOptions: TulsiOption,
                            buildOptions: TulsiOption) -> [String: RuleEntry] {
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
