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

import Foundation

/// Information about the Xcode file format that should be used to serialize PBXObjects.
// These values can be obtained by inspecting a generated .xcodeproj file (but generally newer
// Xcode versions can parse properly formatted old file versions).
let XcodeVersionInfo = (objectVersion: "46", compatibilityVersion: "Xcode 3.2")


/// Valid values for the sourceTree field on PBXReference-derived classes. These values correspond to
/// the "Location" selector in Xcode's File Inspector and indicate how the path field in the
/// PBXReference should be handled.
enum SourceTree: String {
  /// "Relative to Group" indicates that the path is relative to the group enclosing this reference.
  case Group = "<group>"

  /// "Absolute Path" indicates that the path is absolute.
  case Absolute = "<absolute>"

  /// "Relative to Build Products" indicates that the path is relative to the BUILT_PRODUCTS_DIR
  /// environment variable.
  case BuiltProductsDir = "BUILT_PRODUCTS_DIR"

  /// "Relative to SDK" indicates that the path is relative to the SDKROOT environment variable.
  case SDKRoot = "SDKROOT"

  /// "Relative to Project" indicates that the path is relative to the SOURCE_ROOT environment
  /// variable (likely the parent of the .pbxcodeproj bundle).
  case SourceRoot = "SOURCE_ROOT"

  /// "Relative to Developer Directory" indicates that the path is relative to the DEVELOPER_DIR
  /// environment variable (likely the Developer directory within the running Xcode.app bundle).
  case DeveloperDir = "DEVELOPER_DIR"
}

// Models a path within an Xcode project file.
struct SourceTreePath: Hashable {
  /// Indicates the type of "path".
  var sourceTree: SourceTree
  var path: String
  var hashValue: Int {
    return sourceTree.hashValue &+ path.hashValue
  }
}

func == (lhs: SourceTreePath, rhs: SourceTreePath) -> Bool {
  return (lhs.sourceTree == rhs.sourceTree) && (lhs.path == rhs.path)
}


/// Protocol for all serializable project objects.
protocol PBXObjectProtocol: PBXProjSerializable, CustomDebugStringConvertible {
  /// Provides a string identifying this object's type.
  var isa: String { get }
  /// Used in the generation of globally unique IDs.
  var hashValue: Int { get }
  var globalID: String { get set }

  var comment: String? { get }
}

extension PBXObjectProtocol {
  var debugDescription: String {
    return "\(type(of: self)) \(String(describing: self.comment))"
  }
}


/// Models a collection of build settings.
final class XCBuildConfiguration: PBXObjectProtocol {
  var globalID: String = ""
  let name: String
  var buildSettings = [String:String]()
  var baseConfigurationReference: PBXFileReference?

  var isa: String {
    return "XCBuildConfiguration"
  }

  lazy var hashValue: Int = { [unowned self] in
    return self.name.hashValue
  }()

  var comment: String? {
    return name
  }

  init(name: String) {
    self.name = name
  }

  func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try serializer.addField("name", name)
    try serializer.addField("buildSettings", buildSettings)
    try serializer.addField("baseConfigurationReference", baseConfigurationReference)
  }
}


/// Internal base class for file references and groups.
class PBXReference: PBXObjectProtocol {
  var globalID: String = ""
  let name: String
  // be careful setting these; they're cached in PBXGroup
  fileprivate(set) var path: String?
  fileprivate(set) var sourceTree: SourceTree

  var isa: String {
    assertionFailure("PBXReference must be subclassed")
    return ""
  }

  lazy var hashValue: Int = { [unowned self] in
    return self.name.hashValue &+ (self.path?.hashValue ?? 0)
  }()

  var comment: String? {
    return name
  }

  lazy var fileExtension: String? = { [unowned self] in
    guard let p = self.path else { return nil }
    return p.pbPathExtension
  }()

  lazy var uti: String? = { [unowned self] in
    guard let p = self.path else { return nil }
    return p.pbPathUTI
  }()

  weak var parent: PBXReference? {
    return _parent
  }
  fileprivate weak var _parent: PBXReference?

  init(name: String, path: String?, sourceTree: SourceTree, parent: PBXReference? = nil) {
    self.name = name
    self.path = path
    self.sourceTree = sourceTree
    self._parent = parent
  }

  convenience init(name: String, sourceTreePath: SourceTreePath, parent: PBXReference? = nil) {
    self.init(name: name,
              path: sourceTreePath.path,
              sourceTree: sourceTreePath.sourceTree,
              parent: parent)
  }

  func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try serializer.addField("name", name)
    try serializer.addField("path", path)
    try serializer.addField("sourceTree", sourceTree.rawValue)
  }
}


/// PBXFileReference instances are used to track each file in the project.
final class PBXFileReference: PBXReference, Hashable {
  // A PBXFileReference for an input will have lastKnownFileType set to the file's UTI. An output
  // will have explicitFileType set. The types used correspond to the "Type" field shown in Xcode's
  // File Inspector.
  var explicitFileType: String? {
    if !isInputFile {
      return fileType
    }
    return nil
  }
  var lastKnownFileType: String? {
    if isInputFile {
      return fileType ?? "text"
    }
    return nil
  }

  /// Override for this file reference's UTI.
  var fileTypeOverride: String?

  /// Whether or not this file reference is for a project input file.
  var isInputFile: Bool = false

  override var isa: String {
    return "PBXFileReference"
  }

  var fileType: String? {
    if fileTypeOverride != nil {
      return fileTypeOverride
    }
    return self._pbPathUTI
  }
  // memoized copy of the (expensive) pbPathUTI for this PBXFileReference's name.
  private lazy var _pbPathUTI: String? = { [unowned self] in
    return self.name.pbPathUTI
  }()

