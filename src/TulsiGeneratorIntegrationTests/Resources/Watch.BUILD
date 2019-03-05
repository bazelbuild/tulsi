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

# WatchOS mock BUILD file for aspect testing.

load(
    "@build_bazel_rules_apple//apple:ios.bzl",
    "ios_application",
)
load("@build_bazel_rules_apple//apple:watchos.bzl", "watchos_application", "watchos_extension")
load(
    "@build_bazel_rules_apple//apple:resources.bzl",
    "apple_resource_group",
)

ios_application(
    name = "Application",
    bundle_id = "application.bundle-id",
    entitlements = "Application/entitlements.entitlements",
    families = [
        "iphone",
        "ipad",
    ],
    infoplists = ["Application/Info.plist"],
    minimum_os_version = "10.0",
    watch_application = ":WatchApplication",
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

watchos_application(
    name = "WatchApplication",
    bundle_id = "application.watch.app.bundle-id",
    entitlements = "Watch2Extension/app_entitlements.entitlements",
    extension = ":WatchExtension",
    infoplists = ["Watch2Extension/app_infoplists/Info.plist"],
    minimum_os_version = "3.0",
    storyboards = ["Watch2Extension/Interface.storyboard"],
    deps = [":WatchApplicationResources"],
)

objc_library(
    name = "WatchApplicationResources",
    data = [
        "Watch2Extension/app_asset_catalogs.xcassets/app_asset_file.png",
        "Watch2Extension/ext_resources.file",
        ":WatchApplicationStructuredResources",
    ],
)

apple_resource_group(
    name = "WatchApplicationStructuredResources",
    structured_resources = [
        "Watch2Extension/ext_structured_resources.file",
    ],
)

watchos_extension(
    name = "WatchExtension",
    bundle_id = "application.watch.ext.bundle-id",
    entitlements = "Watch2Extension/ext_entitlements.entitlements",
    infoplists = ["Watch2Extension/ext_infoplists/Info.plist"],
    minimum_os_version = "3.0",
    deps = [
        ":WatchExtensionLibrary",
        ":WatchExtensionResources",
    ],
)

objc_library(
    name = "WatchExtensionResources",
    data = [
        "Watch2Extension/ext_resources.file",
        ":WatchExtensionStructuredResources",
    ],
)

apple_resource_group(
    name = "WatchExtensionStructuredResources",
    structured_resources = [
        "Watch2Extension/ext_structured_resources.file",
    ],
)

objc_library(
    name = "WatchExtensionLibrary",
    srcs = [
        "Watch2ExtensionBinary/srcs/watch2_extension_binary.m",
    ],
    sdk_frameworks = [
        "WatchKit",
    ],
)
