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


extension URL {
  public func relativePathTo(_ target: URL) -> String? {
    guard self.isFileURL && target.isFileURL else {
      return nil
    }

    let rootComponents = pathComponents
    let targetComponents = target.pathComponents

    if target == self {
      return ""
    }

    let zippedComponents = zip(rootComponents, targetComponents)
    var numCommonComponents = 0
    for (a, b) in zippedComponents {
      if a != b { break }
      numCommonComponents += 1
    }

    // Construct a path to the last common component.
    var relativePath = [String](repeating: "..",
                                count: rootComponents.count - numCommonComponents)

    // Append the path from the common component to the target.
    relativePath += targetComponents.suffix(targetComponents.count - numCommonComponents)

    return relativePath.joined(separator: "/")
  }
}