  /// Returns the path to this file reference relative to the source root group.
  /// Access time is linear, depending on the number of parent groups.
  var sourceRootRelativePath: String {
    var parentHierarchy = [path!]
    var group = parent
    while (group != nil && group!.path != nil) {
      parentHierarchy.append(group!.path!)
      group = group!.parent
    }

    let fullPath = parentHierarchy.reversed().joined(separator: "/")
    return fullPath
  }


  init(name: String, path: String?, sourceTree: SourceTree, parent: PBXGroup?) {
    super.init(name: name, path: path, sourceTree: sourceTree, parent: parent)
  }

  convenience init(name: String, sourceTreePath: SourceTreePath, parent: PBXGroup?) {
    self.init(name: name, path: sourceTreePath.path, sourceTree: sourceTreePath.sourceTree, parent: parent)
  }

  override func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try super.serializeInto(serializer)
    if let uti = lastKnownFileType {
      try serializer.addField("lastKnownFileType", uti)
    } else if let uti = explicitFileType {
      try serializer.addField("explicitFileType", uti)
    }

    // Give Starlark files Python syntax highlighting by default.
    // It's quite a good match--and certainly a better default than no highlighting.
    // Xcode's plugin functionality is currently so limited that we can't do better.
    if name == "BUILD" || name == "WORKSPACE" || name.hasSuffix(".bzl") || name.hasSuffix(".sky") || name.hasSuffix(".star") || name.hasSuffix(".bazel") || name.hasSuffix(".BUILD") || name.hasSuffix(".WORKSPACE") {
      try serializer.addField("xcLanguageSpecificationIdentifier", "xcode.lang.python")
    } else if name.hasSuffix(".bazelrc") {
      // Similarly, but shell for .bazelrc 
      try serializer.addField("xcLanguageSpecificationIdentifier", "xcode.lang.sh")
    } else if name.hasSuffix(".tulsigen") || name.hasSuffix(".tulsiconf") || name.hasSuffix(".tulsiconf-user") {
      // Similarly, but JSON for Tulsi configuation files.
      try serializer.addField("xcLanguageSpecificationIdentifier", "xcode.lang.json")
    }
  }
}

func == (lhs: PBXFileReference, rhs: PBXFileReference) -> Bool {
  return lhs.isInputFile == rhs.isInputFile &&
      lhs.fileType == rhs.fileType &&
      lhs.sourceTree == rhs.sourceTree &&
      lhs.name == rhs.name &&
      lhs.path == rhs.path
}


/// PBXGroups are simple containers for other PBXReference instances.
class PBXGroup: PBXReference, Hashable {
  /// Array of reference objects contained by this group.
  var children = [PBXReference]()

  // Indexes for typed access of children.
  var childGroupsByName = [String: PBXGroup]()
  var childVariantGroupsByName = [String: PBXVariantGroup]()
  var childVersionGroupsByName = [String: XCVersionGroup]()
  var fileReferencesBySourceTreePath = [SourceTreePath: PBXFileReference]()

  override var isa: String {
    return "PBXGroup"
  }

  // TODO(dmaclach): Passing back file references is pretty useless for groups.
  // Probably want to change to paths or maybe just walk the fileReferencesBySourceTreePath.
  var allSources: [PBXFileReference] {
    var refs: [PBXFileReference] = []
    for reference in children {
      if let fileReference = reference as? PBXFileReference {
        refs.append(fileReference)
      } else if let groupReference = reference as? PBXGroup {
        refs.append(contentsOf: groupReference.allSources)
      }
    }
    return refs
  }

  init(name: String, path: String?, sourceTree: SourceTree, parent: PBXGroup?) {
    super.init(name: name, path: path, sourceTree: sourceTree, parent: parent)
  }

  convenience init(name: String, sourceTreePath: SourceTreePath, parent: PBXGroup?) {
    self.init(name: name, path: sourceTreePath.path, sourceTree: sourceTreePath.sourceTree, parent: parent)
  }

  func getOrCreateChildGroupByName(_ name: String,
                                   path: String?,
                                   sourceTree: SourceTree = .Group) -> PBXGroup {
    if let value = childGroupsByName[name] {
      return value
    }
    let value = PBXGroup(name: name, path: path, sourceTree: sourceTree, parent: self)
    childGroupsByName[name] = value
    children.append(value)
    return value
  }

  func getOrCreateChildVariantGroupByName(_ name: String,
                                          sourceTree: SourceTree = .Group) -> PBXVariantGroup {
    if let value = childVariantGroupsByName[name] {
      return value
    }
    let value = PBXVariantGroup(name: name, path: nil, sourceTree: sourceTree, parent: self)
    childVariantGroupsByName[name] = value
    children.append(value)
    return value
  }

  func getOrCreateChildVersionGroupByName(_ name: String,
                                          path: String?,
                                          sourceTree: SourceTree = .Group) -> XCVersionGroup {
    if let value = childVersionGroupsByName[name] {
      return value
    }
    let value = XCVersionGroup(name: name, path: path, sourceTree: sourceTree, parent: self)
    childVersionGroupsByName[name] = value
    children.append(value)
    return value
  }

  func getOrCreateFileReferenceBySourceTree(
    _ sourceTree: SourceTree,
    path: String,
    name: String? = nil
  ) -> PBXFileReference {
    let sourceTreePath = SourceTreePath(sourceTree: sourceTree, path: path)
    return getOrCreateFileReferenceBySourceTreePath(sourceTreePath, name: name)
  }

