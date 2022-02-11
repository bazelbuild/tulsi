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

/// Provides a set of project paths to stub Info.plist files to be used by
/// generated targets.
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

    case .MessagesExtension:
      fallthrough
    case .MessagesStickerPackExtension:
      fallthrough
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

/// Provides a set of project paths to stub binary files to use in the generated
/// Xcode project.
struct StubBinaryPaths {
  let clang: String
  let swiftc: String
  let ld: String
}

/// Defines an object that can populate a PBXProject based on RuleEntry's.
protocol PBXTargetGeneratorProtocol: AnyObject {
  static func getRunTestTargetBuildConfigPrefix() -> String

  static func workingDirectoryForPBXGroup(_ group: PBXGroup) -> String

  /// Returns a new PBXGroup instance appropriate for use as a top level project group.
  static func mainGroupForOutputFolder(_ outputFolderURL: URL, workspaceRootURL: URL) -> PBXGroup

  init(bazelPath: String,
       bazelBinPath: String,
       project: PBXProject,
       buildScriptPath: String,
       stubInfoPlistPaths: StubInfoPlistPaths,
       stubBinaryPaths: StubBinaryPaths,
       tulsiVersion: String,
       options: TulsiOptionSet,
       localizedMessageLogger: LocalizedMessageLogger,
       workspaceRootURL: URL,
       suppressCompilerDefines: Bool)

  /// Generates file references for the given file paths in the associated project without adding
  /// them to an indexer target. The paths must be relative to the workspace root. If pathFilters is
  /// non-nil, paths that do not match an entry in the pathFilters set will be omitted.
  func generateFileReferencesForFilePaths(_ paths: [String], pathFilters: Set<String>?)

  /// Registers the given Bazel rule and its transitive dependencies for inclusion by the Xcode
  /// indexer, adding source files whose directories are present in pathFilters. The rule will
  /// only be processed if it hasn't already (and therefore isn't in processedEntries).
  /// - processedEntries: Map of RuleEntry to cumulative preprocessor framework search paths.
  func registerRuleEntryForIndexer(_ ruleEntry: RuleEntry,
                                   ruleEntryMap: RuleEntryMap,
                                   pathFilters: Set<String>,
                                   processedEntries: inout [RuleEntry: (NSOrderedSet)])

  /// Generates indexer targets for rules that were previously registered through
  /// registerRuleEntryForIndexer. This method may only be called once, after all rule entries have
  /// been registered.
  /// Returns a map of indexer targets, keyed by the name of the indexer.
  func generateIndexerTargets() -> [String: PBXTarget]

  /// Generates a legacy target that is added as a dependency of all build targets and invokes
  /// the given script. The build action may be accessed by the script via the ACTION environment
  /// variable.
  func generateBazelCleanTarget(_ scriptPath: String, workingDirectory: String,
                                startupOptions: [String])

  /// Generates project-level build configurations.
  func generateTopLevelBuildConfigurations(_ buildSettingOverrides: [String: String])

  /// Generates Xcode build targets that invoke Bazel for the given targets. For test-type rules,
  /// non-compiling source file linkages are created to facilitate indexing of XCTests.
  ///
  /// If `pathFilters` is nil, no path filtering is done for test sources (to keep legacy behavior
  /// for users who were depending upon it).
  ///
  /// Returns a mapping from build label to generated PBXNativeTarget.
  /// Throws if one of the RuleEntry instances is for an unsupported Bazel target type.
  func generateBuildTargetsForRuleEntries(
    _ entries: Set<RuleEntry>,
    ruleEntryMap: RuleEntryMap,
    pathFilters: Set<String>?
  ) throws -> [BuildLabel: PBXNativeTarget]
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
    case unsupportedTargetType(String, String)
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

  /// Symlink to the Bazel execution root inside .tulsi in the xcodeproj
  static let TulsiExecutionRootSymlinkPath = ".tulsi/tulsi-execution-root"
  // Old versions of Tulsi mis-referred to the execution root as the workspace.
  // We preserve the old symlink name for backwards compatibility. 
  static let TulsiExecutionRootSymlinkLegacyPath = ".tulsi/tulsi-workspace"


  /// Xcode variable name used to refer to the symlink to the Bazel execution root.
  static let BazelExecutionRootSymlinkVarName = "TULSI_EXECUTION_ROOT"
  // Old versions of Tulsi mis-referred to the execution root as the workspace.
  // We preserve the old build variable name for backwards compatibility. 
  static let BazelExecutionRootSymlinkLegacyVarName = "TULSI_BWRS"

  /// Symlink to the Bazel output base inside .tulsi in the xcodeproj
  static let TulsiOutputBaseSymlinkPath = ".tulsi/tulsi-output-base"

  /// Xcode variable name used to refer to the Bazel output base.
  static let BazelOutputBaseSymlinkVarName = "TULSI_OUTPUT_BASE"

  /// Path to the Bazel executable.
  let bazelPath: String

  /// Location of the bazel bin symlink, relative to the workspace root.
  let bazelBinPath: String
  private(set) lazy var bazelGenfilesPath: String = { [unowned self] in
    return self.bazelBinPath.replacingOccurrences(of: "-bin", with: "-genfiles")
  }()

  /// Previous path to the Tulsi generated outputs root. We remap any paths of this form to the
  /// new `tulsiIncludesPath` form automatically for convenience.
  static let legacyTulsiIncludesPath = "_tulsi-includes/x/x"

  /// The path to the Tulsi generated outputs root. For more information see tulsi_aspects.bzl
  static let tulsiIncludesPath = "bazel-tulsi-includes/x/x"

  /// Path prefix for files from external repositories.
  static let externalPrefix = "external/"

  let project: PBXProject
  let buildScriptPath: String
  let stubInfoPlistPaths: StubInfoPlistPaths
  let stubBinaryPaths: StubBinaryPaths
  let tulsiVersion: String
  let options: TulsiOptionSet
  let localizedMessageLogger: LocalizedMessageLogger
  let workspaceRootURL: URL
  let suppressCompilerDefines: Bool

  var bazelCleanScriptTarget: PBXLegacyTarget? = nil

  /// Stores data about a given RuleEntry to be used in order to generate Xcode indexer targets.
  private struct IndexerData {
    /// Provides information about the RuleEntry instances supported by an IndexerData.
    /// Specifically, NameInfoToken tuples provide the targetName, full target label hash, and
    /// potentially the target configuration in order to differentiate between rules with the
    /// same name but different paths and configurations.
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
    let resolvedDependencies: Set<RuleEntry>
    let preprocessorDefines: Set<String>
    let otherCFlags: [String]
    let otherSwiftFlags: [String]
    let includes: [String]
    let frameworkSearchPaths: [String]
    let swiftIncludePaths: [String]
    let deploymentTarget: DeploymentTarget
    let buildPhase: PBXSourcesBuildPhase
    let pchFile: BazelFileInfo?
    let bridgingHeader: BazelFileInfo?
    let enableModules: Bool

