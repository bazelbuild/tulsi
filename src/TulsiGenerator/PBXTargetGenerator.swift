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


// Concrete PBXProject target generator.
class PBXTargetGenerator {

  enum ProjectSerializationError: ErrorType {
    case BUILDFileIsNotContainedByProjectRoot
    case GeneralFailure(String)
    case UnsupportedTargetType(String)
  }

  /// Names of Xcode build configurations to generate.
  // NOTE: Must be kept in sync with the CONFIGURATION environment variable use in the build script.
  static let buildConfigNames = ["Debug", "Fastbuild", "Release"]

  /// Prefix for special configs used when running XCTests that prevent compilation and linking of
  /// any source files. This allows XCTest bundles to have associated test sources indexed by Xcode
  /// but not compiled when testing (as they're compiled by Bazel and the generated project may be
  /// missing information necessary to compile them anyway). Configs are generated for Debug and
  /// Release builds.
  // NOTE: This value needs to be kept in sync with the bazel_build script.
  static let runTestTargetBuildConfigPrefix = "__TulsiTestRunner_"

  /// Name of the static library target that will be used to accumulate all source file dependencies
  /// in order to make their symbols available to the Xcode indexer.
  static let IndexerTargetPrefix = "_indexer_"

  /// Name of the legacy target that will be used to communicate with Bazel during Xcode clean
  /// actions.
  static let BazelCleanTarget = "_bazel_clean_"

  /// Location of the bazel binary.
  let bazelURL: NSURL

  /// Location of the bazel-bin symlink, relative to the workspace root.
  let bazelBinPath: String
  var bazelGenfilesPath: String {
    return bazelBinPath.stringByReplacingOccurrencesOfString("-bin", withString: "-genfiles")
  }

  let project: PBXProject
  let buildScriptPath: String
  let envScriptPath: String
  let tulsiVersion: String
  let options: TulsiOptionSet
  let localizedMessageLogger: LocalizedMessageLogger
  let workspaceRootURL: NSURL
  let suppressCompilerDefines: Bool

  var bazelCleanScriptTarget: PBXLegacyTarget? = nil

  private static func projectRefForBazelFileInfo(info: BazelFileInfo) -> String {
    return "$(TULSI_WORKSPACE_ROOT)/\(info.fullPath)"
  }

  init(bazelURL: NSURL,
       bazelBinPath: String,
       project: PBXProject,
       buildScriptPath: String,
       envScriptPath: String,
       tulsiVersion: String,
       options: TulsiOptionSet,
       localizedMessageLogger: LocalizedMessageLogger,
       workspaceRootURL: NSURL,
       suppressCompilerDefines: Bool = false) {
    self.bazelURL = bazelURL
    self.bazelBinPath = bazelBinPath
    self.project = project
    self.buildScriptPath = buildScriptPath
    self.envScriptPath = envScriptPath
    self.tulsiVersion = tulsiVersion
    self.options = options
    self.localizedMessageLogger = localizedMessageLogger
    self.workspaceRootURL = workspaceRootURL
    self.suppressCompilerDefines = suppressCompilerDefines
  }

  /// Generates file references for the given file paths in the associated project without adding
  /// them to an indexer target. The paths must be relative to the workspace root.
  func generateFileReferencesForFilePaths(paths: [String]) {
    project.getOrCreateGroupsAndFileReferencesForPaths(paths)
  }

