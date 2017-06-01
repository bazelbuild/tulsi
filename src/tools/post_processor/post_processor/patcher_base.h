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

#ifndef POST_PROCESSOR_PATCHERBASE_H_
#define POST_PROCESSOR_PATCHERBASE_H_

#include <string>
#include <unordered_map>

#include "return_code.h"


namespace post_processor {

class MachOFile;

/// Virtual base class for patchers.
class PatcherBase {
 public:
  PatcherBase(const std::unordered_map<std::string, std::string> &prefix_map,
              bool verbose = false) :
      prefix_map_(prefix_map),
      verbose_(verbose) {
  }

  virtual ~PatcherBase() {}

  virtual ReturnCode Patch(MachOFile *f) = 0;

 protected:
  inline void VerbosePrint(const char *fmt, ...) const {
    if (!verbose_) {
      return;
    }

    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
  }

 protected:
  const std::unordered_map<std::string,std::string> prefix_map_;
  bool verbose_;
};

}  // namespace post_processor

#endif  // POST_PROCESSOR_PATCHERBASE_H_
