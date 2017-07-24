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

/// Provides a set of project paths to stub Info.plist files to be used by generated targets.
struct StubInfoPlistPaths {
  let resourcesDirectory: String
  let defaultStub: String
  let watchOSStub: String
  let watchOSAppExStub: String

  func stubPlist(_ entry: RuleEntry) -> String {

    switch entry.pbxTargetType! {
    case .Watch1App, .Watch2App:
      return watchOSStub

    case .Watch1Extension, .Watch2Extension:
      return watchOSAppExStub

    case .AppExtension:
      return stubProjectPath(forRuleEntry: entry)

    default:
      return defaultStub
    }
  }

  func plistFilename(forRuleEntry ruleEntry: RuleEntry) -> String {
    return "Stub_\(ruleEntry.label.asFullPBXTargetName!).plist"
  }

  func stubProjectPath(forRuleEntry ruleEntry: RuleEntry) -> String {
    let fileName = plistFilename(forRuleEntry: ruleEntry)
    return "\(resourcesDirectory)/\(fileName)"
  }
}

/// Defines an object that can populate a PBXProject based on RuleEntry's.
protocol PBXTargetGeneratorProtocol: class {
  static func getRunTestTargetBuildConfigPrefix() -> String

  static func workingDirectoryForPBXGroup(_ group: PBXGroup) -> String

  /// Returns a new PBXGroup instance appropriate for use as a top level project group.
  static func mainGroupForOutputFolder(_ outputFolderURL: URL, workspaceRootURL: URL) -> PBXGroup

  init(bazelURL: URL,
       bazelBinPath: String,
       project: PBXProject,
       buildScriptPath: String,
       stubInfoPlistPaths: StubInfoPlistPaths,
       tulsiVersion: String,
       options: TulsiOptionSet,
       localizedMessageLogger: LocalizedMessageLogger,
       workspaceRootURL: URL,
       suppressCompilerDefines: Bool,
       redactWorkspaceSymlink: Bool)

  /// Generates file references for the given file paths in the associated project without adding
  /// them to an indexer target. The paths must be relative to the workspace root. If pathFilters is
  /// non-nil, paths that do not match an entry in the pathFilters set will be omitted.
  func generateFileReferencesForFilePaths(_ paths: [String], pathFilters: Set<String>?)

  /// Registers the given Bazel rule and its transitive dependencies for inclusion by the Xcode
  /// indexer, adding source files whose directories are present in pathFilters.
  func registerRuleEntryForIndexer(_ ruleEntry: RuleEntry,
                                   ruleEntryMap: [BuildLabel: RuleEntry],
                                   pathFilters: Set<String>)

  /// Generates indexer targets for rules that were previously registered through
  /// registerRuleEntryForIndexer. This method may only be called once, after all rule entries have
  /// been registered.
  /// Returns a map of indexer targets, keyed by the name of the indexer.
  func generateIndexerTargets() -> [String: PBXTarget]

  /// Generates a legacy target that is added as a dependency of all build targets and invokes
  /// the given script. The build action may be accessed by the script via the ACTION environment
  /// variable.
  func generateBazelCleanTarget(_ scriptPath: String, workingDirectory: String)

  /// Generates project-level build configurations.
  func generateTopLevelBuildConfigurations(_ buildSettingOverrides: [String: String])

  /// Generates Xcode build targets that invoke Bazel for the given targets. For test-type rules,
  /// non-compiling source file linkages are created to facilitate indexing of XCTests.
  /// Returns a map of target name to associated intermediate build artifacts.
  /// Throws if one of the RuleEntry instances is for an unsupported Bazel target type.
  func generateBuildTargetsForRuleEntries(_ entries: Set<RuleEntry>,
                                          ruleEntryMap: [BuildLabel: RuleEntry]) throws -> [String: [String]]
}

extension PBXTargetGeneratorProtocol {
  func generateFileReferencesForFilePaths(_ paths: [String]) {
    generateFileReferencesForFilePaths(paths, pathFilters: nil)
  }
}


/// Concrete PBXProject target generator.
final class PBXTargetGenerator: PBXTargetGeneratorProtocol {

  enum ProjectSerializationError: Error {
    case buildFileIsNotContainedByProjectRoot
    case generalFailure(String)
    case unsupportedTargetType(String)
  }

  /// Names of Xcode build configurations to generate.
  // NOTE: Must be kept in sync with the CONFIGURATION environment variable use in the build script.
  static let buildConfigNames = ["Debug", "Release"]

  /// Tuples consisting of a test runner config name and the base config name (from
  /// buildConfigNames) that it inherits from.
  static let testRunnerEnabledBuildConfigNames = ["Debug", "Release"].map({
    (runTestTargetBuildConfigPrefix + $0, $0)
  })

  /// Prefix for special configs used when running XCTests that prevent compilation and linking of
  /// any source files. This allows XCTest bundles to have associated test sources indexed by Xcode
  /// but not compiled when testing (as they're compiled by Bazel and the generated project may be
  /// missing information necessary to compile them anyway). Configs are generated for Debug and
  /// Release builds.
  // NOTE: This value needs to be kept in sync with the bazel_build script.
  static let runTestTargetBuildConfigPrefix = "__TulsiTestRunner_"
  // TODO(abaire): Remove when Swift supports static stored properties in protocols.
  static func getRunTestTargetBuildConfigPrefix() -> String {
    return runTestTargetBuildConfigPrefix
  }

  /// Name of the static library target that will be used to accumulate all source file dependencies
  /// in order to make their symbols available to the Xcode indexer.
  static let IndexerTargetPrefix = "_idx_"

  /// Rough sanity limit on indexer name length. Names may be slightly longer than this limit.
  /// Empirically, 255 characters is the observed threshold for problems with file systems.
  static let MaxIndexerNameLength = 180

  // Name prefix for auto-generated nop-app extension targets necessary to get Xcode to debug watch
  // Apps.
  private static let watchAppExtensionTargetPrefix = "_tulsi_appex_"

  /// Name of the legacy target that will be used to communicate with Bazel during Xcode clean
  /// actions.
  static let BazelCleanTarget = "_bazel_clean_"

  /// Xcode variable name used to refer to the workspace root.
  static let WorkspaceRootVarName = "TULSI_WR"

  /// Xcode variable name used to refer to the symlink generated by Bazel that contains all
  /// workspace content.
  static let BazelWorkspaceSymlinkVarName = "TULSI_BWRS"

  /// Location of the bazel binary.
  let bazelURL: URL

  /// Location of the bazel bin symlink, relative to the workspace root.
  let bazelBinPath: String
  private(set) lazy var bazelGenfilesPath: String = { [unowned self] in
    return self.bazelBinPath.replacingOccurrences(of: "-bin", with: "-genfiles")
  }()
  private lazy var bazelWorkspaceSymlinkPath: String = { [unowned self] in
    let workspaceDirName: String
    if self.redactWorkspaceSymlink {
      workspaceDirName = "WORKSPACENAME"
    } else {
      workspaceDirName = self.workspaceRootURL.lastPathComponent
    }
    return self.bazelBinPath.replacingOccurrences(of: "-bin", with: "-\(workspaceDirName)")
  }()

  /// The path to the Tulsi generated outputs root. For more information see tulsi_aspects.bzl
  let tulsiIncludesPath = "tulsi-includes/x/x"

  let project: PBXProject
  let buildScriptPath: String
  let stubInfoPlistPaths: StubInfoPlistPaths
  let tulsiVersion: String
  let options: TulsiOptionSet
  let localizedMessageLogger: LocalizedMessageLogger
  let workspaceRootURL: URL
  let suppressCompilerDefines: Bool
  let redactWorkspaceSymlink: Bool

  var bazelCleanScriptTarget: PBXLegacyTarget? = nil

  /// Stores data about a given RuleEntry to be used in order to generate Xcode indexer targets.
  private struct IndexerData {
    /// Provides information about the RuleEntry instances supported by an IndexerData.
    /// Specifically, NameInfoToken tuples provide the targetName and the full target label hash in
    /// order to differentiate between rules with the same name but different paths.
    struct NameInfoToken {
      let targetName: String
      let labelHash: Int

      init(ruleEntry: RuleEntry) {
        self.init(label: ruleEntry.label)
      }

      init(label: BuildLabel) {
        targetName = label.targetName!
        labelHash = label.hashValue
      }
    }

    let indexerNameInfo: [NameInfoToken]
    let dependencies: Set<BuildLabel>
    let preprocessorDefines: Set<String>
    let otherCFlags: [String]
    let otherSwiftFlags: [String]
    let includes: [String]
    let frameworkSearchPaths: [String]
    let swiftIncludePaths: [String]
    let iPhoneOSDeploymentTarget: String?
    let macOSDeploymentTarget: String?
    let tvOSDeploymentTarget: String?
    let watchOSDeploymentTarget: String?
    let buildPhase: PBXSourcesBuildPhase
    let pchFile: BazelFileInfo?
    let bridgingHeader: BazelFileInfo?
    let enableModules: Bool

