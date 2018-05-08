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

"""Bazel flags for architecture / platform combinations.

Every platform has the --apple_platform_type flag set (macOS uses 'darwin'
instead of 'macos').

macOS and iOS use the base --cpu flag, while tvOS and watchOS use --tvos_cpus
and --watchos_cpus respectively.

For iOS apps, the --watchos_cpus flag is also set separately.
"""


def bazel_build_flags(config_platform, arch):
  """Returns an array of command line flags for bazel."""
  if config_platform == 'darwin':
    options = ['--apple_platform_type=macos']
  else:
    options = ['--apple_platform_type=%s' % config_platform]
  if config_platform in ['ios', 'darwin']:
    options.append('--cpu=%s_%s' % (config_platform, arch))
  else:
    options.append('--%scpus=%s' % (config_platform, arch))
  # Set watchos_cpus for bundled watch apps.
  if config_platform == 'ios':
    if arch.startswith('arm'):
      options.append('--watchos_cpus=armv7k')
    else:
      options.append('--watchos_cpus=i386')

  return options
