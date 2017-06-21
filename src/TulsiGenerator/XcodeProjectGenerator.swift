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


/// Provides functionality to generate an Xcode project from a TulsiGeneratorConfig.
final class XcodeProjectGenerator {
  enum ProjectGeneratorError: Error {
    /// General Xcode project creation failure with associated debug info.
    case serializationFailed(String)

    /// The given labels failed to resolve to valid targets.
    case labelResolutionFailed(Set<BuildLabel>)
  }

  /// Encapsulates the source paths of various resources (scripts, utilities, etc...) that will be
  /// copied into the generated Xcode project.
  struct ResourceSourcePathURLs {
    let buildScript: URL  // The script to run on "build" actions.
    let cleanScript: URL  // The script to run on "clean" actions.
    let extraBuildScripts: [URL] // Any additional scripts to install into the project bundle.
    let postProcessor: URL  // Binary post processor utility.
    let uiRunnerEntitlements: URL  // Entitlements file template for UI Test runner apps.
    let stubInfoPlist: URL  // Stub Info.plist (needed for Xcode 8).
    let stubIOSAppExInfoPlistTemplate: URL  // Stub Info.plist (needed for app extension targets).
    let stubWatchOS2InfoPlist: URL  // Stub Info.plist (needed for watchOS2 app targets).
    let stubWatchOS2AppExInfoPlist: URL  // Stub Info.plist (needed for watchOS2 appex targets).

    // In order to load tulsi_aspects, Tulsi constructs a Bazel repository inside of the generated
    // Xcode project. Its structure looks like this:
    // ├── Bazel
    // │   ├── WORKSPACE
    // │   └── tulsi
    // │       ├── file1
    // │       └── ...
    // These two items define the content of this repository, including the WORKSPACE file and the
    // "tulsi" package.
    let bazelWorkspaceFile: URL // Stub WORKSPACE file.
    let tulsiPackageFiles: [URL] // Files to copy into the "tulsi" package.
  }

  /// Path relative to PROJECT_FILE_PATH in which Tulsi generated files (scripts, artifacts, etc...)
  /// should be placed.
  private static let TulsiArtifactDirectory = ".tulsi"
  static let ScriptDirectorySubpath = "\(TulsiArtifactDirectory)/Scripts"
  static let BazelDirectorySubpath = "\(TulsiArtifactDirectory)/Bazel"
  static let TulsiPackageName = "tulsi"
  static let UtilDirectorySubpath = "\(TulsiArtifactDirectory)/Utils"
  static let ConfigDirectorySubpath = "\(TulsiArtifactDirectory)/Configs"
  static let ProjectResourcesDirectorySubpath = "\(TulsiArtifactDirectory)/Resources"
  static let ManifestFileSubpath = "\(TulsiArtifactDirectory)/generatorManifest.json"
  private static let BuildScript = "bazel_build.py"
  private static let CleanScript = "bazel_clean.sh"
  private static let WorkspaceFile = "WORKSPACE"
  private static let PostProcessorUtil = "post_processor"
  private static let UIRunnerEntitlements = "XCTRunner.entitlements"
  private static let StubInfoPlistFilename = "StubInfoPlist.plist"
  private static let StubWatchOS2InfoPlistFilename = "StubWatchOS2InfoPlist.plist"
  private static let StubWatchOS2AppExInfoPlistFilename = "StubWatchOS2AppExInfoPlist.plist"

  private let workspaceRootURL: URL
  private let config: TulsiGeneratorConfig
  private let localizedMessageLogger: LocalizedMessageLogger
  private let fileManager: FileManager
  private let workspaceInfoExtractor: BazelWorkspaceInfoExtractorProtocol
  private let resourceURLs: ResourceSourcePathURLs
  private let tulsiVersion: String

  private let pbxTargetGeneratorType: PBXTargetGeneratorProtocol.Type

  /// Exposed for testing. Simply writes the given NSData to the given NSURL.
  /// TODO(dmishe): Use fileManager instance to perform writes, and remove this block.
  var writeDataHandler: (URL, Data) throws -> Void = { (outputFileURL: URL, data: Data) in
    try data.write(to: outputFileURL, options: NSData.WritingOptions.atomic)
  }

  /// Exposed for testing. Returns the current user name.
  var usernameFetcher: () -> String = NSUserName

  /// Exposed for testing. Suppresses writing any preprocessor defines integral to Bazel itself into
  /// the generated project.
  var suppressCompilerDefines = false

  /// Exposed for testing. Instead of writing the real workspace name into the generated project,
  /// write a stub value that will be the same regardless of the execution environment.
  var redactWorkspaceSymlink = false

  /// Exposed for testing. Suppresses creating folders for artifacts that are expected to be
  /// generated by Bazel.
  var suppressGeneratedArtifactFolderCreation = false

  init(workspaceRootURL: URL,
       config: TulsiGeneratorConfig,
       localizedMessageLogger: LocalizedMessageLogger,
       workspaceInfoExtractor: BazelWorkspaceInfoExtractorProtocol,
       resourceURLs: ResourceSourcePathURLs,
       tulsiVersion: String,
       fileManager: FileManager = FileManager.default,
       pbxTargetGeneratorType: PBXTargetGeneratorProtocol.Type = PBXTargetGenerator.self) {
    self.workspaceRootURL = workspaceRootURL
    self.config = config
    self.localizedMessageLogger = localizedMessageLogger
    self.workspaceInfoExtractor = workspaceInfoExtractor
    self.resourceURLs = resourceURLs
    self.tulsiVersion = tulsiVersion
    self.fileManager = fileManager
    self.pbxTargetGeneratorType = pbxTargetGeneratorType
  }

