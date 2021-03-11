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

import Foundation

// Provides methods to patch up Bazel specific PBX objects and references before project generation.
// This patches @external container Bazel files to be relative to the exec root.
final class BazelPBXReferencePatcher {

  private let fileManager: FileManager

  init(fileManager: FileManager) {
    self.fileManager = fileManager
  }

  // Resolves the given Bazel exec-root relative path to a filesystem path.
  // This is intended to be used to resolve "@external_repo" style labels to paths usable by Xcode
  // and any other paths that must be relative to the Bazel exec root.
  private func resolvePathFromBazelExecRoot(_ xcodeProject: PBXProject, _ path: String) -> String {
    return "\(xcodeProject.name).xcodeproj/.tulsi/\(PBXTargetGenerator.TulsiWorkspacePath)/\(path)"
  }

  // Returns true if the file reference patching was handled.
  func patchNonPresentFileReference(file: PBXFileReference,
                                    url: URL,
                                    workspaceRootURL: URL) -> Bool {
    return false
  }

  // Examines the given xcodeProject, patching any groups that were generated under Bazel's magical
  // "external" container to absolute filesystem references.
  func patchExternalRepositoryReferences(_ xcodeProject: PBXProject) {
    let mainGroup = xcodeProject.mainGroup
    guard let externalGroup = mainGroup.childGroupsByName["external"] else { return }

    // The external directory may contain files such as a WORKSPACE file, but we only patch folders
    let childGroups = externalGroup.children.filter { $0 is PBXGroup } as! [PBXGroup]

    for child in childGroups {
      let resolvedPath = resolvePathFromBazelExecRoot(xcodeProject, "external/\(child.name)")
      let newChild = mainGroup.getOrCreateChildGroupByName("@\(child.name)",
                                                           path: resolvedPath,
                                                           sourceTree: .SourceRoot)
      newChild.migrateChildrenOfGroup(child)
    }
    mainGroup.removeChild(externalGroup)
  }
}
