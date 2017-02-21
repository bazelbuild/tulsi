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


/// Throwable error type for the Tulsi domain.
class TulsiError: NSError {
  enum ErrorCode: NSInteger {
    /// All purpose generic error.
    case general

    /// An attempt has been made to generate an Xcode project from a generator config that is
    /// missing critical information.
    case configNotGenerateable
    /// An attempt has been made to load a config from an URL which is not valid.
    case configNotLoadable
    /// An attempt has been made to save a generator config which is missing critical information.
    case configNotSaveable
  }

  convenience init(errorMessage: String) {
    let fmt = NSLocalizedString("TulsiError_General",
                                comment: "A generic exception was thrown, additional debug data is in %1$@.")
    self.init(code: .general, userInfo: [NSLocalizedDescriptionKey: String(format: fmt, errorMessage) as AnyObject])
  }

  init(code: ErrorCode, userInfo: [String: AnyObject]? = nil) {
    var userInfo = userInfo
    if userInfo == nil {
      userInfo = [NSLocalizedDescriptionKey: TulsiError.localizedErrorMessageForCode(code) as AnyObject]
    } else if userInfo?[NSLocalizedDescriptionKey] == nil {
      userInfo![NSLocalizedDescriptionKey] = TulsiError.localizedErrorMessageForCode(code) as AnyObject?
    }
    super.init(domain: "Tulsi", code: code.rawValue, userInfo: userInfo)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  // MARK: - Private methods

  private static func localizedErrorMessageForCode(_ errorCode: ErrorCode) -> String {
    switch errorCode {
      case .configNotGenerateable:
        return NSLocalizedString("TulsiError_ConfigNotGenerateable",
                                 comment: "Error message for when the user tried to generate an Xcode project from an incomplete config.")
      case .configNotLoadable:
        return NSLocalizedString("TulsiError_ConfigNotLoadable",
                                 comment: "Error message for when a generator config fails to load for an unspecified reason.")
      case .configNotSaveable:
        return NSLocalizedString("TulsiError_ConfigNotSaveable",
                                 comment: "Generator config is not fully populated and cannot be saved.")

      case .general:
        let fmt = NSLocalizedString("TulsiError_General",
                                    comment: "A generic exception was thrown, additional debug data is in %1$@.")
        return String(format: fmt, "Code: \(errorCode)")
    }
  }
}
