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

#ifndef POST_PROCESSOR_DWARFBUFFERREADER_H_
#define POST_PROCESSOR_DWARFBUFFERREADER_H_

#include <assert.h>
#include <string>

namespace post_processor {

/// Provides basic functions to manage a byte buffer as a collection of
/// DWARF-style primitives (e.g., ULEB128-encoded values, QWORDS, etc...).
class DWARFBufferReader {
 public:
  /// WARNING: This class does not take ownership of the given buffer and it is
  /// the responsibility of the user to ensure that the buffer is valid for the
  /// life of this instance.
  DWARFBufferReader(const uint8_t *buffer,
                    size_t buffer_length,
                    bool swap_byte_ordering);

  inline size_t buffer_length() const { return buffer_length_; }

  /// The offset to the current read position from the beginning of the buffer.
  inline size_t read_position() const { return read_ptr_ - buffer_; }

  inline size_t bytes_remaining() const {
    if (read_ptr_ >= buffer_end_) { return 0; }
    return buffer_end_ - read_ptr_;
  }

  inline bool ReadByte(uint8_t *byte) {
    if (bytes_remaining() < 1) { return false; }
    *byte = *read_ptr_;
    ++read_ptr_;
    return true;
  }

  bool ReadWORD(uint16_t *);
  bool ReadDWORD(uint32_t *);
  bool ReadQWORD(uint64_t *);

  /// Reads a DWARF Little Endian Base 128-encoded value.
  bool ReadULEB128(uint64_t *out);

  /// Copies length characters into the given buffer.
  inline bool ReadCharacters(char *buffer, size_t length) {
    assert(buffer);
    if (length > bytes_remaining()) { return false; }
    memcpy(buffer, read_ptr_, length);
    read_ptr_ += length;
    return true;
  }

  /// Reads a null-terminated ASCII string into the given buffer.
  bool ReadASCIIZ(std::string *out);

  /// Sets the read pointer to the given offset. No validation is performed so
  /// care must be taken to ensure that the given offset is not past the end of
  /// the buffer.
  inline void SeekToOffset(size_t offset) { read_ptr_ = buffer_ + offset; }

  /// Advances the read pointer by the given number of bytes. No validation is
  /// performed so care must be taken to ensure that the pointer is not advanced
  /// past the end of the buffer.
  inline void SkipForward(size_t bytes) { read_ptr_ += bytes; }

 private:
  uint8_t const *buffer_;
  size_t buffer_length_;
  bool swap_byte_ordering_;

  // Convenience pointer to one byte past the end of the buffer_;
  uint8_t const *buffer_end_;

  const uint8_t *read_ptr_;
};

}  // namespace post_processor

#endif  // POST_PROCESSOR_DWARFBUFFERREADER_H_
