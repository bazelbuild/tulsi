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

"""Test the schema generated for the shared database."""

import unittest
from symbol_cache_schema import SymbolCacheSchema


SHARED_MEMORY_DB = 'file::memory:?cache=shared'


class TestSymbolCacheSchema(unittest.TestCase):

  def testSchemaColumns(self):
    uuid = 'E56A19D3-CA4C-3760-8855-26C98A9E1865'
    dsym_path = '/usr/bin'  # Using a directory in place of dSYM.
    arch = 'x86_64'

    symbol_cache = SymbolCacheSchema(SHARED_MEMORY_DB)
    connection = symbol_cache.connection
    cursor = connection.cursor()
    cursor.execute('INSERT INTO symbol_cache '
                   'VALUES("%s", "%s", "%s");' %
                   (uuid, dsym_path, arch))
    connection.commit()

    cursor.execute('SELECT uuid, dsym_path, architecture FROM symbol_cache;')
    rows_inserted = cursor.fetchall()
    self.assertEqual(len(rows_inserted), 1)
    self.assertEqual(rows_inserted[0][0], uuid)
    self.assertEqual(rows_inserted[0][1], dsym_path)
    self.assertEqual(rows_inserted[0][2], arch)


if __name__ == '__main__':
  unittest.main()
