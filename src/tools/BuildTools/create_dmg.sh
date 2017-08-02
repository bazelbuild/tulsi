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
#
# Build script to generate a dmg image for Tulsi.

if [[ $# < 1 ]]; then
  echo "Usage: $0 <source_bundle> [options]"
  echo "Options:"
  echo "  -o <output_file>: Full path to the target .dmg file. Defaults to"
  echo "                    source_bundle with .app replaced by .dmg."
  echo "  --volume <name>: Name for the dmg volume. Defaults to source_bundle"
  echo "                   with no path or file extension."
  echo "  -f <absolute_file_path>: An additional file to be added to the dmg."
  echo "                           May be used multiple times."
  exit 1
fi

readonly src_bundle_path="$1"
readonly src_bundle_file=$(basename "${src_bundle_path}")
readonly app_name="${src_bundle_file%.*}"
if [[ "${app_name}" == "" ]]; then
  echo "Invalid source bundle ${src_bundle_file} (must end with .app)."
  exit 1
fi

shift
additional_files=()
while [[ $# > 0 ]]; do
  case "$1" in
    -f)
      shift
      if [[ ! "$1" = /* ]]; then
        echo "Error: -f files must be absolute paths, \"$1\" is invalid."
        exit 1
      fi
      additional_files+=("$1")
      ;;
    -o)
      shift
      output_file="$1"
      ;;
    --volume)
      volname="$1"
      ;;
    *)
      echo "WARNING: Unknown option '$1'"
      ;;
  esac
  shift
done

if [[ "${output_file:-}" == "" ]]; then
  output_file="${app_name}.dmg"
fi
readonly tmp_file="${output_file}.tmp.dmg"

if [[ "${volname:-}" == "" ]]; then
  volname="${app_name}"
fi

if [[ -e "${output_file}" ]]; then
  rm "${output_file}"
fi

# Grab the absolute path to the temp file for cleanup in case an error occurs
# while in a subdirectory.
readonly tmp_file_dirname=$(dirname "${tmp_file}")
readonly tmp_file_basename=$(basename "${tmp_file}")
if [[ ! -d "${tmp_file_dirname}" ]]; then
  mkdir -p "${tmp_file_dirname}"
fi
pushd "${tmp_file_dirname}" > /dev/null
readonly tmp_file_abs_path="$(pwd)/${tmp_file_basename}"
popd > /dev/null
function cleanup {
  rm -f "${tmp_file_abs_path}"
}
trap cleanup exit

# Echo commands for the log.
set -x

# Create a dmg from the source bundle.
hdiutil create -ov \
        -srcfolder "${src_bundle_path}" \
        -volname "${volname}" \
        -fs HFS+ \
        -format UDRW "${tmp_file}"

# Open the dmg and add a link to /Applications and any additional files.
readonly devs=$(hdiutil attach "${tmp_file}" | cut -f 1)
readonly dev=$(echo ${devs} | cut -f 1 -d ' ')

# The following actions are performed in a subshell to ensure that the mounted
# image is detached in the case of an error (via a separate exit trap).
(
  function close_dmg {
    hdiutil detach $dev
  }
  trap close_dmg exit

  pushd "/Volumes/${volname}" > /dev/null

  ln -s /Applications .

  if [[ ${#additional_files[@]} > 0 ]]; then
    readonly files_dir="Tulsi Additional Files"
    mkdir "${files_dir}"
    pushd "${files_dir}" > /dev/null
    for f in "${additional_files[@]}"; do
      cp "${f}" .
    done
    popd > /dev/null
    additional_files_command="set position of item \"${files_dir}\" of container window to {80, 230}"
    window_bottom=470
  else
    additional_files_command=""
    window_bottom=340
  fi

  popd > /dev/null
)

# Convert the dmg to a compressed read-only one.
hdiutil convert "${tmp_file}" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "${output_file}"
