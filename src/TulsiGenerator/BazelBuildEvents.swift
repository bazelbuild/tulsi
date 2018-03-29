// Copyright 2017 The Tulsi Authors. All rights reserved.
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

/// A Bazel Build Event parsed from its JSON representation. Currently this is only used for seeing
/// what files are generated.
class BazelBuildEvent {
  let files: [String]

  init(eventDictionary: [String: AnyObject]) {
    var files = [String]()
    if let namedSetOfFiles = eventDictionary["namedSetOfFiles"] as? [String: AnyObject],
       let fileDicts = namedSetOfFiles["files"] as? [[String: AnyObject]] {
      for fileDict in fileDicts {
        guard let uri = fileDict["uri"] as? String else { continue }
        // File URIs have a 'file://' prefix, so remove if present.
        if uri.hasPrefix("file://") {
          let index = uri.index(uri.startIndex, offsetBy: 7)
          files.append(String(uri[index...]))
        }
      }
    }
    self.files = files
  }
}

class BazelBuildEventsReader {

  private let filePath: String
  private let localizedMessageLogger: LocalizedMessageLogger

  init(filePath: String, localizedMessageLogger: LocalizedMessageLogger) {
    self.filePath = filePath
    self.localizedMessageLogger = localizedMessageLogger
  }

  func readAllEvents() throws -> [BazelBuildEvent] {
    let string = try String(contentsOfFile: filePath, encoding: .utf8)
    var newEvents = [BazelBuildEvent]()
    string.enumerateLines { line, _ in
      guard let event = self.parseBuildEventFromLine(line) else { return }
      newEvents.append(event)
    }
    return newEvents
  }

  func parseBuildEventFromLine(_ line: String) -> BazelBuildEvent? {
    guard let data = line.data(using: .utf8) else {
      localizedMessageLogger.warning("BazelParseBuildEventFailed",
                                     comment: "Error to show when unable to parse a Bazel Build Event JSON dictionary. Additional information: %1$@.",
                                     values:"Failed to convert string to UTF-8")
      return nil
    }
    do {
      guard let json = try JSONSerialization.jsonObject(with: data,
                                                        options: JSONSerialization.ReadingOptions())
                                                        as? [String: AnyObject] else {
        localizedMessageLogger.warning("BazelParseBuildEventFailed",
                                       comment: "Error to show when unable to parse a Bazel Build Event JSON dictionary. Additional information: %1$@.",
                                       values:"Failed to parse event JSON from string: " + line)
        return nil
      }
      return BazelBuildEvent(eventDictionary: json)
    } catch let e as NSError {
      localizedMessageLogger.warning("BazelParseBuildEventFailed",
                                     comment: "Error to show when unable to parse a Bazel Build Event JSON dictionary. Additional information: %1$@.",
                                     values:"Error when parsing JSON: " + e.localizedDescription)
      return nil
    } catch {
      localizedMessageLogger.warning("BazelParseBuildEventFailed",
                                     comment: "Error to show when unable to parse a Bazel Build Event JSON dictionary. Additional information: %1$@.",
                                     values:"Unknown error when parsing JSON from string: " + line)
      return nil
    }
  }
}