  func getOrCreateFileReferenceBySourceTreePath(
    _ sourceTreePath: SourceTreePath,
    name: String? = nil
  ) -> PBXFileReference {
    if let value = fileReferencesBySourceTreePath[sourceTreePath] {
      return value
    }
    let name = name ?? sourceTreePath.path.pbPathLastComponent
    let value = PBXFileReference(name: name,
                                 sourceTreePath: sourceTreePath,
                                 parent:self)
    fileReferencesBySourceTreePath[sourceTreePath] = value
    children.append(value)
    return value
  }

  func removeChild(_ child: PBXReference) {
    children = children.filter() { $0 !== child }
    if child is XCVersionGroup {
      childVersionGroupsByName.removeValue(forKey: child.name)
    } else if child is PBXVariantGroup {
      childVariantGroupsByName.removeValue(forKey: child.name)
    } else if child is PBXGroup {
      childGroupsByName.removeValue(forKey: child.name)
    } else if child is PBXFileReference {
      let sourceTreePath = SourceTreePath(sourceTree: child.sourceTree, path: child.path!)
      fileReferencesBySourceTreePath.removeValue(forKey: sourceTreePath)
    }
  }

  // Recursively updates the child's path for a migration to self.
  func updatePathForChild(_ child: PBXReference, currentPath: String?) {
    // Assume the name of the PBXReference is a component of the path.
    let childPath: String
    if let currentPath = currentPath {
      childPath = currentPath + "/" + child.name
    } else {
      childPath = child.name
    }

    if let child = child as? PBXGroup {
      for grandchild in child.children {
        child.updatePathForChild(grandchild, currentPath: childPath)
      }
    } else if let child = child as? PBXFileReference {
      updatePathForChildFile(child, toPath: childPath)
    }
  }

  func updatePathForChildFile(
    _ child: PBXFileReference,
    toPath: String,
    sourceTree: SourceTree? = nil) { // Source tree defaults to staying the same
    // Updates internal index to match
    fileReferencesBySourceTreePath.removeValue(
      forKey: SourceTreePath(sourceTree: child.sourceTree, path: child.path!))
    let newSourceTreePath =
      SourceTreePath(sourceTree: sourceTree ?? child.sourceTree, path: toPath)
    child.path = newSourceTreePath.path
    child.sourceTree = newSourceTreePath.sourceTree
    fileReferencesBySourceTreePath[newSourceTreePath] = child
  }

  /// Takes ownership of the children of the given group. Note that this leaves the "other" group in
  /// an invalid state and it should be discarded (for example, via removeChild).
  func migrateChildrenOfGroup(_ other: PBXGroup) {
    for child in other.children {
      child._parent = self
      children.append(child)

      // Update path for the child and its entire tree.
      updatePathForChild(child, currentPath: nil)

      if let child = child as? XCVersionGroup {
        childVersionGroupsByName[child.name] = child
      } else if let child = child as? PBXVariantGroup {
        childVariantGroupsByName[child.name] = child
      } else if let child = child as? PBXGroup {
        childGroupsByName[child.name] = child
      } else if let child = child as? PBXFileReference {
        let sourceTreePath = SourceTreePath(sourceTree: child.sourceTree, path: child.path!)
        fileReferencesBySourceTreePath[sourceTreePath] = child
      }
    }
  }

  /// Returns the (first) child file reference with the given name, if any.
  func childFileReference(withName name: String) -> PBXFileReference? {
    return fileReferencesBySourceTreePath.values.first { $0.name == name }
  }

  override func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try super.serializeInto(serializer)
    try serializer.addField("children", children.sorted(by: {$0.name < $1.name}))
  }
}

func == (lhs: PBXGroup, rhs: PBXGroup) -> Bool {
  // NOTE(abaire): This isn't technically correct as it's possible to create two groups with
  // identical paths but different contents. For this to be reusable, everything should really be
  // made Hashable and the children should be compared as well.
  return lhs.name == rhs.name &&
      lhs.isa == rhs.isa &&
      lhs.path == rhs.path
}


/// Models a localized resource group.
class PBXVariantGroup: PBXGroup {
  override var isa: String {
    return "PBXVariantGroup"
  }
}


/// Models a versioned group (e.g., a Core Data xcdatamodeld).
final class XCVersionGroup: PBXGroup {
  /// The active child reference.
  var currentVersion: PBXReference? = nil
  var versionGroupType: String = ""

  override var isa: String {
    return "XCVersionGroup"
  }

  init(name: String,
       path: String?,
       sourceTree: SourceTree,
       parent: PBXGroup?,
       versionGroupType: String = "") {
    super.init(name: name, path: path, sourceTree: sourceTree, parent: parent)
  }

  convenience init(name: String,
                   sourceTreePath: SourceTreePath,
                   parent: PBXGroup?,
                   versionGroupType: String = "") {
    self.init(name: name,
              path: sourceTreePath.path,
              sourceTree: sourceTreePath.sourceTree,
              parent: parent,
              versionGroupType: versionGroupType)
  }

  func setCurrentVersionByName(_ name: String) -> Bool {
    // We have to go by name instead of path as PBXFileReferences' paths are relative to the
    // mainGroup while the name is just the name of the file.
    guard let value = childFileReference(withName: name) else {
      return false
    }

    currentVersion = value
    return true
  }

  override func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try super.serializeInto(serializer)

    if let currentVersion = currentVersion {
      try serializer.addField("currentVersion", currentVersion)
    }
    try serializer.addField("versionGroupType", versionGroupType)
  }
}


/// Models the set of XCBuildConfiguration instances for a given target or project.
final class XCConfigurationList: PBXObjectProtocol {
  var globalID: String = ""
  var buildConfigurations = [String: XCBuildConfiguration]()
  var defaultConfigurationIsVisible = false
  var defaultConfigurationName: String? = nil

