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


/// Valid Apple Platform Types.
/// See https://docs.bazel.build/versions/master/skylark/lib/apple_common.html#platform_type
public enum PlatformType: String {
  case ios
  case macos
  case tvos
  case watchos

  var buildSettingsDeploymentTarget: String {
    switch self {
    case .ios: return "IPHONEOS_DEPLOYMENT_TARGET"
    case .macos: return "MACOSX_DEPLOYMENT_TARGET"
    case .tvos: return "TVOS_DEPLOYMENT_TARGET"
    case .watchos: return "WATCHOS_DEPLOYMENT_TARGET"
    }
  }

  var simulatorSDK: String {
    switch self {
    case .ios: return "iphonesimulator"
    case .macos: return "macosx"
    case .tvos: return "appletvsimulator"
    case .watchos: return "watchsimulator"
    }
  }

  var deviceSDK: String {
    switch self {
    case .ios: return "iphoneos"
    case .macos: return "macosx"
    case .tvos: return "appletvos"
    case .watchos: return "watchos"
    }
  }

  /// Path of where the test host is expected to be built for each available platform.
  func testHostPath(hostTargetPath: String, hostTargetProductName: String) -> String? {
    switch self {
    case .ios: return "$(BUILT_PRODUCTS_DIR)/\(hostTargetPath)/\(hostTargetProductName)"
    case .macos: return "$(BUILT_PRODUCTS_DIR)/\(hostTargetPath)/Contents/MacOS/\(hostTargetProductName)"
    case .tvos: return "$(BUILT_PRODUCTS_DIR)/\(hostTargetPath)/\(hostTargetProductName)"
    case .watchos: return nil
    }
  }
}

/// Target platform and os version to be used when generating the project.
public struct DeploymentTarget : Equatable {
  let platform: PlatformType
  let osVersion: DottedVersion

  public static func ==(lhs: DeploymentTarget, rhs: DeploymentTarget) -> Bool {
    return lhs.platform == rhs.platform && lhs.osVersion == rhs.osVersion
  }
}

/// Construct to represent a dotted version for comparison. Supports strings of the form "x.x.x".
public struct DottedVersion : Comparable, CustomStringConvertible {
  // TODO(b/68662759): Keep storage limited to a String, instead of maintaining an additional array.

  /// Version represented as an array of Ints, each indice representing position by periods.
  private let storedVersion: [Int]

  /// Version represented as a String.
  private let storedVersionString: String

  /// Character set to separate version information, which is merely a period.
  // TODO(b/31809759): Needed for NSString.components; remove when Tulsi requires Xcode 8.3 minimum.
  static private let dotSet = CharacterSet(charactersIn: ".")

  /// Optional initializer; returns nil if the string passed is not correctly formatted.
  init?(_ versionString: String) {
    var storedVersion = [Int]()

    // Validate to make sure the version is in the expected lexiographic format.
    // TODO(b/31809759): Switch to String.split(...) when Tulsi requires Xcode 8.3 minimum.
    for versionNumber in (versionString as NSString).components(separatedBy: DottedVersion.dotSet) {

      // Allow for empty strings; treat as 0s to maintain ordinal form.
      if versionNumber.isEmpty {
        storedVersion.append(0)
        continue
      }

      // Every string split by periods should be able to be expressed as an integer.
      guard let versionSegment = Int(versionNumber) else {
        print("For versionString of \(versionString), \(versionNumber) is not a number.")
        return nil
      }
      // Construct the array representation as we pass each stage of validation.
      storedVersion.append(versionSegment)
    }

    // Store the array representation.
    self.storedVersion = storedVersion

    // Compose the string representation from the array, removing leading 0s and trailing periods.
    self.storedVersionString = storedVersion.map(String.init).joined(separator: ".")
  }

  /// Outputs version without new lines or extraneous characters, suitable for target names.
  public var description: String {
    return self.storedVersionString
  }

  /// If lengths don't match, extend the short array with "0"s to match longest's length.
  private static func extendToGreatestLength(_ x: [Int], _ y: [Int]) -> (x: [Int], y: [Int]) {

    // Use difference to determine how we need to pad the strings.
    let xDifference = x.count - y.count
    if xDifference == 0 {
      // Return copies of the originals if no height adjustments need to be made.
      return (x, y)
    }
    var xOut = x
    var yOut = y

    if xDifference > 0 {
      // Add 0s to the Y array if the X array was found to be greater.
      for _ in Array(repeating: 0, count: xDifference) {
        yOut.append(0)
      }
    } else {
      // Add 0s to the X array if the Y array was found to be greater.
      for _ in Array(repeating: 0, count: -xDifference) {
        xOut.append(0)
      }
    }
    // Return copies with adjusted heights.
    return (xOut, yOut)
  }

  /// Determine if the strings are equal. Covering that X.X.0 and X.X should be considered equal.
  public static func == (x: DottedVersion, y: DottedVersion) -> Bool {
    // TODO(b/68662759): Optimize to do direct string comparisons without requiring extra storage.

    // Extend lengths to match for doing integer comparison at each location with ==<Element>.
    let versionArrays = extendToGreatestLength(x.storedVersion, y.storedVersion)

    return versionArrays.x == versionArrays.y
  }

  /// Do a lexiographic comparison between versions. To cover the X.X.X case for comparing version.
  public static func < (x: DottedVersion, y: DottedVersion) -> Bool {
    // TODO(b/68662759): Optimize to do direct string comparisons without requiring extra storage.

    // Extend lengths to match for doing integer comparison at each location with zip(...).
    let versionArrays = extendToGreatestLength(x.storedVersion, y.storedVersion)
    for (xVersion, yVersion) in zip(versionArrays.x, versionArrays.y) {

      // At the first inequality of integers, starting from leftmost position...
      if xVersion != yVersion {
        // Return if the leftmost location is less than the rightmost.
        return xVersion < yVersion
      }
    }
    // No inequality was found; return false.
    return false
  }
}