    /// Returns the full name that should be used when generating a target for this indexer.
    var indexerName: String {
      var fullName = ""
      var fullHash = 0

      for token in indexerNameInfo {
        if fullName.isEmpty {
          fullName = token.targetName
        } else {
          fullName += "_\(token.targetName)"
        }
        fullHash = fullHash &+ token.labelHash
      }
      return PBXTargetGenerator.indexerNameForTargetName(fullName, hash: fullHash)
    }

    /// Returns an array of aliases for this indexer data. Each element is the full indexerName of
    /// an IndexerData instance that has been merged into this IndexerData.
    var supportedIndexingTargets: [String] {
      var supportedTargets = [indexerName]
      if indexerNameInfo.count > 1 {
        for token in indexerNameInfo {
          supportedTargets.append(PBXTargetGenerator.indexerNameForTargetName(token.targetName,
                                                                              hash: token.labelHash))
        }
      }
      return supportedTargets
    }

    /// Returns an array of indexing target names that this indexer depends on.
    var indexerNamesForDependencies: [String] {
      return dependencies.map() {
        PBXTargetGenerator.indexerNameForTargetName($0.targetName!, hash: $0.hashValue)
      }
    }

    /// Indicates whether or not this indexer may be merged with the given indexer.
    func canMergeWith(_ other: IndexerData) -> Bool {
      if self.pchFile != other.pchFile || self.bridgingHeader != other.bridgingHeader {
        return false
      }

      if !(preprocessorDefines == other.preprocessorDefines &&
          enableModules == other.enableModules &&
          otherCFlags == other.otherCFlags &&
          otherSwiftFlags == other.otherSwiftFlags &&
          frameworkSearchPaths == other.frameworkSearchPaths &&
          includes == other.includes &&
          swiftIncludePaths == other.swiftIncludePaths &&
          iPhoneOSDeploymentTarget == other.iPhoneOSDeploymentTarget &&
          macOSDeploymentTarget == other.macOSDeploymentTarget &&
          tvOSDeploymentTarget == other.tvOSDeploymentTarget &&
          watchOSDeploymentTarget == other.watchOSDeploymentTarget) {
        return false
      }

      return true
    }

    /// Returns a new IndexerData instance that is the result of merging this indexer with another.
    func merging(_ other: IndexerData) -> IndexerData {
      let newDependencies = dependencies.union(other.dependencies)
      let newName = indexerNameInfo + other.indexerNameInfo
      let newBuildPhase = PBXSourcesBuildPhase()
      newBuildPhase.files = buildPhase.files + other.buildPhase.files

      return IndexerData(indexerNameInfo: newName,
                         dependencies: newDependencies,
                         preprocessorDefines: preprocessorDefines,
                         otherCFlags: otherCFlags,
                         otherSwiftFlags: otherSwiftFlags,
                         includes: includes,
                         frameworkSearchPaths: frameworkSearchPaths,
                         swiftIncludePaths: swiftIncludePaths,
                         iPhoneOSDeploymentTarget: iPhoneOSDeploymentTarget,
                         macOSDeploymentTarget: macOSDeploymentTarget,
                         tvOSDeploymentTarget: tvOSDeploymentTarget,
                         watchOSDeploymentTarget: watchOSDeploymentTarget,
                         buildPhase: newBuildPhase,
                         pchFile: pchFile,
                         bridgingHeader: bridgingHeader,
                         enableModules: enableModules)
    }
  }

  /// Registered indexers that will be modeled as static libraries.
  private var staticIndexers = [String: IndexerData]()
  /// Registered indexers that will be modeled as dynamic frameworks.
  private var frameworkIndexers = [String: IndexerData]()

  /// Maps the names of indexer targets to the generated target instance in the project. Values are
  /// not guaranteed to be unique, as several targets may be merged into a single target during
  /// optimization.
  private var indexerTargetByName = [String: PBXTarget]()

  static func workingDirectoryForPBXGroup(_ group: PBXGroup) -> String {
    switch group.sourceTree {
      case .SourceRoot:
        if let relativePath = group.path, !relativePath.isEmpty {
          return "${SRCROOT}/\(relativePath)"
        }
        return ""

      case .Absolute:
        return group.path!

      default:
        assertionFailure("Group has an unexpected sourceTree type \(group.sourceTree)")
        return ""
    }
  }

  static func mainGroupForOutputFolder(_ outputFolderURL: URL, workspaceRootURL: URL) -> PBXGroup {
    let outputFolder = outputFolderURL.path
    let workspaceRoot = workspaceRootURL.path

    let slashTerminatedOutputFolder = outputFolder + (outputFolder.hasSuffix("/") ? "" : "/")
    let slashTerminatedWorkspaceRoot = workspaceRoot + (workspaceRoot.hasSuffix("/") ? "" : "/")

    // If workspaceRoot == outputFolder, return a relative group with no path.
    if slashTerminatedOutputFolder == slashTerminatedWorkspaceRoot {
      return PBXGroup(name: "mainGroup", path: nil, sourceTree: .SourceRoot, parent: nil)
    }

    // If outputFolder contains workspaceRoot, return a relative group with the path from
    // outputFolder to workspaceRoot
    if workspaceRoot.hasPrefix(slashTerminatedOutputFolder) {
      let index = workspaceRoot.characters.index(workspaceRoot.startIndex, offsetBy: slashTerminatedOutputFolder.characters.count)
      let relativePath = workspaceRoot.substring(from: index)
      return PBXGroup(name: "mainGroup",
                      path: relativePath,
                      sourceTree: .SourceRoot,
                      parent: nil)
    }

    // If workspaceRoot contains outputFolder, return a relative group using .. to walk up to
    // workspaceRoot from outputFolder.
    if outputFolder.hasPrefix(slashTerminatedWorkspaceRoot) {
      let index = outputFolder.characters.index(outputFolder.startIndex, offsetBy: slashTerminatedWorkspaceRoot.characters.count + 1)
      let pathToWalkBackUp = outputFolder.substring(from: index) as NSString
      let numberOfDirectoriesToWalk = pathToWalkBackUp.pathComponents.count
      let relativePath = [String](repeating: "..", count: numberOfDirectoriesToWalk).joined(separator: "/")
      return PBXGroup(name: "mainGroup",
                      path: relativePath,
                      sourceTree: .SourceRoot,
                      parent: nil)
    }

    return PBXGroup(name: "mainGroup",
                    path: workspaceRootURL.path,
                    sourceTree: .Absolute,
                    parent: nil)
  }

  /// Returns a project-relative path for the given BazelFileInfo.
  private static func projectRefForBazelFileInfo(_ info: BazelFileInfo) -> String {
    switch info.targetType {
      case .generatedFile:
        return "$(\(WorkspaceRootVarName))/\(info.fullPath)"
      case .sourceFile:
        return "$(\(BazelWorkspaceSymlinkVarName))/\(info.fullPath)"
    }
  }

  init(bazelURL: URL,
       bazelBinPath: String,
       project: PBXProject,
       buildScriptPath: String,
       stubInfoPlistPaths: StubInfoPlistPaths,
       tulsiVersion: String,
       options: TulsiOptionSet,
       localizedMessageLogger: LocalizedMessageLogger,
       workspaceRootURL: URL,
       suppressCompilerDefines: Bool = false,
       redactWorkspaceSymlink: Bool = false) {
    self.bazelURL = bazelURL
    self.bazelBinPath = bazelBinPath
    self.project = project
    self.buildScriptPath = buildScriptPath
    self.stubInfoPlistPaths = stubInfoPlistPaths
    self.tulsiVersion = tulsiVersion
    self.options = options
    self.localizedMessageLogger = localizedMessageLogger
    self.workspaceRootURL = workspaceRootURL
    self.suppressCompilerDefines = suppressCompilerDefines
    self.redactWorkspaceSymlink = redactWorkspaceSymlink
  }

  func generateFileReferencesForFilePaths(_ paths: [String], pathFilters: Set<String>?) {
    if let pathFilters = pathFilters {
      let filteredPaths = paths.filter(pathFilterFunc(pathFilters))
      project.getOrCreateGroupsAndFileReferencesForPaths(filteredPaths)
    } else {
      project.getOrCreateGroupsAndFileReferencesForPaths(paths)
    }
  }

