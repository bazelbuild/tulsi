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

#include "mach_o_file.h"


namespace post_processor {

MachOFile::MachOFile(const std::string &filename,
                     off_t content_offset,
                     size_t content_size,
                     bool swap_byte_ordering,
                     bool verbose) :
    content_offset_(content_offset),
    content_size_(content_size),
    host_byte_order_(NXHostByteOrder()),
    swap_byte_ordering_(swap_byte_ordering) {
  if (verbose) {
    resolver_set_.command_resolver.reset(new MachLoadCommandResolver());
    resolver_set_.symtab_nlist_resolver.reset(new SymtabNListResolver());
  }

  file_ = fopen(filename.c_str(), "rb+");
  fseeko(file_, content_offset_, SEEK_SET);
}

MachOFile::~MachOFile() {
  if (file_) {
    fclose(file_);
  }
}

std::unique_ptr<uint8_t[]> MachOFile::ReadSectionData(
    const std::string &segment_name,
    const std::string &section_name,
    off_t *size,
    size_t trailing_bytes) const {
  off_t offset;
  if (!GetSectionInfo(segment_name,
                      section_name,
                      &offset,
                      size)) {
    return nullptr;
  }

  fseeko(file_, offset, SEEK_SET);
  std::unique_ptr<uint8_t[]> data(new uint8_t[*size + trailing_bytes]);
  if (fread(data.get(), 1, *size, file_) != *size) {
    fprintf(stderr,
            "ERROR: Failed to read section %s:%s.\n",
            segment_name.c_str(),
            section_name.c_str());
    return nullptr;
  }

  if (trailing_bytes) {
    memset(&data[*size], 0, trailing_bytes);
  }

  *size += trailing_bytes;
  return data;
}

MachOFile::WriteReturnCode MachOFile::WriteSectionData(
    const std::string &segment_name,
    const std::string &section_name,
    std::unique_ptr<uint8_t[]> data,
    size_t data_size) {

  off_t file_offset;
  off_t existing_section_size;
  if (!GetSectionInfo(segment_name,
                      section_name,
                      &file_offset,
                      &existing_section_size)) {
    fprintf(stderr,
            "ERROR: Attempt to write non-existent section %s:%s.\n",
            segment_name.c_str(),
            section_name.c_str());
    return WRITE_FAILED;
  }

  // Perform the write immediately if possible.
  if (data_size == existing_section_size) {
    fseeko(file_, file_offset, SEEK_SET);
    if (fwrite(data.get(), 1, data_size, file_) != data_size) {
      fprintf(stderr,
              "ERROR: Failed to write updated section %s:%s.\n",
              segment_name.c_str(),
              section_name.c_str());
      return WRITE_FAILED;
    }

    return WRITE_OK;
  }

  SectionPath key(segment_name, section_name);
  deferred_write_actions_[key] = DeferredWriteData {
      std::move(data),
      data_size,
      (size_t)existing_section_size
  };

  return WRITE_DEFERRED;
}

}  // namespace post_processor
