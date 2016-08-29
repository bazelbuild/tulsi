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

#ifndef POST_PROCESSOR_MACHOFILE_H_
#define POST_PROCESSOR_MACHOFILE_H_

#include <cstdio>
#include <string>
#import <vector>

#include <architecture/byte_order.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <mach-o/swap.h>

#include "return_code.h"


namespace post_processor {

class MachLoadCommandResolver;
class SymtabNListResolver;

/// Provides basic interaction for Mach-O files.
class MachOFile {
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
  MachOFile(const std::string &filename, bool verbose = false);

  ~MachOFile();

  ReturnCode Read();

  inline bool Has32Bit() const { return has_32_bit_; }
  inline bool Has64Bit() const { return has_64_bit_; }

  bool GetSectionInfo32(const std::string &segment_name,
                        const std::string &section_name,
                        size_t *file_offset,
                        size_t *section_size,
                        bool *swap_byte_ordering) const;
  bool GetSectionInfo64(const std::string &segment_name,
                        const std::string &section_name,
                        size_t *file_offset,
                        size_t *section_size,
                        bool *swap_byte_ordering) const;

 private:

  // Provides a set of lookup tables converting data types to strings for
  // verbose-mode output.
  struct ResolverSet {
    std::unique_ptr<MachLoadCommandResolver> command_resolver;
    std::unique_ptr<SymtabNListResolver> symtab_nlist_resolver;
  };

  template <typename HeaderType,
            void (*SwapHeaderFunc)(HeaderType*, NXByteOrder),
            const uint32_t kSegmentLoadCommandID,
            typename MachSegmentType,
            typename SymbolTableType>
  struct MachContent {
    ReturnCode Read(NXByteOrder host_byte_order,
                    FILE *file,
                    const ResolverSet &resolverSet);

    // Absolute offset within the container file to the start of this Mach-O
    // content. Any file offsets used within segments will be relative to this
    // value.
    size_t file_offset;
    bool swap_byte_ordering;
    HeaderType header;
    std::vector<MachSegmentType> segments;
    SymbolTableType symbolTable;
  };

  template <typename SegmentCommandType,
            void (*SwapSegmentCommandFunc)(SegmentCommandType*, NXByteOrder),
            typename SectionType,
            void (*SwapSectionFunc)(SectionType*, uint32_t, NXByteOrder)>
  struct MachSegment {
    ReturnCode Read(bool swap_byte_ordering,
                    NXByteOrder host_byte_order,
                    FILE *file);

    SegmentCommandType command;
    std::vector<SectionType> sections;
  };

  template <typename NListType,
            void (*SwapNlistFunc)(NListType*, uint32_t, NXByteOrder)>
  struct SymbolTable {
    ReturnCode Read(bool swap_byte_ordering,
                    NXByteOrder host_byte_order,
                    size_t file_offset,
                    FILE *file,
                    const ResolverSet &resolverSet);

    std::vector<NListType> debugSymbols;
  };

 private:
  MachOFile() = delete;
  MachOFile(const MachOFile &) = delete;
  MachOFile &operator=(const MachOFile &) = delete;

  ReturnCode PeekMagicHeader(FileFormat *fileFormat, bool *swap);
  ReturnCode ReadHeaderFat(bool swap_byte_ordering);

 private:
  std::string filename_;
  FILE *file_;

  NXByteOrder host_byte_order_;
  FileFormat file_format_;

  bool has_32_bit_;
  bool has_64_bit_;

  typedef MachSegment<segment_command, swap_segment_command,
                      section, swap_section> MachSegment32;
  typedef SymbolTable<struct nlist, swap_nlist> SymbolTable32;
  typedef MachContent<mach_header,
                      swap_mach_header,
                      LC_SEGMENT,
                      MachSegment32,
                      SymbolTable32> MachContent32;
  MachContent32 header_32_;

  typedef MachSegment<segment_command_64, swap_segment_command_64,
                      section_64, swap_section_64> MachSegment64;
  typedef SymbolTable<struct nlist_64, swap_nlist_64> SymbolTable64;
  typedef MachContent<mach_header_64,
                      swap_mach_header_64,
                      LC_SEGMENT_64,
                      MachSegment64,
                      SymbolTable64> MachContent64;
  MachContent64 header_64_;

  ResolverSet resolver_set_;
};

}  // namespace post_processor

#endif  //POST_PROCESSOR_MACHOFILE_H_
