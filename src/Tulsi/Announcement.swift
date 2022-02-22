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
  var bannerMessage: String
  var cliMessage: String
  var link: String?
  var shouldAppearAtTopOfCLIOutput: Bool

  enum CodingKeys: String, CodingKey {
    case id = "announcementId"
    case bannerMessage
    case cliMessage
    case link
    case shouldAppearAtTopOfCLIOutput
  }

  // MARK: - Instance methods

  func createBanner() -> AnnouncementBanner {
    return AnnouncementBanner(announcement: self)
  }

  func createCLIOutput() -> String {
    var linkText = ""
    if let link = link {
        linkText = "Link: \(link)\n"
    }

    let mainTextContent = """
      \(cliMessage)
      \(linkText)
      To disable this message, please run

      generate_xcodeproj.sh --mark-read \(id)
      """
    let contentSeparator = "**************************"

    if shouldAppearAtTopOfCLIOutput {
      return """

        \(contentSeparator)

        \(mainTextContent)

        \(contentSeparator)

        """
    } else {
      return """

        \(contentSeparator)

        \(mainTextContent)

        """
    }
  }

  func hasBeenDismissed() -> Bool {
    return UserDefaults.standard.bool(forKey: id)
  }

  func recordDismissal() {
    UserDefaults.standard.set(true, forKey: id)
  }

  // MARK: - Static methods

  static func getAllAnnouncements() throws -> [Announcement] {
    guard let jsonPath = Bundle.main.url(forResource: "AnnouncementConfig", withExtension: "json")
    else {
      throw TulsiError(errorMessage: "Failed to locate configuration file for announcements")
    }

    let data = try Data(contentsOf: jsonPath)
    let decoder = JSONDecoder()

    return try decoder.decode([Announcement].self, from: data)
  }

  static func getNextUnreadAnnouncement() throws -> Announcement? {
    return try getAllAnnouncements().first(where: {!$0.hasBeenDismissed()})
  }

  static func loadAnnouncement(byId id: String) throws -> Announcement? {
    return try getAllAnnouncements().first(where: {$0.id == id})
  }
}
