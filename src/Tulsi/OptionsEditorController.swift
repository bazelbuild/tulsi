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


@objc
protocol OptionsEditorOutlineViewDelegate: NSOutlineViewDelegate {
  /// Invoked when the delete key is pressed on the given view. Should return true if the event was
  /// fully handled, false if it should be passed up the responder chain.
  optional func deleteKeyPressedForOptionsEditorOutlineView(view: OptionsEditorOutlineView) -> Bool
}


/// Outline view containing the options editor.
class OptionsEditorOutlineView: NSOutlineView {
  override func keyDown(theEvent: NSEvent) {
    guard let eventCharacters = theEvent.charactersIgnoringModifiers else {
      super.keyDown(theEvent)
      return
    }

    // Eat spacebar presses as the option editor view does not support activation of rows this way.
    if eventCharacters == " " {
      return
    }

    if let delegate = self.delegate() as? OptionsEditorOutlineViewDelegate {
      let scalars = eventCharacters.unicodeScalars
      if scalars.count == 1 {
        let character = scalars[scalars.startIndex]
        if character == UnicodeScalar(NSDeleteCharacter) ||
            character == UnicodeScalar(NSBackspaceCharacter) ||
            character == UnicodeScalar(NSDeleteFunctionKey) ||
            character == UnicodeScalar(NSDeleteCharFunctionKey) {
          if let handled = delegate.deleteKeyPressedForOptionsEditorOutlineView?(self) where handled {
            return
          }
        }
      }
    }

    super.keyDown(theEvent)
  }
}


/// Table cell view with the ability to draw a background.
class TextTableCellView: NSTableCellView {
  @IBInspectable var drawsBackground: Bool = false {
    didSet {
      needsDisplay = true
    }
  }

  @IBInspectable var backgroundColor: NSColor = NSColor.controlBackgroundColor() {
    didSet {
      if drawsBackground {
        needsDisplay = true
      }
    }
  }

  // Whether or not this cell view is currently selected in the table.
  var selected: Bool = false {
    didSet {
      if drawsBackground {
        needsDisplay = true
      }
    }
  }

  override func drawRect(dirtyRect: NSRect) {
    if drawsBackground {
      if selected {
        NSColor.clearColor().setFill()
      } else {
        backgroundColor.setFill()
      }

      NSRectFill(dirtyRect)
    }
    super.drawRect(dirtyRect)
  }
}


/// A table cell view containing a pop up button.
class PopUpButtonTableCellView: TextTableCellView {
  @IBOutlet weak var popUpButton: NSPopUpButton!
}


/// A text field within the editor outline view.
class OptionsEditorTextField: NSTextField {
  override func textDidEndEditing(var notification: NSNotification) {
    // If the text field completed due to a return keypress convert its movement into "other" so
    // that the keypress is not passed up the responder chain causing some other control (e.g., the
    // default button in the wizard) to handle it as well.
    if let movement = notification.userInfo?["NSTextMovement"] as? Int where movement == NSReturnTextMovement {
      let userInfo = ["NSTextMovement": NSOtherTextMovement]
      notification = NSNotification(name: notification.name, object: notification.object, userInfo: userInfo)
    }
    super.textDidEndEditing(notification)
  }
}


/// View controller for the multiline popup editor displayed when a user double clicks an option.
class OptionsEditorPopoverViewController: NSViewController, NSTextFieldDelegate {
  dynamic var value: String? = nil

  enum CloseReason {
    case Cancel, Accept
  }
  var closeReason: CloseReason = .Cancel

  weak var popover: NSPopover? = nil

  var optionNode: OptionsEditorNode! = nil
  var optionLevel: OptionsEditorNode.OptionLevel = .Default

  func setRepresentedOptionNode(optionNode: OptionsEditorNode, level: OptionsEditorNode.OptionLevel) {
    self.optionNode = optionNode
    self.optionLevel = level
    let (currentValue, inherited) = optionNode.displayItemForOptionLevel(optionLevel)
    if inherited {
      value = ""
    } else {
      value = currentValue
    }
  }

  // MARK: - NSTextFieldDelegate

  func control(control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
    if closeReason == .Accept {
      optionNode.setDisplayItem(fieldEditor.string, forOptionLevel: optionLevel)
    }
    return true
  }

