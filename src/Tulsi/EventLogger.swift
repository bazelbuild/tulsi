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
import TulsiGenerator


/// Writes events to the console.
final class EventLogger {
  private let verboseLevel: TulsiMessageLevel
  private var observer: NSObjectProtocol? = nil

  private let logFile: FileHandle?

  init(verboseLevel: TulsiMessageLevel, logToFile: Bool=false) {
    self.verboseLevel = verboseLevel

    if logToFile, let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String {
      self.logFile = EventLogger.createLogFile(appName)
    } else {
      self.logFile = nil
    }
  }

  deinit {
    if let observer = self.observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func startLogging() {
    observer = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: TulsiMessageNotification),
                                                      object: nil,
                                                      queue: nil) {
      [weak self] (notification: Notification) in
        guard let item = LogMessage(notification: notification) else {
          return
        }
        self?.logItem(item)
    }
  }

  // MARK: - Private methods

  private static func createLogFile(_ appName: String) -> FileHandle? {
    let fileManager = FileManager.default
    guard let folder = fileManager.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first else {
      return nil
    }

    let tulsiFolder = folder.appendingPathComponent(appName)
    var isDirectory: ObjCBool = false
    let fileExists = fileManager.fileExists(atPath: tulsiFolder.path, isDirectory: &isDirectory)

    if !fileExists || !isDirectory.boolValue {
      do {
        try fileManager.createDirectory(at: tulsiFolder,
                                        withIntermediateDirectories: true,
                                        attributes: nil)
      } catch {
        print("failed to create logging folder at \"\(tulsiFolder)\".")
        return nil
      }
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
    let date = Date()
    let dateString = dateFormatter.string(from: date)

    let logFileUrl = tulsiFolder.appendingPathComponent("generate_log_\(dateString).txt")
    do {
      fileManager.createFile(atPath: logFileUrl.path, contents: nil, attributes: nil)
      return try FileHandle(forWritingTo: logFileUrl)
    } catch {
      print("error creating log file at \"\(logFileUrl.path)\".")
      return nil
    }
  }

  private func logItem(_ item: LogMessage) {
    let level: String = item.level.rawValue

    let logString = "[\(level)] \(item.message)\n"
    if let logFile = self.logFile, let logData = logString.data(using: .utf8) {
      logFile.seekToEndOfFile()
      logFile.write(logData)
    }

    guard self.verboseLevel.logRank.rawValue >= item.level.logRank.rawValue else {
      return
    }

    let details: String
    if let itemDetails = item.details {
      details = " \(itemDetails)"
    } else {
      details = ""
    }
    print("[\(level)] \(item.message)\(details)")
  }
}
