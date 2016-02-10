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


// Controller for the view allowing users to select a subset of the source files to include in the
// generated Xcode project.
class SourceFileViewController: NSViewController, WizardSubviewProtocol {
  dynamic var sourceFileContentArray : [UIRuleNode] = []

  // MARK: - WizardSubviewProtocol

  weak var presentingWizardViewController: WizardViewController? = nil

  func wizardSubviewWillActivateMovingForward() {
    let document = representedObject as! TulsiDocument
    sourceFileContentArray = []
    document.updateSourceRuleEntries(populateOutlineView)
  }

  // MARK: - Private methods

  private func populateOutlineView(sourceRuleEntries: [UIRuleEntry]) {
    var splitSourceRulesEntries: [[String]] = []

    // Decompose each rule and merge into a tree of subelements.
    let componentDelimiters = NSCharacterSet(charactersInString:"/:")
    for sourceRule in sourceRuleEntries {
      splitSourceRulesEntries.append(sourceRule.fullLabel.componentsSeparatedByCharactersInSet(componentDelimiters))
    }
    let topNode = UIRuleNode(name:"")
    for var i = 0; i < splitSourceRulesEntries.count; ++i {
      let label = splitSourceRulesEntries[i]
      var node = topNode
      elementLoop: for element in label {
        if element == "" {
          continue
        }
        for child in node.children {
          if child.name == element {
            node = child
            continue elementLoop
          }
        }
        let newNode = UIRuleNode(name: element)
        node.children.append(newNode)
        node = newNode
      }
      node.entry = sourceRuleEntries[i]
    }
    sourceFileContentArray = topNode.children
  }
}
