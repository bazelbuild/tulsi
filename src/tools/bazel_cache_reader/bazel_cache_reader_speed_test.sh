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
# Standalone benchmark to imitate LLDB's image lookups in the first session.
#
# `log enable lldb host` in ~/.lldbinit to see each lookup in LLDB.
#
# Run this script as /usr/bin/time's argument for worst case performance.

for i in `seq 1 410`;
do
  $HOME/Library/Application\ Support/Tulsi/Scripts/bazel_cache_reader $RANDOM > /dev/null
done
