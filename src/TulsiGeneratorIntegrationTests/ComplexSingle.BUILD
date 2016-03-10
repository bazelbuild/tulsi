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
        "main.m",
        ":SrcGenerator",
    ],
    bridging_header = ":BridgingHeaderGenerator",
    defines = [
        "A=DEFINE",
    ],
    includes = [
        "additional/include",
        "another/include",
    ],
    deps = [
        ":Library",
    ],
)

objc_library(
    name = "Library",
    srcs = [
        "path/to/src5.mm",
        ":LibrarySources",
    ],
    hdrs = [
        "path/to/header.h",
    ],
    copts = ["-DCOPT_DEFINE"],
    defines = [
        "DEFINES_DEFINE=1",
        "SECOND_DEFINE=2",
    ],
    pch = ":PCHGenerator",
    xibs = ["path/to/xib.xib"],
)

ios_test(
    name = "XCTest",
    srcs = select({
        ":config_test_enabled": ["test/configTestSource.m"],
        "//conditions:default": ["test/defaultTestSource.m"],
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
        "path/to/src1.m",
        "path/to/src2.m",
        "path/to/src3.m",
        "path/to/src4.m",
    ],
)

genrule(
    name = "BridgingHeaderGenerator",
    srcs = ["path/to/bridging_header.h"],
    outs = ["bridging_header.h"],
    cmd = "cp $< $@",
)

genrule(
    name = "PCHGenerator",
    srcs = ["path/to/pch.h"],
    outs = ["PCHFile.pch"],
    cmd = "cp $< $@",
)

genrule(
    name = "SrcGenerator",
    srcs = ["path/to/input.m"],
    outs = ["path/to/output.m"],
    cmd = "cp $< $@",
)
