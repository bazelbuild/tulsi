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

set -eu

readonly tulsi_bundle_id=com.google.Tulsi
readonly app_bundle_path=$(mdfind kMDItemCFBundleIdentifier=${tulsi_bundle_id})
readonly tulsi_path=${app_bundle_path}/Contents/MacOS/Tulsi

if [[ $# == 0 ]]; then
  exec "${tulsi_path}" -- -h
else
  exec "${tulsi_path}" -- "$@"
fi
