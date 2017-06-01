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

#ifndef POST_PROCESSOR_COVMAPSECTION_H_
#define POST_PROCESSOR_COVMAPSECTION_H_

#include <sys/types.h>

#include <string>
#include <vector>
#include <unordered_map>

#include "dwarf_buffer_reader.h"
#include "return_code.h"


namespace post_processor {

/// Provides utilities to read and manipulate __llvm_covmap sections in Mach
/// binaries.
/// WARNING: This class is not thread-safe.
class CovmapSection {
 public:
  /// Creates a CovmapSection that may be used to manipulate the given coverage
  /// map data. If "swap_byte_ordering" is true, values read will be translated
  /// to host byte order.
  CovmapSection(std::unique_ptr<uint8_t[]> covmap_section,
                size_t section_length,
                bool swap_byte_ordering);

  /// Parses the section data.
  ReturnCode Parse();

  /// Patches all filenames in the covmap data, replacing any paths that start
  /// with "old_prefix" with "new_prefix".
  /// WARNING: As an optimization, this method may move and invalidate this
  ///          CovmapSection's data member. It is unsafe to invoke any method on
  ///          this instance after this method returns.
  std::unique_ptr<uint8_t[]> PatchFilenamesAndInvalidate(
      const std::unordered_map<std::string,std::string> &prefix_map,
      size_t *section_length,
      bool *data_was_modified);

  inline const uint8_t *section_data() const { return section_data_.get(); }
  inline size_t section_length() const { return section_length_; }

 private:
  /// Models an array of filenames associated with a given coverage mapping.
  struct FilenameGroup {
    void CalculateSize();
    /// Appends the serialized form of this FilenameGroup to the given vector,
    /// inserting additional empty filenames if necessary to pad to min_size.
    bool Serialize(std::vector<uint8_t> *v, size_t min_size = 0) const;

    size_t size;  // Serialized size of this group in bytes.
    off_t offset;  // Offset of this FilenameGroup in the file.
    std::vector<std::string> filenames;
  };

 private:
  /// Reads an LLVM coverage mapping. has_more is set to true if additional
  /// coverage mappings may be read from this covmap section.
  ReturnCode ReadCoverageMapping(bool *has_more);
  /// Reads function records within an LLVM coverage mapping.
  ReturnCode ReadFunctionRecords(uint32_t count);
  /// Reads function records within an LLVM v2 coverage mapping.
  ReturnCode ReadV2FunctionRecords(uint32_t count);
  /// Reads a filename array within an LLVM coverage mapping.
  ReturnCode ReadFilenameGroup(FilenameGroup *);

 private:
  std::unique_ptr<uint8_t[]> section_data_;
  size_t section_length_;
  DWARFBufferReader reader_;
  std::vector<FilenameGroup> filename_groups_;
};

}  // namespace post_processor

#endif  // POST_PROCESSOR_COVMAPSECTION_H_
