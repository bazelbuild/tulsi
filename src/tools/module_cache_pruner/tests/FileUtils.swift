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

private let fileManager = FileManager.default

struct DirectoryStructure {
  var files: [String]?
  var directories: [String: DirectoryStructure]?
}

/// Creates a directory and any subdirectories + dummy files at the given location on the file
/// system.
func createDirectoryStructure(_ directory: URL, withContents contents: DirectoryStructure) throws {
  if let files = contents.files {
    for filename in files {
      let filepath = directory.appendingPathComponent(filename)
      try "".write(to: filepath, atomically: true, encoding: .utf8)
    }
  }

  if let directories = contents.directories {
    for (dirname, contents) in directories {
      let subdirectory = directory.appendingPathComponent(dirname)
      try fileManager.createDirectory(at: subdirectory, withIntermediateDirectories: true)
      try createDirectoryStructure(subdirectory, withContents: contents)
    }
  }
}

/// Creates a directory with a random name in the macOS temporary directory.
func createTemporaryDirectory() -> URL? {
  let osTemporaryDirectory = URL(
    fileURLWithPath: NSTemporaryDirectory(),
    isDirectory: true)

  guard
    let temporaryDirectory = try? fileManager.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: osTemporaryDirectory,
      create: true)
  else {
    return nil
  }

  // The macOS temporary directory is located under the `/var` root directory. `/var` is a symlink
  // to `/private/var` which can cause problems when testing for equal values since equality will
  // depend on whether prod code resolves the realpath or leaves it as the symlink. To avoid issues,
  // return the realpath so test and prod code will only ever handle one version of the path.
  guard let temporaryDirectoryRealPath = realpath(temporaryDirectory.path, nil) else {
    return nil
  }

  return URL(fileURLWithPath: String(cString: temporaryDirectoryRealPath), isDirectory: true)
}

/// Returns a URL to a location for a JSON file with a random filename under the macOS temporary
/// directory. This function does not create a file at that location.
func getTemporaryJSONFileURL() -> URL {
  let temporaryDirectoryURL = URL(
    fileURLWithPath: NSTemporaryDirectory(),
    isDirectory: true)
  let temporaryFilename = ProcessInfo().globallyUniqueString
  return temporaryDirectoryURL.appendingPathComponent("\(temporaryFilename).json")
}

/// Enumerates the full contents of a directory and returns a Set of the results containing only
/// relative paths to the given directory.
func getDirectoryContentsWithRelativePaths(directory: URL) -> Set<String> {
  // The file manager enumerator function accepts an option that will enumerate with relative paths,
  // i.e. FileManager.DirectoryEnumerationOptions.producesRelativePathURLs, but that options
  // requires macOS 10.15 which is not guaranteed when building Tulsi. Instead, we create the
  // relative paths ourselves.
  guard let results = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
    return []
  }

  let directoryPath = directory.path
  var relativeResults = Set<String>()
  for result in results {
    if let resultUrl = result as? URL {
      let resultPath = resultUrl.path
      let path =
        resultPath.hasPrefix(directoryPath)
        ? String(resultPath.dropFirst(directoryPath.count + 1)) : resultPath
      relativeResults.insert(path)
    }
  }
  return relativeResults
}