  /// Determines the "best" common SDKROOT for a sequence of RuleEntries.
  static func projectSDKROOT<T>(_ targetRules: T) -> String? where T: Sequence, T.Iterator.Element == RuleEntry {
    var discoveredSDKs = Set<String>()
    for entry in targetRules {
      if let sdkroot = entry.XcodeSDKRoot {
        discoveredSDKs.insert(sdkroot)
      }
    }

    if discoveredSDKs.count == 1 {
      return discoveredSDKs.first!
    }

    if discoveredSDKs.isEmpty {
      // In practice this should not happen since it'd indicate a project that won't be able to
      // build. It is possible that the user is in the process of creating a new project, so
      // rather than fail the generation a default is selected. Since iOS happens to be the best
      // supported type by Bazel at the time of this writing, it is chosen as the default.
      return "iphoneos"
    }

    if discoveredSDKs == ["iphoneos", "watchos"] {
      // Projects containing just an iPhone host and a watchOS app use iphoneos as the project SDK
      // to match Xcode's behavior.
      return "iphoneos"
    }

    // Projects that have a collection that is not mappable to a standard Xcode project simply
    // do not set the SDKROOT. Unfortunately this will cause "My Mac" to be listed as a target
    // device regardless of whether or not the selected build target supports it, but this is
    // a somewhat better user experience when compared to any other device SDK (in which Xcode
    // will display every simulator for that platform regardless of whether or not the build
    // target can be run on them).
    return nil
  }

  /// Generates an Xcode project bundle in the given folder.
  /// NOTE: This may be a long running operation.
  func generateXcodeProjectInFolder(_ outputFolderURL: URL) throws -> URL {
    let generateProfilingToken = localizedMessageLogger.startProfiling("generating_project",
                                                                       context: config.projectName)
    defer { localizedMessageLogger.logProfilingEnd(generateProfilingToken) }
    try resolveConfigReferences()

    let mainGroup = pbxTargetGeneratorType.mainGroupForOutputFolder(outputFolderURL,
                                                                    workspaceRootURL: workspaceRootURL)

    let projectResourcesDirectory = "${PROJECT_FILE_PATH}/\(XcodeProjectGenerator.ProjectResourcesDirectorySubpath)"
    let plistPaths = StubInfoPlistPaths(
      resourcesDirectory: projectResourcesDirectory,
      defaultStub: "\(projectResourcesDirectory)/\(XcodeProjectGenerator.StubInfoPlistFilename)",
      watchOSStub: "\(projectResourcesDirectory)/\(XcodeProjectGenerator.StubWatchOS2InfoPlistFilename)",
      watchOSAppExStub: "\(projectResourcesDirectory)/\(XcodeProjectGenerator.StubWatchOS2AppExInfoPlistFilename)")

    let projectInfo = try buildXcodeProjectWithMainGroup(mainGroup, stubInfoPlistPaths: plistPaths)

    let serializingProgressNotifier = ProgressNotifier(name: SerializingXcodeProject,
                                                       maxValue: 1,
                                                       indeterminate: true)
    let serializer = OpenStepSerializer(rootObject: projectInfo.project,
                                        gidGenerator: ConcreteGIDGenerator())

    let serializingProfileToken = localizedMessageLogger.startProfiling("serializing_project",
                                                                        context: config.projectName)
    guard let serializedXcodeProject = serializer.serialize() else {
      throw ProjectGeneratorError.serializationFailed("OpenStep serialization failed")
    }
    localizedMessageLogger.logProfilingEnd(serializingProfileToken)

    let projectBundleName = config.xcodeProjectFilename
    let projectURL = outputFolderURL.appendingPathComponent(projectBundleName)
    if !createDirectory(projectURL) {
      throw ProjectGeneratorError.serializationFailed("Project directory creation failed")
    }

    let pbxproj = projectURL.appendingPathComponent("project.pbxproj")
    try writeDataHandler(pbxproj, serializedXcodeProject)
    serializingProgressNotifier.incrementValue()

    try installWorkspaceSettings(projectURL)
    try installXcodeSchemesForProjectInfo(projectInfo,
                                          projectURL: projectURL,
                                          projectBundleName: projectBundleName)
    installTulsiScripts(projectURL)
    installTulsiBazelPackage(projectURL)
    installUtilities(projectURL)
    installGeneratorConfig(projectURL)
    installGeneratedProjectResources(projectURL)
    installStubExtensionPlistFiles(projectURL,
                                   rules: projectInfo.buildRuleEntries.filter { $0.pbxTargetType == .AppExtension },
                                   plistPaths: plistPaths)

    let artifactFolderProfileToken = localizedMessageLogger.startProfiling("creating_artifact_folders",
                                                                           context: config.projectName)
    createGeneratedArtifactFolders(mainGroup, relativeTo: projectURL)
    localizedMessageLogger.logProfilingEnd(artifactFolderProfileToken)

    let manifestProfileToken = localizedMessageLogger.startProfiling("writing_manifest",
                                                                     context: config.projectName)

    let manifestFileURL = projectURL.appendingPathComponent(XcodeProjectGenerator.ManifestFileSubpath,
                                                                 isDirectory: false)
    let manifest = GeneratorManifest(localizedMessageLogger: localizedMessageLogger,
                                     pbxProject: projectInfo.project,
                                     intermediateArtifacts: projectInfo.intermediateArtifacts)
    manifest.writeToURL(manifestFileURL)
    localizedMessageLogger.logProfilingEnd(manifestProfileToken)

    return projectURL
  }

  // MARK: - Private methods

  /// Encapsulates information about the results of a buildXcodeProjectWithMainGroup invocation.
  private struct GeneratedProjectInfo {
    /// The newly created PBXProject instance.
    let project: PBXProject

    /// RuleEntry's for which build targets were created. Note that this list may differ from the
    /// set of targets selected by the user as part of the generator config.
    let buildRuleEntries: Set<RuleEntry>

    /// RuleEntry's for test_suite's for which special test schemes should be created.
    let testSuiteRuleEntries: [BuildLabel: RuleEntry]

    /// A mapping of indexer targets by name.
    let indexerTargets: [String: PBXTarget]

    /// Map of target name to any intermediate artifact files.
    let intermediateArtifacts: [String: [String]]
  }

  /// Invokes Bazel to load any missing information in the config file.
  private func resolveConfigReferences() throws {
    let resolvedLabels = loadRuleEntryMap()
    let unresolvedLabels = config.buildTargetLabels.filter() { resolvedLabels[$0] == nil }
    if !unresolvedLabels.isEmpty {
      throw ProjectGeneratorError.labelResolutionFailed(Set<BuildLabel>(unresolvedLabels))
    }
  }

