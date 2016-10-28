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

  enum LaunchStyle: String {
    case Normal = "0"
    case AppExtension = "2"
  }

  enum RunnableDebuggingMode: String {
    case Default = "0"
    case WatchOS = "2"
  }

  let version: String
  let target: PBXTarget
  let project: PBXProject
  let projectBundleName: String
  let testActionBuildConfig: String
  let launchActionBuildConfig: String
  let profileActionBuildConfig: String
  let analyzeActionBuildConfig: String
  let archiveActionBuildConfig: String
  let appExtension: Bool
  let launchStyle: LaunchStyle
  let runnableDebuggingMode: RunnableDebuggingMode
  let explicitTests: [PBXTarget]?
  // List of additional targets and their project bundle names that should be built along with the
  // primary target.
  let additionalBuildTargets: [(PBXTarget, String)]?

  let primaryTargetBuildableReference: BuildableReference
  let commandlineArguments: [String]
  let environmentVariables: [String: String]

  init(target: PBXTarget,
       project: PBXProject,
       projectBundleName: String,
       testActionBuildConfig: String = "Debug",
       launchActionBuildConfig: String = "Debug",
       profileActionBuildConfig: String = "Release",
       analyzeActionBuildConfig: String = "Debug",
       archiveActionBuildConfig: String = "Release",
       appExtension: Bool = false,
       launchStyle: LaunchStyle = .Normal,
       runnableDebuggingMode: RunnableDebuggingMode = .Default,
       version: String = "1.3",
       explicitTests: [PBXTarget]? = nil,
       additionalBuildTargets: [(PBXTarget, String)]? = nil,
       commandlineArguments: [String] = [],
       environmentVariables: [String: String] = [:]) {
    self.version = version
    self.target = target
    self.project = project
    self.projectBundleName = projectBundleName
    self.testActionBuildConfig = testActionBuildConfig
    self.launchActionBuildConfig = launchActionBuildConfig
    self.profileActionBuildConfig = profileActionBuildConfig
    self.analyzeActionBuildConfig = analyzeActionBuildConfig
    self.archiveActionBuildConfig = archiveActionBuildConfig
    self.appExtension = appExtension
    self.launchStyle = launchStyle
    self.runnableDebuggingMode = runnableDebuggingMode
    self.explicitTests = explicitTests
    self.additionalBuildTargets = additionalBuildTargets

    self.commandlineArguments = commandlineArguments
    self.environmentVariables = environmentVariables

    primaryTargetBuildableReference = BuildableReference(target: target,
                                                         projectBundleName: projectBundleName)
  }

  func toXML() -> NSXMLDocument {
    let rootElement = NSXMLElement(name: "Scheme")
    var rootAttributes = [
        "version": version,
        "LastUpgradeVersion": project.lastUpgradeCheck
    ]
    if appExtension {
      rootAttributes["wasCreatedForAppExtension"] = "YES"
    }
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
    let parallelizeBuildables: String
    if runnableDebuggingMode == .WatchOS {
      parallelizeBuildables = "NO"
    } else {
      parallelizeBuildables = "YES"
    }
    let buildActionAttributes = [
        "parallelizeBuildables": parallelizeBuildables,
        "buildImplicitDependencies": "YES",
    ]
    element.setAttributesWithDictionary(buildActionAttributes)

    let buildActionEntries = NSXMLElement(name: "BuildActionEntries")

    let buildActionEntryAttributes = [
        "buildForTesting": "YES",
        "buildForRunning": "YES",
        "buildForProfiling": "YES",
        "buildForArchiving": "YES",
        "buildForAnalyzing": "YES",
    ]
    func addBuildActionEntry(buildableReference: BuildableReference) {
      let buildActionEntry = NSXMLElement(name: "BuildActionEntry")
      buildActionEntry.setAttributesWithDictionary(buildActionEntryAttributes)
      buildActionEntry.addChild(buildableReference.toXML())
      buildActionEntries.addChild(buildActionEntry)
    }

    addBuildActionEntry(primaryTargetBuildableReference)
    if let additionalBuildTargets = additionalBuildTargets {
      for (target, bundleName) in additionalBuildTargets {
        addBuildActionEntry(BuildableReference(target: target, projectBundleName: bundleName))
      }
    }

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
    if let explicitTests = explicitTests {
      testTargets = explicitTests
    } else {
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
    var attributes = [
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
    if launchStyle == .AppExtension {
      attributes["selectedDebuggerIdentifier"] = ""
      attributes["selectedLauncherIdentifier"] = "Xcode.IDEFoundation.Launcher.PosixSpawn"
      attributes["launchAutomaticallySubstyle"] = launchStyle.rawValue
    }

    element.setAttributesWithDictionary(attributes)
    if !self.commandlineArguments.isEmpty {
      element.addChild(commandlineArgumentsElement(self.commandlineArguments))
    }
    element.addChild(environmentVariablesElement(self.environmentVariables))
    if launchStyle != .AppExtension {
      element.addChild(buildableProductRunnable(runnableDebuggingMode))
    } else {
      let macroExpansion = NSXMLElement(name: "MacroExpansion")
      macroExpansion.addChild(primaryTargetBuildableReference.toXML())
      element.addChild(macroExpansion)
    }
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
    if launchStyle != .AppExtension {
      element.addChild(buildableProductRunnable(runnableDebuggingMode))
    } else {
      element.addChild(buildableProductRunnable(.Default))
    }

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
  private func buildableProductRunnable(runnableDebuggingMode: RunnableDebuggingMode) -> NSXMLElement {
    let element: NSXMLElement
    var attributes = ["runnableDebuggingMode": runnableDebuggingMode.rawValue]
    switch runnableDebuggingMode {
      case .WatchOS:
        element = NSXMLElement(name: "RemoteRunnable")
        // This is presumably watchOS's equivalent of SpringBoard on iOS and comes from the schemes
        // generated by Xcode 7.
        attributes["BundleIdentifier"] = "com.apple.carousel"
        if let productName = target.productName {
          // This should be CFBundleDisplayName for the target but doesn't seem to actually matter.
          attributes["RemotePath"] = "/\(productName)"
        }

      default:
        element = NSXMLElement(name: "BuildableProductRunnable")
    }
    element.setAttributesWithDictionary(attributes)
    element.addChild(primaryTargetBuildableReference.toXML())
    return element
  }

  /// Generates a CommandlineArguments element based on arguments.
  private func commandlineArgumentsElement(arguments: [String]) -> NSXMLElement {
    let element = NSXMLElement(name: "CommandLineArguments")
    for argument in arguments {
      let argumentElement = NSXMLElement(name: "CommandLineArgument")
      argumentElement.setAttributesAsDictionary([
        "argument": argument,
        "isEnabled": "YES"
      ])
      element.addChild(argumentElement)
    }
    return element
  }

  /// Generates an EnvironmentVariables element based on vars.
  private func environmentVariablesElement(variables: [String: String]) -> NSXMLElement {
    let element = NSXMLElement(name:"EnvironmentVariables")
    for (key, value) in variables {
      let environmentVariable = NSXMLElement(name:"EnvironmentVariable")
      environmentVariable.setAttributesWithDictionary([
        "key": key,
        "value": value,
        "isEnabled": "YES"
      ])
      element.addChild(environmentVariable)
    }
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
