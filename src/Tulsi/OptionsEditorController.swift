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
  @objc optional func deleteKeyPressedForOptionsEditorOutlineView(_ view: OptionsEditorOutlineView) -> Bool
}


/// Outline view containing the options editor.
final class OptionsEditorOutlineView: NSOutlineView {
  override func keyDown(with theEvent: NSEvent) {
    guard let eventCharacters = theEvent.charactersIgnoringModifiers else {
      super.keyDown(with: theEvent)
      return
    }

    // Eat spacebar presses as the option editor view does not support activation of rows this way.
    if eventCharacters == " " {
      return
    }

    if let delegate = self.delegate as? OptionsEditorOutlineViewDelegate {
      let scalars = eventCharacters.unicodeScalars
      if scalars.count == 1 {
        let character = scalars[scalars.startIndex]
        if character == UnicodeScalar(NSDeleteCharacter) ||
            character == UnicodeScalar(NSBackspaceCharacter) ||
            character == UnicodeScalar(NSDeleteFunctionKey) ||
            character == UnicodeScalar(NSDeleteCharFunctionKey) {
          if let handled = delegate.deleteKeyPressedForOptionsEditorOutlineView?(self), handled {
            return
          }
        }
      }
    }

    super.keyDown(with: theEvent)
  }
}


/// Table cell view with the ability to draw a background.
class TextTableCellView: NSTableCellView {
  @IBInspectable var drawsBackground: Bool = false {
    didSet {
      needsDisplay = true
    }
  }

  @IBInspectable var backgroundColor: NSColor = NSColor.controlBackgroundColor {
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

  override func draw(_ dirtyRect: NSRect) {
    if drawsBackground {
      if selected {
        NSColor.clear.setFill()
      } else {
        backgroundColor.setFill()
      }

      dirtyRect.fill()
    }
    super.draw(dirtyRect)
  }
}


/// A table cell view containing a pop up button.
final class PopUpButtonTableCellView: TextTableCellView {
  @IBOutlet weak var popUpButton: NSPopUpButton!
}


/// A text field within the editor outline view.
final class OptionsEditorTextField: NSTextField {
  override func textDidEndEditing(_ notification: Notification) {
    var notification = notification
    // If the text field completed due to a return keypress convert its movement into "other" so
    // that the keypress is not passed up the responder chain causing some other control (e.g., the
    // default button in the wizard) to handle it as well.
    if let movement = notification.userInfo?["NSTextMovement"] as? Int, movement == NSReturnTextMovement {
      let userInfo = ["NSTextMovement": NSOtherTextMovement]
      notification = Notification(name: notification.name, object: notification.object, userInfo: userInfo)
    }
    super.textDidEndEditing(notification)
  }
}


/// View controller for the multiline popup editor displayed when a user double clicks an option.
final class OptionsEditorPopoverViewController: NSViewController, NSTextFieldDelegate {
  @objc dynamic var value: String? = nil

  enum CloseReason {
    case cancel, accept
  }
  var closeReason: CloseReason = .accept
  var optionItem: AnyObject? = nil

  fileprivate weak var popover: NSPopover? = nil

  private var optionNode: OptionsEditorNode! = nil
  private var optionLevel: OptionsEditorNode.OptionLevel = .Default

  func setRepresentedOptionNode(_ optionNode: OptionsEditorNode, level: OptionsEditorNode.OptionLevel) {
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

  func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
    if closeReason == .accept {
      optionNode.setDisplayItem(fieldEditor.string, forOptionLevel: optionLevel)
    }
    return true
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    switch commandSelector {
      // Operations that cancel.
      case #selector(NSControl.cancelOperation(_:)):
        closeReason = .cancel

      // Operations that commit the current value.
      case #selector(NSControl.insertNewline(_:)):
        closeReason = .accept
        popover?.performClose(control)
        return true

      // Operations that should be disabled.
      case #selector(NSControl.insertBacktab(_:)):
        fallthrough
      case #selector(NSControl.insertTab(_:)):
        return true

      default:
        break
    }

    // Allow the system to handle the selector.
    return false
  }
}


final class OptionsEditorController: NSObject, OptionsEditorOutlineViewDelegate, NSPopoverDelegate {
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
  // The table column used to display system or tulsiproj defaults.
  let defaultValueColumn: NSTableColumn
  // The table column used to display project-wide options.
  let projectValueColumn: NSTableColumn
  // The table column used to display build target-specific build options.
  let targetValueColumn: NSTableColumn

