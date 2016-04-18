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


/// Window controller for the splash screen.
final class SplashScreenWindowController: NSWindowController {

  @IBOutlet var recentDocumentsArrayController: NSArrayController!
  @IBOutlet weak var splashScreenImageView: NSImageView!
  dynamic var applicationVersion: String = ""
  dynamic var recentDocumentURLs = [NSURL]()

  override var windowNibName: String? {
    return "SplashScreenWindowController"
  }

  override func windowWillLoad() {
    super.windowWillLoad()
    NSValueTransformer.setValueTransformer(TulsiProjDocumentURLToNameValueTransformer(),
                                           forName: "TulsiProjDocumentURLToNameValueTransformer")
  }

  override func windowDidLoad() {
    super.windowDidLoad()

    splashScreenImageView.image = NSApplication.sharedApplication().applicationIconImage

    if let cfBundleVersion = NSBundle.mainBundle().infoDictionary?["CFBundleVersion"] as? String {
      applicationVersion = cfBundleVersion
    }

    recentDocumentURLs = [NSURL()]
    recentDocumentURLs.appendContentsOf(getRecentProjectURLs())
  }

  @IBAction func didDoubleClickRecentDocument(sender: NSTableView) {
    let clickedRow = sender.clickedRow
    guard clickedRow >= 0 else { return }
    let documentController = NSDocumentController.sharedDocumentController()
    if clickedRow == 0 {
      // Handle the special "New project" item.
      do {
        try documentController.openUntitledDocumentAndDisplay(true)
      } catch let e as NSError {
        let alert = NSAlert()
        alert.messageText = e.localizedFailureReason ?? e.localizedDescription
        alert.informativeText = e.localizedRecoverySuggestion ?? ""
        alert.runModal()
      }
    } else {
      let url = recentDocumentURLs[clickedRow]
      documentController.openDocumentWithContentsOfURL(url, display: true) {
        (_: NSDocument?, _: Bool, _: NSError?) in
      }
    }
  }

  // MARK: - Private methods

  private func getRecentProjectURLs() -> [NSURL] {
    let projectExtension = TulsiProjectDocument.getTulsiBundleExtension()
    let documentController = NSDocumentController.sharedDocumentController()

    var recentURLs = [NSURL]()
    for url in documentController.recentDocumentURLs {
      guard let path = url.path where path.containsString(projectExtension) else { continue }

      var components: [String] = url.pathComponents!
      var i = components.count - 1
      repeat {
        if (components[i] as NSString).pathExtension == projectExtension {
          break
        }
        i -= 1
      } while i > 0

      let projectURL: NSURL
      if i == components.count - 1 {
        projectURL = url
      } else {
        let projectComponents = [String](components.prefix(i + 1))
        projectURL = NSURL.fileURLWithPathComponents(projectComponents)!
      }

      if !recentURLs.contains(projectURL) {
        recentURLs.append(projectURL)
      }
    }

    return recentURLs
  }
}


/// Transformer that converts a URL for a Tulsi project document to a name suitable for display in
/// the splash screen.
final class TulsiProjDocumentURLToNameValueTransformer : NSValueTransformer {
  override class func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override class func allowsReverseTransformation() -> Bool  {
    return false
  }

  override func transformedValue(value: AnyObject?) -> AnyObject? {
    guard let url = value as? NSURL, filename = url.lastPathComponent else {
      return NSLocalizedString("SplashScreen_NewProject",
                               comment: "Special item in the recent documents list on the splash screen that will create a new project document.")
    }

    return (filename as NSString).stringByDeletingPathExtension
  }
}
