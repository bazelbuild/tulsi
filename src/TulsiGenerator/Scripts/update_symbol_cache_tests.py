#!/usr/bin/python3
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

"""Test updating entries in the dSYM cache."""

import unittest
import sqlite3
from update_symbol_cache import UpdateSymbolCache


SHARED_MEMORY_DB = 'file::memory:?cache=shared'


class TestUpdatingSymbolCache(unittest.TestCase):

  def testUpdatingTwoDifferentUUIDs(self):
    uuid = '706D191F-BFB6-35EE-9817-ED494F68ED76'
    dsym_path = '/usr/bin'  # Using a directory in place of dSYM.
    arch = 'i386'

    uuid2 = 'E56A19D3-CA4C-3760-8855-26C98A9E1865'
    dsym_path2 = '/usr/bin'  # Using the same directory (like fat binary)
    arch2 = 'x86_64'

    update_symbol_cache = UpdateSymbolCache(SHARED_MEMORY_DB)
    err_msg = update_symbol_cache.UpdateUUID(uuid, dsym_path, arch)
    self.assertFalse(err_msg)
    err_msg = update_symbol_cache.UpdateUUID(uuid2, dsym_path2, arch2)
    self.assertFalse(err_msg)

    connection = sqlite3.connect(SHARED_MEMORY_DB)
    cursor = connection.cursor()
    cursor.execute('SELECT uuid, dsym_path, architecture '
                   'FROM symbol_cache '
                   'ORDER BY uuid;')
    rows_inserted = cursor.fetchall()
    self.assertEqual(len(rows_inserted), 2)
    self.assertEqual(rows_inserted[0][0], uuid)
    self.assertEqual(rows_inserted[0][1], dsym_path)
    self.assertEqual(rows_inserted[0][2], arch)
    self.assertEqual(rows_inserted[1][0], uuid2)
    self.assertEqual(rows_inserted[1][1], dsym_path2)
    self.assertEqual(rows_inserted[1][2], arch2)

  def testUpdatingWithChangedUUIDs(self):
    uuid = 'E56A19D3-CA4C-3760-8855-26C98A9E1865'
    dsym_path = '/usr/bin'  # Using a directory in place of dSYM.
    arch = 'x86_64'

    update_symbol_cache = UpdateSymbolCache(SHARED_MEMORY_DB)
    err_msg = update_symbol_cache.UpdateUUID(uuid, dsym_path, arch)
    self.assertFalse(err_msg)

    connection = sqlite3.connect(SHARED_MEMORY_DB)
    cursor = connection.cursor()
    cursor.execute('SELECT uuid, dsym_path, architecture FROM symbol_cache;')
    rows_inserted = cursor.fetchall()
    self.assertEqual(len(rows_inserted), 1)
    self.assertEqual(rows_inserted[0][0], uuid)
    self.assertEqual(rows_inserted[0][1], dsym_path)
    self.assertEqual(rows_inserted[0][2], arch)

    uuid2 = '706D191F-BFB6-35EE-9817-ED494F68ED76'

    err_msg = update_symbol_cache.UpdateUUID(uuid2, dsym_path, arch)
    self.assertFalse(err_msg)

    connection = sqlite3.connect(SHARED_MEMORY_DB)
    cursor = connection.cursor()
    cursor.execute('SELECT uuid, dsym_path, architecture FROM symbol_cache;')
    rows_inserted = cursor.fetchall()
    self.assertEqual(len(rows_inserted), 1)
    self.assertEqual(rows_inserted[0][0], uuid2)
    self.assertEqual(rows_inserted[0][1], dsym_path)
    self.assertEqual(rows_inserted[0][2], arch)


if __name__ == '__main__':
  unittest.main()