  var isa: String {
    return "XCConfigurationList"
  }

  lazy var hashValue: Int = { [unowned self] in
    return self.comment?.hashValue ?? 0
  }()

  let comment: String?

  init(forType: String? = nil, named: String? = nil) {
    if let ownerType = forType, let name = named {
      self.comment = "Build configuration list for \(ownerType) \"\(name)\""
    } else {
      self.comment = nil
    }
  }

  func getOrCreateBuildConfiguration(_ name: String) -> XCBuildConfiguration {
    if let value = buildConfigurations[name] {
      return value
    }
    let value = XCBuildConfiguration(name: name)
    buildConfigurations[name] = value
    return value
  }

  func getBuildConfiguration(_ name: String) -> XCBuildConfiguration? {
    return buildConfigurations[name]
  }

  func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try serializer.addField("buildConfigurations", buildConfigurations.values.sorted(by: {$0.name < $1.name}))
    try serializer.addField("defaultConfigurationIsVisible", defaultConfigurationIsVisible)
    if let defaultConfigurationName = defaultConfigurationName {
      try serializer.addField("defaultConfigurationName", defaultConfigurationName)
    }
  }
}


/// Internal base class for concrete build phases (each of which capture a set of files that will be
/// used as inputs to that phase).
class PBXBuildPhase: PBXObjectProtocol  {
  // Used to identify different phases of the same type (i.e. isa).
  var mnemonic: String = ""
  var globalID: String = ""
  var files = [PBXBuildFile]()
  let buildActionMask: Int
  let runOnlyForDeploymentPostprocessing: Bool

  init(buildActionMask: Int = 0, runOnlyForDeploymentPostprocessing: Bool = false) {
    self.buildActionMask = buildActionMask
    self.runOnlyForDeploymentPostprocessing = runOnlyForDeploymentPostprocessing
  }

  var isa: String {
    assertionFailure("PBXBuildPhase must be subclassed")
    return ""
  }

  var hashValue: Int {
    assertionFailure("PBXBuildPhase must be subclassed")
    return 0
  }

  var comment: String? {
    assertionFailure("PBXBuildPhase must be subclassed")
    return nil
  }

  func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try serializer.addField("buildActionMask", buildActionMask)
    try serializer.addField("files", files)
    try serializer.addField("runOnlyForDeploymentPostprocessing", runOnlyForDeploymentPostprocessing)
  }
}


/// Encapsulates a source file compilation phase.
final class PBXSourcesBuildPhase: PBXBuildPhase  {
  override var isa: String {
    return "PBXSourcesBuildPhase"
  }

  override var hashValue: Int {
    return 0
  }

  override var comment: String? {
    return "Sources"
  }

  override init(buildActionMask: Int = 0, runOnlyForDeploymentPostprocessing: Bool = false) {
    super.init(buildActionMask: buildActionMask,
               runOnlyForDeploymentPostprocessing: runOnlyForDeploymentPostprocessing)
    self.mnemonic = "CompileSources"
  }
}


/// Encapsulates a shell script execution phase.
final class PBXShellScriptBuildPhase: PBXBuildPhase {
  let inputPaths: [String]
  let outputPaths: [String]
  let shellPath: String
  let shellScript: String
  let name: String?
  var showEnvVarsInLog = false

  override var isa: String {
    return "PBXShellScriptBuildPhase"
  }

  override var hashValue: Int { return _hashValue }
  private let _hashValue: Int

  override var comment: String? {
    return name ?? "ShellScript"
  }

  init(shellScript: String,
       shellPath: String = "/bin/sh",
       name: String?,
       inputPaths: [String] = [String](),
       outputPaths: [String] = [String](),
       buildActionMask: Int = 0,
       runOnlyForDeploymentPostprocessing: Bool = false) {
    self.shellScript = shellScript
    self.shellPath = shellPath
    self.name = name
    self.inputPaths = inputPaths
    self.outputPaths = outputPaths
    self._hashValue = shellPath.hashValue &+ shellScript.hashValue

    super.init(buildActionMask: buildActionMask,
               runOnlyForDeploymentPostprocessing: runOnlyForDeploymentPostprocessing)
  }

  override func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try super.serializeInto(serializer)
    try serializer.addField("inputPaths", inputPaths)
    try serializer.addField("outputPaths", outputPaths)
    try serializer.addField("name", name)
    try serializer.addField("shellPath", shellPath)
    try serializer.addField("shellScript", shellScript)
    try serializer.addField("showEnvVarsInLog", showEnvVarsInLog)
  }
}


/// File reference with associated build flags (set in Xcode via the Compile Sources phase). This
/// extra level of indirection allows any given PBXReference to be included in multiple targets
/// with different COMPILER_FLAGS settings for each. (e.g., a file could have a preprocessor define
/// set while compiling a test target that is not set when building the main target).
final class PBXBuildFile: PBXObjectProtocol {
  var globalID: String = ""
  let fileRef: PBXReference
  let settings: [String: String]?

  init(fileRef: PBXReference, settings: [String: String]? = nil) {
    self.fileRef = fileRef
    self.settings = settings
  }

  lazy var hashValue: Int = { [unowned self] in
    var val = self.fileRef.hashValue
    if let settings = self.settings {
      for (key, value) in settings {
        val = val &+ key.hashValue &+ value.hashValue
      }
    }
    return val
  }()

  var isa: String {
    return "PBXBuildFile"
  }

  var comment: String? {
    if let parent = fileRef.parent {
      return "\(fileRef.comment!) in \(parent.comment!)"
    }
    return fileRef.comment
  }