  func registerRuleEntryForIndexer(_ ruleEntry: RuleEntry,
                                   ruleEntryMap: [BuildLabel: RuleEntry],
                                   pathFilters: Set<String>) {
    let includePathInProject = pathFilterFunc(pathFilters)
    func includeFileInProject(_ info: BazelFileInfo) -> Bool {
      return includePathInProject(info.fullPath)
    }

    func addFileReference(_ info: BazelFileInfo) {
      let (_, fileReferences) = project.getOrCreateGroupsAndFileReferencesForPaths([info.fullPath])
      fileReferences.first!.isInputFile = info.targetType == .sourceFile
    }

    func addBuildFileForRule(_ ruleEntry: RuleEntry) {
      guard let buildFilePath = ruleEntry.buildFilePath, includePathInProject(buildFilePath) else {
        return
      }
      project.getOrCreateGroupsAndFileReferencesForPaths([buildFilePath])
    }

    // Map of build label to cumulative preprocessor framework search paths.
    // TODO(b/63628175): Clean this nested method to also retrieve framework_dir and framework_file
    // from the ObjcProvider, for both static and dynamic frameworks.
    var processedEntries = [BuildLabel: (NSOrderedSet)]()
    @discardableResult
    func generateIndexerTargetGraphForRuleEntry(_ ruleEntry: RuleEntry) -> (NSOrderedSet) {
      if let data = processedEntries[ruleEntry.label] {
        return data
      }
      var frameworkSearchPaths = NSMutableOrderedSet()

      defer {
        processedEntries[ruleEntry.label] = (frameworkSearchPaths)
      }

      for dep in ruleEntry.dependencies {
        guard let depEntry = ruleEntryMap[BuildLabel(dep)] else {
          localizedMessageLogger.warning("UnknownTargetRule",
                                         comment: "Failure to look up a Bazel target that was expected to be present. The target label is %1$@",
                                         values: dep)
          continue
        }

        let inheritedFrameworkSearchPaths = generateIndexerTargetGraphForRuleEntry(depEntry)
        frameworkSearchPaths.union(inheritedFrameworkSearchPaths)
      }
      var defines = Set<String>()
      if let ruleDefines = ruleEntry.defines {
        defines.formUnion(ruleDefines)
      }

      if !suppressCompilerDefines,
         let ruleDefines = ruleEntry.attributes[.compiler_defines] as? [String], !ruleDefines.isEmpty {
        defines.formUnion(ruleDefines)
      }

      let includes = NSMutableOrderedSet()
      if let includePaths = ruleEntry.includePaths {
        let rootedPaths: [String] = includePaths.map() { (path, recursive) in
          let rootedPath = "$(\(PBXTargetGenerator.WorkspaceRootVarName))/\(path)"
          if recursive {
            return "\(rootedPath)/**"
          }
          return rootedPath
        }
        includes.addObjects(from: rootedPaths)

        /// Some targets that generate sources also provide header search paths into non-generated
        /// sources. Using workspace root is needed for the former, but the latter has to be
        /// included via the Bazel workspace root.
        /// TODO(tulsi-team): See if we can merge the two locations to just Bazel workspace.
        let bazelWorkspaceRootedPaths: [String] = includePaths.map() { (path, recursive) in
          let rootedPath = "$(\(PBXTargetGenerator.BazelWorkspaceSymlinkVarName))/\(path)"
          if recursive {
            return "\(rootedPath)/**"
          }
          return rootedPath
        }
        includes.addObjects(from: bazelWorkspaceRootedPaths)
      }

      // Search path entries are added for all framework imports, regardless of whether the
      // framework bundles are allowed by the include filters. The search path excludes the bundle
      // itself.
      ruleEntry.frameworkImports.forEach() {
        let fullPath = $0.fullPath as NSString
        let rootedPath = "$(\(PBXTargetGenerator.BazelWorkspaceSymlinkVarName))/\(fullPath.deletingLastPathComponent)"
        frameworkSearchPaths.add(rootedPath)
      }
      let sourceFileInfos = ruleEntry.sourceFiles.filter(includeFileInProject)
      let nonARCSourceFileInfos = ruleEntry.nonARCSourceFiles.filter(includeFileInProject)
      let frameworkFileInfos = ruleEntry.frameworkImports.filter(includeFileInProject)
      let nonSourceVersionedFileInfos = ruleEntry.versionedNonSourceArtifacts.filter(includeFileInProject)

      for target in ruleEntry.normalNonSourceArtifacts.filter(includeFileInProject) {
        let path = target.fullPath as NSString
        let group = project.getOrCreateGroupForPath(path.deletingLastPathComponent)
        let ref = group.getOrCreateFileReferenceBySourceTree(.Group,
                                                             path: path as String)
        ref.isInputFile = target.targetType == .sourceFile
      }

      if sourceFileInfos.isEmpty &&
          nonARCSourceFileInfos.isEmpty &&
          frameworkFileInfos.isEmpty &&
          nonSourceVersionedFileInfos.isEmpty {
        return (frameworkSearchPaths)
      }

      var localPreprocessorDefines = defines
      let localIncludes = includes.mutableCopy() as! NSMutableOrderedSet
      let otherCFlags = NSMutableOrderedSet()
      if let copts = ruleEntry.attributes[.copts] as? [String], !copts.isEmpty {
        for opt in copts {
          // TODO(abaire): Add support for shell tokenization as advertised in the Bazel build
          //     encyclopedia.
          if opt.hasPrefix("-D") {
            localPreprocessorDefines.insert(opt.substring(from: opt.characters.index(opt.startIndex, offsetBy: 2)))
          } else if opt.hasPrefix("-I") {
            var path = opt.substring(from: opt.characters.index(opt.startIndex, offsetBy: 2))
            if !path.hasPrefix("/") {
              path = "$(\(PBXTargetGenerator.BazelWorkspaceSymlinkVarName))/\(path)"
            }
            localIncludes.add(path)
          } else {
            otherCFlags.add(opt)
          }
        }
      }

      let pchFile = BazelFileInfo(info: ruleEntry.attributes[.pch])
      if let pchFile = pchFile, includeFileInProject(pchFile) {
        addFileReference(pchFile)
      }

      let bridgingHeader = BazelFileInfo(info: ruleEntry.attributes[.bridging_header])
      if let bridgingHeader = bridgingHeader, includeFileInProject(bridgingHeader) {
        addFileReference(bridgingHeader)
      }
      let enableModules = (ruleEntry.attributes[.enable_modules] as? Int) == 1

      addBuildFileForRule(ruleEntry)

      let (nonARCFiles, nonARCSettings) = generateFileReferencesAndSettingsForNonARCFileInfos(nonARCSourceFileInfos)
      var fileReferences = generateFileReferencesForFileInfos(sourceFileInfos)
      fileReferences.append(contentsOf: generateFileReferencesForFileInfos(frameworkFileInfos))
      fileReferences.append(contentsOf: nonARCFiles)

      var buildPhaseReferences: [PBXReference]
      if nonSourceVersionedFileInfos.isEmpty {
        buildPhaseReferences = [PBXReference]()
      } else {
        let versionedFileReferences = createReferencesForVersionedFileTargets(nonSourceVersionedFileInfos)
        buildPhaseReferences = versionedFileReferences as [PBXReference]
      }
      buildPhaseReferences.append(contentsOf: fileReferences as [PBXReference])

      let buildPhase = createBuildPhaseForReferences(buildPhaseReferences,
                                                     withPerFileSettings: nonARCSettings)

      if !buildPhase.files.isEmpty {
        // TODO(abaire): Extract STL path via the aspect once it is exposed to Skylark.
        // Bazel appends a built-in tools/cpp/gcc3 path in CppHelper.java but that path is not
        // exposed to Skylark. For now Tulsi hardcodes it here to allow proper indexer behavior.
        // NOTE: this requires tools/cpp/gcc3 to be available from the workspace root, which may
        // require symlinking on the part of the user. This requirement should go away when it is
        // retrieved via the aspect (which should resolve the Bazel tool path correctly).
        var resolvedIncludes = localIncludes.array as! [String]
        resolvedIncludes.append("$(\(PBXTargetGenerator.BazelWorkspaceSymlinkVarName))/tools/cpp/gcc3")

        let swiftIncludePaths = NSMutableOrderedSet()
        for module in ruleEntry.swiftTransitiveModules {
          let fullPath = module.fullPath as NSString
          let includePath = fullPath.deletingLastPathComponent
          swiftIncludePaths.add("$(\(PBXTargetGenerator.BazelWorkspaceSymlinkVarName))/\(includePath)")
        }

        // Load module maps explicitly instead of letting Clang discover them on search paths. This
        // is needed to avoid a case where Clang may load the same header both in modular and
        // non-modular contexts, leading to duplicate definitions in the same file.
        // See llvm.org/bugs/show_bug.cgi?id=19501
        let otherSwiftFlags = ruleEntry.objCModuleMaps.map() {
           "-Xcc -fmodule-map-file=$(\(PBXTargetGenerator.BazelWorkspaceSymlinkVarName))/\($0.fullPath)"
        }

        let dependencyLabels = ruleEntry.dependencies.map() { BuildLabel($0) }
        let indexerData = IndexerData(indexerNameInfo: [IndexerData.NameInfoToken(ruleEntry: ruleEntry)],
                                      dependencies: Set(dependencyLabels),
                                      preprocessorDefines: localPreprocessorDefines,
                                      otherCFlags: otherCFlags.array as! [String],
                                      otherSwiftFlags: otherSwiftFlags,
                                      includes: resolvedIncludes,
                                      frameworkSearchPaths: frameworkSearchPaths.array as! [String],
                                      swiftIncludePaths: swiftIncludePaths.array as! [String],
                                      iPhoneOSDeploymentTarget: ruleEntry.iPhoneOSDeploymentTarget,
                                      macOSDeploymentTarget: ruleEntry.macOSDeploymentTarget,
                                      tvOSDeploymentTarget: ruleEntry.tvOSDeploymentTarget,
                                      watchOSDeploymentTarget: ruleEntry.watchOSDeploymentTarget,
                                      buildPhase: buildPhase,
                                      pchFile: pchFile,
                                      bridgingHeader: bridgingHeader,
                                      enableModules: enableModules)
        if (ruleEntry.type == "swift_library") {
          frameworkIndexers[indexerData.indexerName] = indexerData
        } else {
          staticIndexers[indexerData.indexerName] = indexerData
        }
      }

      return (frameworkSearchPaths)
    }

    generateIndexerTargetGraphForRuleEntry(ruleEntry)
  }

