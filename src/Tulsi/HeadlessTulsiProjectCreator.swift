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

import Cocoa
import TulsiGenerator


/// Provides functionality to generate a Tulsiproj bundle.
struct HeadlessTulsiProjectCreator {

  let arguments: TulsiCommandlineParser.Arguments

  init(arguments: TulsiCommandlineParser.Arguments) {
    self.arguments = arguments
  }

  /// Performs project generation.
  func generate() throws {
    guard let bazelPath = arguments.bazel else {
      throw HeadlessModeError.missingBazelPath
    }
    let defaultFileManager = FileManager.default
    if !defaultFileManager.isExecutableFile(atPath: bazelPath) {
      throw HeadlessModeError.invalidBazelPath
    }

    guard let tulsiprojName = arguments.tulsiprojName else {
      fatalError("HeadlessTulsiProjectCreator invoked without a valid tulsiprojName")
    }

    guard let targets = arguments.buildTargets else {
      throw HeadlessModeError.missingBuildTargets
    }

    guard let outputFolderPath = arguments.outputFolder else {
      throw HeadlessModeError.explicitOutputOptionRequired
    }

    let (projectURL, projectName) = try buildOutputPath(outputFolderPath,
                                                        projectBundleName: tulsiprojName)

    let workspaceRootURL: URL
    if let explicitWorkspaceRoot = arguments.workspaceRootOverride {
      workspaceRootURL = URL(fileURLWithPath: explicitWorkspaceRoot, isDirectory: true)
    } else {
      workspaceRootURL = URL(fileURLWithPath: defaultFileManager.currentDirectoryPath,
                               isDirectory: true)
    }
    let workspaceFileURL = try buildWORKSPACEFileURL(workspaceRootURL)

    TulsiProjectDocument.showAlertsOnErrors = false
    defer {
      TulsiProjectDocument.showAlertsOnErrors = true
    }

    try createTulsiProject(projectName,
                           workspaceFileURL: workspaceFileURL,
                           targets: targets,
                           atURL: projectURL)
  }

  // MARK: - Private methods

  private func createTulsiProject(_ projectName: String,
                                  workspaceFileURL: URL,
                                  targets: [String],
                                  atURL projectURL: URL) throws {
    let document = TulsiProjectDocument()
    document.createNewProject(projectName, workspaceFileURL: workspaceFileURL)

    let bazelPackages = processBazelPackages(document, targets: targets)

    if document.ruleInfos.isEmpty {
      throw HeadlessModeError.bazelTargetProcessingFailed
    }

    if let buildStartupOptions = arguments.buildStartupOptions {
      guard let optionSet = document.optionSet else {
        fatalError("Failed to retrieve option set.")
      }
      optionSet[.BazelBuildStartupOptionsDebug].projectValue = buildStartupOptions
      optionSet[.BazelBuildStartupOptionsRelease].projectValue = buildStartupOptions
    }
    if let buildOptions = arguments.buildOptions {
      guard let optionSet = document.optionSet else {
        fatalError("Failed to retrieve option set.")
      }
      optionSet[.BazelBuildOptionsDebug].projectValue = buildOptions
      optionSet[.BazelBuildOptionsRelease].projectValue = buildOptions
    }

    document.fileURL = projectURL


    try document.writeSafely(to: projectURL,
                             ofType: "com.google.tulsi.project",
                             for: .saveOperation)

    try addDefaultConfig(document,
                         named: projectName,
                         bazelPackages: bazelPackages,
                         targets: targets,
                         additionalSourcePaths: arguments.additionalPathFilters)
  }

