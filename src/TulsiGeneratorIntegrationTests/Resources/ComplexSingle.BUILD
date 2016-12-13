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

# Complex mock BUILD file for aspect testing.

load(":ComplexSingle.bzl", "test_macro")

config_setting(
    name = "config_test_enabled",
    values = {"define": "TEST=1"},
)

ios_application(
    name = "Application",
    binary = ":Binary",
    entitlements = "Application/entitlements.entitlements",
    extensions = [
        ":TodayExtension",
        ":WatchExtension",
        ":Watch2Extension",
    ],
    structured_resources = [
        "Application/structured_resources.file1",
        "Application/structured_resources.file2",
    ],
)

objc_binary(
    name = "Binary",
    srcs = [
        "Binary/srcs/main.m",
        ":SrcGenerator",
    ],
    asset_catalogs = [
        "Binary/AssetsOne.xcassets/test_file.ico",
        "Binary/AssetsOne.xcassets/another_file.ico",
        "Binary/AssetsTwo.xcassets/png_file.png",
    ],
    bundles = [":ObjCBundle"],
    defines = [
        "A=BINARY_DEFINE",
    ],
    includes = [
        "Binary/includes/first/include",
        "Binary/includes/second/include",
    ],
    infoplist = "Binary/Info.plist",
    non_arc_srcs = [
        "Binary/non_arc_srcs/NonARCFile.mm",
    ],
    non_propagated_deps = [
        ":NonPropagatedLibrary",
    ],
    storyboards = [
        "Binary/Base.lproj/One.storyboard",
        ":StoryboardGenerator",
    ],
    strings = [
        "Binary/Base.lproj/Localizable.strings",
        "Binary/Base.lproj/Localized.strings",
        "Binary/en.lproj/Localized.strings",
        "Binary/en.lproj/EN.strings",
        "Binary/es.lproj/Localized.strings",
        "Binary/NonLocalized.strings",
    ],
    deps = [
        ":CoreDataResources",
        ":Library",
        ":ObjCFramework",
    ],
)

objc_bundle(
    name = "ObjCBundle",
    bundle_imports = [
        "ObjCBundle.bundle/FileOne.txt",
        "ObjCBundle.bundle/FileTwo",
    ],
)

objc_library(
    name = "CoreDataResources",
    datamodels = glob(["Test.xcdatamodeld/**"]),
)

objc_library(
    name = "Library",
    srcs = [
        "Library/srcs/SrcsHeader.h",
        "Library/srcs/src5.mm",
        ":LibrarySources",
    ],
    hdrs = [
        "Library/hdrs/HdrsHeader.h",
    ],
    copts = ["-DLIBRARY_COPT_DEFINE"],
    defines = [
        "LIBRARY_DEFINES_DEFINE=1",
        "'LIBRARY SECOND DEFINE'=2",
        "LIBRARY_VALUE_WITH_SPACES=\"Value with spaces\"",
    ],
    pch = ":PCHGenerator",
    xibs = ["Library/xib.xib"],
    deps = [
        ":SubLibrary",
        ":SubLibraryWithDefines",
        ":SubLibraryWithDifferentDefines",
    ],
)

objc_library(
    name = "SubLibrary",
    srcs = [
        "SubLibrary/srcs/src.mm",
    ],
    enable_modules = 1,
    pch = "SubLibrary/pch/AnotherPCHFile.pch",
)

objc_library(
    name = "SubLibraryWithDefines",
    srcs = [
        "SubLibraryWithDefines/srcs/src.mm",
    ],
    copts = [
        "-menable-no-nans",
        "-menable-no-infs",
        "-I/SubLibraryWithDefines/local/includes",
        "-Irelative/SubLibraryWithDefines/local/includes",
    ],
    defines = [
        "SubLibraryWithDefines=1",
        "SubLibraryWithDefines_DEFINE=SubLibraryWithDefines",
    ],
    deps = ["SubLibraryWithIdenticalDefines"],
)

objc_library(
    name = "SubLibraryWithIdenticalDefines",
    srcs = [
        "SubLibraryWithIdenticalDefines/srcs/sub_library_with_identical_defines.m",
    ],
    copts = [
        "-menable-no-nans",
        "-menable-no-infs",
        "-I/SubLibraryWithDefines/local/includes",
        "-Irelative/SubLibraryWithDefines/local/includes",
    ],
    defines = [
        "SubLibraryWithDefines=1",
        "SubLibraryWithDefines_DEFINE=SubLibraryWithDefines",
    ],
)

objc_library(
    name = "SubLibraryWithDifferentDefines",
    srcs = [
        "SubLibraryWithDifferentDefines/srcs/src.mm",
    ],
    copts = [
        "-DSubLibraryWithDifferentDefines_LocalDefine",
        "-DSubLibraryWithDifferentDefines_INTEGER_DEFINE=1",
        "-DSubLibraryWithDifferentDefines_STRING_DEFINE=Test",
        "-DSubLibraryWithDifferentDefines_STRING_WITH_SPACES='String with spaces'",
        "-D'SubLibraryWithDifferentDefines Define with spaces'",
        "-D'SubLibraryWithDifferentDefines Define with spaces and value'=1",
    ],
    defines = [
        "SubLibraryWithDifferentDefines=1",
    ],
    includes = ["SubLibraryWithDifferentDefines/includes"],
)