  // Generates a PBXProject and a returns it along with a set of
  private func buildXcodeProjectWithMainGroup(_ mainGroup: PBXGroup, stubInfoPlistPaths: StubInfoPlistPaths) throws -> GeneratedProjectInfo {
    let xcodeProject = PBXProject(name: config.projectName, mainGroup: mainGroup)

    if let enabled = config.options[.SuppressSwiftUpdateCheck].commonValueAsBool, enabled {
      xcodeProject.lastSwiftUpdateCheck = "0710"
    }

    let buildScriptPath = "${PROJECT_FILE_PATH}/\(XcodeProjectGenerator.ScriptDirectorySubpath)/\(XcodeProjectGenerator.BuildScript)"
    let cleanScriptPath = "${PROJECT_FILE_PATH}/\(XcodeProjectGenerator.ScriptDirectorySubpath)/\(XcodeProjectGenerator.CleanScript)"


    let generator = pbxTargetGeneratorType.init(bazelURL: config.bazelURL,
                                                bazelBinPath: workspaceInfoExtractor.bazelBinPath,
                                                project: xcodeProject,
                                                buildScriptPath: buildScriptPath,
                                                stubInfoPlistPaths: stubInfoPlistPaths,
                                                tulsiVersion: tulsiVersion,
                                                options: config.options,
                                                localizedMessageLogger: localizedMessageLogger,
                                                workspaceRootURL: workspaceRootURL,
                                                suppressCompilerDefines: suppressCompilerDefines,
                                                redactWorkspaceSymlink: redactWorkspaceSymlink)

    if let additionalFilePaths = config.additionalFilePaths {
      generator.generateFileReferencesForFilePaths(additionalFilePaths)
    }

    let ruleEntryMap = loadRuleEntryMap()
    var expandedTargetLabels = Set<BuildLabel>()
    var testSuiteRules = [BuildLabel: RuleEntry]()
    // Ideally this should use a generic SequenceType, but Swift 2.2 sometimes crashes in this case.
    // TODO(abaire): Go back to using a generic here when support for Swift 2.2 is removed.
    func expandTargetLabels(_ labels: Set<BuildLabel>) {
      for label in labels {
        guard let ruleEntry = ruleEntryMap[label] else { continue }
        if ruleEntry.type != "test_suite" {
          // Add the RuleEntry itself and any registered extensions.
          expandedTargetLabels.insert(label)
          expandedTargetLabels.formUnion(ruleEntry.extensions)
        } else {
          // Expand the test_suite to its set of tests.
          testSuiteRules[ruleEntry.label] = ruleEntry
          expandTargetLabels(ruleEntry.weakDependencies)
        }
      }
    }
    let buildTargetLabels = Set(config.buildTargetLabels)
    expandTargetLabels(buildTargetLabels)

    var targetRules = Set<RuleEntry>()
    var hostTargetLabels = [BuildLabel: BuildLabel]()

    func profileAction(_ name: String, action: () throws -> Void) rethrows {
      let profilingToken = localizedMessageLogger.startProfiling(name, context: config.projectName)
      try action()
      localizedMessageLogger.logProfilingEnd(profilingToken)
    }

    profileAction("gathering_sources_for_indexers") {
      let progressNotifier = ProgressNotifier(name: GatheringIndexerSources,
                                              maxValue: expandedTargetLabels.count)
      for label in expandedTargetLabels {
        progressNotifier.incrementValue()
        guard let ruleEntry = ruleEntryMap[label] else {
          localizedMessageLogger.error("UnknownTargetRule",
                                       comment: "Failure to look up a Bazel target that was expected to be present. The target label is %1$@",
                                       context: config.projectName,
                                       values: label.value)
          continue
        }
        targetRules.insert(ruleEntry)
        for hostTargetLabel in ruleEntry.linkedTargetLabels {
          hostTargetLabels[hostTargetLabel] = ruleEntry.label
        }
        generator.registerRuleEntryForIndexer(ruleEntry,
                                              ruleEntryMap: ruleEntryMap,
                                              pathFilters: config.pathFilters)
      }
    }
    var indexerTargets = [String: PBXTarget]()
    profileAction("generating_indexers") {
      let progressNotifier = ProgressNotifier(name: GeneratingIndexerTargets,
                                              maxValue: 1,
                                              indeterminate: true)
      indexerTargets = generator.generateIndexerTargets()
      progressNotifier.incrementValue()
    }

    profileAction("adding_buildfiles") {
      let buildfiles = workspaceInfoExtractor.extractBuildfiles(expandedTargetLabels)
      let paths = buildfiles.map() { $0.asFileName! }
      generator.generateFileReferencesForFilePaths(paths, pathFilters: config.pathFilters)
    }

    // Generate RuleEntry's for any test hosts to ensure that selected tests can be executed in
    // Xcode.
    for (hostLabel, testLabel) in hostTargetLabels {
      if config.buildTargetLabels.contains(hostLabel) { continue }
      localizedMessageLogger.warning("GeneratingTestHost",
                                     comment: "Warning to show when a user has selected an XCTest (%2$@) but not its host application (%1$@), resulting in an automated target generation which may have issues.",
                                     context: config.projectName,
                                     values: hostLabel.value, testLabel.value)
      let bazelBinPath = workspaceInfoExtractor.bazelBinPath
      let expectedArtifact = BazelFileInfo(rootPath: bazelBinPath,
                                           subPath: "\(hostLabel.asFileName!).ipa",
                                           isDirectory: false,
                                           targetType: .generatedFile)

      targetRules.insert(RuleEntry(label: hostLabel,
                                   type: "_test_host_",
                                   attributes: [:],
                                   artifacts: [expectedArtifact]))
    }

    let workingDirectory = pbxTargetGeneratorType.workingDirectoryForPBXGroup(mainGroup)
    profileAction("generating_clean_target") {
      generator.generateBazelCleanTarget(cleanScriptPath, workingDirectory: workingDirectory)
    }
    profileAction("generating_top_level_build_configs") {
      var buildSettings = [String: String]()
      if let sdkroot = XcodeProjectGenerator.projectSDKROOT(targetRules) {
        buildSettings = ["SDKROOT": sdkroot]
      }
      // Pull in transitive settings from the top level targets.
      for entry in targetRules {
        if let swiftVersion = entry.attributes[.swift_language_version] as? String {
          buildSettings["SWIFT_VERSION"] = swiftVersion
        }
        if let swiftToolchain = entry.attributes[.swift_toolchain] as? String {
          buildSettings["TOOLCHAINS"] = swiftToolchain
        }
      }

      buildSettings["TULSI_PROJECT"] = config.projectName
      generator.generateTopLevelBuildConfigurations(buildSettings)
    }

    var intermediateArtifacts = [String: [String]]()
    try profileAction("generating_build_targets") {
      intermediateArtifacts = try generator.generateBuildTargetsForRuleEntries(targetRules,
                                                                               ruleEntryMap: ruleEntryMap)
    }

    profileAction("patching_external_repository_references") {
      patchExternalRepositoryReferences(xcodeProject)
    }
    return GeneratedProjectInfo(project: xcodeProject,
                                buildRuleEntries: targetRules,
                                testSuiteRuleEntries: testSuiteRules,
                                indexerTargets: indexerTargets,
                                intermediateArtifacts: intermediateArtifacts)
  }

