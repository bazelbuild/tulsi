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

# mock BUILD file with an extension referenced by multiple bundles to test that a scheme is
# generated for every host-extension pair.

load(
    "@build_bazel_rules_apple//apple:ios.bzl",
    "ios_application",
    "ios_extension",
)

ios_application(
    name = "ApplicationOne",
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
)

ios_application(
    name = "ApplicationTwo",
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
)
