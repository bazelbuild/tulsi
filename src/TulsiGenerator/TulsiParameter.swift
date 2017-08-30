// Copyright 2017 The Tulsi Authors. All rights reserved.
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

/// Struct representing a value that is read in the following precedence:
/// (high) explicitly provided (ie argument) <- options (ie config) <- project <- Fallback (low)
public struct TulsiParameter<T> {

  /// Origin of a TulsiParameter, which has precedence:
  /// (high) explicitly provided (ie argument) <- options (ie config) <- project <- Fallback (low)
  public enum Source: Int {
    /// Provided by an argument or flag. Highest precedence.
    case explicitlyProvided

    /// Provided by a TulsiOption.
    case options

    /// Provided by a Tulsi Project.
    case project

    /// default, back up value in cases where a value is needed. Lowest precedence.
    case fallback

    /// Returns true if self is higher priority than the other.
    public func isHigherPriorityThan(_ other: Source) -> Bool {
      return self.rawValue < other.rawValue;
    }
  }

  public let value: T
  public let source: Source

  init(value: T, source: Source) {
    self.value = value
    self.source = source
  }

  init?(value: T?, source: Source) {
    guard let value = value else { return nil }
    self.init(value: value, source: source)
  }

  /// Returns true if self is higher priority than the other.
  public func isHigherPriorityThan(_ other: TulsiParameter<T>) -> Bool {
    return self.source.isHigherPriorityThan(other.source)
  }

  /// Reduces self with given TulsiParameter, returning the value with the higher priority (or self
  /// if the priorities are equal).
  public func reduce(_ other: TulsiParameter<T>?) -> TulsiParameter<T> {
    if let other = other, other.isHigherPriorityThan(self) {
      return other
    }
    return self
  }
}
