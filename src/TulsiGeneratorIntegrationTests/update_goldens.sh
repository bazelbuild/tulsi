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

set -eu

# Update this whenever the version of Xcode needed to generate the goldens
# changes.
readonly XCODE_VERSION=13.2.1

readonly WORKSPACE=$(bazel info workspace)
readonly TEST_PATH="src/TulsiGeneratorIntegrationTests"
readonly GOLDENS_DIR="${WORKSPACE}/${TEST_PATH}/Resources/GoldenProjects"
readonly TESTLOGS_DIR=$(bazel info bazel-testlogs)
readonly OUTPUT_DIR="${TESTLOGS_DIR}/${TEST_PATH}"

bazel test //src/TulsiGeneratorIntegrationTests:EndToEndGenerationTests \
  --xcode_version="$XCODE_VERSION" --nocheck_visibility \
  --use_top_level_targets_for_symlinks && :

bazel_exit_code=$?

if [[ $bazel_exit_code -eq 3 ]]; then
  TEMP_DIR=$(mktemp -d)
  unzip -qq "${OUTPUT_DIR}/EndToEndGenerationTests/test.outputs/outputs.zip" -d "${TEMP_DIR}"
  rm -rf "${GOLDENS_DIR}"/*
  cp -R "${TEMP_DIR}/tulsi_e2e_output"/* "${GOLDENS_DIR}"
  rm -rf "${TEMP_DIR}"
  echo "Updated goldens for failed tests."
elif [[ $bazel_exit_code -eq 0 ]]; then
  echo "Tests pass, no update necessary."
else
  exit $bazel_exit_code
fi
