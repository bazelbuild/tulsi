// Copyright 2018 The Tulsi Authors. All rights reserved.
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

protocol Pythonable {
  func toPython(_ indentation: String) -> String
}

enum PythonSettings {
  static let doubleIndent: String = "    "
}

extension Dictionary where Key == String, Value: Pythonable {
  func toPython(_ indentation: String) -> String {
    guard !isEmpty else { return "{}" }

    let nestedIndentation = "\(indentation)\(PythonSettings.doubleIndent)"
    var script = "{\n"
    for (key, value) in self {
      script += """
\(nestedIndentation)\(key.toPython(nestedIndentation)): \(value.toPython(nestedIndentation)),

"""
    }
    script += "\(indentation)}"
    return script
  }
}

// TODO(tulsi-team): When we update to Swift 4.2, delete this in favor of conditional conformances.
extension Dictionary where Key == String, Value == [String] {
  func toPython(_ indentation: String) -> String {
    guard !isEmpty else { return "{}" }

    let nestedIndentation = "\(indentation)\(PythonSettings.doubleIndent)"
    var script = "{\n"
    for (key, value) in self {
      script += """
\(nestedIndentation)\(key.toPython(nestedIndentation)): \(value.toPython(nestedIndentation)),

"""
    }
    script += "\(indentation)}"
    return script
  }
}

extension Array where Element: Pythonable {
  func toPython(_ indentation: String) -> String {
    guard !isEmpty else { return "[]" }

    var script = "[\n"
    for value in self {
      script += """
\(indentation)\(PythonSettings.doubleIndent)\(value.toPython("")),

"""
    }
    script += "\(indentation)]"
    return script
  }
}

extension Set where Element: Pythonable {
  func toPython(_ indentation: String) -> String {
    guard !isEmpty else { return "set()" }

    var script = "set([\n"
    for value in self {
      script += """
\(indentation)\(PythonSettings.doubleIndent)\(value.toPython("")),

"""
    }
    script += "\(indentation)])"
    return script
  }
}

extension String: Pythonable {
  func toPython(_ indentation: String) -> String {
    guard self.contains("'") else { return "'\(self)'"}

    let escapedStr = self.replacingOccurrences(of: "'", with: "\\'")
    return "'\(escapedStr)'"
  }
}

class BazelFlags: Equatable, Pythonable {
  public let startup: [String]
  public let build: [String]

  public convenience init(startupStr: String, buildStr: String) {
    self.init(startup: startupStr.components(separatedBy: " "),
              build: buildStr.components(separatedBy: " "))
  }

  public init(startup: [String] = [], build: [String] = []) {
    self.startup = startup.filter { !$0.isEmpty }
    self.build = build.filter { !$0.isEmpty }
  }

  var isEmpty: Bool {
    return startup.isEmpty && build.isEmpty
  }

  func toPython(_ indentation: String) -> String {
    guard !self.isEmpty else { return "BazelFlags()" }

    let nestedIndentation = "\(indentation)\(PythonSettings.doubleIndent)"
    return """
BazelFlags(
\(nestedIndentation)startup = \(startup.toPython(nestedIndentation)),
\(nestedIndentation)build = \(build.toPython(nestedIndentation)),
\(indentation))
"""
  }

  static func ==(lhs: BazelFlags, rhs: BazelFlags) -> Bool {
    return lhs.startup == rhs.startup && lhs.build == rhs.build
  }

  static func +(lhs: BazelFlags, rhs: BazelFlags) -> BazelFlags {
    return BazelFlags(startup: lhs.startup + rhs.startup,
                      build: lhs.build + rhs.build)
  }
}

class BazelFlagsSet: Equatable, Pythonable {
  public let debug: BazelFlags
  public let release: BazelFlags

  public convenience init(startupFlags: [String] = [], buildFlags: [String] = []) {
    self.init(common: BazelFlags(startup: startupFlags, build: buildFlags))
  }

  public init(debug: BazelFlags = BazelFlags(),
              release: BazelFlags = BazelFlags(),
              common: BazelFlags = BazelFlags()) {
    self.debug = debug + common
    self.release = release + common
  }

  var isEmpty: Bool {
    return debug.isEmpty && release.isEmpty
  }

  func getFlags(forDebug: Bool = true) -> BazelFlags {
    return forDebug ? debug : release
  }

  func toPython(_ indentation: String) -> String {
    guard !isEmpty else { return "BazelFlagsSet()" }

    let nestedIndentation = "\(indentation)\(PythonSettings.doubleIndent)"

    // If debug == release we don't need to specify the same flags twice.
    guard debug != release else {
      return """
BazelFlagsSet(
\(nestedIndentation)flags = \(debug.toPython(nestedIndentation)),
\(indentation))
"""
    }

    return """
BazelFlagsSet(
\(nestedIndentation)debug = \(debug.toPython(nestedIndentation)),
\(nestedIndentation)release = \(release.toPython(nestedIndentation)),
\(indentation))
"""
  }

