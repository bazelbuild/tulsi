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

protocol TargetGeneratorProtocol {
  /// Generates file references for the given file paths in the associated project without adding
  /// them to an indexer target. The paths must be relative to the workspace root.
  func generateFileReferencesForFilePaths(paths: [String])

  /// Generates an indexer target for the given Bazel rule and its transitive dependencies, adding
  /// source files whose directories are present in pathFilters.
  func generateIndexerTargetForRuleEntry(ruleEntry: RuleEntry,
                                         ruleEntryMap: [BuildLabel: RuleEntry],
                                         pathFilters: Set<String>)

  /// Generates a legacy target that is added as a dependency of all build targets and invokes
  /// the given script. The build action may be accessed by the script via the ACTION environment
  /// variable.
  func generateBazelCleanTarget(scriptPath: String, workingDirectory: String)

  /// Generates top level build configurations with an optional set of additional include paths.
  func generateTopLevelBuildConfigurations(additionalIncludePaths: Set<String>?)

  /// Generates Xcode build targets that invoke Bazel for the given targets. For test-type rules,
  /// non-compiling source file linkages are created to facilitate indexing of XCTests.
  /// Throws if one of the RuleEntry instances is for an unsupported Bazel target type.
  func generateBuildTargetsForRuleEntries(ruleEntries: [RuleEntry]) throws
}


/// Encapsulates a file that may be a bazel input or output.
struct BazelFileTarget {
  enum TargetType {
    case SourceFile
    case GeneratedFile
  }

  static func fileTargetFromAspectFileInfo(info: AnyObject?) -> BazelFileTarget? {
    guard let info = info as? [String: AnyObject] else { return nil }

    guard let path = info["path"] as? String,
              isSourceFile = info["src"] as? Bool else {
      assertionFailure("Aspect provided a file info dictionary but was missing required keys")
      return nil
    }
    return BazelFileTarget(path: path,
                           targetType: isSourceFile ? .SourceFile : .GeneratedFile)
  }

  /// The path to this file relative to the bazel workspace root or generated files root.
  let path: String

  /// The type of this file.
  let targetType: TargetType

  var fullPath: String {
    switch targetType {
      case .SourceFile:
        return "$(SRCROOT)/\(path)"
      case .GeneratedFile:
        return "bazel-genfiles/\(path)"
    }
  }
}


// Concrete PBXProject target generator.
class BazelTargetGenerator: TargetGeneratorProtocol {

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

  let project: PBXProject
  let buildScriptPath: String
  let envScriptPath: String
  let options: TulsiOptionSet
  let localizedMessageLogger: LocalizedMessageLogger
  let workspaceRootURL: NSURL

  var bazelCleanScriptTarget: PBXLegacyTarget? = nil

  init(bazelURL: NSURL,
       project: PBXProject,
       buildScriptPath: String,
       envScriptPath: String,
       options: TulsiOptionSet,
       localizedMessageLogger: LocalizedMessageLogger,
       workspaceRootURL: NSURL) {
    self.bazelURL = bazelURL
    self.project = project
    self.buildScriptPath = buildScriptPath
    self.envScriptPath = envScriptPath
    self.options = options
    self.localizedMessageLogger = localizedMessageLogger
    self.workspaceRootURL = workspaceRootURL
  }

  // MARK: - TargetGeneratorProtocol

  func generateFileReferencesForFilePaths(paths: [String]) {
    project.getOrCreateGroupsAndFileReferencesForPaths(paths)
  }

