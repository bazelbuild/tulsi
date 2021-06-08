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
import os

/// The top level structure of the metadata file we need to parse.
struct RawExplicitModulesMetadata: Codable {
  var explicitModules: [RawExplicitModuleBody]

  private enum CodingKeys : String, CodingKey {
    case explicitModules = "explicit_modules"
  }
}

/// An individual module in the metadata file we need to parse.
struct RawExplicitModuleBody: Codable {
  ///  The path to the explicit module in the bazel outputs directory.
  var path: String
  ///  The full name of the explicit module.
  var name: String
}

/// Reads the given metadata file and returns a list of names of all explicit modules referenced in
/// that file.
func getExplicitModuleNames(fromMetadataFile metadataPath: String) throws -> [String] {
  let metadataURL = URL(fileURLWithPath: metadataPath)
  let data = try Data(contentsOf: metadataURL)
  let jsonData = try JSONDecoder().decode(RawExplicitModulesMetadata.self, from: data)
  return jsonData.explicitModules.map { $0.name }
}