    /// Returns the deploymentTarget as a string for an indexerName.
    static func deploymentTargetLabel(_ deploymentTarget: DeploymentTarget) -> String {
      return String(format: "%@_min%@",
                    deploymentTarget.platform.rawValue,
                    deploymentTarget.osVersion)
    }

    /// Returns the deploymentTarget as a string for the indexerName.
    var deploymentTargetLabel: String {
      return IndexerData.deploymentTargetLabel(deploymentTarget)
    }

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
      return PBXTargetGenerator.indexerNameForTargetName(fullName,
                                                         hash: fullHash,
                                                         suffix: deploymentTargetLabel)
    }

    /// Returns an array of aliases for this indexer data. Each element is the full indexerName of
    /// an IndexerData instance that has been merged into this IndexerData.
    var supportedIndexingTargets: [String] {
      var supportedTargets = [indexerName]
      if indexerNameInfo.count > 1 {
        for token in indexerNameInfo {
          supportedTargets.append(PBXTargetGenerator.indexerNameForTargetName(token.targetName,
                                                                              hash: token.labelHash,
                                                                              suffix: deploymentTargetLabel))
        }
      }
      return supportedTargets
    }

    /// Returns an array of indexing target names that this indexer depends on.
    var indexerNamesForResolvedDependencies: [String] {
      let parentDeploymentTargetLabel = self.deploymentTargetLabel
      return resolvedDependencies.map() { entry in
        let deploymentTargetLabel: String
        if let deploymentTarget = entry.deploymentTarget {
          deploymentTargetLabel = IndexerData.deploymentTargetLabel(deploymentTarget)
        } else {
          deploymentTargetLabel = parentDeploymentTargetLabel
        }
        return PBXTargetGenerator.indexerNameForTargetName(entry.label.targetName!,
                                                           hash: entry.label.hashValue,
                                                           suffix: deploymentTargetLabel)
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
          deploymentTarget == other.deploymentTarget) {
        return false
      }

      return true
    }

    /// Returns a new IndexerData instance that is the result of merging this indexer with another.
    func merging(_ other: IndexerData) -> IndexerData {
      let newDependencies = dependencies.union(other.dependencies)
      let newResolvedDependencies = resolvedDependencies.union(other.resolvedDependencies)
      let newName = indexerNameInfo + other.indexerNameInfo
      let newBuildPhase = PBXSourcesBuildPhase()
      newBuildPhase.files = buildPhase.files + other.buildPhase.files

      return IndexerData(indexerNameInfo: newName,
                         dependencies: newDependencies,
                         resolvedDependencies: newResolvedDependencies,
                         preprocessorDefines: preprocessorDefines,
                         otherCFlags: otherCFlags,
                         otherSwiftFlags: otherSwiftFlags,
                         includes: includes,
                         frameworkSearchPaths: frameworkSearchPaths,
                         swiftIncludePaths: swiftIncludePaths,
                         deploymentTarget: deploymentTarget,
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
      let index = workspaceRoot.index(workspaceRoot.startIndex, offsetBy: slashTerminatedOutputFolder.count)
      let relativePath = String(workspaceRoot[index...])
      return PBXGroup(name: "mainGroup",
                      path: relativePath,
                      sourceTree: .SourceRoot,
                      parent: nil)
    }

    // If workspaceRoot contains outputFolder, return a relative group using .. to walk up to
    // workspaceRoot from outputFolder.
    if outputFolder.hasPrefix(slashTerminatedWorkspaceRoot) {
      let index = outputFolder.index(outputFolder.startIndex, offsetBy: slashTerminatedWorkspaceRoot.count + 1)
      let pathToWalkBackUp = String(outputFolder[index...]) as NSString
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
        return "$(\(BazelExecutionRootSymlinkVarName))/\(info.fullPath)"
    }
  }

  /// Returns the default Deployment Target (iOS 9). This is just a sensible default
  /// in the odd case that we didn't get a Deployment Target from the Aspect.
  private static func defaultDeploymentTarget() -> DeploymentTarget {
    return DeploymentTarget(platform: .ios, osVersion: "9.0")
  }

  /// Computed property to determine if USER_HEADER_SEARCH_PATHS should be set for Objective-C
  /// targets.
  var improvedImportAutocompletionFix: Bool {
    return options[.ImprovedImportAutocompletionFix].commonValueAsBool ?? true
  }

  init(bazelPath: String,
       bazelBinPath: String,
       project: PBXProject,
       buildScriptPath: String,
       stubInfoPlistPaths: StubInfoPlistPaths,
       stubBinaryPaths: StubBinaryPaths,
       tulsiVersion: String,
       options: TulsiOptionSet,
       localizedMessageLogger: LocalizedMessageLogger,
       workspaceRootURL: URL,
       suppressCompilerDefines: Bool = false) {
    self.bazelPath = bazelPath
    self.bazelBinPath = bazelBinPath
    self.project = project
    self.buildScriptPath = buildScriptPath
    self.stubInfoPlistPaths = stubInfoPlistPaths
    self.stubBinaryPaths = stubBinaryPaths
    self.tulsiVersion = tulsiVersion
    self.options = options
    self.localizedMessageLogger = localizedMessageLogger
    self.workspaceRootURL = workspaceRootURL
    self.suppressCompilerDefines = suppressCompilerDefines
  }

  func generateFileReferencesForFilePaths(_ paths: [String], pathFilters: Set<String>?) {
    if let pathFilters = pathFilters {
      let filteredPaths = paths.filter(pathFilterFunc(pathFilters))
      project.getOrCreateGroupsAndFileReferencesForPaths(filteredPaths)
    } else {
      project.getOrCreateGroupsAndFileReferencesForPaths(paths)
    }
  }

