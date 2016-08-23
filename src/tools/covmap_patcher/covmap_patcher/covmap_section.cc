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

namespace {

// Temporary buffer used when reading and writing filenames in
// llvm_covmap data.
// A global buffer is used to avoid any stack implications (which is acceptable
// only because CovmapSection is explicitly not thread-safe).
char filename_buffer[4096];

}  // namespace

namespace covmap_patcher {

CovmapSection::CovmapSection(const std::string &filename,
                             size_t section_offset,
                             size_t section_length,
                             bool swap_byte_ordering) :
    filename_(filename),
    file_(nullptr),
    section_offset_(section_offset),
    section_end_(section_offset + section_length),
    swap_byte_ordering_(swap_byte_ordering) {
}

CovmapSection::~CovmapSection() {
  if (file_) {
    fclose(file_);
  }
}

ReturnCode CovmapSection::Read() {
  if (file_) {
    fclose(file_);
  }

  file_ = fopen(filename_.c_str(), "rb+");
  if (!file_) {
    fprintf(stderr, "ERROR: Failed to open %s for r/w.\n", filename_.c_str());
    return ERR_OPEN_FAILED;
  }

  fseek(file_, section_offset_, SEEK_SET);
  bool has_more = true;
  while (has_more) {
    ReturnCode retval = ReadCoverageMapping(&has_more);
    if (retval != ERR_OK) {
      return retval;
    }
  }

  size_t position = (size_t)ftell(file_);
  if (position != section_end_) {
    fprintf(stderr,
            "ERROR: read covmap offset does not match end of section "
                "(%lu != %lu).\n",
            position,
            section_end_);
    return ERR_INVALID_FILE;
  }

  return ERR_OK;
}

ReturnCode CovmapSection::PatchFilenames(
    const std::string &old_prefix,
    const std::string &new_prefix) {
  size_t prefix_size = old_prefix.size();
  auto old_prefix_begin = old_prefix.cbegin();
  auto old_prefix_end = old_prefix.cend();

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
      needs_rewrite = true;
    }

    if (needs_rewrite) {
      new_group.CalculateSize();
      assert(g.size >= new_group.size);
      size_t padding = g.size - new_group.size;
      ReturnCode retval = WriteFilenameGroup(new_group, padding);
      if (retval != ERR_OK) {
        return retval;
      }
    }
  }
  return ERR_OK;
}