  // Examines the given xcodeProject, patching any groups that were generated under Bazel's magical
  // "external" container to absolute filesystem references.
  private func patchExternalRepositoryReferences(_ xcodeProject: PBXProject) {
    let mainGroup = xcodeProject.mainGroup
    guard let externalGroup = mainGroup.childGroupsByName["external"] else { return }
    let externalChildren = externalGroup.children as! [PBXGroup]
    for child in externalChildren {
      guard let resolvedPath = workspaceInfoExtractor.resolveExternalReferencePath("external/\(child.path!)") else {
        localizedMessageLogger.warning("ExternalRepositoryResolutionFailed",
                                       comment: "Failed to look up a valid filesystem path for the external repository group given as %1$@. The project should work correctly, but any files inside of the cited group will be unavailable.",
                                       context: config.projectName,
                                       values: child.path!)
        continue
      }

      let newChild = mainGroup.getOrCreateChildGroupByName("@\(child.name)",
                                                           path: resolvedPath,
                                                           sourceTree: .Absolute)
      newChild.serializesName = true
      newChild.migrateChildrenOfGroup(child)
    }
    mainGroup.removeChild(externalGroup)
  }

  private func installWorkspaceSettings(_ projectURL: URL) throws {
    func writeWorkspaceSettings(_ workspaceSettings: [String: Any],
                                toDirectoryAtURL directoryURL: URL,
                                replaceIfExists: Bool = false) throws {

      let workspaceSettingsURL = directoryURL.appendingPathComponent("WorkspaceSettings.xcsettings")
      if (!replaceIfExists && fileManager.fileExists(atPath: workspaceSettingsURL.path)) ||
          !createDirectory(directoryURL) {
        return
      }

      let data = try PropertyListSerialization.data(fromPropertyList: workspaceSettings,
                                                                      format: .xml,
                                                                      options: 0)
      try writeDataHandler(workspaceSettingsURL, data)
    }


    let workspaceSharedDataURL = projectURL.appendingPathComponent("project.xcworkspace/xcshareddata")
    try writeWorkspaceSettings(["IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded": false as AnyObject],
                               toDirectoryAtURL: workspaceSharedDataURL,
                               replaceIfExists: true)

    let workspaceUserDataURL = projectURL.appendingPathComponent("project.xcworkspace/xcuserdata/\(usernameFetcher()).xcuserdatad")
    let perUserWorkspaceSettings: [String: Any] = [
        "LiveSourceIssuesEnabled": true,
        "IssueFilterStyle": "ShowAll",
    ]
    try writeWorkspaceSettings(perUserWorkspaceSettings, toDirectoryAtURL: workspaceUserDataURL)
  }

  private func loadRuleEntryMap() -> [BuildLabel: RuleEntry] {
    return workspaceInfoExtractor.ruleEntriesForLabels(config.buildTargetLabels,
                                                       startupOptions: config.options[.BazelBuildStartupOptionsDebug],
                                                       buildOptions: config.options[.BazelBuildOptionsDebug])
  }

