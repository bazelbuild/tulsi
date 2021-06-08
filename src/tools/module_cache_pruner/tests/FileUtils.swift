// Copyright 2021 The Tulsi Authors. All rights reserved.
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

private let fileManager = FileManager.default

/// Returns a URL to a location for a JSON file with a random filename under the macOS temporary
/// directory. This function does not create a file at that location.
func getTemporaryJSONFileURL() -> URL {
  let temporaryDirectoryURL = URL(
    fileURLWithPath: NSTemporaryDirectory(),
    isDirectory: true)
  let temporaryFilename = ProcessInfo().globallyUniqueString
  return temporaryDirectoryURL.appendingPathComponent("\(temporaryFilename).json")
}
