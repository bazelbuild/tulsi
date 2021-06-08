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

@testable import ModuleCachePruner

/// Writes a JSON metadata file to a temporary location and returns a URL to that location.
func createFakeMetadataFile(contents: RawExplicitModulesMetadata) throws -> URL {
  let temporaryFileURL = getTemporaryJSONFileURL()
  let jsonData = try JSONEncoder().encode(contents)
  try jsonData.write(to: temporaryFileURL)
  return temporaryFileURL
}

/// Convenience function that abstracts away the need to provide the JSON data in the required
/// format. Instead, this function accepts FakeModule objects and converts them into the required
/// format.
func createFakeMetadataFile(withExplicitModules modules: [FakeModule]) throws -> URL {
  let fakeMetadataBody = modules.map {
    RawExplicitModuleBody(
      path: $0.explicitFilepath, name: $0.name)
  }
  let fakeMetadata = RawExplicitModulesMetadata(explicitModules: fakeMetadataBody)
  return try createFakeMetadataFile(contents: fakeMetadata)
}
