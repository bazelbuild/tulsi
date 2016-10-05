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

#ifndef POST_PROCESSOR_RETURNCODE_H_
#define POST_PROCESSOR_RETURNCODE_H_


namespace post_processor {

enum ReturnCode {
    ERR_OK = 0,
    ERR_OPEN_FAILED = 10,
    ERR_READ_FAILED,
    ERR_INVALID_FILE,
    ERR_OUT_OF_MEMORY,
    ERR_NOT_IMPLEMENTED,
    ERR_WRITE_FAILED = 20,

    /// The write operation was deferred and will not be performed until a
    /// serialization method is called.
    ERR_WRITE_DEFERRED
};

}  // namespace post_processor

#endif  // POST_PROCESSOR_RETURNCODE_H_