  private func processBazelPackages(_ document: TulsiProjectDocument,
                                    targets: [String]) -> Set<String> {
    let bazelPackages = extractBazelPackages(targets)

    // Updating the project's bazelPackages will cause it to go into processing, observe the
    // processing key and block further execution until it is completed.
    let semaphore = DispatchSemaphore(value: 0)
    let observer = document.observe(\.processing, options: .new) { _, change in
      guard change.newValue == false else { return }
      semaphore.signal()
    }
    defer { observer.invalidate() }
    document.bazelPackages = Array(bazelPackages)

    // Wait until processing completes.
    _ = semaphore.wait(timeout: DispatchTime.distantFuture)

    return bazelPackages
  }

  private func addDefaultConfig(_ projectDocument: TulsiProjectDocument,
                                named projectName: String,
                                bazelPackages: Set<String>,
                                targets: [String],
                                additionalSourcePaths: Set<String>? = nil) throws {
    let additionalFilePaths = bazelPackages.map() { "\($0)/BUILD" }
    guard let generatorConfigFolderURL = projectDocument.generatorConfigFolderURL else {
      fatalError("Config folder unexpectedly nil")
    }

    let configDocument = try TulsiGeneratorConfigDocument.makeDocumentWithProjectRuleEntries(projectDocument.ruleInfos,
                                                                                             optionSet: projectDocument.optionSet!,
                                                                                             projectName: projectName,
                                                                                             saveFolderURL: generatorConfigFolderURL,
                                                                                             infoExtractor: projectDocument.infoExtractor,
                                                                                             messageLog: projectDocument,
                                                                                             additionalFilePaths: additionalFilePaths,
                                                                                             bazelURL: projectDocument.bazelURL)
    projectDocument.trackChildConfigDocument(configDocument)

    let targetLabels = Set(targets.map() { BuildLabel($0, normalize: true) })
    // Select appropriate rule infos in the config.
    for info in configDocument.uiRuleInfos {
      info.selected = targetLabels.contains(info.ruleInfo.label)
    }

    // Add a single source path including every possible source.
    configDocument.sourcePaths = [UISourcePath(path: ".", selected: true, recursive: true)]
    if let sourcePaths = additionalSourcePaths {
        // TODO(thomasmarsh@github): This currently assumes that the paths are recursive. A more robust solution
        // would be preferred to handle both recursive and non-recursive cases.
        configDocument.sourcePaths += sourcePaths.map { UISourcePath(path: $0, selected: false, recursive: true) }
    }
    configDocument.headlessSave(projectName)
  }

  private func extractBazelPackages(_ targets: [String]) -> Set<String> {
    var buildFiles = Set<String>()
    for target in targets {
      guard let range = target.range(of: ":"), !range.isEmpty else { continue }
      let package = String(target[..<range.lowerBound])
      buildFiles.insert(package)
    }
    return buildFiles
  }

  /// Processes the "outputFolder" argument, returning the Tulsi project bundle URL and project
  /// name.
  private func buildOutputPath(_ outputFolderPath: String,
                               projectBundleName: String) throws -> (URL, String) {
    let outputFolderURL = URL(fileURLWithPath: outputFolderPath, isDirectory: true)

    guard projectBundleName == (projectBundleName as NSString).lastPathComponent else {
      throw HeadlessModeError.invalidProjectBundleName
    }

    let projectName = (projectBundleName as NSString).deletingPathExtension
    let normalizedProjectBundleName = "\(projectName).\(TulsiProjectDocument.getTulsiBundleExtension())"


    let projectBundleURL = outputFolderURL.appendingPathComponent(normalizedProjectBundleName,
                                                                       isDirectory: false)

    return (projectBundleURL, projectName)
  }

  private func buildWORKSPACEFileURL(_ workspaceRootURL: URL) throws -> URL {

    let workspaceFile = workspaceRootURL.appendingPathComponent("WORKSPACE", isDirectory: false)

    var isDirectory = ObjCBool(false)
    if !FileManager.default.fileExists(atPath: workspaceFile.path,
                                       isDirectory: &isDirectory) || isDirectory.boolValue {
      throw HeadlessModeError.missingWORKSPACEFile(workspaceRootURL.path)
    }
    return workspaceFile
  }
}
