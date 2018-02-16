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


/// Controller for the options editor wizard page.
final class OptionsEditorViewController: NSViewController, NSSplitViewDelegate, OptionsTargetSelectorControllerDelegate {

  @IBOutlet weak var targetSelectorView: NSOutlineView!
  @IBOutlet weak var optionEditorView: NSOutlineView!

  @objc dynamic var targetSelectorController: OptionsTargetSelectorController? = nil
  @objc dynamic var editorController: OptionsEditorController? = nil

  override var representedObject: Any? {
    didSet {
      syncViewsFromModel()
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    targetSelectorController = OptionsTargetSelectorController(view: targetSelectorView,
                                                               delegate: self)
    editorController = OptionsEditorController(view: optionEditorView, storyboard: storyboard!)
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    syncViewsFromModel()
  }

  @IBAction func textFieldDidCompleteEditing(_ sender: OptionsEditorTextField) {
    editorController?.stringBasedControlDidCompleteEditing(sender)
  }

  @IBAction func popUpFieldDidCompleteEditing(_ sender: NSPopUpButton) {
    editorController?.popUpFieldDidCompleteEditing(sender)
  }

  @IBAction func didDoubleClickInEditorView(_ sender: NSOutlineView) {
    editorController?.didDoubleClickInEditorView(sender)
  }

  // MARK: - NSSplitViewDelegate

  func splitView(_ splitView: NSSplitView,
                 constrainMinCoordinate proposedMinimumPosition: CGFloat,
                 ofSubviewAt dividerIndex: Int) -> CGFloat {
    // Restrict the splitter so it's never less than the target selector's min width.
    let minWidth = targetSelectorView.tableColumns[0].minWidth + targetSelectorView.intercellSpacing.width
    return minWidth
  }

  // MARK: - OptionsTargetSelectorControllerDelegate

  func didSelectOptionsTargetNode(_ selectedTarget: OptionsTargetNode) {
    editorController?.prepareEditorForTarget(selectedTarget.entry as? UIRuleInfo)
  }

  // MARK: - Private methods

  private func syncViewsFromModel() {
    guard let model = representedObject as? OptionsEditorModelProtocol else { return }

    // Note: the editor's document must be set before the target selector as the target selector
    // immediately updates selection as a side effect of document modification.
    editorController?.model = model
    targetSelectorController?.model = model
  }
}
