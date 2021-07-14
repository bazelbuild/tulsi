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
import os

private let fileManager = FileManager.default

/// Reads the contents of the module cache and returns a dictionary that maps the name of a module
/// to all pcm files in the module cache for that module.
func getImplicitModules(moduleCacheURL: URL) -> [String: [URL]] {
  let implicitModules = getModulesInModuleCache(moduleCacheURL)
  return mapModuleNamesToModuleURLs(implicitModules)
}

/// Converts a list of precompiled module URLs into a dictionary that maps module names to the
/// locations of pcm files for that module.
private func mapModuleNamesToModuleURLs(_ moduleURLs: [URL]) -> [String: [URL]] {
  var moduleNameToURLs: [String: [URL]] = [:]

  for url in moduleURLs {
    if let moduleName = moduleNameForImplicitPrecompiledModule(at: url) {
      var urlsForModule = moduleNameToURLs[moduleName, default: []]
      urlsForModule.append(url)
      moduleNameToURLs[moduleName] = urlsForModule
    }
  }

  return moduleNameToURLs
}

/// Reads the contents of the module cache and returns a list of paths to all the precompiled
/// files in URL form.
private func getModulesInModuleCache(_ moduleCacheURL: URL) -> [URL] {
  let subdirectories = getDirectoriesInModuleCacheRoot(moduleCacheURL)
  var moduleURLs = [URL]()

  let moduleURLsWriteQueue = DispatchQueue(label: "module-cache-urls")
  let directoryEnumeratingDispatchGroup = DispatchGroup()

  for subdirectory in subdirectories {
    directoryEnumeratingDispatchGroup.enter()

    DispatchQueue.global(qos: .default).async {
      let modulesInSubdirectory = getModulesInModuleCacheSubdirectory(subdirectory)
      moduleURLsWriteQueue.async {
        moduleURLs.append(contentsOf: modulesInSubdirectory)
        directoryEnumeratingDispatchGroup.leave()
      }
    }
  }

  directoryEnumeratingDispatchGroup.wait()
  return moduleURLs
}

/// Returns the directories in the root of the module cache directory. Precompiled modules are not
/// found in the root of the module cache directory, they are only found within the subdirectories
/// that are returned by this function.
///
/// ModuleCache.noindex/
///   |- <HashA>/
///   |- ...
///   |- <HashZ>/
///   |- <ModuleName-HashAA>.swiftmodule
///   |- ...
///   |- <ModuleName-HashZZ>.swiftmodule
private func getDirectoriesInModuleCacheRoot(_ moduleCacheURL: URL) -> [URL] {
  do {
    let contents = try fileManager.contentsOfDirectory(
      at: moduleCacheURL, includingPropertiesForKeys: nil, options: [])
    return contents.filter { $0.hasDirectoryPath }
  } catch {
    os_log(
      "Failed to read contents of module cache root at %@: %@", log: logger, type: .error,
      moduleCacheURL.absoluteString, error.localizedDescription)
    return []
  }
}

/// Returns the precompiled module files found in the given subdirectory. Subdirectories will
/// contain precompiled modules and temporary timestamps.
///
/// ModuleCache.noindex/
///   |- <HashA>/
///     |- <ModuleName-HashAA>.pcm
///     |- ...
///     |- <ModuleName-HashAZ>.pcm
///   |- ...
///   |- <HashZ>/
///     |- <ModuleName-HashZA>.pcm
///     |- ...
///     |- <ModuleName-HashZZ>.pcm
private func getModulesInModuleCacheSubdirectory(
  _ directoryURL: URL
) -> [URL] {
  do {
    let contents = try fileManager.contentsOfDirectory(
      at: directoryURL, includingPropertiesForKeys: nil, options: [])
    return contents.filter { !$0.hasDirectoryPath && $0.pathExtension == "pcm" }
  } catch {
    os_log(
      "Failed to read contents of module cache subdirectory at %@: %@", log: logger, type: .error,
      directoryURL.absoluteString, error.localizedDescription)
    return []
  }
}

/// Extracts the module name from an implicit module in LLDB's module cache. Implicit Modules are of
/// the form "<ModuleName-HashAA>.pcm" e.g. "Foundation-3DFYNEBRQSXST.pcm".
private func moduleNameForImplicitPrecompiledModule(at moduleURL: URL) -> String? {
  let filename = moduleURL.lastPathComponent
  return filename.components(separatedBy: "-").first
}
