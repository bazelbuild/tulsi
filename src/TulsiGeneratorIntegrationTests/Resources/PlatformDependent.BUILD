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

# Mock BUILD file for aspect testing.

load(
    "@build_bazel_rules_apple//apple:ios.bzl",
    "apple_product_type",
    "ios_application",
    "ios_extension",
    "ios_unit_test",
    "ios_ui_test",
)
load("@build_bazel_rules_apple//apple:swift.bzl", "swift_library")

ios_application(
    name = "SkylarkApplication",
    bundle_id = "com.google.Tulsi.Application",
    bundle_name = "SkylarkApp",
    extensions = [":StickerExtension"],
    families = ["iphone"],
    infoplists = ["Application/Info.plist"],
    launch_storyboard = "Application/Launch.storyboard",
    minimum_os_version = "8.0",
    settings_bundle = ":SettingsBundle",
    deps = [":MainLibrary"],
)

ios_application(
    name = "SkylarkTargetApplication",
    bundle_id = "com.google.Tulsi.TargetApplication",
    families = ["iphone"],
    infoplists = ["Application/Info.plist"],
    launch_storyboard = "Application/Launch.storyboard",
    minimum_os_version = "8.0",
    deps = [":MainLibrary"],
)

ios_extension(
    name = "StickerExtension",
    asset_catalogs = ["Stickers.xcstickers/asset.png"],
    bundle_id = "com.google.Tulsi.TargetApplication.extension",
    families = ["iphone"],
    infoplists = ["Ext-Info.plist"],
    minimum_os_version = "8.0",
    product_type = apple_product_type.messages_sticker_pack_extension,
)

objc_bundle(
    name = "SettingsBundle",
    bundle_imports = [
        "Settings.bundle/Root.plist",
    ],
)

objc_library(
    name = "MainLibrary",
    srcs = [
        "App/srcs/main.m",
    ],
    asset_catalogs = ["App/Assets.xcassets/asset.png"],
    datamodels = glob(["SimpleTest.xcdatamodeld/**"]),
    defines = [
        "BINARY_ADDITIONAL_DEFINE",
        "BINARY_ANOTHER_DEFINE=2",
    ],
    includes = ["App/includes"],
    storyboards = ["App/Base.lproj/One.storyboard"],
    deps = [
        ":Library",
    ],
)

objc_library(
    name = "Library",
    srcs = [
        "Library/srcs/SrcsHeader.h",
        "Library/srcs/src1.m",
        "Library/srcs/src2.m",
        "Library/srcs/src3.m",
        "Library/srcs/src4.m",
    ],
    hdrs = [
        "Library/hdrs/HdrsHeader.h",
    ],
    copts = [
        "-DLIBRARY_COPT_DEFINE",
        "-I/Library/absolute/include/path",
        "-Irelative/Library/include/path",
    ],
    defines = ["LIBRARY_DEFINES_DEFINE=1"],
    pch = "Library/pch/PCHFile.pch",
    textual_hdrs = [
        "Library/textual_hdrs/TextualHdrsHeader.h",
    ],
    xibs = ["Library/xibs/xib.xib"],
    deps = [
        "J2ObjCLibrary",
        ":ObjcProtos",
    ],
)

objc_proto_library(
    name = "ObjcProtos",
    deps = [":Protos"],
)

proto_library(
    name = "Protos",
    srcs = ["ProtoFile.proto"],
)

j2objc_library(
    name = "J2ObjCLibrary",
    deps = [
        ":JavaLibrary",
    ],
)

java_library(
    name = "JavaLibrary",
    srcs = ["file.java"],
)

objc_library(
    name = "XCTestCode",
    srcs = [
        "XCTest/srcs/XCTests.mm",
    ],
    deps = [
        ":Library",
    ],
)

objc_library(
    name = "XCUITestCode",
    srcs = [
        "XCUITest/srcs/XCUITests.mm",
    ],
    deps = [
        ":Library",
    ],
)

swift_library(
    name = "XCTestCodeSwift",
    srcs = ["XCTest/srcs/Tests.swift"],
)

ios_unit_test(
    name = "XCTest",
    minimum_os_version = "8.0",
    test_host = ":SkylarkApplication",
    deps = [
        ":XCTestCode",
        ":XCTestCodeSwift",
    ],
)

ios_unit_test(
    name = "XCTestWithNoTestHost",
    minimum_os_version = "8.0",
    deps = [
        ":XCTestCode",
        ":XCTestCodeSwift",
    ],
)

ios_ui_test(
    name = "XCUITest",
    minimum_os_version = "8.0",
    runner = "//tools/objc/sim_devices:default_runner",
    test_host = ":SkylarkApplication",
    deps = [
        ":XCUITestCode",
    ],
)

objc_library(
    name = "LegacyTestsLib",
    srcs = [
        "LegacyTests/LegacyTests.m",
    ],
)

ios_unit_test(
    name = "LegacyTests",
    minimum_os_version = "8.0",
    deps = [
        ":LegacyTestsLib",
    ],
)