  func generateIndexerTargetForRuleEntry(ruleEntry: RuleEntry,
                                         ruleEntryMap: [BuildLabel: RuleEntry],
                                         pathFilters: Set<String>) {

    var sourceDirectory = BazelTargetGenerator.workingDirectoryForPBXGroup(project.mainGroup)
    if sourceDirectory.isEmpty {
      sourceDirectory = "$(SRCROOT)"
    }

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

      if let ruleIncludes = ruleEntry.attributes[.includes] as? [String] {
        let rootedPaths = ruleIncludes.map({"\(sourceDirectory)/\($0)"})
        for include in rootedPaths {
          if !includesSet.contains(include) {
            includes.append(include)
            includesSet.insert(include)
          }
        }
      }

      let sourcePaths = ruleEntry.sourceFiles.filter(includePathInProject)
      var buildPhaseReferences = [PBXReference]()
      if let datamodelDescriptions = ruleEntry.attributes[.datamodels] as? [[String: AnyObject]] {
        var fileTargets = [BazelFileTarget]()
        for description in datamodelDescriptions {
          guard let target = BazelFileTarget.fileTargetFromAspectFileInfo(description) else {
            assertionFailure("Failed to resolve datamodel file description to a file target")
            continue
          }
          fileTargets.append(target)
        }
        let versionedFileReferences = createReferencesForVersionedFileTargets(fileTargets)
        buildPhaseReferences.appendContentsOf(versionedFileReferences as [PBXReference])
      }

      if sourcePaths.isEmpty && buildPhaseReferences.isEmpty {
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
              path = "\(sourceDirectory)/\(path)"
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
      let (_, fileReferences) = project.getOrCreateGroupsAndFileReferencesForPaths(sourcePaths)
      buildPhaseReferences.appendContentsOf(fileReferences as [PBXReference])
      addBuildFileForRule(ruleEntry)
      let buildPhase = createBuildPhaseForReferences(buildPhaseReferences)
      indexingTarget.buildPhases.append(buildPhase)
      addConfigsForIndexingTarget(indexingTarget,
                                  ruleEntry: ruleEntry,
                                  preprocessorDefines: localPreprocessorDefines,
                                  includes: localIncludes,
                                  sourceFilter: includePathInProject)
      return (defines, includes)
    }

    generateIndexerTargetGraphForRuleEntry(ruleEntry)
  }

