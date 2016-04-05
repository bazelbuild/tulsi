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

public protocol MessageLoggerProtocol {
  /// Used to report a non-fatal warning message.
  func warning(message: String)

  /// Used to report a fatal error message, optionally with a detailed message to be shown in the
  /// resulting alert popup.
  func error(message: String, details: String?)

  /// Used to display a general status message.
  func info(message: String)
}

extension MessageLoggerProtocol {
  func error(message: String) {
    error(message, details: nil)
  }
}
