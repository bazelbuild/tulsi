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

// Represents a label in a build file - http://bazel.io/docs/build-ref.html#labels
public class BuildLabel: Comparable, Equatable, Hashable, CustomStringConvertible {
  public let value: String

  public var targetName: String? {
    let components = value.componentsSeparatedByString(":")
    if components.count > 1 {
      return components.last
    }

    let lastPackageComponent = value.componentsSeparatedByString("/").last!
    if lastPackageComponent.isEmpty {
      return nil
    }
    return lastPackageComponent
  }

  public var packageName: String? {
    guard var package = value.componentsSeparatedByString(":").first else {
      return nil
    }

    if package.hasPrefix("//") {
      package.removeRange(Range(start: package.startIndex, end: package.startIndex.advancedBy(2)))
    }
    if package.isEmpty || package.hasSuffix("/") {
      return ""
    }
    return package
  }

  public var asFileName: String? {
    guard let package = packageName, target = targetName else {
      return nil
    }
    return "\(package)/\(target)"
  }

  public var hashValue: Int {
    return value.hashValue
  }

  init(_ label: String) {
    self.value = label
  }

  // MARK: - CustomStringConvertible

  public var description: String {
    return self.value
  }
}

// MARK: - Comparable

public func <(lhs: BuildLabel, rhs: BuildLabel) -> Bool {
  return lhs.value < rhs.value
}

// MARK: - Equatable

public func ==(lhs: BuildLabel, rhs: BuildLabel) -> Bool {
  return lhs.value == rhs.value
}