  func generateBazelCleanTarget(scriptPath: String, workingDirectory: String = "") {
    assert(bazelCleanScriptTarget == nil, "generateBazelCleanTarget may only be called once")

    let bazelPath = bazelURL.path!
    bazelCleanScriptTarget = project.createLegacyTarget(
        BazelTargetGenerator.BazelCleanTarget,
        buildToolPath: "\(scriptPath)",
        buildArguments: "\"\(bazelPath)\"",
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

  func generateTopLevelBuildConfigurations(additionalIncludePaths: Set<String>? = nil) {
    var buildSettings = options.commonBuildSettings()
    buildSettings["ONLY_ACTIVE_ARCH"] = "YES"
    // Fixes an Xcode "Upgrade to recommended settings" warning. Technically the warning only
    // requires this to be added to the Debug build configuration but as code is never compiled
    // anyway it doesn't hurt anything to set it on all configs.
    buildSettings["ENABLE_TESTABILITY"] = "YES"

    // Bazel takes care of signing the generated applications, so Xcode's signing must be disabled.
    buildSettings["CODE_SIGNING_REQUIRED"] = "NO"
    buildSettings["CODE_SIGN_IDENTITY"] = ""

    var sourceDirectory = BazelTargetGenerator.workingDirectoryForPBXGroup(project.mainGroup)
    if sourceDirectory.isEmpty {
      sourceDirectory = "$(SRCROOT)"
    }
    var searchPaths = [sourceDirectory]
    if let additionalIncludePaths = additionalIncludePaths {
      let rootedPaths = additionalIncludePaths.sort().map({"\(sourceDirectory)/\($0)"})
      searchPaths.appendContentsOf(rootedPaths)
    }
    buildSettings["HEADER_SEARCH_PATHS"] = searchPaths.joinWithSeparator(" ")

    createBuildConfigurationsForList(project.buildConfigurationList, buildSettings: buildSettings)
  }

  func generateBuildTargetsForRuleEntries(ruleEntries: [RuleEntry]) throws {
    var testTargetLinkages = [(PBXTarget, String, RuleEntry)]()

    for entry: RuleEntry in ruleEntries {
      let target = try createBuildTargetForRuleEntry(entry)

      if let hostLabelString = entry.attributes[.xctest_app] as? String {
        let hostLabel = BuildLabel(hostLabelString)
        guard let hostTargetName = hostLabel.targetName else {
          throw ProjectSerializationError.GeneralFailure("Test target \(entry.label) has an invalid host label \(hostLabel)")
        }
        testTargetLinkages.append((target, hostTargetName, entry))
      }
    }

    for (testTarget, hostTargetName, entry) in testTargetLinkages {
      updateTestTarget(testTarget,
                       withLinkageToHostTargetNamed: hostTargetName,
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

  /// Adds the given file targets to a versioned group.
  private func createReferencesForVersionedFileTargets(fileTargets: [BazelFileTarget]) -> [XCVersionGroup] {
    var groups = [String: XCVersionGroup]()

    for target in fileTargets {
      let path = target.path as NSString
      let versionedGroupPath = path.stringByDeletingLastPathComponent
      let type = target.path.pbPathUTI ?? ""
      let versionedGroup = project.getOrCreateVersionGroupForPath(versionedGroupPath,
                                                                  versionGroupType: type)
      if groups[versionedGroupPath] == nil {
        groups[versionedGroupPath] = versionedGroup
      }
      let ref = versionedGroup.getOrCreateFileReferenceBySourceTree(.Group,
                                                                    path: path.lastPathComponent)
      ref.isInputFile = target.targetType == .SourceFile
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
                                           sourceFilter: (String) -> Bool) {
    var buildSettings = options.buildSettingsForTarget(target.name)
    buildSettings["PRODUCT_NAME"] = target.productName!

    func addFilteredSourceReference(target: BazelFileTarget) {
      if target.targetType == .SourceFile && sourceFilter(target.path) {
        project.getOrCreateGroupsAndFileReferencesForPaths([target.path])
      }
    }

    if let pchFile = BazelFileTarget.fileTargetFromAspectFileInfo(ruleEntry.attributes[.pch]) {
      buildSettings["GCC_PREFIX_HEADER"] = pchFile.fullPath
      addFilteredSourceReference(pchFile)
    }

    if let preprocessorDefines = preprocessorDefines where !preprocessorDefines.isEmpty {
      let cflagDefines = preprocessorDefines.sort().map({"-D\($0)"})
      buildSettings["OTHER_CFLAGS"] = cflagDefines.joinWithSeparator(" ")
    }

    if let bridgingHeader = BazelFileTarget.fileTargetFromAspectFileInfo(ruleEntry.attributes[.bridging_header]) {
      buildSettings["SWIFT_OBJC_BRIDGING_HEADER"] = bridgingHeader.fullPath
      addFilteredSourceReference(bridgingHeader)
    }

    if !includes.isEmpty {
      buildSettings["HEADER_SEARCH_PATHS"] = "$(inherited) " + includes.joinWithSeparator(" ")
    }

    createBuildConfigurationsForList(target.buildConfigurationList, buildSettings: buildSettings)
  }

  // Updates the build settings and optionally adds a "Compile sources" phase for the given test
  // bundle target.
  private func updateTestTarget(target: PBXTarget,
                                withLinkageToHostTargetNamed hostTargetName: String,
                                ruleEntry: RuleEntry) {
    guard let hostTarget = project.targetByName(hostTargetName) as? PBXNativeTarget else {
      // If the user did not choose to include the host target it won't be available so the
      // linkage can be skipped silently.
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
      let indexerTarget = project.targetByName(indexerNameForRuleEntry(ruleEntry))
      updateMissingBuildConfigurationsForList(target.buildConfigurationList,
                                              withBuildSettings: testSettings,
                                              inheritingFromConfigurationList: indexerTarget?.buildConfigurationList)
    }

    let sourcePaths = ruleEntry.sourceFiles
    if !sourcePaths.isEmpty {
      let (_, fileReferences) = project.getOrCreateGroupsAndFileReferencesForPaths(sourcePaths)
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

  // Adds a dummy build configuration to the given list based off of the Debug config that is
  // used to effectively disable compilation when running XCTests by converting each compile call
  // into a "clang -help" invocation.
  private func addTestRunnerBuildConfigurationToBuildConfigurationList(list: XCConfigurationList) {

    func createTestConfigForBaseConfig(configurationName: String) {
      let baseConfig = list.getOrCreateBuildConfiguration(configurationName)
      let testConfigName = BazelTargetGenerator.runTestTargetBuildConfigPrefix + configurationName
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
    for configName in BazelTargetGenerator.buildConfigNames {
      let config = buildConfigurationList.getOrCreateBuildConfiguration(configName)
      config.buildSettings = buildSettings
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

    for configName in BazelTargetGenerator.buildConfigNames {
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
    return BazelTargetGenerator.IndexerTargetPrefix + "\(targetName)_\(hash)"
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

  private func createBuildTargetForRuleEntry(entry: RuleEntry) throws -> PBXTarget {
    guard let pbxTargetType = entry.pbxTargetType else {
      throw ProjectSerializationError.UnsupportedTargetType(entry.type)
    }

    let name = entry.label.targetName!
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
    let workingDirectory = BazelTargetGenerator.workingDirectoryForPBXGroup(project.mainGroup)
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
        "--bazel \"\(bazelURL.path!)\" "

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
      for (configName, value) in configValues {
        guard let concreteValue = value else { continue }
        commandLine += "\(optionFlag)[\(configName.rawValue)] \(concreteValue) -- "
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