  static func ==(lhs: BazelFlagsSet, rhs: BazelFlagsSet) -> Bool {
    return lhs.debug == rhs.debug && lhs.release == rhs.release
  }

  static func +(lhs: BazelFlagsSet, rhs: BazelFlagsSet) -> BazelFlagsSet {
    return BazelFlagsSet(debug: lhs.debug + rhs.debug,
                         release: lhs.release + rhs.release)
  }
}

class BazelBuildSettings: Pythonable {

  public let bazel: String
  public let bazelExecRoot: String
  public let bazelOutputBase: String

  public let defaultPlatformConfigIdentifier: String
  public let platformConfigurationFlags: [String: [String]]

  public let tulsiCacheAffectingFlagsSet: BazelFlagsSet
  public let tulsiCacheSafeFlagSet: BazelFlagsSet

  public let tulsiSwiftFlagSet: BazelFlagsSet
  public let tulsiNonSwiftFlagSet: BazelFlagsSet

  public let swiftFeatures: [String]
  public let nonSwiftFeatures: [String]

  /// Set of targets which depend (in some fashion) on Swift.
  public let swiftTargets: Set<String>

  public let projDefaultFlagSet: BazelFlagsSet
  public let projTargetFlagSets: [String: BazelFlagsSet]

  public static var platformConfigurationFlagsMap: [String: [String]] {
    return PlatformConfiguration.allValidConfigurations.reduce(into: [String: [String]]()) { (dict, config) in
      dict[config.identifier] = config.bazelFlags
    }
  }

  public init(bazel: String,
              bazelExecRoot: String,
              bazelOutputBase: String,
              defaultPlatformConfigIdentifier: String,
              platformConfigurationFlags: [String: [String]]?,
              swiftTargets: Set<String>,
              tulsiCacheAffectingFlagsSet: BazelFlagsSet,
              tulsiCacheSafeFlagSet: BazelFlagsSet,
              tulsiSwiftFlagSet: BazelFlagsSet,
              tulsiNonSwiftFlagSet: BazelFlagsSet,
              swiftFeatures: [String],
              nonSwiftFeatures: [String],
              projDefaultFlagSet: BazelFlagsSet,
              projTargetFlagSets: [String: BazelFlagsSet]) {
    self.bazel = bazel
    self.bazelExecRoot = bazelExecRoot
    self.bazelOutputBase = bazelOutputBase
    self.defaultPlatformConfigIdentifier = defaultPlatformConfigIdentifier
    self.platformConfigurationFlags = platformConfigurationFlags ?? BazelBuildSettings.platformConfigurationFlagsMap
    self.swiftTargets = swiftTargets
    self.tulsiCacheAffectingFlagsSet = tulsiCacheAffectingFlagsSet
    self.tulsiCacheSafeFlagSet = tulsiCacheSafeFlagSet
    self.tulsiSwiftFlagSet = tulsiSwiftFlagSet
    self.tulsiNonSwiftFlagSet = tulsiNonSwiftFlagSet
    self.swiftFeatures = swiftFeatures
    self.nonSwiftFeatures = nonSwiftFeatures
    self.projDefaultFlagSet = projDefaultFlagSet
    self.projTargetFlagSets = projTargetFlagSets
  }

  public func toPython(_ indentation: String) -> String {
    let nestedIndentation = "\(indentation)\(PythonSettings.doubleIndent)"
    return """
BazelBuildSettings(
\(nestedIndentation)\(bazel.toPython(nestedIndentation)),
\(nestedIndentation)\(bazelExecRoot.toPython(nestedIndentation)),
\(nestedIndentation)\(bazelOutputBase.toPython(nestedIndentation)),
\(nestedIndentation)\(defaultPlatformConfigIdentifier.toPython(nestedIndentation)),
\(nestedIndentation)\(platformConfigurationFlags.toPython(nestedIndentation)),
\(nestedIndentation)\(swiftTargets.toPython(nestedIndentation)),
\(nestedIndentation)\(tulsiCacheAffectingFlagsSet.toPython(nestedIndentation)),
\(nestedIndentation)\(tulsiCacheSafeFlagSet.toPython(nestedIndentation)),
\(nestedIndentation)\(tulsiSwiftFlagSet.toPython(nestedIndentation)),
\(nestedIndentation)\(tulsiNonSwiftFlagSet.toPython(nestedIndentation)),
\(nestedIndentation)\(swiftFeatures.toPython(nestedIndentation)),
\(nestedIndentation)\(nonSwiftFeatures.toPython(nestedIndentation)),
\(nestedIndentation)\(projDefaultFlagSet.toPython(nestedIndentation)),
\(nestedIndentation)\(projTargetFlagSets.toPython(nestedIndentation)),
\(indentation))
"""
  }
}
