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


/// View controller encapsulating the Tulsi generator config wizard.
final class ConfigEditorWizardViewController: NSViewController, NSPageControllerDelegate {
  // The storyboard identifiers for the wizard subpage view controllers.
  static let wizardPageIdentifiers = [
      "BUILDTargetSelect",
      "Options",
      "SourceTargetSelect",
  ]
  static let LastPageIndex = wizardPageIdentifiers.count - 1
  var pageViewController: NSPageController! = nil

  @IBOutlet weak var previousButton: NSButton!
  @IBOutlet weak var nextButton: NSButton!

  override var representedObject: Any? {
    didSet {
      // Update the current wizard page, if any.
      pageViewController?.selectedViewController?.representedObject = representedObject
    }
  }

  override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
    if segue.identifier! == "Embed Wizard PageController" {
      pageViewController = (segue.destinationController as! NSPageController)
      pageViewController.arrangedObjects = ConfigEditorWizardViewController.wizardPageIdentifiers
      pageViewController.delegate = self
    }
    super.prepare(for: segue, sender: sender)
  }

  func setNextButtonEnabled(_ enabled: Bool) {
    nextButton.isEnabled = enabled
  }

  func updateNextButton() {
    if pageViewController.selectedIndex == 0 {
      let document = representedObject as! TulsiGeneratorConfigDocument
      nextButton.isEnabled = document.selectedRuleInfoCount > 0
    }
  }

  @IBAction func cancel(_ sender: AnyObject?) {
    let document = representedObject as! TulsiGeneratorConfigDocument
    do {
      try document.revert()
    } catch {
      // Nothing useful can be done here with failures to revert so the exception is ignored.
    }
    document.close()
  }

  @IBAction func next(_ sender: NSButton? = nil) {
    if let deactivatingSubview = pageViewController.selectedViewController as? WizardSubviewProtocol, deactivatingSubview.shouldWizardSubviewDeactivateMovingForward?() == false {
      return
    }

    var selectedIndex = pageViewController.selectedIndex
    if selectedIndex >= ConfigEditorWizardViewController.LastPageIndex {
      let document = representedObject as! TulsiGeneratorConfigDocument
      document.save() { (canceled, error) in
        if !canceled && error == nil {
          document.close()
        }
      }
      return
    }

    pageViewController!.navigateForward(sender)
    selectedIndex += 1
    previousButton.isHidden = false

    if selectedIndex == ConfigEditorWizardViewController.LastPageIndex {
      nextButton.title = NSLocalizedString("Wizard_SaveConfig",
                                           comment: "Label for action button to be used to go to the final page in the project wizard.")
    }
  }

  @IBAction func previous(_ sender: NSButton? = nil) {
    if let deactivatingSubview = pageViewController.selectedViewController as? WizardSubviewProtocol, deactivatingSubview.shouldWizardSubviewDeactivateMovingBackward?() == false {
      return
    }

    var selectedIndex = pageViewController!.selectedIndex
    if selectedIndex > 0 {
      previousButton.isHidden = selectedIndex <= 1
      pageViewController!.navigateBack(sender)
      selectedIndex -= 1
      nextButton.isEnabled = true

      if selectedIndex < ConfigEditorWizardViewController.LastPageIndex {
        nextButton.title = NSLocalizedString("Wizard_Next",
                                             comment: "Label for action button to be used to go to the next page in the project wizard.")
      }
    }
  }

  // MARK: - NSPageControllerDelegate

  func pageController(_ pageController: NSPageController, identifierFor object: Any) -> NSPageController.ObjectIdentifier {
    return object as! NSPageController.ObjectIdentifier
  }

  func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier) -> NSViewController {
    let vc = storyboard!.instantiateController(withIdentifier: identifier) as! NSViewController

    // NSPageController doesn't appear to support Autolayout properly, so fall back to
    // autoresizingMask.
    vc.view.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
    return vc
  }

  func pageController(_ pageController: NSPageController,
                      prepare viewController: NSViewController,
                      with object: Any?) {
    _pageController(pageController, prepareViewController: viewController, withObject: object! as AnyObject)
  }

  private func _pageController(_ pageController: NSPageController,
                               prepareViewController viewController: NSViewController,
                               withObject object: AnyObject) {
    // By default, the viewController will have its representedObject set to the currently selected
    // member of the pageController's arrangedObjects. Wizard pages need to represent the underlying
    // TulsiDocument, so it's set here.
    viewController.representedObject = representedObject

    // This index is guaranteed to exist due to fixed number of pages we have.
    let newPageIndex = ConfigEditorWizardViewController.wizardPageIdentifiers.firstIndex(of: object as! String)!
    let subview = viewController as? WizardSubviewProtocol
    subview?.presentingWizardViewController = self
    if pageController.selectedIndex < newPageIndex {
      subview?.wizardSubviewWillActivateMovingForward?()
    } else if pageController.selectedIndex > newPageIndex {
      subview?.wizardSubviewWillActivateMovingBackward?()
    }
  }

  func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
    if let subview = pageController.selectedViewController as? WizardSubviewProtocol {
      subview.wizardSubviewDidDeactivate?()
    }
    pageController.completeTransition()
  }
}

