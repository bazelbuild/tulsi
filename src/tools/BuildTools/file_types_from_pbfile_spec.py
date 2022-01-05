#!/usr/bin/python3
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
"""Helper script to parse Xcode's pbfilespec's and create a map of file extension to PBXProj UTI.
"""

import os
import plistlib
import subprocess
import sys


def _ParseFile(filename):
  """Parses the given file and returns a mapping of extensions to utis."""
  xml_content = subprocess.check_output([
      'plutil', '-convert', 'xml1', '-o', '-', filename
  ])
  result = dict()
  entry_list = plistlib.loads(xml_content)
  assert isinstance(entry_list, list)
  for entry in entry_list:
    identifier = entry.get('Identifier')
    extensions = entry.get('Extensions')
    if identifier and extensions:
      for e in extensions:
        if e:
          result[e] = identifier
  return result


def main(args):
  xcode_path = os.path.abspath(args[1])
  files = subprocess.check_output(['find', xcode_path, '-name', '*.pbfilespec'],
                                  encoding='utf-8')
  files = [f for f in files.split('\n') if f.strip()]
  extensions_to_uti = dict()
  for filename in files:
    extensions_to_uti.update(_ParseFile(filename))
  for ext in sorted(extensions_to_uti):
    print('  "%s": "%s",' % (ext, extensions_to_uti[ext]))
  return 0


if __name__ == '__main__':
  if len(sys.argv) <= 1:
    print('Usage: %s <Xcode.app path>' % sys.argv[0])
    sys.exit(1)
  sys.exit(main(sys.argv))
