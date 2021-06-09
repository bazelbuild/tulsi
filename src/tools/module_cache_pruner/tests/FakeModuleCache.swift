// Copyright 2021 The Tulsi Authors. All rights reserved.
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

/// Creates a complete directory tree in a temporary directory with the given structure.
func createFakeModuleCache(with contents: DirectoryStructure) -> URL? {
  guard let temporaryDirectory = createTemporaryDirectory() else {
    return nil
  }

  do {
    try createDirectoryStructure(temporaryDirectory, withContents: contents)
  } catch {
    try? FileManager.default.removeItem(at: temporaryDirectory)
    return nil
  }
  return temporaryDirectory
}

/// Convenience function that abstracts away the need to provide the exact directory tree structure.
/// Instead, this function accepts FakeModule objects labeled as either swift or clang modules and
/// computes the directory structure.
func createFakeModuleCache(
  withSwiftModules swiftModules: [FakeModule],
  andClangModules clangModulesByDirectory: [String: [FakeModule]]
) -> URL? {
  var directories = [String: DirectoryStructure]()
  for (directory, clangModules) in clangModulesByDirectory {
    directories[directory] = DirectoryStructure(files: clangModules.map { $0.implicitFilename })
  }
  let files = swiftModules.map { $0.swiftName }

  let contents = DirectoryStructure(files: files, directories: directories)
  return createFakeModuleCache(with: contents)
}
