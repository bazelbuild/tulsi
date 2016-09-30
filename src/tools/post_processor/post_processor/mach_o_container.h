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

#ifndef POST_PROCESSOR_MACHOCONTAINER_H_
#define POST_PROCESSOR_MACHOCONTAINER_H_

#include <architecture/byte_order.h>

#include <string>

#include "return_code.h"


namespace post_processor {

class MachOFile;

/// Provides basic interaction for containers of Mach-O files.
/// NOTE: The current implementation allows at most one 32-bit image and one
///       64-bit image. The behavior for containers with multiple 32- or 64-bit
///       is undefined.
class MachOContainer {
 public:
  enum FileFormat {
      FF_INVALID,
      FF_32,  // 32-bit Mach data.
      FF_64,  // 64-bit Mach data.
      FF_FAT  // Fat data (containing 0 or 1 of both 32-bit and 64-bit images).
  };

 public:
  /// Constructs a parser instance for the given filename. If verbose is true,
  /// user-friendly strings will be emitted as the file is parsed.
  MachOContainer(const std::string &filename, bool verbose = false);

  ~MachOContainer();

  ReturnCode Read();
  ReturnCode PerformDeferredWrites();

  inline bool Has32Bit() const { return static_cast<bool>(content_32_); }
  inline bool Has64Bit() const { return static_cast<bool>(content_64_); }

  inline MachOFile &GetMachOFile32() { return *content_32_.get(); }
  inline MachOFile &GetMachOFile64() { return *content_64_.get(); }

 private:
  MachOContainer() = delete;
  MachOContainer(const MachOContainer &) = delete;
  MachOContainer &operator=(const MachOContainer &) = delete;

  ReturnCode PeekMagicHeader(FileFormat *fileFormat, bool *swap);
  ReturnCode ReadFatContainer(bool swap_byte_ordering);
  ReturnCode Read32BitContainer(bool swap_byte_ordering, off_t content_size);
  ReturnCode Read64BitContainer(bool swap_byte_ordering, off_t content_size);

 private:
  std::string filename_;
  FILE *file_;

  bool verbose_;

  NXByteOrder host_byte_order_;
  std::unique_ptr<MachOFile> content_32_;
  std::unique_ptr<MachOFile> content_64_;
};

}  // namespace post_processor

#endif  // POST_PROCESSOR_MACHOCONTAINER_H_
