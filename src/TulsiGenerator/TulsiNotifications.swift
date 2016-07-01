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

/// Sent when message information should be displayed to the user and/or sent to the system log.
/// The userInfo dictionary contains:
///   "level": String - The level of the message (see TulsiMessageLevel)
///   "message": String - The body of the message.
///   "details": String? - Optional detailed information about the message.
///   "context": String? - Optional contextual information about the message.
public let TulsiMessageNotification = "com.google.tulsi.Message"

/// Message levels used by TulsiMessage notifications.
public enum TulsiMessageLevel: String {
  case Error, Warning, Info, Syslog
}

public struct LogMessage {
  public let level: TulsiMessageLevel
  public let message: String
  public let details: String?
  public let context: String?

  public static func postError(message: String, details: String? = nil, context: String? = nil) {
    postMessage(.Error, message: message, details: details, context: context)
  }

  public static func postWarning(message: String, details: String? = nil, context: String? = nil) {
    postMessage(.Warning, message: message, details: details, context: context)
  }

  public static func postInfo(message: String, details: String? = nil, context: String? = nil) {
    postMessage(.Info, message: message, details: details, context: context)
  }

  public static func postSyslog(message: String, details: String? = nil, context: String? = nil) {
    postMessage(.Syslog, message: message, details: details, context: context)
  }

  /// Convenience method to post a notification that may be converted into a TulsiMessageItem.
  private static func postMessage(level: TulsiMessageLevel,
                                  message: String,
                                  details: String? = nil,
                                  context: String? = nil) {
    var userInfo = [
        "level": level.rawValue,
        "message": message,
    ]
    if let details = details {
      userInfo["details"] = details
    }
    if let context = context {
      userInfo["context"] = context
    }

    NSNotificationCenter.defaultCenter().postNotificationName(TulsiMessageNotification,
                                                              object: nil,
                                                              userInfo: userInfo)
  }

  public init?(notification: NSNotification) {
    guard notification.name == TulsiMessageNotification,
          let userInfo = notification.userInfo,
          let levelString = userInfo["level"] as? String,
          let message = userInfo["message"] as? String,
          let level = TulsiMessageLevel(rawValue: levelString) else {
      // TODO(abaire): Remove useless initialization when Swift 2.1 support is dropped.
      self.level = .Error
      self.message = ""
      self.details = nil
      self.context = nil
      return nil
    }

    self.level = level
    self.message = message
    self.details = userInfo["details"] as? String
    self.context = userInfo["context"] as? String
  }
}

/// Sent when the Tulsi generator initiates a task whose progress may be tracked.
/// The userInfo dictionary contains:
///   "name": String - The name of the task.
///   "maxValue": Int - The maximum value of the task
///   "progressNotificationName" - The name of the notification that will be sent when progress
///       changes.
///   "startIndeterminate" - Whether or not there might be an indeterminate delay before the first
///       update (for instance if a long initialization is required before actual work is begun).
public let ProgressUpdatingTaskDidStart = "com.google.tulsi.progressUpdatingTaskDidStart"
public let ProgressUpdatingTaskName = "name"
public let ProgressUpdatingTaskMaxValue = "maxValue"
public let ProgressUpdatingTaskStartIndeterminate = "startIndeterminate"

/// Sent when a task's progress changes.
/// The userInfo dictionary contains "value": Int - the new progress
public let ProgressUpdatingTaskProgress = "com.google.tulsi.progressUpdatingTaskProgress"
public let ProgressUpdatingTaskProgressValue = "value"

/// Sent when creating Xcode build targets.
public let GeneratingBuildTargets = "generatingBuildTargets"

/// Sent when creating Xcode indexer targets.
public let GeneratingIndexerTargets = "generatingIndexerTargets"

/// Sent when copying the build scripts into the output Xcode project.
public let InstallingScripts = "installingScripts"

/// Sent when copying the generator config into the output Xcode project.
public let InstallingGeneratorConfig = "installingGeneratorConfig"

/// Sent when starting to serialize the Xcode project.
public let SerializingXcodeProject = "serializingXcodeProject"

/// Sent when extracting source files from Bazel rules.
public let SourceFileExtraction = "sourceFileExtraction"

/// Sent when extracting workspace information.
public let WorkspaceInfoExtraction = "workspaceInfoExtraction"