  func control(control: NSControl, textView: NSTextView, doCommandBySelector commandSelector: Selector) -> Bool {
    switch commandSelector {
      // Operations that cancel.
      case Selector("cancelOperation:"):
        closeReason = .Cancel

      // Operations that commit the current value.
      case Selector("insertNewline:"):
        closeReason = .Accept
        popover?.performClose(control)
        return true

      // Operations that should be disabled.
      case Selector("insertBacktab:"):
        fallthrough
      case Selector("insertTab:"):
        return true

      default:
        break
    }

    // Allow the system to handle the selector.
    return false
  }
}


class OptionsEditorController: NSObject, OptionsEditorOutlineViewDelegate, NSPopoverDelegate {
  // Storyboard identifiers.
  static let settingColumnIdentifier = "Setting"
  static let targetColumnIdentifier = OptionsEditorNode.OptionLevel.Target.rawValue
  static let projectColumnIdentifier = OptionsEditorNode.OptionLevel.Project.rawValue
  static let defaultColumnIdentifier = OptionsEditorNode.OptionLevel.Default.rawValue
  static let tableCellViewIdentifier = "TableCellView"
  static let popUpButtonCellViewIdentifier = "PopUpButtonCell"
  static let boldPopUpButtonCellViewIdentifier = "BoldPopUpButtonCell"

  // The set of column identifiers whose contents are entirely controlled via bindings set in the
  // storyboard.
  static let bindingsControlledColumns = Set([settingColumnIdentifier, defaultColumnIdentifier])

  let storyboard: NSStoryboard
  weak var view: NSOutlineView!
  // The table column used to display build target-specific build options.
  let targetValueColumn: NSTableColumn

  dynamic var nodes = [OptionsEditorNode]()
  weak var document: TulsiDocument? = nil

  // Popover containing a multiline editor for an option the user double clicked on.
  var popoverEditor: NSPopover! = nil
  var popoverViewController: OptionsEditorPopoverViewController! = nil

  init(view: NSOutlineView, storyboard: NSStoryboard) {
    self.view = view
    self.storyboard = storyboard
    self.targetValueColumn = view.tableColumnWithIdentifier(OptionsEditorController.targetColumnIdentifier)!
    super.init()
    self.view.setDelegate(self)
  }

  /// Prepares the editor view to edit options with the most specialized column set to the given
  /// target rule.
  func prepareEditorForTarget(target: UIRuleEntry?) {
    if target == nil {
      targetValueColumn.hidden = true
    } else {
      targetValueColumn.title = target!.targetName!
      targetValueColumn.hidden = false
    }

    var newOptionNodes = [OptionsEditorNode]()
    var optionGroupNodes = [TulsiOptionKeyGroup: OptionsEditorGroupNode]()
    for (key, option) in document!.options.allOptions {
      let newNode: OptionsEditorNode
      switch option.valueType {
        case .Bool:
          newNode = OptionsEditorBooleanNode(key: key, option: option, target: target)
        case .String:
          newNode = OptionsEditorStringNode(key: key, option: option, target: target)
      }

      if let (group, displayName, description) = document!.options.groupInfoForOptionKey(key) {
        var parent: OptionsEditorGroupNode! = optionGroupNodes[group]
        if parent == nil {
          parent = OptionsEditorGroupNode(key: group,
                                          displayName: displayName,
                                          description: description)
          optionGroupNodes[group] = parent
          newOptionNodes.append(parent)
        }
        parent.addChildNode(newNode)
      } else {
        newOptionNodes.append(newNode)
      }
    }
    nodes = newOptionNodes.sort { $0.name < $1.name }
  }

  func stringBasedControlDidCompleteEditing(control: NSControl) {
    let (node, modifiedLevel) = optionNodeAndLevelForControl(control)
    node.setDisplayItem(control.stringValue, forOptionLevel: modifiedLevel)
    reloadDataForEditedControl(control)
  }

  func popUpFieldDidCompleteEditing(button: NSPopUpButton) {
    let (node, level) = optionNodeAndLevelForControl(button)
    node.setDisplayItem(button.titleOfSelectedItem, forOptionLevel: level)
    reloadDataForEditedControl(button)
  }