  /// Generates an indexer target for the given Bazel rule and its transitive dependencies, adding
  /// source files whose directories are present in pathFilters.
  func generateIndexerTargetForRuleEntry(ruleEntry: RuleEntry,
                                         ruleEntryMap: [BuildLabel: RuleEntry],
                                         pathFilters: Set<String>) {
    let recursiveFilters = Set<String>(pathFilters.filter({ $0.hasSuffix("/...") }).map() {
      $0.substringToIndex($0.endIndex.advancedBy(-3))
    })

    func includePathInProject(path: String) -> Bool {
      let dir = (path as NSString).stringByDeletingLastPathComponent
      if pathFilters.contains(dir) { return true }
      let terminatedDir = dir + "/"
      for filter in recursiveFilters {
        if terminatedDir.hasPrefix(filter) { return true }
      }
      return false
    }

    func includeFileInProject(info: BazelFileInfo) -> Bool {
      return includePathInProject(info.fullPath)
    }

    func addBuildFileForRule(ruleEntry: RuleEntry) {
      guard let buildFilePath = ruleEntry.buildFilePath where includePathInProject(buildFilePath) else {
        return
      }
      project.getOrCreateGroupsAndFileReferencesForPaths([buildFilePath])
    }

    // Map of build label to cumulative preprocessor defines and include paths.
    var processedEntries = [BuildLabel: (Set<String>, [String])]()
    func generateIndexerTargetGraphForRuleEntry(ruleEntry: RuleEntry) -> (Set<String>, [String]) {
      if let data = processedEntries[ruleEntry.label] {
        return data
      }
      var defines = Set<String>()
      var includes = [String]()
      var includesSet = Set<String>()

      defer { processedEntries[ruleEntry.label] = (defines, includes) }

      for dep in ruleEntry.dependencies {
        guard let depEntry = ruleEntryMap[BuildLabel(dep)] else {
          localizedMessageLogger.warning("UnknownTargetRule",
                                         comment: "Failure to look up a Bazel target that was expected to be present. The target label is %1$@",
                                         values: dep)
          continue
        }

        let (inheritedDefines, inheritedIncludes) = generateIndexerTargetGraphForRuleEntry(depEntry)
        defines.unionInPlace(inheritedDefines)
        for include in inheritedIncludes {
          if !includesSet.contains(include) {
            includes.append(include)
            includesSet.insert(include)
          }
        }
      }

      if let ruleDefines = ruleEntry.attributes[.defines] as? [String] where !ruleDefines.isEmpty {
        defines.unionInPlace(ruleDefines)
      }
      if !suppressCompilerDefines,
         let ruleDefines = ruleEntry.attributes[.compiler_defines] as? [String]
         where !ruleDefines.isEmpty {
        defines.unionInPlace(ruleDefines)
      }

      if let ruleIncludes = ruleEntry.attributes[.includes] as? [String] {
        let packagePath: String
        if let packageName = ruleEntry.label.packageName where !packageName.isEmpty {
          packagePath = packageName + "/"
        } else {
          packagePath = ""
        }
        let rootedPaths = ruleIncludes.map() { "$(TULSI_WORKSPACE_ROOT)/\(packagePath)\($0)" }
        for include in rootedPaths {
          if !includesSet.contains(include) {
            includes.append(include)
            includesSet.insert(include)
          }
        }
      }

      if let generatedIncludePaths = ruleEntry.generatedIncludePaths {
        let rootedPaths = generatedIncludePaths.map() { "$(TULSI_WORKSPACE_ROOT)/\($0)" }
        for include in rootedPaths {
          if !includesSet.contains(include) {
            includes.append(include)
            includesSet.insert(include)
          }
        }
      }

      let sourceFileInfos = ruleEntry.sourceFiles.filter(includeFileInProject)
      let nonARCSourceFileInfos = ruleEntry.nonARCSourceFiles.filter(includeFileInProject)
      var buildPhaseReferences = [PBXReference]()
      let versionedFileTargets = ruleEntry.versionedNonSourceArtifacts.filter(includeFileInProject)
      if !versionedFileTargets.isEmpty {
        let versionedFileReferences = createReferencesForVersionedFileTargets(versionedFileTargets)
        buildPhaseReferences.appendContentsOf(versionedFileReferences as [PBXReference])
      }

      for target in ruleEntry.normalNonSourceArtifacts.filter(includeFileInProject) {
        let path = target.fullPath as NSString
        let group = project.getOrCreateGroupForPath(path.stringByDeletingLastPathComponent)
        let ref = group.getOrCreateFileReferenceBySourceTree(.Group,
                                                             path: path.lastPathComponent)
        ref.isInputFile = target.targetType == .SourceFile
      }

      if sourceFileInfos.isEmpty && nonARCSourceFileInfos.isEmpty && buildPhaseReferences.isEmpty {
        return (defines, includes)
      }

      var localPreprocessorDefines = defines
      var localIncludes = includes
      if let copts = ruleEntry.attributes[.copts] as? [String] where !copts.isEmpty {
        for opt in copts {
          // TODO(abaire): Add support for shell tokenization as advertised in the Bazel build
          //     encyclopedia.
          if opt.hasPrefix("-D") {
            localPreprocessorDefines.insert(opt.substringFromIndex(opt.startIndex.advancedBy(2)))
          } else  if opt.hasPrefix("-I") {
            var path = opt.substringFromIndex(opt.startIndex.advancedBy(2))
            if !path.hasPrefix("/") {
              path = "$(TULSI_WORKSPACE_ROOT)/\(path)"
            }
            if !includesSet.contains(path) {
              localIncludes.append(path)
              includesSet.insert(path)
            }
          }
        }
      }

      let targetName = indexerNameForRuleEntry(ruleEntry)
      let indexingTarget = project.createNativeTarget(targetName,
                                                      targetType: PBXTarget.ProductType.StaticLibrary)

      var fileReferences = generateFileReferencesForFileInfos(sourceFileInfos)
      fileReferences.appendContentsOf(generateFileReferencesForNonARCFileInfos(nonARCSourceFileInfos))
      buildPhaseReferences.appendContentsOf(fileReferences as [PBXReference])
      addBuildFileForRule(ruleEntry)
      let buildPhase = createBuildPhaseForReferences(buildPhaseReferences)
      indexingTarget.buildPhases.append(buildPhase)
      addConfigsForIndexingTarget(indexingTarget,
                                  ruleEntry: ruleEntry,
                                  preprocessorDefines: localPreprocessorDefines,
                                  includes: localIncludes,
                                  sourceFilter: includeFileInProject)
      return (defines, includes)
    }

    generateIndexerTargetGraphForRuleEntry(ruleEntry)
  }

