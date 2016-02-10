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


/// Convenience subclass of NSOpenPanel that acts as its own delegate and applies a filtering
/// function for -panel:shouldEnableURL:.
class FilteredOpenPanel: NSOpenPanel, NSOpenSavePanelDelegate {
  typealias FilterFunc = (sender: FilteredOpenPanel, shouldEnableURL: NSURL) -> Bool

  var filterFunc: FilterFunc? = nil

  static func filteredOpenPanel(filter: FilterFunc?) -> FilteredOpenPanel {
    let panel = FilteredOpenPanel()
    panel.filterFunc = filter
    panel.delegate = panel
    return panel
  }

  /// Creates a filtered NSOpenPanel that accepts any non-package directories and any files whose
  /// last path component is in the given array of names.
  static func filteredOpenPanelAcceptingNonPackageDirectoriesAndFilesNamed(names: [String]) -> FilteredOpenPanel {
    return filteredOpenPanel(filterNonPackageDirectoriesOrFilesMatchingNames(names))
  }

  // MARK: - NSOpenSavePanelDelegate

  func panel(sender: AnyObject, shouldEnableURL url: NSURL) -> Bool {
    return filterFunc?(sender: self, shouldEnableURL: url) ?? true
  }

  private static func filterNonPackageDirectoriesOrFilesMatchingNames(validFiles: [String]) -> ((AnyObject, NSURL) -> Bool) {
    return { (sender: AnyObject, shouldEnableURL url: NSURL) -> Bool in
      var isDir: AnyObject?
      var isPackage: AnyObject?
      do {
        try url.getResourceValue(&isDir, forKey: NSURLIsDirectoryKey)
        try url.getResourceValue(&isPackage, forKey: NSURLIsPackageKey)
        if let isDir = isDir as? NSNumber, isPackage = isPackage as? NSNumber
            where !isPackage.boolValue {
          if isDir.boolValue { return true }
          if let filename = url.lastPathComponent {
            return validFiles.contains(filename)
          }
        }
      } catch _ {
        // Treat any exception as an invalid URL.
      }
      return false
    }
  }
}

