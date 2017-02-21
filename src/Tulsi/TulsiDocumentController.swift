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


// Document controller for customization of the open panel.
final class TulsiDocumentController: NSDocumentController {

  override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
    openPanel.message = NSLocalizedString("OpenProject_OpenProjectPanelMessage",
                                          comment: "Message to show at the top of tulsiproj open panel, explaining what to do.")
    return super.runModalOpenPanel(openPanel, forTypes: types)
  }
}