  /// Generates a legacy target that is added as a dependency of all build targets and invokes
  /// the given script. The build action may be accessed by the script via the ACTION environment
  /// variable.
  func generateBazelCleanTarget(scriptPath: String, workingDirectory: String = "") {
    assert(bazelCleanScriptTarget == nil, "generateBazelCleanTarget may only be called once")

    let bazelPath = bazelURL.path!
    bazelCleanScriptTarget = project.createLegacyTarget(PBXTargetGenerator.BazelCleanTarget,
                                                        buildToolPath: "\(scriptPath)",
                                                        buildArguments: "\"\(bazelPath)\" \"\(bazelBinPath)\"",
                                                        buildWorkingDirectory: workingDirectory)

    for target: PBXTarget in project.allTargets {
      if target === bazelCleanScriptTarget {
        continue
      }

      target.createDependencyOn(bazelCleanScriptTarget!,
                                proxyType: PBXContainerItemProxy.ProxyType.TargetReference,
                                inProject: project,
                                first: true)
    }
  }

  /// Generates top level build configurations with an optional set of additional include paths.
  func generateTopLevelBuildConfigurations(additionalIncludePaths: Set<String>? = nil) {
    var buildSettings = options.commonBuildSettings()
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

    var sourceDirectory = PBXTargetGenerator.workingDirectoryForPBXGroup(project.mainGroup)
    if sourceDirectory.isEmpty {
      sourceDirectory = "$(SRCROOT)"
    }
    buildSettings["TULSI_WORKSPACE_ROOT"] = sourceDirectory
    buildSettings["TULSI_VERSION"] = tulsiVersion

    var searchPaths = ["$(TULSI_WORKSPACE_ROOT)",
                       "$(TULSI_WORKSPACE_ROOT)/\(bazelBinPath)",
                       "$(TULSI_WORKSPACE_ROOT)/\(bazelGenfilesPath)",
    ]
    if let additionalIncludePaths = additionalIncludePaths {
      let rootedPaths = additionalIncludePaths.sort().map({"$(TULSI_WORKSPACE_ROOT)/\($0)"})
      searchPaths.appendContentsOf(rootedPaths)
    }
    buildSettings["HEADER_SEARCH_PATHS"] = searchPaths.joinWithSeparator(" ")

    createBuildConfigurationsForList(project.buildConfigurationList, buildSettings: buildSettings)
  }

