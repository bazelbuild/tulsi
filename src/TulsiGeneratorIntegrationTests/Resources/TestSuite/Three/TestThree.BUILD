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

# Simple mock test.

ios_test(
    name = "XCTest",
    srcs = ["XCTest.m"],
    xctest = 1,
    xctest_app = "//TestSuite:TestApplication",
)

ios_test(
    name = "NonXCTest",
    srcs = ["nonXCTest.m"],
    xctest = 0,
)
