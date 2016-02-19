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
    case General

    /// An attempt has been made to generate an Xcode project from a generator config that is
    /// missing critical information.
    case ConfigNotGenerateable
    /// An attempt has been made to load a config from an URL which is not valid.
    case ConfigNotLoadable
    /// An attempt has been made to save a generator config which is missing critical information.
    case ConfigNotSaveable
  }

  convenience init(errorMessage: String) {
    let fmt = NSLocalizedString("TulsiError_General",
                                comment: "A generic exception was thrown, additional debug data is in %1$@.")
    self.init(code: .General, userInfo: [NSLocalizedDescriptionKey: String(format: fmt, errorMessage)])
  }

  init(code: ErrorCode, var userInfo: [String: AnyObject]? = nil) {
    if userInfo == nil {
      userInfo = [NSLocalizedDescriptionKey: TulsiError.localizedErrorMessageForCode(code)]
    } else if userInfo?[NSLocalizedDescriptionKey] == nil {
      userInfo![NSLocalizedDescriptionKey] = TulsiError.localizedErrorMessageForCode(code)
    }
    super.init(domain: "Tulsi", code: code.rawValue, userInfo: userInfo)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  // MARK: - Private methods

  private static func localizedErrorMessageForCode(errorCode: ErrorCode) -> String {
    // TODO(abaire): Localize.
    switch errorCode {
      case .ConfigNotGenerateable:
        return "Generator config is not fully populated and cannot generate an Xcode project."
      case .ConfigNotLoadable:
        return "Generator config could not be loaded from the given location."
      case .ConfigNotSaveable:
        return "Generator config is not fully populated and cannot be saved."

      case .General:
        return "A general error of type \(errorCode) occurred."
    }
  }
}
