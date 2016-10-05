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

#include "covmap_section.h"

#include <assert.h>
#include <libkern/OSByteOrder.h>

#include <list>

namespace {

// Temporary buffer used when reading and writing filenames in
// llvm_covmap data.
// A global buffer is used to avoid any stack implications (which is acceptable
// only because CovmapSection is explicitly not thread-safe).
char filename_buffer[4096];

size_t EncodedLEB128Size(size_t value) {
  size_t encoded_len = 1;
  for (size_t val = value >> 7; val; val >>= 7, ++encoded_len) {
    // Intentionally empty.
  }
  return encoded_len;
}

/// Appends the given value encoded in ULEB128 form to the given vector.
void EncodeLEB128(std::vector<uint8_t> *v, size_t value) {
  do {
    uint8_t b = (uint8_t)(value & 0x7F);
    value >>= 7;
    if (value != 0) {
      b |= 0x80;
    }
    v->push_back(b);
  } while (value != 0);
}

}  // namespace

namespace post_processor {

CovmapSection::CovmapSection(std::unique_ptr<uint8_t[]> covmap_section,
                             size_t section_length,
                             bool swap_byte_ordering) :
    section_data_(std::move(covmap_section)),
    section_length_(section_length),
    reader_(section_data_.get(), section_length, swap_byte_ordering) {
}

ReturnCode CovmapSection::Parse() {
  if (!section_data()) {
    fprintf(stderr,
            "ERROR: Attempt to parse invalid coverage map section data.\n");
    return ERR_INVALID_FILE;
  }

  bool has_more = true;
  while (has_more) {
    ReturnCode retval = ReadCoverageMapping(&has_more);
    if (retval != ERR_OK) {
      return retval;
    }
  }

  if (reader_.bytes_remaining()) {
    fprintf(stderr,
            "ERROR: read covmap offset does not match end of section "
                "(%lu != %lu).\n",
            reader_.read_position(),
            section_length_);
    return ERR_INVALID_FILE;
  }

  return ERR_OK;
}

std::unique_ptr<uint8_t[]> CovmapSection::PatchFilenamesAndInvalidate(
    const std::string &old_prefix,
    const std::string &new_prefix,
    size_t *section_length,
    bool *data_was_modified) {
  assert(section_length && data_was_modified);

  size_t prefix_size = old_prefix.size();
  auto old_prefix_begin = old_prefix.cbegin();
  auto old_prefix_end = old_prefix.cend();

  *data_was_modified = false;
  bool may_write_in_place = true;

  struct FilenameGroupReplacement {
    off_t offset;
    size_t original_size;
    std::vector<uint8_t> serialized_data;
  };

  std::list<FilenameGroupReplacement> replacement_groups;

  for (FilenameGroup g : filename_groups_) {
    FilenameGroup new_group = g;
    new_group.filenames.clear();
    bool needs_rewrite = false;

    for (const auto &filename : g.filenames) {
      if (filename.size() < prefix_size ||
          !std::equal(old_prefix_begin, old_prefix_end, filename.cbegin())) {
        new_group.filenames.push_back(filename);
        continue;
      }

      std::string new_filename = filename;
      new_filename.replace(0, prefix_size, new_prefix);
      new_group.filenames.push_back(new_filename);
      *data_was_modified = true;
      needs_rewrite = true;
    }

    if (!needs_rewrite) { continue; }

    new_group.CalculateSize();
    std::vector<uint8_t> new_filegroup_data;
    if (!new_group.Serialize(&new_filegroup_data, g.size)) {
      return nullptr;
    }

    if (new_filegroup_data.size() != g.size) {
      may_write_in_place = false;
    }

    replacement_groups.push_back(FilenameGroupReplacement {
        g.offset,
        g.size,
        std::move(new_filegroup_data)
    });
  }

  if (!*data_was_modified) {
    *section_length = section_length_;
    return std::move(section_data_);
  }

  // If the new data is the same size as the old, simply overwrite it and return
  // the current buffer.
  if (may_write_in_place) {
    uint8_t *section_data = section_data_.get();
    for (const auto &replacement : replacement_groups) {
      memcpy(section_data + replacement.offset,
             replacement.serialized_data.data(),
             replacement.original_size);
    }

    *section_length = section_length_;
    return std::move(section_data_);
  }

  // TODO(abaire): Produce a new section.
  fprintf(stderr, "Changing covmap section size is not yet supported.\n");
  return nullptr;
}

ReturnCode CovmapSection::ReadCoverageMapping(bool *has_more) {
  assert(has_more);
  uint32_t function_records_size = 0;
  uint32_t filenames_size = 0;
  uint32_t coverage_size = 0;
  uint32_t version = 0;
  if (!(reader_.ReadDWORD(&function_records_size) &&
        reader_.ReadDWORD(&filenames_size) &&
        reader_.ReadDWORD(&coverage_size) &&
        reader_.ReadDWORD(&version))) {
    fprintf(stderr, "Failed to read coverage mapping\n.");
    return ERR_INVALID_FILE;
  }

  version += 1;
  switch (version) {
    case 1:
      {
        ReturnCode retval = ReadFunctionRecords(function_records_size);
        if (retval != ERR_OK) {
          return retval;
        }
      }
      break;

    case 2:
      {
        ReturnCode retval = ReadV2FunctionRecords(function_records_size);
        if (retval != ERR_OK) {
          return retval;
        }
      }
      break;

    default:
      fprintf(stderr, "ERROR: covmap version %d is not supported.\n", version);
      return ERR_INVALID_FILE;
  }

  size_t data_start_offset = reader_.read_position();

  FilenameGroup filename_group;
  ReturnCode retval = ReadFilenameGroup(&filename_group);
  if (retval != ERR_OK) {
    return retval;
  }
  filename_groups_.push_back(filename_group);

  // Skip past the rest of the data.
  size_t data_end_offset = data_start_offset + filenames_size + coverage_size;
  if (data_end_offset > reader_.buffer_length()) {
    fprintf(stderr,
            "ERROR: Invalid covmap data (beyond end of section).\n");
    return ERR_READ_FAILED;
  }
  reader_.SeekToOffset(data_end_offset);

  if (data_end_offset >= reader_.buffer_length()) {
    *has_more = false;
  } else {
    *has_more = true;
    auto misalign = data_end_offset & 0x07;
    if (misalign) {
      reader_.SkipForward(8 - misalign);
    }
  }

  return ERR_OK;
}

ReturnCode CovmapSection::ReadFilenameGroup(
    CovmapSection::FilenameGroup *g) {
  assert(g);

  g->offset = static_cast<off_t>(reader_.read_position());
  uint64_t num_filenames;
  if (!reader_.ReadULEB128(&num_filenames)) {
    fprintf(stderr, "Failed to read filename count\n.");
    return ERR_INVALID_FILE;
  }
  g->size = size_t(reader_.read_position() - g->offset);

  for (auto i = 0; i < num_filenames; ++i) {
    off_t offset = static_cast<off_t>(reader_.read_position());
    uint64_t filename_len;
    if (!reader_.ReadULEB128(&filename_len)) {
      fprintf(stderr, "Failed to read filename length\n.");
      return ERR_INVALID_FILE;
    }

    std::unique_ptr<char[]> filename_heap_buf;
    char *filename_ptr = nullptr;

    size_t bytes_needed = filename_len + 1;
    if (bytes_needed < sizeof(filename_buffer)) {
      filename_ptr = filename_buffer;
    } else {
      filename_heap_buf.reset(new char[bytes_needed]);
      filename_ptr = filename_heap_buf.get();
    }

    filename_ptr[filename_len] = 0;
    if (!reader_.ReadCharacters(filename_ptr, filename_len)) {
      fprintf(stderr, "Failed to read filename at %llu\n", offset);
      return ERR_READ_FAILED;
    }
    g->filenames.push_back(filename_ptr);
    g->size += reader_.read_position() - offset;
  }

  return ERR_OK;
}

ReturnCode CovmapSection::ReadFunctionRecords(uint32_t count) {
  for (auto i = 0; i < count; ++i) {
    uint64_t name_ref;
    uint32_t name_len;
    uint32_t data_size;
    uint64_t func_hash;

    if (!(reader_.ReadQWORD(&name_ref) &&
          reader_.ReadDWORD(&name_len) &&
          reader_.ReadDWORD(&data_size) &&
          reader_.ReadQWORD(&func_hash))) {
      return ERR_INVALID_FILE;
    }

    // TODO(abaire): Store the function records if useful.
  }

  return ERR_OK;
}

ReturnCode CovmapSection::ReadV2FunctionRecords(uint32_t count) {
  for (auto i = 0; i < count; ++i) {
    uint64_t name_md5;
    uint32_t data_size;
    uint64_t func_hash;

    if (!(reader_.ReadQWORD(&name_md5) &&
          reader_.ReadDWORD(&data_size) &&
          reader_.ReadQWORD(&func_hash))) {
      return ERR_INVALID_FILE;
    }

    // TODO(abaire): Store the function records if useful.
  }

  return ERR_OK;
}

void CovmapSection::FilenameGroup::CalculateSize() {
  size = EncodedLEB128Size(filenames.size());

  for (const auto &filename : filenames) {
    size_t filename_size = filename.size();
    size += EncodedLEB128Size(filename_size);
    size += filename_size;
  }
}

bool CovmapSection::FilenameGroup::Serialize(std::vector<uint8_t> *v,
                                             size_t minimum_size) const {
  // Note that the order in which the strings are written must be preserved as
  // encoded coverage data refers to filenames by index. This also means that it
  // is safe to inject additional filenames as they will not be referenced by
  // the coverage mapping data.

  size_t padding = 0;
  if (size < minimum_size) {
    padding = minimum_size - size;
  }

  size_t string_count = filenames.size();
  size_t padding_strings_needed = 0;
  if (padding) {
    padding_strings_needed = (padding + 127) / 128;

    size_t real_string_count_size = EncodedLEB128Size(string_count);
    string_count += padding_strings_needed;
    size_t padded_string_count_size = EncodedLEB128Size(string_count);
    size_t additional_bytes_used =
        padded_string_count_size - real_string_count_size;

    if (additional_bytes_used >= padding) {
      // TODO(abaire): Support this by combining padding across covmaps or by
      //               ignoring the minimum_size and rewriting the entire covmap
      //               section.
      fprintf(stderr,
              "Edge case encountered: Can't fit padding. %lu bytes needed but "
                  "string count requires %lu bytes\n",
              padding,
              additional_bytes_used);
      return false;
    }
  }

  v->reserve(v->size() + size + padding);
  EncodeLEB128(v, string_count);

  for (const auto &filename : filenames) {
    EncodeLEB128(v, filename.size());
    std::copy(filename.cbegin(),
              filename.cend(),
              std::back_inserter<std::vector<uint8_t>>(*v));
  }

  if (padding) {
    memset(filename_buffer, 0, 128);

    // Inject empty 127 character strings (each of which takes 128 bytes),
    // leaving room for one or two final strings and ensuring that the
    // final string can consume at least two bytes of padding. A padding
    // value of 129 is special cased into a 126 char and a 1 char filename
    // whereas any other value will fit into 1 filename.
    filename_buffer[0] = 127;
    while (padding > 129) {
      std::copy(filename_buffer,
                filename_buffer + 128,
                std::back_inserter(*v));
      padding -= 128;
    }

    // Handle the degenerate case where writing 128 bytes would leave 1 byte of
    // padding, which is impossible to express as a length-prefixed filename.
    if (padding == 129) {
      filename_buffer[0] = 126;
      std::copy(filename_buffer,
                filename_buffer + 127,
                std::back_inserter(*v));
      padding -= 127;
    }

    // Write out any remaining padding. At this point there are 128 or fewer
    // bytes left to write. So everything can fit in a single string.
    if (padding) {
      filename_buffer[0] = static_cast<char>(padding - 1);
      if (padding > 1) {
        std::copy(filename_buffer,
                  filename_buffer + padding,
                  std::back_inserter(*v));
      }
    }
  }

  return true;
}

}  // namespace post_processor