  @discardableResult
  func generateIndexerTargets() -> [String: PBXTarget] {
    mergeRegisteredIndexers()

    func generateIndexer(_ name: String,
                         indexerType: PBXTarget.ProductType,
                         data: IndexerData) {
      let indexingTarget = project.createNativeTarget(name, targetType: indexerType)
      indexingTarget.buildPhases.append(data.buildPhase)
      addConfigsForIndexingTarget(indexingTarget, data: data)

      for name in data.supportedIndexingTargets {
        indexerTargetByName[name] = indexingTarget
      }
    }

    for (name, data) in staticIndexers {
      generateIndexer(name, indexerType: PBXTarget.ProductType.StaticLibrary, data: data)
    }

    for (name, data) in frameworkIndexers {
      generateIndexer(name, indexerType: PBXTarget.ProductType.Framework, data: data)
    }

    func linkDependencies(_ dataMap: [String: IndexerData]) {
      for (name, data) in dataMap {
        guard let indexerTarget = indexerTargetByName[name] else {
          localizedMessageLogger.infoMessage("Unexpectedly failed to resolve indexer \(name)")
          continue
        }

        for depName in data.indexerNamesForDependencies {
          guard let indexerDependency = indexerTargetByName[depName], indexerDependency !== indexerTarget else {
            continue
          }

          indexerTarget.createDependencyOn(indexerDependency,
                                           proxyType: PBXContainerItemProxy.ProxyType.targetReference,
                                           inProject: project)
        }
      }
    }

    linkDependencies(staticIndexers)
    linkDependencies(frameworkIndexers)

    return indexerTargetByName
  }

  func generateBazelCleanTarget(_ scriptPath: String, workingDirectory: String = "") {
    assert(bazelCleanScriptTarget == nil, "generateBazelCleanTarget may only be called once")

    let bazelPath = bazelURL.path
    bazelCleanScriptTarget = project.createLegacyTarget(PBXTargetGenerator.BazelCleanTarget,
                                                        buildToolPath: "\(scriptPath)",
                                                        buildArguments: "\"\(bazelPath)\" \"\(bazelBinPath)\"",
                                                        buildWorkingDirectory: workingDirectory)

    for target: PBXTarget in project.allTargets {
      if target === bazelCleanScriptTarget {
        continue
      }

      target.createDependencyOn(bazelCleanScriptTarget!,
                                proxyType: PBXContainerItemProxy.ProxyType.targetReference,
                                inProject: project,
                                first: true)
    }
  }

  func generateTopLevelBuildConfigurations(_ buildSettingOverrides: [String: String] = [:]) {
    var buildSettings = options.commonBuildSettings()

    for (key, value) in buildSettingOverrides {
      buildSettings[key] = value
    }

    buildSettings["ONLY_ACTIVE_ARCH"] = "YES"
    // Fixes an Xcode "Upgrade to recommended settings" warning. Technically the warning only
    // requires this to be added to the Debug build configuration but as code is never compiled
    // anyway it doesn't hurt anything to set it on all configs.
    buildSettings["ENABLE_TESTABILITY"] = "YES"

    // Bazel sources are more or less ARC by default (the user has to use the special non_arc_srcs
    // attribute for non-ARC) so the project is set to reflect that and per-file flags are used to
    // override the default.
    buildSettings["CLANG_ENABLE_OBJC_ARC"] = "YES"

    // Bazel takes care of signing the generated applications, so Xcode's signing must be disabled.
    buildSettings["CODE_SIGNING_REQUIRED"] = "NO"
    buildSettings["CODE_SIGN_IDENTITY"] = ""

    // Explicitly setting the FRAMEWORK_SEARCH_PATHS will allow Xcode to resolve references to the
    // XCTest framework when performing Live issues analysis.
    buildSettings["FRAMEWORK_SEARCH_PATHS"] = "$(PLATFORM_DIR)/Developer/Library/Frameworks";

    var sourceDirectory = PBXTargetGenerator.workingDirectoryForPBXGroup(project.mainGroup)
    if sourceDirectory.isEmpty {
      sourceDirectory = "$(SRCROOT)"
    }

    // A variable pointing to the true root is provided for scripts that may need it.
    buildSettings["\(PBXTargetGenerator.WorkspaceRootVarName)"] = sourceDirectory

    // Bazel generates a symlink to a directory that collects all of the data needed for this
    // workspace. While this is often identical to the workspace, it sometimes collects other paths
    // and is the better option for most Xcode project path references.
    buildSettings["\(PBXTargetGenerator.BazelWorkspaceSymlinkVarName)"] =
        "${\(PBXTargetGenerator.WorkspaceRootVarName)}/\(bazelWorkspaceSymlinkPath)"

    buildSettings["TULSI_VERSION"] = tulsiVersion

    let searchPaths = ["$(\(PBXTargetGenerator.BazelWorkspaceSymlinkVarName))",
                       "$(\(PBXTargetGenerator.WorkspaceRootVarName))/\(bazelBinPath)",
                       "$(\(PBXTargetGenerator.WorkspaceRootVarName))/\(bazelGenfilesPath)",
                       "$(\(PBXTargetGenerator.BazelWorkspaceSymlinkVarName))/\(tulsiIncludesPath)"
    ]
    // Ideally this would use USER_HEADER_SEARCH_PATHS but some code generation tools (e.g.,
    // protocol buffers) make use of system-style includes.
    buildSettings["HEADER_SEARCH_PATHS"] = searchPaths.joined(separator: " ")

    createBuildConfigurationsForList(project.buildConfigurationList, buildSettings: buildSettings)
    addTestRunnerBuildConfigurationToBuildConfigurationList(project.buildConfigurationList)
  }

  /// Generates build targets for the given rule entries and returns a map of target name to the
  /// list of any intermediate artifacts produced when building that target.
  @discardableResult
  func generateBuildTargetsForRuleEntries(_ ruleEntries: Set<RuleEntry>,
                                          ruleEntryMap: [BuildLabel: RuleEntry]) throws -> [String: [String]] {
    let namedRuleEntries = generateUniqueNamesForRuleEntries(ruleEntries)
    var testTargetLinkages = [(PBXTarget, BuildLabel, RuleEntry)]()
    let progressNotifier = ProgressNotifier(name: GeneratingBuildTargets,
                                            maxValue: namedRuleEntries.count)
    var allIntermediateArtifacts = [String: [String]]()
    var watchAppTargets = [String: (PBXNativeTarget, RuleEntry)]()
    var watchExtensionsByEntry = [RuleEntry: PBXNativeTarget]()
    for (name, entry) in namedRuleEntries {
      progressNotifier.incrementValue()
      let (target, intermediateArtifacts) = try createBuildTargetForRuleEntry(entry,
                                                                              named: name,
                                                                              ruleEntryMap: ruleEntryMap)
      allIntermediateArtifacts[name] = intermediateArtifacts

      for attribute in [.xctest_app, .test_host] as [RuleEntry.Attribute] {
        if let hostLabelString = entry.attributes[attribute] as? String {
          let hostLabel = BuildLabel(hostLabelString)
          testTargetLinkages.append((target, hostLabel, entry))
        }
      }

      switch entry.pbxTargetType {
        case .Watch2App?:
          watchAppTargets[name] = (target, entry)
        case .Watch2Extension?:
          watchExtensionsByEntry[entry] = target
        default:
          break
      }
    }

    // The watch app target must have an explicit dependency on the watch extension target.
    for (_, (watchAppTarget, watchRuleEntry)) in watchAppTargets {
      for ext in watchRuleEntry.extensions {
        if let extEntry = ruleEntryMap[ext], extEntry.pbxTargetType == .Watch2Extension {
          if let watchExtensionTarget = watchExtensionsByEntry[extEntry] {
            watchAppTarget.createDependencyOn(watchExtensionTarget, proxyType: .targetReference, inProject: project)
          } else {
            localizedMessageLogger.warning("FindingWatchExtensionFailed",
                                           comment: "Message to show when the watchOS app extension %1$@ could not be found and the resulting project will not be able to launch the watch app.",
                                           values: extEntry.label.value)
          }
        }
      }
    }

    for (testTarget, testHostLabel, entry) in testTargetLinkages {
      updateTestTarget(testTarget,
                       withLinkageToHostTarget: testHostLabel,
                       ruleEntry: entry,
                       ruleEntryMap: ruleEntryMap)
    }

    return allIntermediateArtifacts
  }

