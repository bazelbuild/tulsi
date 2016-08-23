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

#include "MachLoadCommandResolver.h"


namespace covmap_patcher {

MachOFile::MachOFile(const std::string &filename, bool verbose) :
    filename_(filename),
    file_(nullptr),
    file_format_(FF_INVALID),
    has_32_bit_(false),
    has_64_bit_(false),
    command_resolver_(nullptr) {
  host_byte_order_ = NXHostByteOrder();
  if (verbose) {
    command_resolver_.reset(new MachLoadCommandResolver());
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
                               command_resolver_.get());
      break;

    case FF_64:
      header_64_.file_offset = 0;
      header_64_.swap_byte_ordering = swap_byte_ordering;
      retval = header_64_.Read(host_byte_order_,
                               file_,
                               command_resolver_.get());
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
          typename MachSegmentType>
ReturnCode
MachOFile::MachContent<HeaderType,
                       SwapHeaderFunc,
                       kSegmentLoadCommandID,
                       MachSegmentType>::Read(
    NXByteOrder host_byte_order,
    FILE *file,
    const MachLoadCommandResolver *command_resolver) {
  file_offset = (size_t)ftell(file);
  if (fread(&header, sizeof(header), 1, file) != 1) {
    return ERR_READ_FAILED;
  }
  if (swap_byte_ordering) {
    SwapHeaderFunc(&header, host_byte_order);
  }

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
      printf("%s\n", info.c_str());
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
                               command_resolver_.get());
      if (retval != ERR_OK) {
        return retval;
      }
      has_32_bit_ = true;
    } else if (format == FF_64) {
      header_64_.swap_byte_ordering = swap;
      retval = header_64_.Read(host_byte_order_,
                               file_,
                               command_resolver_.get());
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
                                 bool *swap_byte_ordering) {
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
                                 bool *swap_byte_ordering) {
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

}  // namespace covmap_patcher
