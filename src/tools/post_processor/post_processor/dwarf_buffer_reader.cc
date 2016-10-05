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

#include "dwarf_buffer_reader.h"

#include <libkern/OSByteOrder.h>

#include <cstdio>


namespace post_processor {

DWARFBufferReader::DWARFBufferReader(const uint8_t *buffer,
                                     size_t buffer_length,
                                     bool swap_byte_ordering) :
    buffer_(buffer),
    buffer_length_(buffer_length),
    swap_byte_ordering_(swap_byte_ordering),
    buffer_end_(buffer + buffer_length),
    read_ptr_(buffer_) {
}

bool DWARFBufferReader::ReadWORD(uint16_t *out) {
  assert(out);
  if (bytes_remaining() < sizeof(*out)) {
    fprintf(stderr, "Failed to read WORD value.\n");
    return false;
  }
  *out = *(reinterpret_cast<const uint16_t*>(read_ptr_));
  read_ptr_ += sizeof(*out);
  if (swap_byte_ordering_) {
    OSSwapInt16(*out);
  }
  return true;
}

bool DWARFBufferReader::ReadDWORD(uint32_t *out) {
  assert(out);
  if (bytes_remaining() < sizeof(*out)) {
    fprintf(stderr, "Failed to read DWORD value.\n");
    return false;
  }
  *out = *(reinterpret_cast<const uint32_t*>(read_ptr_));
  read_ptr_ += sizeof(*out);
  if (swap_byte_ordering_) {
    OSSwapInt32(*out);
  }
  return true;
}

bool DWARFBufferReader::ReadQWORD(uint64_t *out) {
  assert(out);
  if (bytes_remaining() < sizeof(*out)) {
    fprintf(stderr, "Failed to read QWORD value.\n");
    return false;
  }
  *out = *(reinterpret_cast<const uint64_t*>(read_ptr_));
  read_ptr_ += sizeof(*out);
  if (swap_byte_ordering_) {
    OSSwapInt64(*out);
  }
  return true;
}

bool DWARFBufferReader::ReadULEB128(uint64_t *out) {
  assert(out);
  *out = 0;
  uint shift = 0;
  uint8_t b = 0;

  do {
    if (!ReadByte(&b)) {
      fprintf(stderr, "Failed to read ULEB128 value.\n");
      return false;
    }

    *out += ((uint)(b & 0x7F)) << shift;
    shift += 7;
  } while (b & 0x80);

  return true;
}

}  // namespace post_processor