  @objc dynamic var nodes = [OptionsEditorNode]()
  weak var model: OptionsEditorModelProtocol? = nil {
    didSet {
      guard let model = model else { return }
      defaultValueColumn.title = model.defaultValueColumnTitle
      projectValueColumn.title = model.projectValueColumnTitle
    }
  }

  // Popover containing a multiline editor for an option the user double clicked on.
  var popoverEditor: NSPopover! = nil
  var popoverViewController: OptionsEditorPopoverViewController! = nil

  init(view: NSOutlineView, storyboard: NSStoryboard) {
    self.view = view
    self.storyboard = storyboard
    defaultValueColumn = view.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: OptionsEditorController.defaultColumnIdentifier))!
    projectValueColumn = view.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: OptionsEditorController.projectColumnIdentifier))!
    targetValueColumn = view.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: OptionsEditorController.targetColumnIdentifier))!
    super.init()
    self.view.delegate = self
  }

  /// Prepares the editor view to edit options with the most specialized column set to the given
  /// target rule.
  func prepareEditorForTarget(_ target: UIRuleInfo?) {
    if target == nil {
      targetValueColumn.isHidden = true
    } else {
      targetValueColumn.title = target!.targetName!
      targetValueColumn.isHidden = false
    }

    var newOptionNodes = [OptionsEditorNode]()
    var optionGroupNodes = [TulsiOptionKeyGroup: OptionsEditorGroupNode]()

    let optionSet = model?.optionSet
    guard let visibleOptions = optionSet?.allVisibleOptions else { return }
    for (key, option) in visibleOptions {
      let newNode: OptionsEditorNode
      switch option.valueType {
        case .bool:
          newNode = OptionsEditorBooleanNode(key: key, option: option, model: model, target: target)
        case .string:
          newNode = OptionsEditorStringNode(key: key,
                                            option: option,
                                            model: model,
                                            target: target)
        case .stringEnum:
          newNode = OptionsEditorConstrainedStringNode(key: key,
                                                       option: option,
                                                       model: model,
                                                       target: target)
      }

      if let (group, displayName, description) = optionSet?.groupInfoForOptionKey(key) {
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
    nodes = newOptionNodes.sorted { $0.name < $1.name }
  }

  func stringBasedControlDidCompleteEditing(_ control: NSControl) {
    let (node, modifiedLevel) = optionNodeAndLevelForControl(control)
    node.setDisplayItem(control.stringValue, forOptionLevel: modifiedLevel)
    reloadDataForEditedControl(control)
  }

  func popUpFieldDidCompleteEditing(_ button: NSPopUpButton) {
    let (node, level) = optionNodeAndLevelForControl(button)
    node.setDisplayItem(button.titleOfSelectedItem, forOptionLevel: level)
    reloadDataForEditedControl(button)
  }

  func didDoubleClickInEditorView(_ editor: NSOutlineView) {
    if editor.clickedRow < 0 || editor.clickedColumn < 0 {
      return
    }

    let clickedColumn = editor.tableColumns[editor.clickedColumn]
    let columnIdentifier = clickedColumn.identifier
    guard let optionLevel = OptionsEditorNode.OptionLevel(rawValue: columnIdentifier.rawValue) else {
      assert(columnIdentifier.rawValue == OptionsEditorController.settingColumnIdentifier,
             "Mismatch in storyboard column identifier and OptionLevel enum")
      return
    }
    let optionItem = editor.item(atRow: editor.clickedRow)!
    let optionNode = optionNodeForItem(optionItem as AnyObject, outlineView: editor)

    // Verify that the column is editable.
    if OptionsEditorController.bindingsControlledColumns.contains(columnIdentifier.rawValue) ||
        !optionNode.editableForOptionLevel(optionLevel) {
      return
    }

    if optionNode.supportsMultilineEditor,
       let view = editor.view(atColumn: editor.clickedColumn,
                                      row: editor.clickedRow,
                                      makeIfNecessary: false) {

      popoverEditor = NSPopover()
      if popoverViewController == nil {
        popoverViewController = storyboard.instantiateController(withIdentifier: "OptionsEditorPopover") as? OptionsEditorPopoverViewController
      }
      popoverEditor.contentViewController = popoverViewController
      popoverViewController.optionItem = optionItem as AnyObject?
      popoverViewController.setRepresentedOptionNode(optionNode, level: optionLevel)
      popoverViewController.popover = popoverEditor
      popoverEditor.delegate = self
      popoverEditor.behavior = .semitransient
      popoverEditor.show(relativeTo: NSRect(), of: view, preferredEdge: .minY)
    }
  }

  // MARK: - OptionsEditorOutlineViewDelegate

  func deleteKeyPressedForOptionsEditorOutlineView(_ view: OptionsEditorOutlineView) -> Bool {
    let selectedRow = view.selectedRow
    if selectedRow < 0 || selectedRow >= nodes.count { return false }
    let selectedNode = optionNodeForItem(view.item(atRow: selectedRow)! as AnyObject, outlineView: view)
    if selectedNode.deleteMostSpecializedValue() {
      reloadDataForRow(selectedRow)
      return true
    }

    return false
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    if tableColumn == nil { return nil }

    let identifier = tableColumn!.identifier
    if OptionsEditorController.bindingsControlledColumns.contains(identifier.rawValue) {
      return outlineView.makeView(withIdentifier: identifier, owner: self)
    }

    let optionNode = optionNodeForItem(item as AnyObject, outlineView: outlineView)
    let optionLevel = OptionsEditorNode.OptionLevel(rawValue: identifier.rawValue)!
    let (displayItem, inherited) = optionNode.displayItemForOptionLevel(optionLevel)
    let explicit = !inherited
    let highlighted = explicit && optionLevel == optionNode.mostSpecializedOptionLevel
    let editable = optionNode.editableForOptionLevel(optionLevel)

    let view: NSView?
    switch optionNode.valueType {
      case .string:
        view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: OptionsEditorController.tableCellViewIdentifier),
                                                  owner: self)
        if let tableCellView = view as? TextTableCellView {
          prepareTableCellView(tableCellView,
                               withValue: displayItem,
                               explicit: explicit,
                               highlighted: highlighted,
                               editable: editable)
        }

      case .stringEnum:
        fallthrough
      case .bool:
        let identifier: String
        if explicit {
          identifier = OptionsEditorController.boldPopUpButtonCellViewIdentifier
        }
        else {
          identifier = OptionsEditorController.popUpButtonCellViewIdentifier
        }
        view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: identifier), owner: self)
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

  func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
    func setColumnsSelectedForRow(_ rowIndex: Int, selected: Bool) {
      guard rowIndex >= 0 && rowIndex < view.numberOfRows,
            let rowView = view.rowView(atRow: rowIndex, makeIfNecessary: false) else {
        return
      }
      for i in 0 ..< rowView.numberOfColumns {
        if let columnView = rowView.view(atColumn: i) as? TextTableCellView {
          columnView.selected = selected
        }
      }
    }

    setColumnsSelectedForRow(outlineView.selectedRow, selected: false)
    setColumnsSelectedForRow(view.row(forItem: item), selected: true)
    return true
  }

  // MARK: - NSPopoverDelegate

  func popoverDidClose(_ notification: Notification) {
    if notification.userInfo?[NSPopover.closeReasonUserInfoKey] as? String != NSPopover.CloseReason.standard.rawValue {
      return
    }

    if popoverViewController.closeReason == .accept {
      reloadDataForItem(popoverViewController.optionItem)
    }
    popoverEditor = nil
  }

  // MARK: - Private methods

  private func optionNodeForItem(_ item: AnyObject, outlineView: NSOutlineView) -> OptionsEditorNode {
    guard let treeNode = item as? NSTreeNode else {
      assertionFailure("Item must be an NSTreeNode")
      return nodes[0]
    }
    return treeNode.representedObject as! OptionsEditorNode
  }

  private func optionNodeAndLevelForControl(_ control: NSControl) -> (OptionsEditorNode, OptionsEditorNode.OptionLevel) {
    let item = view.item(atRow: view.row(for: control))
    let node = optionNodeForItem(item! as AnyObject, outlineView: view)
    let columnIndex = view.column(for: control)
    let columnIdentifier = view.tableColumns[columnIndex].identifier
    let level = OptionsEditorNode.OptionLevel(rawValue: columnIdentifier.rawValue)!
    return (node, level)
  }

  /// Populates the given table cell view with this option's content
  private func prepareTableCellView(_ view: TextTableCellView,
                                    withValue value: String,
                                    explicit: Bool,
                                    highlighted: Bool,
                                    editable: Bool) {
    guard let textField = view.textField else { return }
    textField.isEnabled = editable

    view.drawsBackground = highlighted
    if highlighted {
      textField.textColor = NSColor.controlTextColor
    } else {
      textField.textColor = NSColor.disabledControlTextColor
    }

    let attributedValue = NSMutableAttributedString(string: value)
    attributedValue.setAttributes([NSAttributedString.Key.font: fontForOption(explicit)],
                                  range: NSRange(location: 0, length: attributedValue.length))
    textField.attributedStringValue = attributedValue
  }

  private func preparePopUpButtonTableCellView(_ view: PopUpButtonTableCellView,
                                               withMenuItems menuItems: [String],
                                               selectedValue: String,
                                               highlighted: Bool,
                                               editable: Bool) {
    let button = view.popUpButton
    button?.removeAllItems()
    button?.addItems(withTitles: menuItems)
    button?.selectItem(withTitle: selectedValue)
    button?.isEnabled = editable
    view.drawsBackground = highlighted
  }

  private func fontForOption(_ explicit: Bool) -> NSFont {
    if explicit {
      return NSFont.boldSystemFont(ofSize: 11)
    }
    return NSFont.systemFont(ofSize: 11)
  }

  private func reloadDataForEditedControl(_ control: NSControl) {
    reloadDataForRow(view.row(for: control))
  }

  private func reloadDataForRow(_ row: Int) {
    guard row >= 0 else { return }
    let item = view.item(atRow: row)!
    reloadDataForItem(item as AnyObject?)
  }

  private func reloadDataForItem(_ item: AnyObject?) {
    let indexes = NSMutableIndexSet(index: view.row(forItem: item))
    if let parent = view.parent(forItem: item) {
      indexes.add(view.row(forItem: parent))
    } else {
      let numChildren = view.numberOfChildren(ofItem: item)
      for i in 0 ..< numChildren {
        let child = view.child(i, ofItem: item)
        let childIndex = view.row(forItem: child)
        if childIndex >= 0 {
          indexes.add(childIndex)
        }
      }
    }

    // Reload everything in the mutable middle columns. The values in the "setting" and "default"
    // columns never change.
    let columnRange = NSRange(location: 1, length: view.numberOfColumns - 2)
    view.reloadData(forRowIndexes: indexes as IndexSet, columnIndexes: IndexSet(integersIn: Range(columnRange)!))
  }
}