  // Writes Xcode schemes for non-indexer targets if they don't already exist.
  private func installXcodeSchemesForProjectInfo(_ info: GeneratedProjectInfo,
                                                 projectURL: URL,
                                                 projectBundleName: String) throws {
    let xcschemesURL = projectURL.appendingPathComponent("xcshareddata/xcschemes")
    guard createDirectory(xcschemesURL) else { return }

    func targetForLabel(_ label: BuildLabel) -> PBXTarget? {
      if let pbxTarget = info.project.targetByName[label.targetName!] {
        return pbxTarget
      } else if let pbxTarget = info.project.targetByName[label.asFullPBXTargetName!] {
        return pbxTarget
      }
      return nil
    }

    func commandlineArguments(for ruleEntry: RuleEntry) -> [String] {
      return config.options[.CommandlineArguments, ruleEntry.label.value]?.components(separatedBy: " ") ?? []
    }

    func environmentVariables(for ruleEntry: RuleEntry) -> [String: String] {
      var environmentVariables: [String: String] = [:]
      config.options[.EnvironmentVariables, ruleEntry.label.value]?.components(separatedBy: .newlines).forEach() { keyValueString in
        let components = keyValueString.components(separatedBy: "=")
        let key = components.first ?? ""
        if !key.isEmpty {
          let value = components[1..<components.count].joined(separator: "=")
          environmentVariables[key] = value
        }
      }
      return environmentVariables
    }

    func preActionScripts(for ruleEntry: RuleEntry) -> [XcodeActionType: String] {
        var preActionScripts: [XcodeActionType: String] = [:]
        preActionScripts[.BuildAction] = config.options[.BuildActionPreActionScript, ruleEntry.label.value] ?? nil
        preActionScripts[.LaunchAction] = config.options[.LaunchActionPreActionScript, ruleEntry.label.value] ?? nil
        preActionScripts[.TestAction] = config.options[.TestActionPreActionScript, ruleEntry.label.value] ?? nil
        return preActionScripts
    }

    func postActionScripts(for ruleEntry: RuleEntry) -> [XcodeActionType: String] {
        var postActionScripts: [XcodeActionType: String] = [:]
        postActionScripts[.BuildAction] = config.options[.BuildActionPostActionScript, ruleEntry.label.value] ?? nil
        postActionScripts[.LaunchAction] = config.options[.LaunchActionPostActionScript, ruleEntry.label.value] ?? nil
        postActionScripts[.TestAction] = config.options[.TestActionPostActionScript, ruleEntry.label.value] ?? nil
        return postActionScripts
    }
    // Build a map of extension targets to hosts so the hosts may be referenced as additional build
    // requirements. This is necessary for watchOS2 targets (Xcode will spawn an error when
    // attempting to run the app without the scheme linkage, even though Bazel will create the
    // embedded host correctly) and does not harm other extensions.
    var extensionHosts = [BuildLabel: RuleEntry]()
    for entry in info.buildRuleEntries {
      for extensionLabel in entry.extensions {
        extensionHosts[extensionLabel] = entry
      }
    }

    let runTestTargetBuildConfigPrefix = pbxTargetGeneratorType.getRunTestTargetBuildConfigPrefix()
    for entry in info.buildRuleEntries {
      // Generate an XcodeScheme with a test action set up to allow tests to be run without Xcode
      // attempting to compile code.
      let target: PBXNativeTarget
      if let pbxTarget = targetForLabel(entry.label) as? PBXNativeTarget {
        target = pbxTarget
      } else {
        localizedMessageLogger.warning("XCSchemeGenerationFailed",
                                       comment: "Warning shown when generation of an Xcode scheme failed for build target %1$@",
                                       context: config.projectName,
                                       values: entry.label.value)
        continue
      }

      let filename = target.name + ".xcscheme"

      let url = xcschemesURL.appendingPathComponent(filename)
      let appExtension: Bool
      let extensionType: String?
      let launchStyle: XcodeScheme.LaunchStyle
      let runnableDebuggingMode: XcodeScheme.RunnableDebuggingMode
      let targetType = entry.pbxTargetType ?? .Application
      switch targetType {
        case .AppExtension:
          appExtension = true
          launchStyle = .AppExtension
          runnableDebuggingMode = .Default
          extensionType = entry.extensionType

        case .Watch1App, .Watch2App:
          appExtension = false
          extensionType = nil
          launchStyle = .Normal
          runnableDebuggingMode = .Remote

        default:
          appExtension = false
          launchStyle = .Normal
          runnableDebuggingMode = .Default
          extensionType = nil
      }

      var additionalBuildTargets = target.buildActionDependencies.map() {
        ($0, projectBundleName, XcodeScheme.makeBuildActionEntryAttributes())
      }
      if let host = extensionHosts[entry.label] {
        guard let hostTarget = targetForLabel(host.label) else {
          localizedMessageLogger.warning("XCSchemeGenerationFailed",
                                         comment: "Warning shown when generation of an Xcode scheme failed for build target %1$@",
                                         details: "Extension host could not be resolved.",
                                         context: config.projectName,
                                         values: entry.label.value)
          continue
        }
        let hostTargetTuple =
            (hostTarget, projectBundleName, XcodeScheme.makeBuildActionEntryAttributes())
        additionalBuildTargets.append(hostTargetTuple)
      }

      let scheme = XcodeScheme(target: target,
                               project: info.project,
                               projectBundleName: projectBundleName,
                               testActionBuildConfig: runTestTargetBuildConfigPrefix + "Debug",
                               profileActionBuildConfig: runTestTargetBuildConfigPrefix + "Release",
                               appExtension: appExtension,
                               extensionType: extensionType,
                               launchStyle: launchStyle,
                               runnableDebuggingMode: runnableDebuggingMode,
                               additionalBuildTargets: additionalBuildTargets,
                               commandlineArguments: commandlineArguments(for: entry),
                               environmentVariables: environmentVariables(for: entry),
                               preActionScripts:preActionScripts(for: entry),
                               postActionScripts:postActionScripts(for: entry),
                               localizedMessageLogger: localizedMessageLogger)
      let xmlDocument = scheme.toXML()


      let data = xmlDocument.xmlData(withOptions: Int(XMLNode.Options.nodePrettyPrint.rawValue))
      try writeDataHandler(url, data)
    }

    func extractTestTargets(_ testSuite: RuleEntry) -> (Set<PBXTarget>, PBXTarget?) {
      var suiteHostTarget: PBXTarget? = nil
      var validTests = Set<PBXTarget>()
      for testEntryLabel in testSuite.weakDependencies {
        if let recursiveTestSuite = info.testSuiteRuleEntries[testEntryLabel] {
          let (recursiveTests, recursiveSuiteHostTarget) = extractTestTargets(recursiveTestSuite)
          validTests.formUnion(recursiveTests)
          if suiteHostTarget == nil {
            suiteHostTarget = recursiveSuiteHostTarget
          }
          continue
        }

        guard let testTarget = targetForLabel(testEntryLabel) as? PBXNativeTarget else {
          localizedMessageLogger.warning("TestSuiteUsesUnresolvedTarget",
                                         comment: "Warning shown when a test_suite %1$@ refers to a test label %2$@ that was not resolved and will be ignored",
                                         context: config.projectName,
                                         values: testSuite.label.value, testEntryLabel.value)
          continue
        }

        // Non XCTests are treated as standalone applications and cannot be included in an Xcode
        // test scheme.
        if testTarget.productType == .Application {
          localizedMessageLogger.warning("TestSuiteIncludesNonXCTest",
                                         comment: "Warning shown when a non XCTest %1$@ is included in a test suite %2$@ and will be ignored.",
                                         context: config.projectName,
                                         values: testEntryLabel.value, testSuite.label.value)
          continue
        }

        guard let testHostTarget = info.project.linkedHostForTestTarget(testTarget) as? PBXNativeTarget else {
          localizedMessageLogger.warning("TestSuiteTestHostResolutionFailed",
                                         comment: "Warning shown when the test host for a test %1$@ inside test suite %2$@ could not be found. The test will be ignored, but this state is unexpected and should be reported.",
                                         context: config.projectName,
                                         values: testEntryLabel.value, testSuite.label.value)
          continue
        }

        if suiteHostTarget == nil {
          suiteHostTarget = testHostTarget
        }

        validTests.insert(testTarget)
      }

      return (validTests, suiteHostTarget)
    }

    func installSchemeForTestSuite(_ suite: RuleEntry, named suiteName: String) throws {
      let (validTests, extractedHostTarget) = extractTestTargets(suite)
      guard let concreteTarget = extractedHostTarget, !validTests.isEmpty else {
        localizedMessageLogger.warning("TestSuiteHasNoValidTests",
                                       comment: "Warning shown when none of the tests of a test suite %1$@ were able to be resolved.",
                                       context: config.projectName,
                                       values: suite.label.value)
        return
      }

      let filename = suiteName + "_Suite.xcscheme"

      let url = xcschemesURL.appendingPathComponent(filename)
      let scheme = XcodeScheme(target: concreteTarget,
                               project: info.project,
                               projectBundleName: projectBundleName,
                               testActionBuildConfig: runTestTargetBuildConfigPrefix + "Debug",
                               profileActionBuildConfig: runTestTargetBuildConfigPrefix + "Release",
                               explicitTests: Array(validTests),
                               commandlineArguments: commandlineArguments(for: suite),
                               environmentVariables: environmentVariables(for: suite),
                               preActionScripts: preActionScripts(for: suite),
                               postActionScripts:postActionScripts(for: suite),
                               localizedMessageLogger: localizedMessageLogger)
      let xmlDocument = scheme.toXML()


      let data = xmlDocument.xmlData(withOptions: Int(XMLNode.Options.nodePrettyPrint.rawValue))
      try writeDataHandler(url, data)
    }

    var testSuiteSchemes = [String: [RuleEntry]]()
    for (label, entry) in info.testSuiteRuleEntries {
      let shortName = label.targetName!
      if let _ = testSuiteSchemes[shortName] {
        testSuiteSchemes[shortName]!.append(entry)
      } else {
        testSuiteSchemes[shortName] = [entry]
      }
    }
    for testSuites in testSuiteSchemes.values {
      for suite in testSuites {
        let suiteName: String
        if testSuites.count > 1 {
          suiteName = suite.label.asFullPBXTargetName!
        } else {
          suiteName = suite.label.targetName!
        }
        try installSchemeForTestSuite(suite, named: suiteName)
      }
    }
  }

