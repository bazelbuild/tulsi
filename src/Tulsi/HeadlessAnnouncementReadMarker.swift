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

/// Provides functionality to mark an announcement as read so it does not display on future
/// headless runs.
struct HeadlessAnnouncementReadMarker {

  let arguments: TulsiCommandlineParser.Arguments

  init(arguments: TulsiCommandlineParser.Arguments) {
    self.arguments = arguments
  }

  /// Marks the specified announcement as read.
  func markRead() throws {
    guard let announcementIdToMarkRead = arguments.announcementId else {
      throw HeadlessModeError.missingAnnouncementId
    }

    guard let announcement = try Announcement.loadAnnouncement(byId: announcementIdToMarkRead) else
    {
      throw HeadlessModeError.invalidAnnouncementId
    }

    announcement.recordDismissal()
    print("\(announcementIdToMarkRead) has been marked read and will not appear again.")
  }
}
