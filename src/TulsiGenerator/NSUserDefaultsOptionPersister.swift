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


/// Concrete option persister backed by NSUserDefaults storage.
class NSUserDefaultsOptionPersister: OptionPersisterProtocol {
  /// Key used to store Tulsi options assigned to all targets loaded from a particular BUILD file.
  static let PROJECT_VALUE_KEY = "!build!"

  /// Key used to store a map of Bazel target to specific Tulsi option values.
  static let TARGET_VALUES_KEY = "!targets!"

  /// Key under which BUILD/target specific options are stored in NSUserDefaults.
  let projectStorageKey: String

  init(projectStorageKey: String) {
    self.projectStorageKey = projectStorageKey
  }

  // MARK: - OptionPersisterProtocol

  func saveProjectValue(value: String?, forStorageKey key: String) {
    persistSpecializedValue(value,
                            forOptionKey: key,
                            specializationKey: NSUserDefaultsOptionPersister.PROJECT_VALUE_KEY)
  }

  func saveTargetValues(values: [String: String]?, forStorageKey key: String) {
    persistSpecializedValue(values,
                            forOptionKey: key,
                            specializationKey: NSUserDefaultsOptionPersister.TARGET_VALUES_KEY)
  }

  func loadProjectValueForStorageKey(storageKey: String) -> String? {
    let specializedOptions = loadDictionaryForKey(projectStorageKey)
    guard let values = specializedOptions[storageKey] as? [String: AnyObject] else {
      return nil
    }
    return values[NSUserDefaultsOptionPersister.PROJECT_VALUE_KEY] as? String
  }

  func loadTargetValueForStorageKey(storageKey: String) -> [String:String]? {
    let specializedOptions = loadDictionaryForKey(projectStorageKey)
    guard let values = specializedOptions[storageKey] as? [String: AnyObject] else {
      return nil
    }
    return values[NSUserDefaultsOptionPersister.TARGET_VALUES_KEY] as? [String: String]
  }

  // MARK: - Private methods

  private func loadDictionaryForKey(key: String) -> [String: AnyObject] {
    let userDefaults = NSUserDefaults.standardUserDefaults()
    if let storedOpts = userDefaults.dictionaryForKey(key) {
      return storedOpts
    }
    return [String: AnyObject]()
  }

  private func setOrRemoveValue(value: AnyObject?,
                                forKey k: String,
                                inout inDictionary storedOptions: [String: AnyObject]) {
    if value != nil {
      storedOptions[k] = value!
    } else {
      storedOptions.removeValueForKey(k)
    }
  }

  // Persists the given project-specific values. Project specific values are stored as a dictionary
  // under some unique key (likely the path to a BUILD file) which maps option keys to value
  // subdictionaries. Each subdictionary contains two values under these specializationKeys:
  // - PROJECT_VALUE_KEY: maps to a single default value to use for this option
  // - TARGET_VALUES_KEY: maps to a dictionary of target label -> value to use for that particular
  //     target.
  private func persistSpecializedValue(value: AnyObject?,
                                       forOptionKey optionKey: String,
                                       specializationKey: String ) {
    let userDefaults = NSUserDefaults.standardUserDefaults()
    var specializedOptions = loadDictionaryForKey(projectStorageKey)

    var currentOptions: [String: AnyObject]
    if let storedOptions = specializedOptions[optionKey] as? [String: AnyObject] {
      currentOptions = storedOptions
    } else {
      currentOptions = [String: AnyObject]()
    }

    setOrRemoveValue(value,
                     forKey: specializationKey,
                     inDictionary: &currentOptions)

    specializedOptions[optionKey] = currentOptions
    userDefaults.setObject(specializedOptions, forKey: projectStorageKey)
  }
}
