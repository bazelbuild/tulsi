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


// Models a node in the source filter picker.
final class SourcePathNode: UISelectableOutlineViewNode {

  /// Whether or not this specific node is set as recursive-enabled (rather than some child marking
  /// it as mixed state).
  @objc dynamic var explicitlyRecursive: Bool {
    return recursive == NSControl.StateValue.on.rawValue
  }

  /// This node's recursive UI state (NSOnState/NSOffState/NSMixedState).
  @objc dynamic var recursive: Int {
    get {
      guard let entry = entry as? UISourcePath else { return NSControl.StateValue.off.rawValue }
      if entry.recursive { return NSControl.StateValue.on.rawValue }

      for child in children as! [SourcePathNode] {
        if child.recursive != NSControl.StateValue.off.rawValue {
          return NSControl.StateValue.mixed.rawValue
        }
      }
      return NSControl.StateValue.off.rawValue
    }

    set {
      // No work needs to be done for mixed state, as it does not affect the underlying values.
      if newValue == NSControl.StateValue.mixed.rawValue { return }

      guard let entry = entry as? UISourcePath else { return }
      let enabled = newValue == NSControl.StateValue.on.rawValue
      willChangeValue(for: \.explicitlyRecursive)
      entry.recursive = enabled
      didChangeValue(for: \.explicitlyRecursive)

      // If this node is newly recursive, force hasRecursiveEnabledParent, otherwise have children
      // inherit this node's status.
      setChildrenHaveRecursiveParent(enabled || hasRecursiveEnabledParent)

      // Notify KVO that this node's ancestors have also changed state.
      var child: SourcePathNode? = self
      while let parent = child?.parent as? SourcePathNode {
        parent.willChangeValue(for: \.recursive)
        parent.didChangeValue(for: \.recursive)
        child = parent
      }
    }
  }

  @objc dynamic var hasRecursiveEnabledParent: Bool = false {
    willSet {
      // If this node is recursive its children will still have a recursive parent and there's no
      // need to update them.
      if recursive == NSControl.StateValue.on.rawValue || newValue == hasRecursiveEnabledParent { return }
      setChildrenHaveRecursiveParent(newValue)
    }
  }

  @objc func validateRecursive(_ ioValue: AutoreleasingUnsafeMutablePointer<AnyObject?>) throws {
    if let value = ioValue.pointee as? NSNumber {
      if value.intValue == NSControl.StateValue.mixed.rawValue {
        ioValue.pointee = NSNumber(value: NSControl.StateValue.on.rawValue as Int)
      }
    }
  }

  // MARK: - Private methods

  fileprivate func setChildrenHaveRecursiveParent(_ newValue: Bool) {
    for child in children as! [SourcePathNode] {
      child.hasRecursiveEnabledParent = newValue
      // Children of a recursive-enabled node may not be recursive themselves (it's redundant and
      // potentially confusing).
      if newValue {
        child.recursive = NSControl.StateValue.off.rawValue
      }
    }
  }
}


// Controller for the view allowing users to select a subset of the source files to include in the
// generated Xcode project.
final class ConfigEditorSourceFilterViewController: NSViewController, WizardSubviewProtocol {
  @objc dynamic var sourceFilterContentArray: [SourcePathNode] = []
  @IBOutlet weak var sourceFilterOutlineView: NSOutlineView!

  override func viewDidLoad() {
    super.viewDidLoad()
    let sourceTargetColumn = sourceFilterOutlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "sourceTargets"))!
    sourceFilterOutlineView.sortDescriptors = [sourceTargetColumn.sortDescriptorPrototype!]
  }

  // MARK: - WizardSubviewProtocol

  weak var presentingWizardViewController: ConfigEditorWizardViewController? = nil

  func wizardSubviewWillActivateMovingForward() {
    let document = representedObject as! TulsiGeneratorConfigDocument
    sourceFilterContentArray = []
    document.updateSourcePaths(populateOutlineView)

    document.updateChangeCount(.changeDone)
  }

  // MARK: - Private methods

  private func populateOutlineView(_ sourcePaths: [UISourcePath]) {
    // Decompose each rule and merge into a tree of subelements.
    let componentDelimiters = CharacterSet(charactersIn: "/:")
    let splitSourcePaths = sourcePaths.map() {
      $0.path.components(separatedBy: componentDelimiters)
    }

    var recursiveNodes = [SourcePathNode]()

    let topNode = SourcePathNode(name: "")
    for i in 0 ..< splitSourcePaths.count {
      let label = splitSourcePaths[i]
      var node = topNode
      elementLoop: for element in label {
        if element == "" {
          continue
        }
        for child in node.children as! [SourcePathNode] {
          if child.name == element {
            node = child
            continue elementLoop
          }
        }
        let newNode = SourcePathNode(name: element)
        node.addChild(newNode)
        node = newNode
      }
      node.entry = sourcePaths[i]
      if node.recursive == NSControl.StateValue.on.rawValue {
        recursiveNodes.append(node)
      }
    }

    // Patch up the recursive status now that the entire tree is constructed.
    for node in recursiveNodes {
      node.setChildrenHaveRecursiveParent(true)
    }

    sourceFilterContentArray = topNode.children as! [SourcePathNode]
  }
}
