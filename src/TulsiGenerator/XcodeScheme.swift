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


/// Models an xcscheme file, providing information to Xcode on how to build targets.
final class XcodeScheme {
  let version: String
  let target: PBXTarget
  let project: PBXProject
  let projectBundleName: String
  let testActionBuildConfig: String
  let launchActionBuildConfig: String
  let profileActionBuildConfig: String
  let analyzeActionBuildConfig: String
  let archiveActionBuildConfig: String

  let primaryTargetBuildableReference: BuildableReference

  init(target: PBXTarget,
       project: PBXProject,
       projectBundleName: String,
       testActionBuildConfig: String = "Debug",
       launchActionBuildConfig: String = "Debug",
       profileActionBuildConfig: String = "Release",
       analyzeActionBuildConfig: String = "Debug",
       archiveActionBuildConfig: String = "Release",
       version: String = "1.3") {
    self.version = version
    self.target = target
    self.project = project
    self.projectBundleName = projectBundleName
    self.testActionBuildConfig = testActionBuildConfig
    self.launchActionBuildConfig = launchActionBuildConfig
    self.profileActionBuildConfig = profileActionBuildConfig
    self.analyzeActionBuildConfig = analyzeActionBuildConfig
    self.archiveActionBuildConfig = archiveActionBuildConfig

    primaryTargetBuildableReference = BuildableReference(target: target,
                                                         projectBundleName: projectBundleName)
  }

  func toXML() -> NSXMLDocument {
    let rootElement = NSXMLElement(name: "Scheme")
    let rootAttributes = [
        "version": version,
        "LastUpgradeVersion": project.lastUpgradeCheck
    ]
    rootElement.setAttributesWithDictionary(rootAttributes)

    rootElement.addChild(buildAction())
    rootElement.addChild(testAction())
    rootElement.addChild(launchAction())
    rootElement.addChild(profileAction())
    rootElement.addChild(analyzeAction())
    rootElement.addChild(archiveAction())

    return NSXMLDocument(rootElement: rootElement)
  }

  // MARK: - Private methods

  /// Settings for the Xcode "Build" action.
  private func buildAction() -> NSXMLElement {
    let element = NSXMLElement(name: "BuildAction")
    let buildActionAttributes = [
        "parallelizeBuildables": "YES",
        "buildImplicitDependencies": "YES",
    ]
    element.setAttributesWithDictionary(buildActionAttributes)

    let buildActionEntry = NSXMLElement(name: "BuildActionEntry")
    let buildActionEntryAttributes = [
        "buildForTesting": "YES",
        "buildForRunning": "YES",
        "buildForProfiling": "YES",
        "buildForArchiving": "YES",
        "buildForAnalyzing": "YES",
    ]
    buildActionEntry.setAttributesWithDictionary(buildActionEntryAttributes)
    buildActionEntry.addChild(primaryTargetBuildableReference.toXML())

    let buildActionEntries = NSXMLElement(name: "BuildActionEntries")
    buildActionEntries.addChild(buildActionEntry)
    element.addChild(buildActionEntries)

    return element
  }

  /// Settings for the Xcode "Test" action.
  private func testAction() -> NSXMLElement {
    let element = NSXMLElement(name: "TestAction")
    let testActionAttributes = [
      "buildConfiguration": testActionBuildConfig,
      "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
      "selectedLauncherIdentifier": "Xcode.DebuggerFoundation.Launcher.LLDB",
      "shouldUseLaunchSchemeArgsEnv": "YES",
    ]
    element.setAttributesWithDictionary(testActionAttributes)

    let testTargets: [PBXTarget]
    // Hosts should have all of their hosted test targets added as testables and tests should have
    // themselves added.
    let linkedTestTargets = project.linkedTestTargetsForHost(target)
    if linkedTestTargets.isEmpty {
      let host = project.linkedHostForTestTarget(target)
      if host != nil {
        testTargets = [target]
      } else {
        testTargets = []
      }
    } else {
      testTargets = linkedTestTargets
    }

    let testables = NSXMLElement(name: "Testables")
    for testTarget in testTargets {
      let testableReference = NSXMLElement(name: "TestableReference")
      testableReference.setAttributesWithDictionary(["skipped": "NO"])

      let buildableRef = BuildableReference(target: testTarget,
                                            projectBundleName: projectBundleName)
      testableReference.addChild(buildableRef.toXML())
      testables.addChild(testableReference)
    }

    element.addChild(testables)

    let macroExpansion = NSXMLElement(name: "MacroExpansion")
    macroExpansion.addChild(primaryTargetBuildableReference.toXML())
    element.addChild(macroExpansion)
    return element
  }

