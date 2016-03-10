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


protocol Selectable: class {
  var selected: Bool { get set }
}

/// Models a UIRuleEntry as a node suitable for an outline view controller.
class UISelectableOutlineViewNode: NSObject {

  /// The display name for this node.
  let name: String

  /// The object contained by this node (only valid for leaf nodes).
  var entry: Selectable? {
    didSet {
      if entry != nil {
        selected = entry!.selected
      }
    }
  }

  /// This node's children.
  var children = [UISelectableOutlineViewNode]()

  /// This node's parent.
  weak var parent: UISelectableOutlineViewNode?

  /// Whether or not this node is selected in the UI.
  var selected: Bool {
    didSet {
      entry?.selected = selected
    }
  }

  init(name: String) {
    self.selected = false
    self.name = name
    super.init()
  }

  func state() -> Int {
    if children.isEmpty {
      return selected ? NSOnState : NSOffState
    }

    var stateIsValid = false
    var state = NSOffState
    for node in children {
      if !stateIsValid {
        state = node.state()
        stateIsValid = true
        continue
      }
      if state != node.state() {
        return NSMixedState
      }
    }
    return state
  }

  func setState(state: Int) {
    let newSelected = (state == NSOnState)
    if selected == newSelected {
      return
    }
    willChangeValueForKey("state")
    selected = newSelected
    for node in children {
      node.setState(state)
    }
    didChangeValueForKey("state")
  }

  // TODO(abaire): Look into whether or not there's a way to prevent the system from setting the
  //               state to mixed in the first place.
  func validateState(ioValue: AutoreleasingUnsafeMutablePointer<AnyObject?>) throws {
    if let value = ioValue.memory as? NSNumber {
      if value.integerValue == NSMixedState {
        ioValue.memory = NSNumber(integer: NSOnState)
      }
    }
  }
}
