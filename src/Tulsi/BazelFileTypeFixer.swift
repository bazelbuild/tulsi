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

import Foundation

// UTIs and TypeCode for our different file types.
// These need to match up with values in the Info.plist
let BuildUTI = "com.google.bazel.build"
let BuildTypeCode = Int(UTGetOSTypeFromString("bILd"))
let WorkspaceUTI = "com.google.bazel.workspace"
let WorkspaceTypeCode = Int(UTGetOSTypeFromString("wKSp"))
let SkylarkUTI = "com.google.bazel.skylark"
let SkylarkTypeCode = Int(UTGetOSTypeFromString("sKYk"))

// Since BUILD and WORKSPACE files don't have extensions, the OS X file system doesn't know what
// type of files they are. As part of our "seamless" experience, we go through mark all the files we
// can with an old fashioned FileType attribute. FileType attributes are currently stored in the
// xattrs of a file (com.apple.finder) and are not seen as modifications to the file by source
// control management. This assigns an icon to the file, makes BUILD files openable by double
// clicking in Tulsi, and marks them as public.text which means that right clicking them in the
// Finder will show you a list of Text editors to edit them with, as well as giving Xcode an idea
// what to do with these filetypes.
// We can't do this with a spotlight plugin because spotlight plugins are run in a read only
// sandbox. We could do this with a LaunchDaemon/Agent but that seemed overly invasive.
class BazelFileTypeFixer: NSObject {
  let query = NSMetadataQuery()

  override init() {
    super.init()
    // TODO(abaire): Re-enable when things are stable and crashing issues can be tracked down.
    // TODO(abaire): Also remove the default public.data handler from CFBundleDocumentTypes.
//    query.predicate = NSPredicate(format: "(kMDItemFSName = 'BUILD' && kMDItemContentType != '%@') " +
//        "|| (kMDItemFSName = 'WORKSPACE' && kMDItemContentType != '%@')", BuildUTI, WorkspaceUTI)
//    query.notificationBatchingInterval = 30
//    NSNotificationCenter.defaultCenter().addObserver(
//        self, selector: Selector("queryDidUpdate:"), name: NSMetadataQueryDidUpdateNotification, object: query)
//    NSNotificationCenter.defaultCenter().addObserver(
//        self, selector: Selector("queryDidUpdate:"), name: NSMetadataQueryDidFinishGatheringNotification, object: query)
//    query.operationQueue = NSOperationQueue()
//    query.startQuery()
  }

  func queryDidUpdate(notification: NSNotification) {
    query.disableUpdates()
    defer {
      query.enableUpdates()
    }
    let manager = NSFileManager.defaultManager()
    for result in query.results {
      guard let item = result as? NSMetadataItem,
            let path = item.valueForAttribute(kMDItemPath as String) as? String else {
        continue
      }

      do {
        var attributes = try manager.attributesOfItemAtPath(path)
        if attributes[NSFileHFSTypeCode] as! Int == 0 {
          let urlPath = NSURL(fileURLWithPath: path)
          switch urlPath.lastPathComponent! {
            case "BUILD":
              attributes[NSFileHFSTypeCode] = BuildTypeCode
            case "WORKSPACE":
              attributes[NSFileHFSTypeCode] = WorkspaceTypeCode
            default:
              continue
          }
          try manager.setAttributes(attributes, ofItemAtPath: path)
        }
      }
      catch let error as NSError {
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError {
          // Just ignore write perm errors. These are common especially with folks using
          // perforce, or other SCMs that lock the files.
          continue
        }
        NSLog("%@", error)
      }
    }
  }
}
