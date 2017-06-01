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

#include <list>
#include <map>
#include <string>
#include <vector>
#include <unordered_map>

#include "patcher_base.h"


namespace post_processor {

class DWARFBufferReader;
class MachOFile;

/// Provides utilities to patch DWARF string table entries.
class DWARFStringPatcher : public PatcherBase {
 public:
  DWARFStringPatcher(const std::unordered_map<std::string, std::string> &prefix_map,
                     bool verbose = false) :
      PatcherBase(prefix_map, verbose) {
  }

  virtual ReturnCode Patch(MachOFile *f);

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

  /// Encapsulates the set of information needed to patch a since compilation
  /// unit's line info.
  struct LineInfoPatch {
    uint64_t compilation_unit_length;

    /// The original offset of the unit_length field.
    size_t compilation_unit_length_offset;

    uint64_t header_length;

    /// The original offset of the header_length field.
    size_t header_length_offset;

    // The original offset of the string table.
    size_t string_table_start_offset;
    // The length in bytes of the unmodified string table, including the null
    // delimiter.
    size_t string_table_length;

    std::unique_ptr<uint8_t[]> new_string_table;
    // The updated length of the string table.
    size_t new_string_table_length;
  };

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

  ReturnCode ProcessAbbrevSection(
      const MachOFile &f,
      std::map<size_t, AbbreviationTable> *abbreviation_table) const;

  ReturnCode ProcessAbbreviation(DWARFBufferReader *reader,
                                 Abbreviation *out,
                                 bool *end_of_table) const;

  ReturnCode PatchInfoSection(
    MachOFile *f,
    const std::map<size_t, size_t> &string_relocation_table,
    const std::map<size_t, AbbreviationTable> &abbreviation_table_map) const;

  ReturnCode PatchLineInfoSection(MachOFile *f);
  ReturnCode ProcessLineInfoData(uint8_t *data,
                                 size_t data_length,
                                 bool swap_byte_ordering,
                                 std::list<LineInfoPatch> *patch_actions,
                                 size_t *patched_section_size_increase);

  ReturnCode ApplyLineInfoPatchesInPlace(
      MachOFile *f,
      std::unique_ptr<uint8_t[]> data,
      size_t data_length,
      const std::list<LineInfoPatch> &patch_actions) const;
  ReturnCode ApplyLineInfoPatches(
      MachOFile *f,
      std::unique_ptr<uint8_t[]> existing_data,
      size_t data_length,
      size_t new_data_length,
      const std::list<LineInfoPatch> &patch_actions) const;
};

}  // namespace post_processor

#endif  // POST_PROCESSOR_DWARFSTRINGPATCHER_H_
