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
  case Error, Warning, Syslog, Info, Debug
}

/// Message levels used for identifying priority and ordering in UI. @objc to use from a Storyboard.
@objc
public enum LogMessagePriority: Int {
  case error, warning, syslog, info, debug
}

extension TulsiMessageLevel {
  public var logRank: LogMessagePriority {
    switch self {
    case .Error:
      return .error
    case .Warning:
      return .warning
    case .Syslog:
      return .syslog
    case .Info:
      return .info
    case .Debug:
      return .debug
    }
  }
}

public struct LogMessage {
  public let level: TulsiMessageLevel
  public let message: String
  public let details: String?
  public let context: String?

  // Sends a notification to display any errors that have been logged with postError.
  public static func displayPendingErrors() {
    let userInfo = [ "displayErrors" : true ]
    NotificationCenter.default.post(name: Notification.Name(rawValue: TulsiMessageNotification),
                                    object: nil,
                                    userInfo: userInfo)
  }

  // Sends a notification to log an error and adds it to a list of errors that can be displayed
  // through the UI. Note that the errors are only displayed through the UI when
  // displayPendingErrors() is called.
  public static func postError(_ message: String, details: String? = nil, context: String? = nil) {
    postMessage(.Error, message: message, details: details, context: context)
  }

  public static func postWarning(_ message: String, details: String? = nil, context: String? = nil) {
    postMessage(.Warning, message: message, details: details, context: context)
  }

  public static func postInfo(_ message: String, details: String? = nil, context: String? = nil) {
    postMessage(.Info, message: message, details: details, context: context)
  }

  public static func postSyslog(_ message: String, details: String? = nil, context: String? = nil) {
    postMessage(.Syslog, message: message, details: details, context: context)
  }

  public static func postDebug(_ message: String, details: String? = nil, context: String? = nil) {
    postMessage(.Debug, message: message, details: details, context: context)
  }

  /// Convenience method to post a notification that may be converted into a TulsiMessageItem.
  private static func postMessage(_ level: TulsiMessageLevel,
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

    NotificationCenter.default.post(name: Notification.Name(rawValue: TulsiMessageNotification),
                                                            object: nil,
                                                            userInfo: userInfo)
  }

  public init?(notification: Notification) {
    guard notification.name.rawValue == TulsiMessageNotification,
          let userInfo = notification.userInfo,
          let levelString = userInfo["level"] as? String,
          let message = userInfo["message"] as? String,
          let level = TulsiMessageLevel(rawValue: levelString) else {
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

/// Sent when building source/setting groupings for indexer libraries.
public let GatheringIndexerSources = "gatheringIndexerSources"

/// Sent when creating Xcode build targets.
public let GeneratingBuildTargets = "generatingBuildTargets"

/// Sent when creating Xcode indexer targets.
public let GeneratingIndexerTargets = "generatingIndexerTargets"

/// Sent when copying the build scripts into the output Xcode project.
public let InstallingScripts = "installingScripts"

/// Sent when copying the build utilities into the output Xcode project.
public let InstallingUtilities = "installingUtilities"

/// Sent when copying the generator config into the output Xcode project.
public let InstallingGeneratorConfig = "installingGeneratorConfig"

/// Sent when starting to serialize the Xcode project.
public let SerializingXcodeProject = "serializingXcodeProject"

/// Sent when extracting source files from Bazel rules.
public let SourceFileExtraction = "sourceFileExtraction"

/// Sent when extracting workspace information.
public let WorkspaceInfoExtraction = "workspaceInfoExtraction"
