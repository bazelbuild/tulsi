# Copyright 2017 The Tulsi Authors. All rights reserved.
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

# Bad mock BUILD file for aspect testing.

load(
    "@build_bazel_rules_apple//apple:ios.bzl",
    "ios_application",
)

ios_application(
    name = "Application",
    bundle_id = "com.example.invalid",
    families = [
        "iphone",
        "ipad",
    ],
    infoplists = ["Info.plist"],
    launch_images = ["Binary_Assets_LaunchImage"],
    launch_storyboard = "Application/Launch.storyboard",
    lolno = "binaary",
    minimum_os_version = "10.0",
)
