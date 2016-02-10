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

// Support for AppleEvent handling between the plugin and the app.
// Currently it passes a record that contains one field (tulsiAEKeyWordXcode).

import Foundation

// Apple owns all lower case AEKeyWords.
let tulsiAEKeyWordXcode = UTGetOSTypeFromString("XCOD")  // An URL to an Xcode.app of typeFileURL.

// Given an URL create the apple event descriptor to wrap it. On 10.11 we could just use
// init(fileURL: NSURL).
func CreateTulsiAppleEventRecord(xcodeURL: NSURL) -> NSAppleEventDescriptor {
  let recordDesc = NSAppleEventDescriptor.recordDescriptor()
  let urlData = CFURLCreateData(nil, xcodeURL as CFURL, CFStringBuiltInEncodings.UTF8.rawValue, true)
  var urlDesc = AEDesc()
  AECreateDesc(DescType(typeFileURL), CFDataGetBytePtr(urlData), CFDataGetLength(urlData), &urlDesc)
  let desc = NSAppleEventDescriptor(AEDescNoCopy: &urlDesc)
  recordDesc.setDescriptor(desc, forKeyword: tulsiAEKeyWordXcode)
  return recordDesc
}

// Extract the Xcode URL from the event. On 10.11 we could replace the last couple of lines with
// xcodeURLData.fileURLValue.
func GetXcodeURLFromCurrentAppleEvent() -> NSURL? {
  guard let event = NSAppleEventManager.sharedAppleEventManager().currentAppleEvent else {
    return nil
  }
  guard let propData = event.descriptorForKeyword(AEKeyword(keyAEPropData)) else {
    return nil
  }
  guard let xcodeURLData = propData.descriptorForKeyword(tulsiAEKeyWordXcode) else {
    return nil
  }
  guard let xcodeURLString = xcodeURLData.stringValue else {
    return nil
  }
  return NSURL(fileURLWithPath: xcodeURLString)
}
