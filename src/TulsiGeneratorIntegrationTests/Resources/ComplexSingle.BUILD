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

config_setting(
    name = "config_test_enabled",
    values = {"define": "TEST=1"},
)

ios_application(
    name = "Application",
    binary = ":Binary",
)

objc_binary(
    name = "Binary",
    srcs = [
        "Binary/srcs/main.m",
        ":SrcGenerator",
    ],
    bridging_header = ":BridgingHeaderGenerator",
    defines = [
        "A=BINARY_DEFINE",
    ],
    includes = [
        "Binary/includes/first/include",
        "Binary/includes/second/include",
    ],
    non_arc_srcs = [
        "Binary/non_arc_srcs/NonARCFile.mm",
    ],
    storyboards = [
        "Binary/Base.lproj/One.storyboard",
        ":StoryboardGenerator",
    ],
    deps = [
        ":CoreDataResources",
        ":Library",
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
    name = "BridgingHeaderGenerator",
    srcs = ["BridgingHeaderGenerator/srcs/bridging_header.h"],
    outs = ["BridgingHeaderGenerator/outs/bridging_header.h"],
    cmd = "cp $< $@",
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
