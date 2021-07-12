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

// Represents a label in a build file - http://bazel.build/docs/build-ref.html#labels
public class BuildLabel: Comparable, Equatable, Hashable, CustomStringConvertible {
  public let value: String

  public lazy var targetName: String? = { [unowned self] in
    let components = self.value.components(separatedBy: ":")
    if components.count > 1 {
      return components.last
    }

    let lastPackageComponent = self.value.components(separatedBy: "/").last!
    if lastPackageComponent.isEmpty {
      return nil
    }
    return lastPackageComponent
  }()

  public lazy var packageName: String? = { [unowned self] in
    guard var package = self.value.components(separatedBy: ":").first else {
      return nil
    }

    if package.hasPrefix("//") {
      package.removeSubrange(package.startIndex ..< package.index(package.startIndex, offsetBy: 2))
    }
    if package.isEmpty || package.hasSuffix("/") {
      return ""
    }
    return package
  }()

  public lazy var asFileName: String? = { [unowned self] in
    guard var package = self.packageName, let target = self.targetName else {
      return nil
    }
    // Fix for external and local_repository, which may be referenced by Bazel via
    // @repository//subpath while we internally refer to them via external/repository/subpath.
    if package.starts(with: "@") {
      package = "external/" + 
        package.suffix(from: package.index(package.startIndex, offsetBy: 1)) // Munch @ prefix
          .replacingOccurrences(of: "//", with: "/") // Fixup //. Xcode can't handle paths like that.
    }
    return "\(package)/\(target)"
  }()

  public lazy var asFullPBXTargetName: String? = { [unowned self] in
    guard let package = self.packageName, let target = self.targetName else {
      return nil
    }
    // Note: The replacement must be done with a value that is not supported in Bazel packages in
    // order to prevent collisions, but is still supported by Xcode (for scheme filenames, etc...).
    return "\(package)/\(target)".replacingOccurrences(of: "/", with: "-")
  }()

  public lazy var hashValue: Int = { [unowned self] in
    return self.value.hashValue
  }()

  public init(_ label: String, normalize: Bool = false) {
    var value = label
    if normalize && !value.hasPrefix("//") {
      value = "//\(value)"
    }
    self.value = value
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