  // MARK: - Private methods

  /// Generates a filter function that may be used to verify that a path string is allowed by the
  /// given set of pathFilters.
  private func pathFilterFunc(_ pathFilters: Set<String>) -> (String) -> Bool {
    let recursiveFilters = Set<String>(pathFilters.filter({ $0.hasSuffix("/...") }).map() {
      $0.substring(to: $0.characters.index($0.endIndex, offsetBy: -3))
    })

    func includePath(_ path: String) -> Bool {
      let dir = (path as NSString).deletingLastPathComponent
      if pathFilters.contains(dir) { return true }
      let terminatedDir = dir + "/"
      for filter in recursiveFilters {
        if terminatedDir.hasPrefix(filter) { return true }
      }
      return false
    }

    return includePath
  }

  /// Attempts to reduce the number of indexers by merging any that have identical settings.
  private func mergeRegisteredIndexers() {

    func mergeIndexers<T : Sequence>(_ indexers: T) -> [String: IndexerData] where T.Iterator.Element == IndexerData {
      var mergedIndexers = [String: IndexerData]()
      var indexers = Array(indexers).sorted { $0.indexerName < $1.indexerName }

      while !indexers.isEmpty {
        var remaining = [IndexerData]()
        var d1 = indexers.popLast()!
        for d2 in indexers {
          if d1.canMergeWith(d2) {
            d1 = d1.merging(d2)
          } else {
            remaining.append(d2)
          }
        }

        mergedIndexers[d1.indexerName] = d1
        indexers = remaining
      }

      return mergedIndexers
    }

    staticIndexers = mergeIndexers(staticIndexers.values)
    frameworkIndexers = mergeIndexers(frameworkIndexers.values)
  }

  private func generateFileReferencesForFileInfos(_ infos: [BazelFileInfo]) -> [PBXFileReference] {
    guard !infos.isEmpty else { return [] }
    var generatedFilePaths = [String]()
    var sourceFilePaths = [String]()
    for info in infos {
      switch info.targetType {
        case .generatedFile:
          generatedFilePaths.append(info.fullPath)
        case .sourceFile:
          sourceFilePaths.append(info.fullPath)
      }
    }

    // Add the source paths directly and the generated paths with explicitFileType set.
    var (_, fileReferences) = project.getOrCreateGroupsAndFileReferencesForPaths(sourceFilePaths)
    let (_, generatedFileReferences) = project.getOrCreateGroupsAndFileReferencesForPaths(generatedFilePaths)
    generatedFileReferences.forEach() { $0.isInputFile = false }

    fileReferences.append(contentsOf: generatedFileReferences)
    return fileReferences
  }

  /// Generates file references for the given infos, and returns a settings dictionary to be passed
  /// to createBuildPhaseForReferences:withPerFileSettings:.
  private func generateFileReferencesAndSettingsForNonARCFileInfos(_ infos: [BazelFileInfo]) -> ([PBXFileReference], [PBXFileReference: [String: String]]) {
    let nonARCFileReferences = generateFileReferencesForFileInfos(infos)
    var settings = [PBXFileReference: [String: String]]()
    let disableARCSetting = ["COMPILER_FLAGS": "-fno-objc-arc"]
    nonARCFileReferences.forEach() {
      settings[$0] = disableARCSetting
    }
    return (nonARCFileReferences, settings)
  }

  private func generateUniqueNamesForRuleEntries(_ ruleEntries: Set<RuleEntry>) -> [String: RuleEntry] {
    // Build unique names for the target rules.
    var collidingRuleEntries = [String: [RuleEntry]]()
    for entry: RuleEntry in ruleEntries {
      let shortName = entry.label.targetName!
      if var existingRules = collidingRuleEntries[shortName] {
        existingRules.append(entry)
        collidingRuleEntries[shortName] = existingRules
      } else {
        collidingRuleEntries[shortName] = [entry]
      }
    }

    var namedRuleEntries = [String: RuleEntry]()
    for (name, entries) in collidingRuleEntries {
      guard entries.count > 1 else {
        namedRuleEntries[name] = entries.first!
        continue
      }

      for entry in entries {
        let fullName = entry.label.asFullPBXTargetName!
        namedRuleEntries[fullName] = entry
      }
    }

    return namedRuleEntries
  }

  /// Adds the given file targets to a versioned group.
  private func createReferencesForVersionedFileTargets(_ fileInfos: [BazelFileInfo]) -> [XCVersionGroup] {
    var groups = [String: XCVersionGroup]()

    for info in fileInfos {
      let path = info.fullPath as NSString
      let versionedGroupPath = path.deletingLastPathComponent
      let type = info.subPath.pbPathUTI ?? ""
      let versionedGroup = project.getOrCreateVersionGroupForPath(versionedGroupPath,
                                                                  versionGroupType: type)
      if groups[versionedGroupPath] == nil {
        groups[versionedGroupPath] = versionedGroup
      }
      let ref = versionedGroup.getOrCreateFileReferenceBySourceTree(.Group,
                                                                    path: path.lastPathComponent)
      ref.isInputFile = info.targetType == .sourceFile
    }

    for (sourcePath, group) in groups {
      setCurrentVersionForXCVersionGroup(group, atPath: sourcePath)
    }
    return Array(groups.values)
  }

  // Attempt to read the .xccurrentversion plists in the xcdatamodeld's and sync up the
  // currentVersion in the XCVersionGroup instances. Failure to specify the currentVersion will
  // result in Xcode picking an arbitrary version.
  private func setCurrentVersionForXCVersionGroup(_ group: XCVersionGroup,
                                                  atPath sourcePath: String) {

    let versionedBundleURL = workspaceRootURL.appendingPathComponent(sourcePath,
                                                                     isDirectory: true)
    let currentVersionPlistURL = versionedBundleURL.appendingPathComponent(".xccurrentversion",
                                                                           isDirectory: false)
    let path = currentVersionPlistURL.path
    guard let data = FileManager.default.contents(atPath: path) else {
      self.localizedMessageLogger.warning("LoadingXCCurrentVersionFailed",
                                          comment: "Message to show when loading a .xccurrentversion file fails.",
                                          values: group.name, "Version file at '\(path)' could not be read")
      return
    }

    do {
      let plist = try PropertyListSerialization.propertyList(from: data,
                                                                       options: PropertyListSerialization.MutabilityOptions(),
                                                                       format: nil) as! [String: AnyObject]
      if let currentVersion = plist["_XCCurrentVersionName"] as? String {
        if !group.setCurrentVersionByName(currentVersion) {
          self.localizedMessageLogger.warning("LoadingXCCurrentVersionFailed",
                                              comment: "Message to show when loading a .xccurrentversion file fails.",
                                              values: group.name, "Version '\(currentVersion)' specified by file at '\(path)' was not found")
        }
      }
    } catch let e as NSError {
      self.localizedMessageLogger.warning("LoadingXCCurrentVersionFailed",
                                          comment: "Message to show when loading a .xccurrentversion file fails.",
                                          values: group.name, "Version file at '\(path)' is invalid: \(e)")
    } catch {
      self.localizedMessageLogger.warning("LoadingXCCurrentVersionFailed",
                                          comment: "Message to show when loading a .xccurrentversion file fails.",
                                          values: group.name, "Version file at '\(path)' is invalid.")
    }
  }

