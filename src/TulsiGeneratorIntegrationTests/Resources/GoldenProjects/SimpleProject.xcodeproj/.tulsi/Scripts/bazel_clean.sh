#!/bin/bash
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
#
#
# Bridge between Xcode and Bazel for the "clean" action.
#
# Usage: bazel_clean.sh <bazel_binary_path>
# Note that the ACTION environment variable is expected to be set to "clean".

set -eu

readonly bazel_executable="$1"
shift

if [[ "${ACTION}" != "clean" ]]; then
  exit 0
fi

# Xcode may have generated a bazel-bin directory after a previous clean.
# Remove it to prevent a useless warning.
if [[ -d bazel-bin && ! -L bazel-bin ]]; then
  rm -r bazel-bin
fi

(
  set -x
  "${bazel_executable}" clean
)
