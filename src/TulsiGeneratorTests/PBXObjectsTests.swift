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
    case fileReference(String)
    case fileReferenceWithName(String, path: String)
    case group(String, contents: [ExpectedStructure])
    case groupWithName(String, path: String, contents: [ExpectedStructure])
    case variantGroup(String, contents: [ExpectedStructure])
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
      .fileReference("root"),
      .group(
        "test",
        contents: [
          .fileReference("test/file"),
        ]),
      .group(
        "deeply",
        contents: [
          .group(
            "nested",
            contents: [
              .group(
                "files",
                contents: [
                  .fileReference("deeply/nested/files/1"),
                  .fileReference("deeply/nested/files/2"),
                ]),
            ]),
        ]),
      .group(
        "/",
        contents: [
          .group(
            "empty",
            contents: [
              .fileReference("/empty/component"),
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
      "overlapping/file",
    ]
    let paths2 = [
      "2",
      "unique/2",
      "overlapping/file",
      "overlapping/2",
    ]
    let expectedStructure: [ExpectedStructure] = [
      .fileReference("1"),
      .fileReference("2"),
      .group(
        "unique",
        contents: [
          .fileReference("unique/1"),
          .fileReference("unique/2"),
        ]),
      .group(
        "overlapping",
        contents: [
          .fileReference("overlapping/file"),
          .fileReference("overlapping/2"),
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
      .fileReference("test"),
      .fileReference("bundle.xcassets"),
      .group(
        "subdir",
        contents: [
          .fileReference("subdir/test.app"),
          .fileReference("subdir/test2.app"),
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
      "deeply/nested/files/4",
    ]
    let expectedSourceRelativePaths = [
      "1": "1",
      "test/2": "test/2",
      "deeply/nested/files/3": "deeply/nested/files/3",
      "deeply/nested/files/4": "deeply/nested/files/4",
    ]
    project.getOrCreateGroupsAndFileReferencesForPaths(paths)
    for fileRef in project.mainGroup.allSources {
      let sourceRelativePath = fileRef.sourceRootRelativePath
      XCTAssertEqual(sourceRelativePath, expectedSourceRelativePaths[fileRef.path!])
    }
  }

  func testPBXReferenceFileExtension() {
    let filenameToExt: [String: String?] = [
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
      "xcstickers",
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

  func testExternalReferencePathMigration() {
    let mainGroup = project.mainGroup
    let movedDir = "fancyExternalDir"
    let paths = [
      "dir/file",
      "external/project/README.md",
      "external/project/src/file.ext",
    ]
    let expectedStructure: [ExpectedStructure] = [
      .group(
        "dir",
        contents: [
          .fileReference("dir/file"),
        ]),
      .groupWithName(
        "@project", path: movedDir,
        contents: [
          .fileReference("README.md"),
          .group(
            "src",
            contents: [
              .fileReference("src/file.ext"),
            ]),
        ]),
    ]

    project.getOrCreateGroupsAndFileReferencesForPaths(paths)
    guard let extGroup = mainGroup.childGroupsByName["external"] else {
      XCTAssert(false, "Unable to find external group for mainGroup \(mainGroup)")
      return
    }

    for child in extGroup.children {
      guard let group = child as? PBXGroup else {
        XCTAssert(false, "Expected child of external group \(extGroup) to be a group, not \(child)")
        continue
      }

      let newChild = mainGroup.getOrCreateChildGroupByName(
        "@\(child.name)",
        path: movedDir,
        sourceTree: .Absolute)
      newChild.migrateChildrenOfGroup(group)
    }
    mainGroup.removeChild(extGroup)

    assertProjectStructure(expectedStructure, forGroup: project.mainGroup)
  }

  func testVariantGroupHandling() {
    let paths = [
      "Base.lproj/Localizable.strings",
      "en.lproj/Localizable.strings",
    ]
    let expectedStructure: [ExpectedStructure] = [
      .variantGroup(
        "Localizable.strings",
        contents: [
          .fileReferenceWithName("Base", path: "Base.lproj/Localizable.strings"),
          .fileReferenceWithName("en", path: "en.lproj/Localizable.strings"),
        ]),
    ]

    project.getOrCreateGroupsAndFileReferencesForPaths(paths)
    assertProjectStructure(expectedStructure, forGroup: project.mainGroup)
  }

  // MARK: - Helper methods

  func assertProjectStructure(
    _ expectedStructure: [ExpectedStructure],
    forGroup group: PBXGroup,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      group.children.count,
      expectedStructure.count,
      "Mismatch in child count for group '\(group.name)'",
      line: line)

    for element in expectedStructure {
      switch element {
      case .fileReference(let name):
        assertGroup(group, containsSourceTree: .Group, path: name, line: line)

      case .fileReferenceWithName(let name, let path):
        assertGroup(group, containsSourceTree: .Group, path: path, name: name, line: line)

      case .group(let name, let grandChildren):
        let childGroup = assertGroup(group, containsGroupWithName: name, line: line)
        assertProjectStructure(grandChildren, forGroup: childGroup, line: line)

      case .groupWithName(let name, let path, let grandChildren):
        let childGroup = assertGroup(group, containsGroupWithName: name, path: path, line: line)
        assertProjectStructure(grandChildren, forGroup: childGroup, line: line)

      case .variantGroup(let name, let grandChildren):
        let childVariantGroup = assertGroup(group, containsVariantGroupWithName: name, line: line)
        assertProjectStructure(grandChildren, forGroup: childVariantGroup, line: line)
      }
    }
  }

  @discardableResult
  func assertGroup(
    _ group: PBXGroup,
    containsSourceTree sourceTree: SourceTree,
    path: String,
    name: String? = nil,
    line: UInt = #line
  ) -> PBXFileReference {
    let sourceTreePath = SourceTreePath(sourceTree: sourceTree, path: path)
    let fileRef = group.fileReferencesBySourceTreePath[sourceTreePath]
    XCTAssertNotNil(
      fileRef,
      "Failed to find expected PBXFileReference '\(path)' in group '\(group.name)",
      line: line)
    if let name = name {
      XCTAssertEqual(name, fileRef!.name)
    }
    return fileRef!
  }

  func assertGroup(
    _ group: PBXGroup,
    containsGroupWithName name: String,
    path: String? = nil,
    line: UInt = #line
  ) -> PBXGroup {
    let child = group.childGroupsByName[name]
    XCTAssertNotNil(
      child,
      "Failed to find child group '\(name)' in group '\(group.name)'",
      line: line)
    if let path = path {
      XCTAssertNotNil(child!.path, "Expected child \(child!) to have a non-nil path")
      XCTAssertEqual(child!.path, path, "Child path \(child!.path!) != expected path \(path)")
    } else {
      XCTAssertNil(child!.path, "Expected child \(child!) to have a nil path")
    }
    return child!
  }

  func assertGroup(
    _ group: PBXGroup,
    containsVariantGroupWithName name: String,
    line: UInt = #line
  ) -> PBXGroup {
    let child = group.childVariantGroupsByName[name]
    XCTAssertNotNil(
      child,
      "Failed to find child variant group '\(name)' in group '\(group.name)'",
      line: line)
    return child!
  }
}
