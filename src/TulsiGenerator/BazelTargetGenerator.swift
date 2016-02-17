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

  /// Generates an indexer target for the given Bazel rule including the given set of source file
  /// paths.
  func generateIndexerTargetForRuleEntry(ruleEntry: RuleEntry, sourcePaths: [String])

  /// Generates a legacy target that is added as a dependency of all build targets and invokes
  /// the given script. The build action may be accessed by the script via the ACTION environment
  /// variable.
  func generateBazelCleanTarget(scriptPath: String, workingDirectory: String)

  /// Generates top level build configurations with an optional set of additional include paths.
  func generateTopLevelBuildConfigurations(additionalIncludePaths: Set<String>?)

  /// Generates Xcode build targets that invoke Bazel for the given targets. For test-type rules
  /// with corresponding entries in sourcePaths, non-compiling source file linkages are created to
  /// facilitate indexing of XCTests.
  /// Throws if one of the RuleEntry instances is for an unsupported Bazel target type.
  func generateBuildTargetsForRuleEntries(ruleEntries: [RuleEntry],
                                          sourcePaths: [RuleEntry: [String]]?) throws
}


/// Encapsulates a file that may be a bazel input or output.
struct BazelFileTarget {
  enum TargetType {
    case SourceFile
    case GeneratedFile
  }

