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

/// View controller for the "recent document" rows in the tableview in the splash screen.
final class SplashScreenRecentDocumentViewController : NSViewController {
  @IBOutlet weak var icon : NSImageView!
  @IBOutlet weak var filename : NSTextField!
  @IBOutlet weak var path: NSTextField!
  var url : NSURL = NSURL()

  override var nibName: String? {
    return "SplashScreenRecentDocumentView"
  }

  override func viewDidLoad() {
    guard let urlPath = url.path else { return }
    icon.image =  NSWorkspace.sharedWorkspace().iconForFile(urlPath)
    filename.stringValue = (url.lastPathComponent! as NSString).stringByDeletingPathExtension
    path.stringValue = ((urlPath as NSString).stringByDeletingLastPathComponent as NSString).stringByAbbreviatingWithTildeInPath
  }
}

/// Window controller for the splash screen.
final class SplashScreenWindowController: NSWindowController, NSTableViewDelegate, NSTableViewDataSource {

  @IBOutlet var recentDocumentsArrayController: NSArrayController!
  @IBOutlet weak var splashScreenImageView: NSImageView!
  dynamic var applicationVersion: String = ""
  dynamic var recentDocumentViewControllers = [SplashScreenRecentDocumentViewController]()

  override var windowNibName: String? {
    return "SplashScreenWindowController"
  }

  override func windowDidLoad() {
    super.windowDidLoad()

    splashScreenImageView.image = NSApplication.sharedApplication().applicationIconImage

    if let cfBundleVersion = NSBundle.mainBundle().infoDictionary?["CFBundleVersion"] as? String {
      applicationVersion = cfBundleVersion
    }

    recentDocumentViewControllers = getRecentDocumentViewControllers()
  }

  @IBAction func createNewDocument(sender: NSButton) {
    let documentController = NSDocumentController.sharedDocumentController()
    do {
      try documentController.openUntitledDocumentAndDisplay(true)
    } catch let e as NSError {
      let alert = NSAlert()
      alert.messageText = e.localizedFailureReason ?? e.localizedDescription
      alert.informativeText = e.localizedRecoverySuggestion ?? ""
      alert.runModal()
    }
  }

  @IBAction func didDoubleClickRecentDocument(sender: NSTableView) {
    let clickedRow = sender.clickedRow
    guard clickedRow >= 0 else { return }
    let documentController = NSDocumentController.sharedDocumentController()
    let viewController = recentDocumentViewControllers[clickedRow]
    documentController.openDocumentWithContentsOfURL(viewController.url, display: true) {
      (_: NSDocument?, _: Bool, _: NSError?) in
    }
  }

  func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
    return recentDocumentViewControllers[row].view
  }

  func numberOfRowsInTableView(tableView: NSTableView) -> Int {
    return recentDocumentViewControllers.count
  }

  // MARK: - Private methods

  private func getRecentDocumentViewControllers() -> [SplashScreenRecentDocumentViewController] {
    let projectExtension = TulsiProjectDocument.getTulsiBundleExtension()
    let documentController = NSDocumentController.sharedDocumentController()

    var recentDocumentViewControllers = [SplashScreenRecentDocumentViewController]()
    var recentDocumentURLs = Set<NSURL>()
    let fileManager = NSFileManager.defaultManager()
    for url in documentController.recentDocumentURLs {
      guard let path = url.path where path.containsString(projectExtension) else { continue }
      if !fileManager.isReadableFileAtPath(path) {
        continue
      }

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
      if (recentDocumentURLs.contains(projectURL)) {
        continue;
      }
      recentDocumentURLs.insert(projectURL);

      let viewController = SplashScreenRecentDocumentViewController()
      viewController.url = projectURL;
      recentDocumentViewControllers.append(viewController)
    }

    return recentDocumentViewControllers
  }
}
