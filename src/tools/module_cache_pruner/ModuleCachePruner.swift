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

import CommonCrypto
import Foundation
import os

private let fileManager = FileManager.default
let prunedModulesTokenFilename = "modules.hash"

/// Prunes the implicit module cache of any modules that are also found in the explicit module
/// metadata files. This avoids a crash when LLDB loads an implicit module which will be outdated if
/// an explicit module counterpart exists.
/// Returns: A list of URLs of the modules that were removed or nil if pruning was skipped all
/// together.
@discardableResult public func pruneModuleCache(
  moduleCachePath: String, explicitModuleMetadataFile: String
) -> [URL]? {
  os_log(
    "Pruning implicit module cache at %@ of explicit modules in %@.", log: logger, type: .default,
    moduleCachePath, explicitModuleMetadataFile)
  let moduleCacheURL = URL(fileURLWithPath: moduleCachePath)
  let hashValueURL = moduleCacheURL.appendingPathComponent(prunedModulesTokenFilename)

  let explicitModuleNames: [String]
  do {
    explicitModuleNames = try getExplicitModuleNames(fromMetadataFile: explicitModuleMetadataFile)
  } catch {
    os_log(
      "Encountered an error while reading metadata file at %@: %@", log: logger, type: .error,
      explicitModuleMetadataFile, error.localizedDescription)
    return nil
  }

  let existingHashValue = readPrunedModulesToken(hashValueURL)
  guard let computedHashValue = computePrunedModulesToken(explicitModuleNames) else {
    os_log(
      "Metadata file contains no explicit module outputs, skipping module cache pruning.",
      log: logger,
      type: .default)
    return nil
  }

  if existingHashValue == computedHashValue {
    os_log(
      "Explicit module outputs have not changed, skipping module cache pruning.", log: logger,
      type: .default)
    return nil
  } else {
    let implicitModulesByName = getImplicitModules(moduleCacheURL: moduleCacheURL)
    os_log(
      "Found %d explicit modules in metadata file and %d unique implicit modules in the module cache.",
      log: logger, type: .debug, explicitModuleNames.count, implicitModulesByName.count)
    let removedModules = removeImplicitModulesWithExplicitModuleCounterparts(
      implicitModulesByName: implicitModulesByName, explicitModuleNames: explicitModuleNames)
    updatePrunedModulesToken(computedHashValue, hashValueURL: hashValueURL)
    os_log(
      "Removed %d implicit modules from the module cache.",
      log: logger, type: .debug, removedModules.count)
    return removedModules
  }
}

private func removeImplicitModulesWithExplicitModuleCounterparts(
  implicitModulesByName: [String: [URL]], explicitModuleNames: [String]
) -> [URL] {
  var removedModules: [URL] = []
  let removedModulesWriteQueue = DispatchQueue(label: "pruned-modules")
  let moduleRemovalDispatchGroup = DispatchGroup()

  for moduleName in explicitModuleNames {
    let implicitModuleURLs = implicitModulesByName[moduleName, default: []]

    for url in implicitModuleURLs {
      os_log("Will remove %@.", log: logger, type: .debug, url.absoluteString)
      moduleRemovalDispatchGroup.enter()

      DispatchQueue.global(qos: .default).async {
        do {
          try fileManager.removeItem(at: url)
          os_log("Did remove %@.", log: logger, type: .debug, url.absoluteString)
          removedModulesWriteQueue.async {
            removedModules.append(url)
            moduleRemovalDispatchGroup.leave()
          }
        } catch {
          os_log(
            "Failed to remove %@: %@.", log: logger, type: .error, url.absoluteString,
            error.localizedDescription)
          moduleRemovalDispatchGroup.leave()
        }
      }
    }
  }

  moduleRemovalDispatchGroup.wait()
  return removedModules
}

private func readPrunedModulesToken(_ hashValueURL: URL) -> String? {
  do {
    let hashValue = try Data(contentsOf: hashValueURL)
    return String(data: hashValue, encoding: .utf8)
  } catch {
    if !error.isFileNotFound() {
      os_log(
        "Encountered an error while reading the stored explicit module hash at %@: %@", log: logger,
        type: .error, hashValueURL.absoluteString, error.localizedDescription)
    }
    // Returning `nil` guarantees that we will prune the module cache again since the newly computed
    // module cache will never be `nil` thus will never match this value.
    return nil
  }
}

private func updatePrunedModulesToken(_ hashValue: String, hashValueURL: URL) {
  do {
    let parentDirectoryURL = hashValueURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: parentDirectoryURL, withIntermediateDirectories: true, attributes: [:])
    try Data(hashValue.utf8).write(to: hashValueURL)
  } catch {
    // Failing to update the pruned module token means that the next run will compare the newly
    // computed module cache token with an outdated token. At worst this will trigger an unnecessary
    // module cache pruning.
    os_log(
      "Encountered an error while updating the stored explicit module hash at %@: %@", log: logger,
      type: .error, hashValueURL.absoluteString, error.localizedDescription)
  }
}

/// Computes a token to track what values were last pruned from the module cache. This can be used
/// to skip pruning when no new explicit modules were built that haven't already been pruned from
/// the implicit module cache. Returns nil when the array of modules is empty meaning that there is
/// nothing to compute.
private func computePrunedModulesToken(_ modules: [String]) -> String? {
  guard !modules.isEmpty else {
    return nil
  }

  let allModules = modules.sorted().joined(separator: ":")
  let inputData = Data(allModules.utf8)

  var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
  inputData.withUnsafeBytes {
    _ = CC_SHA256($0.baseAddress, CC_LONG(inputData.count), &hash)
  }
  return Data(hash).base64EncodedString()
}

extension Error {
  func isFileNotFound() -> Bool {
    let nsError = self as NSError
    return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError
  }
}
