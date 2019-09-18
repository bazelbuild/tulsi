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

typealias StringToObjectDict = [String: NSObject]

class PBXProjSerializerTests: XCTestCase {
  var gidGenerator: MockGIDGenerator! = nil
  var project: PBXProject! = nil
  var serializer: OpenStepSerializer! = nil

  override func setUp() {
    super.setUp()

    gidGenerator = MockGIDGenerator()
    project = PBXProject(name: "TestProject")
    serializer = OpenStepSerializer(rootObject: project, gidGenerator: gidGenerator)
  }

  // MARK: - Tests

  func testOpenStepSerializesEmptyDictionaries() {
    let config = project.buildConfigurationList.getOrCreateBuildConfiguration("Empty")
    config.buildSettings = [String: String]()
    config.globalID = gidGenerator.generateReservedID()

    guard let openStepData = serializer.serialize() else {
      XCTFail("Failed to generate OpenStep format")
      return
    }
    let root: StringToObjectDict
    do {
      root = try PropertyListSerialization.propertyList(
        from: openStepData,
        options: [], format: nil) as! StringToObjectDict
    } catch let error as NSError {
      let serializedData = String(data: openStepData, encoding: String.Encoding.utf8)!
      XCTFail(
        "Failed to parse OpenStep serialized data " + error.localizedDescription + "\n"
          + serializedData)
      return
    }

    let objects = root["objects"] as! StringToObjectDict
    let buildConfigDict: StringToObjectDict! = getObjectByID(
      config.globalID,
      withPBXClass: "XCBuildConfiguration",
      fromObjects: objects)
    XCTAssertNotNil(buildConfigDict["buildSettings"])
  }

  func testOpenStepSerializationIsStable() {
    let project1 = PBXProject(name: "TestProject")
    let gidGenerator1 = MockGIDGenerator()
    populateProject(project1, withGIDGenerator: gidGenerator1)
    let serializer1 = OpenStepSerializer(rootObject: project1, gidGenerator: gidGenerator1)
    guard let openStepData1 = serializer1.serialize() else {
      XCTFail("Failed to generate OpenStep format")
      return
    }

    let project2 = PBXProject(name: "TestProject")
    let gidGenerator2 = MockGIDGenerator()
    populateProject(project2, withGIDGenerator: gidGenerator2)
    let serializer2 = OpenStepSerializer(rootObject: project2, gidGenerator: gidGenerator2)
    guard let openStepData2 = serializer2.serialize() else {
      XCTFail("Failed to generate OpenStep format")
      return
    }

    let serializedData1 = String(data: openStepData1, encoding: String.Encoding.utf8)!
    let serializedData2 = String(data: openStepData2, encoding: String.Encoding.utf8)!
    XCTAssertEqual(serializedData1, serializedData2)
  }

  // MARK: - Helper methods

  // Captures the testable values in defining a PBXFileReference.
  struct FileDefinition {
    let sourceTree: SourceTree
    let path: String
    let uti: String?
    let gid: String
    let isInputFile: Bool

    init(sourceTree: SourceTree, path: String, uti: String?, gid: String, isInputFile: Bool = true)
    {
      self.sourceTree = sourceTree
      self.path = path
      self.uti = uti
      self.gid = gid
      self.isInputFile = isInputFile
    }

    init(sourceTree: SourceTree, path: String, gid: String, isInputFile: Bool = true) {
      let uti = FileExtensionToUTI[(path as NSString).pathExtension]
      self.init(
        sourceTree: sourceTree,
        path: path,
        uti: uti,
        gid: gid,
        isInputFile: isInputFile)
    }
  }

  // Captures the testable values in defining a PBXGroup.
  class GroupDefinition {
    let name: String
    let sourceTree: SourceTree
    let path: String?
    let gid: String
    let files: [FileDefinition]
    let groups: [GroupDefinition]
    let expectedPBXClass: String

