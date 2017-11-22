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


extension JSONSerialization {
  enum EncodingError: Error {
    // A string failed to be encoded into NSData as UTF8.
    case stringUTF8EncodingError
    // A JSON object failed to be encoded into an NSMutableString as UTF8.
    case objectUTF8EncodingError
  }

  class func tulsi_newlineTerminatedUnescapedData(
    jsonObject: Any,
    options: JSONSerialization.WritingOptions
  ) throws -> NSMutableData {
    let content = try JSONSerialization.data(withJSONObject: jsonObject, options: options)
    guard var mutableString = String(data: content, encoding: String.Encoding.utf8) else {
      throw EncodingError.objectUTF8EncodingError
    }
    mutableString.append("\n")
    mutableString = mutableString.replacingOccurrences(of: "\\/", with: "/")
    guard let output = mutableString.data(using: String.Encoding.utf8) else {
      throw EncodingError.stringUTF8EncodingError
    }
    return NSMutableData(data: output)
  }
}
