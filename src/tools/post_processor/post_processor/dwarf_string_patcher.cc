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

namespace {

enum DW_FORM {
  DW_FORM_addr = 0x01,
  DW_FORM_block2 = 0x03,
  DW_FORM_block4 = 0x04,
  DW_FORM_data2 = 0x05,
  DW_FORM_data4 = 0x06,
  DW_FORM_data8 = 0x07,
  DW_FORM_string = 0x08,
  DW_FORM_block = 0x09,
  DW_FORM_block1 = 0x0a,
  DW_FORM_data1 = 0x0b,
  DW_FORM_flag = 0x0c,
  DW_FORM_sdata = 0x0d,
  DW_FORM_strp = 0x0e,
  DW_FORM_udata = 0x0f,
  DW_FORM_ref_addr = 0x10,
  DW_FORM_ref1 = 0x11,
  DW_FORM_ref2 = 0x12,
  DW_FORM_ref4 = 0x13,
  DW_FORM_ref8 = 0x14,
  DW_FORM_ref_udata = 0x15,
  DW_FORM_indirect = 0x16,
};

enum DataSize {
  DataSize_DWORD,
  DataSize_QWORD,
};

inline ReturnCode PatchfoAttributeValue(
    std::function<bool(uint64_t, size_t)> write_func,
    const std::map<size_t, size_t> &string_relocation_table,
    DWARFBufferReader *reader,
    uint64_t form_code,
    uint8_t address_size,
    uint16_t dwarf_version,
    std::function<bool(uint64_t *)> read_func);

}  // namespace


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
  std::unique_ptr<uint8_t[]> &&string_data =
      f->ReadSectionData(segment,
                         string_section,
                         &data_length,
                         1 /* null terminate the data */);
  if (!string_data) {
    fprintf(stderr, "Warning: Failed to find __debug_str section.\n");
    return ERR_OK;
  }

  bool data_was_modified = false;

  // Handle the simple in-place update case.
  if (new_prefix_.length() <= old_prefix_.length()) {
    UpdateStringSectionInPlace(reinterpret_cast<char *>(string_data.get()),
                               static_cast<size_t>(data_length),
                               &data_was_modified);
    if (data_was_modified) {
      // Remove the trailing null.
      --data_length;
      return f->WriteSectionData(segment,
                                 string_section,
                                 std::move(string_data),
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
      reinterpret_cast<char *>(string_data.get()),
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

  std::map<size_t, AbbreviationTable> abbreviation_table_map;
  retval = ProcessAbbrevSection(*f, &abbreviation_table_map);
  if (retval != ERR_OK) {
    return retval;
  }

  return PatchInfoSection(f, string_relocation_table, abbreviation_table_map);
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

ReturnCode DWARFStringPatcher::ProcessAbbrevSection(
    const MachOFile &f,
    std::map<size_t, AbbreviationTable> *table_map) const {
  assert(table_map);
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
      auto table_map_it = table_map->find(cur_table_offset);
      if (table_map_it == table_map->end()) {
        auto result = table_map->insert(
            std::make_pair(cur_table_offset, AbbreviationTable()));
        table_map_it = result.first;
      }
      AbbreviationTable &table = table_map_it->second;
      table[abbreviation.abbreviation_code] = std::move(abbreviation);
    }
  }

  return ERR_OK;
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

ReturnCode DWARFStringPatcher::PatchInfoSection(
    MachOFile *f,
    const std::map<size_t, size_t> &string_relocation_table,
    const std::map<size_t, AbbreviationTable> &abbreviation_table_map) const {
  const std::string segment = "__DWARF";
  const std::string section = "__debug_info";
  off_t data_length;
  std::unique_ptr<uint8_t[]> &&data =
    f->ReadSectionData(segment,
                       section,
                       &data_length);
  if (!data) {
    fprintf(stderr, "Failed to find __debug_info section.\n");
    return ERR_INVALID_FILE;
  }

  bool data_was_modified = false;
  DWARFBufferReader reader(data.get(),
                           static_cast<size_t>(data_length),
                           f->swap_byte_ordering());

  while (reader.bytes_remaining() > 0) {
    uint64_t compilation_unit_length;
    uint32_t compilation_unit_length_32;
    if (!reader.ReadDWORD(&compilation_unit_length_32)) {
      fprintf(stderr, "Failed to read DWARF info section.\n");
      return ERR_INVALID_FILE;
    }

    std::function<bool(uint64_t *)> read_func;
    std::function<bool(uint64_t, size_t)> write_func;

    if (compilation_unit_length_32 & 0x80000000) {
      if (!reader.ReadQWORD(&compilation_unit_length)) {
        fprintf(stderr, "Failed to read DWARF info section.\n");
        return ERR_INVALID_FILE;
      }
      read_func = [&](uint64_t *out) -> bool {
        return reader.ReadQWORD(out);
      };
      write_func = [&](uint64_t value, size_t offset) -> bool {
        uint64_t *target = reinterpret_cast<uint64_t*>(data.get() + offset);
        if (f->swap_byte_ordering()) {
          OSSwapInt64(value);
        }
        *target = value;
        data_was_modified = true;
        return true;
      };
    } else {
      compilation_unit_length = compilation_unit_length_32;
      read_func = [&](uint64_t *out) -> bool {
        uint32_t val;
        if (!reader.ReadDWORD(&val)) {
          fprintf(stderr, "Failed to read DWARF info section.\n");
          return false;
        }
        *out = val;
        return true;
      };
      write_func = [&](uint64_t value, size_t offset) -> bool {
        uint32_t actual_value = static_cast<uint32_t>(value);
        uint32_t *target = reinterpret_cast<uint32_t*>(data.get() + offset);
        if (f->swap_byte_ordering()) {
          OSSwapInt32(actual_value);
        }
        *target = actual_value;
        data_was_modified = true;
        return true;
      };
    }

    size_t unit_end_position = reader.read_position() + compilation_unit_length;

    uint16_t dwarf_version;
    if (!reader.ReadWORD(&dwarf_version)) {
      fprintf(stderr, "Failed to read DWARF info section.\n");
      return ERR_INVALID_FILE;
    }

    uint64_t abbrev_offset;
    if (!read_func(&abbrev_offset)) {
      return ERR_INVALID_FILE;
    }
    uint8_t address_size;
    if (!reader.ReadByte(&address_size)) {
      fprintf(stderr, "Failed to read DWARF info section.\n");
      return ERR_INVALID_FILE;
    }

    auto abbreviation_table_it = abbreviation_table_map.find(abbrev_offset);
    if (abbreviation_table_it == abbreviation_table_map.end()) {
      fprintf(stderr,
              "Invalid abbreviation table reference %llu in DWARF info "
                  "section.\n",
              abbrev_offset);
      return ERR_INVALID_FILE;
    }
    const AbbreviationTable &abbreviation_table = abbreviation_table_it->second;

    while (reader.read_position() < unit_end_position) {
      uint64_t abbrev_code;
      if (!reader.ReadULEB128(&abbrev_code)) {
        fprintf(stderr, "Failed to read DWARF info section.\n");
        return ERR_INVALID_FILE;
      }
      if (abbrev_code == 0) {
        // Skip this null padding entry.
        continue;
      }

      auto abbreviation_it = abbreviation_table.find(abbrev_code);
      if (abbreviation_it == abbreviation_table.end()) {
        fprintf(stderr, "Failed to read DWARF info section.\n");
        return ERR_INVALID_FILE;
      }
      const Abbreviation &abbreviation = abbreviation_it->second;
      for (auto &attribute : abbreviation.attributes) {
        ReturnCode retval = PatchfoAttributeValue(write_func,
                                                  string_relocation_table,
                                                  &reader,
                                                  attribute.second,
                                                  address_size,
                                                  dwarf_version,
                                                  read_func);
        if (retval != ERR_OK) {
          fprintf(stderr, "Invalid entry in DWARF info section.\n");
          return retval;
        }
      }
    }
  }

  if (!data_was_modified) {
    return ERR_OK;
  }

  return f->WriteSectionData(segment,
                             section,
                             std::move(data),
                             static_cast<size_t>(data_length));
}

namespace {

inline ReturnCode PatchfoAttributeValue(
    std::function<bool(uint64_t, size_t)> write_func,
    const std::map<size_t, size_t> &string_relocation_table,
    DWARFBufferReader *reader,
    uint64_t form_code,
    uint8_t address_size,
    uint16_t dwarf_version,
    std::function<bool(uint64_t *)> read_func) {
  assert(reader);

  switch (form_code) {
    case DW_FORM_addr:
      reader->SkipForward(address_size);
      return ERR_OK;

    case  DW_FORM_block2: {
      uint16_t block_len;
      if (!reader->ReadWORD(&block_len)) {
        return ERR_INVALID_FILE;
      }
      reader->SkipForward(block_len);
      return ERR_OK;
    }

    case DW_FORM_block4: {
      uint32_t block_len;
      if (!reader->ReadDWORD(&block_len)) {
        return ERR_INVALID_FILE;
      }
      reader->SkipForward(block_len);
      return ERR_OK;
    }

    case DW_FORM_data1:
    case DW_FORM_ref1:
    case DW_FORM_flag:
      reader->SkipForward(1);
      return ERR_OK;

    case DW_FORM_data2:
    case DW_FORM_ref2:
      reader->SkipForward(2);
      return ERR_OK;

    case DW_FORM_data4:
    case DW_FORM_ref4:
      reader->SkipForward(4);
      return ERR_OK;

    case DW_FORM_data8:
    case DW_FORM_ref8:
      reader->SkipForward(8);
      return ERR_OK;

    case DW_FORM_string: {
      std::string str;
      if (!reader->ReadASCIIZ(&str)) {
        return ERR_INVALID_FILE;
      }
      return ERR_OK;
    }

    case DW_FORM_block: {
      uint64_t block_len;
      if (!reader->ReadULEB128(&block_len)) {
        return ERR_INVALID_FILE;
      }
      reader->SkipForward(block_len);
      return ERR_OK;
    }

    case DW_FORM_block1: {
      uint8_t block_len;
      if (!reader->ReadByte(&block_len)) {
        return ERR_INVALID_FILE;
      }
      reader->SkipForward(block_len);
      return ERR_OK;
    }

    case DW_FORM_sdata: {
      // TODO(abaire): Should be a signed LEB128 (if this data is ever used).
      uint64_t data;
      if (!reader->ReadULEB128(&data)) {
        return ERR_INVALID_FILE;
      }
      return ERR_OK;
    }

    case DW_FORM_strp: {
      size_t pos = reader->read_position();
      uint64_t string_offset;
      if (!read_func(&string_offset)) {
        return ERR_INVALID_FILE;
      }

      // TODO(abaire): Patch the offset;
      auto table_relocation = string_relocation_table.find(string_offset);
      if (table_relocation == string_relocation_table.end()) {
        fprintf(stderr,
                "Failed to relocate string offset %llu.\n",
                string_offset);
        return ERR_INVALID_FILE;
      }

      size_t new_offset = table_relocation->second;
      if (new_offset != string_offset) {
        if (!write_func(new_offset, pos)) {
          return ERR_WRITE_FAILED;
        }
      }
      return ERR_OK;
    }

    case DW_FORM_udata:
    case DW_FORM_ref_udata: {
      uint64_t data;
      if (!reader->ReadULEB128(&data)) {
        return ERR_INVALID_FILE;
      }
      return ERR_OK;
    }

    case DW_FORM_ref_addr: {
      if (dwarf_version <= 2) {
        reader->SkipForward(address_size);
        return ERR_OK;
      }
      uint64_t addr;
      if (!read_func(&addr)) {
        return ERR_INVALID_FILE;
      }
      return ERR_OK;
    }

    case DW_FORM_indirect: {
      uint64_t real_encoding;
      if (!reader->ReadULEB128(&real_encoding)) {
        return ERR_INVALID_FILE;
      }
      return PatchfoAttributeValue(write_func,
                                   string_relocation_table,
                                   reader,
                                   real_encoding,
                                   address_size,
                                   dwarf_version,
                                   read_func);
    }

    default:
      fprintf(stderr, "Unknown attribute form 0x%llX\n", form_code);
      return ERR_NOT_IMPLEMENTED;
  }

  return ERR_NOT_IMPLEMENTED;
}

}  // namespace

}  // namespace post_processor
