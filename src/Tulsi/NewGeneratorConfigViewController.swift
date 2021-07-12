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


/// Protocol used to inform receiver of a NewGeneratorConfigViewController's exit status.
protocol NewGeneratorConfigViewControllerDelegate: AnyObject {
  func viewController(_ vc: NewGeneratorConfigViewController,
                      didCompleteWithReason: NewGeneratorConfigViewController.CompletionReason)
}


/// View controller for the new TulsiGeneratorConfig sheet.
final class NewGeneratorConfigViewController: NSViewController {

  /// The reason that a NewProjectViewController exited.
  enum CompletionReason {
    case cancel, create
  }

  weak var delegate: NewGeneratorConfigViewControllerDelegate?

  @objc dynamic var configName: String? = nil

  @IBAction func didClickCancelButton(_ sender: NSButton) {
    delegate?.viewController(self, didCompleteWithReason: .cancel)
  }

  @IBAction func didClickSaveButton(_ sender: NSButton) {
    self.delegate?.viewController(self, didCompleteWithReason: .create)
  }
}
