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

# mock BUILD file using Swift targets for aspect testing.

load(
    "@build_bazel_rules_apple//apple:ios.bzl",
    "ios_application",
)
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

ios_application(
    name = "Application",
    bundle_id = "com.example.invalid",
    families = [
        "iphone",
        "ipad",
    ],
    infoplists = ["Info.plist"],
    minimum_os_version = "10.0",
    deps = [":ApplicationLibrary"],
)

objc_library(
    name = "ApplicationLibrary",
    srcs = [
        "//tools/objc:objc_dummy.mm",
    ],
    deps = [
        ":SwiftLibrary",
        ":SwiftLibraryV3",
        ":SwiftLibraryV4",
    ],
)

swift_library(
    name = "SwiftLibraryV3",
    srcs = [
        "SwiftLibraryV3/srcs/a.swift",
        "SwiftLibraryV3/srcs/b.swift",
    ],
    copts = [
        "-swift-version",
        "3",
    ],
    defines = [
        "LIBRARY_DEFINE_V3",
    ],
    generates_header = True,
)

swift_library(
    name = "SwiftLibraryV4",
    srcs = [
        "SwiftLibraryV4/srcs/a.swift",
        "SwiftLibraryV4/srcs/b.swift",
    ],
    copts = [
        "-swift-version",
        "4",
    ],
    defines = [
        "LIBRARY_DEFINE_V4",
    ],
    generates_header = True,
)

swift_library(
    name = "SwiftLibrary",
    srcs = [
        "SwiftLibrary/srcs/a.swift",
        "SwiftLibrary/srcs/b.swift",
    ],
    defines = [
        "LIBRARY_DEFINE",
    ],
    generates_header = True,
    deps = [
        ":SubSwiftLibrary",
    ],
)

swift_library(
    name = "SubSwiftLibrary",
    srcs = [
        "SubSwiftLibrary/srcs/c.swift",
    ],
    defines = [
        "SUB_LIBRARY_DEFINE",
    ],
    generates_header = True,
)
