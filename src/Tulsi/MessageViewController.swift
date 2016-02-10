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


/// NSTableView that posts a notification when live resizing completes.
class MessageTableView: NSTableView {
  override func viewDidEndLiveResize() {
    super.viewDidEndLiveResize()

    // Give the delegate a chance to handle the resize now that the live operation is completed.
    NSNotificationCenter.defaultCenter().postNotificationName(NSTableViewColumnDidResizeNotification,
                                                              object: self)
  }
}


/// View controller for the message output area in the Tulsi wizard.
class MessageViewController: NSViewController, NSTableViewDelegate, NSUserInterfaceValidations {
  let minRowHeight = CGFloat(16.0)

  @IBOutlet var messageArrayController: NSArrayController!
  @IBOutlet weak var messageAreaScrollView: NSScrollView!

  // Display heights of each row in the message table.
  var rowHeights = [Int: CGFloat]()

  dynamic var messageCount: Int = 0 {
    didSet {
      // Assume that a reduction in the message count means all cached heights are invalid.
      if messageCount < oldValue {
        rowHeights.removeAll(keepCapacity: true)
      }
      scrollToNewRowIfAtBottom()
    }
  }

  override func loadView() {
    NSValueTransformer.setValueTransformer(MessageTypeToImageValueTransformer(),
                                           forName: "MessageTypeToImageValueTransformer")
    super.loadView()
    bind("messageCount", toObject: messageArrayController, withKeyPath: "arrangedObjects.@count", options: nil)
  }

  @IBAction func copy(sender: AnyObject?) {
    guard let selectedItems = messageArrayController.selectedObjects as? [NSPasteboardWriting] where !selectedItems.isEmpty else {
      return
    }

    let pasteboard = NSPasteboard.generalPasteboard()
    pasteboard.clearContents()
    pasteboard.writeObjects(selectedItems)
  }

  // MARK: - NSUserInterfaceValidations

  func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
    if item.action() == Selector("copy:") {
      return !messageArrayController.selectedObjects.isEmpty
    }
    return false
  }

  // MARK: - NSTableViewDelegate

  func tableView(tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    if let height = rowHeights[row] {
      return height
    }
    let message = messageArrayController.arrangedObjects[row] as! UIMessage
    let column = tableView.tableColumns.first!
    let cell = column.dataCell as! NSTextFieldCell
    cell.stringValue = message.text
    let bounds = CGRect(x: 0, y: 0, width: column.width, height: CGFloat.max)
    let requiredSize = cell.cellSizeForBounds(bounds)
    let height = max(requiredSize.height, minRowHeight)
    rowHeights[row] = height
    return height
  }

  func tableViewColumnDidResize(notification: NSNotification) {
    guard let tableView = notification.object as? NSTableView else { return }
    // Wait until resizing completes before doing a lot of work.
    if tableView.inLiveResize {
      return
    }
    // Disable animation.
    NSAnimationContext.beginGrouping()
    NSAnimationContext.currentContext().duration = 0
    rowHeights.removeAll(keepCapacity: true)
    let numRows = messageArrayController.arrangedObjects.count
    let allRowsIndex = NSIndexSet(indexesInRange: NSRange(location: 0, length: numRows))
    tableView.noteHeightOfRowsWithIndexesChanged(allRowsIndex)
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
class MessageTypeToImageValueTransformer : NSValueTransformer {
  override class func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override class func allowsReverseTransformation() -> Bool  {
    return false
  }

  override func transformedValue(value: AnyObject?) -> AnyObject? {
    guard let intValue = value as? Int,
          messageType = UIMessage.MessageType(rawValue: intValue) else {
      return nil
    }

    switch messageType {
      case .Info:
        return NSImage(named: "message_info")
      case .Warning:
        return NSImage(named: "message_warning")
      case .Error:
        return NSImage(named: "message_error")
    }
  }
}
