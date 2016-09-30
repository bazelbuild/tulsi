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

#include <assert.h>
#include <unistd.h>

#include <architecture/byte_order.h>
#include <mach-o/loader.h>
#include <mach-o/stab.h>
#include <mach-o/swap.h>

#include <cstdio>
#include <map>
#include <string>
#include <vector>

#include "mach_load_command_resolver.h"
#include "symtab_nlist_resolver.h"
#include "return_code.h"


namespace post_processor {

class MachLoadCommandResolver;
class SymtabNListResolver;

/// Base class for Mach-O file manipulation.
class MachOFile {
 public:
  /// Status codes for write operations.
  enum WriteReturnCode {
    /// The write operation was deferred and will not be performed until
    /// PerformDeferredWrites is invoked.
    WRITE_DEFERRED,

    /// The write was completed successfully.
    WRITE_OK,

    /// The write was attempted but failed.
    WRITE_FAILED
  };

 public:
  /// Constructs a parser instance for MachO content in the the given filename
  /// with the given offest and size. If verbose is true, user-friendly strings
  /// will be emitted as the file is parsed.
  MachOFile(const std::string &filename,
            off_t content_offset,
            size_t content_size,
            bool swap_byte_ordering,
            bool verbose = false);

  virtual ~MachOFile();

  inline bool swap_byte_ordering() const { return swap_byte_ordering_; }
  inline bool has_deferred_writes() const {
    return !deferred_write_actions_.empty();
  }

  virtual ReturnCode Read() = 0;

  /// Extracts information about a section, returning false if it does not
  /// exist.
  virtual bool GetSectionInfo(const std::string &segment_name,
                              const std::string &section_name,
                              off_t *file_offset,
                              off_t *section_size) const = 0;

  /// Reads the data referenced by the given section and returns it. If the
  /// section is found, the returned buffer will contain the data referenced by
  /// the section with trailing_bytes additional 0's following it.
  std::unique_ptr<uint8_t[]> ReadSectionData(const std::string &segment_name,
                                             const std::string &section_name,
                                             off_t *size,
                                             size_t trailing_bytes = 0) const;

  /// Replaces the given section's data with the given data array.
  WriteReturnCode WriteSectionData(const std::string &segment_name,
                                   const std::string &section_name,
                                   std::unique_ptr<uint8_t[]> data,
                                   size_t data_size);

  /// Returns a new buffer containing this Mach-O file's content with any
  /// deferred writes applied to it.
  virtual std::vector<uint8_t> SerializeWithDeferredWrites() = 0;

 protected:
  // Provides a set of lookup tables converting data types to strings for
  // verbose-mode output.
  struct ResolverSet {
    std::unique_ptr<MachLoadCommandResolver> command_resolver;
    std::unique_ptr<SymtabNListResolver> symtab_nlist_resolver;
  };

  // (segment, section) used to identify a particular section.
  typedef std::pair<std::string, std::string> SectionPath;

  struct DeferredWriteData {
    std::unique_ptr<uint8_t[]> data;
    size_t data_size;
    size_t existing_data_size;
  };

 protected:
  // File from which Mach-O content will be read/written.
  FILE *file_;

  // Offset within file_ to the start of the Mach-O content. Any file offsets
  // used within segments will be relative to this value.
  off_t content_offset_;

  // Size of the Mach-O content.
  size_t content_size_;

  NXByteOrder host_byte_order_;
  bool swap_byte_ordering_;

  ResolverSet resolver_set_;

  std::map<SectionPath, DeferredWriteData> deferred_write_actions_;
};


// MachOFileImpl is templated such that the same implementation class may be
// used to support both 32 and 64 bit code. The template parameters are
// collapsed into macros for readability's sake.
#define POST_PROCESSOR_MACHOFILE_H_TEMPLATE_DECL \
    typename HeaderType, \
    void (*SwapHeaderFunc)(HeaderType *, NXByteOrder), \
    const uint32_t kSegmentLoadCommandID, \
    typename SegmentCommandType, \
    void (*SwapSegmentCommandFunc)(SegmentCommandType *, NXByteOrder), \
    typename SectionType, \
    void (*SwapSectionFunc)(SectionType *, uint32_t, NXByteOrder), \
    typename NListType, \
    void (*SwapNlistFunc)(NListType *, uint32_t, NXByteOrder)

#define POST_PROCESSOR_MACHOFILE_H_TEMPLATE_PARAMS \
  HeaderType, \
  SwapHeaderFunc, \
  kSegmentLoadCommandID, \
  SegmentCommandType, \
  SwapSegmentCommandFunc, \
  SectionType, \
  SwapSectionFunc, \
  NListType, \
  SwapNlistFunc

/// Provides basic interaction for a Mach-O data within a container.
template<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_DECL>
class MachOFileImpl: public MachOFile {
 public:
  MachOFileImpl(const std::string &filename,
                off_t content_offset,
                size_t content_size,
                bool swap_byte_ordering,
                bool verbose = false) :
      MachOFile(filename,
                content_offset,
                content_size,
                swap_byte_ordering,
                verbose) {
  }

