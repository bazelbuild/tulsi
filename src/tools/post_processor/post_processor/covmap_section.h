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

#include <string>
#include <sys/types.h>
#include <vector>

#include "return_code.h"


namespace post_processor {

/// Provides utilities to read and manipulate __llvm_covmap sections in Mach
/// binaries.
/// WARNING: This class is not thread-safe.
class CovmapSection {
 public:
  /// Creates a CovmapSection that will manipulate the MachO file given by
  /// "filename" with __llvm_covmap data at "section_offset" of
  /// "section_length" bytes. If "swap_byte_ordering" is true, values read will
  /// be translated to host byte order.
  CovmapSection(const std::string &filename,
                off_t section_offset,
                off_t section_length,
                bool swap_byte_ordering);

  ~CovmapSection();

  /// Reads covmap data from the file.
  ReturnCode Read();
  /// Patches all filenames in the covmap data, replacing any paths that start
  /// with "old_prefix" with "new_prefix".
  ReturnCode PatchFilenames(const std::string &old_prefix,
                            const std::string &new_prefix);

 private:
  /// Models an array of filenames associated with a given coverage mapping.
  struct FilenameGroup {
    void CalculateSize();

    off_t size;  // Serialized size of this group in bytes.
    off_t offset;  // Offset of this FilenameGroup in the file.
    std::vector<std::string> filenames;
  };

 private:
  bool ReadDWORD(uint32_t *);
  bool ReadQWORD(uint64_t *);
  /// Reads a DWARF Little Endian Base 128-encoded value.
  bool ReadLEB128(uint *value);

  /// Reads an LLVM coverage mapping. has_more is set to true if additional
  /// coverage mappings may be read from this covmap section.
  ReturnCode ReadCoverageMapping(bool *has_more);
  /// Reads function records within an LLVM coverage mapping.
  ReturnCode ReadFunctionRecords(uint32_t count);
  /// Reads function records within an LLVM v2 coverage mapping.
  ReturnCode ReadV2FunctionRecords(uint32_t count);
  /// Reads a filename array within an LLVM coverage mapping.
  ReturnCode ReadFilenameGroup(FilenameGroup *);

  static size_t EncodedLEB128Size(size_t value);
  /// Little Endian Base 128-encodes a value.
  static std::vector<uint8_t> EncodeLEB128(size_t value);
  ReturnCode WriteLEB128(size_t value);
  /// Writes the given FilenameGroup at its offset, inserting "padding" bytes
  /// as additional empty filenames.
  ReturnCode WriteFilenameGroup(const FilenameGroup &, size_t padding = 0);

 private:
  off_t section_offset_;
  off_t section_end_;
  std::string filename_;
  FILE *file_;

  bool swap_byte_ordering_;

  std::vector<FilenameGroup> filename_groups_;
};

}  // namespace post_processor

#endif  // POST_PROCESSOR_COVMAPSECTION_H_
