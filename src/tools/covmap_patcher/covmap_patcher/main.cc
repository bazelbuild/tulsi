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


using covmap_patcher::CovmapSection;
using covmap_patcher::MachOFile;
using covmap_patcher::ReturnCode;

namespace {
void PrintUsage(const char *executable_name);
int PatchCovmapSection(const std::string &filename,
                       size_t offset,
                       size_t length,
                       bool swap_byte_ordering,
                       const std::string &old_prefix,
                       const std::string &new_prefix);
}  // namespace


int main(int argc, const char* argv[]) {
  if (argc < 4) {
    PrintUsage(argv[0]);
    return 1;
  }

  // TODO(abaire): Support growing sections.
  if (strlen(argv[3]) > strlen(argv[2])) {
    fprintf(stderr,
            "Cannot grow paths (new_path length must be <= old_path length\n");
    return 1;
  }

  std::string filename(argv[1]);
  MachOFile f(filename, false);
  {
    ReturnCode retval = f.Read();
    if (retval != covmap_patcher::ERR_OK) {
      fprintf(stderr,
              "ERROR: Failed to read Mach-O content from %s.\n",
              filename.c_str());
      return (int)retval;
    }
  }

  std::string old_prefix(argv[2]);
  std::string new_prefix(argv[3]);
  size_t offset = 0, len = 0;
  bool swap_byte_ordering = false;

  if (f.Has32Bit()) {
    if (!f.GetSectionInfo32("__DATA",
                            "__llvm_covmap",
                            &offset,
                            &len,
                            &swap_byte_ordering)) {
      fprintf(stderr, "Warning: Failed to find __llvm_covmap section in "
          "32-bit data.\n");
    } else {
      int retval = PatchCovmapSection(filename,
                                      offset,
                                      len,
                                      swap_byte_ordering,
                                      old_prefix,
                                      new_prefix);
      if (retval) {
        return retval;
      }
    }
  }

  if (f.Has64Bit()) {
    if (!f.GetSectionInfo64("__DATA",
                            "__llvm_covmap",
                            &offset,
                            &len,
                            &swap_byte_ordering)) {
      fprintf(stderr, "Warning: Failed to find __llvm_covmap section in "
          "64-bit data.\n");
    } else {
      int retval = PatchCovmapSection(filename,
                                      offset,
                                      len,
                                      swap_byte_ordering,
                                      old_prefix,
                                      new_prefix);
      if (retval) {
        return retval;
      }
    }
  }

  return 0;
}

namespace {

void PrintUsage(const char *executable_name) {
  printf("Usage: %s <object_file> <old_path> <new_path>\n", executable_name);
  printf("Modifies the contents of the LLVM coverage map in the given "
             "object_file by replacing any paths that start with \"old_path\" "
             "with \"new_path\".\n");
}

int PatchCovmapSection(const std::string &filename,
                       size_t offset,
                       size_t length,
                       bool swap_byte_ordering,
                       const std::string &old_prefix,
                       const std::string &new_prefix) {
  CovmapSection covmap_section(filename,
                               offset,
                               length,
                               swap_byte_ordering);

  ReturnCode retval = covmap_section.Read();
  if (retval != covmap_patcher::ERR_OK) {
    fprintf(stderr, "ERROR: Failed to read LLVM coverage data.\n");
    return (int)retval;
  }

  return (int)covmap_section.PatchFilenames(old_prefix, new_prefix);
}

}  // namespace