  /// Generates Xcode build targets that invoke Bazel for the given targets. For test-type rules,
  /// non-compiling source file linkages are created to facilitate indexing of XCTests.
  /// Throws if one of the RuleEntry instances is for an unsupported Bazel target type.
  func generateBuildTargetsForRuleEntries(ruleEntries: [RuleEntry]) throws {
    let namedRuleEntries = generateUniqueNamesForRuleEntries(ruleEntries)
    var testTargetLinkages = [(PBXTarget, BuildLabel, RuleEntry)]()
    for (name, entry) in namedRuleEntries {
      let target = try createBuildTargetForRuleEntry(entry, named: name)

      if let hostLabelString = entry.attributes[.xctest_app] as? String {
        let hostLabel = BuildLabel(hostLabelString)
        testTargetLinkages.append((target, hostLabel, entry))
      }
    }

    for (testTarget, testHostLabel, entry) in testTargetLinkages {
      updateTestTarget(testTarget,
                       withLinkageToHostTarget: testHostLabel,
                       ruleEntry: entry)
    }
  }

  // Returns a PBXGroup appropriate for use as a top level project group.
  static func mainGroupForOutputFolder(outputFolderURL: NSURL, workspaceRootURL: NSURL) -> PBXGroup {
    let outputFolder = outputFolderURL.path!
    let workspaceRoot = workspaceRootURL.path!

    let slashTerminatedOutputFolder = outputFolder + (outputFolder.hasSuffix("/") ? "" : "/")
    let slashTerminatedWorkspaceRoot = workspaceRoot + (workspaceRoot.hasSuffix("/") ? "" : "/")

    // If workspaceRoot == outputFolder, return a relative group with no path.
    if slashTerminatedOutputFolder == slashTerminatedWorkspaceRoot {
      return PBXGroup(name: "mainGroup", path: nil, sourceTree: .SourceRoot, parent: nil)
    }

    // If outputFolder contains workspaceRoot, return a relative group with the path from
    // outputFolder to workspaceRoot
    if workspaceRoot.hasPrefix(slashTerminatedOutputFolder) {
      let index = workspaceRoot.startIndex.advancedBy(slashTerminatedOutputFolder.characters.count)
      let relativePath = workspaceRoot.substringFromIndex(index)
      return PBXGroup(name: "mainGroup",
                      path: relativePath,
                      sourceTree: .SourceRoot,
                      parent: nil)
    }

    // If workspaceRoot contains outputFolder, return a relative group using .. to walk up to
    // workspaceRoot from outputFolder.
    if outputFolder.hasPrefix(slashTerminatedWorkspaceRoot) {
      let index = outputFolder.startIndex.advancedBy(slashTerminatedWorkspaceRoot.characters.count + 1)
      let pathToWalkBackUp = outputFolder.substringFromIndex(index) as NSString
      let numberOfDirectoriesToWalk = pathToWalkBackUp.pathComponents.count
      let relativePath = [String](count: numberOfDirectoriesToWalk, repeatedValue: "..").joinWithSeparator("/")
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

  // MARK: - Private methods

  private func generateFileReferencesForFileInfos(infos: [BazelFileInfo]) -> [PBXFileReference] {
    var generatedFilePaths = [String]()
    var sourceFilePaths = [String]()
    for info in infos {
      switch info.targetType {
        case .GeneratedFile:
          generatedFilePaths.append(info.fullPath)
        case .SourceFile:
          sourceFilePaths.append(info.fullPath)
      }
    }

    // Add the source paths directly and the generated paths with explicitFileType set.
    var (_, fileReferences) = project.getOrCreateGroupsAndFileReferencesForPaths(sourceFilePaths)
    let (_, generatedFileReferences) = project.getOrCreateGroupsAndFileReferencesForPaths(generatedFilePaths)
    generatedFileReferences.forEach() { $0.isInputFile = false }

    fileReferences.appendContentsOf(generatedFileReferences)
    return fileReferences
  }

  /// Generates file references for the given infos, marking them as -fno-objc-arc.
  private func generateFileReferencesForNonARCFileInfos(infos: [BazelFileInfo]) -> [PBXFileReference] {
    let nonARCFileReferences = generateFileReferencesForFileInfos(infos)
    nonARCFileReferences.forEach() {
      $0.setCompilerFlags(["-fno-objc-arc"])
    }
    return nonARCFileReferences
  }

  private func generateUniqueNamesForRuleEntries(ruleEntries: [RuleEntry]) -> [String: RuleEntry] {
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
  private func createReferencesForVersionedFileTargets(fileInfos: [BazelFileInfo]) -> [XCVersionGroup] {
    var groups = [String: XCVersionGroup]()

    for info in fileInfos {
      let path = info.fullPath as NSString
      let versionedGroupPath = path.stringByDeletingLastPathComponent
      let type = info.subPath.pbPathUTI ?? ""
      let versionedGroup = project.getOrCreateVersionGroupForPath(versionedGroupPath,
                                                                  versionGroupType: type)
      if groups[versionedGroupPath] == nil {
        groups[versionedGroupPath] = versionedGroup
      }
      let ref = versionedGroup.getOrCreateFileReferenceBySourceTree(.Group,
                                                                    path: path.lastPathComponent)
      ref.isInputFile = info.targetType == .SourceFile
    }

    for (sourcePath, group) in groups {
      setCurrentVersionForXCVersionGroup(group, atPath: sourcePath)
    }
    return Array(groups.values)
  }

  // Attempt to read the .xccurrentversion plists in the xcdatamodeld's and sync up the
  // currentVersion in the XCVersionGroup instances. Failure to specify the currentVersion will
  // result in Xcode picking an arbitrary version.
  private func setCurrentVersionForXCVersionGroup(group: XCVersionGroup,
                                                  atPath sourcePath: String) {
    let versionedBundleURL = workspaceRootURL.URLByAppendingPathComponent(sourcePath,
                                                                          isDirectory: true)
    let currentVersionPlistURL = versionedBundleURL.URLByAppendingPathComponent(".xccurrentversion",
                                                                                isDirectory: false)
    let path = currentVersionPlistURL.path!
    guard let data = NSFileManager.defaultManager().contentsAtPath(path) else {
      self.localizedMessageLogger.warning("LoadingXCCurrentVersionFailed",
                                          comment: "Message to show when loading a .xccurrentversion file fails.",
                                          values: group.name, "Version file at '\(path)' could not be read")
      return
    }

    do {
      let plist = try NSPropertyListSerialization.propertyListWithData(data,
                                                                       options: .Immutable,
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
  private func addConfigsForIndexingTarget(target: PBXTarget,
                                           ruleEntry: RuleEntry,
                                           preprocessorDefines: Set<String>?,
                                           includes: [String],
                                           sourceFilter: (BazelFileInfo) -> Bool) {
    var buildSettings = options.buildSettingsForTarget(target.name)
    buildSettings["PRODUCT_NAME"] = target.productName!

    func addFilteredSourceReference(info: BazelFileInfo) {
      if !sourceFilter(info) { return }
      let (_, fileReferences) = project.getOrCreateGroupsAndFileReferencesForPaths([info.fullPath])
      fileReferences.first!.isInputFile = info.targetType == .SourceFile
    }

    if let pchFile = BazelFileInfo(info: ruleEntry.attributes[.pch]) {
      buildSettings["GCC_PREFIX_HEADER"] = PBXTargetGenerator.projectRefForBazelFileInfo(pchFile)
      addFilteredSourceReference(pchFile)
    }

    if let preprocessorDefines = preprocessorDefines where !preprocessorDefines.isEmpty {
      let cflagDefines = preprocessorDefines.sort().map({"-D\($0)"})
      buildSettings["OTHER_CFLAGS"] = cflagDefines.joinWithSeparator(" ")
    }

    if let bridgingHeader = BazelFileInfo(info: ruleEntry.attributes[.bridging_header]) {
      buildSettings["SWIFT_OBJC_BRIDGING_HEADER"] = PBXTargetGenerator.projectRefForBazelFileInfo(bridgingHeader)
      addFilteredSourceReference(bridgingHeader)
    }

    if let enableModules = ruleEntry.attributes[.enable_modules] as? Int where enableModules == 1 {
      buildSettings["CLANG_ENABLE_MODULES"] = "YES"
    }

    if !includes.isEmpty {
      buildSettings["HEADER_SEARCH_PATHS"] = "$(inherited) " + includes.joinWithSeparator(" ")
    }

    createBuildConfigurationsForList(target.buildConfigurationList, buildSettings: buildSettings)
  }

  // Updates the build settings and optionally adds a "Compile sources" phase for the given test
  // bundle target.
  private func updateTestTarget(target: PBXTarget,
                                withLinkageToHostTarget hostTargetLabel: BuildLabel,
                                ruleEntry: RuleEntry) {
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
           hostProductName = hostTarget.productName {
      let testSettings = [
          "BUNDLE_LOADER": "$(TEST_HOST)",
          "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(hostProduct)/\(hostProductName)",
      ]

      // Inherit the resolved values from the indexer.
      let indexerTarget = project.targetByName[indexerNameForRuleEntry(ruleEntry)]
      updateMissingBuildConfigurationsForList(target.buildConfigurationList,
                                              withBuildSettings: testSettings,
                                              inheritingFromConfigurationList: indexerTarget?.buildConfigurationList)
    }

    let sourceFileInfos = ruleEntry.sourceFiles
    let nonARCSourceFileInfos = ruleEntry.nonARCSourceFiles
    if !sourceFileInfos.isEmpty || !nonARCSourceFileInfos.isEmpty {
      var fileReferences = generateFileReferencesForFileInfos(sourceFileInfos)
      fileReferences.appendContentsOf(generateFileReferencesForNonARCFileInfos(nonARCSourceFileInfos))
      let buildPhase = createBuildPhaseForReferences(fileReferences)
      target.buildPhases.append(buildPhase)

      // Add configurations that will allow the tests to be run but not compiled. Note that the
      // config needs to be in the project (in order to pick up the correct defaults for the project
      // type), the host (where it will be set in the xcode scheme) and the test bundle target
      // (where it will be applied when the host is executed with the test action). Xcode does not
      // explicitly produce errors if the target is not found in all three places, but it does
      // behave unexpectedly.
      addTestRunnerBuildConfigurationToBuildConfigurationList(project.buildConfigurationList)
      addTestRunnerBuildConfigurationToBuildConfigurationList(target.buildConfigurationList)
      addTestRunnerBuildConfigurationToBuildConfigurationList(hostTarget.buildConfigurationList)
    }
  }

  // Resolves a BuildLabel to an existing PBXTarget, handling target name collisions.
  private func projectTargetForLabel(label: BuildLabel) -> PBXTarget? {
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
  private func addTestRunnerBuildConfigurationToBuildConfigurationList(list: XCConfigurationList) {

    func createTestConfigForBaseConfig(configurationName: String) {
      let baseConfig = list.getOrCreateBuildConfiguration(configurationName)
      let testConfigName = PBXTargetGenerator.runTestTargetBuildConfigPrefix + configurationName
      let config = list.getOrCreateBuildConfiguration(testConfigName)

      var runTestTargetBuildSettings = baseConfig.buildSettings
      // Prevent compilation invocations from actually compiling files.
      runTestTargetBuildSettings["OTHER_CFLAGS"] = "-help"
      // Prevents linker invocations from attempting to use the .o files which were never generated
      // due to compilation being turned into nop's.
      runTestTargetBuildSettings["OTHER_LDFLAGS"] = "-help"
      // Prevent Xcode from attempting to create a fat binary with lipo from artifacts that were
      // never generated by the linker nop's.
      runTestTargetBuildSettings["ONLY_ACTIVE_ARCH"] = "YES"
      // Prevent Xcode from attempting to generate a dSYM bundle from non-existent linker artifacts.
      runTestTargetBuildSettings["DEBUG_INFORMATION_FORMAT"] = "dwarf"

      config.buildSettings = runTestTargetBuildSettings
    }

    createTestConfigForBaseConfig("Debug")
    createTestConfigForBaseConfig("Release")
  }

  private func createBuildConfigurationsForList(buildConfigurationList: XCConfigurationList,
                                                buildSettings: Dictionary<String, String>) {
    func addPreprocessorDefine(define: String, toConfig config: XCBuildConfiguration) {
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
      }
    }
  }

  private func updateMissingBuildConfigurationsForList(buildConfigurationList: XCConfigurationList,
                                                       withBuildSettings newSettings: Dictionary<String, String>,
                                                       inheritingFromConfigurationList baseConfigurationList: XCConfigurationList? = nil) {
    func mergeDictionary(inout old: [String: String],
                         withContentsOfDictionary new: [String: String]) {
      for (key, value) in new {
        if let _ = old[key] { continue }
        old.updateValue(value, forKey: key)
      }
    }

    for configName in PBXTargetGenerator.buildConfigNames {
      let config = buildConfigurationList.getOrCreateBuildConfiguration(configName)
      mergeDictionary(&config.buildSettings, withContentsOfDictionary: newSettings)

      if let baseSettings = baseConfigurationList?.getOrCreateBuildConfiguration(configName).buildSettings {
        mergeDictionary(&config.buildSettings, withContentsOfDictionary: baseSettings)
      }
    }
  }

  private func indexerNameForRuleEntry(ruleEntry: RuleEntry) -> String {
    let targetName = ruleEntry.label.targetName!
    let hash = ruleEntry.label.hashValue
    return PBXTargetGenerator.IndexerTargetPrefix + "\(targetName)_\(hash)"
  }

  // Creates a PBXSourcesBuildPhase with the given references, optionally applying the given
  // per-file settings to each.
  private func createBuildPhaseForReferences(refs: [PBXReference],
                                             withPerFileSettings settings: [String: String]? = nil) -> PBXSourcesBuildPhase {
    let buildPhase = PBXSourcesBuildPhase()

    for ref in refs {
      if let file = ref as? PBXFileReference {
        // Do not add header files to the build phase.
        guard let fileUTI = file.uti
            where fileUTI.hasPrefix("sourcecode.") && !fileUTI.hasSuffix(".h") else {
          continue
        }
      }

      buildPhase.files.append(PBXBuildFile(fileRef: ref, settings: settings))
    }
    return buildPhase
  }

  private func createBuildTargetForRuleEntry(entry: RuleEntry,
                                             named name: String) throws -> PBXTarget {
    guard let pbxTargetType = entry.pbxTargetType else {
      throw ProjectSerializationError.UnsupportedTargetType(entry.type)
    }
    let target = project.createNativeTarget(name, targetType: pbxTargetType)

    var buildSettings = options.buildSettingsForTarget(name)
    buildSettings["BUILD_PATH"] = entry.label.packageName!
    buildSettings["PRODUCT_NAME"] = name

    // The following settings are simply passed through the environment for use by build scripts.
    buildSettings["BAZEL_TARGET"] = entry.label.value
    if let ipaTarget = entry.implicitIPATarget {
      buildSettings["BAZEL_TARGET_IPA"] = ipaTarget.asFileName
    }

    // TODO(abaire): Remove this hackaround when Bazel generates dSYMs for ios_applications.
    // The build script uses the binary label to find and move the dSYM associated with an
    // ios_application rule. In the future, Bazel should generate dSYMs directly for ios_application
    // rules, at which point this may be removed.
    if let binaryLabel = entry.attributes[.binary] as? String {
      buildSettings["BAZEL_BINARY_TARGET"] = binaryLabel
      let buildLabel = BuildLabel(binaryLabel)
      let binaryPackage = buildLabel.packageName!
      let binaryTarget = buildLabel.targetName!
      let (binaryBundle, _) = PBXProject.productNameAndTypeForTargetName(binaryTarget,
                                                                         targetType: pbxTargetType)
      let dSYMPath =  "\(binaryPackage)/\(binaryBundle).dSYM"
      buildSettings["BAZEL_BINARY_DSYM"] = dSYMPath
    }

    createBuildConfigurationsForList(target.buildConfigurationList, buildSettings: buildSettings)

    if let buildPhase = createBuildPhaseForRuleEntry(entry) {
      target.buildPhases.append(buildPhase)
    }

    if let legacyTarget = bazelCleanScriptTarget {
      target.createDependencyOn(legacyTarget,
                                proxyType: PBXContainerItemProxy.ProxyType.TargetReference,
                                inProject: project,
                                first: true)
    }

    return target
  }

  private func createBuildPhaseForRuleEntry(entry: RuleEntry) -> PBXShellScriptBuildPhase? {
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
        ". \"\(envScriptPath)\"\n" +
        "exec \(commandLine) --install_generated_artifacts"

    let buildPhase = PBXShellScriptBuildPhase(shellScript: shellScript, shellPath: "/bin/bash")
    #if DEBUG
    buildPhase.showEnvVarsInLog = true
    #endif
    return buildPhase
  }

  static func workingDirectoryForPBXGroup(group: PBXGroup) -> String {
    switch group.sourceTree {
      case .SourceRoot:
        if let relativePath = group.path where !relativePath.isEmpty {
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

  /// Constructs a commandline string that will invoke the bazel build script to generate the given
  /// buildLabels (a space-separated set of Bazel target labels) with user options set for the given
  /// optionsTarget.
  private func buildScriptCommandlineForBuildLabels(buildLabels: String,
                                                    withOptionsForTargetLabel target: BuildLabel) -> String {
    var commandLine = "\"\(buildScriptPath)\" " +
        "\(buildLabels) " +
        "--bazel \"\(bazelURL.path!)\" " +
        "--bazel_bin_path \"\(bazelBinPath)\" "

    func addPerConfigValuesForOptions(optionKeys: [TulsiOptionKey], optionFlag: String) {
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
        commandLine += "\(optionFlag) \(concreteValue) -- "
        return
      }

      // Emit a filtered option (--optionName[configName]) for each config.
      for (optionKey, value) in configValues {
        guard let concreteValue = value else { continue }
        let rawName = optionKey.rawValue
        var configKey: String! = nil
        for key in ["Debug", "Fastbuild", "Release"] {
          if rawName.hasSuffix(key) {
            configKey = key
            break
          }
        }
        if configKey == nil {
          assertionFailure("Failed to map option key \(optionKey) to a build config.")
          configKey = "Fastbuild"
        }
        commandLine += "\(optionFlag)[\(configKey)] \(concreteValue) -- "
      }
    }

    addPerConfigValuesForOptions([.BazelBuildOptionsDebug,
                                  .BazelBuildOptionsFastbuild,
                                  .BazelBuildOptionsRelease
                                 ],
                                 optionFlag: "--bazel_options")

    addPerConfigValuesForOptions([.BazelBuildStartupOptionsDebug,
                                  .BazelBuildStartupOptionsFastbuild,
                                  .BazelBuildStartupOptionsRelease
                                 ],
                                 optionFlag: "--bazel_startup_options")

    return commandLine
  }
}
