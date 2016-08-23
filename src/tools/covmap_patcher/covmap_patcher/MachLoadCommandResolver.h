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

#ifndef COVMAP_PATCHER_MACH_LOAD_COMMAND_RESOLVER_H_
#define COVMAP_PATCHER_MACH_LOAD_COMMAND_RESOLVER_H_

#include <map>
#include <string>

namespace covmap_patcher {

/// Provides functionality to resolve a Mach-O load command to a user-readable
/// string.
class MachLoadCommandResolver {
 public:
  MachLoadCommandResolver();

  inline std::string GetLoadCommandInfo(uint32_t load_command) const {
    auto result = command_to_info_.find(load_command);
    if (result == command_to_info_.cend()) {
      return "<Unknown load command>";
    }
    return result->second;
  }

 private:
  std::map<uint32_t, std::string> command_to_info_;
};

}  // namespace covmap_patcher

#endif  //COVMAP_PATCHER_MACH_LOAD_COMMAND_RESOLVER_H_
