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

#ifndef POST_PROCESSOR_COVMAPPATCHER_H_
#define POST_PROCESSOR_COVMAPPATCHER_H_

#include <string>
#include <unordered_map>

#include "patcher_base.h"


namespace post_processor {

class CovmapSection;

/// Provides utilities to patch LLVM coverage map data.
class CovmapPatcher : public PatcherBase {
 public:
  CovmapPatcher(const std::unordered_map<std::string, std::string> &prefix_map,
                bool verbose = false) :
      PatcherBase(prefix_map, verbose) {
  }

  virtual ReturnCode Patch(MachOFile *f);

 private:
  std::unique_ptr<uint8_t[]> PatchCovmapSection(
      CovmapSection *section,
      size_t *new_data_length,
      bool *data_was_modified) const;
};

}  // namespace post_processor

#endif  // POST_PROCESSOR_COVMAPPATCHER_H_
