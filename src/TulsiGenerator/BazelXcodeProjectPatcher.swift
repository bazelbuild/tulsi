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
// This will remove any invalid .xcassets in order to make Xcode happy, as well as apply a
// BazelPBXReferencePatcher to any files that can't be found. As a backup, paths are set to be
// relative to the Bazel exec root for non-generated files.
final class BazelXcodeProjectPatcher {

  // FileManager used to check for presence of PBXFileReferences when patching.
  let fileManager: FileManager

  init(fileManager: FileManager) {
    self.fileManager = fileManager
  }

  // Rewrites the path for file references that it believes to be relative to Bazel's exec root.
  // This should be called before patching external references.
  private func patchFileReference(xcodeProject: PBXProject, file: PBXFileReference, url: URL, workspaceRootURL: URL) {
    // We only want to modify the path if the current path doesn't point to a valid file.
    guard !fileManager.fileExists(atPath: url.path) else { return }

    // Don't patch anything that isn't group relative.
    guard file.sourceTree == .Group else { return }

    // Guaranteed to have parent bc that's how we accessed it.
    // Parent guaranteed to be PBXGroup because it's a PBXFileReference
    let parent = file.parent as! PBXGroup

    // Just remove .xcassets that are not present. Unfortunately, Xcode's handling of .xcassets has
    // quite a number of issues with Tulsi and readonly files.
    //
    // .xcassets references in a project that are not present on disk will present a warning after
    // opening the main target.
    //
    // Readonly (not writeable) .xcassets that contain an .appiconset with a Contents.json will
    // trigger Xcode into an endless loop of
    //     "You don’t have permission to save the file “Contents.json” in the folder <X>."
    // This is present in Xcode 8.3.3 and Xcode 9b2.
    guard !url.path.hasSuffix(".xcassets") else {
      parent.removeChild(file)
      return
    }

    // Default to be relative to the bazel exec root
    // This is for both source files as well as generated files (which always need to be relative
    // to the bazel exec root).
    let newPath = "\(xcodeProject.name).xcodeproj/\(PBXTargetGenerator.TulsiExecutionRootSymlinkPath)/\(file.path!)"
    parent.updatePathForChildFile(file, toPath: newPath, sourceTree: .SourceRoot)
  }

  // Handles patching PBXFileReferences that are not present on disk. This should be called before
  // calling patchExternalRepositoryReferences.
  func patchBazelRelativeReferences(_ xcodeProject: PBXProject,
                                    _ workspaceRootURL : URL) {
    // Exclude external references that have yet to be patched in.
    var queue = xcodeProject.mainGroup.children.filter{ $0.name != "external" }

    while !queue.isEmpty {
      let ref = queue.remove(at: 0)
      if let group = ref as? PBXGroup {
        // Queue up all children of the group so we can find all of their FileReferences.
        queue.append(contentsOf: group.children)
      } else if let file = ref as? PBXFileReference,
                let fileURL = URL(string: file.path!, relativeTo: workspaceRootURL) {
        self.patchFileReference(xcodeProject: xcodeProject, file: file, url: fileURL,
                                workspaceRootURL: workspaceRootURL)
      }
    }
  }

  // Handles patching any groups that were generated under Bazel's magical "external" container to
  // proper filesystem references. This should be called after patchBazelRelativeReferences.
  func patchExternalRepositoryReferences(_ xcodeProject: PBXProject) {
    let mainGroup = xcodeProject.mainGroup
    guard let externalGroup = mainGroup.childGroupsByName["external"] else { return }

    // The external directory may contain files such as a WORKSPACE file, but we only patch folders
    let childGroups = externalGroup.children.filter { $0 is PBXGroup } as! [PBXGroup]

    for child in childGroups {
      // Resolve external workspaces via their more stable location in output base
      // <output base>/external remains between builds and contains all external workspaces
      // <execution root>/external is instead torn down on each build, breaking the paths to any
      // external workspaces not used in the particular target being built 
      let resolvedPath = "\(xcodeProject.name).xcodeproj/\(PBXTargetGenerator.TulsiOutputBaseSymlinkPath)/external/\(child.name)"
      let newChild = mainGroup.getOrCreateChildGroupByName("@\(child.name)",
                                                           path: resolvedPath,
                                                           sourceTree: .SourceRoot)
      newChild.migrateChildrenOfGroup(child)
    }
    mainGroup.removeChild(externalGroup)
  }
}