    init(
      name: String,
      sourceTree: SourceTree,
      path: String?,
      gid: String,
      files: [FileDefinition],
      groups: [GroupDefinition],
      expectedPBXClass: String = "PBXGroup"
    ) {
      self.name = name
      self.sourceTree = sourceTree
      self.path = path
      self.gid = gid
      self.files = files
      self.groups = groups
      self.expectedPBXClass = expectedPBXClass
    }

    func groupByAddingGroup(_ group: GroupDefinition) -> GroupDefinition {
      var newGroups = groups
      newGroups.append(group)
      return GroupDefinition(
        name: name,
        sourceTree: sourceTree,
        path: path,
        gid: gid,
        files: files,
        groups: newGroups,
        expectedPBXClass: expectedPBXClass)
    }
  }

  class VersionGroupDefinition: GroupDefinition {
    let currentVersion: FileDefinition
    let versionGroupType: String

    init(
      name: String,
      sourceTree: SourceTree,
      path: String?,
      gid: String,
      files: [FileDefinition],
      groups: [GroupDefinition],
      currentVersion: FileDefinition,
      versionGroupType: String? = nil
    ) {
      self.currentVersion = currentVersion
      if let versionGroupType = versionGroupType {
        self.versionGroupType = versionGroupType
      } else {
        self.versionGroupType = FileExtensionToUTI[(name as NSString).pathExtension] ?? ""
      }
      super.init(
        name: name,
        sourceTree: sourceTree,
        path: path,
        gid: gid,
        files: files,
        groups: groups,
        expectedPBXClass: "XCVersionGroup")
    }
  }

  // Captures the testable values used when defining a simple PBXProject.
  struct SimpleProjectDefinition {
    struct NativeTargetDefinition {
      let name: String
      let settings: [String: String]
      let config: String
      let targetType: PBXTarget.ProductType
    }

    struct LegacyTargetDefinition {
      let name: String
      let buildToolPath: String
      let buildArguments: String
      let buildWorkingDirectory: String
    }

    let projectLevelBuildConfigName: String
    let projectLevelBuildConfigSettings: [String: String]
    let nativeTarget: NativeTargetDefinition
    let legacyTarget: LegacyTargetDefinition
    let mainGroupGID: String
    let mainGroupDefinition: GroupDefinition
  }

  private func generateSimpleProject() -> SimpleProjectDefinition {
    return populateProject(project, withGIDGenerator: gidGenerator)
  }

