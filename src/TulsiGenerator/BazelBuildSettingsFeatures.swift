// Copyright 2017 The Tulsi Authors. All rights reserved.
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

let bazelBuildSettingsFeatures = [
  // For non-distributed builds.
  "TULSI_DEBUG_PREFIX_MAP",
  // TODO(b/71515804): Remove if no issues are found in replacing post_processor with this.
  "TULSI_PATCHLESS_DSYMS",
  // TODO(b/71645041): Remove if no issues are found in focusing our remapping like this.
  "TULSI_STRICTER_REMAPPING",
  // TODO(b/71714998): Remove if no issues are found in adding a trailing slash to our remappings.
  "TULSI_TRAILING_SLASHES",
]