ios_test(
    name = "XCTest",
    srcs = select({
        ":config_test_enabled": ["XCTest/srcs/configTestSource.m"],
        "//conditions:default": ["XCTest/srcs/defaultTestSource.m"],
    }),
    xctest = 1,
    xctest_app = ":Application",
    deps = [
        ":Library",
    ],
)

objc_library(
    name = "NonPropagatedLibrary",
    srcs = [
        "NonPropagatedLibrary/srcs/non_propagated.m",
    ],
)

objc_framework(
    name = "ObjCFramework",
    framework_imports = [
        "ObjCFramework/test.framework/file1",
        "ObjCFramework/test.framework/file2.txt",
        "ObjCFramework/test.framework/file3.m",
        "ObjCFramework/test.framework/file4.h",
    ],
)

ios_extension_binary(
    name = "TodayExtensionBinary",
    srcs = [
        "TodayExtensionBinary/srcs/today_extension_binary.m",
    ],
)

ios_extension(
    name = "TodayExtension",
    binary = "TodayExtensionBinary",
    infoplists = [
        "TodayExtension/Plist1.plist",
        "TodayExtension/Plist2.plist",
    ],
    resources = [
        "TodayExtension/resources/file1",
        "TodayExtension/resources/file2.file",
    ],
)

apple_watch_extension_binary(
    name = "WatchExtensionBinary",
    srcs = [
        "WatchExtensionBinary/srcs/watch_extension_binary.m",
    ],
    sdk_frameworks = [
        "WatchKit",
    ],
)

apple_watch1_extension(
    name = "WatchExtension",
    app_asset_catalogs = [
        "WatchExtension/app_asset_catalogs.xcassets/app_asset_file.png",
    ],
    app_entitlements = "WatchExtension/app_entitlements.entitlements",
    app_infoplists = [
        "WatchExtension/app_infoplists/Info.plist",
    ],
    app_name = "WatchApp",
    app_resources = [
        "WatchExtension/app_resources.file",
    ],
    app_structured_resources = [
        "WatchExtension/app_structured_resources.file",
    ],
    binary = ":WatchExtensionBinary",
    ext_entitlements = "WatchExtension/ext_entitlements.entitlements",
    ext_infoplists = [
        "WatchExtension/ext_infoplists/Info.plist",
    ],
    ext_resources = [
        "WatchExtension/ext_resources.file",
    ],
    ext_structured_resources = [
        "WatchExtension/ext_structured_resources.file",
    ],
)

apple_watch2_extension(
    name = "Watch2Extension",
    app_asset_catalogs = [
        "Watch2Extension/app_asset_catalogs.xcassets/app_asset_file.png",
    ],
    app_entitlements = "Watch2Extension/app_entitlements.entitlements",
    app_infoplists = [
        "Watch2Extension/app_infoplists/Info.plist",
    ],
    app_name = "WatchOS2App",
    app_resources = [
        "Watch2Extension/app_resources.file",
    ],
    app_storyboards = [
        "Watch2Extension/Interface.storyboard",
    ],
    app_structured_resources = [
        "Watch2Extension/app_structured_resources.file",
    ],
    binary = ":Watch2ExtensionBinary",
    ext_entitlements = "Watch2Extension/ext_entitlements.entitlements",
    ext_infoplists = [
        "Watch2Extension/ext_infoplists/Info.plist",
    ],
    ext_resources = [
        "Watch2Extension/ext_resources.file",
    ],
    ext_structured_resources = [
        "Watch2Extension/ext_structured_resources.file",
    ],
)

apple_binary(
    name = "Watch2ExtensionBinary",
    srcs = [
        "Watch2ExtensionBinary/srcs/watch2_extension_binary.m",
    ],
    sdk_frameworks = [
        "WatchKit",
    ],
)

filegroup(
    name = "LibrarySources",
    srcs = [
        "LibrarySources/srcs/src1.m",
        "LibrarySources/srcs/src2.m",
        "LibrarySources/srcs/src3.m",
        "LibrarySources/srcs/src4.m",
    ],
)

genrule(
    name = "PCHGenerator",
    srcs = ["PCHGenerator/srcs/pch.h"],
    outs = ["PCHGenerator/outs/PCHFile.pch"],
    cmd = "cp $< $@",
)

genrule(
    name = "SrcGenerator",
    srcs = ["SrcGenerator/srcs/input.m"],
    outs = ["SrcGenerator/outs/output.m"],
    cmd = "cp $< $@",
)

genrule(
    name = "StoryboardGenerator",
    srcs = ["StoryboardGenerator/srcs/storyboard_input.file"],
    outs = ["StoryboardGenerator/outs/Two.storyboard"],
    cmd = "cp $< $@",
)
