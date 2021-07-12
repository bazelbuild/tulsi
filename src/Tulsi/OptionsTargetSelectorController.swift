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


/// Models a UIRuleEntry as a node suitable for display in the options target selector.
class OptionsTargetNode: UISelectableOutlineViewNode {

  /// Tooltip to be displayed for this node.
  @objc var toolTip: String? = nil

  @objc var boldFont: Bool {
    return !children.isEmpty
  }
}


protocol OptionsTargetSelectorControllerDelegate: AnyObject {
  /// Invoked when the target selection has been changed.
  func didSelectOptionsTargetNode(_ node: OptionsTargetNode)
}


// Delegate for the target selector outline view.
class OptionsTargetSelectorController: NSObject, NSOutlineViewDelegate {
  static let projectSectionTitle =
      NSLocalizedString("OptionsTarget_ProjectSectionTitle",
                        comment: "Short header shown before the project in the options editor's target selector.")
  static let targetSectionTitle =
      NSLocalizedString("OptionsTarget_TargetSectionTitle",
                        comment: "Short header shown before the build targets in the options editor's target selector.")

  weak var view: NSOutlineView!
  @objc dynamic var nodes = [OptionsTargetNode]()

  weak var delegate: OptionsTargetSelectorControllerDelegate?
  weak var model: OptionsEditorModelProtocol! = nil {
    didSet {
      if model == nil || model.projectName == nil { return }

      let projectSection = OptionsTargetNode(name: OptionsTargetSelectorController.projectSectionTitle)
      projectSection.addChild(OptionsTargetNode(name: model.projectName!))
      var newNodes = [projectSection]

      if model.shouldShowPerTargetOptions, let targetEntries = model.optionsTargetUIRuleEntries {
        let targetSection = OptionsTargetNode(name: OptionsTargetSelectorController.targetSectionTitle)
        for entry in targetEntries {
          let node = OptionsTargetNode(name: entry.targetName!)
          node.toolTip = entry.fullLabel
          node.entry = entry
          targetSection.addChild(node)
        }
        newNodes.append(targetSection)
      }
      nodes = newNodes

      // Expand all children in the target selector and select the project.
      view.expandItem(nil, expandChildren: true)
      view.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    }
  }

  init(view: NSOutlineView, delegate: OptionsTargetSelectorControllerDelegate) {
    self.view = view
    self.delegate = delegate
    super.init()
    self.view.delegate = self
  }

  func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
    // The top level items are not selectable.
    return outlineView.level(forItem: item) > 0
  }

  func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
    return false
  }

  func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
    return false
  }

  func outlineViewSelectionDidChange(_ notification: Notification) {
    if delegate == nil { return }
    let selectedTreeNode = view.item(atRow: view.selectedRow) as! NSTreeNode
    let selectedTarget = selectedTreeNode.representedObject as! OptionsTargetNode
    delegate!.didSelectOptionsTargetNode(selectedTarget)
  }
}
