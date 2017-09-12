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
  let osVersion: String

  public static func ==(lhs: DeploymentTarget, rhs: DeploymentTarget) -> Bool {
    return lhs.platform == rhs.platform && lhs.osVersion == rhs.osVersion
  }
}
