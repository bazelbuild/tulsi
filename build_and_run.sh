#!/bin/bash
# Copyright 2018 The Tulsi Authors. All rights reserved.
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

set -eu

readonly unzip_dir="${1:-$HOME/Applications}"

# build it
bazel build //:tulsi
# unzip it
unzip -oq $(bazel info workspace)/bazel-bin/tulsi.zip -d "$unzip_dir"
# run it
open "$unzip_dir/Tulsi.app"
