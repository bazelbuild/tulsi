#!/bin/bash
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
#
#
# Helper script to invoke Tulsi in commandline mode.
# The path to the Tulsi.app bundle may be provided though the TULSI_APP
# environment variable. If it is not, the script will attempt to find
# Tulsi using the first result returned by the Spotlight index.

# Convenient script to generate Tulsi.xcodeproj for developing Tulsi

set -eu

bazel_path="$(which bazel)"
srcroot="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tulsiproj_path="$srcroot/Tulsi.tulsiproj"

exec "$bazel_path" run //:tulsi -- -- \
  --genconfig "$tulsiproj_path" --bazel "$bazel_path"
