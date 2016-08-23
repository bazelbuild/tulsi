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

#ifndef COVMAP_PATCHER_RETURNCODE_H_
#define COVMAP_PATCHER_RETURNCODE_H_


namespace covmap_patcher {

enum ReturnCode {
    ERR_OK = 0,
    ERR_OPEN_FAILED = 10,
    ERR_READ_FAILED,
    ERR_INVALID_FILE,
    ERR_OUT_OF_MEMORY,
    ERR_WRITE_FAILED = 20,
};

}  // namespace covmap_patcher

#endif  // COVMAP_PATCHER_RETURNCODE_H_
