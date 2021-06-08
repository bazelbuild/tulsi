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

class ExplicitModuleTests: XCTestCase {
  let modules = FakeModules()
  var fakeMetadataFile: URL?

  override func tearDown() {
    if let fakeMetadataFile = fakeMetadataFile {
      try? FileManager.default.removeItem(at: fakeMetadataFile)
    }
  }

  func testExtractingModuleNamesFromMetatdataFile() {
    do {
      fakeMetadataFile = try createFakeMetadataFile(
        withExplicitModules: [
          modules.system.foundation, modules.system.coreFoundation, modules.user.buttonsLib,
          modules.user.buttonsIdentity,
        ])
    } catch {
      XCTFail("Failed to create required fake metadata file: \(error)")
      return
    }

    let expectedExplicitModuleNames = [
      modules.system.foundation, modules.system.coreFoundation, modules.user.buttonsLib,
      modules.user.buttonsIdentity,
    ].map { $0.name }

    XCTAssertEqual(
      try? getExplicitModuleNames(fromMetadataFile: fakeMetadataFile!.path),
      expectedExplicitModuleNames
    )
  }
}
