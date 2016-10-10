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
#include <list>
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
  inline off_t content_offset() const { return content_offset_; }

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
  ReturnCode WriteSectionData(const std::string &segment_name,
                              const std::string &section_name,
                              std::unique_ptr<uint8_t[]> data,
                              size_t data_size);

  /// Appends this Mach-O file's content (with any deferred writes applied to
  /// it) to the given buffer.
  virtual ReturnCode SerializeWithDeferredWrites(std::vector<uint8_t> *) = 0;

  inline void VerbosePrint(const char *fmt, ...) const {
    if (!verbose_) {
      return;
    }

    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
  }

 protected:
  // Provides a set of lookup tables converting data types to strings for
  // verbose-mode output.
  struct ResolverSet {
    std::unique_ptr<MachLoadCommandResolver> command_resolver;
    std::unique_ptr<SymtabNListResolver> symtab_nlist_resolver;
  };

  struct DeferredWriteData {
    std::unique_ptr<uint8_t[]> data;
    size_t data_size;
    size_t existing_data_size;
  };

  // (segment, section) used to identify a particular section.
  typedef std::pair<std::string, std::string> SectionPath;

 protected:
  /// Appends the Mach-O file data represented by this instance to the given
  /// buffer.
  ReturnCode LoadBuffer(std::vector<uint8_t> *buffer) const;

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

  bool verbose_;
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

  virtual ReturnCode SerializeWithDeferredWrites(std::vector<uint8_t> *);

 private:
  struct MachSegment {
    ReturnCode Read(bool swap_byte_ordering,
                    NXByteOrder host_byte_order,
                    FILE *file);

    /// Returns the content offset of the section with the given name or -1 if
    /// no such section exists.
    inline off_t GetSectionInfoOffset(const std::string &section_name) const {
      off_t section_info_offset = command_offset + sizeof(command);
      for (const auto &section : sections) {
        if (section_name == section.sectname) {
          return section_info_offset;
        }
        section_info_offset += sizeof(section);
      }
      return -1;
    }

    // Offset of this segment's command entry in the Mach-O file.
    off_t command_offset;
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

  // TODO(abaire): Support multiple segments with the same name.
  struct SegmentResizeInfo {
    // Delta size for the segment overall.
    size_t total_size_adjustment;

    // All of the sections within this segment that will be rewritten by
    // deferred writes.
    std::list<SectionPath> resized_sections;
  };

 private:
  MachOFileImpl() = delete;
  MachOFileImpl(const MachOFileImpl &) = delete;
  MachOFileImpl &operator=(const MachOFileImpl &) = delete;

  inline ReturnCode CalculateDeferredWriteSegmentResizes(
      std::map<std::string, SegmentResizeInfo> *resizes,
      off_t *total_resize) const;

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
      // Update the segment offset such that it is relative to the Mach-O file's
      // start and not the container.
      segment.command_offset -= content_offset_;
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
  command_offset = ftello(file);
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
  std::unique_ptr<char[]> string_table(new char[command.strsize]);
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
ReturnCode
MachOFileImpl<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_PARAMS>::
SerializeWithDeferredWrites(std::vector<uint8_t> *buffer) {
  assert(buffer);
  size_t mach_o_data_offset = buffer->size();
  ReturnCode retval = LoadBuffer(buffer);
  if (retval != ERR_OK) {
    return retval;
  }
  if (deferred_write_actions_.empty()) { return ERR_OK; }

  off_t total_resize = 0;
  std::map<std::string, SegmentResizeInfo> segment_resizes;
  retval = CalculateDeferredWriteSegmentResizes(&segment_resizes,
                                                &total_resize);
  if (retval != ERR_OK) {
    return retval;
  }

  // Handle the segments in reverse order, moving each to its new location and
  // patching relevant offsets.
  auto i = segments_.rbegin();

  // Offset of the first byte after the end of the segment data for the Mach-O
  // image in the buffer.
  size_t segment_data_end_offset =
      (mach_o_data_offset + i->command.fileoff + i->command.filesize);
  size_t trailing_bytes = buffer->size() - segment_data_end_offset;

  buffer->resize(buffer->size() + total_resize);

  // Shift up any trailing data.
  if (trailing_bytes) {
    uint8_t *trailing_data = buffer->data() + segment_data_end_offset;
    uint8_t *trailing_data_new = trailing_data + total_resize;
    memmove(trailing_data_new, trailing_data, trailing_bytes);
  }

  uint8_t *mach_data = buffer->data() + mach_o_data_offset;
  auto i_end = segments_.rend();
  for (; i != i_end && total_resize; ++i) {
    off_t command_offset = i->command_offset;
    const SegmentCommandType &command = i->command;

    uint8_t *segment_data = mach_data + command.fileoff;
    uint8_t *segment_data_new = segment_data + total_resize;

    size_t segment_resize_bytes = 0;
    auto resize = segment_resizes.find(command.segname);
    if (resize != segment_resizes.end()) {
      const SegmentResizeInfo &resize_info = resize->second;
      segment_resize_bytes = resize_info.total_size_adjustment;
    }

    // Resize this segment by shifting the target pointer down.
    segment_data_new -= segment_resize_bytes;
    total_resize -= segment_resize_bytes;

    // Move the existing data to the new location, then patch the segment
    // command to reflect the changes.
    SegmentCommandType *command_new =
        reinterpret_cast<SegmentCommandType *>(mach_data + command_offset);
    size_t new_data_offset = segment_data_new - mach_data;
    command_new->fileoff =
        static_cast<__typeof__(command_new->fileoff)>(new_data_offset);
    command_new->filesize += segment_resize_bytes;

    if (resize == segment_resizes.end()) {
      // If no sections are changed, the existing data is simply moved to the
      // new location.
      memmove(segment_data_new, segment_data, command.filesize);
    } else {
      // Walk the section list, copying unmodified sections and applying the new
      // write data to modified ones, patching the section table offsets as
      // necessary.
      size_t section_info_offset = command_offset + sizeof(SegmentCommandType);
      SectionType *first_section_info =
          reinterpret_cast<SectionType *>(mach_data + section_info_offset);

      // segment_resize_bytes provides the total size increase for this segment,
      // sections that are not being replaced are shifted up by the resize
      // amount and the resize is decremented as replacement sections are
      // injected.
      size_t section_shift = segment_resize_bytes;
      SectionType *cur_section_info =
          &first_section_info[command_new->nsects - 1];
      for (; cur_section_info >= first_section_info; --cur_section_info) {
        SectionPath path(command.segname, cur_section_info->sectname);
        const auto write_data_it = deferred_write_actions_.find(path);
        if (write_data_it == deferred_write_actions_.end()) {
          uint8_t *section_data = mach_data + cur_section_info->offset;
          uint8_t *section_data_new = section_data + section_shift;
          cur_section_info->offset += section_shift;
          memmove(section_data_new, section_data, cur_section_info->size);
        } else {
          const DeferredWriteData &write_data = write_data_it->second;
          section_shift -= write_data.data_size - write_data.existing_data_size;
          cur_section_info->offset += section_shift;
          uint8_t *section_data_new = mach_data + cur_section_info->offset;
          memcpy(section_data_new, write_data.data.get(), write_data.data_size);
        }
      }
    }
  }
  // Any remaining segments are unchanged and can be ignored.

  return ERR_OK;
}

template<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_DECL>
ReturnCode
MachOFileImpl<POST_PROCESSOR_MACHOFILE_H_TEMPLATE_PARAMS>::
CalculateDeferredWriteSegmentResizes(
    std::map<std::string, SegmentResizeInfo> *resizes,
    off_t *total_resize) const {
  assert(resizes && total_resize);

  *total_resize = 0;
  for (const auto &write_action : deferred_write_actions_) {
    const auto &write_data = write_action.second;
    if (write_data.data_size < write_data.existing_data_size) {
      fprintf(stderr, "Shrinking segments is not yet implemented.\n");
      return ERR_NOT_IMPLEMENTED;
    }
    auto adjustment = write_data.data_size - write_data.existing_data_size;

    const auto &segment_name = write_action.first.first;
    auto resize_it = resizes->find(segment_name);
    if (resize_it == resizes->end()) {
      SegmentResizeInfo resize_info;
      resize_info.total_size_adjustment = adjustment;
      resize_info.resized_sections.push_back(write_action.first);
      (*resizes)[segment_name] = std::move(resize_info);
    } else {
      SegmentResizeInfo &resize_info = resize_it->second;
      resize_info.total_size_adjustment += adjustment;
      resize_info.resized_sections.push_back(write_action.first);
    }
    *total_resize += adjustment;
  }

  return ERR_OK;
}

#undef POST_PROCESSOR_MACHOFILE_H_TEMPLATE_DECL
#undef POST_PROCESSOR_MACHOFILE_H_TEMPLATE_PARAMS

}  // namespace post_processor

#endif  // POST_PROCESSOR_MACHOFILE_H_