  func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try serializer.addField("fileRef", fileRef)
    if let concreteSettings = settings {
      try serializer.addField("settings", concreteSettings)
    }
  }
}


/// Base class for concrete build targets.
class PBXTarget: PBXObjectProtocol, Hashable {
  enum ProductType: String {
    case StaticLibrary = "com.apple.product-type.library.static"
    case DynamicLibrary = "com.apple.product-type.library.dynamic"
    case Tool = "com.apple.product-type.tool"
    case Bundle = "com.apple.product-type.bundle"
    case Framework = "com.apple.product-type.framework"
    case StaticFramework = "com.apple.product-type.framework.static"
    case Application = "com.apple.product-type.application"
    case AppClip = "com.apple.product-type.application.on-demand-install-capable"
    case MessagesApplication = "com.apple.product-type.application.messages"
    case MessagesExtension = "com.apple.product-type.app-extension.messages"
    case MessagesStickerPackExtension = "com.apple.product-type.app-extension.messages-sticker-pack"
    case UnitTest = "com.apple.product-type.bundle.unit-test"
    case UIUnitTest = "com.apple.product-type.bundle.ui-testing"
    case InAppPurchaseContent = "com.apple.product-type.in-app-purchase-content"
    case AppExtension = "com.apple.product-type.app-extension"
    case XPCService = "com.apple.product-type.xpc-service"
    case Watch1App = "com.apple.product-type.application.watchapp"
    case Watch2App = "com.apple.product-type.application.watchapp2"
    case Watch1Extension = "com.apple.product-type.watchkit-extension"
    case Watch2Extension = "com.apple.product-type.watchkit2-extension"
    case TVAppExtension = "com.apple.product-type.tv-app-extension"

    /// Whether or not this ProductType denotes a watch application.
    var isWatchApp: Bool {
      return self == .Watch1App || self == .Watch2App
    }

    /// Whether or not this ProductType is an iOS app extension or variant.
    var isiOSAppExtension: Bool {
      return self == .AppExtension || self == .MessagesExtension
          || self == .MessagesStickerPackExtension
    }

    /// Whether or not this ProductType denotes a test bundle.
    var isTest: Bool {
      return self == .UnitTest || self == .UIUnitTest
    }

    /// Whether or not this ProductTypes denotes a library target.
    var isLibrary: Bool {
      return self == .StaticLibrary || self == .DynamicLibrary
    }

    /// Returns the extension type associated with this watch app type (or nil if this ProductType
    /// is not a WatchApp type).
    var watchAppExtensionType: ProductType? {
      switch self {
        case .Watch1App:
          return .Watch1Extension
        case .Watch2App:
          return .Watch2Extension
        default:
          return nil
      }
    }

    var explicitFileType: String {
      switch self {
        case .StaticLibrary:
          return "archive.ar"

        case .DynamicLibrary:
          return "compiled.mach-o.dylib"

        case .Tool:
          return "compiled.mach-o.executable"

        case .Bundle:
          return "wrapper.bundle"

        case .Framework:
          return "wrapper.framework"

        case .StaticFramework:
          return "wrapper.framework.static"

        case .Watch1App:
          fallthrough
        case .Watch2App:
          fallthrough
        case .MessagesApplication:
          fallthrough
        case .AppClip:
          fallthrough
        case .Application:
          return "wrapper.application"

        case .UnitTest:
          fallthrough
        case .UIUnitTest:
          return "wrapper.cfbundle"

        case .InAppPurchaseContent:
          return "folder"

        case .Watch1Extension:
          fallthrough
        case .Watch2Extension:
          fallthrough
        case .TVAppExtension:
          fallthrough
        case .MessagesExtension:
          fallthrough
        case .MessagesStickerPackExtension:
          fallthrough
        case .AppExtension:
          return "wrapper.app-extension"

        case .XPCService:
          return "wrapper.xpc-service"
      }
    }

    func productName(_ name: String) -> String {
      switch self {
        case .StaticLibrary:
          return "lib\(name).a"

        case .DynamicLibrary:
          return "lib\(name).dylib"

        case .Tool:
          return name

        case .Bundle:
          return "\(name).bundle"

        case .Framework:
          return "\(name).framework"

        case .StaticFramework:
          return "\(name).framework"

        case .Watch2App:
          fallthrough
        case .MessagesApplication:
          fallthrough
        case .AppClip:
          fallthrough
        case .Application:
          return "\(name).app"

        case .UnitTest:
          fallthrough
        case .UIUnitTest:
          return "\(name).xctest"

        case .InAppPurchaseContent:
          return name

        case .Watch1App:
          // watchOS1 apps are packaged as extensions.
          fallthrough
        case .Watch1Extension:
          fallthrough
        case .Watch2Extension:
          fallthrough
        case .TVAppExtension:
          fallthrough
        case .MessagesExtension:
          fallthrough
        case .MessagesStickerPackExtension:
          fallthrough
        case .AppExtension:
          return "\(name).appex"

        case .XPCService:
          return "\(name).xpc"
      }
    }
  }

  var globalID: String = ""
  let name: String
  var productName: String? { return name }
  // The primary artifact generated by building this target. Generally this will be productName with
  // a file/bundle extension.
  var buildableName: String { return name }
  lazy var buildConfigurationList: XCConfigurationList = { [unowned self] in
    XCConfigurationList(forType: self.isa, named: self.name)
  }()
  /// The targets on which this target depends.
  var dependencies = [PBXTargetDependency]()
  /// Any targets which must be built by XCSchemes generated for this target.
  var buildActionDependencies = Set<PBXTarget>()
  /// The build phases to be executed to generate this target.
  var buildPhases = [PBXBuildPhase]()
  /// Deployment target for this target, if available.
  let deploymentTarget: DeploymentTarget?

