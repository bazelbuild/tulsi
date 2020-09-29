# Copyright 2016 The Tulsi Authors. All rights reserved.
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

# AppClip mock BUILD file for aspect testing.

load(
    "@build_bazel_rules_apple//apple:ios.bzl",
    "ios_app_clip",
    "ios_application",
)
load(
    "@build_bazel_rules_apple//apple:resources.bzl",
    "apple_resource_group",
)

ios_application(
    name = "Application",
    app_clips = [":AppClip"],
    bundle_id = "application.bundle-id",
    entitlements = "Application/entitlements.entitlements",
    families = [
        "iphone",
    ],
    infoplists = ["Application/Info.plist"],
    minimum_os_version = "14.0",
    deps = [
        ":ApplicationLibrary",
        ":ApplicationResources",
    ],
)

objc_library(
    name = "ApplicationResources",
    data = [":ApplicationStructuredResources"],
)

apple_resource_group(
    name = "ApplicationStructuredResources",
    structured_resources = [
        "Application/structured_resources.file1",
    ],
)

objc_library(
    name = "ApplicationLibrary",
    srcs = [
        "Library/srcs/main.m",
    ],
    data = [
        "Library/AssetsOne.xcassets/test_file.ico",
        "Library/AssetsTwo.xcassets/png_file.png",
    ],
    includes = [
        "Library/includes/one/include",
    ],
)

ios_app_clip(
    name = "AppClip",
    bundle_id = "application.bundle-id.clip",
    entitlements = "AppClip/app_entitlements.entitlements",
    families = ["iphone"],
    infoplists = ["AppClip/app_infoplists/Info.plist"],
    minimum_os_version = "14.0",
    deps = [":AppClipLibrary"],
)

objc_library(
    name = "AppClipLibrary",
    srcs = [
        "Library/srcs/app_clip_main.m",
    ],
    data = [
        "Library/AssetsOne.xcassets/test_file.ico",
        "Library/AssetsTwo.xcassets/png_file.png",
    ],
    includes = [
        "Library/includes/one/include",
    ],
)
