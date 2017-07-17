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

# Load Skylark macros.
load(
    "//tools/build_defs/apple:ios.bzl",
    "skylark_ios_application",
)
load(
    "//tools/build_defs/apple:watchos.bzl",
    "skylark_watchos_application",
    "skylark_watchos_extension",
)

skylark_ios_application(
    name = "Application",
    bundle_id = "application.bundle_id",
    entitlements = "Application/entitlements.entitlements",
    families = [
        "iphone",
        "ipad",
    ],
    infoplists = ["Application/Info.plist"],
    watch_application = ":WatchApplication",
    deps = [
        ":ApplicationLibrary",
        ":ApplicationResources",
    ],
)

objc_library(
    name = "ApplicationResources",
    structured_resources = [
        "Application/structured_resources.file1",
    ],
)

objc_library(
    name = "ApplicationLibrary",
    srcs = [
        "Library/srcs/main.m",
    ],
    asset_catalogs = [
        "Library/AssetsOne.xcassets/test_file.ico",
        "Library/AssetsTwo.xcassets/png_file.png",
    ],
    includes = [
        "Library/includes/one/include",
    ],
)

skylark_watchos_application(
    name = "WatchApplication",
    bundle_id = "application.watch.app.bundle_id",
    entitlements = "Watch2Extension/app_entitlements.entitlements",
    extension = ":WatchExtension",
    infoplists = ["Watch2Extension/app_infoplists/Info.plist"],
    storyboards = ["Watch2Extension/Interface.storyboard"],
    deps = [":WatchApplicationResources"],
)

objc_library(
    name = "WatchApplicationResources",
    asset_catalogs = ["Watch2Extension/app_asset_catalogs.xcassets/app_asset_file.png"],
    resources = [
        "Watch2Extension/ext_resources.file",
    ],
    structured_resources = [
        "Watch2Extension/ext_structured_resources.file",
    ],
)

skylark_watchos_extension(
    name = "WatchExtension",
    bundle_id = "application.watch.ext.bundle_id",
    entitlements = "Watch2Extension/ext_entitlements.entitlements",
    infoplists = ["Watch2Extension/ext_infoplists/Info.plist"],
    deps = [
        ":WatchExtensionLibrary",
        ":WatchExtensionResources",
    ],
)

objc_library(
    name = "WatchExtensionResources",
    resources = [
        "Watch2Extension/ext_resources.file",
    ],
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
