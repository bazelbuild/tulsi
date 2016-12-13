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
    xctest = 1,
)

## Skylark-based tvOS rules.
# TODO(abaire): Move to ComplexSingle.BUILD when the rules are open sourecd.
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
