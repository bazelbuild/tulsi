// Copyright 2017 The Tulsi Authors. All rights reserved.
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

/// This class acts as a data store for all of the RuleEntries that are read by our Aspects. It
/// effectively maps from BuildLabel to RuleEntry, with the caveat that a single BuildLabel may
/// actually have multiple RuleEntries depending on Bazel configuration splits. For example, if an
/// objc_library is depended on by an ios_application with a minimum_os_version of 9 and depended on
/// by an ios_unit_test with a minimum_os_version of 10, then we will actually discover two versions
/// of the same objc_library, one for iOS 10 and the other for iOS 9.
public class RuleEntryMap {
  private var labelToEntries = [BuildLabel: [RuleEntry]]()
  private var allEntries = [RuleEntry]()
  private var labelsWithWarning = Set<BuildLabel>()

  private let localizedMessageLogger: LocalizedMessageLogger?

  init(localizedMessageLogger: LocalizedMessageLogger? = nil) {
    self.localizedMessageLogger = localizedMessageLogger
  }

  init(_ ruleEntryMap: RuleEntryMap) {
    localizedMessageLogger = ruleEntryMap.localizedMessageLogger
    allEntries = ruleEntryMap.allEntries
    labelToEntries = ruleEntryMap.labelToEntries
  }

  public var allRuleEntries: [RuleEntry] {
    return allEntries
  }

  public func insert(ruleEntry: RuleEntry) {
    allEntries.append(ruleEntry)
    labelToEntries[ruleEntry.label, default: []].append(ruleEntry)
  }

  public func hasAnyRuleEntry(withBuildLabel buildLabel: BuildLabel) -> Bool {
    return anyRuleEntry(withBuildLabel: buildLabel) != nil
  }

  /// Returns a RuleEntry from the list of RuleEntries with the specified BuildLabel.
  public func anyRuleEntry(withBuildLabel buildLabel: BuildLabel) -> RuleEntry? {
    guard let ruleEntries = labelToEntries[buildLabel] else {
      return nil
    }
    return ruleEntries.last
  }

  /// Returns a list of RuleEntry with the specified BuildLabel.
  public func ruleEntries(buildLabel: BuildLabel) -> [RuleEntry] {
    guard let ruleEntries = labelToEntries[buildLabel] else {
      return [RuleEntry]()
    }
    return ruleEntries
  }

  /// Returns a RuleEntry which is a dep of the given RuleEntry, matched by configuration.
  public func ruleEntry(buildLabel: BuildLabel, depender: RuleEntry) -> RuleEntry? {
    guard let deploymentTarget = depender.deploymentTarget else {
      localizedMessageLogger?.warning("DependentRuleEntryHasNoDeploymentTarget",
                                      comment: "Error when a RuleEntry with deps does not have a DeploymentTarget. RuleEntry's label is in %1$@, dep's label is in %2$@.",
                                      values: depender.label.description,
                                              buildLabel.description)
      return anyRuleEntry(withBuildLabel: buildLabel)
    }
    return ruleEntry(buildLabel: buildLabel, deploymentTarget: deploymentTarget)
  }

  /// Returns a RuleEntry with the given buildLabel and deploymentTarget.
  public func ruleEntry(buildLabel: BuildLabel, deploymentTarget: DeploymentTarget) -> RuleEntry? {
    guard let ruleEntries = labelToEntries[buildLabel] else {
      return nil
    }
    guard !ruleEntries.isEmpty else {
      return nil
    }

    // If there's only one, we just assume that it's right.
    if ruleEntries.count == 1 {
      return ruleEntries.first
    }

    for ruleEntry in ruleEntries {
      if deploymentTarget == ruleEntry.deploymentTarget {
        return ruleEntry
      }
    }

    if labelsWithWarning.insert(buildLabel).inserted {
      // Must be multiple. Shoot out a warning and return the last.
      localizedMessageLogger?.warning("AmbiguousRuleEntryReference",
                                      comment: "Warning when unable to resolve a RuleEntry for a given DeploymentTarget. RuleEntry's label is in %1$@.",
                                      values: buildLabel.description)
    }

    return ruleEntries.last
  }
}
