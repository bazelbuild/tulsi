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

final class ProjectOutputFolderPanel {

  /// Whether or not the output panel is currently being displayed.
  static var displaying: Bool {
    return outputFolderOpenPanel != nil
  }

  private static var outputFolderOpenPanel: NSOpenPanel!

  /// Displays an output panel that automatically updates the given TulsiDocument's output folder
  /// path.
  static func beginSheetModalForWindow(window: NSWindow,
                                       document: TulsiDocument,
                                       initialURL: NSURL?,
                                       generationAction: Bool = false,
                                       completionHandler: ((NSInteger) -> Void)? = nil) {
    assert(outputFolderOpenPanel == nil, "Multiple concurrent ProjectOutputFolderPanel's detected.")
    let panel = NSOpenPanel()
    panel.title = NSLocalizedString("ProjectGeneration_SelectProjectOutputFolderTitle",
                                    comment: "Title for open panel through which the user should select where to generate the Xcode project.")
    panel.message = NSLocalizedString("ProjectGeneration_SelectProjectOutputFolderMessage",
                                      comment: "Message to show at the top of the Xcode output folder sheet, explaining what to do.")

    if generationAction {
      panel.prompt = NSLocalizedString("ProjectGeneration_SelectProjectOutputFolderAndGeneratePrompt",
                                       comment: "Label for the button used to confirm the selected output folder for the generated Xcode project which will also start generating immediately.")
    } else {
      panel.prompt = NSLocalizedString("ProjectGeneration_SelectProjectOutputFolderPrompt",
                                       comment: "Label for the button used to confirm the selected output folder for the generated Xcode project.")
    }
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.directoryURL = initialURL
    panel.beginSheetModalForWindow(window) { value in
      if value == NSFileHandlingPanelOKButton {
        document.outputFolderURL = panel.URL
      }
      self.outputFolderOpenPanel = nil
      completionHandler?(value)
    }

    outputFolderOpenPanel = panel
  }

  // MARK: - Private methods.
  private init() {
  }
}
