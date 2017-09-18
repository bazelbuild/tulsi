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


extension Thread {
  /// Performs the given closure on the main queue.
  public class func doOnMainQueue(_ closure: @escaping () -> Void ) {
    DispatchQueue.main.async(execute: closure)
  }

  /// Performs the given closure on the system thread reserved for user-initiated activities.
  public class func doOnQOSUserInitiatedThread(_ closure: @escaping () -> Void ) {
    DispatchQueue.global(qos: DispatchQoS.QoSClass.userInitiated).async(execute: closure)
  }
}