ReturnCode CovmapSection::ReadCoverageMapping(bool *has_more) {
  assert(has_more);
  uint32_t function_records_size = 0;
  uint32_t filenames_size = 0;
  uint32_t coverage_size = 0;
  uint32_t version = 0;
  if (!(ReadDWORD(&function_records_size) &&
        ReadDWORD(&filenames_size) &&
        ReadDWORD(&coverage_size) &&
        ReadDWORD(&version))) {
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

  auto data_start = ftell(file_);

  FilenameGroup filename_group;
  ReturnCode retval = ReadFilenameGroup(&filename_group);
  if (retval != ERR_OK) {
    return retval;
  }
  filename_groups_.push_back(filename_group);

  // Skip past the rest of the data.
  auto data_end = data_start + filenames_size + coverage_size;
  if (data_end == section_end_) {
    *has_more = false;
  } else {
    *has_more = true;
    auto misalign = data_end & 0x07;
    if (misalign) {
      data_end += 8 - misalign;
    }
  }
  fseek(file_, data_end, SEEK_SET);

  return ERR_OK;
}

ReturnCode CovmapSection::ReadFilenameGroup(
    CovmapSection::FilenameGroup *g) {
  assert(g);

  g->offset = (size_t)ftell(file_);
  uint num_filenames;
  if (!ReadLEB128(&num_filenames)) {
    fprintf(stderr, "Failed to read filename count\n.");
    return ERR_INVALID_FILE;
  }
  g->size = (size_t)ftell(file_) - g->offset;

  for (auto i = 0; i < num_filenames; ++i) {
    long offset = ftell(file_);
    uint filename_len;
    if (!ReadLEB128(&filename_len)) {
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
    if (fread(filename_ptr, 1, filename_len, file_) != filename_len) {
      fprintf(stderr, "Failed to read filename at %lu\n", offset);
      return ERR_READ_FAILED;
    }
    g->filenames.push_back(filename_ptr);
    g->size += ftell(file_) - offset;
  }

  return ERR_OK;
}

bool CovmapSection::ReadDWORD(uint32_t *out) {
  assert(out);
  if (fread(out, sizeof(*out), 1, file_) != 1) {
    fprintf(stderr, "Failed to read DWORD value.\n");
    return false;
  }
  if (swap_byte_ordering_) {
    OSSwapInt32(*out);
  }
  return true;
}

bool CovmapSection::ReadQWORD(uint64_t *out) {
  assert(out);
  if (fread(out, sizeof(*out), 1, file_) != 1) {
    fprintf(stderr, "Failed to read QWORD value.\n");
    return false;
  }
  if (swap_byte_ordering_) {
    OSSwapInt64(*out);
  }
  return true;
}

bool CovmapSection::ReadLEB128(uint *value) {
  assert(value);
  *value = 0;
  uint shift = 0;
  uint8_t b = 0;

  do {
    if (fread(&b, sizeof(b), 1, file_) != 1) {
      fprintf(stderr, "Failed to read LE128 value.\n");
      return false;
    }

    *value += ((uint)(b & 0x7F)) << shift;
    shift += 7;
  } while (b & 0x80);

  return true;
}

ReturnCode CovmapSection::ReadFunctionRecords(uint32_t count) {
  for (auto i = 0; i < count; ++i) {
    uint64_t name_ref;
    uint32_t name_len;
    uint32_t data_size;
    uint64_t func_hash;

    if (!(ReadQWORD(&name_ref) &&
          ReadDWORD(&name_len) &&
          ReadDWORD(&data_size) &&
          ReadQWORD(&func_hash))) {
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

    if (!(ReadQWORD(&name_md5) &&
          ReadDWORD(&data_size) &&
          ReadQWORD(&func_hash))) {
      return ERR_INVALID_FILE;
    }

    // TODO(abaire): Store the function records if useful.
  }

  return ERR_OK;
}

size_t CovmapSection::EncodedLEB128Size(size_t value) {
  size_t encoded_len = 1;
  for (size_t val = value >> 7; val; val >>= 7, ++encoded_len) {
    // Intentionally empty.
  }
  return encoded_len;
}

std::vector<uint8_t> CovmapSection::EncodeLEB128(size_t value) {
  std::vector<uint8_t> ret;

  do {
    uint8_t b = (uint8_t)(value & 0x7F);
    value >>= 7;
    if (value != 0) {
      b |= 0x80;
    }
    ret.push_back(b);
  } while (value != 0);

  return ret;
}

ReturnCode CovmapSection::WriteLEB128(size_t value) {
  auto encoded_val = CovmapSection::EncodeLEB128(value);
  size_t val_size = encoded_val.size();
  if (fwrite(encoded_val.data(), 1, val_size, file_) != val_size) {
    fprintf(stderr, "Failed to write LE128 value (%lu).\n", value);
    return ERR_WRITE_FAILED;
  }

  return ERR_OK;
}

ReturnCode CovmapSection::WriteFilenameGroup(
    const FilenameGroup &g,
    size_t padding) {

  // The given FilenameGroup is written back to its offset within the file and
  // null strings are inserted to fill "padding" bytes. Note that the order in
  // which the strings are written must be preserved as encoded coverage data
  // refers to filenames by index. This also means that it is safe to inject
  // additional filenames as they will not be referenced by the data.

  fseek(file_, g.offset, SEEK_SET);

  size_t string_count = g.filenames.size();
  size_t padding_strings_needed = 0;
  if (padding) {
    padding_strings_needed = (padding + 127) / 128;

    size_t real_string_count_size = EncodedLEB128Size(string_count);
    string_count += padding_strings_needed;
    size_t padded_string_count_size = EncodedLEB128Size(string_count);
    size_t additional_bytes_used =
        padded_string_count_size - real_string_count_size;

    if (additional_bytes_used >= padding) {
      // TODO(abaire): Support this by combining padding across covmaps.
      fprintf(stderr,
              "Edge case encountered: Can't fit padding. %lu bytes needed but "
                  "string count requires %lu bytes\n",
              padding,
              additional_bytes_used);
      return ERR_INVALID_FILE;
    }
  }

  ReturnCode retval = WriteLEB128(string_count);
  if (retval != ERR_OK) {
    return retval;
  }

  for (const auto &filename : g.filenames) {
    size_t filename_size = filename.size();
    retval = WriteLEB128(filename_size);
    if (retval != ERR_OK) {
      return retval;
    }

    if (fwrite(filename.c_str(), 1, filename_size, file_) != filename_size) {
      fprintf(stderr,
              "Failed to write filename of %lu bytes.\n",
              filename_size);
      return ERR_WRITE_FAILED;
    }
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
      if (fwrite(filename_buffer, 1, 128, file_) != 128) {
        fprintf(stderr, "Failed to write padding filename of 128 bytes.\n");
        return ERR_WRITE_FAILED;
      }
      padding -= 128;
    }

    // Handle the degenerate case where writing 128 bytes would leave 1 byte of
    // padding, which is impossible to express as a length-prefixed filename.
    if (padding == 129) {
      filename_buffer[0] = 126;
      if (fwrite(filename_buffer, 1, 127, file_) != 127) {
        fprintf(stderr, "Failed to write padding filename of 127 bytes\n");
        return ERR_WRITE_FAILED;
      }
      padding -= 127;
    }

    // Write out any remaining padding. At this point there are 128 or fewer
    // bytes left to write. So everything can fit in a single string.
    if (padding) {
      filename_buffer[0] = (char)(padding - 1);
      if (fwrite(filename_buffer, 1, padding, file_) != padding) {
        fprintf(stderr,
                "Failed to write padding filename of %lu bytes\n",
                padding);
        return ERR_WRITE_FAILED;
      }
    }
  }

  return ERR_OK;
}

void CovmapSection::FilenameGroup::CalculateSize() {
  size = 0;
  auto encoded_val = CovmapSection::EncodeLEB128(filenames.size());
  size += encoded_val.size();

  for (const auto &filename : filenames) {
    size_t filename_size = filename.size();
    encoded_val = CovmapSection::EncodeLEB128(filename_size);
    size += encoded_val.size();
    size += filename_size;
  }
}

}  // namespace covmap_patcher
