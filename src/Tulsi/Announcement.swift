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

import Foundation

/// Provides a model for announcements shown in the announcement banner.
struct Announcement: Codable {
  var id: String
  var link: String?
  var message: String

  enum CodingKeys: String, CodingKey {
    case id = "announcementId"
    case link
    case message
  }

  func createBanner() -> AnnouncementBanner {
    return AnnouncementBanner(announcement: self)
  }

  func hasBeenDismissed() -> Bool {
    return UserDefaults.standard.bool(forKey: id)
  }

  func recordDismissal() {
    UserDefaults.standard.set(true, forKey: id)
  }
}
