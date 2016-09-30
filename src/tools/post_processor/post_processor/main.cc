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

#include <assert.h>
#include <stdio.h>

#include <list>
#include <vector>

#include "covmap_section.h"
#include "mach_o_container.h"
#include "mach_o_file.h"


using post_processor::CovmapSection;
using post_processor::MachOContainer;
using post_processor::MachOFile;
using post_processor::ReturnCode;

namespace {

struct PatchSettings {
  std::string filename;  // The path of the file to act on.
  std::string old_prefix;  // The path prefix to be replaced.
  std::string new_prefix;  // The new path prefix to replace old_prefix.

  bool patch_dwarf_symbols;  // Whether or not to patch DWARF paths.
  bool patch_coverage_maps;  // Whether or not to patch LLVM coverage maps.
};

void PrintUsage(const char *executable_name);
int Patch(MachOFile *, const PatchSettings &);

}  // namespace


int main(int argc, const char* argv[]) {
  if (argc < 4) {
    PrintUsage(argv[0]);
    return 1;
  }

  bool verbose = false;
  PatchSettings patch_settings;
  std::vector<std::string> filenames;
  for (int i = 1; i < argc - 2; ++i) {
    const char *arg = argv[i];

    if (!strcmp(arg, "-v") || !strcmp(arg, "--verbose")) {
      verbose = true;
      continue;
    }

    if (!strcmp(arg, "-c") || !strcmp(arg, "--covmap")) {
      patch_settings.patch_coverage_maps = true;
      continue;
    }

    if (!strcmp(arg, "-d") || !strcmp(arg, "--dwarf")) {
      patch_settings.patch_dwarf_symbols = true;
      continue;
    }

    if (arg[0] == '-') {
      fprintf(stderr, "Unknown option %s\n", arg);
      return 1;
    }

    filenames.push_back(arg);
  }

  if (!verbose &&
      !patch_settings.patch_dwarf_symbols &&
      !patch_settings.patch_coverage_maps) {
    PrintUsage(argv[0]);
    return 1;
  }

  patch_settings.old_prefix = argv[argc - 2];
  patch_settings.new_prefix = argv[argc - 1];

  for (auto &filename : filenames) {
    patch_settings.filename = filename;
    MachOContainer f(filename, verbose);
    ReturnCode retval = f.Read();
    if (retval != post_processor::ERR_OK) {
      fprintf(stderr,
              "ERROR: Failed to read Mach-O content from %s.\n",
              filename.c_str());
      return (int)retval;
    }

    if (f.Has32Bit()) {
      int retval = Patch(&f.GetMachOFile32(), patch_settings);
      if (retval) {
        return retval;
      }
    }

    if (f.Has64Bit()) {
      int retval = Patch(&f.GetMachOFile64(), patch_settings);
      if (retval) {
        return retval;
      }
    }

    // TODO(abaire): Process any deferred writes.
  }

  return 0;
}

