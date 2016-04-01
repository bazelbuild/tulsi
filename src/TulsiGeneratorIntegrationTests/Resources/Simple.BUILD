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

# Simple mock BUILD file for aspect testing.

ios_application(
    name = "Application",
    binary = ":Binary",
    launch_image = "Binary_Assets_LaunchImage",
    launch_storyboard = "Application/Launch.storyboard",
)

objc_binary(
    name = "Binary",
    srcs = [
        "Binary/srcs/main.m",
    ],
    asset_catalogs = ["Binary/Assets.xcassets"],
    bridging_header = "Binary/bridging_header/bridging_header.h",
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
    xibs = ["Library/xibs/xib.xib"],
)

ios_test(
    name = "XCTest",
    srcs = [
        "XCTest/srcs/src1.mm",
    ],
    xctest = 1,
    xctest_app = ":Application",
    deps = [
        ":Library",
    ],
)

ios_test(
    name = "XCTestWithDefaultHost",
    srcs = [
        "XCTestWithDefaultHost/srcs/src1.mm",
    ],
    xctest = 1,
)