  func didDoubleClickInEditorView(editor: NSOutlineView) {
    if editor.clickedRow < 0 || editor.clickedColumn < 0 {
      return
    }

    let clickedColumn = editor.tableColumns[editor.clickedColumn]
    let columnIdentifier = clickedColumn.identifier
    guard let optionLevel = OptionsEditorNode.OptionLevel(rawValue: columnIdentifier) else {
      assert(columnIdentifier == OptionsEditorController.settingColumnIdentifier,
             "Mismatch in storyboard column identifier and OptionLevel enum")
      return
    }
    let optionNode = optionNodeForItem(editor.itemAtRow(editor.clickedRow)!, outlineView: editor)

    // Verify that the column is editable.
    if OptionsEditorController.bindingsControlledColumns.contains(columnIdentifier) ||
        !optionNode.editableForOptionLevel(optionLevel) {
      return
    }

    if optionNode.supportsMultilineEditor,
       let view = editor.viewAtColumn(editor.clickedColumn,
                                      row: editor.clickedRow,
                                      makeIfNecessary: false) {

      popoverEditor = NSPopover()
      if popoverViewController == nil {
        popoverViewController = storyboard.instantiateControllerWithIdentifier("OptionsEditorPopover") as? OptionsEditorPopoverViewController
      }
      popoverEditor.contentViewController = popoverViewController
      popoverViewController.setRepresentedOptionNode(optionNode, level: optionLevel)
      popoverViewController.popover = popoverEditor
      popoverEditor.delegate = self
      popoverEditor.behavior = .Semitransient
      popoverEditor.showRelativeToRect(NSRect(), ofView: view, preferredEdge: .MinY)
    }
  }

  // MARK: - OptionsEditorOutlineViewDelegate

  func deleteKeyPressedForOptionsEditorOutlineView(view: OptionsEditorOutlineView) -> Bool {
    let selectedRow = view.selectedRow
    if selectedRow < 0 || selectedRow >= nodes.count { return false }
    let selectedNode = optionNodeForItem(view.itemAtRow(selectedRow)!, outlineView: view)
    if selectedNode.deleteMostSpecializedValue() {
      reloadDataForRow(selectedRow)
      return true
    }

    return false
  }

  func outlineView(outlineView: NSOutlineView, viewForTableColumn tableColumn: NSTableColumn?, item: AnyObject) -> NSView? {
    if tableColumn == nil { return nil }

    let identifier = tableColumn!.identifier
    if OptionsEditorController.bindingsControlledColumns.contains(identifier) {
      return outlineView.makeViewWithIdentifier(identifier, owner: self)
    }

    let optionNode = optionNodeForItem(item, outlineView: outlineView)
    let optionLevel = OptionsEditorNode.OptionLevel(rawValue: identifier)!
    let (displayItem, inherited) = optionNode.displayItemForOptionLevel(optionLevel)
    let explicit = !inherited
    let highlighted = explicit && optionLevel == optionNode.mostSpecializedOptionLevel
    let editable = optionNode.editableForOptionLevel(optionLevel)

    let view: NSView?
    switch optionNode.valueType {
      case .String:
        view = outlineView.makeViewWithIdentifier(OptionsEditorController.tableCellViewIdentifier,
                                                  owner: self)
        if let tableCellView = view as? TextTableCellView {
          prepareTableCellView(tableCellView,
                               withValue: displayItem,
                               explicit: explicit,
                               highlighted: highlighted,
                               editable: editable)
        }

      case .Bool:
        // TODO(abaire): Track down why NSPopUpButton ignores mutation to attributedTitle and remove
        //               the boldPopUpButtonCell here and from the storyboard.
        let identifier: String
        if explicit {
          identifier = OptionsEditorController.boldPopUpButtonCellViewIdentifier
        }
        else {
          identifier = OptionsEditorController.popUpButtonCellViewIdentifier
        }
        view = outlineView.makeViewWithIdentifier(identifier, owner: self)
        if let tableCellView = view as? PopUpButtonTableCellView {
          preparePopUpButtonTableCellView(tableCellView,
                                          withMenuItems: optionNode.multiSelectItems,
                                          selectedValue: displayItem,
                                          highlighted: highlighted,
                                          editable: editable)
        }
    }
    return view
  }