  ReturnCode Read();

  /// Extracts information about a section, returning false if it does not
  /// exist.
  virtual bool GetSectionInfo(const std::string &segment_name,
                              const std::string &section_name,
                              off_t *file_offset,
                              off_t *section_size) const;

  virtual std::vector<uint8_t> SerializeWithDeferredWrites();

 private:
  struct MachSegment {
    ReturnCode Read(bool swap_byte_ordering,
                    NXByteOrder host_byte_order,
                    FILE *file);

    SegmentCommandType command;
    std::vector<SectionType> sections;
  };

  struct SymbolTable {
    ReturnCode Read(bool swap_byte_ordering,
                    NXByteOrder host_byte_order,
                    size_t file_offset,
                    FILE *file,
                    const ResolverSet &resolverSet);

    std::vector<NListType> debugSymbols;
  };

 private:
  MachOFileImpl() = delete;
  MachOFileImpl(const MachOFileImpl &) = delete;
  MachOFileImpl &operator=(const MachOFileImpl &) = delete;

 private:
  HeaderType header_;
  std::vector<MachSegment> segments_;
  SymbolTable symbol_table_;
};


/// 32-bit MachOFile.
typedef MachOFileImpl<
    mach_header,
    swap_mach_header,
    LC_SEGMENT,
    segment_command,
    swap_segment_command,
    section,
    swap_section,
    struct nlist,
    swap_nlist> MachOFile32;

/// 64-bit MachOFile.
typedef MachOFileImpl<
    mach_header_64,
    swap_mach_header_64,
    LC_SEGMENT_64,
    segment_command_64,
    swap_segment_command_64,
    section_64,
    swap_section_64,
    struct nlist_64,
    swap_nlist_64> MachOFile64;

template<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_DECL>
ReturnCode
MachOFileImpl<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_PARAMS>::Read() {
  if (fread(&header_, sizeof(header_), 1, file_) != 1) {
    return ERR_READ_FAILED;
  }
  if (swap_byte_ordering_) {
    SwapHeaderFunc(&header_, host_byte_order_);
  }

  const MachLoadCommandResolver *command_resolver =
      resolver_set_.command_resolver.get();
  segments_.clear();
  for (auto i = 0; i < header_.ncmds; ++i) {
    load_command cmd;
    if (fread(&cmd, sizeof(cmd), 1, file_) != 1) {
      return ERR_READ_FAILED;
    }
    fseeko(file_, -sizeof(cmd), SEEK_CUR);

    if (swap_byte_ordering_) {
      swap_load_command(&cmd, host_byte_order_);
    }

    if (command_resolver) {
      const std::string &&info = command_resolver->GetLoadCommandInfo(cmd.cmd);
      printf("@%llu: %s\n", ftello(file_), info.c_str());
    }

    if (cmd.cmd == kSegmentLoadCommandID) {
      MachSegment segment;
      ReturnCode retval = segment.Read(swap_byte_ordering_,
                                       host_byte_order_,
                                       file_);
      if (retval != ERR_OK) {
        return retval;
      }
      segments_.push_back(segment);
    } else if (cmd.cmd == LC_SYMTAB) {
      off_t cmd_end_offset = ftello(file_) + cmd.cmdsize;
      ReturnCode retval = symbol_table_.Read(swap_byte_ordering_,
                                           host_byte_order_,
                                           content_offset_,
                                           file_,
                                           resolver_set_);
      if (retval != ERR_OK) {
        return retval;
      }
      fseeko(file_, cmd_end_offset, SEEK_SET);
    } else {
      fseeko(file_, cmd.cmdsize, SEEK_CUR);
    }
  }

  return ERR_OK;
}

template<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_DECL>
ReturnCode
MachOFileImpl<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_PARAMS>::MachSegment::
Read(bool swap_byte_ordering,
     NXByteOrder host_byte_order,
     FILE *file) {
  if (fread(&command, sizeof(command), 1, file) != 1) {
    fprintf(stderr, "Failed to read segment load command.\n");
    return ERR_READ_FAILED;
  }
  if (swap_byte_ordering) {
    SwapSegmentCommandFunc(&command, host_byte_order);
  }

  sections.clear();
  sections.reserve(command.nsects);
  for (auto i = 0; i < command.nsects; ++i) {
    SectionType section;
    if (fread(&section, sizeof(section), 1, file) != 1) {
      fprintf(stderr, "Failed to read section data.\n");
      return ERR_READ_FAILED;
    }
    if (swap_byte_ordering) {
      SwapSectionFunc(&section, 1, host_byte_order);
    }

    sections.push_back(section);
  }

  return ERR_OK;
}

template<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_DECL>
ReturnCode
MachOFileImpl<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_PARAMS>::SymbolTable::
Read(bool swap_byte_ordering,
     NXByteOrder host_byte_order,
     size_t file_offset,
     FILE *file,
     const ResolverSet &resolver_set) {
  symtab_command command;
  if (fread(&command, sizeof(command), 1, file) != 1) {
    fprintf(stderr, "Failed to read symtab command.\n");
    return ERR_READ_FAILED;
  }
  if (swap_byte_ordering) {
    swap_symtab_command(&command, host_byte_order);
  }

  size_t string_table_offset = command.stroff + file_offset;
  std::unique_ptr<char> string_table(new char[command.strsize]);
  fseek(file, string_table_offset, SEEK_SET);
  if (fread(string_table.get(), 1, command.strsize, file) != command.strsize) {
    fprintf(stderr, "Failed to read symbol string table.\n");
    return ERR_READ_FAILED;
  }

  size_t symbol_table_offset = command.symoff + file_offset;
  fseek(file, symbol_table_offset, SEEK_SET);

  const SymtabNListResolver *resolver =
      resolver_set.symtab_nlist_resolver.get();
  for (uint32_t i = 0; i < command.nsyms; ++i) {
    NListType nlist_entry;
    if (fread(&nlist_entry, sizeof(nlist_entry), 1, file) != 1) {
      fprintf(stderr, "Failed to read symbol table nlist data.\n");
      return ERR_READ_FAILED;
    }
    if (swap_byte_ordering) {
      SwapNlistFunc(&nlist_entry, 1, host_byte_order);
    }

    if (!(nlist_entry.n_type & N_STAB)) {
      // Skip non-debug symbols.
      continue;
    }

    if (resolver) {
      const std::string &info = resolver->GetDebugTypeInfo(nlist_entry.n_type);
      printf("%s\n", info.c_str());
    }

    switch (nlist_entry.n_type) {
      case N_SO:
        // TODO(abaire): Implement.
        printf("N_SO - source file name: name,,n_sect,0,address\n");
        printf("\tn_strx: %d - %s\n",
               nlist_entry.n_un.n_strx,
               string_table.get() + nlist_entry.n_un.n_strx);
        printf("\tn_sect: %u\n", nlist_entry.n_sect);
        printf("\tn_desc: %d (expected 0)\n", (int32_t) nlist_entry.n_desc);
        printf("\tn_value (address): %u\n",
               (uint32_t)nlist_entry.n_value);
        break;

      case N_OSO: {
        // TODO(abaire): Implement.
        printf("N_OSO - object file name: name,,0,0,st_mtime\n");
        printf("\tn_strx: %d - %s\n",
               nlist_entry.n_un.n_strx,
               string_table.get() + nlist_entry.n_un.n_strx);
        printf("\tn_sect: %u (expected 0)\n", nlist_entry.n_sect);
        printf("\tn_desc: %d (expected 0)\n", (int32_t) nlist_entry.n_desc);
        time_t modification_time = (time_t) nlist_entry.n_value;
        char buffer[32] = {0};
        struct tm modification_time_tm;
        localtime_r(&modification_time, &modification_time_tm);
        strftime(buffer,
                 sizeof(buffer),
                 "%b %d %H:%M",
                 &modification_time_tm);
        printf("\tst_mtime: %u %s\n",
               (uint32_t)nlist_entry.n_value,
               buffer);
      }
        break;

      default:
        break;
    }
  }

  return ERR_OK;
}

template<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_DECL>
bool
MachOFileImpl<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_PARAMS>::GetSectionInfo(
    const std::string &segment_name,
    const std::string &section_name,
    off_t *file_offset,
    off_t *section_size) const {
  assert(file_offset && section_size);
  for (const auto &segment : segments_) {
    if (segment_name != segment.command.segname) {
      continue;
    }

    for (auto &section : segment.sections) {
      if (section_name != section.sectname) {
        continue;
      }

      *file_offset = section.offset + content_offset_;
      *section_size = section.size;
      return true;
    }
  }

  return false;
}

template<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_DECL>
std::vector<uint8_t>
MachOFileImpl<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_PARAMS>::
SerializeWithDeferredWrites() {
  return std::vector<uint8_t>();
}

#undef POST_PROCESSOR_MACHOFILE_H_TEMPLATE_DECL
#undef POST_PROCESSOR_MACHOFILE_H_TEMPLATE_PARAMS

}  // namespace post_processor

#endif  // POST_PROCESSOR_MACHOFILE_H_
