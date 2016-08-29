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

#ifndef POST_PROCESSOR_SYMTABNLISTRESOLVER_H_
#define POST_PROCESSOR_SYMTABNLISTRESOLVER_H_

#include <string>
#include <map>

namespace post_processor {

/// Provides functionality to resolve nlist entries within a Mach-O LC_SYMTAB
/// segment to user-readable strings.
class SymtabNListResolver {
 public:
  SymtabNListResolver();

  inline std::string GetDebugTypeInfo(uint32_t type) const {
    auto result = debug_type_to_info_.find(type);
    if (result == debug_type_to_info_.cend()) {
      return "<Unknown debug type>";
    }
    return result->second;
  }

 private:
  std::map<uint32_t, std::string> debug_type_to_info_;
};

}  // namespace post_processor

#endif  // POST_PROCESSOR_SYMTABNLISTRESOLVER_H_
