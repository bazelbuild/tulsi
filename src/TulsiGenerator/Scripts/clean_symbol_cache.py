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

"""Clean invalid entries from the dSYM symbol cache."""

import os
import sys
from symbol_cache_schema import SQLITE_SYMBOL_CACHE_PATH
from symbol_cache_schema import SymbolCacheSchema


class CleanSymbolCache(object):
  """Cleans all orphaned entries in the DBGScriptCommands database."""

  def CleanMissingDSYMs(self):
    """Removes all entries where dsym_path cannot be found."""
    connection = self.cache_schema.connection
    cursor = connection.cursor()
    cursor.execute('SELECT DISTINCT dsym_path FROM symbol_cache;')
    dsym_path_rows = cursor.fetchall()

    dsym_paths_to_delete = []

    for dsym_path_row in dsym_path_rows:
      dsym_path = dsym_path_row[0]

      # dSYM bundles are directories, not files.
      if not os.path.isdir(dsym_path):
        dsym_paths_to_delete.append(dsym_path)

    if dsym_paths_to_delete:
      paths_to_delete = ['dsym_path = "%s"' % x for x in dsym_paths_to_delete]
      delete_query_where = ' OR '.join(paths_to_delete)
      cursor.execute('DELETE FROM symbol_cache '
                     'WHERE %s' % delete_query_where)

    connection.commit()

  def __init__(self, db_path=SQLITE_SYMBOL_CACHE_PATH):
    self.cache_schema = SymbolCacheSchema(db_path)


if __name__ == '__main__':
  CleanSymbolCache().CleanMissingDSYMs()
  sys.exit(0)
