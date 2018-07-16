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

extension String {
  // Escape the string for the shell by enclosing it in single quotes if needed. When enclosing in
  // single quotes, we must replace single quotes with '\\'' which outputs '\''.
  // See https://stackoverflow.com/a/1315213 for more information.
  public var escapingForShell: String {
    guard rangeOfCharacter(from: .whitespaces) != nil || contains("'") || contains("$") else {
      return self
    }
    let escapedString = replacingOccurrences(of: "'", with: "'\\''")
    return "'\(escapedString)'"
  }
}
