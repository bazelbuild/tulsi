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

// Alias to make it clearer that PBXDict is just a simple String:NSObject mapping.
typealias StringToObjectDict = PBXDict

class PBXProjSerializerTests: XCTestCase {
  var gidGenerator: MockGIDGenerator! = nil
  var project: PBXProject! = nil
  var serializer: PBXProjSerializer! = nil

  override func setUp() {
    super.setUp()

    gidGenerator = MockGIDGenerator()
    project = PBXProject(name: "TestProject")
    serializer = PBXProjSerializer(rootObject: project, gidGenerator: gidGenerator)
  }

  // MARK: - Tests
  func testEmptyProject() {
    let dict = serializer.toDictionary()

    let classes = dict["classes"] as! StringToObjectDict
    XCTAssertEqual(classes.count, 0)

    XCTAssertEqual(dict["archiveVersion"], "1")
    XCTAssertEqual(dict["objectVersion"], XcodeVersionInfo.objectVersion)

    let objects = dict["objects"] as! StringToObjectDict
    let projectDict: StringToObjectDict! = getProjectFromRoot(dict, objects: objects)

    XCTAssertEqual(projectDict["compatibilityVersion"], XcodeVersionInfo.compatibilityVersion)

    let mainGroup = project.mainGroup
    XCTAssertNotNil(objects[mainGroup.globalID])
    XCTAssertEqual(projectDict["mainGroup"], mainGroup.globalID)

    let buildConfigList: StringToObjectDict! = getBuildConfigurationListFromProject(projectDict, objects: objects)
    let buildConfigs: [String]! = getBuildConfigurationsFromBuildConfigurationList(buildConfigList)
    XCTAssertEqual(buildConfigs.count, 0)

    // Validate that the dict can be serialized as an XML Plist.
    do {
      try NSPropertyListSerialization.dataWithPropertyList(dict, format: .XMLFormat_v1_0, options: 0)
    } catch let error as NSError {
      XCTFail(error.localizedDescription)
    }
  }

  func testMultipleToDictionaryCallsAreEquivalent() {
    let dict1 = serializer.toDictionary()
    let dict2 = serializer.toDictionary()
    XCTAssertEqual(dict1, dict2)
  }

  func testSimpleProject() {
    let projectDef = generateSimpleProject()

    // Serialize and test the contents.
    let root = serializer.toDictionary()
    let objects = root["objects"] as! StringToObjectDict

    let projectDict: StringToObjectDict! = getProjectFromRoot(root, objects: objects)
    do {
      let buildConfigList: StringToObjectDict! = getBuildConfigurationListFromProject(projectDict, objects: objects)
      let buildConfigs: [String]! = getBuildConfigurationsFromBuildConfigurationList(buildConfigList)
      XCTAssertEqual(buildConfigs.count, 1)

      let projectBuildConfigDict: StringToObjectDict! = getObjectByID(buildConfigs[0], withPBXClass: "XCBuildConfiguration", fromObjects: objects)
      XCTAssertEqual(projectBuildConfigDict["name"], projectDef.projectLevelBuildConfigName)
      XCTAssertEqual(projectBuildConfigDict["buildSettings"], projectDef.projectLevelBuildConfigSettings)
    }

    guard let targets = projectDict["targets"] as? [String] else {
      XCTFail("Project is missing expected 'targets' member")
      return
    }
    XCTAssertEqual(targets.count, 2, "Mismatch in number of project targets")

    for target in targets {
      let objectType = getObjectTypeForID(target, fromObjects: objects)!
      switch objectType {
      case "PBXNativeTarget":
        do {
          let target: StringToObjectDict! = getObjectByID(target, withPBXClass: "PBXNativeTarget", fromObjects: objects)
          assertNativeTargetDict(target, matchesDefinition: projectDef.nativeTarget, withObjects: objects)
        }

      case "PBXLegacyTarget":
        do {
          let target: StringToObjectDict! = getObjectByID(target, withPBXClass: "PBXLegacyTarget", fromObjects: objects)
          assertLegacyTargetDict(target, matchesDefinition: projectDef.legacyTarget, withObjects: objects)
        }

      default:
        XCTFail("Found unexpected target of type '\(objectType)'")
      }
    }

    XCTAssertEqual(projectDict["mainGroup"], projectDef.mainGroupGID)
    assertGroupSerialized(projectDef.mainGroupDefinition, withObjects: objects)

    do {
      try NSPropertyListSerialization.dataWithPropertyList(root, format: .XMLFormat_v1_0, options: 0)
    } catch let error as NSError {
      XCTFail(error.localizedDescription)
    }
  }

