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
  // This list needs to be kept up to date with whatever Bazel supports and determines the set of
  // user-selectable target types displayed in the Tulsi UI.
  // This filter does not limit Tulsi from generating targets for other types, however. Notably,
  // since apple_watch2_extension extensions are tightly bound to their host binary, Tulsi
  // automatically generates all targets referenced in an ios_application's "extensions" attribute
  // rather than risk the user accidentally selecting the extension without the host. For this
  // reason, apple_watch1_extension and ios_extension are both omitted as well.
  static let filteredFileTypes = [
      "apple_unit_test",
      "objc_binary",  // TODO(abaire): Remove when app-related attributes are removed from Bazel.
      "objc_library",
      "ios_application",
      "ios_framework",
      "ios_test",
      "swift_library",
      "test_suite",
      "tvos_application",
      "_ios_application",
      "_tvos_application",
  ]

  @IBOutlet weak var buildTargetTable: NSTableView!

  dynamic let typeFilter: NSPredicate? = NSPredicate.init(format: "(SELF.type IN %@) OR (SELF.selected == TRUE)",
                                                          argumentArray: [filteredFileTypes])

  var selectedRuleInfoCount: Int = 0 {
    didSet {
      presentingWizardViewController?.setNextButtonEnabled(selectedRuleInfoCount > 0)
    }
  }

  override var representedObject: AnyObject? {
    didSet {
      unbind("selectedRuleInfoCount")
      guard let document = representedObject as? TulsiGeneratorConfigDocument else { return }
      bind("selectedRuleInfoCount",
           toObject: document,
           withKeyPath: "selectedRuleInfoCount",
           options: nil)
    }
  }

  deinit {
    unbind("selectedRuleInfoCount")
  }

  override func loadView() {
    super.loadView()

    let typeColumn = buildTargetTable.tableColumnWithIdentifier("Type")!
    let labelColumn = buildTargetTable.tableColumnWithIdentifier("Label")!
    buildTargetTable.sortDescriptors = [typeColumn.sortDescriptorPrototype!,
                                        labelColumn.sortDescriptorPrototype!]
  }

  // MARK: - WizardSubviewProtocol

  weak var presentingWizardViewController: ConfigEditorWizardViewController? = nil {
    didSet {
      presentingWizardViewController?.setNextButtonEnabled(selectedRuleInfoCount > 0)
    }
  }

  func wizardSubviewDidDeactivate() {
    unbind("selectedRuleInfoCount")
  }
}
