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


class MockWorkspaceInfoExtractor: BazelWorkspaceInfoExtractorProtocol {

  var labelToRuleEntry = [BuildLabel: RuleEntry]()
  /// The set of labels passed to ruleEntriesForLabels that could not be found in the
  /// labelToRuleEntry dictionary.
  var invalidLabels = Set<BuildLabel>()

  var bazelURL = URL(fileURLWithPath: "")
  var bazelBinPath = "bazel-bin"

  func extractRuleInfoFromProject(_ project: TulsiProject) -> [RuleInfo] {
    return []
  }

  func ruleEntriesForLabels(_ labels: [BuildLabel],
                            startupOptions: TulsiOption,
                            buildOptions: TulsiOption) -> [BuildLabel: RuleEntry] {
    invalidLabels.removeAll(keepingCapacity: true)
    var ret = [BuildLabel: RuleEntry]()
    for label in labels {
      guard let entry = labelToRuleEntry[label] else {
        invalidLabels.insert(label)
        continue
      }
      ret[label] = entry
    }
    return ret
  }

  func resolveExternalReferencePath(_ path: String) -> String? {
    return nil
  }

  func extractBuildfiles<T:Collection>(_ forTargets: T) -> Set<BuildLabel> where T.Iterator.Element == BuildLabel {
    return Set()
  }
}
