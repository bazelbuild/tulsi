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

#include "dwarf_string_patcher.h"

#include "dwarf_buffer_reader.h"
#include "mach_o_file.h"


namespace post_processor {

DWARFStringPatcher::DWARFStringPatcher(
    const std::string &old_prefix,
    const std::string &new_prefix) :
    old_prefix_(old_prefix),
    new_prefix_(new_prefix) {
}

ReturnCode DWARFStringPatcher::Patch(post_processor::MachOFile *f) {
  assert(f);

  const std::string segment("__DWARF");
  const std::string string_section("__debug_str");
  off_t data_length;

  // Note that a NULL is added to the section data buffer to ensure that the
  // table can be processed in a predictable manner (DWARF string tables
  // generally omit the final NULL terminator and use the section size to
  // delimit the final string).
  std::unique_ptr<uint8_t[]> &&data =
      f->ReadSectionData(segment,
                         string_section,
                         &data_length,
                         1 /* null terminate the data */);
  if (!data) {
    fprintf(stderr, "Warning: Failed to find __debug_str section.\n");
    return ERR_OK;
  }

  bool data_was_modified = false;

  // Handle the simple in-place update case.
  if (new_prefix_.length() <= old_prefix_.length()) {
    UpdateStringSectionInPlace(reinterpret_cast<char *>(data.get()),
                               static_cast<size_t>(data_length),
                               &data_was_modified);
    if (data_was_modified) {
      // Remove the trailing null.
      --data_length;
      return f->WriteSectionData(segment,
                                 string_section,
                                 std::move(data),
                                 static_cast<size_t>(data_length));
    }
    return ERR_OK;
  }

  // At this point a full table replacement is required. This necessitates
  // rewriting the string table itself, then walking through the other DWARF
  // sections and updating any string references to point at their new
  // locations.

  size_t new_data_length = (size_t)data_length;
  std::map<size_t, size_t> string_relocation_table;
  std::unique_ptr<uint8_t[]> &&new_data = RewriteStringSection(
      reinterpret_cast<char *>(data.get()),
      static_cast<size_t>(data_length),
      &string_relocation_table,
      &new_data_length,
      &data_was_modified);
  if (!data_was_modified) {
    return ERR_OK;
  }

  // The last entry need not be null terminated.
  --new_data_length;
  ReturnCode retval = f->WriteSectionData(segment,
                                          string_section,
                                          std::move(new_data),
                                          new_data_length);
  if (retval != ERR_OK && retval != ERR_WRITE_DEFERRED) {
    return retval;
  }

  retval = ProcessAbbrevSection(*f);
  if (retval != ERR_OK) {
    return retval;
  }

  // TODO(abaire): Patch string refs in the other DWARF sections.

  return ERR_NOT_IMPLEMENTED;
}

void DWARFStringPatcher::UpdateStringSectionInPlace(
    char *data,
    size_t data_length,
    bool *data_was_modified) {
  assert(data && data_was_modified);

  *data_was_modified = false;
  size_t old_prefix_length = old_prefix_.length();
  const char *old_prefix_cstr = old_prefix_.c_str();
  size_t new_prefix_length = new_prefix_.length();
  const char *new_prefix_cstr = new_prefix_.c_str();

  // The data table is an offset-indexed contiguous array of null terminated
  // ASCII or UTF-8 strings, so strings whose lengths are being reduced or
  // maintained may be modified in place without changing the run-time
  // behavior.
  // TODO(abaire): Support UTF-8.
  char *start = data;
  char *end = start + data_length;
  while (start < end) {
    size_t entry_length = strlen(start);
    if (entry_length >= old_prefix_length &&
        !memcmp(start, old_prefix_cstr, old_prefix_length)) {
      *data_was_modified = true;
      size_t suffix_length = entry_length - old_prefix_length;
      memcpy(start, new_prefix_cstr, new_prefix_length);
      memmove(start + new_prefix_length,
              start + old_prefix_length,
              suffix_length);
      start[new_prefix_length + suffix_length] = 0;
    }
    start += entry_length + 1;
  }
}

std::unique_ptr<uint8_t[]> DWARFStringPatcher::RewriteStringSection(
    char *data,
    size_t data_length,
    std::map<size_t, size_t> *relocation_table,
    size_t *new_data_length,
    bool *data_was_modified) {
  assert(data && relocation_table && new_data_length && data_was_modified);

  relocation_table->clear();
  *data_was_modified = false;
  auto old_prefix_begin = old_prefix_.begin();
  auto old_prefix_end = old_prefix_.end();
  size_t old_prefix_length = old_prefix_.length();
  size_t delta_length = new_prefix_.length() - old_prefix_.length();

  std::list<std::string> new_string_table;
  *new_data_length = 0;
  size_t original_offset = 0;
  size_t new_offset = 0;
  char *start = data;
  char *end = start + data_length;
  while (start < end) {
    std::string entry(start);
    size_t len = entry.length();
    size_t len_plus_one = len + 1;
    start += len_plus_one;
    *new_data_length += len_plus_one;

    if (len >= old_prefix_length &&
        std::equal(old_prefix_begin, old_prefix_end, entry.begin())) {
      *data_was_modified = true;
      entry.replace(0, old_prefix_length, new_prefix_);
      *new_data_length += delta_length;
    }
    new_string_table.push_back(entry);

    (*relocation_table)[original_offset] = new_offset;
    original_offset += len_plus_one;
    new_offset += entry.size() + 1;
  }

  std::unique_ptr<uint8_t[]> new_data(new uint8_t[*new_data_length]);
  uint8_t *offset = new_data.get();
  for (auto str : new_string_table) {
    auto str_length = str.length();
    memcpy(offset, str.c_str(), str_length);
    offset += str_length + 1;
  }

  return new_data;
}

ReturnCode DWARFStringPatcher::ProcessAbbrevSection(const MachOFile &f) const {
  off_t data_length;
  std::unique_ptr<uint8_t[]> &&data = f.ReadSectionData("__DWARF",
                                                        "__debug_abbrev",
                                                        &data_length);
  if (!data) {
    fprintf(stderr, "Warning: Failed to find __debug_abbrev section.\n");
    return ERR_OK;
  }

  DWARFBufferReader reader(data.get(),
                           static_cast<size_t>(data_length),
                           f.swap_byte_ordering());

  size_t cur_table_offset = 0;
  std::map<size_t, AbbreviationTable> table_map;

  while (reader.bytes_remaining()) {
    Abbreviation abbreviation;
    bool end_of_table;
    ReturnCode retval = ProcessAbbreviation(&reader,
                                            &abbreviation,
                                            &end_of_table);
    if (retval != ERR_OK) {
      return retval;
    }

    if (end_of_table) {
      cur_table_offset = reader.read_position();
    } else {
      if (table_map.find(cur_table_offset) == table_map.end()) {
        table_map[cur_table_offset] = AbbreviationTable();
      }
      AbbreviationTable &table = table_map[cur_table_offset];
      table[abbreviation.abbreviation_code] = std::move(abbreviation);
    }
  }

  return ERR_NOT_IMPLEMENTED;
}

ReturnCode DWARFStringPatcher::ProcessAbbreviation(DWARFBufferReader *reader,
                                                   Abbreviation *out,
                                                   bool *end_of_table) const {
  assert(reader && out && end_of_table);
  if (!reader->ReadULEB128(&out->abbreviation_code)) {
    fprintf(stderr, "Failed to read DWARF abbreviation table.\n");
    return ERR_INVALID_FILE;
  }

  *end_of_table = (out->abbreviation_code == 0);
  if (*end_of_table) {
    return ERR_OK;
  }

  if (!reader->ReadULEB128(&out->tag)) {
    fprintf(stderr, "Failed to read DWARF abbreviation table.\n");
    return ERR_INVALID_FILE;
  }

  uint8_t has_children;
  if (!reader->ReadByte(&has_children)) {
    fprintf(stderr, "Failed to read DWARF abbreviation table.\n");
    return ERR_INVALID_FILE;
  }
  out->has_children = has_children != 0;

  out->attributes.clear();
  while (true) {
    uint64_t name, form;
    if (!reader->ReadULEB128(&name) || !reader->ReadULEB128(&form)) {
      fprintf(stderr, "Failed to read DWARF abbreviation table.\n");
      return ERR_INVALID_FILE;
    }

    if (name == 0 && form == 0) {
      break;
    }

    out->attributes.push_back(Attribute(name, form));
  }

  return ERR_OK;
}

}  // namespace post_processor