  @discardableResult
  private func populateProject(
    _ targetProject: PBXProject, withGIDGenerator generator: MockGIDGenerator
  ) -> SimpleProjectDefinition {
    let projectLevelBuildConfigName = "ProjectConfig"
    let projectLevelBuildConfigSettings = [
      "TEST_SETTING": "test_setting",
      "QuotedSetting": "Quoted string value"
    ]
    let nativeTarget = SimpleProjectDefinition.NativeTargetDefinition(
      name: "NativeApplicationTarget",
      settings: ["PRODUCT_NAME": "ProductName", "QuotedValue": "A quoted value"],
      config: "Config1",
      targetType: PBXTarget.ProductType.Application
    )
    let legacyTarget = SimpleProjectDefinition.LegacyTargetDefinition(
      name: "LegacyTarget",
      buildToolPath: "buildToolPath",
      buildArguments: "buildArguments",
      buildWorkingDirectory: "buildWorkingDirectory")

    // Note: This test relies on the fact that the current serializer implementation preserves the
    // GIDs of any objects it attempts to serialize.
    let mainGroupGID = generator.generateReservedID()
    let mainGroupDefinition: GroupDefinition
    do {
      let mainGroupFiles = [
        FileDefinition(
          sourceTree: .Group, path: "GroupFile.swift", gid: generator.generateReservedID()),
        FileDefinition(
          sourceTree: .Absolute, path: "/fake/path/AbsoluteFile.swift",
          gid: generator.generateReservedID()),
      ]
      let activeDatamodelVersion = FileDefinition(
        sourceTree: .Group,
        path: "v2.xcdatamodel",
        uti: DirExtensionToUTI["xcdatamodel"],
        gid: generator.generateReservedID(),
        isInputFile: true)
      let mainGroupGroups = [
        GroupDefinition(
          name: "Products",
          sourceTree: .Group,
          path: nil,
          gid: generator.generateReservedID(),
          files: [],
          groups: []
        ),
        GroupDefinition(
          name: "ChildGroup",
          sourceTree: .Group,
          path: "child_group_path",
          gid: generator.generateReservedID(),
          files: [
            FileDefinition(
              sourceTree: .Group, path: "ChildRelativeFile.swift",
              gid: generator.generateReservedID()),
            FileDefinition(sourceTree: .Group, path: "t.a", gid: generator.generateReservedID()),
            FileDefinition(
              sourceTree: .Group, path: "t.dylib", gid: generator.generateReservedID()),
            FileDefinition(
              sourceTree: .Group, path: "t.framework", gid: generator.generateReservedID()),
            FileDefinition(sourceTree: .Group, path: "t.jpg", gid: generator.generateReservedID()),
            FileDefinition(sourceTree: .Group, path: "t.m", gid: generator.generateReservedID()),
            FileDefinition(sourceTree: .Group, path: "t.mm", gid: generator.generateReservedID()),
            FileDefinition(sourceTree: .Group, path: "t.pch", gid: generator.generateReservedID()),
            FileDefinition(
              sourceTree: .Group, path: "t.plist", gid: generator.generateReservedID()),
            FileDefinition(sourceTree: .Group, path: "t.png", gid: generator.generateReservedID()),
            FileDefinition(sourceTree: .Group, path: "t.rtf", gid: generator.generateReservedID()),
            FileDefinition(
              sourceTree: .Group, path: "t.storyboard", gid: generator.generateReservedID()),
            FileDefinition(
              sourceTree: .Group, path: "t.xcassets", uti: DirExtensionToUTI["xcassets"],
              gid: generator.generateReservedID()),
            FileDefinition(
              sourceTree: .Group, path: "t.xcstickers", uti: DirExtensionToUTI["xcstickers"],
              gid: generator.generateReservedID()),
            FileDefinition(sourceTree: .Group, path: "t.xib", gid: generator.generateReservedID()),
            FileDefinition(
              sourceTree: .Group, path: "Test", uti: "text", gid: generator.generateReservedID()),
            FileDefinition(
              sourceTree: .Group, path: "Output.app", gid: generator.generateReservedID(),
              isInputFile: false),
          ],
          groups: []
        ),
        VersionGroupDefinition(
          name: "DataModel.xcdatamodeld",
          sourceTree: .Group,
          path: "DataModel.xcdatamodeld",
          gid: generator.generateReservedID(),
          files: [
            FileDefinition(
              sourceTree: .Group,
              path: "v1.xcdatamodel",
              uti: DirExtensionToUTI["xcdatamodel"],
              gid: generator.generateReservedID(),
              isInputFile: true),
            activeDatamodelVersion,
          ],
          groups: [],
          currentVersion: activeDatamodelVersion,
          versionGroupType: DirExtensionToUTI["xcdatamodeld"]
        ),
      ]
      mainGroupDefinition = GroupDefinition(
        name: "mainGroup",
        sourceTree: .SourceRoot,
        path: nil,
        gid: mainGroupGID,
        files: mainGroupFiles,
        groups: mainGroupGroups)
    }
    let definition = SimpleProjectDefinition(
      projectLevelBuildConfigName: projectLevelBuildConfigName,
      projectLevelBuildConfigSettings: projectLevelBuildConfigSettings,
      nativeTarget: nativeTarget,
      legacyTarget: legacyTarget,
      mainGroupGID: mainGroupGID,
      mainGroupDefinition: mainGroupDefinition
    )

    do {
      let config = targetProject.buildConfigurationList.getOrCreateBuildConfiguration(
        projectLevelBuildConfigName)
      config.buildSettings = projectLevelBuildConfigSettings
    }
    let nativePBXTarget = targetProject.createNativeTarget(
      nativeTarget.name,
      deploymentTarget: nil,
      targetType: nativeTarget.targetType)
    let config = nativePBXTarget.buildConfigurationList.getOrCreateBuildConfiguration(
      nativeTarget.config)
    config.buildSettings = nativeTarget.settings
    let legacyPBXTarget = targetProject.createLegacyTarget(
      legacyTarget.name,
      deploymentTarget: nil,
      buildToolPath: legacyTarget.buildToolPath,
      buildArguments: legacyTarget.buildArguments,
      buildWorkingDirectory: legacyTarget.buildWorkingDirectory)
    targetProject.linkTestTarget(legacyPBXTarget, toHostTarget: nativePBXTarget)

    do {
      func populateGroup(_ group: PBXGroup, groupDefinition: GroupDefinition) {
        group.globalID = groupDefinition.gid
        for file in groupDefinition.files {
          let fileRef = group.getOrCreateFileReferenceBySourceTree(file.sourceTree, path: file.path)
          fileRef.globalID = file.gid
          fileRef.isInputFile = file.isInputFile
        }
        for childDef in groupDefinition.groups {
          let childGroup: PBXGroup
          if let versionedChildDef = childDef as? VersionGroupDefinition {
            let versionGroup = group.getOrCreateChildVersionGroupByName(
              versionedChildDef.name,
              path: versionedChildDef.path)
            versionGroup.versionGroupType = versionedChildDef.versionGroupType
            let currentVersionDef = versionedChildDef.currentVersion
            let currentFileRef = versionGroup.getOrCreateFileReferenceBySourceTree(
              currentVersionDef.sourceTree,
              path: currentVersionDef.path)
            currentFileRef.globalID = currentVersionDef.gid
            currentFileRef.isInputFile = currentVersionDef.isInputFile
            versionGroup.currentVersion = currentFileRef
            childGroup = versionGroup
          } else {
            childGroup = group.getOrCreateChildGroupByName(childDef.name, path: childDef.path)
          }
          populateGroup(childGroup, groupDefinition: childDef)
        }
      }

      let mainGroup = targetProject.mainGroup
      populateGroup(mainGroup, groupDefinition: mainGroupDefinition)
    }

    return definition
  }

