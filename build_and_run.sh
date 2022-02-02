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

unzip_dir="$HOME/Applications"
bazel_path="bazel"
xcode_version="13.2.1"

while getopts ":b:d:x:h" opt; do
  case ${opt} in
    h)
      echo "Usage:"
      echo "    ./build_and_run -h          Display this help message."
      echo "    ./build_and_run -b PATH     Bazel binary used to build Tulsi"
      echo "    ./build_and_run -d PATH     Intall Tulsi App at the provided path"
      echo "    ./build_and_run -x VERSION  Xcode version Tulsi should be built for"
      exit 0
      ;;
    b) bazel_path=$OPTARG;;
    d) unzip_dir=$OPTARG;;
    x) xcode_version=$OPTARG;;
    ?)
      echo "Invalid Option: -$OPTARG" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# build it
$bazel_path build //:tulsi --use_top_level_targets_for_symlinks --xcode_version=$xcode_version
# unzip it
unzip -oq $("$bazel_path" info workspace)/bazel-bin/tulsi.zip -d "$unzip_dir"
# run it
open "$unzip_dir/Tulsi.app"