  func testOpenStepMatchesXML() {
    generateSimpleProject()

    // Force the XML serializer to restrict itself to strings for integers and booleans as OpenStep
    // format doesn't support those types.
    guard let xmlData = serializer.toXML(forceBasicTypes: true) else {
      XCTFail("Failed to generate XML format")
      return
    }
    guard let openStepData = serializer.toOpenStep() else {
      XCTFail("Failed to generate OpenStep format")
      return
    }

    let xmlDeserializedPlist: StringToObjectDict
    do {
      xmlDeserializedPlist = try NSPropertyListSerialization.propertyListWithData(xmlData,
          options: .Immutable, format: nil) as! StringToObjectDict
    } catch let error as NSError {
      XCTFail("Failed to parse XML serialized data " + error.localizedDescription)
      return
    }

    let openStepDeserializedPlist: StringToObjectDict
    do {
      openStepDeserializedPlist = try NSPropertyListSerialization.propertyListWithData(openStepData,
          options: .Immutable, format: nil) as! StringToObjectDict
    } catch let error as NSError {
      let serializedData = String(data: openStepData, encoding: NSUTF8StringEncoding)!
      XCTFail("Failed to parse OpenStep serialized data " + error.localizedDescription + "\n" + serializedData)
      return
    }
    XCTAssertEqual(openStepDeserializedPlist, xmlDeserializedPlist)
  }

  func testOpenStepSerializesEmptyDictionaries() {
    let config = project.buildConfigurationList.getOrCreateBuildConfiguration("Empty")
    config.buildSettings = Dictionary<String, String>()
    config.globalID = gidGenerator.generateReservedID()

    guard let openStepData = serializer.toOpenStep() else {
      XCTFail("Failed to generate OpenStep format")
      return
    }
    let root: StringToObjectDict
    do {
      root = try NSPropertyListSerialization.propertyListWithData(openStepData,
          options: .Immutable, format: nil) as! StringToObjectDict
    } catch let error as NSError {
      let serializedData = String(data: openStepData, encoding: NSUTF8StringEncoding)!
      XCTFail("Failed to parse OpenStep serialized data " + error.localizedDescription + "\n" + serializedData)
      return
    }

    let objects = root["objects"] as! StringToObjectDict
    let buildConfigDict: PBXDict! = getObjectByID(config.globalID, withPBXClass: "XCBuildConfiguration", fromObjects: objects)
    XCTAssertNotNil(buildConfigDict["buildSettings"])
  }

  func testOpenStepSerializationIsStable() {
    let project1 = PBXProject(name: "TestProject")
    let gidGenerator1 = MockGIDGenerator()
    populateProject(project1, withGIDGenerator: gidGenerator1)
    let serializer1 = PBXProjSerializer(rootObject: project1, gidGenerator: gidGenerator1)
    guard let openStepData1 = serializer1.toOpenStep() else {
      XCTFail("Failed to generate OpenStep format")
      return
    }

    let project2 = PBXProject(name: "TestProject")
    let gidGenerator2 = MockGIDGenerator()
    populateProject(project2, withGIDGenerator: gidGenerator2)
    let serializer2 = PBXProjSerializer(rootObject: project2, gidGenerator: gidGenerator2)
    guard let openStepData2 = serializer2.toOpenStep() else {
      XCTFail("Failed to generate OpenStep format")
      return
    }

    let serializedData1 = String(data: openStepData1, encoding: NSUTF8StringEncoding)!
    let serializedData2 = String(data: openStepData2, encoding: NSUTF8StringEncoding)!
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
  }

