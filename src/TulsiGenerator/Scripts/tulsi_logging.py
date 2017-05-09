# Copyright 2017 The Tulsi Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Logging routines used by Tulsi scripts."""


class Logger(object):
  """Tulsi specific logging."""

  def log_action(self, action_name, action_id, seconds):
    del action_id  # Unused by this logger.
    # Prints to stdout for display in the Xcode log
    print '<*> %s completed in %0.3f ms' % (action_name, seconds * 1000)
