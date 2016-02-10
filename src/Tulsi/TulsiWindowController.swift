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

import Cocoa

class TulsiWindowController: NSWindowController {

  // Change up the standard window title handling so that they use the package name for the BUILD
  // file, instead of them all just saying "BUILD". Keep the URL to the build file though so that we
  // get correct icon, and correct window title path clicking behavior.
  override func synchronizeWindowTitleWithDocumentName() {
    if let url = document?.fileURL! {
      window!.representedURL = url
      window!.title = (url.URLByDeletingLastPathComponent?.lastPathComponent)!
    }
  }
}
