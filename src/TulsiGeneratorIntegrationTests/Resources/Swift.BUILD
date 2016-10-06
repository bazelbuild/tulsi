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

load("//tools/build_defs/apple:apple.bzl", "swift_library")

ios_application(
    name = "Application",
    binary = ":Binary",
)

objc_binary(
    name = "Binary",
    srcs = [
        "//tools/objc:objc_dummy.m",
    ],
    deps = [
        ":SwiftLibrary",
    ],
)

swift_library(
    name = "SwiftLibrary",
    srcs = [
        "SwiftLibrary/srcs/a.swift",
        "SwiftLibrary/srcs/b.swift",
    ],
)
