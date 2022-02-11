#!/usr/bin/python3
# -*- coding: utf-8 -*-
# Copyright 2022 The Tulsi Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Script responsible for resigning test artifacts so they can run on device."""

import json
import os
import subprocess
import sys

# List of frameworks that Xcode injects into test host targets that should be
# re-signed when running the tests on devices.
XCODE_INJECTED_FRAMEWORKS = [
    'libXCTestBundleInject.dylib',
    'libXCTestSwiftSupport.dylib',
    'IDEBundleInjection.framework',
    'XCTAutomationSupport.framework',
    'XCTest.framework',
    'XCTestCore.framework',
    'XCUnit.framework',
    'XCUIAutomation.framework',
]


def _PrintUnbuffered(msg):
  sys.stdout.write('%s\n' % msg)
  sys.stdout.flush()


def _PrintXcodeWarning(msg):
  sys.stdout.write(':: warning: %s\n' % msg)
  sys.stdout.flush()


def _PrintXcodeError(msg):
  sys.stderr.write(':: error: %s\n' % msg)
  sys.stderr.flush()


def _RunSubprocess(cmd):
  """Runs the given command as a subprocess, returning (exit_code, output)."""
  _PrintUnbuffered('Running %r' % cmd)
  process = subprocess.Popen(
      cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
  output, _ = process.communicate()
  return (process.returncode, output)


def _ResignBundle(bundle_path, signing_identity, entitlements=None):
  """Re-signs the bundle with the given signing identity and entitlements."""

  command = [
      'xcrun',
      'codesign',
      '-f',
      '--timestamp=none',
      '-s',
      signing_identity,
  ]

  if entitlements:
    command.extend(['--entitlements', entitlements])
  else:
    command.append('--preserve-metadata=entitlements')

  command.append(bundle_path)

  returncode, output = _RunSubprocess(command)
  if returncode:
    _PrintXcodeError('Re-sign command %r failed. %s' % (command, output))
    return returncode
  return 0


def _ResignXcodeTestFrameworks(bundle, signing_identity):
  """Re-signs the support frameworks injected by Xcode in the given bundle."""
  for framework in XCODE_INJECTED_FRAMEWORKS:
    framework_path = os.path.join(bundle, 'Frameworks', framework)
    if os.path.isdir(framework_path) or os.path.isfile(framework_path):
      exit_code = _ResignBundle(framework_path, signing_identity)
      if exit_code != 0:
        return exit_code
  return 0


class FrameworksResigningOperation(object):
  """Represents a resigning operation for the test frameworks of a bundle."""

  def __init__(self, bundle_path, signing_identity):
    """All arguments are required and non-None."""
    self.bundle_path = bundle_path
    self.signing_identity = signing_identity

  def __str__(self):
    return 'FrameworksResigningOperation: sign %s using identity %s' % (
        self.bundle_path, self.signing_identity)

  def Perform(self):
    return _ResignXcodeTestFrameworks(self.bundle_path, self.signing_identity)


class BundleResigningOperation(object):
  """Represents a resigning operation for a bundle."""

  def __init__(self, bundle_path, signing_identity, entitlements=None):
    """If the entitlements arg is not given, entitlements are preserved."""
    self.bundle_path = bundle_path
    self.signing_identity = signing_identity
    self.entitlements = entitlements

  def __str__(self):
    return ('BundleResigningOperation: sign %s using identity %s and '
            'entitlements %s') % (
                self.bundle_path, self.signing_identity, self.entitlements)

  def Perform(self):
    return _ResignBundle(self.bundle_path, self.signing_identity,
                         self.entitlements)


class OperationsSerialization(object):
  """Handles serialization of resigning operations."""

  BUNDLE_OPERATION = 'Bundle'
  FRAMEWORKS_OPERATION = 'Frameworks'

  @staticmethod
  def OperationsToJson(operations):
    """Convert the list of operations to a JSON list."""
    if not isinstance(operations, list):
      raise TypeError('Operations is not a list: %s' % str(operations))
    return [OperationsSerialization.OperationToJson(op) for op in operations]

  @staticmethod
  def OperationToJson(operation):
    """Convert the operation to a JSON dictionary."""
    if isinstance(operation, FrameworksResigningOperation):
      return {
          'type': OperationsSerialization.FRAMEWORKS_OPERATION,
          'bundle_path': operation.bundle_path,
          'signing_identity': operation.signing_identity
      }
    if isinstance(operation, BundleResigningOperation):
      return {
          'type': OperationsSerialization.BUNDLE_OPERATION,
          'bundle_path': operation.bundle_path,
          'signing_identity': operation.signing_identity,
          'entitlements': operation.entitlements
      }
    raise TypeError('Unknown resign operation: %s' % str(operation))

  @staticmethod
  def JsonToOperations(json_obj):
    """Convert the JSON list into a list of operations."""
    if not isinstance(json_obj, list):
      raise TypeError('Json operations object is not a list: %s' %
                      str(json_obj))
    return [OperationsSerialization.JsonToOperation(obj) for obj in json_obj]

  @staticmethod
  def JsonToOperation(json_obj):
    """Convert the JSON dictionary to an operation."""
    if not isinstance(json_obj, dict):
      raise TypeError('Json operation object is not a dict: %s' % str(json_obj))
    operation_type = json_obj.get('type', None)
    if operation_type == OperationsSerialization.FRAMEWORKS_OPERATION:
      return FrameworksResigningOperation(json_obj['bundle_path'],
                                          json_obj['signing_identity'])
    elif operation_type == OperationsSerialization.BUNDLE_OPERATION:
      return BundleResigningOperation(json_obj['bundle_path'],
                                      json_obj['signing_identity'],
                                      json_obj['entitlements'])
    else:
      raise TypeError('Invalid operation type: %s' % operation_type)


def PerformOperations(operations):
  """Perform the given resigning operations."""
  for operation in operations:
    returncode = operation.Perform()
    if returncode:
      _PrintXcodeError('Resign operation failed with %d: %s' %
                       (returncode, operation))
      return returncode
  return 0


def main():
  # Only need to resign artifacts for device.
  platform_name = os.environ['PLATFORM_NAME']
  if platform_name.endswith('simulator'):
    return 0

  resign_manifest_path = os.environ['TULSI_RESIGN_MANIFEST']
  with open(resign_manifest_path) as manifest_file:
    resign_manifest = json.load(manifest_file)
    operations = OperationsSerialization.JsonToOperations(resign_manifest)
    return PerformOperations(operations)


if __name__ == '__main__':
  sys.exit(main())
