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

#include <assert.h>
#include <mach-o/stab.h>

#include "mach_load_command_resolver.h"
#include "symtab_nlist_resolver.h"


namespace post_processor {

MachOFile::MachOFile(const std::string &filename, bool verbose) :
    filename_(filename),
    file_(nullptr),
    file_format_(FF_INVALID),
    has_32_bit_(false),
    has_64_bit_(false) {
  host_byte_order_ = NXHostByteOrder();
  if (verbose) {
    resolver_set_.command_resolver.reset(new MachLoadCommandResolver());
    resolver_set_.symtab_nlist_resolver.reset(new SymtabNListResolver());
  }
}

MachOFile::~MachOFile() {
  if (file_) {
    fclose(file_);
  }
}

ReturnCode MachOFile::Read() {
  if (file_) {
    fclose(file_);
  }

  file_ = fopen(filename_.c_str(), "rb");
  if (!file_) {
    return ERR_OPEN_FAILED;
  }

  bool swap_byte_ordering;
  ReturnCode retval = PeekMagicHeader(&file_format_, &swap_byte_ordering);
  if (retval != ERR_OK) {
    return retval;
  }

  switch(file_format_) {
    case FF_32:
      header_32_.file_offset = 0;
      header_32_.swap_byte_ordering = swap_byte_ordering;
      retval = header_32_.Read(host_byte_order_,
                               file_,
                               resolver_set_);
      has_32_bit_ = true;
      break;

    case FF_64:
      header_64_.file_offset = 0;
      header_64_.swap_byte_ordering = swap_byte_ordering;
      retval = header_64_.Read(host_byte_order_,
                               file_,
                               resolver_set_);
      has_64_bit_ = true;
      break;

    case FF_FAT:
      retval = ReadHeaderFat(swap_byte_ordering);
      break;

    case FF_INVALID:
      return ERR_INVALID_FILE;
  }

  return retval;
}

ReturnCode MachOFile::PeekMagicHeader(FileFormat *fileFormat,
                                                 bool *swap) {
  assert(fileFormat && swap);
  *fileFormat = FF_INVALID;
  *swap = false;

  uint32_t magic_header;
  size_t magic_header_size = sizeof(magic_header);
  if (fread(&magic_header, magic_header_size, 1, file_) != 1) {
    fprintf(stderr, "Failed to read magic header.\n");
    return ERR_READ_FAILED;
  }
  fseek(file_, -magic_header_size, SEEK_CUR);

  switch (magic_header) {
    case MH_CIGAM:
      *swap = true;
    case MH_MAGIC:
      *fileFormat = FF_32;
      break;

    case MH_CIGAM_64:
      *swap = true;
    case MH_MAGIC_64:
      *fileFormat = FF_64;
      break;

    case FAT_CIGAM:
      *swap = true;
    case FAT_MAGIC:
      *fileFormat = FF_FAT;
      break;

    default:
      fprintf(stderr, "Invalid magic header value 0x%X.\n", magic_header);
      return ERR_INVALID_FILE;
  }

  return ERR_OK;
}

template <typename HeaderType,
          void (*SwapHeaderFunc)(HeaderType*, NXByteOrder),
          const uint32_t kSegmentLoadCommandID,
          typename MachSegmentType,
          typename SymbolTableNListType>
ReturnCode
MachOFile::MachContent<HeaderType,
                       SwapHeaderFunc,
                       kSegmentLoadCommandID,
                       MachSegmentType,
                       SymbolTableNListType>::Read(
    NXByteOrder host_byte_order,
    FILE *file,
    const ResolverSet &resolver_set) {
  file_offset = (size_t)ftell(file);
  if (fread(&header, sizeof(header), 1, file) != 1) {
    return ERR_READ_FAILED;
  }
  if (swap_byte_ordering) {
    SwapHeaderFunc(&header, host_byte_order);
  }

  const MachLoadCommandResolver *command_resolver =
      resolver_set.command_resolver.get();
  segments.clear();
  for (auto i = 0; i < header.ncmds; ++i) {
    load_command cmd;
    if (fread(&cmd, sizeof(cmd), 1, file) != 1) {
      return ERR_READ_FAILED;
    }
    fseek(file, -sizeof(cmd), SEEK_CUR);

    if (swap_byte_ordering) {
      swap_load_command(&cmd, host_byte_order);
    }

    if (command_resolver) {
      const std::string &&info = command_resolver->GetLoadCommandInfo(cmd.cmd);
      printf("@%lu: %s\n", ftell(file), info.c_str());
    }

    if (cmd.cmd == kSegmentLoadCommandID) {
      MachSegmentType segment;
      ReturnCode retval = segment.Read(swap_byte_ordering,
                                       host_byte_order,
                                       file);
      if (retval != ERR_OK) {
        return retval;
      }
      segments.push_back(segment);
    } else if (cmd.cmd == LC_SYMTAB) {
      size_t cmd_end_offset = (size_t)ftell(file) + cmd.cmdsize;
      ReturnCode retval = symbolTable.Read(swap_byte_ordering,
                                           host_byte_order,
                                           file_offset,
                                           file,
                                           resolver_set);
      if (retval != ERR_OK) {
        return retval;
      }
      fseek(file, cmd_end_offset, SEEK_SET);
    } else {
      fseek(file, cmd.cmdsize, SEEK_CUR);
    }
  }

  return ERR_OK;
}

template <typename SegmentCommandType,
          void (*SwapSegmentCommandFunc)(SegmentCommandType*, NXByteOrder),
          typename SectionType,
          void (*SwapSectionFunc)(SectionType*, uint32_t, NXByteOrder)>
ReturnCode
MachOFile::MachSegment<SegmentCommandType,
                       SwapSegmentCommandFunc,
                       SectionType,
                       SwapSectionFunc>::Read(
    bool swap_byte_ordering,
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

template <typename NListType,
          void (*SwapNlistFunc)(NListType*, uint32_t, NXByteOrder)>
ReturnCode MachOFile::SymbolTable<NListType, SwapNlistFunc>::Read(
    bool swap_byte_ordering,
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
      const std::string &&info = resolver->GetDebugTypeInfo(nlist_entry.n_type);
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

      case N_OSO:
        {
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

ReturnCode MachOFile::ReadHeaderFat(bool swap_byte_ordering) {
  fat_header header;
  if (fread(&header, sizeof(header), 1, file_) != 1) {
    fprintf(stderr, "Failed to read fat header.\n");
    return ERR_READ_FAILED;
  }
  if (swap_byte_ordering) {
    swap_fat_header(&header, host_byte_order_);
  }

  std::unique_ptr<fat_arch[]> archs(new fat_arch[header.nfat_arch]);
  if (!archs.get()) {
    fprintf(stderr, "Failed to allocate %d fat headers.\n", header.nfat_arch);
    return ERR_OUT_OF_MEMORY;
  }

  if (fread(archs.get(),
            sizeof(archs[0]),
            header.nfat_arch,
            file_) != header.nfat_arch) {
    fprintf(stderr, "Failed to read %d fat headers.\n", header.nfat_arch);
    return ERR_READ_FAILED;
  }
  if (swap_byte_ordering) {
    swap_fat_arch(archs.get(), header.nfat_arch, host_byte_order_);
  }

  for (auto i = 0; i < header.nfat_arch; ++i) {
    fat_arch arch_info = archs[i];
    fseek(file_, arch_info.offset, SEEK_SET);

    FileFormat format;
    bool swap;
    ReturnCode retval = PeekMagicHeader(&format, &swap);
    if (retval != ERR_OK) {
      return retval;
    }

    if (format == FF_32) {
      header_32_.swap_byte_ordering = swap;
      retval = header_32_.Read(host_byte_order_,
                               file_,
                               resolver_set_);
      if (retval != ERR_OK) {
        return retval;
      }
      has_32_bit_ = true;
    } else if (format == FF_64) {
      header_64_.swap_byte_ordering = swap;
      retval = header_64_.Read(host_byte_order_,
                               file_,
                               resolver_set_);
      if (retval != ERR_OK) {
        return retval;
      }
      has_64_bit_ = true;
    } else {
      fprintf(stderr,
              "Unexpectedly found nested file type %d in FAT arch section.\n",
              format);
      return ERR_INVALID_FILE;
    }
  }

  return ERR_OK;
}

bool MachOFile::GetSectionInfo32(const std::string &segment_name,
                                 const std::string &section_name,
                                 size_t *file_offset,
                                 size_t *section_size,
                                 bool *swap_byte_ordering) const {
  assert(file_offset && section_size);
  if (!has_32_bit_) {
    return false;
  }
  if (swap_byte_ordering) {
    *swap_byte_ordering = header_32_.swap_byte_ordering;
  }

  for (auto &segment : header_32_.segments) {
    if (segment_name != segment.command.segname) {
      continue;
    }

    for (auto &section : segment.sections) {
      if (section_name != section.sectname) {
        continue;
      }

      *file_offset = section.offset + header_32_.file_offset;
      *section_size = section.size;
      return true;
    }
  }

  return false;
}

bool MachOFile::GetSectionInfo64(const std::string &segment_name,
                                 const std::string &section_name,
                                 size_t *file_offset,
                                 size_t *section_size,
                                 bool *swap_byte_ordering) const {
  assert(file_offset && section_size);
  if (!has_64_bit_) {
    return false;
  }
  if (swap_byte_ordering) {
    *swap_byte_ordering = header_64_.swap_byte_ordering;
  }

  for (auto &segment : header_64_.segments) {
    if (segment_name != segment.command.segname) {
      continue;
    }

    for (auto &section : segment.sections) {
      if (section_name != section.sectname) {
        continue;
      }

      *file_offset = section.offset + header_64_.file_offset;
      *section_size = section.size;
      return true;
    }
  }

  return false;
}

}  // namespace post_processor
