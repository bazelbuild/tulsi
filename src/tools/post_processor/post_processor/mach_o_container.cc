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

#include "mach_o_container.h"

#include <assert.h>
#include <sys/stat.h>

#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach-o/swap.h>

#include "mach_o_file.h"


namespace post_processor {

MachOContainer::MachOContainer(const std::string &filename, bool verbose) :
    filename_(filename),
    file_(nullptr),
    verbose_(verbose),
    content_32_(nullptr),
    content_64_(nullptr),
    host_byte_order_(NXHostByteOrder()) {
}

MachOContainer::~MachOContainer() {
  if (file_) {
    fclose(file_);
  }
}

namespace {

off_t GetFileSize(FILE *file) {
  struct stat file_stat;

  int fd = fileno(file);
  if (fstat(fd, &file_stat)) {
    fprintf(stderr, "Failed to retrieve file size.\n");
    return 0;
  }
  return file_stat.st_size;
}

}  // namespace

ReturnCode MachOContainer::Read() {
  if (file_) {
    fclose(file_);
  }

  file_ = fopen(filename_.c_str(), "rb");
  if (!file_) {
    return ERR_OPEN_FAILED;
  }

  bool swap_byte_ordering;
  FileFormat file_format;
  ReturnCode retval = PeekMagicHeader(&file_format, &swap_byte_ordering);
  if (retval != ERR_OK) {
    return retval;
  }

  switch(file_format) {
    case FF_32: {
      off_t content_size = GetFileSize(file_);
      return Read32BitContainer(swap_byte_ordering, content_size);
    }

    case FF_64: {
      off_t content_size = GetFileSize(file_);
      return Read64BitContainer(swap_byte_ordering, content_size);
    }

    case FF_FAT:
      return ReadFatContainer(swap_byte_ordering);

    case FF_INVALID:
      return ERR_INVALID_FILE;
  }
}

ReturnCode MachOContainer::PerformDeferredWrites() {
  return ERR_OK;
}

ReturnCode MachOContainer::PeekMagicHeader(FileFormat *fileFormat,
                                           bool *swap) {
  assert(fileFormat && swap);
  *fileFormat = FF_INVALID;
  *swap = false;

  uint32_t magic_header;
  off_t magic_header_size = sizeof(magic_header);
  if (fread(&magic_header, magic_header_size, 1, file_) != 1) {
    fprintf(stderr, "Failed to read magic header.\n");
    return ERR_READ_FAILED;
  }
  fseeko(file_, -magic_header_size, SEEK_CUR);

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

ReturnCode MachOContainer::ReadFatContainer(bool swap_byte_ordering) {
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
    const fat_arch &arch_info = archs[i];
    fseeko(file_, arch_info.offset, SEEK_SET);

    FileFormat format;
    bool swap;
    ReturnCode retval = PeekMagicHeader(&format, &swap);
    if (retval != ERR_OK) {
      return retval;
    }

    if (format == FF_32) {
      retval = Read32BitContainer(swap, arch_info.size);
      if (retval != ERR_OK) {
        return retval;
      }
    } else if (format == FF_64) {
      retval = Read64BitContainer(swap, arch_info.size);
      if (retval != ERR_OK) {
        return retval;
      }
    } else {
      fprintf(stderr,
              "Unexpectedly found nested file type %d in fat arch section.\n",
              format);
      return ERR_INVALID_FILE;
    }
  }

  return ERR_OK;
}

ReturnCode MachOContainer::Read32BitContainer(bool swap_byte_ordering,
                                              off_t content_size) {
  off_t content_offset = ftello(file_);
  content_32_.reset(new MachOFile32(filename_,
                                    content_offset,
                                    content_size,
                                    swap_byte_ordering,
                                    verbose_));
  return content_32_->Read();
}

ReturnCode MachOContainer::Read64BitContainer(bool swap_byte_ordering,
                                              off_t content_size) {
  off_t content_offset = ftello(file_);
  content_64_.reset(new MachOFile64(filename_,
                                    content_offset,
                                    content_size,
                                    swap_byte_ordering,
                                    verbose_));
  return content_64_->Read();
}

}  // namespace post_processor
