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
  var url: URL?

  override var nibName: NSNib.Name? {
    return "SplashScreenRecentDocumentView"
  }

  override func viewDidLoad() {
    guard let url = url else { return }
    icon.image =  NSWorkspace.shared.icon(forFile: url.path)
    filename.stringValue = (url.lastPathComponent as NSString).deletingPathExtension
    path.stringValue = ((url.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
  }
}

/// Window controller for the splash screen.
final class SplashScreenWindowController: NSWindowController, NSTableViewDelegate, NSTableViewDataSource {

  @IBOutlet var recentDocumentsArrayController: NSArrayController!
  @IBOutlet weak var splashScreenImageView: NSImageView!
  @objc dynamic var applicationVersion: String = ""
  @objc dynamic var recentDocumentViewControllers = [SplashScreenRecentDocumentViewController]()

  override var windowNibName: NSNib.Name? {
    return "SplashScreenWindowController"
  }

  override func windowDidLoad() {
    super.windowDidLoad()

    splashScreenImageView.image = NSImage(named: "AppIcon")

    if let cfBundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
      applicationVersion = cfBundleVersion
    }

    recentDocumentViewControllers = getRecentDocumentViewControllers()
  }

  @IBAction func createNewDocument(_ sender: NSButton) {
    let documentController = NSDocumentController.shared
    do {
      try documentController.openUntitledDocumentAndDisplay(true)
    } catch let e as NSError {
      let alert = NSAlert()
      alert.messageText = e.localizedFailureReason ?? e.localizedDescription
      alert.informativeText = e.localizedRecoverySuggestion ?? ""
      alert.runModal()
    }
  }

  @IBAction func didDoubleClickRecentDocument(_ sender: NSTableView) {
    let clickedRow = sender.clickedRow
    guard clickedRow >= 0 else { return }
    let documentController = NSDocumentController.shared
    let viewController = recentDocumentViewControllers[clickedRow]

    guard let url = viewController.url  else { return }
    documentController.openDocument(withContentsOf: url, display: true) {
      (_: NSDocument?, _: Bool, _: Error?) in
    }
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    return recentDocumentViewControllers[row].view
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return recentDocumentViewControllers.count
  }

  // MARK: - Private methods

  private func getRecentDocumentViewControllers() -> [SplashScreenRecentDocumentViewController] {
    let projectExtension = TulsiProjectDocument.getTulsiBundleExtension()
    let documentController = NSDocumentController.shared

    var recentDocumentViewControllers = [SplashScreenRecentDocumentViewController]()
    var recentDocumentURLs = Set<URL>()
    let fileManager = FileManager.default
    for url in documentController.recentDocumentURLs {
      let path = url.path
      guard path.contains(projectExtension) else { continue }
      if !fileManager.isReadableFile(atPath: path) {
        continue
      }

      let components: [String] = url.pathComponents
      var i = components.count - 1
      repeat {
        if (components[i] as NSString).pathExtension == projectExtension {
          break
        }
        i -= 1
      } while i > 0

      let projectURL: URL
      if i == components.count - 1 {
        projectURL = url
      } else {
        let projectComponents = [String](components.prefix(i + 1))
        projectURL = NSURL.fileURL(withPathComponents: projectComponents)! as URL
      }
      if (recentDocumentURLs.contains(projectURL)) {
        continue
      }
      recentDocumentURLs.insert(projectURL)

      let viewController = SplashScreenRecentDocumentViewController()
      viewController.url = projectURL
      recentDocumentViewControllers.append(viewController)
    }

    return recentDocumentViewControllers
  }
}
