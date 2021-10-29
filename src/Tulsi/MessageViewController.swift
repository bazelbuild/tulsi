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


/// NSTableView that posts a notification when live resizing completes.
final class MessageTableView: NSTableView {
  override func viewDidEndLiveResize() {
    super.viewDidEndLiveResize()

    // Give the delegate a chance to handle the resize now that the live operation is completed.
    NotificationCenter.default.post(name: NSTableView.columnDidResizeNotification,
                                                              object: self)
  }
}


/// View controller for the message output area in the Tulsi wizard.
final class MessageViewController: NSViewController, NSTableViewDelegate, NSUserInterfaceValidations {
  let minRowHeight = CGFloat(16.0)

  @IBOutlet var messageArrayController: NSArrayController!
  @IBOutlet weak var messageAreaScrollView: NSScrollView!

  // Display heights of each row in the message table.
  var rowHeights = [Int: CGFloat]()

  @objc dynamic var messageCount: Int = 0 {
    didSet {
      // Assume that a reduction in the message count means all cached heights are invalid.
      if messageCount < oldValue {
        rowHeights.removeAll(keepingCapacity: true)
      }
      scrollToNewRowIfAtBottom()
    }
  }

  override func loadView() {
    ValueTransformer.setValueTransformer(MessageTypeToImageValueTransformer(),
                                           forName: NSValueTransformerName(rawValue: "MessageTypeToImageValueTransformer"))
    super.loadView()
    bind(NSBindingName(rawValue: "messageCount"), to: messageArrayController!, withKeyPath: "arrangedObjects.@count", options: nil)
  }

  @IBAction func copy(_ sender: AnyObject?) {
    guard let selectedItems = messageArrayController.selectedObjects as? [NSPasteboardWriting], !selectedItems.isEmpty else {
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects(selectedItems)
  }

  @IBAction func clearMessages(_ sender: AnyObject?) {
    (self.representedObject as! TulsiProjectDocument).clearMessages()
  }

  // MARK: - NSUserInterfaceValidations

  func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(copy(_:)) {
      return !messageArrayController.selectedObjects.isEmpty
    }
    return false
  }

  // MARK: - NSTableViewDelegate

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    if let height = rowHeights[row] {
      return height
    }
    let message = (messageArrayController.arrangedObjects as! [UIMessage])[row]
    let column = tableView.tableColumns.first!
    let cell = column.dataCell as! NSTextFieldCell
    cell.stringValue = message.text
    let bounds = CGRect(x: 0, y: 0, width: column.width, height: CGFloat.greatestFiniteMagnitude)
    let requiredSize = cell.cellSize(forBounds: bounds)
    let height = max(requiredSize.height, minRowHeight)
    rowHeights[row] = height
    return height
  }

  func tableViewColumnDidResize(_ notification: Notification) {
    guard let tableView = notification.object as? NSTableView else { return }
    // Wait until resizing completes before doing a lot of work.
    if tableView.inLiveResize {
      return
    }
    // Disable animation.
    NSAnimationContext.beginGrouping()
    NSAnimationContext.current.duration = 0
    rowHeights.removeAll(keepingCapacity: true)
    let numRows = (messageArrayController.arrangedObjects as AnyObject).count!
    let allRowsIndex = IndexSet(integersIn: 0..<numRows)

    tableView.noteHeightOfRows(withIndexesChanged: allRowsIndex)
    NSAnimationContext.endGrouping()
  }

  // MARK: - Private methods

  private func scrollToNewRowIfAtBottom() {
    guard messageCount > 0,
        let tableView = messageAreaScrollView.documentView as? NSTableView else {
      return
    }

    let lastRowIndex = messageCount - 1

    let scrollContentViewBounds = messageAreaScrollView.contentView.bounds
    let contentViewHeight = scrollContentViewBounds.height

    let newRowHeight = self.tableView(tableView, heightOfRow: lastRowIndex) + tableView.intercellSpacing.height
    let bottomScrollY = tableView.frame.maxY - (contentViewHeight + newRowHeight)

    if scrollContentViewBounds.origin.y >= bottomScrollY {
      tableView.scrollRowToVisible(lastRowIndex)
    }
  }
}


/// Transformer that converts a UIMessage type into an image to be displayed in the message view.
final class MessageTypeToImageValueTransformer : ValueTransformer {
  override class func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override class func allowsReverseTransformation() -> Bool  {
    return false
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let intValue = value as? Int,
          let messageType = TulsiGenerator.LogMessagePriority(rawValue: intValue) else {
      return nil
    }

    switch messageType {
      case .info, .debug, .syslog:
        return NSImage(named: "message_info")
      case .warning:
        return NSImage(named: "message_warning")
      case .error:
        return NSImage(named: "message_error")
    }
  }
}
