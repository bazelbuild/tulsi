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

ios_application(
    name = "Application",
    binary = ":Binary",
)

objc_binary(
    name = "Binary",
    srcs = [
        "Binary/srcs/main.m",
    ],
    deps = [
        ":J2ObjCLibrary",
        ":ObjCProtoLibrary",
    ],
)

proto_library(
    name = "ProtoLibrary",
    srcs = ["protolibrary.proto"],
)

objc_proto_library(
    name = "ObjCProtoLibrary",
    deps = [
        ":ProtoLibrary",
    ],
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

ios_test(
    name = "XCTestWithDefaultHost",
    srcs = [
        "XCTestWithDefaultHost/srcs/src1.mm",
    ],
)

## Skylark-based tvOS rules.
# TODO(abaire): Move to ComplexSingle.BUILD when the rules are open sourced.
load(
    "//tools/build_defs/apple:tvos.bzl",
    "skylark_tvos_application",
    "skylark_tvos_extension",
)

skylark_tvos_application(
    name = "tvOSApplication",
    bundle_id = "c.test.tvOSApplication",
    extensions = [":tvOSExtension"],
    infoplists = [
        "tvOSApplication/Info.plist",
    ],
    deps = [":tvOSLibrary"],
)

skylark_tvos_extension(
    name = "tvOSExtension",
    bundle_id = "c.test.tvOSExtension",
    infoplists = [
        "tvOSExtension/Info.plist",
    ],
    deps = [":tvOSLibrary"],
)

objc_library(
    name = "tvOSLibrary",
    srcs = ["tvOSLibrary/srcs/src.m"],
    enable_modules = True,
)

## Skylark-based test rules.
load("//tools/build_defs/apple:ios.bzl", "skylark_ios_application")
load(
    "//tools/build_defs/apple/testing:ios.bzl",
    "ios_unit_test",
    "ios_ui_test",
)

skylark_ios_application(
    name = "SkylarkApplication",
    bundle_id = "com.google.Tulsi.Application",
    families = ["iphone"],
    infoplists = ["Application/Info.plist"],
    launch_storyboard = "Application/Launch.storyboard",
    settings_bundle = ":SettingsBundle",
    deps = [":MainLibrary"],
)

skylark_ios_application(
    name = "SkylarkTargetApplication",
    bundle_id = "com.google.Tulsi.TargetApplication",
    families = ["iphone"],
    infoplists = ["Application/Info.plist"],
    launch_storyboard = "Application/Launch.storyboard",
    deps = [":MainLibrary"],
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
        "Binary/srcs/main.m",
    ],
    asset_catalogs = ["Binary/Assets.xcassets/asset.png"],
    datamodels = glob(["SimpleTest.xcdatamodeld/**"]),
    defines = [
        "BINARY_ADDITIONAL_DEFINE",
        "BINARY_ANOTHER_DEFINE=2",
    ],
    includes = ["Binary/includes"],
    storyboards = ["Binary/Base.lproj/One.storyboard"],
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
)

objc_library(
    name = "XCTestCode",
    srcs = [
        "XCTest/srcs/src1.mm",
    ],
    deps = [
        ":Library",
    ],
)

objc_library(
    name = "XCUITestCode",
    srcs = [
        "XCUITest/srcs/src1.mm",
    ],
    deps = [
        ":Library",
    ],
)

ios_unit_test(
    name = "XCTest",
    test_host = ":SkylarkApplication",
    deps = [
        ":XCTestCode",
    ],
)

ios_ui_test(
    name = "XCUITest",
    runner = "//tools/objc/sim_devices:default_runner",
    test_host = ":SkylarkApplication",
    deps = [
        ":XCUITestCode",
    ],
)
