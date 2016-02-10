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
import TulsiGenerator

// Wraps a TulsiGenerator::RuleEntry with functionality to allow it to track selection and be
// accessed via bindings in the UI.
class UIRuleEntry: NSObject {
  dynamic var targetName: String? {
    return ruleEntry.label.targetName
  }

  dynamic var type: String {
    return ruleEntry.type
  }

  dynamic var selected: Bool = false

  var fullLabel: String {
    return ruleEntry.label.value
  }

  let ruleEntry: RuleEntry

  init(ruleEntry: RuleEntry) {
    self.ruleEntry = ruleEntry
  }
}