  private func installTulsiScripts(_ projectURL: URL) {

    let scriptDirectoryURL = projectURL.appendingPathComponent(XcodeProjectGenerator.ScriptDirectorySubpath,
                                                                    isDirectory: true)
    if createDirectory(scriptDirectoryURL) {
      let profilingToken = localizedMessageLogger.startProfiling("installing_scripts",
                                                                 context: config.projectName)
      let progressNotifier = ProgressNotifier(name: InstallingScripts, maxValue: 1)
      defer { progressNotifier.incrementValue() }
      localizedMessageLogger.infoMessage("Installing scripts")
      installFiles([(resourceURLs.buildScript, XcodeProjectGenerator.BuildScript),
                    (resourceURLs.cleanScript, XcodeProjectGenerator.CleanScript),
                   ],
                   toDirectory: scriptDirectoryURL)
      installFiles(resourceURLs.extraBuildScripts.map { ($0, $0.lastPathComponent) },
                   toDirectory: scriptDirectoryURL)

      localizedMessageLogger.logProfilingEnd(profilingToken)
    }
  }

  private func installTulsiBazelPackage(_ projectURL: URL) {

    let bazelWorkspaceURL = projectURL.appendingPathComponent(XcodeProjectGenerator.BazelDirectorySubpath,
                                                              isDirectory: true)
    let bazelPackageURL = bazelWorkspaceURL.appendingPathComponent(XcodeProjectGenerator.TulsiPackageName,
                                                                   isDirectory: true)

    if createDirectory(bazelPackageURL) {
      let profilingToken = localizedMessageLogger.startProfiling("installing_package",
                                                                 context: config.projectName)
      let progressNotifier = ProgressNotifier(name: InstallingScripts, maxValue: 1)
      defer { progressNotifier.incrementValue() }
      localizedMessageLogger.infoMessage("Installing Bazel integration package")

      installFiles([(resourceURLs.bazelWorkspaceFile, XcodeProjectGenerator.WorkspaceFile)],
                   toDirectory: bazelWorkspaceURL)
      installFiles(resourceURLs.tulsiPackageFiles.map { ($0, $0.lastPathComponent) },
                   toDirectory: bazelPackageURL)

      localizedMessageLogger.logProfilingEnd(profilingToken)
    }
  }

  private func installUtilities(_ projectURL: URL) {
    let utilDirectoryURL = projectURL.appendingPathComponent(XcodeProjectGenerator.UtilDirectorySubpath,
                                                                  isDirectory: true)
    if createDirectory(utilDirectoryURL) {
      let profilingToken = localizedMessageLogger.startProfiling("installing_utilities",
                                                                 context: config.projectName)
      let progressNotifier = ProgressNotifier(name: InstallingUtilities, maxValue: 1)
      defer { progressNotifier.incrementValue() }
      localizedMessageLogger.infoMessage("Installing utilities")
      installFiles([(resourceURLs.postProcessor, XcodeProjectGenerator.PostProcessorUtil)],
                   toDirectory: utilDirectoryURL)
      localizedMessageLogger.logProfilingEnd(profilingToken)
    }
  }

  private func installGeneratorConfig(_ projectURL: URL) {
    let configDirectoryURL = projectURL.appendingPathComponent(XcodeProjectGenerator.ConfigDirectorySubpath,
                                                                    isDirectory: true)
    guard createDirectory(configDirectoryURL, failSilently: true) else { return }
    let profilingToken = localizedMessageLogger.startProfiling("installing_generator_config",
                                                               context: config.projectName)
    let progressNotifier = ProgressNotifier(name: InstallingGeneratorConfig, maxValue: 1)
    defer { progressNotifier.incrementValue() }
    localizedMessageLogger.infoMessage("Installing generator config")

    let configURL = configDirectoryURL.appendingPathComponent(config.defaultFilename)
    var errorInfo: String? = nil
    do {
      let data = try config.save()
      try writeDataHandler(configURL, data as Data)
    } catch let e as NSError {
      errorInfo = e.localizedDescription
    } catch {
      errorInfo = "Unexpected exception"
    }
    if let errorInfo = errorInfo {
      localizedMessageLogger.syslogMessage("Generator config serialization failed. \(errorInfo)",
                                           context: config.projectName)
      return
    }

    let perUserConfigURL = configDirectoryURL.appendingPathComponent(TulsiGeneratorConfig.perUserFilename)
    errorInfo = nil
    do {
      if let data = try config.savePerUserSettings() {
        try writeDataHandler(perUserConfigURL, data as Data)
      }
    } catch let e as NSError {
      errorInfo = e.localizedDescription
    } catch {
      errorInfo = "Unexpected exception"
    }
    if let errorInfo = errorInfo {
      localizedMessageLogger.syslogMessage("Generator per-user config serialization failed. \(errorInfo)",
                                           context: config.projectName)
      return
    }
    localizedMessageLogger.logProfilingEnd(profilingToken)
  }