  /// Registers the given Bazel rule and its transitive dependencies for inclusion by the Xcode
  /// indexer, adding source files whose directories are present in pathFilters. The rule will
  /// only be processed if it hasn't already (and therefore isn't in processedEntries).
  /// - processedEntries: Map of RuleEntry to cumulative preprocessor framework search paths.
  func registerRuleEntryForIndexer(_ ruleEntry: RuleEntry,
                                   ruleEntryMap: RuleEntryMap,
                                   pathFilters: Set<String>,
                                   processedEntries: inout [RuleEntry: (NSOrderedSet)]) {
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

    // Recursively find all targets that are direct dependencies of test targets, and skip adding
    // indexers for them, because their sources will be added directly to the test target.
    var ruleEntryLabelsToSkipForIndexing = Set<BuildLabel>()
    func addTestDepsToSkipList(_ ruleEntry: RuleEntry) {
      if ruleEntry.pbxTargetType?.isTest ?? false {
        for dep in ruleEntry.dependencies {
          ruleEntryLabelsToSkipForIndexing.insert(dep)
          guard let depEntry = ruleEntryMap.ruleEntry(buildLabel: dep, depender: ruleEntry) else {
            localizedMessageLogger.warning("UnknownTargetRule",
                                           comment: "Failure to look up a Bazel target that was expected to be present. The target label is %1$@",
                                           values: dep.value)
            continue
          }
          addTestDepsToSkipList(depEntry)
        }
      }
    }
    addTestDepsToSkipList(ruleEntry)

    // TODO(b/63628175): Clean this nested method to also retrieve framework_dir and framework_file
    // from the ObjcProvider, for both static and dynamic frameworks.
    @discardableResult
    func generateIndexerTargetGraphForRuleEntry(_ ruleEntry: RuleEntry) -> (NSOrderedSet) {
      if let data = processedEntries[ruleEntry] {
        return data
      }
      let frameworkSearchPaths = NSMutableOrderedSet()

      defer {
        processedEntries[ruleEntry] = (frameworkSearchPaths)
      }

      var resolvedDependecies = [RuleEntry]()
      for dep in ruleEntry.dependencies {
        guard let depEntry = ruleEntryMap.ruleEntry(buildLabel: dep, depender: ruleEntry) else {
          localizedMessageLogger.warning("UnknownTargetRule",
                                         comment: "Failure to look up a Bazel target that was expected to be present. The target label is %1$@",
                                         values: dep.value)
          continue
        }

        resolvedDependecies.append(depEntry)
        let inheritedFrameworkSearchPaths = generateIndexerTargetGraphForRuleEntry(depEntry)
        frameworkSearchPaths.union(inheritedFrameworkSearchPaths)
      }
      var defines = Set<String>()
      if let ruleDefines = ruleEntry.objcDefines {
        defines.formUnion(ruleDefines)
      }

      if !suppressCompilerDefines,
         let ruleDefines = ruleEntry.attributes[.compiler_defines] as? [String], !ruleDefines.isEmpty {
        defines.formUnion(ruleDefines)
      }

      let includes = NSMutableOrderedSet()
      addIncludes(ruleEntry, toSet: includes)

      // Search path entries are added for all framework imports, regardless of whether the
      // framework bundles are allowed by the include filters. The search path excludes the bundle
      // itself.
      ruleEntry.frameworkImports.forEach() {
        let fullPath = $0.fullPath as NSString
        let rootedPath = "$(\(PBXTargetGenerator.BazelExecutionRootSymlinkVarName))/\(fullPath.deletingLastPathComponent)"
        frameworkSearchPaths.add(rootedPath)
      }
      let sourceFileInfos = ruleEntry.sourceFiles.filter(includeFileInProject)
      let nonARCSourceFileInfos = ruleEntry.nonARCSourceFiles.filter(includeFileInProject)
      let frameworkFileInfos = ruleEntry.frameworkImports.filter(includeFileInProject)
      let nonSourceVersionedFileInfos = ruleEntry.versionedNonSourceArtifacts.filter(includeFileInProject)

      for target in ruleEntry.normalNonSourceArtifacts.filter(includeFileInProject) {
        let path = target.fullPath
        let (_, ref) = project.createGroupsAndFileReferenceForPath(path, underGroup: project.mainGroup)
        ref.isInputFile = target.targetType == .sourceFile
      }

      // Indexer targets aren't needed:
      // - if the target is a filegroup (we generate an indexer for what references the filegroup).
      // - if the target has no source files (there's nothing to index!)
      // - if the target is a test bundle (we generate proper targets for these).
      // - if the target is a direct dependency of a test target (these sources are added directly to the test target).
      if (sourceFileInfos.isEmpty &&
          nonARCSourceFileInfos.isEmpty &&
          frameworkFileInfos.isEmpty &&
          nonSourceVersionedFileInfos.isEmpty)
        || ruleEntry.pbxTargetType?.isTest ?? false
        || ruleEntry.type == "filegroup"
        || ruleEntryLabelsToSkipForIndexing.contains(ruleEntry.label) {
        addBuildFileForRule(ruleEntry)
        return (frameworkSearchPaths)
      }

      var localPreprocessorDefines = defines
      let localIncludes = includes.mutableCopy() as! NSMutableOrderedSet
      let otherCFlags = NSMutableArray()
      let swiftIncludePaths = NSMutableOrderedSet()
      let otherSwiftFlags = NSMutableArray()
      addLocalSettings(ruleEntry, localDefines: &localPreprocessorDefines, localIncludes: localIncludes,
                       otherCFlags: otherCFlags, swiftIncludePaths: swiftIncludePaths, otherSwiftFlags: otherSwiftFlags)

      addOtherSwiftFlags(ruleEntry, toArray: otherSwiftFlags)
      addSwiftIncludes(ruleEntry, toSet: swiftIncludePaths)

      let pchFile = BazelFileInfo(info: ruleEntry.attributes[.pch])
      if let pchFile = pchFile, includeFileInProject(pchFile) {
        addFileReference(pchFile)
      }

      let bridgingHeader = BazelFileInfo(info: ruleEntry.attributes[.bridging_header])
      if let bridgingHeader = bridgingHeader, includeFileInProject(bridgingHeader) {
        addFileReference(bridgingHeader)
      }
      let enableModules = (ruleEntry.attributes[.enable_modules] as? Bool) == true

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
        let resolvedIncludes = localIncludes.array as! [String]

        let deploymentTarget: DeploymentTarget
        if let ruleDeploymentTarget = ruleEntry.deploymentTarget {
          deploymentTarget = ruleDeploymentTarget
        } else {
          deploymentTarget = PBXTargetGenerator.defaultDeploymentTarget()
          localizedMessageLogger.warning("NoDeploymentTarget",
                                         comment: "Rule Entry for %1$@ has no DeploymentTarget set. Defaulting to iOS 9.",
                                         values: ruleEntry.label.value)
        }

        let indexerData = IndexerData(indexerNameInfo: [IndexerData.NameInfoToken(ruleEntry: ruleEntry)],
                                      dependencies: ruleEntry.dependencies,
                                      resolvedDependencies: Set(resolvedDependecies),
                                      preprocessorDefines: localPreprocessorDefines,
                                      otherCFlags: otherCFlags as! [String],
                                      otherSwiftFlags: otherSwiftFlags as! [String],
                                      includes: resolvedIncludes,
                                      frameworkSearchPaths: frameworkSearchPaths.array as! [String],
                                      swiftIncludePaths: swiftIncludePaths.array as! [String],
                                      deploymentTarget: deploymentTarget,
                                      buildPhase: buildPhase,
                                      pchFile: pchFile,
                                      bridgingHeader: bridgingHeader,
                                      enableModules: enableModules)
        let isSwiftRule = ruleEntry.attributes[.has_swift_info] as? Bool ?? false
        if (isSwiftRule) {
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
      let indexingTarget = project.createNativeTarget(name,
                                                      deploymentTarget: nil,
                                                      targetType: indexerType,
                                                      isIndexerTarget: true)
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

        for depName in data.indexerNamesForResolvedDependencies {
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

  func generateBazelCleanTarget(_ scriptPath: String, workingDirectory: String = "",
                                startupOptions: [String] = []) {
    assert(bazelCleanScriptTarget == nil, "generateBazelCleanTarget may only be called once")

    let allArgs = [bazelPath, bazelBinPath] + startupOptions
    let buildArgs = allArgs.map { "\"\($0)\""}.joined(separator: " ")

    bazelCleanScriptTarget = project.createLegacyTarget(PBXTargetGenerator.BazelCleanTarget,
                                                        deploymentTarget: nil,
                                                        buildToolPath: "\(scriptPath)",
                                                        buildArguments: buildArgs,
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
    // This is required to disable code signing with the new build system.
    if !options.useLegacyBuildSystem {
      buildSettings["CODE_SIGNING_ALLOWED"] = "NO"
    }

    // Explicitly setting the FRAMEWORK_SEARCH_PATHS will allow Xcode to resolve references to the
    // XCTest framework when performing Live issues analysis.
    buildSettings["FRAMEWORK_SEARCH_PATHS"] = "$(PLATFORM_DIR)/Developer/Library/Frameworks";

    // Prevent Xcode from replacing the Swift StdLib dylibs that Bazel already packaged.
    buildSettings["DONT_RUN_SWIFT_STDLIB_TOOL"] = "YES"

    var sourceDirectory = PBXTargetGenerator.workingDirectoryForPBXGroup(project.mainGroup)
    if sourceDirectory.isEmpty {
      sourceDirectory = "$(SRCROOT)"
    }

    // A variable pointing to the true root is provided for scripts that may need it.
    buildSettings["\(PBXTargetGenerator.WorkspaceRootVarName)"] = sourceDirectory

    // Create variables wrapping symlinks created during builds.
    // The symlinks are located inside of the project package as opposed to relative to the workspace
    // so that it is using the same local file system as the project to maximize performance.
    // In some cases where the workspace was on a remote volume, jumping through the symlink on the
    // remote volume that pointed back to local disk was causing performance issues.
    buildSettings[PBXTargetGenerator.BazelExecutionRootSymlinkVarName] =
        "$(PROJECT_FILE_PATH)/\(PBXTargetGenerator.TulsiExecutionRootSymlinkPath)"
    buildSettings[PBXTargetGenerator.BazelExecutionRootSymlinkLegacyVarName] =
        "$(PROJECT_FILE_PATH)/\(PBXTargetGenerator.TulsiExecutionRootSymlinkPath)"
    buildSettings[PBXTargetGenerator.BazelOutputBaseSymlinkVarName] =
        "$(PROJECT_FILE_PATH)/\(PBXTargetGenerator.TulsiOutputBaseSymlinkPath)"

    buildSettings["TULSI_VERSION"] = tulsiVersion

    // Set default Python STDOUT encoding of scripts run by Xcode (such as bazel_build.py) to UTF-8.
    // Otherwise, this would be the Python 2 default of ASCII, causing various encoding errors when
    // handling UTF-8 output from Bazel BEP in bazel_build.py.
    buildSettings["PYTHONIOENCODING"] = "utf8"

    let searchPaths = ["$(\(PBXTargetGenerator.BazelExecutionRootSymlinkVarName))",
                       "$(\(PBXTargetGenerator.WorkspaceRootVarName))/\(bazelBinPath)",
                       "$(\(PBXTargetGenerator.WorkspaceRootVarName))/\(bazelGenfilesPath)",
                       "$(\(PBXTargetGenerator.BazelExecutionRootSymlinkVarName))/\(PBXTargetGenerator.tulsiIncludesPath)"
    ]
    // Ideally this would use USER_HEADER_SEARCH_PATHS but some code generation tools (e.g.,
    // protocol buffers) make use of system-style includes.
    buildSettings["HEADER_SEARCH_PATHS"] = searchPaths.joined(separator: " ")

    // Configure our binary stubs if we're targetting the new build system.
    if !options.useLegacyBuildSystem {
      buildSettings["CC"] = stubBinaryPaths.clang
      buildSettings["CXX"] = stubBinaryPaths.clang
      buildSettings["LD"] = stubBinaryPaths.ld
      buildSettings["LDPLUSPLUS"] = stubBinaryPaths.ld
      buildSettings["SWIFT_EXEC"] = stubBinaryPaths.swiftc
    }

    createBuildConfigurationsForList(project.buildConfigurationList, buildSettings: buildSettings)
    addTestRunnerBuildConfigurationToBuildConfigurationList(project.buildConfigurationList)
  }

  /// Generates build targets for the given rule entries.
  func generateBuildTargetsForRuleEntries(
    _ ruleEntries: Set<RuleEntry>,
    ruleEntryMap: RuleEntryMap,
    pathFilters: Set<String>?
  ) throws -> [BuildLabel: PBXNativeTarget] {
    let namedRuleEntries = generateUniqueNamesForRuleEntries(ruleEntries)

    let progressNotifier = ProgressNotifier(name: GeneratingBuildTargets,
                                            maxValue: namedRuleEntries.count)

    var testTargetLinkages = [(PBXNativeTarget, BuildLabel?, RuleEntry)]()
    var watchAppTargets = [String: (PBXNativeTarget, RuleEntry)]()
    var watchExtensionsByEntry = [RuleEntry: PBXNativeTarget]()
    var targetsByLabel = [BuildLabel: PBXNativeTarget]()

    for (name, entry) in namedRuleEntries {
      progressNotifier.incrementValue()
      let target = try createBuildTargetForRuleEntry(entry,
                                                     named: name,
                                                     ruleEntryMap: ruleEntryMap)
      targetsByLabel[entry.label] = target

      if let script = options[.PreBuildPhaseRunScript, entry.label.value] {
        let runScript = PBXShellScriptBuildPhase(
          shellScript: script,
          shellPath: "/bin/bash",
          name: "Pre-build Run Script")
        runScript.showEnvVarsInLog = true
        target.buildPhases.insert(runScript, at: 0)
      }

      if let script = options[.PostBuildPhaseRunScript, entry.label.value] {
        let runScript = PBXShellScriptBuildPhase(
          shellScript: script,
          shellPath: "/bin/bash",
          name: "Post-build Run Script")
        runScript.showEnvVarsInLog = true
        target.buildPhases.append(runScript)
      }

      if let hostLabelString = entry.attributes[.test_host] as? String {
        let hostLabel = BuildLabel(hostLabelString)
        testTargetLinkages.append((target, hostLabel, entry))
      } else if entry.pbxTargetType == .UnitTest {
        // If there is no host and it's a unit test, assume it doesn't need one, i.e. it's a
        // library based test.
        testTargetLinkages.append((target, nil, entry))
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
        if let extEntry = ruleEntryMap.ruleEntry(buildLabel: ext, depender: watchRuleEntry),
            extEntry.pbxTargetType == .Watch2Extension {
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
      let testHostTarget: PBXNativeTarget?
      if let hostTargetLabel = testHostLabel {
        testHostTarget = targetsByLabel[hostTargetLabel]
        if testHostTarget == nil {
          // If the user did not choose to include the host target it won't be available so the
          // linkage can be skipped. We will still force the generation of this test host target to
          // avoid issues when running tests as bundle targets in Xcode.
          localizedMessageLogger.warning("MissingTestHost",
                                         comment: "Warning to show when a user has selected an XCTest but not its host application.",
                                         values: entry.label.value, hostTargetLabel.value)
          continue
        }
      } else {
        testHostTarget = nil
      }
      updateTestTarget(testTarget,
                       withLinkageToHostTarget: testHostTarget,
                       ruleEntry: entry,
                       ruleEntryMap: ruleEntryMap,
                       pathFilters: pathFilters)
    }
    return targetsByLabel
  }

  // MARK: - Private methods

  /// Generates a filter function that may be used to verify that a path string is allowed by the
  /// given set of pathFilters.
  private func pathFilterFunc(_ pathFilters: Set<String>?) -> (String) -> Bool {
    guard let pathFilters = pathFilters else {
      return { (path: String) -> Bool in
        return true
      }
    }
    let recursiveFilters = Set<String>(pathFilters.filter({ $0.hasSuffix("/...") }).map() {
      let index = $0.index($0.endIndex, offsetBy: -3)
      return String($0[..<index])
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

  /// Find the longest common non-empty strict prefix for the given strings if there is one.
  private func longestCommonPrefix(_ strings: Set<String>, separator: Character) -> String {
    // Longest common prefix for 0 or 1 string(s) doesn't make sense.
    guard strings.count >= 2, var shortestString = strings.first else { return "" }
    for str in strings {
      guard str.count < shortestString.count else { continue }
      shortestString = str
    }

    guard !shortestString.isEmpty else { return "" }

    // Drop the last so we can only get a strict prefix.
    var components = shortestString.split(separator: separator).dropLast()
    var potentialPrefix = "\(components.joined(separator: "\(separator)"))\(separator)"

    for str in strings {
      while !components.isEmpty && !str.hasPrefix(potentialPrefix) {
        components = components.dropLast()
        potentialPrefix = "\(components.joined(separator: "\(separator)"))\(separator)"
      }
    }
    return potentialPrefix
  }

  /// Name the given `ruleEntries` using the `namer` function.
  ///
  /// `ruleEntries` must be mutually exclusive with the values in `named`. Intended use case:
  /// call this first with an initial set and `namer`, and then subsequent calls should use the
  /// results of the previous call (unnamed entries) with a different `namer`.
  ///
  /// Only unique names will be inserted into the `named` dictionary. If when naming a
  /// `RuleEntry`, the name is already in the `named` dictionary, the previously named
  /// `RuleEntry` will still be valid.
  ///
  /// Returns a `Set<RuleEntry>` representing the entries which still need to be named.
  private func uniqueNames(for ruleEntries: Set<RuleEntry>,
                           named: inout [String: RuleEntry],
                           namer: (_ ruleEntry: RuleEntry) -> String?
  ) -> Set<RuleEntry> {
    var unnamed = Set<RuleEntry>()

    // Group the entries by name.
    var ruleEntriesByName = [String: [RuleEntry]]()
    for entry in ruleEntries {
      guard let name = namer(entry) else {
        unnamed.insert(entry)
        continue
      }
      ruleEntriesByName[name, default: []].append(entry)
    }

    for (name, entries) in ruleEntriesByName {
      // Name already used or not unique.
      guard entries.count == 1 && named.index(forKey: name) == nil else {
        unnamed.formUnion(entries)
        continue
      }
      named[name] = entries.first!
    }
    return unnamed
  }

  /// Generate unique names for the given rule entries, using the bundle name when it is
  /// unique. Otherwise, falls back to a name based on the target label.
  private func generateUniqueNamesForRuleEntries(_ ruleEntries: Set<RuleEntry>) -> [String: RuleEntry] {
    var named = [String: RuleEntry]()
    // Try to name using the bundle names first, then the target name.
    var unnamed = self.uniqueNames(for: ruleEntries, named: &named) { $0.bundleName }
    unnamed = self.uniqueNames(for: unnamed, named: &named) {
      $0.label.targetName
    }

    // Continue only if we need to de-duplicate.
    guard !unnamed.isEmpty else {
      return named
    }

    // Special handling for the remaining unnamed entries - use their full target label.
    let conflictingFullNames = Set(unnamed.map {
      $0.label.asFullPBXTargetName!
    })

    // Try to strip out a common prefix if we can find one.
    let commonPrefix = self.longestCommonPrefix(conflictingFullNames, separator: "-")

    guard !commonPrefix.isEmpty else {
      for entry in unnamed {
        let fullName = entry.label.asFullPBXTargetName!
        named[fullName] = entry
      }
      return named
    }

    // Found a common prefix, we can strip it as long as we don't cause a new duplicate.
    let charsToDrop = commonPrefix.count
    for entry in unnamed {
      let fullName = entry.label.asFullPBXTargetName!
      let shortenedFullName = String(fullName.dropFirst(charsToDrop))
      guard !shortenedFullName.isEmpty && named.index(forKey: shortenedFullName) == nil else {
        named[fullName] = entry
        continue
      }
      named[shortenedFullName] = entry
    }

    return named
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
                                                                    path: path as String)
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
  // Note that preprocessorDefines may or may not contain values with spaces. If it does contain
  // spaces, the key will be escaped (e.g. -Dfoo bar becomes -D"foo bar").
  private func addConfigsForIndexingTarget(_ target: PBXTarget, data: IndexerData) {

    var buildSettings = options.buildSettingsForTarget(target.name)
    buildSettings["PRODUCT_NAME"] = target.productName!

    if let pchFile = data.pchFile {
      buildSettings["GCC_PREFIX_HEADER"] = PBXTargetGenerator.projectRefForBazelFileInfo(pchFile)
    }

    var allOtherCFlags = data.otherCFlags.filter { !$0.hasPrefix("-W") }
    // Escape the spaces in the defines by transforming -Dfoo bar into -D"foo bar".
    if !data.preprocessorDefines.isEmpty {
      allOtherCFlags.append(contentsOf: data.preprocessorDefines.sorted().map { define in
        // Need to quote all defines with spaces that are not yet quoted.
        if define.rangeOfCharacter(from: .whitespaces) != nil &&
            !((define.hasPrefix("\"") && define.hasSuffix("\"")) ||
              (define.hasPrefix("'") && define.hasSuffix("'"))) {
          return "-D\"\(define)\""
        }
        return "-D\(define)"
      })
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

    // Set USER_HEADER_SEARCH_PATHS for non-Swift (meaning static library) indexer targets if the
    // improved include/import setting is enabled.
    if self.improvedImportAutocompletionFix, let nativeTarget = target as? PBXNativeTarget,
       nativeTarget.productType == .StaticLibrary {
      buildSettings["USER_HEADER_SEARCH_PATHS"] = "$(\(PBXTargetGenerator.WorkspaceRootVarName))"
    }

    // Default the SDKROOT to the proper device SDK.
    // Previously, we would force the indexer targets to the x86_64 simulator. This caused indexing
    // to fail when building Swift for device, as the arm Swift modules would be discovered via
    // tulsi-includes but Xcode would only index for x86_64. Note that just setting this is not
    // enough; research has shown that Xcode needs a scheme for these indexer targets in order to
    // use the proper ARCH for indexing, so we also generate an `_idx_Scheme` containing all
    // indexer targets as build targets.
    let deploymentTarget = data.deploymentTarget
    let platform = deploymentTarget.platform
    buildSettings["SDKROOT"] = platform.deviceSDK
    buildSettings[platform.buildSettingsDeploymentTarget] = deploymentTarget.osVersion

    createBuildConfigurationsForList(target.buildConfigurationList,
                                     buildSettings: buildSettings,
                                     indexerSettingsOnly: true)
  }

  /// Updates the build settings and optionally adds a "Compile sources" phase for the given test
  /// bundle target.
  private func updateTestTarget(_ target: PBXNativeTarget,
                                withLinkageToHostTarget hostTarget: PBXNativeTarget?,
                                ruleEntry: RuleEntry,
                                ruleEntryMap: RuleEntryMap,
                                pathFilters: Set<String>?) {
    // If the test target has a test host, check that it was included in the Tulsi configuration.
    if let hostTarget = hostTarget {
      project.linkTestTarget(target, toHostTarget: hostTarget)
    }
    updateTestTargetIndexer(target, ruleEntry: ruleEntry, hostTarget: hostTarget, ruleEntryMap: ruleEntryMap)
    updateTestTargetBuildPhases(target, ruleEntry: ruleEntry, ruleEntryMap: ruleEntryMap, pathFilters: pathFilters)
  }

  /// Updates the test target indexer with test specific values.
  private func updateTestTargetIndexer(_ target: PBXNativeTarget,
                                       ruleEntry: RuleEntry,
                                       hostTarget: PBXNativeTarget?,
                                       ruleEntryMap: RuleEntryMap) {
    let testSettings = targetTestSettings(target, hostTarget: hostTarget, ruleEntry: ruleEntry, ruleEntryMap: ruleEntryMap)

    // Inherit the resolved values from the indexer.
    let deploymentTarget = ruleEntry.deploymentTarget ?? PBXTargetGenerator.defaultDeploymentTarget()
    let deploymentTargetLabel = IndexerData.deploymentTargetLabel(deploymentTarget)
    let indexerName = PBXTargetGenerator.indexerNameForTargetName(ruleEntry.label.targetName!,
                                                                  hash: ruleEntry.label.hashValue,
                                                                  suffix: deploymentTargetLabel)
    let indexerTarget = indexerTargetByName[indexerName]
    updateMissingBuildConfigurationsForList(target.buildConfigurationList,
                                            withBuildSettings: testSettings,
                                            inheritingFromConfigurationList: indexerTarget?.buildConfigurationList,
                                            suppressingBuildSettings: ["ARCHS", "VALID_ARCHS"])
  }

  private func updateTestTargetBuildPhases(_ target: PBXNativeTarget,
                                           ruleEntry: RuleEntry,
                                           ruleEntryMap: RuleEntryMap,
                                           pathFilters: Set<String>?) {
    let includePathInProject = pathFilterFunc(pathFilters)
    func includeFileInProject(_ info: BazelFileInfo) -> Bool {
      return includePathInProject(info.fullPath)
    }
    let testSourceFileInfos = ruleEntry.sourceFiles.filter(includeFileInProject)
    let testNonArcSourceFileInfos = ruleEntry.nonARCSourceFiles.filter(includeFileInProject)
    let containsSwift = ruleEntry.attributes[.has_swift_dependency] as? Bool ?? false

    // For the Swift dummy files phase to work, it has to be placed before the Compile Sources build
    // phase.
    if containsSwift {
      let testBuildPhase = createGenerateSwiftDummyFilesTestBuildPhase()
      target.buildPhases.append(testBuildPhase)
    }
    if !testSourceFileInfos.isEmpty || !testNonArcSourceFileInfos.isEmpty {
      // Create dummy dependency files for non-Swift code as Xcode expects Clang to generate them.
      let allSources = testSourceFileInfos + testNonArcSourceFileInfos
      let nonSwiftSources = allSources.filter { !$0.subPath.hasSuffix(".swift") }
      if !nonSwiftSources.isEmpty {
        let testBuildPhase = createGenerateDummyDependencyFilesTestBuildPhase(nonSwiftSources)
        target.buildPhases.append(testBuildPhase)
      }
      var fileReferences = generateFileReferencesForFileInfos(testSourceFileInfos)
      let (nonARCFiles, nonARCSettings) =
          generateFileReferencesAndSettingsForNonARCFileInfos(testNonArcSourceFileInfos)
      fileReferences.append(contentsOf: nonARCFiles)
      let buildPhase = createBuildPhaseForReferences(fileReferences,
                                                     withPerFileSettings: nonARCSettings)
      target.buildPhases.append(buildPhase)
    }
  }

  /// Adds includes paths from the RuleEntry to the given NSSet.
  private func addIncludes(_ ruleEntry: RuleEntry,
                           toSet includes: NSMutableOrderedSet) {
    if let includePaths = ruleEntry.includePaths {
      let rootedPaths: [String] = includePaths.map() { (path, recursive) in
        // Any paths of the tulsi-includes form will only be in the bazel workspace symlink since
        // they refer to generated files from a build.
        // Otherwise we assume the file exists in its workspace.
        let prefixVar: String
        if path.hasPrefix(PBXTargetGenerator.tulsiIncludesPath) {
          prefixVar = PBXTargetGenerator.BazelExecutionRootSymlinkVarName
        } else if path.hasPrefix(PBXTargetGenerator.externalPrefix) {
          // We refer to files in external workspaces via their more stable location in output base
          // <output base>/external remains between builds and contains all external workspaces
          // <execution root>/external is instead torn down on each build, breaking the paths to
          // any external workspaces not used in the particular target being built 
          prefixVar = PBXTargetGenerator.BazelOutputBaseSymlinkVarName
        } else {
          prefixVar = PBXTargetGenerator.WorkspaceRootVarName
        }
        let rootedPath = "$(\(prefixVar))/\(path)"
        if recursive {
          return "\(rootedPath)/**"
        }
        return rootedPath
      }
      includes.addObjects(from: rootedPaths)
    }
  }

  /// Adds swift include paths from the RuleEntry to the given NSSet.
  private func addSwiftIncludes(_ ruleEntry: RuleEntry,
                                toSet swiftIncludes: NSMutableOrderedSet) {
    for module in ruleEntry.swiftTransitiveModules {
      let fullPath = module.fullPath as NSString
      let includePath = fullPath.deletingLastPathComponent
      swiftIncludes.add("$(\(PBXTargetGenerator.BazelExecutionRootSymlinkVarName))/\(includePath)")
    }
  }

  /// Returns other swift compiler flags for the given target based on the RuleEntry.
  private func addOtherSwiftFlags(_ ruleEntry: RuleEntry, toArray swiftFlags: NSMutableArray) {
    // Load module maps explicitly instead of letting Clang discover them on search paths. This
    // is needed to avoid a case where Clang may load the same header both in modular and
    // non-modular contexts, leading to duplicate definitions in the same file.
    // See llvm.org/bugs/show_bug.cgi?id=19501
    swiftFlags.addObjects(from: ruleEntry.objCModuleMaps.map() {
      "-Xcc -fmodule-map-file=$(\(PBXTargetGenerator.BazelExecutionRootSymlinkVarName))/\($0.fullPath)"
    })

    if let swiftDefines = ruleEntry.swiftDefines {
      for flag in swiftDefines {
        swiftFlags.add("-D\(flag)")
      }
    }
  }

  /// Reads the RuleEntry's copts and puts the arguments into the correct set.
  private func addLocalSettings(_ ruleEntry: RuleEntry,
                                localDefines: inout Set<String>,
                                localIncludes: NSMutableOrderedSet,
                                otherCFlags: NSMutableArray,
                                swiftIncludePaths: NSMutableOrderedSet,
                                otherSwiftFlags: NSMutableArray) {
    if let swiftc_opts = ruleEntry.attributes[.swiftc_opts] as? [String], !swiftc_opts.isEmpty {
      for opt in swiftc_opts {
        if opt.hasPrefix("-I") {
          let index = opt.index(opt.startIndex, offsetBy: 2)
          var path = String(opt[index...])
          if !path.hasPrefix("/") {
            path = "$(\(PBXTargetGenerator.BazelExecutionRootSymlinkVarName))/\(path)"
          }
          swiftIncludePaths.add(path)
        } else {
          otherSwiftFlags.add(opt)
        }
      }
    }
    guard let copts = ruleEntry.attributes[.copts] as? [String], !copts.isEmpty else {
      return
    }
    for opt in copts {
      if opt.hasPrefix("-D") {
        let index = opt.index(opt.startIndex, offsetBy: 2)
        localDefines.insert(String(opt[index...]))
      } else if opt.hasPrefix("-I") {
        let index = opt.index(opt.startIndex, offsetBy: 2)
        var path = String(opt[index...])
        if !path.hasPrefix("/") {
          path = "$(\(PBXTargetGenerator.BazelExecutionRootSymlinkVarName))/\(path)"
        }
        localIncludes.add(path)
      } else {
        otherCFlags.add(opt)
      }
    }
  }

  /// Returns test specific settings for test targets.
  private func targetTestSettings(_ target: PBXNativeTarget,
                                  hostTarget: PBXNativeTarget?,
                                  ruleEntry: RuleEntry,
                                  ruleEntryMap: RuleEntryMap) -> [String: String] {
    var testSettings = ["TULSI_TEST_RUNNER_ONLY": "YES"]
    // Attempt to update the build configs for the target to include BUNDLE_LOADER and TEST_HOST
    // values, linking the test target to its host.
    if let hostTargetPath = hostTarget?.productReference?.path,
      let hostTargetProductName = hostTarget?.productName,
      let deploymentTarget = target.deploymentTarget {

      if target.productType == .UIUnitTest {
        testSettings["TEST_TARGET_NAME"] = hostTargetProductName
      } else if let testHostPath = deploymentTarget.platform.testHostPath(hostTargetPath: hostTargetPath,
                                                                          hostTargetProductName: hostTargetProductName) {
        testSettings["BUNDLE_LOADER"] = "$(TEST_HOST)"
        testSettings["TEST_HOST"] = testHostPath
      }
    }

    let includes = NSMutableOrderedSet()

    // We don't use the defines at the moment but the function will add them anyway. We could try
    // to use the defines but we'd have to do so on a per-file basis as this Test target can contain
    // files from multiple targets.
    var defines = Set<String>()
    let swiftIncludePaths = NSMutableOrderedSet()
    let otherSwiftFlags = NSMutableArray()

    addIncludes(ruleEntry, toSet: includes)
    addLocalSettings(ruleEntry, localDefines: &defines, localIncludes: includes,
                     otherCFlags: NSMutableArray(), swiftIncludePaths: NSMutableOrderedSet(),
                     otherSwiftFlags: NSMutableArray())
    addSwiftIncludes(ruleEntry, toSet: swiftIncludePaths)
    addOtherSwiftFlags(ruleEntry, toArray: otherSwiftFlags)

    let includesArr = includes.array as! [String]
    if !includesArr.isEmpty {
      testSettings["HEADER_SEARCH_PATHS"] = "$(inherited) " + includesArr.joined(separator: " ")
    }

    if let swiftIncludes = swiftIncludePaths.array as? [String], !swiftIncludes.isEmpty {
      testSettings["SWIFT_INCLUDE_PATHS"] = "$(inherited) " + swiftIncludes.joined(separator: " ")
    }

    if let otherSwiftFlagsArr = otherSwiftFlags as? [String], !otherSwiftFlagsArr.isEmpty {
      testSettings["OTHER_SWIFT_FLAGS"] = "$(inherited) " + otherSwiftFlagsArr.joined(separator: " ")
    }

    if let moduleName = ruleEntry.moduleName {
      testSettings["PRODUCT_MODULE_NAME"] = moduleName
    }

    return testSettings
  }

  // Adds a dummy build configuration to the given list based off of the Debug config that is
  // used to effectively disable compilation when running XCTests by converting each compile call
  // into a "clang --version" invocation.
  private func addTestRunnerBuildConfigurationToBuildConfigurationList(_ list: XCConfigurationList) {

    func createTestConfigNamed(_ testConfigName: String,
                               forBaseConfigNamed configurationName: String) {
      let baseConfig = list.getOrCreateBuildConfiguration(configurationName)
      let config = list.getOrCreateBuildConfiguration(testConfigName)

      var runTestTargetBuildSettings = baseConfig.buildSettings
      // Prevent compilation invocations from actually compiling ObjC, C and Swift files.
      runTestTargetBuildSettings["OTHER_CFLAGS"] = "--version"
      runTestTargetBuildSettings["OTHER_SWIFT_FLAGS"] = "--version"
      // Prevents linker invocations from attempting to use the .o files which were never generated
      // due to compilation being turned into nop's.
      runTestTargetBuildSettings["OTHER_LDFLAGS"] = "--version"

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
      if configName == "Debug" {
        addPreprocessorDefine("DEBUG=1", toConfig: config)
      } else if configName == "Release" {
        addPreprocessorDefine("NDEBUG=1", toConfig: config)
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

  static func indexerNameForTargetName(_ targetName: String, hash: Int, suffix: String?) -> String {
    let normalizedTargetName: String
    if targetName.count > MaxIndexerNameLength {
      let endIndex = targetName.index(targetName.startIndex, offsetBy: MaxIndexerNameLength - 4)
      normalizedTargetName = String(targetName[..<endIndex]) + "_etc"
    } else {
      normalizedTargetName = targetName
    }
    if let suffix = suffix {
      return String(format: "\(IndexerTargetPrefix)\(normalizedTargetName)_%08X_%@", hash, suffix)
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

  /// Creates a PBXNativeTarget for the given rule entry, returning it.
  private func createBuildTargetForRuleEntry(_ entry: RuleEntry,
                                             named name: String,
                                             ruleEntryMap: RuleEntryMap)
      throws -> (PBXNativeTarget) {
    guard let pbxTargetType = entry.pbxTargetType else {
      throw ProjectSerializationError.unsupportedTargetType(entry.type, entry.label.value)
    }
    let target = project.createNativeTarget(name,
                                            deploymentTarget: entry.deploymentTarget,
                                            targetType: pbxTargetType)

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

    if let deploymentTarget = entry.deploymentTarget {
      buildSettings[deploymentTarget.platform.buildSettingsDeploymentTarget] = deploymentTarget.osVersion
    }

    // watchOS1 apps require TARGETED_DEVICE_FAMILY to be overridden as they are a specialization of
    // an iOS target rather than a true standalone (like watchOS2 and later).
    if pbxTargetType == .Watch1App {
      buildSettings["TARGETED_DEVICE_FAMILY"] = "4"
      buildSettings["TARGETED_DEVICE_FAMILY[sdk=iphonesimulator*]"] = "1,4"
    }

    // App clips are improperly signed by Xcode when using the legacy build system even with
    // CODE_SIGNING_REQUIRED=NO so disable code signing and let bazel_build.py do the necessary
    // signing.
    if pbxTargetType == .AppClip {
      buildSettings["CODE_SIGNING_ALLOWED"] = "NO"
    }

    // bazel_build.py uses this to determine if it needs to pass the --xcode_version flag, as the
    // flag can have implications for caching even if the user's active Xcode version is the same
    // as the flag.
    if let xcodeVersion = entry.xcodeVersion {
      buildSettings["TULSI_XCODE_VERSION"] = xcodeVersion
    }

    // Disable Xcode's attempts at generating dSYM bundles as it conflicts with the operation of the
    // special test runner build configurations (which have associated sources but don't actually
    // compile anything).
    buildSettings["DEBUG_INFORMATION_FORMAT"] = "dwarf"

    // The following settings are simply passed through the environment for use by build scripts.
    buildSettings["BAZEL_TARGET"] = entry.label.value

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

    return target
  }

  private func createGenerateSwiftDummyFilesTestBuildPhase() -> PBXShellScriptBuildPhase {
    let shellScript =
        "# Script to generate specific Swift files Xcode expects when running tests.\n" +
        "set -eu\n" +
        "ARCH_ARRAY=($ARCHS)\n" +
        "SUFFIXES=(swiftdoc swiftmodule)\n" +
        "for ARCH in \"${ARCH_ARRAY[@]}\"\n" +
        "do\n" +
        "  mkdir -p \"$OBJECT_FILE_DIR_normal/$ARCH/\"\n" +
        "  touch \"$OBJECT_FILE_DIR_normal/$ARCH/$SWIFT_OBJC_INTERFACE_HEADER_NAME\"\n" +
        "  for SUFFIX in \"${SUFFIXES[@]}\"\n" +
        "  do\n" +
        "    touch \"$OBJECT_FILE_DIR_normal/$ARCH/$PRODUCT_MODULE_NAME.$SUFFIX\"\n" +
        "  done\n" +
        "done\n"

    let buildPhase = PBXShellScriptBuildPhase(
      shellScript: shellScript,
      shellPath: "/bin/bash",
      name: "Swift dummy file generation")
    buildPhase.showEnvVarsInLog = true
    buildPhase.mnemonic = "SwiftDummy"
    return buildPhase
  }

  private func createGenerateDummyDependencyFilesTestBuildPhase(_ sources: [BazelFileInfo]) -> PBXShellScriptBuildPhase {
    let files = sources.map { ($0.subPath as NSString).deletingPathExtension.pbPathLastComponent }
    let shellScript = """
# Script to generate dependency files Xcode expects when running tests.
set -eu
ARCH_ARRAY=($ARCHS)
FILES=(\(files.map { $0.escapingForShell }.joined(separator: " ")))
for ARCH in "${ARCH_ARRAY[@]}"
do
  mkdir -p "$OBJECT_FILE_DIR_normal/$ARCH/"
  rm -f "$OBJECT_FILE_DIR_normal/$ARCH/${PRODUCT_NAME}_dependency_info.dat"
  printf '\\x00\\x31\\x00' >"$OBJECT_FILE_DIR_normal/$ARCH/${PRODUCT_NAME}_dependency_info.dat"
  for FILE in "${FILES[@]}"
  do
    touch "$OBJECT_FILE_DIR_normal/$ARCH/$FILE.d"
  done
done
"""
    let buildPhase = PBXShellScriptBuildPhase(
      shellScript: shellScript,
      shellPath: "/bin/bash",
      name: "Objective-C dummy file generation")
    buildPhase.showEnvVarsInLog = true
    buildPhase.mnemonic = "ObjcDummy"
    return buildPhase
  }

  private func createBuildPhaseForRuleEntry(_ entry: RuleEntry)
      -> PBXShellScriptBuildPhase? {
    let buildLabel = entry.label.value
    let commandLine = buildScriptCommandlineForBuildLabels(buildLabel)
    let workingDirectory = PBXTargetGenerator.workingDirectoryForPBXGroup(project.mainGroup)
    let changeDirectoryAction: String
    if workingDirectory.isEmpty {
      changeDirectoryAction = ""
    } else {
      changeDirectoryAction = "cd \"\(workingDirectory)\""
    }
    let shellScript = "set -e\n" +
        "\(changeDirectoryAction)\n" +
        "exec \(commandLine)"

    // Using the Info.plist as an input forces Xcode to run this after processing the Info.plist,
    // allowing our script to safely overwrite the Info.plist after Xcode does its processing.
    let inputPaths = ["$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)"]
    let buildPhase = PBXShellScriptBuildPhase(
      shellScript: shellScript,
      shellPath: "/bin/bash",
      name: "build \(entry.label)",
      inputPaths: inputPaths
    )
    buildPhase.showEnvVarsInLog = true
    buildPhase.mnemonic = "BazelBuild"
    return buildPhase
  }

  /// Constructs a commandline string that will invoke the bazel build script to generate the given
  /// buildLabels (a space-separated set of Bazel target labels).
  private func buildScriptCommandlineForBuildLabels(_ buildLabels: String) -> String {
    return "\"\(buildScriptPath)\" " +
        "\(buildLabels) " +
        "--bazel \"\(bazelPath)\" " +
        "--bazel_bin_path \"\(bazelBinPath)\" " +
        "--verbose "
  }
}
