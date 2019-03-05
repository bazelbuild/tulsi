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

# MacOS mock BUILD file for testing.

load(
    "@build_bazel_rules_apple//apple:macos.bzl",
    "macos_application",
    "macos_command_line_application",
    "macos_extension",
    "macos_unit_test",
    "macos_ui_test",
    "macos_bundle",
)
load("@build_bazel_rules_apple//apple:versioning.bzl", "apple_bundle_version")

macos_application(
    name = "MyMacOSApp",
    additional_contents = dict({
        "MyPlugin": "PlugIns",
    }.items()),
    app_icons = [":MacAppIcon.xcassets"],
    bundle_id = "com.example.mac-app",
    extensions = [
        ":MyTodayExtension",
    ],
    infoplists = [":Info.plist"],
    minimum_os_version = "10.13",
    version = ":MyAppVersion",
    deps = [":MyMacAppSources"],
)

apple_bundle_version(
    name = "MyAppVersion",
    build_version = "1.0",
)

filegroup(
    name = "MacAppIcon.xcassets",
    srcs = [
        "MacAppIcon.xcassets/MacAppIcon.appiconset/Contents.json",
        "MacAppIcon.xcassets/MacAppIcon.appiconset/MacAppIcon-16.png",
        "MacAppIcon.xcassets/MacAppIcon.appiconset/MacAppIcon-16@2x.png",
    ],
)

objc_library(
    name = "MyMacAppSources",
    srcs = [
        "src/AppDelegate.h",
        "src/AppDelegate.m",
        "src/main.m",
    ],
    data = [
        "Resources/Main.storyboard",
    ],
)

macos_extension(
    name = "MyTodayExtension",
    bundle_id = "com.example.mac-app.today-extension",
    entitlements = ":MyTodayExtension-Entitlements.entitlements",
    infoplists = [":MyTodayExtension-Info.plist"],
    minimum_os_version = "10.13",
    version = ":MyTodayExtensionVersion",
    deps = [":MyTodayExtensionSources"],
)

macos_bundle(
    name = "MyPlugin",
    bundle_extension = "bundle",
    bundle_id = "com.example.mac-app.plugin",
    bundle_name = "MyPlugin",
    infoplists = [":MyPlugin_Info.plist"],
    minimum_os_version = "10.13",
    version = ":MyPlugInVersion",
    deps = [
        ":MyPluginSources",
    ],
)

apple_bundle_version(
    name = "MyTodayExtensionVersion",
    build_version = "1.0",
)

apple_bundle_version(
    name = "MyPlugInVersion",
    build_version = "1.0",
)

objc_library(
    name = "MyTodayExtensionSources",
    srcs = [
        "src/extensions/today/ExtSources/TodayViewController.m",
        "src/extensions/today/TodayViewController.h",
    ],
    data = [
        "Resources/extensions/today/TodayViewController.xib",
    ],
    sdk_frameworks = [
        "NotificationCenter",
    ],
)

objc_library(
    name = "MyPluginSources",
    srcs = [
        "src/plugin/PluginViewController.h",
        "src/plugin/PluginViewController.m",
    ],
    data = [
        "Resources/plugin/PluginViewController.xib",
    ],
    sdk_frameworks = [
        "NotificationCenter",
    ],
)

macos_command_line_application(
    name = "MyCommandLineApp",
    bundle_id = "com.example.command-line",
    infoplists = [":MyCommandLineApp-Info.plist"],
    minimum_os_version = "10.13",
    version = ":CommandLineVersion",
    deps = [":MyCommandLineAppSource"],
)

objc_library(
    name = "MyCommandLineAppSource",
    srcs = ["src/main.m"],
)

apple_bundle_version(
    name = "CommandLineVersion",
    build_version = "1.0",
)

# Test targets

objc_library(
    name = "UnitTestsLib",
    srcs = ["test/UnitTests.m"],
)

objc_library(
    name = "UnitTestsNoHostLib",
    srcs = ["test/UnitTestsNoHost.m"],
)

objc_library(
    name = "UITestsLib",
    srcs = ["test/UITests.m"],
)

macos_unit_test(
    name = "UnitTests",
    minimum_os_version = "10.13",
    test_host = ":MyMacOSApp",
    deps = [":UnitTestsLib"],
)

macos_unit_test(
    name = "UnitTestsNoHost",
    bundle_id = "com.tulsi.tests",
    minimum_os_version = "10.13",
    deps = [":UnitTestsNoHostLib"],
)

macos_ui_test(
    name = "UITests",
    minimum_os_version = "10.13",
    test_host = ":MyMacOSApp",
    deps = [":UITestsLib"],
)
