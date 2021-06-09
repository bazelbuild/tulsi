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
import XCTest

@testable import ModuleCachePruner

/// Converts a Dictionary that uses Arrays for the values into a nearly identical Dictionary that
/// instead uses Sets for the values. This allows us to test for Dictionary equality without
/// needing to worry about the ordering in the values.
func convertArrayValuesToSetValues(_ input: [String: [URL]]) -> [String: Set<URL>] {
  return Dictionary(uniqueKeysWithValues: input.map { ($0, Set($1)) })
}

class ImplicitModuleTests: XCTestCase {
  let modules = FakeModules()
  var fakeModuleCacheURL: URL?

  override func tearDown() {
    if let moduleCacheURL = fakeModuleCacheURL {
      try? FileManager.default.removeItem(at: moduleCacheURL)
    }
  }

  func testMappingModulesInModuleCache() {
    guard
      let moduleCacheURL = createFakeModuleCache(
        withSwiftModules: [
          modules.system.foundation, modules.system.coreFoundation, modules.system.darwin,
        ],
        andClangModules: [
          "DirectoryHash1": [
            modules.user.buttonsLib, modules.user.buttonsIdentity, modules.user.buttonsModel,
          ],
          "DirectoryHash2": [
            modules.user.buttonsLib, modules.user.buttonsIdentity, modules.user.buttonsModel,
          ],
        ])
    else {
      XCTFail("Failed to create fake module cache required for test.")
      return
    }

    fakeModuleCacheURL = moduleCacheURL

    let subdirectory1 = moduleCacheURL.appendingPathComponent("DirectoryHash1")
    let subdirectory2 = moduleCacheURL.appendingPathComponent("DirectoryHash2")
    let expectedImplicitModuleMapping = [
      modules.user.buttonsLib.name: [
        subdirectory1.appendingPathComponent(modules.user.buttonsLib.implicitFilename),
        subdirectory2.appendingPathComponent(modules.user.buttonsLib.implicitFilename),
      ],
      modules.user.buttonsIdentity.name: [
        subdirectory1.appendingPathComponent(modules.user.buttonsIdentity.implicitFilename),
        subdirectory2.appendingPathComponent(modules.user.buttonsIdentity.implicitFilename),
      ],
      modules.user.buttonsModel.name: [
        subdirectory1.appendingPathComponent(modules.user.buttonsModel.implicitFilename),
        subdirectory2.appendingPathComponent(modules.user.buttonsModel.implicitFilename),
      ],
    ]

    let actualImplicitModuleMapping = getImplicitModules(moduleCacheURL: moduleCacheURL)
    XCTAssertEqual(
      convertArrayValuesToSetValues(actualImplicitModuleMapping),
      convertArrayValuesToSetValues(expectedImplicitModuleMapping))
  }
}
