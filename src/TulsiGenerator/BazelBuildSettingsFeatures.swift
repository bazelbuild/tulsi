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

/// Returns the configuration flags required to build a Bazel target and all of its dependencies
/// with the specified PlatformType and AppleCPU.
///
///  - Every platform has the --apple_platform_type flag set
///  - macOS and iOS use the base --cpu flag, while tvOS and watchOS use the  --tvos_cpus and
///    --watchos_cpus respectively
///  - iOS also sets the --watchos_cpus flag (as it can contain a watchOS app embedded)
extension PlatformConfiguration {
  public var bazelFlags: [String] {
    var flags = ["--apple_platform_type=\(platform.bazelPlatform)"]

    switch platform {
    case .ios, .macos:
      flags.append("--cpu=\(platform.bazelCPUPlatform)_\(cpu.rawValue)")
    case .tvos:
      flags.append("--\(platform.bazelCPUPlatform)_cpus=\(cpu.rawValue)")
    case .watchos:
      flags.append("--\(platform.bazelCPUPlatform)_cpus=\(cpu.watchCPU.rawValue)")
    }

    if case .ios = platform {
      flags.append("--\(PlatformType.watchos.bazelCPUPlatform)_cpus=\(cpu.watchCPU.rawValue)")
    }

    return flags
  }
}

public class BazelBuildSettingsFeatures {
  public static func enabledFeatures(options: TulsiOptionSet) -> Set<BazelSettingFeature> {
    // A normalized path for -fdebug-prefix-map exists for keeping all debug information as built by
    // Clang consistent for the sake of caching within a distributed build system.
    //
    // This is handled through a wrapped_clang feature flag via the CROSSTOOL.
    //
    // The use of this flag does not affect any sources built by swiftc. At present time, all Swift
    // compiled sources will be built with uncacheable, absolute paths, as the Swift compiler does
    // not present an easy means of similarly normalizing all debug information.
    return [.DebugPathNormalization]
  }
}
