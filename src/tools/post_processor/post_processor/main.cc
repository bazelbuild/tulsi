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
#include <vector>

#include "covmap_section.h"
#include "mach_o_file.h"


using post_processor::CovmapSection;
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

int Patch32(const MachOFile &, const PatchSettings &);
int Patch64(const MachOFile &, const PatchSettings &);

int PatchCovmapSection(const PatchSettings &settings,
                       size_t offset,
                       size_t length,
                       bool swap_byte_ordering);
int PatchDWARFStringSection(const PatchSettings &settings,
                            size_t offset,
                            size_t length);
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

  // TODO(abaire): Support growing paths by appending sections.
  if (patch_settings.new_prefix.length() > patch_settings.old_prefix.length()) {
    fprintf(stderr,
            "Cannot grow paths (new_path length must be <= old_path length\n");
    return 1;
  }

  for (auto &filename : filenames) {
    patch_settings.filename = filename;
    MachOFile f(filename, verbose);
    {
      ReturnCode retval = f.Read();
      if (retval != post_processor::ERR_OK) {
        fprintf(stderr,
                "ERROR: Failed to read Mach-O content from %s.\n",
                filename.c_str());
        return (int)retval;
      }
    }

    if (f.Has32Bit()) {
      int retval = Patch32(f, patch_settings);
      if (retval) {
        return retval;
      }
    }

    if (f.Has64Bit()) {
      int retval = Patch64(f, patch_settings);
      if (retval) {
        return retval;
      }
    }
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

int Patch32(const MachOFile &f, const PatchSettings &settings) {
  size_t offset = 0, len = 0;
  bool swap_byte_ordering = false;

  if (settings.patch_coverage_maps) {
    if (!f.GetSectionInfo32("__DATA",
                            "__llvm_covmap",
                            &offset,
                            &len,
                            &swap_byte_ordering)) {
      fprintf(stderr, "Warning: Failed to find __llvm_covmap section in "
          "32-bit data.\n");
    } else {
      int retval = PatchCovmapSection(settings,
                                      offset,
                                      len,
                                      swap_byte_ordering);
      if (retval) {
        return retval;
      }
    }
  }

  if (settings.patch_dwarf_symbols) {
    if (!f.GetSectionInfo32("__DWARF",
                            "__debug_str",
                            &offset,
                            &len,
                            &swap_byte_ordering)) {
      fprintf(stderr, "Warning: Failed to find __debug_str section in "
          "32-bit data.\n");
    } else {
      int retval = PatchDWARFStringSection(settings, offset, len);
      if (retval) {
        return retval;
      }
    }
  }
  return 0;
}

int Patch64(const MachOFile &f, const PatchSettings &settings) {
  size_t offset = 0, len = 0;
  bool swap_byte_ordering = false;

  if (settings.patch_coverage_maps) {
    if (!f.GetSectionInfo64("__DATA",
                            "__llvm_covmap",
                            &offset,
                            &len,
                            &swap_byte_ordering)) {
      fprintf(stderr, "Warning: Failed to find __llvm_covmap section in "
          "64-bit data.\n");
    } else {
      int retval = PatchCovmapSection(settings,
                                      offset,
                                      len,
                                      swap_byte_ordering);
      if (retval) {
        return retval;
      }
    }
  }

  if (settings.patch_dwarf_symbols) {
    if (!f.GetSectionInfo64("__DWARF",
                            "__debug_str",
                            &offset,
                            &len,
                            &swap_byte_ordering)) {
      fprintf(stderr, "Warning: Failed to find __debug_str section in "
          "64-bit data.\n");
    } else {
      int retval = PatchDWARFStringSection(settings, offset, len);
      if (retval) {
        return retval;
      }
    }
  }
  return 0;
}

int PatchCovmapSection(const PatchSettings &settings,
                       size_t offset,
                       size_t length,
                       bool swap_byte_ordering) {
  CovmapSection covmap_section(settings.filename,
                               offset,
                               length,
                               swap_byte_ordering);

  ReturnCode retval = covmap_section.Read();
  if (retval != post_processor::ERR_OK) {
    fprintf(stderr, "ERROR: Failed to read LLVM coverage data.\n");
    return (int)retval;
  }

  return (int)covmap_section.PatchFilenames(settings.old_prefix,
                                            settings.new_prefix);
}

int PatchDWARFStringSection(const PatchSettings &settings,
                            size_t offset,
                            size_t length) {
  FILE *file = fopen(settings.filename.c_str(), "rb+");
  if (!file) {
    fprintf(stderr,
            "ERROR: Failed to open %s for r/w.\n",
            settings.filename.c_str());
    return ReturnCode::ERR_OPEN_FAILED;
  }
  fseek(file, offset, SEEK_SET);

  std::unique_ptr<char[]> data(new char[length + 1]);
  if (fread(data.get(), 1, length, file) != length) {
    fprintf(stderr, "ERROR: Failed to read DWARF string section.\n");
    fclose(file);
    return ReturnCode::ERR_READ_FAILED;
  }

  // The data table is an offset-indexed contiguous array of null terminated
  // ASCII or UTF-8 strings, so strings whose lengths are being reduced or
  // maintained may be modified in place without changing the run-time
  // behavior.

  // A null is inserted into the buffer to ensure that a malformed table can be
  // processed in a predictable manner.
  data[length] = 0;

  size_t old_prefix_length = settings.old_prefix.length();
  const char *old_prefix_cstr = settings.old_prefix.c_str();
  size_t new_prefix_length = settings.new_prefix.length();
  const char *new_prefix_cstr = settings.new_prefix.c_str();

  // TODO(abaire): Support UTF-8.
  char *start = data.get();
  char *end = start + length;
  while (start < end) {
    size_t entry_length = strlen(start);
    if (entry_length >= old_prefix_length &&
        !memcmp(start, old_prefix_cstr, old_prefix_length)) {
      size_t suffix_length = entry_length - old_prefix_length;
      memcpy(start, new_prefix_cstr, new_prefix_length);
      memmove(start + new_prefix_length,
              start + old_prefix_length,
              suffix_length);
      start[new_prefix_length + suffix_length] = 0;
    }
    start += entry_length + 1;
  }

  fseek(file, offset, SEEK_SET);
  if (fwrite(data.get(), 1, length, file) != length) {
    fprintf(stderr, "ERROR: Failed to write updated DWARF string section.\n");
    fclose(file);
    return ReturnCode::ERR_WRITE_FAILED;
  }
  fclose(file);

  return ReturnCode::ERR_OK;
}

}  // namespace