  var isa: String {
    assertionFailure("PBXTarget must be subclassed")
    return ""
  }

  lazy var hashValue: Int = { [unowned self] in
    return self.name.hashValue &+ (self.comment?.hashValue ?? 0)
  }()

  var comment: String? {
    return name
  }

  init(name: String, deploymentTarget: DeploymentTarget?) {
    self.name = name
    self.deploymentTarget = deploymentTarget
  }

  /// Creates a dependency on the given target.
  /// If first is true, the dependency will be prepended instead of appended.
  func createDependencyOn(_ target: PBXTarget,
                          proxyType: PBXContainerItemProxy.ProxyType,
                          inProject project: PBXProject,
                          first: Bool = false) {
    if target === self {
      assertionFailure("Targets may not be dependent on themselves. (\(target.name))")
      return
    }

    let dependency = project.createTargetDependency(target, proxyType: proxyType)
    if first {
      dependencies.insert(dependency, at: 0)
    } else {
      dependencies.append(dependency)
    }
  }

  /// Creates a BuildAction-only dependency on the given target. Unlike a true dependency, this
  /// linkage is only intended to affect generated XCSchemes.
  func createBuildActionDependencyOn(_ target: PBXTarget) {
    buildActionDependencies.insert(target)
  }

  func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try serializer.addField("buildPhases", buildPhases)
    try serializer.addField("buildConfigurationList", buildConfigurationList)
    try serializer.addField("dependencies", dependencies)
    try serializer.addField("name", name)
    try serializer.addField("productName", productName)
  }
}

func == (lhs: PBXTarget, rhs: PBXTarget) -> Bool {
  return lhs.name == rhs.name
}


/// Models a target that produces a binary.
final class PBXNativeTarget: PBXTarget {
  let productType: ProductType

  /// Reference to the output of this target.
  var productReference: PBXFileReference?

  override var buildableName: String {
    return productType.productName(name)
  }

  override var isa: String {
    return "PBXNativeTarget"
  }

  init(name: String, deploymentTarget: DeploymentTarget?, productType: ProductType) {
    self.productType = productType
    super.init(name: name, deploymentTarget: deploymentTarget)
  }

  override func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try super.serializeInto(serializer)
    // An empty buildRules array is emitted to match Xcode's serialization.
    try serializer.addField("buildRules", [String]())
    try serializer.addField("productReference", productReference)
    try serializer.addField("productType", productType.rawValue)
  }
}


/// Models a target that executes an arbitrary binary.
final class PBXLegacyTarget: PBXTarget {
  let buildArgumentsString: String
  let buildToolPath: String
  let buildWorkingDirectory: String
  var passBuildSettingsInEnvironment: Bool = true

  override var isa: String {
    return "PBXLegacyTarget"
  }

  init(name: String,
       deploymentTarget: DeploymentTarget?,
       buildToolPath: String,
       buildArguments: String,
       buildWorkingDirectory: String) {
    self.buildToolPath = buildToolPath
    self.buildArgumentsString = buildArguments
    self.buildWorkingDirectory = buildWorkingDirectory
    super.init(name: name, deploymentTarget: deploymentTarget)
  }

  override func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try super.serializeInto(serializer)
    try serializer.addField("buildArgumentsString", buildArgumentsString)
    try serializer.addField("buildToolPath", buildToolPath)
    try serializer.addField("buildWorkingDirectory", buildWorkingDirectory)
    try serializer.addField("passBuildSettingsInEnvironment", passBuildSettingsInEnvironment)
  }
}


/// Models a link to a target or output file which may be in a different project.
final class PBXContainerItemProxy: PBXObjectProtocol, Hashable {
  /// The type of the item being referenced.
  enum ProxyType: Int {
    /// Refers to a PBXTarget in some project file.
    case targetReference = 1

    /// Refers to a PBXFileReference in some other project file (an output of another project's
    /// target).
    case fileReference = 2
  }

  var globalID: String = ""

  /// The project containing the referenced item.
  var containerPortal: PBXProject {
    return _ContainerPortal!
  }
  private weak var _ContainerPortal: PBXProject?

  /// The target being tracked by this proxy.
  var target: PBXObjectProtocol {
    return _target!
  }
  fileprivate weak var _target: PBXObjectProtocol?

  let proxyType: ProxyType

  var isa: String {
    return "PBXContainerItemProxy"
  }

  var hashValue: Int {
    return _target!.hashValue &+ proxyType.rawValue
  }

  var comment: String? {
    return "PBXContainerItemProxy"
  }

  init(containerPortal: PBXProject, target: PBXObjectProtocol, proxyType: ProxyType) {
    self._ContainerPortal = containerPortal
    self._target = target
    self.proxyType = proxyType
  }

  func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    try serializer.addField("containerPortal", _ContainerPortal)
    try serializer.addField("proxyType", proxyType.rawValue)
    try serializer.addField("remoteGlobalIDString", _target, rawID: true)
  }
}

func == (lhs: PBXContainerItemProxy, rhs: PBXContainerItemProxy) -> Bool {
  if lhs.proxyType != rhs.proxyType { return false }

  switch lhs.proxyType {
    case .targetReference:
      return lhs._target as? PBXTarget == rhs._target as? PBXTarget
    case .fileReference:
      return lhs._target as? PBXFileReference == rhs._target as? PBXFileReference
  }
}


/// Models a dependent relationship between a build target and some other build target.
final class PBXTargetDependency: PBXObjectProtocol {
  var globalID: String = ""
  let targetProxy: PBXContainerItemProxy

  init(targetProxy: PBXContainerItemProxy) {
    self.targetProxy = targetProxy
  }

