// Copyright 2016 The Tulsi Authors. All rights reserved.
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

#ifndef POST_PROCESSOR_DWARFSTRINGPATCHER_H_
#define POST_PROCESSOR_DWARFSTRINGPATCHER_H_

#include <sys/types.h>

#include <map>
#include <string>
#include <vector>

#include "return_code.h"


namespace post_processor {

class DWARFBufferReader;
class MachOFile;

/// Provides utilities to patch DWARF string table entries.
class DWARFStringPatcher {
 public:
  DWARFStringPatcher(const std::string &old_prefix,
                     const std::string &new_prefix);

  ReturnCode Patch(MachOFile *f);

 private:
  // DWARF attributes consist of a "name" value and a form type.
  typedef std::pair<uint64_t, uint64_t> Attribute;

  struct Abbreviation {
    uint64_t abbreviation_code;
    uint64_t tag;
    bool has_children;
    std::vector<Attribute> attributes;
  };

  typedef std::map<uint64_t, Abbreviation> AbbreviationTable;

 private:
  void UpdateStringSectionInPlace(char *data,
                                  size_t data_length,
                                  bool *data_was_modified);

  std::unique_ptr<uint8_t[]> RewriteStringSection(
      char *data,
      size_t data_length,
      std::map<size_t, size_t> *relocation_table,
      size_t *new_data_length,
      bool *data_was_modified);

  ReturnCode ProcessAbbrevSection(const MachOFile &f) const;
  ReturnCode ProcessAbbreviation(DWARFBufferReader *reader,
                                 Abbreviation *out,
                                 bool *end_of_table) const;

 private:
  const std::string old_prefix_;
  const std::string new_prefix_;
};

}  // namespace post_processor

#endif  // POST_PROCESSOR_DWARFSTRINGPATCHER_H_
