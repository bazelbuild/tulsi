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

/// Valid CPU types (for rules_apple Bazel targets).
public enum CPU: String {
  case i386
  case x86_64
  case armv7
  case armv7k
  case arm64
  case arm64e
  case arm64_32
  case sim_arm64

  public static let allCases: [CPU] = [.i386, .x86_64, .armv7, .armv7k, .arm64, .arm64e, .arm64_32, .sim_arm64]

  var isARM: Bool {
    switch self {
    case .i386: return false
    case .x86_64: return false
    case .armv7: return true
    case .armv7k: return true
    case .arm64: return true
    case .arm64e: return true
    case .arm64_32: return true
    case .sim_arm64: return true
    }
  }

  var watchCPU: CPU {
    if PlatformConfiguration.use64BitWatchSimulator {
      return isARM ? .armv7k : .x86_64
    } else {
      return isARM ? .armv7k : .i386
    }
  }
}

/// Represents a (PlatformType, AppleCPU) pair.
public struct PlatformConfiguration {

  /// Xcode 12 uses x86_64 64bit watch simulators in contrast to i386 32bit watch simulators
  /// used in Xcode 11 and older. 32bit apps cannot run on 64bit simulators and vice versa.
  /// Tulsi sets the CPU configuration at project generation time so we cannot dynamically
  /// swap between the two. Instead, Tulsi has an option 'Use64BitWatchSimulator' in the project
  /// config that allows the user to specify whether Tulsi should assume 64bit watch simulators.
  /// This value should be set to the value read from the Tulsi config and should be set as
  /// soon as the TulsiOption's are extracted to ensure the proper architecture is used
  /// everywhere.
  public static var use64BitWatchSimulator = false

  public let platform: PlatformType
  public let cpu: CPU

  /// Default to iOS 64-bit simulator.
  public static let defaultConfiguration = PlatformConfiguration(platform: .ios, cpu: .x86_64)

  /// Returns all valid PlatformConfiguration identifiers.
  public static var allValidConfigurations: [PlatformConfiguration] {
    var platforms = [PlatformConfiguration]()
    for platformType in PlatformType.allCases {
      for cpu in platformType.validCPUs {
        platforms.append(PlatformConfiguration(platform: platformType, cpu: cpu))
      }
    }
    return platforms
  }

  public init(platform: PlatformType, cpu: CPU) {
    self.platform = platform
    self.cpu = cpu
  }

  /// Initialize based on an identifier; will only succeed if the identifier is present in
  /// PlatformConfiguration.allPlatformCPUIdentifiers (which checks for combination validity).
  public init?(identifier: String) {
    for validConfiguration in PlatformConfiguration.allValidConfigurations {
      if validConfiguration.identifier == identifier {
        self.platform = validConfiguration.platform
        self.cpu = validConfiguration.cpu
        return
      }
    }
    return nil
  }

  /// Human readable identifier for this (PlatformType, CPU) pair.
  var identifier: String {
    return "\(platform.bazelPlatform)_\(cpu.rawValue)"
  }
}

/// Valid Apple Platform Types.
/// See https://docs.bazel.build/versions/master/skylark/lib/apple_common.html#platform_type
public enum PlatformType: String {
  case ios
  case macos
  case tvos
  case watchos

  public static let allCases: [PlatformType] = [.ios, .macos, .tvos, .watchos]

  var validCPUs: Set<CPU> {
    switch self {
    case .ios: return [.i386, .x86_64, .armv7, .arm64, .arm64e, .sim_arm64]
    case .macos: return  [.x86_64, .arm64, .arm64e]
    case .tvos: return [.x86_64, .arm64]
    case .watchos: return [.i386, .x86_64, .armv7k, .arm64_32]
    }
  }

  var bazelCPUPlatform: String {
    switch self {
    case .macos: return "darwin"
    default: return bazelPlatform
    }
  }

  var bazelPlatform: String {
    return rawValue
  }

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

  var userString: String {
    switch self {
    case .ios: return "iOS"
    case .macos: return "macOS"
    case .tvos: return "tvOS"
    case .watchos: return "watchOS"
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
  let osVersion: String

  public static func ==(lhs: DeploymentTarget, rhs: DeploymentTarget) -> Bool {
    return lhs.platform == rhs.platform && lhs.osVersion == rhs.osVersion
  }
}