  var isa: String {
    return "PBXTargetDependency"
  }

  var hashValue: Int {
    return targetProxy.hashValue
  }

  var comment: String? {
    return "PBXTargetDependency"
  }

  func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    // Note(abaire): Xcode also generates a "target" field.
    try serializer.addField("targetProxy", targetProxy)
  }
}


/// Models a project container.
final class PBXProject: PBXObjectProtocol {
  // Name of the group in which target file references are stored.
  static let ProductsGroupName = "Products"
  // Name of the group inside ProductsGroupName to store indexer target file references.
  static let IndexerProductsGroupName = "Indexer"

  var globalID: String = ""
  let name: String

  /// The root group for this project.
  let mainGroup: PBXGroup

  /// Map of target name to target instance.
  var targetByName = [String: PBXTarget]()

  /// List of all targets.
  var allTargets: Dictionary<String, PBXTarget>.Values {
    return targetByName.values
  }

  let compatibilityVersion = XcodeVersionInfo.compatibilityVersion
  let lastUpgradeCheck = "1000"
  /// May be set to an Xcode version string indicating the last time a Swift upgrade check was
  /// performed (e.g., 0710).
  var lastSwiftUpdateCheck: String? = nil

  /// List of (testTarget, hostTarget) pairs linking test targets to their host applications.
  var testTargetLinkages = [(PBXTarget, PBXTarget)]()

  // Maps container proxies to PBXTargetDependency instances to facilitate reuse of target
  // dependency instances.
  var targetDependencies = [PBXContainerItemProxy: PBXTargetDependency]()

  lazy var buildConfigurationList: XCConfigurationList = { [unowned self] in
    XCConfigurationList(forType: self.isa, named: self.name)
  }()

  var isa: String {
    return "PBXProject"
  }

  var hashValue: Int {
    return name.hashValue
  }

  var comment: String? {
    return "Project object"
  }

  init(name: String, mainGroup: PBXGroup? = nil) {
    if mainGroup != nil {
      self.mainGroup = mainGroup!
    } else {
      self.mainGroup = PBXGroup(name: "mainGroup", path: nil, sourceTree: .SourceRoot, parent: nil)
    }
    self.name = name
  }

  func createNativeTarget(_ name: String,
                          deploymentTarget: DeploymentTarget?,
                          targetType: PBXTarget.ProductType,
                          isIndexerTarget: Bool = false) -> PBXNativeTarget {
    let value = PBXNativeTarget(name: name,
                                deploymentTarget: deploymentTarget,
                                productType: targetType)
    targetByName[name] = value

    var productsGroup = mainGroup.getOrCreateChildGroupByName(PBXProject.ProductsGroupName,
                                                              path: nil)
    if isIndexerTarget {
      productsGroup = productsGroup.getOrCreateChildGroupByName(PBXProject.IndexerProductsGroupName,
                                                                path: nil)
    }
    let productName = targetType.productName(name)
    let productReference = productsGroup.getOrCreateFileReferenceBySourceTree(.BuiltProductsDir,
                                                                              path: productName)
    productReference.fileTypeOverride = targetType.explicitFileType
    productReference.isInputFile = false
    value.productReference = productReference

    return value
  }

  func createLegacyTarget(_ name: String,
                          deploymentTarget: DeploymentTarget?,
                          buildToolPath: String,
                          buildArguments: String,
                          buildWorkingDirectory: String) -> PBXLegacyTarget {
    let value = PBXLegacyTarget(name: name,
                                deploymentTarget: deploymentTarget,
                                buildToolPath: buildToolPath,
                                buildArguments: buildArguments,
                                buildWorkingDirectory: buildWorkingDirectory)
    targetByName[name] = value
    return value
  }

  /// Creates subgroups and a file reference to the given path under the special Products directory
  /// rather than as a normal component of the build process. This should very rarely be used, but
  /// is useful if it is necessary to add references to byproducts of the build process that are
  /// not the direct output of any PBXTarget.
  @discardableResult
  func createProductReference(_ path: String) -> (Set<PBXGroup>, PBXFileReference) {
    let productsGroup = mainGroup.getOrCreateChildGroupByName(PBXProject.ProductsGroupName,
                                                              path: nil)
    return createGroupsAndFileReferenceForPath(path, underGroup: productsGroup)
  }

  func linkTestTarget(_ testTarget: PBXTarget, toHostTarget hostTarget: PBXTarget) {
    testTargetLinkages.append((testTarget, hostTarget))
    testTarget.createDependencyOn(hostTarget,
                                  proxyType:PBXContainerItemProxy.ProxyType.targetReference,
                                  inProject: self)
  }

  func linkedTestTargetsForHost(_ host: PBXTarget) -> [PBXTarget] {
    let targetHostPairs = testTargetLinkages.filter() {
      (testTarget: PBXTarget, testHostTarget: PBXTarget) -> Bool in
        testHostTarget == host
    }

    return targetHostPairs.map() { $0.0 }
  }

  func linkedHostForTestTarget(_ target: PBXTarget) -> PBXTarget? {
    for (testTarget, testHostTarget) in testTargetLinkages {
      if testTarget == target {
        return testHostTarget
      }
    }

    return nil
  }

  func createTargetDependency(_ target: PBXTarget, proxyType: PBXContainerItemProxy.ProxyType) -> PBXTargetDependency {
    let targetProxy = PBXContainerItemProxy(containerPortal: self, target: target, proxyType: proxyType)
    if let existingDependency = targetDependencies[targetProxy] {
      return existingDependency
    }

    let dependency = PBXTargetDependency(targetProxy: targetProxy)
    targetDependencies[targetProxy] = dependency
    return dependency
  }

