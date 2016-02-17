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


extension NSThread {
  /// Performs the given closure on the main thread, possibly synchronously if called from the
  /// main thread.
  public class func doOnMainThread(closure: (Void) -> Void ) {
    if !NSThread.isMainThread() {
      dispatch_async(dispatch_get_main_queue(), closure)
    } else {
      closure()
    }
  }
}
