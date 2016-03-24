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

test_suite(
    name = "explicit_XCTests",
    tests = [
        "//TestSuite/One:XCTest",
        "//TestSuite/Three:XCTest",
        "//TestSuite/Two:XCTest",
    ],
)

test_suite(
    name = "explicit_NonXCTests",
    tests = [
        "//TestSuite/One:NonXCTest",
        "//TestSuite/Three:NonXCTest",
        "//TestSuite/Two:NonXCTest",
    ],
)

test_suite(
    name = "local_tagged_tests",
    tags = ["tagged"],
)

ios_application(
    name = "TestApplication",
    binary = ":Binary",
)

objc_binary(
    name = "Binary",
    srcs = [
        "Binary/srcs/main.m",
    ],
)

ios_test(
    name = "TestSuiteXCTest",
    srcs = ["TestSuite/TestSuiteXCTest.m"],
    tags = ["tagged"],
    xctest_app = ":TestApplication",
)

ios_test(
    name = "TestSuiteNonXCTest",
    srcs = ["TestSuite/TestSuiteNonXCTest.m"],
    tags = ["tagged"],
    xctest = 0,
)

ios_test(
    name = "TestSuiteXCTestNotTagged",
    srcs = ["TestSuite/RootXCTest.m"],
    xctest_app = ":TestApplication",
)