  /// Settings for the Xcode "Run" action.
  private func launchAction() -> NSXMLElement {
    let element = NSXMLElement(name: "LaunchAction")
    let attributes = [
        "buildConfiguration": launchActionBuildConfig,
        "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
        "selectedLauncherIdentifier": "Xcode.DebuggerFoundation.Launcher.LLDB",
        "launchStyle": "0",
        "useCustomWorkingDirectory": "NO",
        "ignoresPersistentStateOnLaunch": "NO",
        "debugDocumentVersioning": "YES",
        "debugServiceExtension": "internal",
        "allowLocationSimulation": "YES",
    ]
    element.setAttributesWithDictionary(attributes)
    element.addChild(buildableProductRunnable())
    return element
  }

  /// Settings for the Xcode "Profile" action.
  private func profileAction() -> NSXMLElement {
    let element = NSXMLElement(name: "ProfileAction")
    let attributes = [
        "buildConfiguration": profileActionBuildConfig,
        "shouldUseLaunchSchemeArgsEnv": "YES",
        "useCustomWorkingDirectory": "NO",
        "debugDocumentVersioning": "YES",
    ]
    element.setAttributesWithDictionary(attributes)
    element.addChild(buildableProductRunnable())

    return element
  }

  /// Settings for the Xcode "Analyze" action.
  private func analyzeAction() -> NSXMLElement {
    let element = NSXMLElement(name: "AnalyzeAction")
    element.setAttributesWithDictionary(["buildConfiguration": analyzeActionBuildConfig,
                                        ])
    return element
  }

  /// Settings for the Xcode "Archive" action.
  private func archiveAction() -> NSXMLElement {
    let element = NSXMLElement(name: "ArchiveAction")
    element.setAttributesWithDictionary(["buildConfiguration": archiveActionBuildConfig,
                                         "revealArchiveInOrganizer": "YES",
                                        ])
    return element
  }

  /// Container for BuildReference instances that may be run by Xcode.
  private func buildableProductRunnable(runnableDebuggingMode: Bool = false) -> NSXMLElement {
    let element = NSXMLElement(name: "BuildableProductRunnable")
    let debugModeString = runnableDebuggingMode ? "1" : "0"
    element.setAttributesWithDictionary(["runnableDebuggingMode": debugModeString])
    element.addChild(primaryTargetBuildableReference.toXML())
    return element
  }


  /// Information about a PBXTarget that may be built.
  class BuildableReference {
    /// The GID of the target being built.
    let buildableGID: String
    /// The product name of the target being built (e.g., "Application.app").
    let buildableName: String
    /// The name of the target being built.
    let targettName: String
    /// Name of the xcodeproj containing this reference (e.g., "Project.xcodeproj").
    let projectBundleName: String

    convenience init(target: PBXTarget, projectBundleName: String) {
      self.init(buildableGID: target.globalID,
                buildableName: target.productName!,
                targettName: target.name,
                projectBundleName: projectBundleName)
    }

    init(buildableGID: String,
         buildableName: String,
         targettName: String,
         projectBundleName: String) {
      self.buildableGID = buildableGID
      self.buildableName = buildableName
      self.targettName = targettName
      self.projectBundleName = projectBundleName
    }

    func toXML() -> NSXMLElement {
      let element = NSXMLElement(name: "BuildableReference")
      let attributes = [
          "BuildableIdentifier": "primary",
          "BlueprintIdentifier": "\(buildableGID)",
          "BuildableName": "\(buildableName)",
          "BlueprintName": "\(targettName)",
          "ReferencedContainer": "container:\(projectBundleName)"
      ]
      element.setAttributesWithDictionary(attributes)
      return element
    }
  }
}
