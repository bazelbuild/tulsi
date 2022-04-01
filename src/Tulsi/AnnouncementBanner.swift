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

  var delegate: AnnouncementBannerDelegate?

  let messageView = NSView(frame: CGRect.zero)
  let messageLabel = NSTextField(wrappingLabelWithString: "Placeholder")
  let dismissButton = NSButton(frame: CGRect.zero)

  let margin = CGFloat(8)

  // MARK: - Initializers

  init(announcement: Announcement) {
    self.announcement = announcement

    super.init(frame: CGRect.zero)
    wantsLayer = true
    translatesAutoresizingMaskIntoConstraints = false

    messageView.translatesAutoresizingMaskIntoConstraints = false

    messageLabel.stringValue = announcement.bannerMessage
    messageLabel.setAccessibilityLabel(announcement.bannerMessage)
    messageLabel.isBezeled = false
    messageLabel.isEditable = false
    messageLabel.isSelectable = false
    messageLabel.translatesAutoresizingMaskIntoConstraints = false

    if announcement.link != nil {
      let gestureRecognizer = NSClickGestureRecognizer(
        target: self,
        action: #selector(openUrl(_:)))
      messageView.addGestureRecognizer(gestureRecognizer)
    }

    dismissButton.target = self
    dismissButton.action = #selector(didClickDismissButton(_:))
    dismissButton.wantsLayer = true
    dismissButton.layer?.backgroundColor = NSColor.clear.cgColor
    dismissButton.isBordered = false
    dismissButton.translatesAutoresizingMaskIntoConstraints = false

    let accessiblityComment = "Dismisses the announcement banner."
    let dismissButtonAccessibilityLabel = NSLocalizedString(
      "AnnouncementBanner_DismissButtonAccessibilityLabel", comment: accessiblityComment)
    dismissButton.setAccessibilityLabel(dismissButtonAccessibilityLabel)

    dismissButton.image = NSImage(
      systemSymbolName: "xmark.circle.fill", accessibilityDescription: accessiblityComment)
    dismissButton.contentTintColor = NSColor.white
    layer?.backgroundColor = NSColor.systemGray.cgColor
    messageLabel.textColor = NSColor.white

    self.addSubview(messageView)
    messageView.addSubview(messageLabel)
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
    self.delegate?.announcementBannerWasDismissed(banner: self)
  }

  @objc func openUrl(_ sender: Any?) {
    if let link = announcement.link, let url = URL(string: link) {
      NSWorkspace.shared.open(url)
    }
  }

  // Mark - Private Setup Functions

  func activateConstraints() {
    removeConstraints(self.constraints)

    let views = ["view": messageView, "btn": dismissButton]
    let labels = ["msg": messageLabel]

    messageView.addConstraints(
      NSLayoutConstraint.constraints(
        withVisualFormat: "H:|-8-[msg]-8-|", options: .alignAllCenterX, metrics: nil,
        views: labels))
    messageView.addConstraints(
      NSLayoutConstraint.constraints(
        withVisualFormat: "V:|-8-[msg]-8-|", options: .directionLeadingToTrailing, metrics: nil,
        views: labels))

    self.addConstraints(
      NSLayoutConstraint.constraints(
        withVisualFormat: "H:|-0-[view]-0-[btn]-8-|",
        options: NSLayoutConstraint.FormatOptions.alignAllCenterY, metrics: nil, views: views))
    messageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    dismissButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)

    self.addConstraints(
      NSLayoutConstraint.constraints(
        withVisualFormat: "V:|-0-[view]-0-|", options: .directionLeadingToTrailing, metrics: nil,
        views: views))
  }
}

protocol AnnouncementBannerDelegate {
  func announcementBannerWasDismissed(banner: AnnouncementBanner)
}