namespace {

void PrintUsage(const char *executable_name) {
  printf("Usage: %s <mode_options> <object_file> <old_path> <new_path>\n",
         executable_name);
  printf("Modifies the contents of the LLVM coverage map in the given "
             "object_file by replacing any paths that start with \"old_path\" "
             "with \"new_path\".\n");
  printf("\nMode options (at least one is required):\n"
         "\t-v, --verbose:\n"
         "\t  Print out verbose information during Mach parsing.\n"
         "\t-c, --covmap:\n"
         "\t  Patch paths in LLVM coverage maps.\n"
         "\t-d, --dwarf:\n"
         "\t  Patch paths in DWARF symbols.\n");
}

std::unique_ptr<uint8_t[]> PatchCovmapSection(
    const std::string &old_prefix,
    const std::string &new_prefix,
    std::unique_ptr<uint8_t[]> data,
    size_t *data_length,
    bool *data_was_modified,
    bool swap_byte_ordering) {
  if (new_prefix.length() > old_prefix.length()) {
    fprintf(stderr,
            "Cannot grow paths (new_path length must be <= old_path length\n");
    return nullptr;
  }

  CovmapSection covmap_section(std::move(data),
                               *data_length,
                               swap_byte_ordering);

  ReturnCode retval = covmap_section.Parse();
  if (retval != post_processor::ERR_OK) {
    fprintf(stderr, "ERROR: Failed to read LLVM coverage data.\n");
    return nullptr;
  }

  return covmap_section.PatchFilenamesAndInvalidate(old_prefix,
                                                    new_prefix,
                                                    data_length,
                                                    data_was_modified);
}

void UpdateDWARFStringSectionInPlace(char *data,
                                     size_t data_length,
                                     const std::string &old_prefix,
                                     const std::string &new_prefix,
                                     bool *data_was_modified) {
  assert(data && data_was_modified);
  *data_was_modified = false;
  size_t old_prefix_length = old_prefix.length();
  const char *old_prefix_cstr = old_prefix.c_str();
  size_t new_prefix_length = new_prefix.length();
  const char *new_prefix_cstr = new_prefix.c_str();

  // The data table is an offset-indexed contiguous array of null terminated
  // ASCII or UTF-8 strings, so strings whose lengths are being reduced or
  // maintained may be modified in place without changing the run-time
  // behavior.
  // TODO(abaire): Support UTF-8.
  char *start = data;
  char *end = start + data_length;
  while (start < end) {
    size_t entry_length = strlen(start);
    if (entry_length >= old_prefix_length &&
        !memcmp(start, old_prefix_cstr, old_prefix_length)) {
      *data_was_modified = true;
      size_t suffix_length = entry_length - old_prefix_length;
      memcpy(start, new_prefix_cstr, new_prefix_length);
      memmove(start + new_prefix_length,
              start + old_prefix_length,
              suffix_length);
      start[new_prefix_length + suffix_length] = 0;
    }
    start += entry_length + 1;
  }
}

std::unique_ptr<uint8_t[]> UpdateDWARFStringSection(
    char *data,
    size_t data_length,
    const std::string &old_prefix,
    const std::string &new_prefix,
    size_t *new_data_length,
    bool *data_was_modified) {
  assert(data && new_data_length && data_was_modified);
  *data_was_modified = false;
  auto old_prefix_begin = old_prefix.begin();
  auto old_prefix_end = old_prefix.end();
  size_t old_prefix_length = old_prefix.length();
  size_t delta_length = new_prefix.length() - old_prefix.length();

  std::list<std::string> new_string_table;
  *new_data_length = 0;
  char *start = data;
  char *end = start + data_length;
  while (start < end) {
    std::string entry(start);
    size_t len = entry.length();
    start += len + 1;
    *new_data_length += len + 1;

    if (len >= old_prefix_length &&
        std::equal(old_prefix_begin, old_prefix_end, entry.begin())) {
      *data_was_modified = true;
      entry.replace(0, old_prefix_length, new_prefix);
      *new_data_length += delta_length;
    }
    new_string_table.push_back(entry);
  }

  std::unique_ptr<uint8_t[]> new_data(new uint8_t[*new_data_length]);
  uint8_t *offset = new_data.get();
  for (auto str : new_string_table) {
    auto str_length = str.length();
    memcpy(offset, str.c_str(), str_length);
    offset += str_length + 1;
  }

  return new_data;
}

// A null must be appended to the data buffer to ensure that a malformed
// table can be processed in a predictable manner.
// *data_length must be set to the size of the data array in bytes on input
// and will be updated to the returned buffer size on successful output.
std::unique_ptr<uint8_t[]> PatchDWARFStringSection(
    const std::string &old_prefix,
    const std::string &new_prefix,
    std::unique_ptr<uint8_t[]> data,
    size_t *data_length,
    bool *data_was_modified) {

  if (new_prefix.length() <= old_prefix.length()) {
    UpdateDWARFStringSectionInPlace(reinterpret_cast<char *>(data.get()),
                                    *data_length,
                                    old_prefix,
                                    new_prefix,
                                    data_was_modified);
    // Remove the trailing null.
    --(*data_length);
    return data;
  }

  size_t new_data_length;
  std::unique_ptr<uint8_t[]> &&new_data = UpdateDWARFStringSection(
      reinterpret_cast<char *>(data.get()),
      *data_length,
      old_prefix,
      new_prefix,
      &new_data_length,
      data_was_modified);
  // The last entry need not be null terminated.
  *data_length = new_data_length - 1;
  return std::move(new_data);
}

int Patch(MachOFile *f, const PatchSettings &settings) {
  if (settings.patch_coverage_maps) {
    const std::string segment("__DATA");
    const std::string section("__llvm_covmap");
    off_t data_length;
    std::unique_ptr<uint8_t[]> &&data =
        f->ReadSectionData(segment,
                           section,
                           &data_length);
    if (!data) {
      fprintf(stderr, "Warning: Failed to find __llvm_covmap section.\n");
    } else {
      size_t new_data_length = (size_t)data_length;
      bool data_was_modified = false;
      std::unique_ptr<uint8_t[]> &&new_section_data = PatchCovmapSection(
          settings.old_prefix,
          settings.new_prefix,
          std::move(data),
          &new_data_length,
          &data_was_modified,
          f->swap_byte_ordering());
      if (!new_section_data) {
        return 1;
      }

      if (data_was_modified) {
        MachOFile::WriteReturnCode retval = f->WriteSectionData(
            segment,
            section,
            std::move(new_section_data),
            new_data_length);
        if (retval == MachOFile::WRITE_FAILED) {
          return 1;
        }
      }
    }
  }

  if (settings.patch_dwarf_symbols) {
    const std::string segment("__DWARF");
    const std::string section("__debug_str");
    off_t data_length;
    std::unique_ptr<uint8_t[]> &&data =
        f->ReadSectionData(segment,
                           section,
                           &data_length,
                           1 /* null terminate the data */);
    if (!data) {
      fprintf(stderr, "Warning: Failed to find __debug_str section.\n");
    } else {
      size_t new_data_length = (size_t)data_length;
      bool data_was_modified = false;
      std::unique_ptr<uint8_t[]> &&new_section_data = PatchDWARFStringSection(
          settings.old_prefix,
          settings.new_prefix,
          std::move(data),
          &new_data_length,
          &data_was_modified);
      if (!new_section_data) {
        return 1;
      }

      if (data_was_modified) {
        MachOFile::WriteReturnCode retval = f->WriteSectionData(
            segment,
            section,
            std::move(new_section_data),
            new_data_length);
        if (retval == MachOFile::WRITE_FAILED) {
          return 1;
        }
      }
    }
  }

  return 0;
}

}  // namespace