  private func installGeneratedProjectResources(_ projectURL: URL) {

    let targetDirectoryURL = projectURL.appendingPathComponent(XcodeProjectGenerator.ProjectResourcesDirectorySubpath,
                                                                    isDirectory: true)
    guard createDirectory(targetDirectoryURL) else { return }
    let profilingToken = localizedMessageLogger.startProfiling("installing_project_resources",
                                                               context: config.projectName)
    localizedMessageLogger.infoMessage("Installing project resources")

    installFiles([(resourceURLs.uiRunnerEntitlements, XcodeProjectGenerator.UIRunnerEntitlements),
                  (resourceURLs.stubInfoPlist, XcodeProjectGenerator.StubInfoPlistFilename),
                  (resourceURLs.stubWatchOS2InfoPlist, XcodeProjectGenerator.StubWatchOS2InfoPlistFilename),
                  (resourceURLs.stubWatchOS2AppExInfoPlist, XcodeProjectGenerator.StubWatchOS2AppExInfoPlistFilename),
                 ],
                 toDirectory: targetDirectoryURL)


    localizedMessageLogger.logProfilingEnd(profilingToken)
  }

  private func installStubExtensionPlistFiles(_ projectURL: URL, rules: [RuleEntry], plistPaths: StubInfoPlistPaths) {
    let targetDirectoryURL = projectURL.appendingPathComponent(XcodeProjectGenerator.ProjectResourcesDirectorySubpath,
                                                               isDirectory: true)
    guard createDirectory(targetDirectoryURL) else { return }
    let profilingToken = localizedMessageLogger.startProfiling("installing_plist_files",
                                                               context: config.projectName)
    localizedMessageLogger.infoMessage("Installing plist files")

    let templatePath = resourceURLs.stubIOSAppExInfoPlistTemplate.path
    guard let plistTemplateData = fileManager.contents(atPath: templatePath) else {
      localizedMessageLogger.error("PlistTemplateNotFound",
                                   comment: LocalizedMessageLogger.bugWorthyComment("Failed to load a plist template"),
                                   context: config.projectName,
                                   values: templatePath)
      return
    }

    let plistTemplate: NSDictionary
    do {
      plistTemplate = try PropertyListSerialization.propertyList(from: plistTemplateData,
                                                                 options: PropertyListSerialization.ReadOptions.mutableContainers,
                                                                 format: nil) as! NSDictionary
    } catch let e {
      localizedMessageLogger.error("PlistDeserializationFailed",
                                   comment: LocalizedMessageLogger.bugWorthyComment("Failed to deserialize a plist template"),
                                   context: config.projectName,
                                   values: resourceURLs.stubIOSAppExInfoPlistTemplate.path, e.localizedDescription)
      return
    }

    for entry in rules {
      plistTemplate.setValue(entry.extensionType, forKeyPath: "NSExtension.NSExtensionPointIdentifier")

      let plistName = plistPaths.plistFilename(forRuleEntry: entry)
      let targetURL = URL(string: plistName, relativeTo: targetDirectoryURL)!

      let data: Data
      do {
        data = try PropertyListSerialization.data(fromPropertyList: plistTemplate, format: .xml, options: 0)
      } catch let e {
        localizedMessageLogger.error("SerializingPlistFailed",
                                     comment: LocalizedMessageLogger.bugWorthyComment("Failed to serialize a plist template"),
                                     context: config.projectName,
                                     values: e.localizedDescription)
        return
      }

      guard fileManager.createFile(atPath: targetURL.path, contents: data, attributes: nil) else {
        localizedMessageLogger.error("WritingPlistFailed",
                                     comment: LocalizedMessageLogger.bugWorthyComment("Failed to write a plist template"),
                                     context: config.projectName,
                                     values: targetURL.path)
        return
      }
    }


    localizedMessageLogger.logProfilingEnd(profilingToken)
  }

  private func createDirectory(_ resourceDirectoryURL: URL, failSilently: Bool = false) -> Bool {
    do {
      try fileManager.createDirectory(at: resourceDirectoryURL,
                                           withIntermediateDirectories: true,
                                           attributes: nil)
    } catch let e as NSError {
      if !failSilently {
        localizedMessageLogger.error("DirectoryCreationFailed",
                                     comment: "Failed to create an important directory. The resulting project will most likely be broken. A bug should be reported.",
                                     context: config.projectName,
                                     values: resourceDirectoryURL as NSURL, e.localizedDescription)
      }
      return false
    }
    return true
  }

  private func installFiles(_ files: [(sourceURL: URL, filename: String)],
                            toDirectory directory: URL, failSilently: Bool = false) {
    for (sourceURL, filename) in files {
      guard let targetURL = URL(string: filename, relativeTo: directory) else {
        if !failSilently {
          localizedMessageLogger.error("CopyingResourceFailed",
                                       comment: "Failed to copy an important file resource, the resulting project will most likely be broken. A bug should be reported.",
                                       context: config.projectName,
                                       values: sourceURL as NSURL, filename, "Target URL is invalid")
        }
        continue
      }

      let errorInfo: String?
      do {
        if fileManager.fileExists(atPath: targetURL.path) {
          try fileManager.removeItem(at: targetURL)
        }
        try fileManager.copyItem(at: sourceURL, to: targetURL)
        errorInfo = nil
      } catch let e as NSError {
        errorInfo = e.localizedDescription
      } catch {
        errorInfo = "Unexpected exception"
      }
      if !failSilently, let errorInfo = errorInfo {
        let targetURLString = targetURL.absoluteString
        localizedMessageLogger.error("CopyingResourceFailed",
                                     comment: "Failed to copy an important file resource, the resulting project will most likely be broken. A bug should be reported.",
                                     context: config.projectName,
                                     values: sourceURL as NSURL, targetURLString, errorInfo)
      }
    }
  }

