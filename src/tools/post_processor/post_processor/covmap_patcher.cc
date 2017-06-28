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

#include "covmap_patcher.h"

#include "mach_o_file.h"
#include "covmap_section.h"

namespace post_processor {

ReturnCode CovmapPatcher::Patch(MachOFile *f) {
  const std::string segment("__DATA");
  const std::string section("__llvm_covmap");
  size_t data_length;
  std::unique_ptr<uint8_t[]> &&data =
      f->ReadSectionData(segment,
                         section,
                         &data_length);
  if (!data) {
    fprintf(stderr, "Warning: Failed to find __llvm_covmap section.\n");
    return ERR_OK;
  }

  CovmapSection covmap_section(std::move(data),
                               data_length,
                               f->swap_byte_ordering());
  ReturnCode retval = covmap_section.Parse();
  if (retval != post_processor::ERR_OK) {
    fprintf(stderr, "ERROR: Failed to read LLVM coverage data.\n");
    return retval;
  }

  size_t new_data_length;
  bool data_was_modified = false;
  std::unique_ptr<uint8_t[]> &&new_section_data = PatchCovmapSection(
      &covmap_section,
      &new_data_length,
      &data_was_modified);
  if (!new_section_data) {
    return post_processor::ERR_INVALID_FILE;
  }

  if (data_was_modified) {
    retval = f->WriteSectionData(segment,
                                 section,
                                 std::move(new_section_data),
                                 new_data_length);
    if (retval != post_processor::ERR_OK &&
        retval != post_processor::ERR_WRITE_DEFERRED) {
      return retval;
    }
  }

  return ERR_OK;
}

std::unique_ptr<uint8_t[]> CovmapPatcher::PatchCovmapSection(
    CovmapSection *section,
    size_t *new_data_length,
    bool *data_was_modified) const {
  assert(section && new_data_length && data_was_modified);
  return section->PatchFilenamesAndInvalidate(prefix_map_,
                                              new_data_length,
                                              data_was_modified);
}

}  // namespace post_processor
