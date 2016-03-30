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
@testable import TulsiGenerator

// Stub LocalizedMessageLogger that does nothing.
class MockLocalizedMessageLogger: LocalizedMessageLogger {
  var infoMessages = [String]()
  var warningMessageKeys = [String]()
  var errorMessageKeys = [String]()

  init() {
    super.init(messageLogger: nil, bundle: nil)
  }

  override func infoMessage(message: String) {
    infoMessages.append(message)
  }

  override func warning(key: String, comment: String, values: CVarArgType...) {
    warningMessageKeys.append(key)
  }

  override func error(key: String, comment: String, values: CVarArgType...) {
    errorMessageKeys.append(key)
  }
}
