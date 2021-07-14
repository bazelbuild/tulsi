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

load(
    "@build_bazel_rules_apple//apple:apple.bzl",
    "apple_static_framework_import",
)
load(
    "@build_bazel_rules_apple//apple:ios.bzl",
    "ios_application",
    "ios_extension",
    "ios_ui_test",
    "ios_unit_test",
)
load(
    "@build_bazel_rules_apple//apple:resources.bzl",
    "apple_bundle_import",
    "apple_resource_group",
)
load(
    "@build_bazel_rules_apple//apple:tvos.bzl",
    "tvos_application",
    "tvos_extension",
)

ios_application(
    name = "Application",
    bundle_id = "example.iosapp",
    entitlements = "Application/entitlements.entitlements",
    extensions = [
        ":TodayExtension",
    ],
    families = [
        "iphone",
        "ipad",
    ],
    infoplists = ["Application/Info.plist"],
    minimum_os_version = "10.0",
    deps = [
        ":ApplicationLibrary",
    ],
)

objc_library(
    name = "ApplicationLibrary",
    srcs = [
        "Application/srcs/main.m",
        ":SrcGenerator",
    ],
    data = [
        "Application/AssetsOne.xcassets/another_file.ico",
        "Application/AssetsOne.xcassets/test_file.ico",
        "Application/AssetsTwo.xcassets/png_file.png",
        "Application/Base.lproj/Localizable.strings",
        "Application/Base.lproj/Localized.strings",
        "Application/Base.lproj/One.storyboard",
        "Application/NonLocalized.strings",
        "Application/en.lproj/EN.strings",
        "Application/en.lproj/Localized.strings",
        "Application/es.lproj/Localized.strings",
        ":ApplicationResources",
        ":ObjCBundle",
        ":StoryboardGenerator",
    ],
    defines = [
        "A=BINARY_DEFINE",
    ],
    includes = [
        "Application/includes/first/include",
        "Application/includes/second/include",
    ],
    non_arc_srcs = [
        "Application/non_arc_srcs/NonARCFile.mm",
    ],
    deps = [
        ":CoreDataResources",
        ":Library",
        ":ObjCFramework",
    ],
)

apple_resource_group(
    name = "ApplicationResources",
    structured_resources = [
        "Application/structured_resources.file1",
        "Application/structured_resources.file2",
    ],
)

apple_bundle_import(
    name = "ObjCBundle",
    bundle_imports = [
        "ObjCBundle.bundle/FileOne.txt",
        "ObjCBundle.bundle/FileTwo",
    ],
)

objc_library(
    name = "CoreDataResources",
    data = glob(["Test.xcdatamodeld/**"]),
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
    data = ["Library/xib.xib"],
    defines = [
        "LIBRARY_DEFINES_DEFINE=1",
        "'LIBRARY SECOND DEFINE'=2",
        "LIBRARY_VALUE_WITH_SPACES=\"Value with spaces\"",
    ],
    pch = ":PCHGenerator",
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
        "-DSubLibraryWithDifferentDefines_STRING_WITH_SPACES=String with spaces",
        "-D'SubLibraryWithDifferentDefines_SINGLEQUOTED=Single quoted with spaces'",
        "-D\"SubLibraryWithDifferentDefines_PREQUOTED=Prequoted with spaces\"",
    ],
    defines = [
        "SubLibraryWithDifferentDefines=1",
    ],
    includes = ["SubLibraryWithDifferentDefines/includes"],
)

objc_library(
    name = "TestLibrary",
    srcs = select({
        ":config_test_enabled": ["XCTest/srcs/configTestSource.m"],
        "//conditions:default": ["XCTest/srcs/defaultTestSource.m"],
    }),
)

ios_unit_test(
    name = "XCTest",
    minimum_os_version = "10.0",
    runner = "@build_bazel_rules_apple//apple/testing/default_runner:ios_default_runner",
    test_host = ":Application",
    deps = [
        ":Library",
        ":TestLibrary",
    ],
)

apple_static_framework_import(
    name = "ObjCFramework",
    framework_imports = [
        "ObjCFramework/test.framework/file1",
        "ObjCFramework/test.framework/file2.txt",
        "ObjCFramework/test.framework/file3.m",
        "ObjCFramework/test.framework/file4.h",
    ],
)

ios_extension(
    name = "TodayExtension",
    bundle_id = "example.iosapp.todayextension",
    families = [
        "iphone",
        "ipad",
    ],
    infoplists = [
        "TodayExtension/Plist1.plist",
    ],
    minimum_os_version = "10.0",
    deps = [
        ":TodayExtensionLibrary",
        ":TodayExtensionResources",
    ],
)

objc_library(
    name = "TodayExtensionLibrary",
    srcs = [
        "TodayExtension/srcs/today_extension_library.m",
    ],
)

objc_library(
    name = "TodayExtensionResources",
    data = [
        "TodayExtension/resources/file1",
        "TodayExtension/resources/file2.file",
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

tvos_application(
    name = "tvOSApplication",
    bundle_id = "c.test.tvOSApplication",
    extensions = [":tvOSExtension"],
    infoplists = [
        "tvOSApplication/Info.plist",
    ],
    minimum_os_version = "10.0",
    deps = [":tvOSLibrary"],
)

tvos_extension(
    name = "tvOSExtension",
    bundle_id = "c.test.tvOSExtension",
    infoplists = [
        "tvOSExtension/Info.plist",
    ],
    minimum_os_version = "10.0",
    deps = [":tvOSLibrary"],
)

objc_library(
    name = "tvOSLibrary",
    srcs = ["tvOSLibrary/srcs/src.m"],
    enable_modules = 1,
)
