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

#include "covmap_patcher.h"
#include "dwarf_string_patcher.h"
#include "mach_o_container.h"
#include "mach_o_file.h"


using post_processor::CovmapPatcher;
using post_processor::DWARFStringPatcher;
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

  bool verbose;  // Enables verbose output.
};

void PrintUsage(const char *executable_name);
ReturnCode Patch(MachOFile *, const PatchSettings &);

}  // namespace


int main(int argc, const char* argv[]) {
  if (argc < 4) {
    PrintUsage(argv[0]);
    return 127;
  }

  PatchSettings patch_settings;
  patch_settings.patch_coverage_maps = false;
  patch_settings.patch_dwarf_symbols = false;
  patch_settings.verbose = false;
  std::vector<std::string> filenames;
  for (int i = 1; i < argc - 2; ++i) {
    const char *arg = argv[i];

    if (!strcmp(arg, "-v") || !strcmp(arg, "--verbose")) {
      patch_settings.verbose = true;
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
      return 127;
    }

    filenames.push_back(arg);
  }

  if (!patch_settings.verbose &&
      !patch_settings.patch_dwarf_symbols &&
      !patch_settings.patch_coverage_maps) {
    PrintUsage(argv[0]);
    return 127;
  }

  patch_settings.old_prefix = argv[argc - 2];
  patch_settings.new_prefix = argv[argc - 1];

  for (auto &filename : filenames) {
    patch_settings.filename = filename;
    MachOContainer f(filename, patch_settings.verbose);
    ReturnCode retval = f.Read();
    if (retval != post_processor::ERR_OK) {
      fprintf(stderr,
              "ERROR: Failed to read Mach-O content from %s.\n",
              filename.c_str());
      return retval;
    }

    if (f.Has32Bit()) {
      retval = Patch(&f.GetMachOFile32(), patch_settings);
      if (retval != post_processor::ERR_OK) {
        return retval;
      }
    }

    if (f.Has64Bit()) {
      retval = Patch(&f.GetMachOFile64(), patch_settings);
      if (retval != post_processor::ERR_OK) {
        return retval;
      }
    }

    retval = f.PerformDeferredWrites();
    if (retval != post_processor::ERR_OK) {
      return retval;
    }
  }

  if (patch_settings.verbose) {
    printf("Patching completed successfully.\n");
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

ReturnCode Patch(MachOFile *f, const PatchSettings &settings) {
  if (settings.patch_coverage_maps) {
    CovmapPatcher patcher(settings.old_prefix,
                          settings.new_prefix,
                          settings.verbose);

    ReturnCode retval = patcher.Patch(f);
    if (retval != post_processor::ERR_OK &&
        retval != post_processor::ERR_WRITE_DEFERRED) {
      return retval;
    }
  }

  if (settings.patch_dwarf_symbols) {
    DWARFStringPatcher patcher(settings.old_prefix,
                               settings.new_prefix,
                               settings.verbose);
    ReturnCode retval = patcher.Patch(f);
    if (retval != post_processor::ERR_OK &&
        retval != post_processor::ERR_WRITE_DEFERRED) {
      return retval;
    }
  }

  return post_processor::ERR_OK;
}

}  // namespace
