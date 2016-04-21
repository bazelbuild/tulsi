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
  enum Error: ErrorType {
    /// General Xcode project creation failure with associated debug info.
    case SerializationFailed(String)

    /// The given labels failed to resolve to valid targets.
    case LabelResolutionFailed(Set<BuildLabel>)
  }

  /// Path relative to PROJECT_FILE_PATH in which Tulsi generated files (scripts, artifacts, etc...)
  /// should be placed.
  private static let TulsiArtifactDirectory = ".tulsi"
  static let ScriptDirectorySubpath = "\(TulsiArtifactDirectory)/Scripts"
  static let ConfigDirectorySubpath = "\(TulsiArtifactDirectory)/Configs"
  private static let BuildScript = "bazel_build.py"
  private static let CleanScript = "bazel_clean.sh"
  private static let EnvScript = "bazel_env.sh"

  private let workspaceRootURL: NSURL
  private let config: TulsiGeneratorConfig
  private let localizedMessageLogger: LocalizedMessageLogger
  private let fileManager: NSFileManager
  private let workspaceInfoExtractor: BazelWorkspaceInfoExtractorProtocol
  private let buildScriptURL: NSURL
  private let envScriptURL: NSURL
  private let cleanScriptURL: NSURL

  // Exposed for testing. Simply writes the given NSData to the given NSURL.
  var writeDataHandler: (NSURL, NSData) throws -> Void = { (outputFileURL: NSURL, data: NSData) in
    try data.writeToURL(outputFileURL, options: NSDataWritingOptions.DataWritingAtomic)
  }

  // Exposed for testing. Suppresses writing any preprocessor defines integral to Bazel itself into
  // the generated project.
  var suppressCompilerDefines = false

  init(workspaceRootURL: NSURL,
       config: TulsiGeneratorConfig,
       localizedMessageLogger: LocalizedMessageLogger,
       fileManager: NSFileManager,
       workspaceInfoExtractor: BazelWorkspaceInfoExtractorProtocol,
       buildScriptURL: NSURL,
       envScriptURL: NSURL,
       cleanScriptURL: NSURL) {
    self.workspaceRootURL = workspaceRootURL
    self.config = config
    self.localizedMessageLogger = localizedMessageLogger
    self.fileManager = fileManager
    self.workspaceInfoExtractor = workspaceInfoExtractor
    self.buildScriptURL = buildScriptURL
    self.envScriptURL = envScriptURL
    self.cleanScriptURL = cleanScriptURL
  }

  /// Generates an Xcode project bundle in the given folder.
  /// NOTE: This may be a long running operation.
  func generateXcodeProjectInFolder(outputFolderURL: NSURL) throws -> NSURL {
    try resolveConfigReferences()
    let mainGroup = PBXTargetGenerator.mainGroupForOutputFolder(outputFolderURL,
                                                                workspaceRootURL: workspaceRootURL)
    let (xcodeProject, buildTargetRuleEntries) = try buildXcodeProjectWithMainGroup(mainGroup)

    let serializer = OpenStepSerializer(rootObject: xcodeProject,
                                        gidGenerator: ConcreteGIDGenerator())
    guard let serializedXcodeProject = serializer.serialize() else {
      throw Error.SerializationFailed("OpenStep serialization failed")
    }

    let projectBundleName = config.xcodeProjectFilename
    let projectURL = outputFolderURL.URLByAppendingPathComponent(projectBundleName)
    if !createDirectory(projectURL) {
      throw Error.SerializationFailed("Project directory creation failed")
    }
    let pbxproj = projectURL.URLByAppendingPathComponent("project.pbxproj")
    try writeDataHandler(pbxproj, serializedXcodeProject)

    try installWorkspaceSettings(projectURL)
    try installXcodeSchemesForProject(xcodeProject,
                                      projectURL: projectURL,
                                      projectBundleName: projectBundleName,
                                      targetRuleEntries: buildTargetRuleEntries)
    installTulsiScripts(projectURL)
    installGeneratorConfig(projectURL)

    return projectURL
  }

  // MARK: - Private methods

  /// Invokes Bazel to load any missing information in the config file.
  private func resolveConfigReferences() throws {
    let resolvedLabels = loadRuleEntryMap()
    let unresolvedLabels = config.buildTargetLabels.filter() { resolvedLabels[$0] == nil }
    if !unresolvedLabels.isEmpty {
      throw Error.LabelResolutionFailed(Set<BuildLabel>(unresolvedLabels))
    }
  }

  // Generates a PBXProject and a returns it along with a list of RuleEntries for which build
  // targets were created. Note that this list may differ from the set of targets selected by the
  // user as part of the generator config.
  private func buildXcodeProjectWithMainGroup(mainGroup: PBXGroup) throws -> (PBXProject, [RuleEntry]) {
    let xcodeProject = PBXProject(name: config.projectName, mainGroup: mainGroup)
    if let enabled = config.options[.SuppressSwiftUpdateCheck].commonValueAsBool where enabled {
      xcodeProject.lastSwiftUpdateCheck = "0710"
    }

    let buildScriptPath = "${PROJECT_FILE_PATH}/\(XcodeProjectGenerator.ScriptDirectorySubpath)/\(XcodeProjectGenerator.BuildScript)"
    let cleanScriptPath = "${PROJECT_FILE_PATH}/\(XcodeProjectGenerator.ScriptDirectorySubpath)/\(XcodeProjectGenerator.CleanScript)"
    let envScriptPath = "${PROJECT_FILE_PATH}/\(XcodeProjectGenerator.ScriptDirectorySubpath)/\(XcodeProjectGenerator.EnvScript)"

    let generator = PBXTargetGenerator(bazelURL: config.bazelURL,
                                       bazelBinPath: workspaceInfoExtractor.bazelBinPath,
                                       project: xcodeProject,
                                       buildScriptPath: buildScriptPath,
                                       envScriptPath: envScriptPath,
                                       options: config.options,
                                       localizedMessageLogger: localizedMessageLogger,
                                       workspaceRootURL: workspaceRootURL,
                                       suppressCompilerDefines: suppressCompilerDefines)

    if let additionalFilePaths = config.additionalFilePaths {
      generator.generateFileReferencesForFilePaths(additionalFilePaths)
    }

    let ruleEntryMap = loadRuleEntryMap()
    var expandedTargetLabels = Set<BuildLabel>()
    // Swift 2.1 segfaults when dealing with nested functions using generics of any type, so an
    // unnecessary type conversion from an array to a set is done instead.
    func expandTargetLabels(labels: Set<BuildLabel>) {
      for label in labels {
        guard let ruleEntry = ruleEntryMap[label] else { continue }
        if ruleEntry.type != "test_suite" {
          expandedTargetLabels.insert(label)
        } else {
          expandTargetLabels(ruleEntry.weakDependencies)
        }
      }
    }
    expandTargetLabels(Set<BuildLabel>(config.buildTargetLabels))
    // TODO(abaire): Revert to the generic implementation below when Swift 2.1 support is dropped.
//    func expandTargetLabels<T: SequenceType where T.Generator.Element == BuildLabel>(labels: T) {
//      for label in labels {
//        guard let ruleEntry = ruleEntryMap[label] else { continue }
//        if ruleEntry.type != "test_suite" {
//          expandedTargetLabels.insert(label)
//        } else {
//          expandTargetLabels(ruleEntry.weakDependencies)
//        }
//      }
//    }
//    expandTargetLabels(config.buildTargetLabels)

    var targetRuleEntries = [RuleEntry]()
    var hostTargetLabels = [BuildLabel: BuildLabel]()
    for label in expandedTargetLabels {
      guard let ruleEntry = ruleEntryMap[label] else {
        localizedMessageLogger.error("UnknownTargetRule",
                                     comment: "Failure to look up a Bazel target that was expected to be present. The target label is %1$@",
                                     values: label.value)
        continue
      }
      targetRuleEntries.append(ruleEntry)
      for hostTargetLabel in ruleEntry.linkedTargetLabels {
        hostTargetLabels[hostTargetLabel] = ruleEntry.label
      }
      generator.generateIndexerTargetForRuleEntry(ruleEntry,
                                                  ruleEntryMap: ruleEntryMap,
                                                  pathFilters: config.pathFilters)
    }

    // Generate RuleEntry's for any test hosts to ensure that selected tests can be executed in
    // Xcode.
    for (hostLabel, testLabel) in hostTargetLabels {
      if config.buildTargetLabels.contains(hostLabel) { continue }
      localizedMessageLogger.warning("GeneratingTestHost",
                                     comment: "Warning to show when a user has selected an XCTest (%2$@) but not its host application (%1$@), resulting in an automated target generation which may have issues.",
                                     values: hostLabel.value, testLabel.value)
      targetRuleEntries.append(RuleEntry(label: hostLabel,
                                         type: "_test_host_",
                                         attributes: [:],
                                         sourceFiles: [],
                                         dependencies: Set<String>()))
    }

    let workingDirectory = PBXTargetGenerator.workingDirectoryForPBXGroup(mainGroup)
    generator.generateBazelCleanTarget(cleanScriptPath, workingDirectory: workingDirectory)
    generator.generateTopLevelBuildConfigurations()
    try generator.generateBuildTargetsForRuleEntries(targetRuleEntries)

    return (xcodeProject, targetRuleEntries)
  }

  private func installWorkspaceSettings(projectURL: NSURL) throws {
    // Write workspace options if they don't already exist.
    let workspaceSharedDataURL = projectURL.URLByAppendingPathComponent("project.xcworkspace/xcshareddata")
    let workspaceSettingsURL = workspaceSharedDataURL.URLByAppendingPathComponent("WorkspaceSettings.xcsettings")
    if !fileManager.fileExistsAtPath(workspaceSettingsURL.path!) &&
        createDirectory(workspaceSharedDataURL) {
      let workspaceSettings = ["IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded": false]
      let data = try NSPropertyListSerialization.dataWithPropertyList(workspaceSettings,
                                                                      format: .XMLFormat_v1_0,
                                                                      options: 0)
      try writeDataHandler(workspaceSettingsURL, data)
    }
  }

  private func loadRuleEntryMap() -> [BuildLabel: RuleEntry] {
    return workspaceInfoExtractor.ruleEntriesForLabels(config.buildTargetLabels,
                                                       startupOptions: config.options[.BazelBuildStartupOptionsDebug],
                                                       buildOptions: config.options[.BazelBuildOptionsDebug])
  }

  // Writes Xcode schemes for non-indexer targets if they don't already exist.
  private func installXcodeSchemesForProject(xcodeProject: PBXProject,
                                             projectURL: NSURL,
                                             projectBundleName: String,
                                             targetRuleEntries: [RuleEntry]) throws {
    let xcschemesURL = projectURL.URLByAppendingPathComponent("xcshareddata/xcschemes")
    guard createDirectory(xcschemesURL) else { return }

    for entry in targetRuleEntries {
      // Generate an XcodeScheme with a test action set up to allow tests to be run without Xcode
      // attempting to compile code.
      let target: PBXTarget
      if let pbxTarget = xcodeProject.targetByName[entry.label.targetName!] {
        target = pbxTarget
      } else if let pbxTarget = xcodeProject.targetByName[entry.label.asFullPBXTargetName!] {
        target = pbxTarget
      } else {
        localizedMessageLogger.warning("XCSchemeGenerationFailed",
                                       comment: "Warning shown when generation of an Xcode scheme failed for build target %1$@",
                                       values: entry.label.value)
        continue
      }

      let filename = target.name + ".xcscheme"
      let url = xcschemesURL.URLByAppendingPathComponent(filename)
      if fileManager.fileExistsAtPath(url.path!) {
        continue
      }
      let scheme = XcodeScheme(target: target,
                               project: xcodeProject,
                               projectBundleName: projectBundleName,
                               testActionBuildConfig: PBXTargetGenerator.runTestTargetBuildConfigPrefix + "Debug")
      let xmlDocument = scheme.toXML()

      let data = xmlDocument.XMLDataWithOptions(NSXMLNodePrettyPrint)
      try writeDataHandler(url, data)
    }
  }

  private func installTulsiScripts(projectURL: NSURL) {
    let scriptDirectoryURL = projectURL.URLByAppendingPathComponent(XcodeProjectGenerator.ScriptDirectorySubpath,
                                                                    isDirectory: true)
    if createDirectory(scriptDirectoryURL) {
      localizedMessageLogger.infoMessage("Installing scripts")
      installFiles([(buildScriptURL, XcodeProjectGenerator.BuildScript),
                    (cleanScriptURL, XcodeProjectGenerator.CleanScript),
                    (envScriptURL, XcodeProjectGenerator.EnvScript),
                   ],
                   toDirectory: scriptDirectoryURL)
    }
  }

  private func installGeneratorConfig(projectURL: NSURL) {
    let configDirectoryURL = projectURL.URLByAppendingPathComponent(XcodeProjectGenerator.ConfigDirectorySubpath,
                                                                    isDirectory: true)
    guard createDirectory(configDirectoryURL, failSilently: true) else { return }
    localizedMessageLogger.infoMessage("Installing generator config")

    let configURL = configDirectoryURL.URLByAppendingPathComponent(config.defaultFilename)
    var errorInfo: String? = nil
    do {
      let data = try config.save()
      try writeDataHandler(configURL, data)
    } catch let e as NSError {
      errorInfo = e.localizedDescription
    } catch {
      errorInfo = "Unexpected exception"
    }
    if let errorInfo = errorInfo {
      localizedMessageLogger.infoMessage("Generator config serialization failed. \(errorInfo)")
      return
    }

    let perUserConfigURL = configDirectoryURL.URLByAppendingPathComponent(TulsiGeneratorConfig.perUserFilename)
    errorInfo = nil
    do {
      if let data = try config.savePerUserSettings() {
        try writeDataHandler(perUserConfigURL, data)
      }
    } catch let e as NSError {
      errorInfo = e.localizedDescription
    } catch {
      errorInfo = "Unexpected exception"
    }
    if let errorInfo = errorInfo {
      localizedMessageLogger.infoMessage("Generator per-user config serialization failed. \(errorInfo)")
      return
    }
  }

  private func createDirectory(resourceDirectoryURL: NSURL, failSilently: Bool = false) -> Bool {
    do {
      try fileManager.createDirectoryAtURL(resourceDirectoryURL,
                                           withIntermediateDirectories: true,
                                           attributes: nil)
    } catch let e as NSError {
      if !failSilently {
        localizedMessageLogger.error("DirectoryCreationFailed",
                                     comment: "Failed to create an important directory. The resulting project will most likely be broken. A bug should be reported.",
                                     values: resourceDirectoryURL, e.localizedDescription)
      }
      return false
    }
    return true
  }

  private func installFiles(files: [(sourceURL: NSURL, filename: String)],
                            toDirectory directory: NSURL, failSilently: Bool = false) {
    for (sourceURL, filename) in files {
      guard let targetURL = NSURL(string: filename, relativeToURL: directory) else {
        if !failSilently {
          localizedMessageLogger.error("CopyingResourceFailed",
                                       comment: "Failed to copy an important file resource, the resulting project will most likely be broken. A bug should be reported.",
                                       values: sourceURL, filename, "Target URL is invalid")
        }
        continue
      }

      let errorInfo: String?
      do {
        if fileManager.fileExistsAtPath(targetURL.path!) {
          try fileManager.removeItemAtURL(targetURL)
        }
        try fileManager.copyItemAtURL(sourceURL, toURL: targetURL)
        errorInfo = nil
      } catch let e as NSError {
        errorInfo = e.localizedDescription
      } catch {
        errorInfo = "Unexpected exception"
      }
      if !failSilently, let errorInfo = errorInfo {
        localizedMessageLogger.error("CopyingResourceFailed",
                                     comment: "Failed to copy an important file resource, the resulting project will most likely be broken. A bug should be reported.",
                                     values: sourceURL, targetURL.absoluteString, errorInfo)
      }
    }
  }
}