  func outlineView(outlineView: NSOutlineView, shouldSelectItem item: AnyObject) -> Bool {
    func setColumnsSelectedForRow(rowIndex: Int, selected: Bool) {
      guard rowIndex >= 0 && rowIndex < view.numberOfRows,
            let rowView = view.rowViewAtRow(rowIndex, makeIfNecessary: false) else {
        return
      }
      for i in 0..<rowView.numberOfColumns {
        if let columnView = rowView.viewAtColumn(i) as? TextTableCellView {
          columnView.selected = selected
        }
      }
    }

    setColumnsSelectedForRow(outlineView.selectedRow, selected: false)
    setColumnsSelectedForRow(view.rowForItem(item), selected: true)
    return true
  }

  // MARK: - NSPopoverDelegate

  func popoverDidClose(notification: NSNotification) {
    if notification.userInfo?[NSPopoverCloseReasonKey] as? String != NSPopoverCloseReasonStandard {
      return
    }

    if popoverViewController.closeReason == .Accept {
      reloadDataForRow(view.selectedRow)
    }
    popoverEditor = nil
  }

  // MARK: - Private methods

  private func optionNodeForItem(item: AnyObject, outlineView: NSOutlineView) -> OptionsEditorNode {
    guard let treeNode = item as? NSTreeNode else {
      assertionFailure("Item must be an NSTreeNode")
      return nodes[0]
    }
    return treeNode.representedObject as! OptionsEditorNode
  }

  private func optionNodeAndLevelForControl(control: NSControl) -> (OptionsEditorNode, OptionsEditorNode.OptionLevel) {
    let item = view.itemAtRow(view.rowForView(control))
    let node = optionNodeForItem(item!, outlineView: view)
    let columnIndex = view.columnForView(control)
    let columnIdentifier = view.tableColumns[columnIndex].identifier
    let level = OptionsEditorNode.OptionLevel(rawValue: columnIdentifier)!
    return (node, level)
  }

  /// Populates the given table cell view with this option's content
  private func prepareTableCellView(view: TextTableCellView,
                                    withValue value: String,
                                    explicit: Bool,
                                    highlighted: Bool,
                                    editable: Bool) {
    guard let textField = view.textField else { return }
    textField.enabled = editable

    view.drawsBackground = highlighted
    if highlighted {
      textField.textColor = NSColor.controlTextColor()
    } else {
      textField.textColor = NSColor.disabledControlTextColor()
    }

    let attributedValue = NSMutableAttributedString(string: value)
    attributedValue.setAttributes([NSFontAttributeName: fontForOption(explicit)],
                                  range: NSRange(location: 0, length: attributedValue.length))
    textField.attributedStringValue = attributedValue
  }

  private func preparePopUpButtonTableCellView(view: PopUpButtonTableCellView,
                                               withMenuItems menuItems: [String],
                                               selectedValue: String,
                                               highlighted: Bool,
                                               editable: Bool) {
    let button = view.popUpButton
    button.removeAllItems()
    button.addItemsWithTitles(menuItems)
    button.selectItemWithTitle(selectedValue)
    button.enabled = editable
    view.drawsBackground = highlighted
  }

  private func fontForOption(explicit: Bool) -> NSFont {
    if explicit {
      return NSFont.boldSystemFontOfSize(11)
    }
    return NSFont.systemFontOfSize(11)
  }

  private func reloadDataForEditedControl(control: NSControl) {
    reloadDataForRow(view.rowForView(control))
  }

  private func reloadDataForRow(row: Int) {
    let item = view.itemAtRow(row)!
    let indexes = NSMutableIndexSet(index: row)
    if let parent = view.parentForItem(item) {
      indexes.addIndex(view.rowForItem(parent))
    } else {
      let numChildren = view.numberOfChildrenOfItem(item)
      for i in 0..<numChildren {
        let child = view.child(i, ofItem: item)
        indexes.addIndex(view.rowForItem(child))
      }
    }

    let columnRange = NSRange(location: 0, length: view.numberOfColumns)
    view.reloadDataForRowIndexes(indexes, columnIndexes: NSIndexSet(indexesInRange: columnRange))
  }
}
