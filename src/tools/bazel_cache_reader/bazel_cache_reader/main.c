// Copyright 2018 The Tulsi Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

const char *db_path = "/Library/Application Support/Tulsi"
                      "/Scripts/symbol_cache.db";

// Response handler for each row returned by the sqlite3_exec query below.
static int callback(void *unused, int argc, char **argv, char **az_col_name) {
  if (argc != 3) {
    // If the number of columns returned wasn't 3, return an error.
    return 1;
  } else if (access(argv[1], F_OK) == -1) {
    // If the file does not exist, return early. DebugSymbols.framework will not
    // try to find the dSYM in Spotlight if we give it a non-existent result.
    return 0;
  }

  // Print the plist needed by DebugSymbols.framework to find this dSYM.
  printf("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
         "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
         "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
         "<plist version=\"1.0\">\n"
         "<dict>\n"
         "<key>%s</key>\n"
         "<dict>\n"
         "<key>DBGArchitecture</key>\n"
         "<string>%s</string>\n"
         "<key>DBGDSYMPath</key>\n"
         "<string>%s</string>\n"
         "</dict>\n"
         "</dict>\n"
         "</plist>\n", argv[0], argv[2], argv[1]);
  return 0;
}

// This will be called by DebugSymbols.framework with the UUID as its sole arg.
int main(int argc, const char *argv[]) {

  // Print usage information if no or more than one input was detected.
  if (argc != 2) {
    fprintf(stderr, "Usage: %s UUID\n", argv[0]);
    return 1;
  }

  // The UUID is expected to be exactly 36 characters long,
  // but we want to overestimate our buffers in C.

  // Concatenate a path to the database.
  int returncode;
  sqlite3 *db_handler;
  char path_buffer[512];
  char *home_dir = getenv("HOME");
  strlcpy(path_buffer, home_dir, sizeof(path_buffer));
  strlcat(path_buffer, db_path, sizeof(path_buffer));

  // Open a new connection with the database.
  returncode = sqlite3_open(path_buffer, &db_handler);
  if (returncode != SQLITE_OK) {
    fprintf(stderr,
            "Can't open database: %s\n",
            sqlite3_errmsg(db_handler));
    sqlite3_close(db_handler);
    return 1;
  }

  // Execute a query to retrieve the three fields needed for a
  // DebugSymbols.framework plist.
  char *exec_error_msg = NULL;
  char query_buffer[256];  // should fit in 128 but being safe...
  sqlite3_snprintf(sizeof(query_buffer),
                   query_buffer,
                   "SELECT uuid, dsym_path, architecture "
                   "FROM symbol_cache "
                   "WHERE uuid=\"%q\" "
                   "LIMIT 1;",
                   argv[1]);

  // Query prints out a single plist, via callback above.
  returncode = sqlite3_exec(db_handler,
                            query_buffer,
                            callback,
                            0,
                            &exec_error_msg);
  if (returncode != SQLITE_OK) {
    fprintf(stderr,
            "Couldn't execute query to find UUID: %s, %s\n",
            sqlite3_errmsg(db_handler), exec_error_msg);
    sqlite3_close(db_handler);
    return 1;
  }

  // Close connection when we're finished.
  return sqlite3_close(db_handler);
}
