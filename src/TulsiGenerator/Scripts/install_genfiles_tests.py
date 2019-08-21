# Copyright 2018 The Tulsi Authors. All rights reserved.
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

"""Test for install_genfiles.py."""

import os
import unittest

import install_genfiles

DOES_EXIST_DATA = {
    'generated_sources': [
        ('src/TulsiGenerator/Scripts/install_genfiles.py',
         'install_genfiles.py'),
    ],
}


DOES_NOT_EXIST_DATA = {
    'generated_sources': [('src/does/not/exist.txt',
                           'exist.txt')],
}


class TestInstallForData(unittest.TestCase):

  def testSrcDoeNotExist(self):
    tmpdir = os.environ['TEST_TMPDIR']
    installer = install_genfiles.Installer('.', output_root=tmpdir)
    installer.InstallForData(DOES_NOT_EXIST_DATA)
    self.assertFalse(os.path.lexists(
        os.path.join(tmpdir, 'bazel-tulsi-includes/x/x/exist.txt')))

  def testSrcDoesExist(self):
    tmpdir = os.environ['TEST_TMPDIR']
    installer = install_genfiles.Installer('.', output_root=tmpdir)
    installer.InstallForData(DOES_EXIST_DATA)
    # Must use lexists because we create a link but use the wrong exec root,
    # so the symlink is not valid.
    self.assertTrue(os.path.lexists(
        os.path.join(tmpdir, 'bazel-tulsi-includes/x/x/install_genfiles.py')))

if __name__ == '__main__':
  unittest.main()
