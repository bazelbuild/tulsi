#!/usr/bin/python
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

"""
Helper script to parse Xcode's pbfilespec's and create a map of file
extension to PBXProj UTI.
"""

import os
import re
import subprocess
import sys


_DICT_START_RE = re.compile(r'\s*{')
_DICT_END_RE = re.compile(r'\s*}')
_IDENTIFIER_RE = re.compile(r'\s*Identifier = ([^;]+);')
_EXTENSIONS_RE = re.compile(r'\s*Extensions = \(([^\)]+)\);')
_EXTENSIONS_MULTILINE_START_RE = re.compile(r'\s*Extensions = \(\s*$')
_EXTENSIONS_MULTILINE_END_RE = re.compile(r'\s*([^\)]*)\);')


# TODO(abaire): Convert this to using plistlib.
# Convert to XML via plutil subproc and parse directly instead of using regex
# hackery.
def _ParseFile(f, utis):
  """Parses the given file and adds contents to the utis dict."""
  dict_started = False
  identifier = None
  extensions = None
  multiline_extensions = None

  line_num = 0
  for line in f:
    line_num += 1
    if _DICT_START_RE.match(line):
      if dict_started:
        print 'Found start while still in dict parsing %s:%d.' % (filename,
                                                                  line_num)
        return 10
      dict_started = True

    if not dict_started:
      continue

    match = _IDENTIFIER_RE.match(line)
    if match:
      identifier = match.group(1).strip('"')

    match = _EXTENSIONS_RE.match(line)
    if match:
      extensions = match.group(1)

    if multiline_extensions is None:
      if _EXTENSIONS_MULTILINE_START_RE.match(line):
        multiline_extensions = []
        continue
    else:
      match = _EXTENSIONS_MULTILINE_END_RE.match(line)
      if match:
        multiline_extensions.append(match.group(1))
        extensions = ' '.join(multiline_extensions)
        multiline_extensions = None
      else:
        multiline_extensions.append(line.strip())
      continue

    if _DICT_END_RE.match(line):
      if identifier and extensions:
        utis[identifier] = extensions
      identifier = None
      extensions = None
      dict_started = False
  return 0


def main(args):
  xcode_path = os.path.abspath(args[1])
  files = subprocess.check_output(['find', xcode_path, '-name', '*.pbfilespec'])

  utis = dict()

  files = [f for f in files.split('\n') if f.strip()]
  for filename in files:
    with open(filename) as f:
      retval = _ParseFile(f, utis)
      if retval != 0:
        return retval

  extensions_to_uti = dict()
  for uti, extensions in utis.iteritems():
    for ext in extensions.split(','):
      ext = ext.strip().strip('"')
      if ext:
        extensions_to_uti[ext] = uti

  for ext in sorted(extensions_to_uti):
    print '  "%s": "%s",' % (ext, extensions_to_uti[ext])
  return 0


if __name__ == '__main__':
  if len(sys.argv) <= 1:
    print 'Usage: %s <Xcode.app path>' % sys.argv[0]
    sys.exit(1)
  sys.exit(main(sys.argv))