  // Adds XCBuildConfigurations to the given indexer PBXTarget.
  // Note that preprocessorDefines is expected to be a pre-quoted set of defines (e.g., if "key" has
  // spaces it would be the string: key="value with spaces").
  private func addConfigsForIndexingTarget(_ target: PBXTarget, data: IndexerData) {

    var buildSettings = options.buildSettingsForTarget(target.name)
    buildSettings["PRODUCT_NAME"] = target.productName!

    if let pchFile = data.pchFile {
      buildSettings["GCC_PREFIX_HEADER"] = PBXTargetGenerator.projectRefForBazelFileInfo(pchFile)
    }

    var allOtherCFlags = data.otherCFlags
    if !data.preprocessorDefines.isEmpty {
      allOtherCFlags.append(contentsOf: data.preprocessorDefines.sorted().map({"-D\($0)"}))
    }

    if !allOtherCFlags.isEmpty {
      buildSettings["OTHER_CFLAGS"] = allOtherCFlags.joined(separator: " ")
    }

    if let bridgingHeader = data.bridgingHeader {
      buildSettings["SWIFT_OBJC_BRIDGING_HEADER"] = PBXTargetGenerator.projectRefForBazelFileInfo(bridgingHeader)
    }

    if data.enableModules {
      buildSettings["CLANG_ENABLE_MODULES"] = "YES"
    }

    if !data.includes.isEmpty {
      let includes = data.includes.joined(separator: " ")
      buildSettings["HEADER_SEARCH_PATHS"] = "$(inherited) \(includes) "
    }

    if !data.frameworkSearchPaths.isEmpty {
      buildSettings["FRAMEWORK_SEARCH_PATHS"] = "$(inherited) " + data.frameworkSearchPaths.joined(separator: " ")
    }

    if !data.swiftIncludePaths.isEmpty {
      let paths = data.swiftIncludePaths.joined(separator: " ")
      buildSettings["SWIFT_INCLUDE_PATHS"] = "$(inherited) \(paths)"
    }

    if !data.otherSwiftFlags.isEmpty {
      buildSettings["OTHER_SWIFT_FLAGS"] = "$(inherited) " + data.otherSwiftFlags.joined(separator: " ")
    }

    if let iPhoneOSDeploymentTarget = data.iPhoneOSDeploymentTarget {
      buildSettings["IPHONEOS_DEPLOYMENT_TARGET"] = iPhoneOSDeploymentTarget
    }

    if let macOSDeploymentTarget = data.macOSDeploymentTarget {
      buildSettings["MACOSX_DEPLOYMENT_TARGET"] = macOSDeploymentTarget
    }

    if let tvOSDeploymentTarget = data.tvOSDeploymentTarget {
      buildSettings["TVOS_DEPLOYMENT_TARGET"] = tvOSDeploymentTarget
    }

    if let watchOSDeploymentTarget = data.watchOSDeploymentTarget {
      buildSettings["WATCHOS_DEPLOYMENT_TARGET"] = watchOSDeploymentTarget
    }

    // Force the indexers to target the x86_64 simulator. This minimizes issues triggered by
    // Xcode's use of SourceKit to parse Swift-based code. Specifically, Xcode appears to use the
    // first ARCHS value that also appears in VALID_ARCHS when attempting to process swiftmodule's
    // during Live issues parsing.
    // Anecdotally it would appear that users target 64-bit simulators more often than armv7 devices
    // (the first architecture in Xcode 8's default value), so this change increases the chance that
    // the LI parser is able to find appropriate swiftmodule artifacts generated by the Bazel build.
    buildSettings["ARCHS"] = "x86_64"

    let sdkroot: String
    switch (target as? PBXNativeTarget)?.productType {
      case .Watch2App?, .Watch2Extension?:
        sdkroot = "watchsimulator"
      default:
        sdkroot = "iphonesimulator"
    }

    buildSettings["SDKROOT"] = sdkroot
    buildSettings["VALID_ARCHS"] = "x86_64"

    createBuildConfigurationsForList(target.buildConfigurationList,
                                     buildSettings: buildSettings,
                                     indexerSettingsOnly: true)
  }

  // Updates the build settings and optionally adds a "Compile sources" phase for the given test
  // bundle target.
  private func updateTestTarget(_ target: PBXTarget,
                                withLinkageToHostTarget hostTargetLabel: BuildLabel,
                                ruleEntry: RuleEntry,
                                ruleEntryMap: [BuildLabel: RuleEntry]) {
    guard let hostTarget = projectTargetForLabel(hostTargetLabel) as? PBXNativeTarget else {
      // If the user did not choose to include the host target it won't be available so the linkage
      // can be skipped, but the test won't be runnable in Xcode.
      localizedMessageLogger.warning("MissingTestHost",
                                     comment: "Warning to show when a user has selected an XCTest but not its host application.",
                                     values: ruleEntry.label.value, hostTargetLabel.value)
      return
    }

    project.linkTestTarget(target, toHostTarget: hostTarget)

    // Attempt to update the build configs for the target to include BUNDLE_LOADER and TEST_HOST
    // values, linking the test target to its host.
    if let hostProduct = hostTarget.productReference?.path,
           let hostProductName = hostTarget.productName {
      let testSettings: [String: String]
      if ruleEntry.pbxTargetType == .UIUnitTest {
        testSettings = [
          "TEST_TARGET_NAME": hostProductName,
          "TULSI_TEST_RUNNER_ONLY": "YES",
        ]
      } else {
        testSettings = [
          "BUNDLE_LOADER": "$(TEST_HOST)",
          "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(hostProduct)/\(hostProductName)",
          "TULSI_TEST_RUNNER_ONLY": "YES",
        ]
      }

      // Inherit the resolved values from the indexer.
      let indexerName = PBXTargetGenerator.indexerNameForTargetName(ruleEntry.label.targetName!,
                                                                    hash: ruleEntry.label.hashValue)
      let indexerTarget = indexerTargetByName[indexerName]
      updateMissingBuildConfigurationsForList(target.buildConfigurationList,
                                              withBuildSettings: testSettings,
                                              inheritingFromConfigurationList: indexerTarget?.buildConfigurationList,
                                              suppressingBuildSettings: ["ARCHS", "VALID_ARCHS"])
    }

    let (testSourceFileInfos, testNonArcSourceFileInfos, containsSwift) =
        testSourceFiles(forRuleEntry: ruleEntry, ruleEntryMap: ruleEntryMap)

    // For the Swift dummy files phase to work, it has to be placed before the Compile Sources build
    // phase.
    if containsSwift {
      let testBuildPhase = createGenerateSwiftDummyFilesTestBuildPhase()
      target.buildPhases.append(testBuildPhase)
    }
    if !testSourceFileInfos.isEmpty || !testNonArcSourceFileInfos.isEmpty {
      var fileReferences = generateFileReferencesForFileInfos(testSourceFileInfos)
      let (nonARCFiles, nonARCSettings) = generateFileReferencesAndSettingsForNonARCFileInfos(testNonArcSourceFileInfos)
      fileReferences.append(contentsOf: nonARCFiles)
      let buildPhase = createBuildPhaseForReferences(fileReferences,
                                                     withPerFileSettings: nonARCSettings)
      target.buildPhases.append(buildPhase)
    }
  }

  // Returns a tuple containing the sources and non-ARC sources for a ruleEntry of a test rule (e.g.
  // apple_unit_test) and a boolean indicating whether the test sources include Swift files.
  private func testSourceFiles(forRuleEntry ruleEntry: RuleEntry,
                               ruleEntryMap: [BuildLabel: RuleEntry]) -> ([BazelFileInfo], [BazelFileInfo], Bool) {
    // If this target doesn't have a test_bundle attribute, it must be an ios_test target, since
    // the test_bundle attribute is required only for apple_unit_test and apple_ui_test. For
    // ios_test, we return its sources directly.
    guard let testBundleLabelString = ruleEntry.attributes[RuleEntry.Attribute.test_bundle] as? String else {
      return (ruleEntry.sourceFiles, ruleEntry.nonARCSourceFiles, false)
    }

    // Traverse the apple_unit_test -> *_test_bundle -> apple_binary graph in order to get to the
    // binary's direct dependencies. If at any point the expected graph is broken, just return empty
    // sources.
    guard let testBundle = ruleEntryMap[BuildLabel(testBundleLabelString)],
        let testBundleBinaryLabelString = testBundle.attributes[RuleEntry.Attribute.binary] as? String,
        let testBundleBinary = ruleEntryMap[BuildLabel(testBundleBinaryLabelString)] else {
      return ([], [], false)
    }

    var sourceFiles = [BazelFileInfo]()
    var nonARCSourceFiles = [BazelFileInfo]()
    var containsSwift = false

    // Once we have the binary's direct dependencies, gather all the possible sources of those
    // targets and return them.
    for dependency in testBundleBinary.dependencies {
      guard let dependencyTarget = ruleEntryMap[BuildLabel(dependency)] else {
        continue
      }
      sourceFiles.append(contentsOf: dependencyTarget.sourceFiles)
      nonARCSourceFiles.append(contentsOf: dependencyTarget.nonARCSourceFiles)
      containsSwift = containsSwift || dependencyTarget.type == "swift_library"
    }

    return (sourceFiles, nonARCSourceFiles, containsSwift)
  }

