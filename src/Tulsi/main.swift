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

import Cocoa
import TulsiGenerator

private func main() {
  // Parse the commandline parameters to see if the app should operate in headless mode or not.
  let commandlineParser = TulsiCommandlineParser()

  let consoleLogger = EventLogger(verbose: commandlineParser.arguments.verbose)
  consoleLogger.startLogging()

  if !commandlineParser.commandlineSentinalFound {
    NSApplicationMain(Process.argc, Process.unsafeArgv)
    exit(0)
  }

  let queue = dispatch_queue_create("com.google.Tulsi.xcodeProjectGenerator", DISPATCH_QUEUE_SERIAL)
  dispatch_async(queue) {
    let generator = HeadlessXcodeProjectGenerator(arguments: commandlineParser.arguments)
    do {
      try generator.generate()
    } catch HeadlessXcodeProjectGenerator.Error.MissingConfigOption(let option) {
      print("Missing required \(option) param.")
      exit(10)
    } catch HeadlessXcodeProjectGenerator.Error.InvalidConfigPath(let reason) {
      print("Invalid \(TulsiCommandlineParser.ParamGeneratorConfigLong) param: \(reason)")
      exit(11)
    } catch HeadlessXcodeProjectGenerator.Error.InvalidConfigFileContents(let reason) {
      print("Failed to read the given generator config: \(reason)")
      exit(12)
    } catch HeadlessXcodeProjectGenerator.Error.ExplicitOutputOptionRequired {
      print("The \(TulsiCommandlineParser.ParamOutputFolderLong) option is required for the selected config")
      exit(13)
    } catch HeadlessXcodeProjectGenerator.Error.InvalidBazelPath {
      print("The path to the bazel binary is invalid")
      exit(14)
    } catch HeadlessXcodeProjectGenerator.Error.GenerationFailed(let reason) {
      print("Generation failed: \(reason)")
      exit(15)
    } catch HeadlessXcodeProjectGenerator.Error.InvalidWorkspaceRootOverride {
      print("The parameter given as the workspace root path is not a valid directory")
      exit(16)
    } catch HeadlessXcodeProjectGenerator.Error.InvalidProjectFileContents(let reason) {
      print("Failed to read the given project: \(reason)")
      exit(20)
    } catch let e as NSError {
      print("An unexpected exception occurred: \(e.localizedDescription)")
      exit(126)
    } catch {
      print("An unexpected exception occurred")
      exit(127)
    }

    // Ideally this would go just after generator.generate() inside the do block, but doing so trips
    // up the coverage tool as exit is @noreturn. It is important that all catch blocks exit with
    // non-zero codes so that they do not reach this.
    exit(0)
  }

  dispatch_main()
}

// MARK: - Application entrypoint

main()
