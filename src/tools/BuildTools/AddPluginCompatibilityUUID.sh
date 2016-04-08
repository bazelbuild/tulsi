#!/bin/bash -eu
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
# Helper script to add Xcode's UUID to an Info.plist's
# DVTPlugInCompatibilityUUIDs key.

if [[ $# < 2 ]]; then
  echo "Usage: $0 <Xcode.app path> <plist to update path>"
  exit 1
fi

readonly xcode_path="$1"
readonly plist_path="$2"

readonly info_path="${xcode_path}/Contents/Info"
readonly uuid=$(defaults read "${info_path}" DVTPlugInCompatibilityUUID)

readonly plistbuddy="xcrun PlistBuddy"
readonly existing_contents=$(${plistbuddy} -c "Print :DVTPlugInCompatibilityUUIDs" "${plist_path}")

for i in ${existing_contents}; do
  if [[ "${uuid}" == "${i}" ]]; then
    echo "Key '${uuid}' already exists."
    exit 0
  fi
done

${plistbuddy} -c "Add :DVTPlugInCompatibilityUUIDs: string '${uuid}'" "${plist_path}"