  // Resolves a BuildLabel to an existing PBXTarget, handling target name collisions.
  private func projectTargetForLabel(_ label: BuildLabel) -> PBXTarget? {
    guard let targetName = label.targetName else { return nil }
    if let target = project.targetByName[targetName] {
      return target
    }

    guard let fullTargetName = label.asFullPBXTargetName else { return nil }
    return project.targetByName[fullTargetName]
  }

  // Adds a dummy build configuration to the given list based off of the Debug config that is
  // used to effectively disable compilation when running XCTests by converting each compile call
  // into a "clang -help" invocation.
  private func addTestRunnerBuildConfigurationToBuildConfigurationList(_ list: XCConfigurationList) {

    func createTestConfigNamed(_ testConfigName: String,
                               forBaseConfigNamed configurationName: String) {
      let baseConfig = list.getOrCreateBuildConfiguration(configurationName)
      let config = list.getOrCreateBuildConfiguration(testConfigName)

      var runTestTargetBuildSettings = baseConfig.buildSettings
      // Prevent compilation invocations from actually compiling ObjC, C and Swift files.
      runTestTargetBuildSettings["OTHER_CFLAGS"] = "-help"
      runTestTargetBuildSettings["OTHER_SWIFT_FLAGS"] = "-help"
      // Prevents linker invocations from attempting to use the .o files which were never generated
      // due to compilation being turned into nop's.
      runTestTargetBuildSettings["OTHER_LDFLAGS"] = "-help"

      // Force the output of the -emit-objc-header flag to a known value. This should be kept in
      // sync with the RunScript build phase created in createGenerateSwiftDummyFilesTestBuildPhase.
      runTestTargetBuildSettings["SWIFT_OBJC_INTERFACE_HEADER_NAME"] = "$(PRODUCT_NAME).h"

      // Disable the generation of ObjC header files from Swift for test targets.
      runTestTargetBuildSettings["SWIFT_INSTALL_OBJC_HEADER"] = "NO"

      // Prevent Xcode from attempting to create a fat binary with lipo from artifacts that were
      // never generated by the linker nop's.
      runTestTargetBuildSettings["ONLY_ACTIVE_ARCH"] = "YES"

      // Wipe out settings that are not useful for test runners
      // These do nothing and can cause issues due to exceeding environment limits:
      runTestTargetBuildSettings["FRAMEWORK_SEARCH_PATHS"] = ""
      runTestTargetBuildSettings["HEADER_SEARCH_PATHS"] = ""

      config.buildSettings = runTestTargetBuildSettings
    }

    for (testConfigName, configName) in PBXTargetGenerator.testRunnerEnabledBuildConfigNames {
      createTestConfigNamed(testConfigName, forBaseConfigNamed: configName)
    }
  }

  private func createBuildConfigurationsForList(_ buildConfigurationList: XCConfigurationList,
                                                buildSettings: Dictionary<String, String>,
                                                indexerSettingsOnly: Bool = false) {
    func addPreprocessorDefine(_ define: String, toConfig config: XCBuildConfiguration) {
      if let existingDefinitions = config.buildSettings["GCC_PREPROCESSOR_DEFINITIONS"] {
        // NOTE(abaire): Technically this should probably check first to see if "define" has been
        //               set but in the foreseeable usage it's unlikely that this if condition would
        //               ever trigger at all.
        config.buildSettings["GCC_PREPROCESSOR_DEFINITIONS"] = existingDefinitions + " \(define)"
      } else {
        config.buildSettings["GCC_PREPROCESSOR_DEFINITIONS"] = define
      }
    }

    for configName in PBXTargetGenerator.buildConfigNames {
      let config = buildConfigurationList.getOrCreateBuildConfiguration(configName)
      config.buildSettings = buildSettings

      // Insert any defines that are injected by Bazel's ObjcConfiguration.
      // TODO(abaire): Grab these in the aspect instead of hardcoding them here.
      //               Note that doing this would also require per-config aspect passes.
      if configName == "Debug" {
        addPreprocessorDefine("DEBUG=1", toConfig: config)
      } else if configName == "Release" {
        addPreprocessorDefine("NDEBUG=1", toConfig: config)

        if !indexerSettingsOnly {
          // Enable dSYM generation for release builds.
          config.buildSettings["TULSI_USE_DSYM"] = "YES"
        }
      }
    }
  }

  private func updateMissingBuildConfigurationsForList(_ buildConfigurationList: XCConfigurationList,
                                                       withBuildSettings newSettings: Dictionary<String, String>,
                                                       inheritingFromConfigurationList baseConfigurationList: XCConfigurationList? = nil,
                                                       suppressingBuildSettings suppressedKeys: Set<String> = []) {
    func mergeDictionary(_ old: inout [String: String],
                         withContentsOfDictionary new: [String: String]) {
      for (key, value) in new {
        if let _ = old[key] { continue }
        if suppressedKeys.contains(key) { continue }
        old.updateValue(value, forKey: key)
      }
    }

    for configName in PBXTargetGenerator.buildConfigNames {
      let config = buildConfigurationList.getOrCreateBuildConfiguration(configName)
      mergeDictionary(&config.buildSettings, withContentsOfDictionary: newSettings)

      if let baseSettings = baseConfigurationList?.getBuildConfiguration(configName)?.buildSettings {
        mergeDictionary(&config.buildSettings, withContentsOfDictionary: baseSettings)
      }
    }

    for (testRunnerConfigName, configName) in PBXTargetGenerator.testRunnerEnabledBuildConfigNames {
      let config = buildConfigurationList.getOrCreateBuildConfiguration(testRunnerConfigName)
      mergeDictionary(&config.buildSettings, withContentsOfDictionary: newSettings)

      if let baseSettings = baseConfigurationList?.getBuildConfiguration(testRunnerConfigName)?.buildSettings {
        mergeDictionary(&config.buildSettings, withContentsOfDictionary: baseSettings)
      } else if let baseSettings = baseConfigurationList?.getBuildConfiguration(configName)?.buildSettings {
        // Fall back to the base config name if the base configuration list doesn't support a given
        // test runner.
        mergeDictionary(&config.buildSettings, withContentsOfDictionary: baseSettings)
      }
    }
  }

  static func indexerNameForTargetName(_ targetName: String, hash: Int) -> String {
    let normalizedTargetName: String
    if targetName.characters.count > MaxIndexerNameLength {
      let endIndex = targetName.characters.index(targetName.startIndex, offsetBy: MaxIndexerNameLength - 4)
      normalizedTargetName = targetName.substring(to: endIndex) + "_etc"
    } else {
      normalizedTargetName = targetName
    }
    return String(format: "\(IndexerTargetPrefix)\(normalizedTargetName)_%08X", hash)
  }

  // Creates a PBXSourcesBuildPhase with the given references, optionally applying the given
  // per-file settings to each.
  private func createBuildPhaseForReferences(_ refs: [PBXReference],
                                             withPerFileSettings settings: [PBXFileReference: [String: String]]? = nil) -> PBXSourcesBuildPhase {
    let buildPhase = PBXSourcesBuildPhase()

    for ref in refs {
      if let ref = ref as? PBXFileReference {
        // Do not add header files to the build phase.
        guard let fileUTI = ref.uti, fileUTI.hasPrefix("sourcecode.") && !fileUTI.hasSuffix(".h") else {
          continue
        }
        buildPhase.files.append(PBXBuildFile(fileRef: ref, settings: settings?[ref]))
      } else {
        buildPhase.files.append(PBXBuildFile(fileRef: ref))
      }

    }
    return buildPhase
  }

  /// Creates a PBXNativeTarget for the given rule entry, returning it and any intermediate build
  /// artifacts.
  private func createBuildTargetForRuleEntry(_ entry: RuleEntry,
                                             named name: String,
                                             ruleEntryMap: [BuildLabel: RuleEntry]) throws -> (PBXNativeTarget, [String]) {
    guard let pbxTargetType = entry.pbxTargetType else {
      throw ProjectSerializationError.unsupportedTargetType(entry.type)
    }
    let target = project.createNativeTarget(name, targetType: pbxTargetType)

    for f in entry.secondaryArtifacts {
      project.createProductReference(f.fullPath)
    }

    var buildSettings = options.buildSettingsForTarget(name)
    buildSettings["TULSI_BUILD_PATH"] = entry.label.packageName!

    buildSettings["PRODUCT_NAME"] = name
    if let bundleID = entry.bundleID {
      buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] = bundleID
    }
    if let sdkRoot = entry.XcodeSDKRoot {
      buildSettings["SDKROOT"] = sdkRoot
    }

    // An invalid launch image is set in order to suppress Xcode's warning about missing default
    // launch images.
    buildSettings["ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME"] = "Stub Launch Image"
    buildSettings["INFOPLIST_FILE"] = stubInfoPlistPaths.stubPlist(entry)

