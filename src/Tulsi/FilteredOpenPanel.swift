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
  typealias FilterFunc = (_ sender: FilteredOpenPanel, _ shouldEnableURL: URL) -> Bool

  var filterFunc: FilterFunc? = nil

  static func filteredOpenPanel(_ filter: FilterFunc?) -> FilteredOpenPanel {
    let panel = FilteredOpenPanel()
    panel.filterFunc = filter
    panel.delegate = panel
    return panel
  }

  /// Creates a filtered NSOpenPanel that accepts any non-package directories and any files whose
  /// last path component is in the given array of names.
  static func filteredOpenPanelAcceptingNonPackageDirectoriesAndFilesNamed(_ names: [String]) -> FilteredOpenPanel {
    return filteredOpenPanel(filterNonPackageDirectoriesOrFilesMatchingNames(names))
  }

  // MARK: - NSOpenSavePanelDelegate

  func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
    return filterFunc?(self, url) ?? true
  }

  // MARK: - Internal methods

  static func filterNonPackageDirectoriesOrFilesMatchingNames(_ validFiles: [String]) -> FilterFunc {
    return { (sender: AnyObject, url: URL) -> Bool in
      var isDir: AnyObject?
      var isPackage: AnyObject?
      do {
        try (url as NSURL).getResourceValue(&isDir, forKey: URLResourceKey.isDirectoryKey)
        try (url as NSURL).getResourceValue(&isPackage, forKey: URLResourceKey.isPackageKey)
        if let isDir = isDir as? NSNumber, let isPackage = isPackage as? NSNumber, !isPackage.boolValue {
          if isDir.boolValue { return true }
          return validFiles.contains(url.lastPathComponent)
        }
      } catch _ {
        // Treat any exception as an invalid URL.
      }
      return false
    }
  }
}

