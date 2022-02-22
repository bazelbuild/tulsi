// Copyright 2022 The Tulsi Authors. All rights reserved.
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

/// Banner used for presenting users with announcements.
class AnnouncementBanner: NSView {
  let announcement: Announcement

  let messageLabel = NSTextField(wrappingLabelWithString: "Placeholder")
  let dismissButton = NSButton(frame: CGRect.zero)

  let margin = CGFloat(8)

  // MARK: - Initializers

  init(announcement: Announcement) {
    self.announcement = announcement

    super.init(frame: CGRect.zero)
    wantsLayer = true
    layer?.opacity = 1
    translatesAutoresizingMaskIntoConstraints = false

    messageLabel.stringValue = announcement.bannerMessage
    messageLabel.setAccessibilityLabel(announcement.bannerMessage)
    messageLabel.isBezeled = false
    messageLabel.isEditable = false
    messageLabel.isSelectable = false
    messageLabel.backgroundColor = NSColor.clear
    messageLabel.translatesAutoresizingMaskIntoConstraints = false

    if announcement.link != nil {
      let gestureRecognizer = NSClickGestureRecognizer(
        target: self,
        action: #selector(openUrl(_:)))
      messageLabel.addGestureRecognizer(gestureRecognizer)
    }

    dismissButton.target = self
    dismissButton.action = #selector(didClickDismissButton(_:))
    dismissButton.wantsLayer = true
    dismissButton.layer?.backgroundColor = NSColor.clear.cgColor
    dismissButton.isBordered = false
    dismissButton.translatesAutoresizingMaskIntoConstraints = false

    let dismissButtonAccessibilityLabel = NSLocalizedString(
      "AnnouncementBanner_DismissButtonAccessibilityLabel",
      comment: "Accessibility label for the announcement banner dismiss button")
    dismissButton.setAccessibilityLabel(dismissButtonAccessibilityLabel)

    // If dark mode is supported, use a system color. Otherwise, default to
    // colors that are suitable for light mode.
    if #available(macOS 10.14, *) {
      layer?.backgroundColor = NSColor.controlAccentColor.cgColor
      messageLabel.textColor = NSColor.controlTextColor
      dismissButton.attributedTitle = createTitle(withColor: NSColor.controlTextColor)
    } else {
      layer?.backgroundColor = NSColor.lightGray.cgColor
      messageLabel.textColor = NSColor.black
      dismissButton.attributedTitle = createTitle(withColor: NSColor.black)
    }

    self.addSubview(messageLabel)
    self.addSubview(dismissButton)

    activateConstraints()
  }

  required init?(coder: NSCoder) {
    fatalError("This class does not support NSCoding.")
  }

  // MARK: - IBActions

  /// Pressing the dismiss button will write to UserDefaults to indicate that the user has seen
  /// this announcement and dismissed it
  @objc func didClickDismissButton(_ sender: NSButton) {
    announcement.recordDismissal()
    self.removeFromSuperview()
  }

  @objc func openUrl(_ sender: NSView) {
    if let link = announcement.link, let url = URL(string: link) {
      NSWorkspace.shared.open(url)
    }
  }

  // Mark - Private Setup Functions

  func activateConstraints() {
    removeConstraints(self.constraints)

    // Message label constraints
    let messageLabelCenterYContstraint = NSLayoutConstraint(
      item: messageLabel, attribute: .centerY, relatedBy: .equal, toItem: self,
      attribute: .centerY, multiplier: 1, constant: 0)
    let messageLabelLeadingConstraint = NSLayoutConstraint(
      item: messageLabel, attribute: .leading, relatedBy: .equal, toItem: self,
      attribute: .leading, multiplier: 1, constant: margin)
    let messageLabelTrailingConstraint = NSLayoutConstraint(
      item: messageLabel, attribute: .trailing, relatedBy: .lessThanOrEqual, toItem: dismissButton,
      attribute: .leading, multiplier: 1, constant: -margin)
    let messageLabelTopConstraint = NSLayoutConstraint(
      item: messageLabel, attribute: .top, relatedBy: .equal, toItem: self, attribute: .top,
      multiplier: 1, constant: margin)

    // Dismiss button constraints
    let dismissButtonTrailingConstraint = NSLayoutConstraint(
      item: dismissButton, attribute: .trailing, relatedBy: .equal, toItem: self,
      attribute: .trailing, multiplier: 1, constant: -margin)
    let dismissButtonTopConstraint = NSLayoutConstraint(
      item: dismissButton, attribute: .top, relatedBy: .equal, toItem: self, attribute: .top,
      multiplier: 1, constant: margin)
    let dismissButtonCenterYConstraint = NSLayoutConstraint(
      item: dismissButton, attribute: .centerY, relatedBy: .equal, toItem: self,
      attribute: .centerY, multiplier: 1, constant: 0)

    NSLayoutConstraint.activate([
      messageLabelCenterYContstraint, messageLabelLeadingConstraint,
      messageLabelTrailingConstraint, messageLabelTopConstraint, dismissButtonTrailingConstraint,
      dismissButtonTopConstraint, dismissButtonCenterYConstraint,
    ])
  }

  private func createTitle(withColor color: NSColor) -> NSAttributedString {
    let pstyle = NSMutableParagraphStyle()

    pstyle.alignment = .center

    return NSAttributedString(
      string: "X",
      attributes: [.foregroundColor: color, .paragraphStyle: pstyle])
  }
}
