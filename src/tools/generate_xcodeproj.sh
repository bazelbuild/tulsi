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
# Helper script to invoke Tulsi in commandline mode.
# The path to the Tulsi.app bundle may be provided though the TULSI_APP
# environment variable. If it is not, the script will attempt to find
# Tulsi using the first result returned by the Spotlight index.

set -eu

# If the TULSI_APP environment variable is set, use it.
if [[ "${TULSI_APP:-}" != "" ]]; then
  readonly app_bundle_path="${TULSI_APP}"
else
  readonly tulsi_bundle_id=com.google.Tulsi
  app_bundle_path=$(mdfind kMDItemCFBundleIdentifier=${tulsi_bundle_id} | head -1)
fi

if [[ "${app_bundle_path}" == "" ]]; then
  if [[ -f "/Applications/Tulsi.app/Contents/MacOS/Tulsi" ]]; then
    readonly app_bundle_path="/Applications/Tulsi.app"
  else
    echo "Tulsi.app could not be located. Please ensure that you have built\
 Tulsi and that it exists in an accessible location."

    exit 1
  fi
fi

readonly tulsi_path="${app_bundle_path}/Contents/MacOS/Tulsi"

if [[ $# == 0 ]]; then
  exec "${tulsi_path}" -- -h
else
  echo "Using Tulsi at ${app_bundle_path}"
  exec "${tulsi_path}" -- "$@"
fi
