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

import Foundation


@objc
protocol WizardSubviewProtocol {
  /// Informs the receiver of the enclosing WizardViewController.
  var presentingWizardViewController: ConfigEditorWizardViewController? { get set }

  /// Invoked when the wizard subview is about to become active due to a "next" navigation.
  @objc optional func wizardSubviewWillActivateMovingForward()

  /// Invoked when the wizard subview is about to become active due to a "previous" navigation.
  @objc optional func wizardSubviewWillActivateMovingBackward()

  /// Invoked when the wizard subview is about to become inactive due to a "next" navigation. If the
  /// receiver returns false, the navigation action will be cancelled.
  @objc optional func shouldWizardSubviewDeactivateMovingForward() -> Bool

  /// Invoked when the wizard subview is about to become inactive due to a "previous" navigation. If
  /// the receiver returns false, the navigation action will be cancelled.
  @objc optional func shouldWizardSubviewDeactivateMovingBackward() -> Bool

  /// Invoked when the wizard subview is no longer active.
  @objc optional func wizardSubviewDidDeactivate()
}
