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


/// Errors that may be emitted by the various headless generators.
enum HeadlessModeError: Error {
  /// The bazel path must be specified via the commandline.
  case missingBazelPath
  /// The config file path was invalid for the given reason.
  case invalidConfigPath(String)
  /// The config file contents were invalid for the given reason.
  case invalidConfigFileContents(String)
  /// The project file contents were invalid for the given reason.
  case invalidProjectFileContents(String)
  /// The given configuration file requires that an explicit output path be given.
  case explicitOutputOptionRequired
  /// XCode project generation failed for the given reason.
  case generationFailed
  /// The path to the Bazel binary given on the commandline is invalid.
  case invalidBazelPath
  /// A workspace root override was given but references an invalid param.
  case invalidWorkspaceRootOverride
  /// The given workspace root path does not contain a WORKSPACE file.
  case missingWORKSPACEFile(String)
  /// No build targets were specified.
  case missingBuildTargets
  /// The project bundle argument given to the tulsiproj create param is invalid.
  case invalidProjectBundleName
  /// Tulsi failed to identify any valid build targets out of the set of specified targets.
  case bazelTargetProcessingFailed
}
