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


/// The mode in which Tulsi should open in response to a launch from the plugin.
enum TulsiLaunchMode: String {
  case NewProject, OpenProject
}

// Apple owns all lower case AEKeywords.
let TulsiAEKeywordXcode = UTGetOSTypeFromString("XCOD")  // An URL to an Xcode.app of typeFileURL.

// Creates an AppleEvent wrapping the given URL and mode.
func CreateTulsiAppleEventRecord(xcodeURL: NSURL, mode: TulsiLaunchMode = .OpenProject) -> NSAppleEventDescriptor {
  let recordDesc = NSAppleEventDescriptor.recordDescriptor()

  let urlData = CFURLCreateData(nil, xcodeURL as CFURL, CFStringBuiltInEncodings.UTF8.rawValue, true)
  var urlDesc = AEDesc()
  AECreateDesc(DescType(typeFileURL), CFDataGetBytePtr(urlData), CFDataGetLength(urlData), &urlDesc)
  let xcodeDesc = NSAppleEventDescriptor(AEDescNoCopy: &urlDesc)
  recordDesc.setDescriptor(xcodeDesc, forKeyword: TulsiAEKeywordXcode)

  let directObjectDesc = NSAppleEventDescriptor(string: mode.rawValue)
  recordDesc.setParamDescriptor(directObjectDesc, forKeyword: AEKeyword(keyDirectObject))
  return recordDesc
}

// Extracts the Xcode URL and launch mode from the current AppleEvent.
func GetXcodeURLFromCurrentAppleEvent() -> (NSURL, TulsiLaunchMode)? {
  guard let event = NSAppleEventManager.sharedAppleEventManager().currentAppleEvent,
            propData = event.descriptorForKeyword(AEKeyword(keyAEPropData)),
            xcodeURLData = propData.descriptorForKeyword(TulsiAEKeywordXcode) else {
    return nil
  }

  let urlData = xcodeURLData.data
  guard let xcodeURL = CFURLCreateWithBytes(nil,
                                      UnsafePointer<UInt8>(urlData.bytes),
                                      urlData.length,
                                      CFStringBuiltInEncodings.UTF8.rawValue,
                                      nil) as NSURL? else {
    return nil
  }

  guard let launchModeValue = propData.paramDescriptorForKeyword(AEKeyword(keyDirectObject))?.stringValue,
            launchMode = TulsiLaunchMode(rawValue: launchModeValue) else {
    return nil
  }
  return (xcodeURL, launchMode)
}
