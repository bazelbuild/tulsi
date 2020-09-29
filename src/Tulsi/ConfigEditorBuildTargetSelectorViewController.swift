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
  // since watchos_applications are tightly bound to their host binary, Tulsi automatically
  // generates all targets referenced in an ios_application's "extensions" attribute rather than
  // risk the user accidentally selecting the extension without the host. For this reason,
  // ios_extension and watchos_extension are omitted as well.
  static let filteredFileTypes = [
      // Remove apple_ui_test and apple_unit_test once Tulsi has been released with support for
      // the new rule names.
      "apple_ui_test",
      "apple_unit_test",
      "cc_binary",
      "cc_library",
      "cc_test",
      "ios_app_clip",
      "ios_application",
      "ios_framework",
      "ios_static_framework",
      "ios_legacy_test",
      "ios_ui_test",
      "ios_unit_test",
      "macos_application",
      "macos_bundle",
      "macos_command_line_application",
      "macos_extension",
      "macos_ui_test",
      "macos_unit_test",
      "objc_library",
      "swift_library",
      "test_suite",
      "tvos_application",
      "tvos_ui_test",
      "tvos_unit_test",
  ]

  @IBOutlet weak var buildTargetTable: NSTableView!

  @objc dynamic let typeFilter: NSPredicate? = NSPredicate.init(format: "(SELF.type IN %@) OR (SELF.selected == TRUE)",
                                                          argumentArray: [filteredFileTypes])

  @objc var selectedRuleInfoCount: Int = 0 {
    didSet {
      presentingWizardViewController?.setNextButtonEnabled(selectedRuleInfoCount > 0)
    }
  }

  override var representedObject: Any? {
    didSet {
      NSObject.unbind(NSBindingName(rawValue: "selectedRuleInfoCount"))
      guard let document = representedObject as? TulsiGeneratorConfigDocument else { return }
      bind(NSBindingName(rawValue: "selectedRuleInfoCount"),
           to: document,
           withKeyPath: "selectedRuleInfoCount",
           options: nil)
    }
  }

  deinit {
    NSObject.unbind(NSBindingName(rawValue: "selectedRuleInfoCount"))
  }

  override func loadView() {
    super.loadView()

    let typeColumn = buildTargetTable.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "Type"))!
    let labelColumn = buildTargetTable.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "Label"))!
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
    NSObject.unbind(NSBindingName(rawValue: "selectedRuleInfoCount"))
  }
}
