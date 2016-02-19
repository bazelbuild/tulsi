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


/// View controller allowing certain Bazel build targets from the project to be selected for Xcode
/// project generation.
final class ConfigEditorBuildTargetSelectorViewController: NSViewController, WizardSubviewProtocol {
  dynamic var typeFilter: NSPredicate?

  // This list needs to be kept up to date with whatever Bazel does.
  let filteredFileTypes = [
      "objc_binary",
      "objc_library",
      "ios_application",
      "ios_extension_binary",
      "ios_framework_binary",
      "ios_test",
  ]

  var selectedRuleEntryCount: Int = 0 {
    didSet {
      presentingWizardViewController?.setNextButtonEnabled(selectedRuleEntryCount > 0)
    }
  }

  override var representedObject: AnyObject? {
    didSet {
      unbind("selectedRuleEntryCount")
      guard let document = representedObject as? TulsiGeneratorConfigDocument else { return }
      bind("selectedRuleEntryCount",
           toObject: document,
           withKeyPath: "selectedRuleEntryCount",
           options: nil)
    }
  }

  deinit {
    unbind("selectedRuleEntryCount")
  }

  override func loadView() {
    enableFilter(self)
    super.loadView()
  }

  @IBAction func enableFilter(sender: AnyObject?) {
    if typeFilter != nil {
      typeFilter = nil
    } else {
      typeFilter = NSPredicate.init(format: "(SELF.type IN %@) OR (SELF.selected == TRUE)",
                                    argumentArray: [filteredFileTypes])
    }
  }

  // MARK: - WizardSubviewProtocol

  weak var presentingWizardViewController: ConfigEditorWizardViewController? = nil {
    didSet {
      presentingWizardViewController?.setNextButtonEnabled(selectedRuleEntryCount > 0)
    }
  }

  func wizardSubviewWillActivateMovingForward() {
    guard let document = representedObject as? TulsiGeneratorConfigDocument else { return }
    bind("selectedRuleEntryCount",
         toObject: document,
         withKeyPath: "selectedRuleEntryCount",
         options: nil)
  }

  func wizardSubviewDidDeactivate() {
    unbind("selectedRuleEntryCount")
  }
}
