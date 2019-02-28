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

# test_suite mock BUILD file for integration testing.

package(
    default_visibility = ["//TestSuite:__subpackages__"],
)

load(
    "@build_bazel_rules_apple//apple:ios.bzl",
    "ios_application",
    "ios_unit_test",
)

test_suite(
    name = "explicit_XCTests",
    tests = [
        "//TestSuite/One:LogicTest",
        "//TestSuite/One:XCTest",
        "//TestSuite/Three:XCTest",
        "//TestSuite/Two:XCTest",
    ],
)

test_suite(
    name = "local_tagged_tests",
    tags = ["tagged"],
)

test_suite(
    name = "recursive_test_suite",
    tests = [
        ":TestSuiteXCTest",
        "//TestSuite/Three:tagged_tests",
    ],
)

ios_application(
    name = "TestApplication",
    bundle_id = "com.example.testapplication",
    families = [
        "iphone",
        "ipad",
    ],
    infoplists = ["Info.plist"],
    minimum_os_version = "10.0",
    deps = [
        ":ApplicationLibrary",
    ],
)

objc_library(
    name = "ApplicationLibrary",
    srcs = [
        "Application/srcs/main.m",
    ],
)

objc_library(
    name = "TestSuiteXCTestLib",
    srcs = ["TestSuite/TestSuiteXCTest.m"],
    deps = [":ApplicationLibrary"],
)

objc_library(
    name = "TestSuiteXCTestNotTaggedLib",
    srcs = ["TestSuite/RootXCTest.m"],
    deps = [":ApplicationLibrary"],
)

ios_unit_test(
    name = "TestSuiteXCTest",
    minimum_os_version = "10.0",
    runner = "@build_bazel_rules_apple//apple/testing/default_runner:ios_default_runner",
    tags = ["tagged"],
    test_host = ":TestApplication",
    deps = [":TestSuiteXCTestLib"],
)

ios_unit_test(
    name = "TestSuiteXCTestNotTagged",
    minimum_os_version = "10.0",
    runner = "@build_bazel_rules_apple//apple/testing/default_runner:ios_default_runner",
    test_host = ":TestApplication",
    deps = [":TestSuiteXCTestNotTaggedLib"],
)
