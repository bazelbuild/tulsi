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

import XCTest
@testable import TulsiGenerator


class PBXObjectsTests: XCTestCase {
  enum ExpectedStructure {
    case FileReference(String)
    case Group(String, contents: [ExpectedStructure])
  }

  var project: PBXProject! = nil

  override func setUp() {
    super.setUp()

    project = PBXProject(name: "TestProject")
  }

  // MARK: - Tests

  func testProjectCreateGroupsAndFileReferencesForPaths() {
    let paths = [
        "root",
        "test/file",
        "deeply/nested/files/1",
        "deeply/nested/files/2",
        "/empty/component",
    ]
    let expectedStructure: [ExpectedStructure] = [
        .FileReference("root"),
        .Group("test", contents: [
            .FileReference("file"),
        ]),
        .Group("deeply", contents: [
            .Group("nested", contents: [
                .Group("files", contents: [
                    .FileReference("1"),
                    .FileReference("2"),
                ]),
            ]),
        ]),
        .Group("/", contents: [
            .Group("empty", contents: [
                .FileReference("component"),
            ]),
        ]),
    ]

    project.getOrCreateGroupsAndFileReferencesForPaths(paths)
    assertProjectStructure(expectedStructure, forGroup: project.mainGroup)
  }

  func testProjectCreateGroupsAndFileReferencesForNoPathsIsNoOp() {
    let mainGroup: PBXGroup = project.mainGroup
    XCTAssertEqual(mainGroup.children.count, 0)
    project.getOrCreateGroupsAndFileReferencesForPaths([])
    XCTAssertEqual(mainGroup.children.count, 0)
  }

  func testProjectCreateGroupsAndFileReferencesForPathsMultiplePaths() {
    let paths1 = [
        "1",
        "unique/1",
        "overlapping/file"
    ]
    let paths2 = [
        "2",
        "unique/2",
        "overlapping/file",
        "overlapping/2"
    ]
    let expectedStructure: [ExpectedStructure] = [
        .FileReference("1"),
        .FileReference("2"),
        .Group("unique", contents: [
            .FileReference("1"),
            .FileReference("2"),
        ]),
        .Group("overlapping", contents: [
            .FileReference("file"),
            .FileReference("2"),
        ]),
    ]

    project.getOrCreateGroupsAndFileReferencesForPaths(paths1)
    project.getOrCreateGroupsAndFileReferencesForPaths(paths2)
    assertProjectStructure(expectedStructure, forGroup: project.mainGroup)
  }

  func testProjectCreateGroupsAndFileReferencesForBundlePath() {
    let paths = [
        "test",
        "bundle.xcassets/test_content",
        "subdir/test.app/file_inside",
        "subdir/test2.app/dir_inside/file_inside",
    ]
    let expectedStructure: [ExpectedStructure] = [
        .FileReference("test"),
        .FileReference("bundle.xcassets"),
        .Group("subdir", contents: [
            .FileReference("test.app"),
            .FileReference("test2.app"),
        ]),
    ]

    project.getOrCreateGroupsAndFileReferencesForPaths(paths)
    assertProjectStructure(expectedStructure, forGroup: project.mainGroup)
  }

  func testSourceRelativePathGeneration() {
    let paths = [
        "1",
        "test/2",
        "deeply/nested/files/3",
        "deeply/nested/files/4"
    ]
    let expectedSourceRelativePaths = [
        "1": "1",
        "2": "test/2",
        "3": "deeply/nested/files/3",
        "4": "deeply/nested/files/4"
    ]
    project.getOrCreateGroupsAndFileReferencesForPaths(paths)
    for fileRef in project.mainGroup.allSources {
      let sourceRelativePath = fileRef.sourceRootRelativePath
      XCTAssertEqual(sourceRelativePath, expectedSourceRelativePaths[fileRef.path!])
    }
  }

  func testPBXReferenceFileExtension() {
    let filenameToExt: Dictionary<String, String?> = [
        "test.file": "file",
        "test": nil,
        "test.something.ext": "ext",
        "/someplace/test.something.ext": "ext",
    ]

    for (filename, ext) in filenameToExt {
      let f = PBXFileReference(name: "filename", path: filename, sourceTree: .Group, parent: nil)
      XCTAssertEqual(f.fileExtension, ext)

      let g = PBXGroup(name: "filename", path: filename, sourceTree: .Group, parent: nil)
      XCTAssertEqual(g.fileExtension, ext)
    }
  }

  func testPBXReferenceUTI() {
    let fileExtensionsToTest = [
        "a",
        "dylib",
        "swift",
        "xib",
    ]
    for ext in fileExtensionsToTest {
      let filename = "filename.\(ext)"
      let f = PBXFileReference(name: filename, path: filename, sourceTree: .Group, parent: nil)
      let expectedUTI = FileExtensionToUTI[ext]
      XCTAssertEqual(f.uti, expectedUTI, "UTI mismatch for extension '\(ext)'")

      let g = PBXGroup(name: filename, path: filename, sourceTree: .Group, parent: nil)
      XCTAssertEqual(g.uti, expectedUTI, "UTI mismatch for extension '\(ext)'")
    }

    let bundleExtensionsToTest = [
        "app",
        "bundle",
        "xcassets",
    ]
    for ext in bundleExtensionsToTest {
      let filename = "filename.\(ext)"
      let f = PBXFileReference(name: filename, path: filename, sourceTree: .Group, parent: nil)
      let expectedUTI = DirExtensionToUTI[ext]
      XCTAssertEqual(f.uti, expectedUTI, "UTI mismatch for extension '\(ext)'")

      let g = PBXGroup(name: filename, path: filename, sourceTree: .Group, parent: nil)
      XCTAssertEqual(g.uti, expectedUTI, "UTI mismatch for extension '\(ext)'")
    }
  }

  // MARK: - Helper methods

  func assertProjectStructure(expectedStructure: [ExpectedStructure],
                              forGroup group: PBXGroup,
                              line: UInt = __LINE__) {
    XCTAssertEqual(group.children.count,
                   expectedStructure.count,
                   "Mismatch in child count for group '\(group.name)'",
                   line: line)

    for element in expectedStructure {
      switch element {
        case .FileReference(let name):
          assertGroup(group, containsSourceTree: .Group, path: name, line: line)

        case .Group(let name, let grandChildren):
          let childGroup = assertGroup(group, containsGroupWithName: name, line: line)
          assertProjectStructure(grandChildren, forGroup: childGroup, line: line)
      }
    }
  }

  func assertGroup(group: PBXGroup,
                   containsSourceTree sourceTree: SourceTree,
                   path: String,
                   line: UInt = __LINE__) -> PBXFileReference {
    let sourceTreePath = SourceTreePath(sourceTree: sourceTree, path: path)
    let fileRef = group.fileReferencesBySourceTreePath[sourceTreePath]
    XCTAssertNotNil(fileRef,
                    "Failed to find expected PBXFileReference '\(path)' in group '\(group.name)",
                    line: line)
    return fileRef!
  }

  func assertGroup(group: PBXGroup,
                   containsGroupWithName name: String,
                   line: UInt = __LINE__) -> PBXGroup {
    let child = group.childGroupsByName[name]
    XCTAssertNotNil(child,
                    "Failed to find child group '\(name)' in group '\(group.name)'",
                    line: line)
    return child!
  }
}
