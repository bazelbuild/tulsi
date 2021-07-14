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

/// Wraps values that may be needed to describe a module. This allows our tests to use wrapper
/// functions to create fake module caches, metadata files, etc that take instances of these fake
/// modules and extract any module related information needed for a specific function.
struct FakeModule {
  /// The name of the module. e.g. "Foundation"
  let name: String
  /// The filename of the clang module. e.g. "Foundation.swift.pcm"
  let clangName: String
  /// The filename of the swift module. e.g. "Foundation.swiftmodule"
  let swiftName: String
  /// The filepath to the explicit clang module.
  /// e.g. "/private/var/.../bin/buttons/Foundation.swift.pcm"
  let explicitFilepath: String
  /// The filename of the implicit clang module. e.g. "Foundation-ABCDEFGH.pcm"
  /// Note that implicit modules are in the format `<ModuleName>-<BuildOptionsHash>.pcm` and depend
  /// on the build options used for the implicit compilation. This means that in a real implicit
  /// module cache there can be multiple implicit PCMs for the same module.
  let implicitFilename: String

  private static let hashLength = 8
  private static let outputDirectory =
    "/private/var/tmp/_bazel_<user>/<workspace-hash>/execroot/<workspace-name>/bazel-out/ios_x86_64-dbg/bin/buttons"

  init(_ name: String, hashCharacter: String) {
    self.name = name
    self.clangName = "\(name).swift.pcm"
    self.swiftName = "\(name).swiftmodule"
    self.explicitFilepath = "\(FakeModule.outputDirectory)/\(name).swift.pcm"
    self.implicitFilename =
      "\(name)-\(String(repeating: hashCharacter, count: FakeModule.hashLength)).pcm"
  }
}

struct SystemModules {
  let foundation = FakeModule("Foundation", hashCharacter: "A")
  let coreFoundation = FakeModule("CoreFoundation", hashCharacter: "B")
  let darwin = FakeModule("Darwin", hashCharacter: "C")
}

struct UserModules {
  let buttonsLib = FakeModule("ButtonsLib", hashCharacter: "1")
  let buttonsModel = FakeModule("ButtonsModel", hashCharacter: "2")
  let buttonsIdentity = FakeModule("ButtonsIdentity", hashCharacter: "3")
}

/// Encapsulates various ready-to-use fake modules for tests.
struct FakeModules {
  let system = SystemModules()
  let user = UserModules()
}