    if let iPhoneOSDeploymentTarget = entry.iPhoneOSDeploymentTarget {
      buildSettings["IPHONEOS_DEPLOYMENT_TARGET"] = iPhoneOSDeploymentTarget
    }

    if let macOSDeploymentTarget = entry.macOSDeploymentTarget {
      buildSettings["MACOSX_DEPLOYMENT_TARGET"] = macOSDeploymentTarget
    }

    if let tvOSDeploymentTarget = entry.tvOSDeploymentTarget {
      buildSettings["TVOS_DEPLOYMENT_TARGET"] = tvOSDeploymentTarget
    }

    if let watchOSDeploymentTarget = entry.watchOSDeploymentTarget {
      buildSettings["WATCHOS_DEPLOYMENT_TARGET"] = watchOSDeploymentTarget
    }

    // watchOS1 apps require TARGETED_DEVICE_FAMILY to be overridden as they are a specialization of
    // an iOS target rather than a true standalone (like watchOS2 and later).
    if pbxTargetType == .Watch1App {
      buildSettings["TARGETED_DEVICE_FAMILY"] = "4"
      buildSettings["TARGETED_DEVICE_FAMILY[sdk=iphonesimulator*]"] = "1,4"
    }

    // Disable dSYM generation in general, unless the target has Swift dependencies. dSYM files are
    // necessary for debugging Swift targets in Xcode 8; at some point this should be able to be
    // removed, but requires changes to LLDB.
    let dSYMEnabled = entry.attributes[.has_swift_dependency] as? Bool ?? false
    buildSettings["TULSI_USE_DSYM"] = dSYMEnabled ? "YES" : "NO"
    let intermediateArtifacts: [String]
    if !dSYMEnabled {
      // For targets that will not generate dSYMs, the set of intermediate libraries generated for
      // dependencies is provided so that downstream utilities may locate them (e.g., to patch DWARF
      // symbols).
      intermediateArtifacts =
          entry.discoverIntermediateArtifacts(ruleEntryMap).flatMap({ $0.fullPath }).sorted()
    } else {
      intermediateArtifacts = []
    }

    // Disable Xcode's attempts at generating dSYM bundles as it conflicts with the operation of the
    // special test runner build configurations (which have associated sources but don't actually
    // compile anything).
    buildSettings["DEBUG_INFORMATION_FORMAT"] = "dwarf"

    // The following settings are simply passed through the environment for use by build scripts.
    buildSettings["BAZEL_TARGET"] = entry.label.value
    buildSettings["BAZEL_TARGET_TYPE"] = entry.type

    // TODO(abaire): Remove this hackaround when Bazel generates dSYMs for ios_applications.
    // The build script uses the binary label to find and move the dSYM associated with an
    // ios_application rule. In the future, Bazel should generate dSYMs directly for ios_application
    // rules, at which point this may be removed.
    if let binaryLabel = entry.attributes[.binary] as? String {
      buildSettings["BAZEL_BINARY_TARGET"] = binaryLabel
      let buildLabel = BuildLabel(binaryLabel)
      let binaryPackage = buildLabel.packageName!
      let binaryTarget = buildLabel.targetName!
      let binaryBundle = pbxTargetType.productName(binaryTarget)
      let dSYMPath =  "\(binaryPackage)/\(binaryBundle).dSYM"
      buildSettings["BAZEL_BINARY_DSYM"] = dSYMPath
    }

    createBuildConfigurationsForList(target.buildConfigurationList, buildSettings: buildSettings)
    addTestRunnerBuildConfigurationToBuildConfigurationList(target.buildConfigurationList)

    if let buildPhase = createBuildPhaseForRuleEntry(entry) {
      target.buildPhases.append(buildPhase)
    }

    if let legacyTarget = bazelCleanScriptTarget {
      target.createDependencyOn(legacyTarget,
                                proxyType: PBXContainerItemProxy.ProxyType.targetReference,
                                inProject: project,
                                first: true)
    }

    return (target, intermediateArtifacts)
  }

  private func createGenerateSwiftDummyFilesTestBuildPhase() -> PBXShellScriptBuildPhase {
    let shellScript =
        "# Script to generate specific Swift files Xcode expects when running tests.\n" +
        "set -eu\n" +
        "ARCH_ARRAY=($ARCHS)\n" +
        "SUFFIXES=(swiftdoc swiftmodule h)\n" +
        "for ARCH in \"${ARCH_ARRAY[@]}\"\n" +
        "do\n" +
        "  for SUFFIX in \"${SUFFIXES[@]}\"\n" +
        "  do\n" +
        "    touch \"$OBJECT_FILE_DIR_normal/$ARCH/$PRODUCT_NAME.$SUFFIX\"\n" +
        "  done\n" +
        "done\n"

    let buildPhase = PBXShellScriptBuildPhase(shellScript: shellScript, shellPath: "/bin/bash")
    buildPhase.showEnvVarsInLog = true
    buildPhase.mnemonic = "SwiftDummy"
    return buildPhase
  }

  private func createBuildPhaseForRuleEntry(_ entry: RuleEntry) -> PBXShellScriptBuildPhase? {
    let buildLabel = entry.label.value
    let commandLine = buildScriptCommandlineForBuildLabels(buildLabel,
                                                           withOptionsForTargetLabel: entry.label)
    let workingDirectory = PBXTargetGenerator.workingDirectoryForPBXGroup(project.mainGroup)
    let changeDirectoryAction: String
    if workingDirectory.isEmpty {
      changeDirectoryAction = ""
    } else {
      changeDirectoryAction = "cd \"\(workingDirectory)\""
    }
    let shellScript = "set -e\n" +
        "\(changeDirectoryAction)\n" +
        "exec \(commandLine) --install_generated_artifacts"

    let buildPhase = PBXShellScriptBuildPhase(shellScript: shellScript, shellPath: "/bin/bash")
    buildPhase.showEnvVarsInLog = true
    buildPhase.mnemonic = "BazelBuild"
    return buildPhase
  }

  /// Constructs a commandline string that will invoke the bazel build script to generate the given
  /// buildLabels (a space-separated set of Bazel target labels) with user options set for the given
  /// optionsTarget.
  private func buildScriptCommandlineForBuildLabels(_ buildLabels: String,
                                                    withOptionsForTargetLabel target: BuildLabel) -> String {
    var commandLine = "\"\(buildScriptPath)\" " +
        "\(buildLabels) " +
        "--bazel \"\(bazelURL.path)\" " +
        "--bazel_bin_path \"\(bazelBinPath)\" " +
        "--verbose "

    func addPerConfigValuesForOptions(_ optionKeys: [TulsiOptionKey],
                                      additionalFlags: String = "",
                                      optionFlag: String) {
      // Get the value for each config and test to see if they are all identical and may be
      // collapsed.
      var configValues = [TulsiOptionKey: String?]()
      var firstValue: String? = nil
      var valuesDiffer = false
      for key in optionKeys {
        let value = options[key, target.value]
        if configValues.isEmpty {
          firstValue = value
        } else if value != firstValue {
          valuesDiffer = true
        }
        configValues[key] = value
      }

      if !valuesDiffer {
        // Return early if nothing was set.
        guard let concreteValue = firstValue else { return }
        commandLine += "\(optionFlag) \(concreteValue) "
        if !additionalFlags.isEmpty {
          commandLine += "\(additionalFlags) "
        }
        commandLine += "-- "

        return
      }

      // Emit a filtered option (--optionName[configName]) for each config.
      for (optionKey, value) in configValues {
        guard let concreteValue = value else { continue }
        let rawName = optionKey.rawValue
        var configKey: String?
        for key in PBXTargetGenerator.buildConfigNames {
          if rawName.hasSuffix(key) {
            configKey = key
            break
          }
        }
        if configKey == nil {
          assertionFailure("Failed to map option key \(optionKey) to a build config.")
          configKey = "Debug"
        }
        commandLine += "\(optionFlag)[\(configKey!)] \(concreteValue) "
        commandLine += additionalFlags.isEmpty ? "-- " : "\(additionalFlags) -- "
      }
    }

    let additionalFlags: String
    if let shouldContinueBuildingAfterError = options[.BazelContinueBuildingAfterError].commonValueAsBool,
        shouldContinueBuildingAfterError {
      additionalFlags = "--keep_going"
    } else {
      additionalFlags = ""
    }

    addPerConfigValuesForOptions([.BazelBuildOptionsDebug,
                                  .BazelBuildOptionsRelease,
                                 ],
                                 additionalFlags: additionalFlags,
                                 optionFlag: "--bazel_options")

    addPerConfigValuesForOptions([.BazelBuildStartupOptionsDebug,
                                  .BazelBuildStartupOptionsRelease
                                 ],
                                 optionFlag: "--bazel_startup_options")

    return commandLine
  }
}
