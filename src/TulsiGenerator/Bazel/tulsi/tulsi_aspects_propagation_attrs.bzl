# Copyright 2022 The Tulsi Authors. All rights reserved.
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

"""Attributes to propagate into for Tulsi aspects."""

# List of all of the attributes that can link from a Tulsi-supported rule to a
# Tulsi-supported dependency of that rule.
TULSI_COMPILE_DEPS = [
    "app_clips",  # For ios_application which can include app clips.
    "bundles",
    "deps",
    "extension",
    "extensions",
    "frameworks",
    "settings_bundle",
    "srcs",  # To propagate down onto rules which generate source files.
    "tests",  # for test_suite when the --noexpand_test_suites flag is used.
    "_implicit_tests",  # test_suites without a `tests` attr have an '$implicit_tests' attr instead.
    "test_host",
    "additional_contents",  # macos_application can specify a dict with supported rules as keys.
    # Special attribute name which serves as an escape hatch intended for custom
    # rule creators who use non-standard attribute names for rule dependencies
    # and want those dependencies to show up in Xcode.
    "tulsi_deps",
    "watch_application",
]

def attrs_for_target_kind(rule_kind):
    """Returns the attrs we should propagate/collect for the given target."""
    return TULSI_COMPILE_DEPS
