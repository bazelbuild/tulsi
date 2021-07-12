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

import Cocoa
import TulsiGenerator


/// Provides functionality for accessing and mutating an object capable of storing Tulsi options.
protocol OptionsEditorModelProtocol: AnyObject {
  /// The name of the project that the model's options are associated with.
  var projectName: String? { get }

  /// The actual options in the model.
  var optionSet: TulsiOptionSet? { get }

  /// The set of UIRuleEntries for which options may be set.
  var optionsTargetUIRuleEntries: [UIRuleInfo]? { get }

  /// String to be used as the title of the project-wide column containing user-editable values.
  var projectValueColumnTitle: String { get }

  /// String to be used as the title of the column containing default/inherited values that will be
  /// used if the user does not provide any overrides.
  var defaultValueColumnTitle: String { get }

  /// Returns the parent option for the given key or nil if the option does not inherit its default
  /// value from some user-editable value.
  func parentOptionForOptionKey(_ key: TulsiOptionKey) -> TulsiOption?

  /// Notifies the receiver that a change has been made to an option.
  func updateChangeCount(_ change: NSDocument.ChangeType)
}

extension OptionsEditorModelProtocol {

  /// Whether or not per-target options should be shown.
  var shouldShowPerTargetOptions: Bool {
    return optionsTargetUIRuleEntries != nil
  }

  // Options are not inherited by default.
  func parentOptionForOptionKey(_: TulsiOptionKey) -> TulsiOption? {
    return nil
  }
}