  /// This file's bazel build label.
  let label: BuildLabel

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


protocol LabelResolverProtocol {
  /// Resolves a list of labels to a map of label to file targets.
  func resolveFilesForLabels(labels: [String]) -> [String: BazelFileTarget?]?
}

extension LabelResolverProtocol {
  /// Resolves a single label to a file target.
  func resolveFileForLabel(label: String) -> BazelFileTarget? {
    guard let files = resolveFilesForLabels([label]) else {
      return nil
    }

    return files[label]!
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

  /// A special config used when running XCTests that prevents compilation and linking of any source
  /// files. This allows XCTest bundles to have associated test sources indexed by Xcode but not
  /// compiled when testing (as they're compiled by Bazel and the generated project may be missing
  /// information necessary to compile them anyway).
  // NOTE: This value needs to be kept in sync with the bazel_build script, which maps it to a debug
  // compile rather than the default Fastbuild behavior.
  static let runTestTargetBuildConfigName = "__TulsiTestRunnerConfig_DO_NOT_USE_MANUALLY"

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
  let labelResolver: LabelResolverProtocol
  let options: TulsiOptionSet
  let localizedMessageLogger: LocalizedMessageLogger

  var bazelCleanScriptTarget: PBXLegacyTarget? = nil

  init(bazelURL: NSURL,
       project: PBXProject,
       buildScriptPath: String,
       envScriptPath: String,
       labelResolver: LabelResolverProtocol,
       options: TulsiOptionSet,
       localizedMessageLogger: LocalizedMessageLogger) {
    self.bazelURL = bazelURL
    self.project = project
    self.buildScriptPath = buildScriptPath
    self.envScriptPath = envScriptPath
    self.labelResolver = labelResolver
    self.options = options
    self.localizedMessageLogger = localizedMessageLogger
  }

  // MARK: - TargetGeneratorProtocol

  func generateFileReferencesForFilePaths(paths: [String]) {
    project.getOrCreateGroupsAndFileReferencesForPaths(paths)
  }

  func generateIndexerTargetForRuleEntry(ruleEntry: RuleEntry, sourcePaths: [String]) {
    if sourcePaths.isEmpty { return }

    let targetName = indexerNameForRuleEntry(ruleEntry)
    let indexingTarget = project.createNativeTarget(targetName, targetType: PBXTarget.ProductType.StaticLibrary)

    let (_, fileReferences) = project.getOrCreateGroupsAndFileReferencesForPaths(sourcePaths)
    let (buildPhase, pchFile) = createBuildPhaseForFileReferences(fileReferences)
    indexingTarget.buildPhases.append(buildPhase)

    addConfigsForIndexingTarget(indexingTarget, pchFile: pchFile, ruleEntry: ruleEntry)
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

  func generateBuildTargetsForRuleEntries(ruleEntries: [RuleEntry],
                                          sourcePaths: [RuleEntry: [String]]?) throws {
    var testTargetLinkages = [(PBXTarget, String, RuleEntry)]()

    for entry: RuleEntry in ruleEntries {
      let target = try createBuildTargetForRuleEntry(entry)

      if let hostLabelString = entry.attributes["xctest_app"] {
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
                       sourcePaths: sourcePaths?[entry])
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

  // Adds XCBuildConfigurations to the given indexer PBXTarget.
  private func addConfigsForIndexingTarget(target: PBXTarget, pchFile: PBXFileReference?, ruleEntry: RuleEntry) {
    var buildSettings = options.buildSettingsForTarget(target.name)
    buildSettings["PRODUCT_NAME"] = target.productName!

    if pchFile != nil {
      buildSettings["GCC_PREFIX_HEADER"] = pchFile!.sourceRootRelativePath
    }

    // Look for bridging_header attributes in the rule or its binary dependency (e.g., for
    // ios_application).
    var bridgingHeaderLabel: String? = nil
    if let headerSetting = ruleEntry.attributes["bridging_header"] {
      bridgingHeaderLabel = headerSetting
    } else if let binaryLabel = ruleEntry.attributes["binary"],
              headerSetting = ruleEntry.dependencies[binaryLabel]?.attributes["bridging_header"] {
      bridgingHeaderLabel = headerSetting
    }
    if let concreteBridgingHeaderLabel = bridgingHeaderLabel {
      if let file = labelResolver.resolveFileForLabel(concreteBridgingHeaderLabel) {
        buildSettings["SWIFT_OBJC_BRIDGING_HEADER"] = file.fullPath
      } else {
        localizedMessageLogger.warning("BridgingHeaderResolverFailed",
                                       comment: "bridging_header label cannot be resolved to a file. %1$@ is replaced with the bazel label that was used.",
                                       values: concreteBridgingHeaderLabel)
      }
    }

    createBuildConfigurationsForList(target.buildConfigurationList, buildSettings: buildSettings)
  }

  // Updates the build settings and optionally adds a "Compile sources" phase for the given test
  // bundle target.
  private func updateTestTarget(target: PBXTarget,
                                withLinkageToHostTargetNamed hostTargetName: String,
                                sourcePaths: [String]?) {
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
      updateBuildConfigurationsForList(target.buildConfigurationList,
                                       withBuildSettings: testSettings)
    }

    if let concreteSourcePaths = sourcePaths {
      let (_, fileReferences) = project.getOrCreateGroupsAndFileReferencesForPaths(concreteSourcePaths)
      let (buildPhase, _) = createBuildPhaseForFileReferences(fileReferences)
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
    let baseConfig = list.getOrCreateBuildConfiguration("Debug")
    let config = list.getOrCreateBuildConfiguration(BazelTargetGenerator.runTestTargetBuildConfigName)

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

  private func createBuildConfigurationsForList(buildConfigurationList: XCConfigurationList, buildSettings: Dictionary<String, String>) {
    for configName in BazelTargetGenerator.buildConfigNames {
      let config = buildConfigurationList.getOrCreateBuildConfiguration(configName)
      config.buildSettings = buildSettings
    }
  }

  private func updateBuildConfigurationsForList(buildConfigurationList: XCConfigurationList, withBuildSettings newSettings: Dictionary<String, String>) {
    func updateDictionary(inout old: [String: String], withContentsOfDictionary new: [String: String]) {
      for (key, value) in new {
        old.updateValue(value, forKey: key)
      }
    }

    for configName in BazelTargetGenerator.buildConfigNames {
      let config = buildConfigurationList.getOrCreateBuildConfiguration(configName)
      updateDictionary(&config.buildSettings, withContentsOfDictionary: newSettings)
    }
  }

  private func indexerNameForRuleEntry(ruleEntry: RuleEntry) -> String {
    let targetName = ruleEntry.label.targetName!
    let hash = ruleEntry.label.hashValue
    return BazelTargetGenerator.IndexerTargetPrefix + "\(targetName)_\(hash)"
  }

  // Creates a PBXSourcesBuildPhase with the given files, optionally applying the given per-file
  // settings to each file.
  private func createBuildPhaseForFileReferences(fileRefs: [PBXFileReference],
                                                 withPerFileSettings settings: [String: String]? = nil) -> (PBXSourcesBuildPhase, PBXFileReference?) {
    let buildPhase = PBXSourcesBuildPhase()
    var pchFile: PBXFileReference?

    for file in fileRefs {
      guard let fileExtension = file.fileExtension else {
        continue
      }

      if fileExtension == "pch" {
        assert(pchFile == nil)
        pchFile = file
        continue
      }

      guard let fileUTI = file.uti else {
        continue
      }

      // Add any non-header files to the phase.
      if fileUTI.hasPrefix("sourcecode.") && !fileUTI.hasSuffix(".h") {
        buildPhase.files.append(PBXBuildFile(fileRef: file, settings: settings))
      }
    }
    return (buildPhase, pchFile)
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
        ". \(envScriptPath)\n" +
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