  private func createGeneratedArtifactFolders(_ mainGroup: PBXGroup, relativeTo path: URL) {
    if suppressGeneratedArtifactFolderCreation { return }
    let generatedArtifacts = mainGroup.allSources.filter() { !$0.isInputFile }

    let generatedFolders = PathTrie()
    for artifact in generatedArtifacts {
      let url = path.appendingPathComponent(artifact.sourceRootRelativePath)
      if let absoluteURL = (url as NSURL).deletingLastPathComponent?.standardizedFileURL {
        generatedFolders.insert(absoluteURL)
      }
    }

    var failedCreates = [String]()
    for url in generatedFolders.leafPaths() {
      if !createDirectory(url, failSilently: true) {
        failedCreates.append(url.path)
      }
    }
    if !failedCreates.isEmpty {
      localizedMessageLogger.warning("CreatingGeneratedArtifactFoldersFailed",
                                     comment: "Failed to create folders for generated artifacts %1$@. The generated Xcode project may need to be reloaded after the first build.",
                                     context: config.projectName,
                                     values: failedCreates.joined(separator: ", "))
    }
  }


  /// Models a node in a path trie.
  private class PathTrie {
    private var root = PathNode(pathElement: "")

    func insert(_ path: URL) {
      let components = path.pathComponents
      guard !components.isEmpty else {
        return
      }
      root.addPath(components)
    }

    func leafPaths() -> [URL] {
      var ret = [URL]()
      for n in root.children.values {
        for path in n.leafPaths() {
          // TODO(dmishe): Swicth to an appropriate URL method.
          guard let url = NSURL.fileURL(withPathComponents: path) else {
            continue
          }
          ret.append(url as URL)
        }
      }
      return ret
    }

    private class PathNode {
      let value: String
      var children = [String: PathNode]()

      init(pathElement: String) {
        self.value = pathElement
      }

      func addPath<T: Collection>(_ pathComponents: T)
                  where T.SubSequence : Collection,
                  T.SubSequence.Iterator.Element == T.Iterator.Element,
                  T.SubSequence.SubSequence == T.SubSequence,
                  T.Iterator.Element == String {
        guard let firstComponent = pathComponents.first else {
          return
        }

        let node: PathNode
        if let existingNode = children[firstComponent] {
          node = existingNode
        } else {
          node = PathNode(pathElement: firstComponent)
          children[firstComponent] = node
        }
        let remaining = pathComponents.dropFirst()
        if !remaining.isEmpty {
          node.addPath(remaining)
        }
      }

      func leafPaths() -> [[String]] {
        if children.isEmpty {
          return [[value]]
        }
        var ret = [[String]]()
        for n in children.values {
          for childPath in n.leafPaths() {
            var subpath = [value]
            subpath.append(contentsOf: childPath)
            ret.append(subpath)
          }
        }
        return ret
      }
    }
  }

  /// Encapsulates high level information about the generated Xcode project intended for use by
  /// external scripts or to aid debugging.
  private class GeneratorManifest {
    /// Version number used to track changes to the format of the generated manifest.
    // This number may be used by consumers of the manifest for compatibility detection.
    private static let ManifestFormatVersion = 3
    /// Suffix for manifest entries whose recursive contents are used by the Xcode project.
    private static let BundleSuffix = "/**"
    private static let NormalBundleTypes = Set(DirExtensionToUTI.values)

    private let localizedMessageLogger: LocalizedMessageLogger
    private let pbxProject: PBXProject
    var fileReferences: Set<String>! = nil
    var targets: [String: [String]]! = nil
    let intermediateArtifacts: [String: [String]]
    var artifacts: Set<String>! = nil

    init(localizedMessageLogger: LocalizedMessageLogger,
         pbxProject: PBXProject,
         intermediateArtifacts: [String: [String]]) {
      self.localizedMessageLogger = localizedMessageLogger
      self.pbxProject = pbxProject
      self.intermediateArtifacts = intermediateArtifacts
    }

    @discardableResult
    func writeToURL(_ outputURL: URL) -> Bool {
      if fileReferences == nil {
        parsePBXProject()
      }
      let dict: [String: Any] = [
          "manifestVersion": GeneratorManifest.ManifestFormatVersion,
          "fileReferences": Array(fileReferences).sorted(),
          "targets": targets,
          "intermediateArtifacts": intermediateArtifacts,
          "artifacts": Array(artifacts).sorted(),
      ]
      do {
        let data = try JSONSerialization.tulsi_newlineTerminatedDataWithJSONObject(dict,
                                                                                   options: .prettyPrinted)
        return ((try? data.write(to: outputURL, options: [.atomic])) != nil)
      } catch let e as NSError {
        localizedMessageLogger.infoMessage("Failed to write manifest file \(outputURL.path): \(e.localizedDescription)")
        return false
      } catch {
        localizedMessageLogger.infoMessage("Failed to write manifest file \(outputURL.path): Unexpected exception")
        return false
      }
    }

    private func parsePBXProject() {
      fileReferences = Set()
      targets = [:]
      artifacts = Set()

      for ref in pbxProject.mainGroup.allSources {
        let artifactPath: String
        // Bundle-type artifacts are appended with BundleSuffix to indicate that the recursive
        // contents of the bundle are needed.
        if ref.fileType == "wrapper.xcdatamodel",
           let parent = ref.parent as? XCVersionGroup,
           parent.versionGroupType == "wrapper.xcdatamodel" {
          artifactPath = parent.sourceRootRelativePath + GeneratorManifest.BundleSuffix
        } else if let refType = ref.fileType,
            GeneratorManifest.NormalBundleTypes.contains(refType) {
          artifactPath = ref.sourceRootRelativePath + GeneratorManifest.BundleSuffix
        } else {
          artifactPath = ref.sourceRootRelativePath
        }

        if ref.isInputFile {
          fileReferences.insert(artifactPath)
        } else {
          artifacts.insert(artifactPath)
        }
      }

      for target in pbxProject.allTargets {
        let buildConfigList = target.buildConfigurationList
        if let debugConfig = buildConfigList.buildConfigurations["Debug"],
           let bazelOutputs = debugConfig.buildSettings["BAZEL_OUTPUTS"] {
          targets[target.name] = bazelOutputs.components(separatedBy: "\n").sorted()
        } else {
          targets[target.name] = []
        }
      }
    }
  }
}