  // Captures the testable values in defining a PBXGroup.
  struct GroupDefinition {
    let name: String
    let sourceTree: SourceTree
    let path: String?
    let gid: String
    let files: [FileDefinition]
    let groups: [GroupDefinition]
  }

  // Captures the testable values used when defining a simple PBXProject.
  struct SimpleProjectDefinition {
    struct NativeTargetDefinition {
      let name: String
      let settings: Dictionary<String, String>
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
    let projectLevelBuildConfigSettings: Dictionary<String, String>
    let nativeTarget: NativeTargetDefinition
    let legacyTarget: LegacyTargetDefinition
    let mainGroupGID: String
    let mainGroupDefinition: GroupDefinition
  }

  private func generateSimpleProject() -> SimpleProjectDefinition {
    return populateProject(project, withGIDGenerator: gidGenerator)
  }

  private func populateProject(targetProject: PBXProject, withGIDGenerator generator: MockGIDGenerator) -> SimpleProjectDefinition {
    let projectLevelBuildConfigName = "ProjectConfig"
    let projectLevelBuildConfigSettings = ["TEST_SETTING": "test_setting",
                                           "QuotedSetting": "Quoted string value"]
    let nativeTarget = SimpleProjectDefinition.NativeTargetDefinition(name: "NativeApplicationTarget",
        settings: ["PRODUCT_NAME": "ProductName", "QuotedValue": "A quoted value"],
        config: "Config1",
        targetType: PBXTarget.ProductType.Application
    )
    let legacyTarget = SimpleProjectDefinition.LegacyTargetDefinition(name: "LegacyTarget",
        buildToolPath: "buildToolPath",
        buildArguments: "buildArguments",
        buildWorkingDirectory: "buildWorkingDirectory")

    // Note: This test relies on the fact that the current serializer implementation preserves the
    // GIDs of any objects it attempts to serialize.
    let mainGroupGID = generator.generateReservedID()
    let mainGroupDefinition: GroupDefinition
    do {
      let mainGroupFiles = [
          FileDefinition(sourceTree: .Group, path: "GroupFile.swift", uti: FileExtensionToUTI["swift"], gid: generator.generateReservedID(), isInputFile: true),
          FileDefinition(sourceTree: .Absolute, path: "/fake/path/AbsoluteFile.swift", uti: FileExtensionToUTI["swift"], gid: generator.generateReservedID(), isInputFile: true),
      ]
      let mainGroupGroups = [
          GroupDefinition(name: "ChildGroup",
              sourceTree: .Group,
              path: "child_group_path",
              gid: generator.generateReservedID(),
              files: [
                  FileDefinition(sourceTree: .Group, path: "ChildRelativeFile.swift", uti: FileExtensionToUTI["swift"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.a", uti: FileExtensionToUTI["a"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.dylib", uti: FileExtensionToUTI["dylib"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.framework", uti: FileExtensionToUTI["framework"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.jpg", uti: FileExtensionToUTI["jpg"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.m", uti: FileExtensionToUTI["m"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.mm", uti: FileExtensionToUTI["mm"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.pch", uti: FileExtensionToUTI["pch"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.plist", uti: FileExtensionToUTI["plist"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.png", uti: FileExtensionToUTI["png"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.rtf", uti: FileExtensionToUTI["rtf"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.storyboard", uti: FileExtensionToUTI["storyboard"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.xcassets", uti: DirExtensionToUTI["xcassets"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "t.xib", uti: FileExtensionToUTI["xib"], gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "Test", uti: nil, gid: generator.generateReservedID(), isInputFile: true),
                  FileDefinition(sourceTree: .Group, path: "Output.app", uti: "wrapper.application", gid: generator.generateReservedID(), isInputFile: false),
              ],
              groups: []
          ),
      ]
      mainGroupDefinition = GroupDefinition(name: "mainGroup",
          sourceTree: .SourceRoot,
          path: nil,
          gid: mainGroupGID,
          files: mainGroupFiles,
          groups: mainGroupGroups)
    }
    let definition = SimpleProjectDefinition(projectLevelBuildConfigName: projectLevelBuildConfigName,
        projectLevelBuildConfigSettings: projectLevelBuildConfigSettings,
        nativeTarget: nativeTarget,
        legacyTarget: legacyTarget,
        mainGroupGID: mainGroupGID,
        mainGroupDefinition: mainGroupDefinition
    )

    do {
      let config = targetProject.buildConfigurationList.getOrCreateBuildConfiguration(projectLevelBuildConfigName)
      config.buildSettings = projectLevelBuildConfigSettings
    }
    let nativePBXTarget = targetProject.createNativeTarget(nativeTarget.name, targetType: nativeTarget.targetType)
    let config = nativePBXTarget.buildConfigurationList.getOrCreateBuildConfiguration(nativeTarget.config)
    config.buildSettings = nativeTarget.settings
    let legacyPBXTarget = targetProject.createLegacyTarget(legacyTarget.name,
                                                           buildToolPath: legacyTarget.buildToolPath,
                                                           buildArguments: legacyTarget.buildArguments,
                                                           buildWorkingDirectory: legacyTarget.buildWorkingDirectory)
    targetProject.linkTestTarget(legacyPBXTarget, toHostTarget: nativePBXTarget)

    do {
      func populateGroup(group: PBXGroup, groupDefinition: GroupDefinition) {
        group.globalID = groupDefinition.gid
        for file in groupDefinition.files {
          let fileRef = group.getOrCreateFileReferenceBySourceTree(file.sourceTree, path: file.path)
          fileRef.globalID = file.gid
          fileRef.isInputFile = file.isInputFile
        }
        for childDef in groupDefinition.groups {
          let childGroup = group.getOrCreateChildGroupByName(childDef.name, path: childDef.path)
          populateGroup(childGroup, groupDefinition: childDef)
        }
      }

      let mainGroup = targetProject.mainGroup
      populateGroup(mainGroup, groupDefinition: mainGroupDefinition)
    }

    return definition
  }

  private func assertDict(dict: StringToObjectDict, isPBXObjectClass pbxClass: String, line: UInt = __LINE__) {
    guard let isa = dict["isa"] as? String else {
      XCTFail("dictionary is not a PBXObject (missing 'isa' member)", line: line)
      return
    }
    XCTAssertEqual(isa, pbxClass, "Serialized dict is not of the expected PBXObject type", line: line)
  }

  private func getProjectFromRoot(dict: StringToObjectDict, objects: StringToObjectDict, line: UInt = __LINE__) -> StringToObjectDict? {
    guard let rootObjectID = dict["rootObject"] as? String else {
      XCTFail("Root dictionary has no rootObject member", line: line)
      return nil
    }
    guard let projectDict = objects[rootObjectID] as? StringToObjectDict else {
      XCTFail("rootObjectID '\(rootObjectID)' does not reference valid PBXProject", line: line)
      return nil
    }
    assertDict(projectDict, isPBXObjectClass: "PBXProject", line: line)

    return projectDict
  }

  private func getBuildConfigurationListFromProject(projectDict: StringToObjectDict,
                                                    objects: StringToObjectDict,
                                                    line: UInt = __LINE__) -> StringToObjectDict? {
    guard let buildConfigListGID = projectDict["buildConfigurationList"] as? String else {
      XCTFail("Project has no buildConfigurationList", line: line)
      return nil
    }
    guard let buildConfigList = objects[buildConfigListGID] as? StringToObjectDict else {
      XCTFail("Project refers to non-existent buildConfigurationList '\(buildConfigListGID)'", line: line)
      return nil
    }
    assertDict(buildConfigList, isPBXObjectClass: "XCConfigurationList", line: line)

    return buildConfigList
  }

  private func getBuildConfigurationsFromBuildConfigurationList(dict: StringToObjectDict, line: UInt = __LINE__) -> [String]? {
    guard let buildConfigs = dict["buildConfigurations"] as? [String] else {
      XCTFail("buildConfigurationList invalid (no build configurations member)", line: line)
      return nil
    }
    return buildConfigs
  }

  private func getObjectTypeForID(gid: String, fromObjects objects: StringToObjectDict, line: UInt = __LINE__) -> String? {
    guard let dict = objects[gid] as? StringToObjectDict else {
      XCTFail("Missing object with globalID '\(gid)'", line: line)
      return nil
    }

    guard let isa = dict["isa"] as? String else {
      XCTFail("dictionary is not a PBXObject (missing 'isa' member)", line: line)
      return nil
    }
    return isa
  }

  private func getObjectByID(gid: String,
                             withPBXClass pbxClass: String,
                             fromObjects objects: StringToObjectDict,
                             line: UInt = __LINE__) -> StringToObjectDict? {
    guard let dict = objects[gid] as? StringToObjectDict else {
      XCTFail("Missing \(pbxClass) with globalID '\(gid)'", line: line)
      return nil
    }
    assertDict(dict, isPBXObjectClass: pbxClass, line: line)
    return dict
  }

  private func assertGroupSerialized(groupDef: GroupDefinition,
                                     withObjects objects: StringToObjectDict,
                                     line: UInt = __LINE__) {
    let group: StringToObjectDict! = getObjectByID(groupDef.gid,
                                                   withPBXClass: "PBXGroup",
                                                   fromObjects: objects,
                                                   line: line)
    XCTAssertEqual(group["name"], groupDef.name, line: line)
    XCTAssertEqual(group["sourceTree"], groupDef.sourceTree.rawValue, line: line)
    XCTAssertEqual(group["path"], groupDef.path, line: line)

    let numChildren = groupDef.files.count + groupDef.groups.count
    guard numChildren > 0 else {
      return
    }

    guard let children: [String] = group["children"] as? [String] else {
      XCTFail("Group '\(groupDef.name)' is missing 'children' member", line: line)
      return
    }
    let childGIDs = Set(children)

    for fileDef: FileDefinition in groupDef.files {
      XCTAssert(childGIDs.contains(fileDef.gid),
                "Missing expected child file with gid '\(fileDef.gid)'",
                line: line)
      assertFileReferenceSerialized(fileDef, withObjects: objects, line: line)
    }
    for childGroupDef: GroupDefinition in groupDef.groups {
      XCTAssert(childGIDs.contains(childGroupDef.gid),
                "Missing expected child group with gid '\(childGroupDef.gid)'",
                line: line)
      assertGroupSerialized(childGroupDef, withObjects: objects, line: line)
    }

    // Now that all of the expected children have been found, ensure that there are no unexpected
    // ones.
    XCTAssertEqual(children.count, numChildren, line: line)
  }

  private func assertFileReferenceSerialized(fileDef: FileDefinition,
                                             withObjects objects: StringToObjectDict,
                                             line: UInt = __LINE__) {
    let fileRef: StringToObjectDict! = getObjectByID(fileDef.gid,
                                                     withPBXClass: "PBXFileReference",
                                                     fromObjects: objects,
                                                     line: line)
    XCTAssertEqual(fileRef["path"], fileDef.path, line: line)
    XCTAssertEqual(fileRef["sourceTree"], fileDef.sourceTree.rawValue, line: line)

    if fileDef.isInputFile {
      XCTAssertEqual(fileRef["lastKnownFileType"],
                     fileDef.uti,
                     "Unexpected lastKnownFileType for path '\(fileDef.path)'",
                     line: line)
      XCTAssertNil(fileRef["explicitFileType"], line: line)
    } else {
      XCTAssertEqual(fileRef["explicitFileType"],
                     fileDef.uti,
                     "Unexpected explicitFileType for path '\(fileDef.path)'",
                     line: line)
      XCTAssertNil(fileRef["lastKnownFileType"], line: line)
    }
  }

  func assertNativeTargetDict(target: StringToObjectDict,
                              matchesDefinition def: SimpleProjectDefinition.NativeTargetDefinition,
                              withObjects objects: StringToObjectDict,
                              line: UInt = __LINE__) {
    XCTAssertEqual(target["name"], def.name, line: line)
    XCTAssertEqual(target["productName"], def.name, line: line)
    XCTAssertEqual(target["productType"], def.targetType.rawValue, line: line)

    let buildConfigurationListGID = target["buildConfigurationList"] as! String
    let buildConfigList: StringToObjectDict! = getObjectByID(buildConfigurationListGID,
                                                             withPBXClass: "XCConfigurationList",
                                                             fromObjects: objects,
                                                             line: line)
    let buildConfigs: [String]! = getBuildConfigurationsFromBuildConfigurationList(buildConfigList,
                                                                                   line: line)
    XCTAssertEqual(buildConfigs.count, 1, line: line)

    let buildConfigDict: StringToObjectDict! = getObjectByID(buildConfigs[0],
                                                             withPBXClass: "XCBuildConfiguration",
                                                             fromObjects: objects,
                                                             line: line)
    XCTAssertEqual(buildConfigDict["name"], def.config, line: line)
    XCTAssertEqual(buildConfigDict["buildSettings"], def.settings, line: line)

    // TODO(abaire): Validate that the target output information is correct.
    let productReferenceGID = target["productReference"] as! String
    getObjectByID(productReferenceGID,
                  withPBXClass: "PBXFileReference",
                  fromObjects: objects,
                  line: line)
  }

  func assertLegacyTargetDict(target: StringToObjectDict,
                              matchesDefinition def: SimpleProjectDefinition.LegacyTargetDefinition,
                              withObjects objects: StringToObjectDict,
                              line: UInt = __LINE__) {

    XCTAssertEqual(target["name"], def.name, line: line)
    XCTAssertEqual(target["productName"], def.name, line: line)
    XCTAssertEqual(target["buildToolPath"], def.buildToolPath, line: line)
    XCTAssertEqual(target["buildArgumentsString"], def.buildArguments, line: line)
    XCTAssertEqual(target["buildWorkingDirectory"], def.buildWorkingDirectory, line: line)

    let buildConfigurationListGID = target["buildConfigurationList"] as! String
    let buildConfigList: StringToObjectDict! = getObjectByID(buildConfigurationListGID,
                                                             withPBXClass: "XCConfigurationList",
                                                             fromObjects: objects,
                                                             line: line)
    let buildConfigs: [String]! = getBuildConfigurationsFromBuildConfigurationList(buildConfigList,
                                                                                   line: line)
    XCTAssert(buildConfigs.isEmpty, line: line)
  }

  /// Generates predictable GlobalID's for use in tests.
  // Note, this implementation is only suitable for projects with less than 4 billion objects.
  class MockGIDGenerator: GIDGeneratorProtocol {
    var nextID = 0

    func generate(item: PBXObjectProtocol) -> String {
      // This test implementation doesn't utilize the object in generating an ID.
      let gid = gidForCounter(nextID)
      nextID += 1
      return gid
    }

    // MARK: - Methods for testing.
    func generateReservedID() -> String {
      let reservedID = gidForCounter(nextID, prefix: 0xBAADF00D)
      nextID += 1
      return reservedID
    }

    private func gidForCounter(counter : Int, prefix: Int = 0) -> String {
      return String(format: "%08X%08X%08X", prefix, 0, counter & 0xFFFFFFFF)
    }
  }
}
