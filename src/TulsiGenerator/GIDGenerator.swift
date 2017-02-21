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

/// Global ID generator.
protocol GIDGeneratorProtocol {
  /// Generates a unique ID for the given project item. The generator implementation must guarantee
  /// that generate calls will never produce the same GID (e.g., multiple generate calls with the
  /// same or any different item will generate different GIDs each time).
  func generate(_ item: PBXObjectProtocol) -> String
}


/// Implementation of GIDGeneratorProtocol.
final class ConcreteGIDGenerator: GIDGeneratorProtocol {
  /// Map of hash prefix to the last used counter for that prefix.
  private var reservedIDS = [String: Int]()

  func generate(_ item: PBXObjectProtocol) -> String {
    let hash = String(format: "%08X%08X", item.isa.hashValue, item.hashValue)
    let counter = reservedIDS[hash] ?? 0
    let gid = String(format: "\(hash)%08X", counter)
    reservedIDS[hash] = counter + 1
    return gid
  }
}
