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

import Foundation


/// Wraps the standard ProcessRunner and injects Tulsi-specific environment variables.
public final class TulsiProcessRunner {

  public typealias CompletionHandler = (ProcessRunner.CompletionInfo) -> Void

  private static var defaultEnvironment: [String: String] = {
    var environment = ProcessInfo.processInfo.environment
    if let cfBundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
      environment["TULSI_VERSION"] = cfBundleVersion
    }
    return environment
  }()

  /// Prepares a Process using the given launch binary with the given arguments that will collect
  /// output and passing it to a terminationHandler.
  static func createProcess(_ launchPath: String,
                            arguments: [String],
                            environment: [String: String] = [:],
                            messageLogger: LocalizedMessageLogger? = nil,
                            loggingIdentifier: String? = nil,
                            terminationHandler: @escaping CompletionHandler) -> Process {
    let env = environment.merging(defaultEnvironment) { (current, _) in
      return current
    }
    return ProcessRunner.createProcess(launchPath,
                                       arguments: arguments,
                                       environment: env,
                                       messageLogger: messageLogger,
                                       loggingIdentifier: loggingIdentifier,
                                       terminationHandler: terminationHandler)
  }
}
