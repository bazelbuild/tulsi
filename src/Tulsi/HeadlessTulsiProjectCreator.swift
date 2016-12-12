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

  /// Provides functionality to signal a semaphore when the "processing" key on some object is set
  /// to false.
  private class ProcessingCompletedObserver: NSObject {
    let semaphore: dispatch_semaphore_t

    init(semaphore: dispatch_semaphore_t) {
      self.semaphore = semaphore
    }

    override func observeValueForKeyPath(keyPath: String?,
                                ofObject object: AnyObject?,
                                change: [String : AnyObject]?,
                                context: UnsafeMutablePointer<Void>) {
      if context != &HeadlessTulsiProjectCreator.KVOContext {
        super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        return
      }

      if keyPath == "processing", let newValue = change?[NSKeyValueChangeNewKey] as? Bool {
        if (!newValue) {
          dispatch_semaphore_signal(semaphore)
        }
      }
    }
  }

  let arguments: TulsiCommandlineParser.Arguments

  private static var KVOContext: Int = 0

  init(arguments: TulsiCommandlineParser.Arguments) {
    self.arguments = arguments
  }

  /// Performs project generation.
  func generate() throws {
    guard let bazelPath = arguments.bazel else {
      throw HeadlessModeError.MissingBazelPath
    }
    let defaultFileManager = NSFileManager.defaultManager()
    if !defaultFileManager.isExecutableFileAtPath(bazelPath) {
      throw HeadlessModeError.InvalidBazelPath
    }

    guard let tulsiprojName = arguments.tulsiprojName else {
      fatalError("HeadlessTulsiProjectCreator invoked without a valid tulsiprojName")
    }

    guard let targets = arguments.buildTargets else {
      throw HeadlessModeError.MissingBuildTargets
    }

    guard let outputFolderPath = arguments.outputFolder else {
      throw HeadlessModeError.ExplicitOutputOptionRequired
    }

    let (projectURL, projectName) = try buildOutputPath(outputFolderPath,
                                                        projectBundleName: tulsiprojName)

    let workspaceRootURL: NSURL
    if let explicitWorkspaceRoot = arguments.workspaceRootOverride {
      workspaceRootURL = NSURL(fileURLWithPath: explicitWorkspaceRoot, isDirectory: true)
    } else {
      workspaceRootURL = NSURL(fileURLWithPath: defaultFileManager.currentDirectoryPath,
                               isDirectory: true)
    }
    let workspaceFileURL = try buildWORKSPACEFileURL(workspaceRootURL,
                                                     suppressExistenceCheck: arguments.suppressWORKSPACECheck)

    TulsiProjectDocument.showAlertsOnErrors = false
    TulsiProjectDocument.suppressWORKSPACECheck = arguments.suppressWORKSPACECheck
    defer {
      TulsiProjectDocument.showAlertsOnErrors = true
      TulsiProjectDocument.suppressWORKSPACECheck = false
    }

    try createTulsiProject(projectName,
                           workspaceFileURL: workspaceFileURL,
                           targets: targets,
                           atURL: projectURL)
  }

  // MARK: - Private methods

  private func createTulsiProject(projectName: String,
                                  workspaceFileURL: NSURL,
                                  targets: [String],
                                  atURL projectURL: NSURL) throws {
    let document = TulsiProjectDocument()
    document.createNewProject(projectName, workspaceFileURL: workspaceFileURL)

    let bazelPackages = processBazelPackages(document, targets: targets)

    if document.ruleInfos.isEmpty {
      throw HeadlessModeError.BazelTargetProcessingFailed
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


    try document.writeSafelyToURL(projectURL,
                                  ofType: "com.google.tulsi.project",
                                  forSaveOperation: .SaveOperation)

    try addDefaultConfig(document,
                         named: projectName,
                         bazelPackages: bazelPackages,
                         targets: targets)
  }

  private func processBazelPackages(document: TulsiProjectDocument,
                                    targets: [String]) -> Set<String> {
    let bazelPackages = extractBazelPackages(targets)

    // Updating the project's bazelPackages will cause it to go into processing, observe the
    // processing key and block further execution until it is completed.
    let semaphore = dispatch_semaphore_create(0)
    let observer = ProcessingCompletedObserver(semaphore: semaphore)
    document.addObserver(observer,
                         forKeyPath: "processing",
                         options: .New,
                         context: &HeadlessTulsiProjectCreator.KVOContext)

    document.bazelPackages = Array(bazelPackages)

    // Wait until processing completes.
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)

    document.removeObserver(observer, forKeyPath: "processing")
    return bazelPackages
  }

  private func addDefaultConfig(projectDocument: TulsiProjectDocument,
                                named projectName: String,
                                bazelPackages: Set<String>,
                                targets: [String]) throws {
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
    configDocument.headlessSave(projectName)
  }

  private func extractBazelPackages(targets: [String]) -> Set<String> {
    var buildFiles = Set<String>()
    for target in targets {
      guard let range = target.rangeOfString(":") where !range.isEmpty else { continue }
      let package = target.substringToIndex(range.startIndex)
      buildFiles.insert(package)
    }
    return buildFiles
  }

  /// Processes the "outputFolder" argument, returning the Tulsi project bundle URL and project
  /// name.
  private func buildOutputPath(outputFolderPath: String,
                               projectBundleName: String) throws -> (NSURL, String) {
    let outputFolderURL = NSURL(fileURLWithPath: outputFolderPath, isDirectory: true)

    guard projectBundleName == (projectBundleName as NSString).lastPathComponent else {
      throw HeadlessModeError.InvalidProjectBundleName
    }

    let projectName = (projectBundleName as NSString).stringByDeletingPathExtension
    let normalizedProjectBundleName = "\(projectName).\(TulsiProjectDocument.getTulsiBundleExtension())"

#if swift(>=2.3)
    let projectBundleURL = outputFolderURL.URLByAppendingPathComponent(normalizedProjectBundleName,
                                                                       isDirectory: false)!
#else
    let projectBundleURL = outputFolderURL.URLByAppendingPathComponent(normalizedProjectBundleName,
                                                                       isDirectory: false)
#endif

    return (projectBundleURL, projectName)
  }

  private func buildWORKSPACEFileURL(workspaceRootURL: NSURL,
                                     suppressExistenceCheck: Bool = false) throws -> NSURL {
#if swift(>=2.3)
    let workspaceFile = workspaceRootURL.URLByAppendingPathComponent("WORKSPACE",
                                                                             isDirectory: false)!
#else
    let workspaceFile = workspaceRootURL.URLByAppendingPathComponent("WORKSPACE",
                                                                             isDirectory: false)
#endif

    if !suppressExistenceCheck {
      var isDirectory = ObjCBool(false)
      if !NSFileManager.defaultManager().fileExistsAtPath(workspaceFile.path!,
                                                          isDirectory: &isDirectory) || isDirectory {
        throw HeadlessModeError.MissingWORKSPACEFile(workspaceRootURL.path!)
      }
    }
    return workspaceFile
  }
}