  private func assertDict(
    _ dict: StringToObjectDict, isPBXObjectClass pbxClass: String, line: UInt = #line
  ) {
    guard let isa = dict["isa"] as? String else {
      XCTFail("dictionary is not a PBXObject (missing 'isa' member)", line: line)
      return
    }
    XCTAssertEqual(
      isa, pbxClass, "Serialized dict is not of the expected PBXObject type", line: line)
  }

  private func getObjectByID(
    _ gid: String,
    withPBXClass pbxClass: String,
    fromObjects objects: StringToObjectDict,
    line: UInt = #line
  ) -> StringToObjectDict? {
    guard let dict = objects[gid] as? StringToObjectDict else {
      XCTFail("Missing \(pbxClass) with globalID '\(gid)'", line: line)
      return nil
    }
    assertDict(dict, isPBXObjectClass: pbxClass, line: line)
    return dict
  }

  /// Generates predictable GlobalID's for use in tests.
  // Note, this implementation is only suitable for projects with less than 4 billion objects.
  class MockGIDGenerator: GIDGeneratorProtocol {
    var nextID = 0

    func generate(_ item: PBXObjectProtocol) -> String {
      // This test implementation doesn't utilize the object in generating an ID.
      let gid = gidForCounter(nextID)
      nextID += 1
      return gid
    }

    // MARK: - Methods for testing.
    func generateReservedID() -> String {
      let reservedID = gidForCounter(nextID, prefix: 0xBAAD_F00D)
      nextID += 1
      return reservedID
    }

    private func gidForCounter(_ counter: Int, prefix: Int = 0) -> String {
      return String(format: "%08X%08X%08X", prefix, 0, counter & 0xFFFF_FFFF)
    }
  }
}
