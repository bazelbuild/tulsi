# Copyright 2017 The Tulsi Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Paths for Tulsi aspects.

Provides a small set of variables to be referenced for aspect dependencies.
"""

load(
    "@build_bazel_rules_apple//apple:providers.bzl",
    _AppleBinaryInfo = "AppleBinaryInfo",
    _AppleBundleInfo = "AppleBundleInfo",
    _IosApplicationBundleInfo = "IosApplicationBundleInfo",
    _IosExtensionBundleInfo = "IosExtensionBundleInfo",
)
load(
    "@build_bazel_rules_apple//apple/testing:apple_test_rules.bzl",
    _AppleTestInfo = "AppleTestInfo",
)
load(
    "@build_bazel_rules_swift//swift:swift.bzl",
    _SwiftInfo = "SwiftInfo",
)

# Re-export providers.
AppleBinaryInfo = _AppleBinaryInfo

AppleBundleInfo = _AppleBundleInfo

AppleTestInfo = _AppleTestInfo

IosApplicationBundleInfo = _IosApplicationBundleInfo

IosExtensionBundleInfo = _IosExtensionBundleInfo

SwiftInfo = _SwiftInfo