  func targetByName(_ name: String) -> PBXTarget? {
    return targetByName[name]
  }

  /// Creates subgroups and file references for the given set of paths. Path directory components
  /// will be expanded into nested PBXGroup instances, but will not have individual path components.
  /// The full path is made into a PBXFileReference under the inner most PBXGroup.
  /// Returns a tuple containing the PBXGroup and PBXFileReference instances that were touched while
  /// processing the set of paths.
  @discardableResult
  func getOrCreateGroupsAndFileReferencesForPaths(_ paths: [String]) -> (Set<PBXGroup>, [PBXFileReference]) {
    var accessedGroups = Set<PBXGroup>()
    var accessedFileReferences = [PBXFileReference]()

    for path in paths {
      let (groups, ref) = createGroupsAndFileReferenceForPath(path, underGroup: mainGroup)
      accessedGroups.formUnion(groups)
      ref.isInputFile = true
      accessedFileReferences.append(ref)
    }

    return (accessedGroups, accessedFileReferences)
  }

  func getOrCreateGroupForPath(_ path: String) -> PBXGroup {
    guard !path.isEmpty else {
      // Rather than creating an empty subpath, return the mainGroup itself.
      return mainGroup
    }
    var group = mainGroup
    for component in path.components(separatedBy: "/") {
      let groupName = component.isEmpty ? "/" : component
      group = group.getOrCreateChildGroupByName(groupName, path: nil)
    }
    return group
  }

  func getOrCreateVersionGroupForPath(_ path: String, versionGroupType: String) -> XCVersionGroup {
    let parentPath = (path as NSString).deletingLastPathComponent
    let group = getOrCreateGroupForPath(parentPath)

    let versionedGroupName = (path as NSString).lastPathComponent
    let versionedGroup = group.getOrCreateChildVersionGroupByName(versionedGroupName,
                                                                  path: nil)
    versionedGroup.versionGroupType = versionGroupType
    return versionedGroup
  }

  func serializeInto(_ serializer: PBXProjFieldSerializer) throws {
    var attributes: [String: AnyObject] = ["LastUpgradeCheck": lastUpgradeCheck as AnyObject]
    if lastSwiftUpdateCheck != nil {
      attributes["LastSwiftUpdateCheck"] = lastSwiftUpdateCheck! as AnyObject?
    }

    // Link test targets to their host applications.
    var testLinkages = [String: Any]()
    for (testTarget, hostTarget) in testTargetLinkages {
      let testTargetID = try serializer.serializeObject(testTarget, returnRawID: true)
      let hostTargetID = try serializer.serializeObject(hostTarget, returnRawID: true)
      testLinkages[testTargetID] = ["TestTargetID": hostTargetID]
    }
    if !testLinkages.isEmpty {
      attributes["TargetAttributes"] = testLinkages as AnyObject?
    }

    try serializer.addField("attributes", attributes)
    try serializer.addField("buildConfigurationList", buildConfigurationList)
    try serializer.addField("compatibilityVersion", compatibilityVersion)
    try serializer.addField("mainGroup", mainGroup)
    try serializer.addField("targets", targetByName.values.sorted(by: {$0.name < $1.name}))

    // Hardcoded defaults to match Xcode behavior.
    try serializer.addField("developmentRegion", "English")
    try serializer.addField("hasScannedForEncodings", false)
    try serializer.addField("knownRegions", ["en"])
  }

  func createGroupsAndFileReferenceForPath(
    _ path: String,
    underGroup parent: PBXGroup
  ) -> (Set<PBXGroup>, PBXFileReference) {
    var group = parent
    var accessedGroups = Set<PBXGroup>()

    // Traverse the directory components of the path, converting them to Xcode
    // PBXGroups without a path component.
    let components = path.components(separatedBy: "/")
    for i in 0 ..< components.count - 1 {
      // Check to see if this component is actually a bundle that should be treated as a file
      // reference by Xcode (e.g., .xcassets bundles) instead of as a PBXGroup.
      let currentComponent = components[i]

      // Support per-locale files (lprojs), which are represented in PBXVariantGroups.
      if currentComponent.pbPathExtension == "lproj" {
        let lprojName = currentComponent.replacingOccurrences(of: ".lproj", with: "")
        let name = components[i + 1] // Assume it's the next (and last).

        let variantGroup = group.getOrCreateChildVariantGroupByName(name)
        accessedGroups.insert(variantGroup)

        let fileRef = variantGroup.getOrCreateFileReferenceBySourceTree(.Group,
                                                                        path: path,
                                                                        name: lprojName)
        if let ext = name.pbPathExtension, let uti = DirExtensionToUTI[ext] {
          fileRef.fileTypeOverride = uti
        }
        return (accessedGroups, fileRef)
      }

      // This will naively create a bundle grouping rather than including the per-locale strings.
      if let ext = currentComponent.pbPathExtension, let uti = DirExtensionToUTI[ext] {
        let partialPath = components[0...i].joined(separator: "/")
        let fileRef = group.getOrCreateFileReferenceBySourceTree(.Group, path: partialPath)
        fileRef.fileTypeOverride = uti

        // Contents of bundles should never be referenced directly so this path
        // entry is now fully parsed.
        return (accessedGroups, fileRef)
      }

      // Create a subgroup for this simple path component.
      let groupName = currentComponent.isEmpty ? "/" : currentComponent
      group = group.getOrCreateChildGroupByName(groupName, path: nil)
      accessedGroups.insert(group)
    }

    let fileRef = group.getOrCreateFileReferenceBySourceTree(.Group, path: path)
    return (accessedGroups, fileRef)
  }
}
