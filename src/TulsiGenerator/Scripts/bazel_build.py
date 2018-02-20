#!/usr/bin/python
# Copyright 2016 The Tulsi Authors. All rights reserved.
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

"""Bridge between Xcode and Bazel for the "build" action.

NOTE: This script must be executed in the same directory as the Xcode project's
main group in order to generate correct debug symbols.
"""

import atexit
import collections
import errno
import fcntl
import io
import json
import os
import re
import shutil
import signal
import StringIO
import subprocess
import sys
import textwrap
import time
import zipfile

import bazel_build_events
import bazel_options
from execroot_path import BAZEL_EXECUTION_ROOT
import tulsi_logging


# List of frameworks that Xcode injects into test host targets that should be
# re-signed when running the tests on devices.
XCODE_INJECTED_FRAMEWORKS = [
    'IDEBundleInjection',
    'XCTAutomationSupport',
    'XCTest',
]

_logger = tulsi_logging.Logger()


def _PrintXcodeWarning(msg):
  sys.stdout.write(':: warning: %s\n' % msg)
  sys.stdout.flush()


def _PrintXcodeError(msg):
  sys.stderr.write(':: error: %s\n' % msg)
  sys.stderr.flush()


CLEANUP_BEP_FILE_AT_EXIT = False


# Function to be called atexit to clean up the BEP file if one is present.
# This is especially useful in cases of abnormal termination (such as what
# happens when Xcode is killed).
def _BEPFileExitCleanup(bep_file_path):
  if not CLEANUP_BEP_FILE_AT_EXIT:
    return
  try:
    os.remove(bep_file_path)
  except OSError as e:
    _PrintXcodeWarning('Failed to remove BEP file from %s. Error: %s' %
                       (bep_file_path, e.strerror))


def _InterruptHandler(signum, frame):
  """Gracefully exit on SIGINT."""
  del signum, frame  # Unused.
  sys.stdout.write('Caught interrupt signal. Exiting...\n')
  sys.exit(0)


class Timer(object):
  """Simple profiler."""

  def __init__(self, action_name, action_id):
    """Creates a new Timer object.

    Args:
      action_name: A human-readable action name, shown in the build log.
      action_id: A machine-readable action identifier, can be used for metrics.

    Returns:
      A Timer instance.
    """
    self.action_name = action_name
    self.action_id = action_id
    self._start = None

  def Start(self):
    self._start = time.time()
    return self

  def End(self):
    end = time.time()
    seconds = end - self._start
    _logger.log_action(self.action_name, self.action_id, seconds)


# Function to be called atexit to release the file lock on script termination.
def _LockFileExitCleanup(lock_file_handle):
  lock_file_handle.close()


def _LockFileAcquire(lock_path):
  """Force script to wait on global file lock to serialize build target actions.

  Args:
    lock_path: Path to the lock file.
  """
  sys.stdout.write('Queuing Tulsi build...\n')
  sys.stdout.flush()
  locktimer = Timer('Acquiring %s' % lock_path, 'tulsi_build_lock').Start()
  # TODO(b/69414272): See if we can improve this for multiple WORKSPACEs.
  lockfile = open(lock_path, 'w')
  # Register "fclose(...)" as early as possible, before acquiring lock.
  atexit.register(_LockFileExitCleanup, lockfile)
  while True:
    try:
      fcntl.lockf(lockfile, fcntl.LOCK_EX | fcntl.LOCK_NB)
      break
    except IOError as err:
      if err.errno != errno.EAGAIN:
        raise
      else:
        time.sleep(0.1)
  locktimer.End()


class CodesignBundleAttributes(object):
  """Wrapper class for codesigning attributes of a signed bundle."""

  # List of codesigning attributes that this script requires.
  _ATTRIBUTES = ['Authority', 'Identifier', 'TeamIdentifier']

  def __init__(self, codesign_output):
    self.attributes = {}

    pending_attributes = list(self._ATTRIBUTES)
    for line in codesign_output.split('\n'):
      if not pending_attributes:
        break

      for attribute in pending_attributes:
        if line.startswith(attribute):
          value = line[len(attribute) + 1:]
          self.attributes[attribute] = value
          pending_attributes.remove(attribute)
          break

    for attribute in self._ATTRIBUTES:
      if attribute not in self.attributes:
        _PrintXcodeError(
            'Failed to extract %s from %s.\n' % (attribute, codesign_output))

  def Get(self, attribute):
    """Returns the value for the given attribute, or None if it wasn't found."""
    value = self.attributes.get(attribute)
    if attribute not in self._ATTRIBUTES:
      _PrintXcodeError(
          'Attribute %s not declared to be parsed. ' % attribute +
          'Available attributes are %s.\n' % self._ATTRIBUTES)
    return value


class _OptionsParser(object):
  """Handles parsing script options."""

  # Key for options that should be applied to all build configurations.
  ALL_CONFIGS = '__all__'

  # The build configurations handled by this parser.
  KNOWN_CONFIGS = ['Debug', 'Release', 'Fastbuild']

  def __init__(self, sdk_version, platform_name, arch, main_group_path):
    self.targets = []
    self.startup_options = collections.defaultdict(list)
    self.build_options = collections.defaultdict(
        list,
        {
            _OptionsParser.ALL_CONFIGS: [
                '--verbose_failures',
                '--announce_rc',
            ],

            'Debug': [
                '--compilation_mode=dbg',
            ],

            'Release': [
                '--compilation_mode=opt',
                '--strip=always',
            ],

            'Fastbuild': [
                '--compilation_mode=fastbuild',
            ],
        })

    # Options specific to debugger integration in Xcode.
    xcode_version_major = int(os.environ['XCODE_VERSION_MAJOR'])
    if xcode_version_major < 800:
      xcode_lldb_options = [
          '--copt=-Xclang', '--copt=-fdebug-compilation-dir',
          '--copt=-Xclang', '--copt=%s' % main_group_path,
          '--objccopt=-Xclang', '--objccopt=-fdebug-compilation-dir',
          '--objccopt=-Xclang', '--objccopt=%s' % main_group_path,
      ]
      self.build_options['Debug'].extend(xcode_lldb_options)
      self.build_options['Release'].extend(xcode_lldb_options)

    self.sdk_version = sdk_version
    self.platform_name = platform_name

    if self.platform_name.startswith('watch'):
      config_platform = 'watchos'
    elif self.platform_name.startswith('iphone'):
      config_platform = 'ios'
    elif self.platform_name.startswith('macos'):
      config_platform = 'darwin'
    elif self.platform_name.startswith('appletv'):
      config_platform = 'tvos'
    else:
      self._WarnUnknownPlatform()
      config_platform = 'ios'
    self.build_options[_OptionsParser.ALL_CONFIGS].append(
        '--config=%s_%s' % (config_platform, arch))

    self.verbose = 0
    self.install_generated_artifacts = False
    self.bazel_bin_path = 'bazel-bin'
    self.bazel_executable = None

  @staticmethod
  def _UsageMessage():
    """Returns a usage message string."""
    usage = textwrap.dedent("""\
      Usage: %s <target> [<target2> ...] --bazel <bazel_binary_path> [options]

      Where options are:
        --verbose [-v]
            Increments the verbosity of the script by one level. This argument
            may be provided multiple times to enable additional output levels.

        --bazel_startup_options <option1> [<option2> ...] --
            Provides one or more Bazel startup options.

        --bazel_options <option1> [<option2> ...] --
            Provides one or more Bazel build options.

        --bazel_bin_path <path>
            Path at which Bazel-generated artifacts may be retrieved.
      """ % sys.argv[0])

    usage += '\n' + textwrap.fill(
        'Note that the --bazel_startup_options and --bazel_options options may '
        'include an optional configuration specifier in brackets to limit '
        'their contents to a given build configuration. Options provided with '
        'no configuration filter will apply to all configurations in addition '
        'to any configuration-specific options.', 120)

    usage += '\n' + textwrap.fill(
        'E.g., --bazel_options common --  --bazel_options[Release] release -- '
        'would result in "bazel build common release" in the "Release" '
        'configuration and "bazel build common" in all other configurations.',
        120)

    return usage

  def ParseOptions(self, args):
    """Parses arguments, returning (message, exit_code)."""

    bazel_executable_index = args.index('--bazel')

    self.targets = args[:bazel_executable_index]
    if not self.targets or len(args) < bazel_executable_index + 2:
      return (self._UsageMessage(), 10)
    self.bazel_executable = args[bazel_executable_index + 1]

    return self._ParseVariableOptions(args[bazel_executable_index + 2:])

  def GetStartupOptions(self, config):
    """Returns the full set of startup options for the given config."""
    return self._GetOptions(self.startup_options, config)

  def GetBuildOptions(self, config):
    """Returns the full set of build options for the given config."""
    options = self._GetOptions(self.build_options, config)

    version_string = self._GetXcodeVersionString()
    if version_string:
      self._AddDefaultOption(options, '--xcode_version', version_string)

    if self.sdk_version:
      if self.platform_name.startswith('watch'):
        self._AddDefaultOption(options,
                               '--watchos_sdk_version',
                               self.sdk_version)
      elif self.platform_name.startswith('iphone'):
        self._AddDefaultOption(options, '--ios_sdk_version', self.sdk_version)
      elif self.platform_name.startswith('macos'):
        self._AddDefaultOption(options, '--macos_sdk_version', self.sdk_version)
      elif self.platform_name.startswith('appletv'):
        self._AddDefaultOption(options, '--tvos_sdk_version', self.sdk_version)
      else:
        self._WarnUnknownPlatform()
        self._AddDefaultOption(options, '--ios_sdk_version', self.sdk_version)
    return options

  @staticmethod
  def _AddDefaultOption(option_list, option, default_value):
    matching_options = [opt for opt in option_list if opt.startswith(option)]
    if matching_options:
      return option_list

    option_list.append('%s=%s' % (option, default_value))
    return option_list

  @staticmethod
  def _GetOptions(option_set, config):
    """Returns a flattened list from options_set for the given config."""
    options = list(option_set[_OptionsParser.ALL_CONFIGS])
    if config != _OptionsParser.ALL_CONFIGS:
      options.extend(option_set[config])
    return options

  def _WarnUnknownPlatform(self):
    sys.stdout.write('Warning: unknown platform "%s" will be treated as '
                     'iOS\n' % self.platform_name)
    sys.stdout.flush()

  def _ParseVariableOptions(self, args):
    """Parses flag-based args, returning (message, exit_code)."""

    verbose_re = re.compile('-(v+)$')

    while args:
      arg = args[0]
      args = args[1:]

      if arg == '--install_generated_artifacts':
        self.install_generated_artifacts = True

      elif arg.startswith('--bazel_startup_options'):
        config = self._ParseConfigFilter(arg)
        args, items, terminated = self._ParseDoubleDashDelimitedItems(args)
        if not terminated:
          return ('Missing "--" terminator while parsing %s' % arg, 2)
        duplicates = self._FindDuplicateOptions(self.startup_options,
                                                config,
                                                items)
        if duplicates:
          return (
              '%s items conflict with common options: %s' % (
                  arg, ','.join(duplicates)),
              2)
        self.startup_options[config].extend(items)

      elif arg.startswith('--bazel_options'):
        config = self._ParseConfigFilter(arg)
        args, items, terminated = self._ParseDoubleDashDelimitedItems(args)
        if not terminated:
          return ('Missing "--" terminator while parsing %s' % arg, 2)
        duplicates = self._FindDuplicateOptions(self.build_options,
                                                config,
                                                items)
        if duplicates:
          return (
              '%s items conflict with common options: %s' % (
                  arg, ','.join(duplicates)),
              2)
        self.build_options[config].extend(items)

      elif arg == '--bazel_bin_path':
        if not args:
          return ('Missing required parameter for %s' % arg, 2)
        self.bazel_bin_path = args[0]
        args = args[1:]

      elif arg == '--verbose':
        self.verbose += 1

      else:
        match = verbose_re.match(arg)
        if match:
          self.verbose += len(match.group(1))
        else:
          return ('Unknown option "%s"\n%s' % (arg, self._UsageMessage()), 1)

    return (None, 0)

  @staticmethod
  def _ParseConfigFilter(arg):
    match = re.search(r'\[([^\]]+)\]', arg)
    if not match:
      return _OptionsParser.ALL_CONFIGS
    return match.group(1)

  @staticmethod
  def _ConsumeArgumentForParam(param, args):
    if not args:
      return (None, 'Missing required parameter for "%s" option' % param)
    val = args[0]
    return (args[1:], val)

  @staticmethod
  def _ParseDoubleDashDelimitedItems(args):
    """Consumes options until -- is found."""
    options = []
    terminator_found = False

    opts = args
    while opts:
      opt = opts[0]
      opts = opts[1:]
      if opt == '--':
        terminator_found = True
        break
      options.append(opt)

    return opts, options, terminator_found

  @staticmethod
  def _FindDuplicateOptions(options_dict, config, new_options):
    """Returns a list of options appearing in both given option lists."""

    allowed_duplicates = [
        '--copt',
        '--config',
        '--define',
        '--objccopt',
    ]

    def ExtractOptionNames(opts):
      names = set()
      for opt in opts:
        split_opt = opt.split('=', 1)
        if split_opt[0] not in allowed_duplicates:
          names.add(split_opt[0])
      return names

    current_set = ExtractOptionNames(options_dict[config])
    new_set = ExtractOptionNames(new_options)
    conflicts = current_set.intersection(new_set)

    if config != _OptionsParser.ALL_CONFIGS:
      current_set = ExtractOptionNames(options_dict[_OptionsParser.ALL_CONFIGS])
      conflicts = conflicts.union(current_set.intersection(new_set))
    return conflicts

  @staticmethod
  def _GetXcodeVersionString():
    """Returns Xcode version info from the environment as a string."""
    reported_version = os.environ['XCODE_VERSION_ACTUAL']
    match = re.match(r'(\d{2})(\d)(\d)$', reported_version)
    if not match:
      sys.stdout.write('Warning: Failed to extract Xcode version from %s\n' % (
          reported_version))
      sys.stdout.flush()
      return None
    major_version = int(match.group(1))
    minor_version = int(match.group(2))
    fix_version = int(match.group(3))
    fix_version_string = ''
    if fix_version:
      fix_version_string = '.%d' % fix_version
    return '%d.%d%s' % (major_version, minor_version, fix_version_string)


class BazelBuildBridge(object):
  """Handles invoking Bazel and unpacking generated binaries."""

  BUILD_EVENTS_FILE = 'build_events.json'

  SPOTLIGHT_CHECK_ENVVAR = 'TULSI_BUILD_WITHOUT_SPOTLIGHT_AT_MY_OWN_RISK'

  def __init__(self):
    self.verbose = 0
    self.build_path = None
    self.bazel_bin_path = None
    self.codesign_attributes = {}

    self.codesigning_folder_path = os.environ['CODESIGNING_FOLDER_PATH']

    self.xcode_action = os.environ['ACTION']  # The Xcode build action.
    # When invoked as an external build system script, Xcode will set ACTION to
    # an empty string.
    if not self.xcode_action:
      self.xcode_action = 'build'

    self.build_without_spotlight = os.environ.get(
        BazelBuildBridge.SPOTLIGHT_CHECK_ENVVAR, 'NO') == 'YES'

    self.generate_dsym = (os.environ.get('TULSI_ALL_DSYM', 'NO') == 'YES' or
                          os.environ.get('TULSI_MUST_USE_DSYM', 'NO') == 'YES')
    self.use_debug_prefix_map = os.environ.get('TULSI_DEBUG_PREFIX_MAP',
                                               'NO') == 'YES'
    self.extra_remap_path = os.environ.get('TULSI_EXTRA_REMAP_PATH', '')
    self.remap_dotted_paths = os.environ.get('TULSI_REMAP_DOTTED_PATHS',
                                             'NO') == 'YES'

    # Target architecture.  Must be defined for correct setting of
    # the --config flag
    self.arch = os.environ.get('CURRENT_ARCH')
    if not self.arch:
      _PrintXcodeError('Tulsi requires env variable CURRENT_ARCH to be '
                       'set.  Please file a bug against Tulsi.')
      sys.exit(1)

    # Path into which generated artifacts should be copied.
    self.built_products_dir = os.environ['BUILT_PRODUCTS_DIR']
    # Whether or not code coverage information should be generated.
    self.code_coverage_enabled = (
        os.environ.get('CLANG_COVERAGE_MAPPING') == 'YES')
    # Path where Xcode expects generated sources to be placed.
    self.derived_sources_folder_path = os.environ.get('DERIVED_SOURCES_DIR')
    # Full name of the target artifact (e.g., "MyApp.app" or "Test.xctest").
    self.full_product_name = os.environ['FULL_PRODUCT_NAME']
    # Target SDK version.
    self.sdk_version = os.environ.get('SDK_VERSION')
    # TEST_HOST for unit tests.
    self.test_host_binary = os.environ.get('TEST_HOST')
    # Whether this target is a test or not.
    self.is_test = os.environ.get('WRAPPER_EXTENSION') == 'xctest'
    # Target platform.
    self.platform_name = os.environ['PLATFORM_NAME']
    # Type of the target artifact.
    self.product_type = os.environ['PRODUCT_TYPE']
    # Path to the parent of the xcodeproj bundle.
    self.project_dir = os.environ['PROJECT_DIR']
    # Path to the xcodeproj bundle.
    self.project_file_path = os.environ['PROJECT_FILE_PATH']
    # Path to the directory containing the WORKSPACE file.
    self.workspace_root = os.path.abspath(os.environ['TULSI_WR'])
    # Set to the name of the generated bundle for bundle-type targets, None for
    # single file targets (like static libraries).
    self.wrapper_name = os.environ.get('WRAPPER_NAME')
    self.wrapper_suffix = os.environ.get('WRAPPER_SUFFIX', '')
    self.xcode_version_major = int(os.environ['XCODE_VERSION_MAJOR'])
    self.xcode_version_minor = int(os.environ['XCODE_VERSION_MINOR'])

    # Path where Xcode expects the artifacts to be written to. This is not the
    # codesigning_path as device vs simulator builds have different signing
    # requirements, so Xcode expects different paths to be signed. This is
    # mostly apparent on XCUITests where simulator builds set the codesigning
    # path to be the .xctest bundle, but for device builds it is actually the
    # UI runner app (since it needs to be codesigned to run on the device.) The
    # FULL_PRODUCT_NAME variable is a stable path on where to put the expected
    # artifacts. For static libraries (objc_library, swift_library),
    # FULL_PRODUCT_NAME corresponds to the .a file name, which coincides with
    # the expected location for a single artifact output.
    # TODO(b/35811023): Check these paths are still valid.
    self.artifact_output_path = os.path.join(
        os.environ['TARGET_BUILD_DIR'],
        os.environ['FULL_PRODUCT_NAME'])

    # Path to where Xcode expects the binary to be placed.
    self.binary_path = os.path.join(
        os.environ['TARGET_BUILD_DIR'], os.environ['EXECUTABLE_PATH'])

    self.is_simulator = self.platform_name.endswith('simulator')
    # Check to see if code signing actions should be skipped or not.
    if self.is_simulator:
      self.codesigning_allowed = False
    else:
      self.codesigning_allowed = os.environ.get('CODE_SIGNING_ALLOWED') == 'YES'

    self.post_processor_binary = os.path.join(self.project_file_path,
                                              '.tulsi',
                                              'Utils',
                                              'post_processor')
    if self.codesigning_allowed:
      platform_prefix = 'iOS'
      if self.platform_name.startswith('macos'):
        platform_prefix = 'macOS'
      entitlements_filename = '%sXCTRunner.entitlements' % platform_prefix
      self.runner_entitlements_template = os.path.join(self.project_file_path,
                                                       '.tulsi',
                                                       'Resources',
                                                       entitlements_filename)

    self.main_group_path = os.getcwd()
    self.bazel_executable = None

  def Run(self, args):
    """Executes a Bazel build based on the environment and given arguments."""
    if self.xcode_action != 'build':
      sys.stderr.write('Xcode action is %s, ignoring.' % self.xcode_action)
      return 0

    if not self.build_without_spotlight:
      spotlight_status = self._CheckSpotlightStatus()
      if spotlight_status:
        return spotlight_status

    parser = _OptionsParser(self.sdk_version,
                            self.platform_name,
                            self.arch,
                            self.main_group_path)
    timer = Timer('Parsing options', 'parsing_options').Start()
    message, exit_code = parser.ParseOptions(args[1:])
    timer.End()
    if exit_code:
      _PrintXcodeError('Option parsing failed: %s' % message)
      return exit_code

    self.verbose = parser.verbose
    self.bazel_bin_path = os.path.abspath(parser.bazel_bin_path)
    self.bazel_executable = parser.bazel_executable

    # Use -fdebug-prefix-map to have debug symbols match Xcode-visible sources.
    #
    # NOTE: Use of -fdebug-prefix-map leads to producing binaries that cannot be
    # reused across multiple machines by a distributed build system, unless the
    # absolute paths to files visible to Xcode match perfectly between all of
    # those machines.
    #
    # For this reason, -fdebug-prefix-map is provided as a default for non-
    # distributed purposes.
    if self.use_debug_prefix_map:
      # Add the debug source maps now that we have bazel_executable.
      source_maps = self._ExtractTargetSourceMaps()

      prefix_maps = []
      for source_map in source_maps:
        prefix_maps.append('--copt=-fdebug-prefix-map=%s=%s' %
                           source_map)

      # Extend our list of build options with maps just prior to building.
      parser.build_options[_OptionsParser.ALL_CONFIGS].extend(prefix_maps)

    self.build_path = os.path.join(self.bazel_bin_path,
                                   os.environ.get('TULSI_BUILD_PATH', ''))

    # Path to the Build Events JSON file uses pid and is removed if the
    # build is successful.
    filename = '%d_%s' % (os.getpid(), BazelBuildBridge.BUILD_EVENTS_FILE)
    self.build_events_file_path = os.path.join(
        self.project_file_path,
        '.tulsi',
        filename)

    (command, retval) = self._BuildBazelCommand(parser)
    if retval:
      return retval

    timer = Timer('Running Bazel', 'running_bazel').Start()
    exit_code, outputs = self._RunBazelAndPatchOutput(command)
    timer.End()
    if exit_code:
      _PrintXcodeError('Bazel build failed.')
      return exit_code

    if not os.path.exists(BAZEL_EXECUTION_ROOT):
      _PrintXcodeError('No Bazel execution root was found at %s. Debugging '
                       'experience will be compromised. Please report a Tulsi '
                       'bug.' % BAZEL_EXECUTION_ROOT)
      return 404

    # This needs to run after `bazel build`, since it depends on the Bazel
    # workspace directory
    exit_code = self._LinkTulsiWorkspace()
    if exit_code:
      return exit_code

    if parser.install_generated_artifacts:
      timer = Timer('Installing artifacts', 'installing_artifacts').Start()
      exit_code = self._InstallArtifact(outputs)
      timer.End()
      if exit_code:
        return exit_code

      timer = Timer('Installing generated headers',
                    'installing_generated_headers').Start()
      exit_code = self._InstallGeneratedHeaders(outputs)
      timer.End()
      if exit_code:
        return exit_code

      if self.generate_dsym:
        timer = Timer('Installing DSYM bundles', 'installing_dsym').Start()
        exit_code, dsym_paths = self._InstallDSYMBundles(
            self.built_products_dir, outputs)
        timer.End()
        if exit_code:
          return exit_code

        for path in dsym_paths:
          # Starting with Xcode 9.x, a plist based solution exists for dSYM
          # bundles that works with Swift as well as (Obj-)C(++).
          if self.xcode_version_major >= 900:
            timer = Timer('Adding remappings as plists to dSYM',
                          'plist_dsym').Start()
            exit_code = self._PlistdSYMPaths(path)
            timer.End()
            if exit_code:
              _PrintXcodeError('Remapping dSYMs process returned %i, please '
                               'report a Tulsi bug and attach a full Xcode '
                               'build log.' % exit_code)
              return exit_code
          else:
            timer = Timer('Patching DSYM source file paths',
                          'patching_dsym').Start()
            exit_code = self._PatchdSYMPaths(path)
            timer.End()
            if exit_code:
              return exit_code

      # Starting with Xcode 7.3, XCTests inject several supporting frameworks
      # into the test host that need to be signed with the same identity as
      # the host itself.
      if (self.is_test and self.xcode_version_minor >= 730 and
          not self.platform_name.startswith('macos') and
          self.codesigning_allowed):
        exit_code = self._ResignTestArtifacts()
        if exit_code:
          return exit_code

    # Starting with Xcode 8, .lldbinit files are honored during Xcode debugging
    # sessions. This allows use of the target.source-map field to remap the
    # debug symbol paths encoded in the binary to the paths expected by Xcode.
    # In cases where a dSYM bundle was produced, the post_processor will have
    # already corrected the paths and use of target.source-map is redundant (and
    # appears to trigger actual problems in Xcode 8.1 betas). The redundant path
    # correction applies to debug prefix maps as well.
    if self.xcode_version_major >= 800:
      timer = Timer('Updating .lldbinit', 'updating_lldbinit').Start()
      clear_source_map = self.generate_dsym or self.use_debug_prefix_map
      exit_code = self._UpdateLLDBInit(clear_source_map)
      timer.End()
      if exit_code:
        _PrintXcodeWarning('Updating .lldbinit action failed with code %d' %
                           exit_code)

    if self.code_coverage_enabled:
      timer = Timer('Patching LLVM covmap', 'patching_llvm_covmap').Start()
      exit_code = self._PatchLLVMCovmapPaths()
      timer.End()
      if exit_code:
        _PrintXcodeWarning('Patch LLVM covmap action failed with code %d' %
                           exit_code)
    return 0

  def _BuildBazelCommand(self, options):
    """Builds up a commandline string suitable for running Bazel."""
    bazel_command = [options.bazel_executable]

    configuration = os.environ['CONFIGURATION']
    # Treat the special testrunner build config as a Debug compile.
    test_runner_config_prefix = '__TulsiTestRunner_'
    if configuration.startswith(test_runner_config_prefix):
      configuration = configuration[len(test_runner_config_prefix):]
    elif os.environ.get('TULSI_TEST_RUNNER_ONLY') == 'YES':
      _PrintXcodeError('Building test targets with configuration "%s" is not '
                       'allowed. Please use the "Test" action or "Build for" > '
                       '"Testing" instead.' % configuration)
      return (None, 1)

    if configuration not in _OptionsParser.KNOWN_CONFIGS:
      _PrintXcodeError('Unknown build configuration "%s"' % configuration)
      return (None, 1)

    bazel_command.extend(options.GetStartupOptions(configuration))
    bazel_command.append('build')
    bazel_command.extend(options.GetBuildOptions(configuration))

    # Do not follow symlinks on __file__ in case this script is linked during
    # development.
    tulsi_package_dir = os.path.abspath(
        os.path.join(os.path.dirname(__file__), '..', 'Bazel'))

    bazel_command.extend([
        '--build_event_json_file=%s' % self.build_events_file_path,
        #  '--bes_outerr_buffer_size=0',  #  Waiting on a new external release.
        '--output_groups=tulsi-outputs,default',
        '--aspects', '@tulsi//tulsi:tulsi_aspects.bzl%tulsi_outputs_aspect',
        '--override_repository=tulsi=%s' % tulsi_package_dir,
        '--tool_tag=tulsi:bazel_build'])

    if self.code_coverage_enabled:
      self._PrintVerbose('Enabling code coverage information.')
      bazel_command.extend([
          '--collect_code_coverage',
          '--experimental_use_llvm_covmap'])

    if self.generate_dsym:
      bazel_command.append('--apple_generate_dsym')

    bazel_command.append(
        '--define=bazel_rules_apple.propagate_embedded_extra_outputs=1')

    bazel_command.extend(options.targets)

    extra_options = bazel_options.BazelOptions(os.environ)
    bazel_command.extend(extra_options.bazel_feature_flags())

    return (bazel_command, 0)

  def _RunBazelAndPatchOutput(self, command):
    """Runs subprocess command, patching output as it's received."""
    self._PrintVerbose('Running "%s", patching output for main group path at '
                       '"%s" with project path at "%s".' %
                       (' '.join(command),
                        self.main_group_path,
                        self.project_dir))
    # Xcode translates anything that looks like ""<path>:<line>:" that is not
    # followed by the word "warning" into an error. Bazel warnings and debug
    # messages do not fit this scheme and must be patched here.
    bazel_warning_line_regex = re.compile(
        r'(?:DEBUG|WARNING): ([^:]+:\d+:(?:\d+:)?)\s+(.+)')

    def PatchBazelWarningStatements(output_line):
      match = bazel_warning_line_regex.match(output_line)
      if match:
        output_line = '%s warning: %s' % (match.group(1), match.group(2))
      return output_line

    patch_xcode_parsable_line = PatchBazelWarningStatements
    if self.main_group_path != self.project_dir:
      # Match (likely) filename:line_number: lines.
      xcode_parsable_line_regex = re.compile(r'([^/][^:]+):\d+:')

      def PatchOutputLine(output_line):
        output_line = PatchBazelWarningStatements(output_line)
        if xcode_parsable_line_regex.match(output_line):
          output_line = '%s/%s' % (self.main_group_path, output_line)
        return output_line
      patch_xcode_parsable_line = PatchOutputLine

    def HandleOutput(output):
      for line in output.splitlines():
        line = patch_xcode_parsable_line(line) + '\n'
        sys.stdout.write(line)
        sys.stdout.flush()

    def WatcherUpdate(watcher):
      """Processes any new events in the given watcher.

      Args:
        watcher: a BazelBuildEventsWatcher object.

      Returns:
        A list of new tulsiout file names seen.
      """
      new_events = watcher.check_for_new_events()
      new_outputs = []
      for build_event in new_events:
        if build_event.stderr:
          HandleOutput(build_event.stderr)
        if build_event.stdout:
          HandleOutput(build_event.stdout)
        if build_event.files:
          outputs = [x for x in build_event.files if x.endswith('.tulsiouts')]
          new_outputs.extend(outputs)
      return new_outputs

    # Make sure the BEP JSON file exists and is empty. We do this to prevent
    # any sort of race between the watcher, bazel, and the old file contents.
    open(self.build_events_file_path, 'w').close()

    # Start Bazel without any extra files open besides /dev/null, which is
    # used to ignore the output.
    with open(os.devnull, 'w') as devnull:
      process = subprocess.Popen(command,
                                 stdout=devnull,
                                 stderr=subprocess.STDOUT)

    # Register atexit function to clean up BEP file.
    atexit.register(_BEPFileExitCleanup, self.build_events_file_path)
    global CLEANUP_BEP_FILE_AT_EXIT
    CLEANUP_BEP_FILE_AT_EXIT = True

    with io.open(self.build_events_file_path, 'r', -1, 'utf-8', 'ignore'
                ) as bep_file:
      watcher = bazel_build_events.BazelBuildEventsWatcher(bep_file,
                                                           _PrintXcodeWarning)
      output_locations = []
      while process.returncode is None:
        output_locations.extend(WatcherUpdate(watcher))
        time.sleep(0.1)
        process.poll()

      output_locations.extend(WatcherUpdate(watcher))

      if process.returncode == 0 and not output_locations:
        CLEANUP_BEP_FILE_AT_EXIT = False
        _PrintXcodeError('Unable to find location of the .tulsiouts file.'
                         'Please report this as a Tulsi bug, including the'
                         'contents of %s.' % self.build_events_file_path)
        return 1, output_locations
      return process.returncode, output_locations

  def _InstallArtifact(self, outputs):
    """Installs Bazel-generated artifacts into the Xcode output directory."""
    xcode_artifact_path = self.artifact_output_path

    if os.path.isdir(xcode_artifact_path):
      try:
        shutil.rmtree(xcode_artifact_path)
      except OSError as e:
        _PrintXcodeError('Failed to remove stale output directory ""%s". '
                         '%s' % (xcode_artifact_path, e))
        return 600
    elif os.path.isfile(xcode_artifact_path):
      try:
        os.remove(xcode_artifact_path)
      except OSError as e:
        _PrintXcodeError('Failed to remove stale output file ""%s". '
                         '%s' % (xcode_artifact_path, e))
        return 600

    try:
      output_data = json.load(open(outputs[0]))
    except (ValueError, IOError) as e:
      _PrintXcodeError('Failed to load output map ""%s". '
                       '%s' % (outputs[0], e))
      return 600

    if 'artifacts' not in output_data:
      _PrintXcodeError(
          'Failed to find an output artifact for target %s in output map %r' %
          (xcode_artifact_path, output_data))
      return 601

    primary_artifact = output_data['artifacts'][0]

    # The PRODUCT_NAME used by the Xcode project is not trustable as it may be
    # modified by the user and, more importantly, may have been modified by
    # Tulsi to disambiguate multiple targets with the same name.
    # To work around this, the product name is determined by dropping any
    # extension from the primary artifact.
    # TODO(abaire): Consider passing this value to the script explicitly.
    self.bazel_product_name = os.path.splitext(
        os.path.basename(primary_artifact))[0]

    if primary_artifact.endswith('.ipa') or primary_artifact.endswith('.zip'):
      bundle_name = output_data.get('bundle_name')
      exit_code = self._UnpackTarget(primary_artifact,
                                     xcode_artifact_path,
                                     bundle_name)
      if exit_code:
        return exit_code

    elif os.path.isfile(primary_artifact):
      exit_code = self._CopyFile(os.path.basename(primary_artifact),
                                 primary_artifact,
                                 xcode_artifact_path)
      if exit_code:
        return exit_code
    else:
      self._CopyBundle(os.path.basename(primary_artifact),
                       primary_artifact,
                       xcode_artifact_path)

    # No return code check as this is not an essential operation.
    self._InstallEmbeddedBundlesIfNecessary(output_data)

    return 0

  def _InstallEmbeddedBundlesIfNecessary(self, output_data):
    """Install embedded bundles next to the current target's output."""

    # In order to find and load symbols for the binary installed on device,
    # Instruments needs to "see" it in Spotlight index somewhere on the local
    # filesystem. This is only needed for on-device instrumentation.
    #
    # Unfortunatelly, it does not seem to be possible to detect when a build is
    # being made for profiling, thus we can't exclude this step for on-device
    # non-profiling builds.

    if self.is_simulator or ('embedded_bundles' not in output_data):
      return

    timer = Timer('Installing embedded bundles',
                  'installing_embedded_bundles').Start()

    for bundle_info in output_data['embedded_bundles']:
      name = bundle_info['bundle_full_name']
      # TODO(b/68936732): See if copying just the binary (not the whole bundle)
      # is enough to make Instruments work.
      source_path = os.path.join(bundle_info['archive_root'], name)
      output_path = os.path.join(self.built_products_dir, name)
      self._InstallBundle(source_path, output_path)

    timer.End()

  def _InstallGeneratedHeaders(self, output_files):
    """Installs Bazel-generated headers into _tulsi-includes directory."""

    # The folder must begin with an underscore as otherwise Bazel will delete
    # it whenever it builds. See tulsi_aspects.bzl for futher explanation.
    tulsi_root = os.path.join(BAZEL_EXECUTION_ROOT, '_tulsi-includes')

    if os.path.exists(tulsi_root):
      shutil.rmtree(tulsi_root)
    else:
      os.mkdir(tulsi_root)

    for f in output_files:
      data = json.load(open(f))
      if 'generated_sources' not in data:
        continue

      for gs in data['generated_sources']:
        real_path, link_path = gs
        src = os.path.join(BAZEL_EXECUTION_ROOT, real_path)

        # Bazel outputs are not guaranteed to be created if nothing references
        # them. This check skips the processing if an output was declared
        # but not created.
        if not os.path.exists(src):
          continue

        # The /x/x/ part is here to match the number of directory components
        # between tulsi root and bazel root. See tulsi_aspects.bzl for futher
        # explanation.
        dst = os.path.join(tulsi_root, 'x/x/', link_path)
        self._PrintVerbose('Symlinking %s to %s' % (src, dst), 2)

        dst_dir = os.path.split(dst)[0]
        if not os.path.exists(dst_dir):
          os.makedirs(dst_dir)

        # It's important to use lexists() here in case dst is a broken symlink
        # (in which case exists() would return False). For example, older
        # versions of this script did not check if src existed and could create
        # a symlink to an invalid path.
        if os.path.lexists(dst):
          os.unlink(dst)

        os.symlink(src, dst)

  def _InstallBundle(self, source_path, output_path):
    """Copies the bundle at source_path to output_path."""
    if not os.path.isdir(source_path):
      return 0, None

    if os.path.isdir(output_path):
      try:
        shutil.rmtree(output_path)
      except OSError as e:
        _PrintXcodeError('Failed to remove stale bundle ""%s". '
                         '%s' % (output_path, e))
        return 700, None

    exit_code = self._CopyBundle(os.path.basename(source_path),
                                 source_path,
                                 output_path)
    return exit_code, output_path

  def _CopyBundle(self, source_path, full_source_path, output_path):
    """Copies the given bundle to the given expected output path."""
    self._PrintVerbose('Copying %s to %s' % (source_path, output_path))
    try:
      shutil.copytree(full_source_path, output_path)
    except OSError as e:
      _PrintXcodeError('Copy failed. %s' % e)
      return 650
    return 0

  def _CopyFile(self, source_path, full_source_path, output_path):
    """Copies the given file to the given expected output path."""
    self._PrintVerbose('Copying %s to %s' % (source_path, output_path))
    output_path_dir = os.path.dirname(output_path)
    if not os.path.exists(output_path_dir):
      try:
        os.makedirs(output_path_dir)
      except OSError as e:
        _PrintXcodeError('Failed to create output directory ""%s". '
                         '%s' % (output_path_dir, e))
        return 650
    try:
      shutil.copy(full_source_path, output_path)
    except OSError as e:
      _PrintXcodeError('Copy failed. %s' % e)
      return 650
    return 0

  def _UnpackTarget(self, bundle_path, output_path, bundle_name):
    """Unpacks generated bundle into the given expected output path."""
    self._PrintVerbose('Unpacking %s to %s' % (bundle_path, output_path))

    if not os.path.isfile(bundle_path):
      _PrintXcodeError('Generated bundle not found at "%s"' % bundle_path)
      return 670

    # We need to handle IPAs (from the native rules) differently from ZIPs
    # (from the Skylark rules) because they output slightly different directory
    # structures.
    is_ipa = bundle_path.endswith('.ipa')

    expected_bundle_name = bundle_name + self.wrapper_suffix

    # The directory structure within the IPA is then determined based on Bazel's
    # package and/or product type.
    if is_ipa:
      expected_bundle_subpath = os.path.join('Payload', expected_bundle_name)
    else:
      # If the artifact is a ZIP, assume that the bundle is the top-level
      # directory (this is the way in which Skylark rules package artifacts
      # that are not standalone IPAs).
      expected_bundle_subpath = expected_bundle_name

    with zipfile.ZipFile(bundle_path, 'r') as zf:
      for item in zf.infolist():
        filename = item.filename

        # Support directories do not seem to be needed by the debugger and are
        # skipped.
        basedir = filename.split(os.sep)[0]
        if basedir.endswith('Support') or basedir.endswith('Support2'):
          continue

        if len(filename) < len(expected_bundle_subpath):
          continue

        attributes = (item.external_attr >> 16) & 0777
        self._PrintVerbose('Extracting %s (%o)' % (filename, attributes),
                           level=1)

        if not filename.startswith(expected_bundle_subpath):
          # TODO(abaire): Make an error if Bazel modifies this behavior.
          _PrintXcodeWarning('Mismatched extraction path. Bundle content '
                             'at "%s" expected to have subpath of "%s"' %
                             (filename, expected_bundle_subpath))

        dir_components = self._SplitPathComponents(filename)

        # Get the file's path, ignoring the payload components if the archive
        # is an IPA.
        if is_ipa:
          subpath = os.path.join(*dir_components[2:])
        else:
          subpath = os.path.join(*dir_components[1:])
        target_path = os.path.join(output_path, subpath)

        # Ensure the target directory exists.
        try:
          target_dir = os.path.dirname(target_path)
          if not os.path.isdir(target_dir):
            os.makedirs(target_dir)
        except OSError as e:
          _PrintXcodeError(
              'Failed to create target path "%s" during extraction. %s' % (
                  target_path, e))
          return 671

        # If the archive item looks like a file, extract it.
        if not filename.endswith(os.sep):
          with zf.open(item) as src, file(target_path, 'wb') as dst:
            shutil.copyfileobj(src, dst)

        # Patch up the extracted file's attributes to match the zip content.
        if attributes:
          os.chmod(target_path, attributes)

    return 0

  def _InstallDSYMBundles(self, output_dir, aspect_outputs):
    """Copies any generated dSYM bundles to the given directory."""
    target_dsym = os.environ.get('DWARF_DSYM_FILE_NAME')
    if not target_dsym:  # If Xcode is not expecting a dSYM output, skip.
      return 0, None

    dsym_to_process = set([(self.build_path, target_dsym)])

    # Collect additional dSYM bundles generated by the dependencies of this
    # build such as extensions or frameworks.
    child_dsyms = set()
    for path in aspect_outputs:
      try:
        data = json.load(open(path))
      except (ValueError, IOError) as e:
        _PrintXcodeWarning('Failed to load output map ""%s".'
                           '%s' % (path, e))
        break

      for bundle_info in data.get('embedded_bundles', []):
        if not bundle_info['has_dsym']:
          continue
        # Uses the parent of archive_root to find dSYM bundles associated with
        # app/extension/df bundles. Currently hinges on implementation of the
        # build rules.
        dsym_path = os.path.dirname(bundle_info['archive_root'])
        dsym_filename = '%s.dSYM' % bundle_info['bundle_full_name']
        child_dsyms.add((dsym_path, dsym_filename))
    dsym_to_process.update(child_dsyms)

    dsyms_found = []
    for dsym_path, dsym_filename in dsym_to_process:
      input_dsym_full_path = os.path.join(dsym_path, dsym_filename)
      output_full_path = os.path.join(output_dir, dsym_filename)
      exit_code, path = self._InstallBundle(input_dsym_full_path,
                                            output_full_path)
      if exit_code:
        _PrintXcodeWarning('Failed to install dSYM "%s" (%s)'
                           % (target_dsym, exit_code))
      elif path is None:
        _PrintXcodeWarning('Could not find a dSYM bundle named "%s"'
                           % target_dsym)
      else:
        dsyms_found.append(path)

    return 0, dsyms_found

  def _ResignBundle(self, bundle_path, signing_identity, entitlements=None):
    """Re-signs the bundle with the given signing identity and entitlements."""
    if not self.codesigning_allowed:
      return 0

    timer = Timer('\tSigning ' + bundle_path, 'signing_bundle').Start()
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

    returncode, output = self._RunSubprocess(command)
    timer.End()
    if returncode:
      _PrintXcodeError('Re-sign command %r failed. %s' % (command, output))
      return 800 + returncode
    return 0

  def _ResignTestArtifacts(self):
    """Resign test related artifacts that Xcode injected into the outputs."""
    if not self.is_test:
      return 0
    # Extract the signing identity from the bundle at the expected output path
    # since that's where the signed bundle from bazel was placed.
    signing_identity = self._ExtractSigningIdentity(self.artifact_output_path)
    if not signing_identity:
      return 800

    exit_code = 0
    timer = Timer('Re-signing injected test host artifacts',
                  'resigning_test_host').Start()

    if self.test_host_binary:
      # For Unit tests, we need to resign the frameworks that Xcode injected
      # into the test host bundle.
      test_host_bundle = os.path.dirname(self.test_host_binary)
      exit_code = self._ResignXcodeTestFrameworks(
          test_host_bundle, signing_identity)
    else:
      # For UI tests, we need to resign the UI test runner app and the
      # frameworks that Xcode injected into the runner app. The UI Runner app
      # also needs to be signed with entitlements.
      exit_code = self._ResignXcodeTestFrameworks(
          self.codesigning_folder_path, signing_identity)
      if exit_code == 0:
        entitlements_path = self._InstantiateUIRunnerEntitlements()
        if entitlements_path:
          exit_code = self._ResignBundle(
              self.codesigning_folder_path,
              signing_identity,
              entitlements_path)
        else:
          _PrintXcodeError('Could not instantiate UI runner entitlements.')
          exit_code = 800

    timer.End()
    return exit_code

  def _ResignXcodeTestFrameworks(self, bundle, signing_identity):
    """Re-signs the support frameworks injected by Xcode in the given bundle."""
    if not self.codesigning_allowed:
      return 0

    for framework in XCODE_INJECTED_FRAMEWORKS:
      framework_path = os.path.join(
          bundle, 'Frameworks', '%s.framework' % framework)
      if os.path.isdir(framework_path):
        exit_code = self._ResignBundle(framework_path, signing_identity)
        if exit_code != 0:
          return exit_code
    return 0

  def _InstantiateUIRunnerEntitlements(self):
    """Substitute team and bundle identifiers into UI runner entitlements.

    This method throws an IOError exception if the template wasn't found in
    its expected location, or an OSError if the expected output folder could
    not be created.

    Returns:
      The path to where the entitlements file was generated.
    """
    if not self.codesigning_allowed:
      return None
    if not os.path.exists(self.derived_sources_folder_path):
      os.makedirs(self.derived_sources_folder_path)

    output_file = os.path.join(
        self.derived_sources_folder_path,
        self.bazel_product_name + '_UIRunner.entitlements')
    if os.path.exists(output_file):
      os.remove(output_file)

    with open(self.runner_entitlements_template, 'r') as template:
      contents = template.read()
      contents = contents.replace(
          '$(TeamIdentifier)',
          self._ExtractSigningTeamIdentifier(self.artifact_output_path))
      contents = contents.replace(
          '$(BundleIdentifier)',
          self._ExtractSigningBundleIdentifier(self.artifact_output_path))
      with open(output_file, 'w') as output:
        output.write(contents)
    return output_file

  def _ExtractSigningIdentity(self, signed_bundle):
    """Returns the identity used to sign the given bundle path."""
    return self._ExtractSigningAttribute(signed_bundle, 'Authority')

  def _ExtractSigningTeamIdentifier(self, signed_bundle):
    """Returns the team identifier used to sign the given bundle path."""
    return self._ExtractSigningAttribute(signed_bundle, 'TeamIdentifier')

  def _ExtractSigningBundleIdentifier(self, signed_bundle):
    """Returns the bundle identifier used to sign the given bundle path."""
    return self._ExtractSigningAttribute(signed_bundle, 'Identifier')

  def _ExtractSigningAttribute(self, signed_bundle, attribute):
    """Returns the attribute used to sign the given bundle path."""
    if not self.codesigning_allowed:
      return '<CODE_SIGNING_ALLOWED=NO>'

    cached = self.codesign_attributes.get(signed_bundle)
    if cached:
      return cached.Get(attribute)

    timer = Timer('\tExtracting signature for ' + signed_bundle,
                  'extracting_signature').Start()
    output = subprocess.check_output(['xcrun',
                                      'codesign',
                                      '-dvv',
                                      signed_bundle],
                                     stderr=subprocess.STDOUT)
    timer.End()

    bundle_attributes = CodesignBundleAttributes(output)
    self.codesign_attributes[signed_bundle] = bundle_attributes
    return bundle_attributes.Get(attribute)

  _TULSI_LLDBINIT_BLOCK_START = '# <TULSI> LLDB bridge [:\n'
  _TULSI_LLDBINIT_BLOCK_END = '# ]: <TULSI> LLDB bridge\n'
  _TULSI_LLDBINIT_FILE = os.path.expanduser('~/.lldbinit-tulsiproj')
  _TULSI_LLDBINIT_EPILOGUE_FILE = (
      os.path.expanduser('~/.lldbinit-tulsiproj-epilogue'))

  def _ExtractLLDBInitContent(self, lldbinit_path):
    """Extracts the non-Tulsi content of the given lldbinit file."""
    if not os.path.isfile(lldbinit_path):
      return []
    content = []
    with open(lldbinit_path) as f:
      ignoring = False
      for line in f:
        if ignoring:
          if line == self._TULSI_LLDBINIT_BLOCK_END:
            ignoring = False
          continue
        if line == self._TULSI_LLDBINIT_BLOCK_START:
          ignoring = True
          continue
        content.append(line)
    return content

  def _LinkTulsiLLDBInit(self):
    """Adds a reference to ~/.lldbinit-tulsi to the primary lldbinit file.

    Xcode 8+ caches the contents of ~/.lldbinit-Xcode on startup. To get around
    this, an external reference to ~/.lldbinit-tulsi is added, causing LLDB
    itself to load the possibly modified contents on each session.
    """

    lldbinit_path = os.path.expanduser('~/.lldbinit-Xcode')
    if not os.path.isfile(lldbinit_path):
      lldbinit_path = os.path.expanduser('~/.lldbinit')

    content = self._ExtractLLDBInitContent(lldbinit_path)
    out = StringIO.StringIO()
    for line in content:
      out.write(line)

    out.write(self._TULSI_LLDBINIT_BLOCK_START)
    out.write('# This was autogenerated by Tulsi in order to influence LLDB '
              'source-maps at build time.\n')
    out.write('command source %s\n' % self._TULSI_LLDBINIT_FILE)
    out.write(self._TULSI_LLDBINIT_BLOCK_END)

    with open(lldbinit_path, 'w') as outfile:
      out.seek(0)
      # Negative length to make copyfileobj write the whole file at once.
      shutil.copyfileobj(out, outfile, -1)

  def _LinkTulsiLLDBInitEpilogue(self, outfile):
    """Adds a reference to ~/.lldbinit-tulsi-epilogue if it exists.

    This file can be used to append more LLDB commands right after
    .lldbinit-tulsi is sourced.

    Useful for extending or resetting LLDB settings that Tulsi may have set
    automatically

    Args:
      outfile: a file-type object.

    Returns:
      None
    """
    if os.path.isfile(self._TULSI_LLDBINIT_EPILOGUE_FILE):
      outfile.write('command source %s\n' % self._TULSI_LLDBINIT_EPILOGUE_FILE)

  def _UpdateLLDBInit(self, clear_source_map=False):
    """Updates ~/.lldbinit-tulsi to enable debugging of Bazel binaries."""

    # Apple Watch app binaries do not contain any sources.
    if self.product_type == 'com.apple.product-type.application.watchapp2':
      return 0

    self._LinkTulsiLLDBInit()

    with open(self._TULSI_LLDBINIT_FILE, 'w') as out:
      out.write('# This file is autogenerated by Tulsi and should not be '
                'edited.\n')

      if clear_source_map:
        out.write('settings clear target.source-map\n')
        self._LinkTulsiLLDBInitEpilogue(out)
        return 0

      timer = Timer(
          '\tExtracting source paths for ' + self.full_product_name,
          'extracting_source_paths').Start()

      execroot = self._ExtractExecroot()
      timer.End()

      if not execroot:
        _PrintXcodeWarning('Could not find the execroot from %r. File-based '
                           'breakpoints may not work. Please report as a bug.' %
                           self.full_product_name)
        return 0

      source_map = (self._NormalizePath(execroot),
                    self._NormalizePath(self.workspace_root))

      out.write('# This maps Bazel\'s execution root to that used by %r.\n' %
                os.path.basename(self.project_file_path))

      out.write('settings set target.source-map "%s" "%s"\n' % source_map)
      self._LinkTulsiLLDBInitEpilogue(out)

    return 0

  def _PatchLLVMCovmapPaths(self):
    """Invokes post_processor to fix source paths in LLVM coverage maps."""
    if not os.path.isfile(self.binary_path):
      return 0

    self._PrintVerbose('Patching %r -> %r' % (BAZEL_EXECUTION_ROOT,
                                              self.workspace_root), 1)
    args = [
        self.post_processor_binary,
        '-c',
    ]
    if self.verbose > 1:
      args.append('-v')
    args.extend([
        self.binary_path,
        BAZEL_EXECUTION_ROOT,
        self.workspace_root
    ])
    returncode, output = self._RunSubprocess(args)
    if returncode:
      _PrintXcodeWarning('Coverage map patching failed on binary %r (%d). Code '
                         'coverage will probably fail.' %
                         (self.binary_path, returncode))
      _PrintXcodeWarning('Output: %s' % output or '<no output>')
      return 0

    return 0

  def _DWARFdSYMBinaries(self, dsym_bundle_path):
    """Returns an array of abs paths to DWARF binaries in the dSYM bundle.

    Args:
      dsym_bundle_path: absolute path to the dSYM bundle.

    Returns:
      str[]: a list of strings representing the absolute paths to each binary
             found within the dSYM bundle.
    """
    dwarf_dir = os.path.join(dsym_bundle_path,
                             'Contents',
                             'Resources',
                             'DWARF')

    dsym_binaries = []

    for f in os.listdir(dwarf_dir):
      # Ignore hidden files, such as .DS_Store files.
      if not f.startswith('.'):
        # Append full path info.
        dsym_binary = os.path.join(dwarf_dir, f)
        dsym_binaries.append(dsym_binary)

    return dsym_binaries

  def _UUIDsForBinaryAtPath(self, source_binary_path):
    """Returns exit code of dwarfdump along with every UUID found for a binary.

    Args:
      source_binary_path: absolute path to the binary file.

    Returns:
      (Int, str[]): a tuple containing the return code of dwarfdump as its
                    first element, and a list of strings representing each UUID
                    found for each given binary slice found within the binary,
                    if no error has occcured.
    """

    returncode, output = self._RunSubprocess([
        'xcrun',
        'dwarfdump',
        '--uuid',
        source_binary_path
    ])
    if returncode:
      _PrintXcodeWarning('dwarfdump returned %d while finding the UUID for %s'
                         % (returncode, source_binary_path))
      return (returncode, [])

    # All UUIDs for binary slices will be returned as the second from left,
    # from output; "UUID: D4DE5AA2-79EE-36FE-980C-755AED318308 (x86_64)
    # /Applications/Calendar.app/Contents/MacOS/Calendar"

    uuids_found = []
    for dwarfdump_output in output.split('\n'):
      if not dwarfdump_output:
        continue
      found_output = re.match(r'^(?:UUID: )([^ ]+)', dwarfdump_output)
      if not found_output:
        continue
      found_uuid = found_output.group(1)
      if found_uuid:
        uuids_found.append(found_uuid)

    return (0, uuids_found)

  def _CreateUUIDPlist(self, dsym_bundle_path, uuid, source_maps):
    """Creates a UUID.plist in a dSYM bundle to redirect sources.

    Args:
      dsym_bundle_path: absolute path to the dSYM bundle.
      uuid: string representing the UUID of the binary slice with paths to
            remap in the dSYM bundle.
      source_maps: a set of tuples representing all absolute paths to source
                   files compiled by Bazel as strings ($0) associated with the
                   paths to Xcode-visible sources used for the purposes of
                   Tulsi debugging as strings ($1).

    Returns:
      Int: the return code of plutil if a non-zero return code was found, or
           "405", representing a failed copy action when creating the plist.
    """

    # Create a UUID plist at (dsym_bundle_path)/Contents/Resources/ from
    # the plist that was already generated within the dSYM bundle.
    remap_plist = os.path.join(dsym_bundle_path,
                               'Contents',
                               'Resources',
                               '%s.plist' % uuid)
    main_plist = os.path.join(dsym_bundle_path,
                              'Contents',
                              'Info.plist')
    try:
      shutil.copyfile(main_plist, remap_plist)
    except IOError as e:
      _PrintXcodeError('Failed to copy %s to %s, received error %s' %
                       (main_plist, remap_plist, e))
      return 405

    # Via plutil, add the mappings from  _ExtractTargetSourceMaps(). Make
    # sure that we also set DBGVersion to 2 via plutil.
    returncode, output = self._RunSubprocess([
        'xcrun',
        'plutil',
        '-replace',
        'DBGVersion',
        '-string',
        '2',
        remap_plist
    ])
    if returncode:
      _PrintXcodeWarning('plutil returned %d while adding DBGVersion to %s: %s'
                         % (returncode, remap_plist, output))
      return returncode

    json_path_remappings = ''

    for source_map in source_maps:
      json_path_remappings += '"%s" : "%s", ' % source_map

    # Add each mapping as a DBGSourcePathRemapping to the UUID plist here.
    returncode, output = self._RunSubprocess([
        'xcrun',
        'plutil',
        '-replace',
        'DBGSourcePathRemapping',
        '-json',
        '{ ' + json_path_remappings + ' }',
        remap_plist
    ])
    if returncode:
      _PrintXcodeWarning('plutil returned %d while adding '
                         'DBGSourcePathRemapping to %s: %s'
                         % (returncode, remap_plist, output))
      return returncode

    return 0

  def _PlistdSYMPaths(self, dsym_bundle_path):
    """Adds Plists to a given dSYM bundle to redirect DWARF data."""

    # Retrieve all paths that we are expected to remap.
    source_maps = self._ExtractTargetSourceMaps()

    if not source_maps:
      _PrintXcodeWarning('Extracted 0 source paths. File-based breakpoints '
                         'may not work. Please report as a bug.')
      return 410

    # Find the binaries within the dSYM bundle. UUIDs will match that of the
    # binary it was based on.
    dsym_binaries = self._DWARFdSYMBinaries(dsym_bundle_path)

    if not dsym_binaries:
      _PrintXcodeWarning('Could not find the binaries that the dSYM %s was '
                         'based on to determine DWARF binary slices to patch. '
                         'Debugging will probably fail.' % (dsym_bundle_path))
      return 404

    # Find the binary slice UUIDs with dwarfdump from each binary.
    for source_binary_path in dsym_binaries:

      returncode, uuids_found = self._UUIDsForBinaryAtPath(source_binary_path)
      if returncode:
        return returncode

      # Create a plist per UUID, each indicating a binary slice to remap paths.
      for uuid in uuids_found:
        returncode = self._CreateUUIDPlist(dsym_bundle_path, uuid, source_maps)
        if returncode:
          return returncode

    # Update spotlight index with this updated dSYM bundle in case the binary's
    # UUID changed.
    self._RunSubprocess(['mdimport', dsym_bundle_path])

    return 0

  def _PatchdSYMPaths(self, dsym_bundle_path):
    """Invokes post_processor to fix source paths in dSYM DWARF data."""
    dwarf_subpath = os.path.join(dsym_bundle_path,
                                 'Contents',
                                 'Resources',
                                 'DWARF')
    binaries = [os.path.join(dwarf_subpath, b)
                for b in os.listdir(dwarf_subpath)]
    for binary_path in binaries:
      os.chmod(binary_path, 0755)

    args = [self.post_processor_binary, '-d']
    if self.verbose > 1:
      args.append('-v')
    args.extend(binaries)
    args.extend([BAZEL_EXECUTION_ROOT, self.workspace_root])

    self._PrintVerbose('Patching %r -> %r' % (BAZEL_EXECUTION_ROOT,
                                              self.workspace_root), 1)
    returncode, output = self._RunSubprocess(args)
    if returncode:
      _PrintXcodeWarning('DWARF path patching failed on dSYM %r (%d). '
                         'Breakpoints and other debugging actions will '
                         'probably fail.' % (dsym_bundle_path, returncode))
      _PrintXcodeWarning('Output: %s' % output or '<no output>')
      return 0

    return 0

  def _ExtractBazelInfoExecrootPaths(self):
    """Extracts the path to the execution root found in this WORKSPACE.

    Returns:
      None: if an error occurred.
      str: a string representing the absolute path to the execution root found
           for the current Bazel WORKSPACE.
    """
    if not self.bazel_executable:
      _PrintXcodeWarning('Attempted to find the execution root, but the '
                         'path to the Bazel executable was not provided.')
      return None

    timer = Timer('Finding Bazel execution root', 'bazel_execroot').Start()
    returncode, output = self._RunSubprocess([
        self.bazel_executable,
        'info',
        'execution_root',
        '--noshow_loading_progress',
        '--noshow_progress',
    ])
    timer.End()

    if returncode:
      _PrintXcodeWarning('%s returned %d while finding the execution root'
                         % (self.bazel_executable, returncode))
      return None

    for line in output.splitlines():
      # Filter out output that does not contain the /execroot path.
      if '/execroot' not in line:
        continue
      # Return the path from the first /execroot found.
      return line
    _PrintXcodeWarning('%s did not return a recognized /execroot path.'
                       % self.bazel_executable)
    return None

  def _NormalizePath(self, path):
    """Returns paths with a common form, normalized with a trailing slash.

    Args:
      path: a file system path given in the form of a string.

    Returns:
      str: a normalized string with a trailing slash, based on |path|.
    """
    return os.path.normpath(path) + os.sep

  def _ExtractTargetSourceMaps(self):
    """Extracts all source paths as tuples associated with the WORKSPACE path.

    Returns:
      set(): if an error occurred.
      set(str, str): a set of tuples representing all absolute paths to source
                     files compiled by Bazel as strings ($0) associated with
                     the paths to Xcode-visible sources used for the purposes
                     of Tulsi debugging as strings ($1).
    """
    source_maps = set()

    # All paths route to the "workspace root" for sources visible from Xcode.
    sm_wsroot = self._NormalizePath(self.workspace_root)

    # If the user has specified any additional mappings, add them first.
    if self.extra_remap_path:
      source_maps.add((self._NormalizePath(self.extra_remap_path), sm_wsroot))

    # Remap '.' to the workspace root if specified. Simulates a relative path
    # for Xcode-driven LLDB sessions.
    if self.remap_dotted_paths:
      source_maps.add(('./', sm_wsroot))

    # Add a redirection for the Bazel execution root, the path where sources
    # are referenced by Bazel.
    execroot = self._ExtractExecroot()
    if execroot:
      source_maps.add((self._NormalizePath(execroot), sm_wsroot))

    return source_maps

  def _ExtractExecroot(self):
    """Finds the execution root from BAZEL_EXECUTION_ROOT or bazel info.

    Returns:
      None: if an error occurred.
      str: the "execution root", the path to the "root" of all source files
           compiled by Bazel as a string.
    """
    # If we have a cached execution root, check that it exists.
    if os.path.exists(BAZEL_EXECUTION_ROOT):
      # If so, use it.
      execroot = BAZEL_EXECUTION_ROOT
    else:
      # Query Bazel directly for the execution root.
      execroot = self._ExtractBazelInfoExecrootPaths()
    return execroot

  def _LinkTulsiWorkspace(self):
    """Links the Bazel Workspace to the Tulsi Workspace (`tulsi-workspace`)."""
    tulsi_workspace = self.workspace_root + '/tulsi-workspace'
    if os.path.islink(tulsi_workspace):
      os.unlink(tulsi_workspace)

    os.symlink(BAZEL_EXECUTION_ROOT, tulsi_workspace)
    if not os.path.exists(tulsi_workspace):
      _PrintXcodeError(
          'Linking Tulsi Workspace to %s failed.' % tulsi_workspace)
      return -1

  def _PrintSpotlightDisabledMessaging(self):
    """Prints errors to the console indicating that Spotlight is required."""
    spotlight_required_msg = ('Spotlight is needed to find debugging info '
                              'for Bazel-built sources.')
    spotlight_enable_msg = ('Please enable Spotlight with `sudo mdutil -i on /`'
                            ' in the Terminal.')
    spotlight_check_disable_msg = ('If you need to disable this check and '
                                   'proceed with a compromised debugging '
                                   'experience set %s to YES.' %
                                   BazelBuildBridge.SPOTLIGHT_CHECK_ENVVAR)
    _PrintXcodeError(spotlight_required_msg)
    _PrintXcodeError(spotlight_enable_msg)
    _PrintXcodeWarning(spotlight_check_disable_msg)

  def _CheckSpotlightStatus(self):
    """Check if Spotlight has been enabled on root, error if it hasn't been.

    Returns:
      Int: 0 if Spotlight reports that indexing is enabled on the root dir.
           -1 if Spotlight indexing was not found to be enabled on the root
           dir. The return code if the mdutil query on the root dir failed
           to execute properly.
    """
    sys.stdout.write('Checking Spotlight status on the startup disk.\n')
    sys.stdout.flush()
    returncode, output = self._RunSubprocess([
        'mdutil',
        '-s',
        '/'
    ])
    output_single_line = output.replace('\n', '').replace('\t', ' ')
    if returncode != 0:
      _PrintXcodeError('Could not verify status of Spotlight on the startup '
                       'disk.')
      _PrintXcodeError('mdutil exited with %s: "%s".' % (returncode,
                                                         output_single_line))
      self._PrintSpotlightDisabledMessaging()
      return returncode
    # Attempt to match on "Indexing enabled." and any possible variants.
    if 'enabled' not in output:
      _PrintXcodeError('Spotlight has been turned off on the startup disk.')
      _PrintXcodeError('Status returned from mdutil was "%s".' %
                       output_single_line)
      self._PrintSpotlightDisabledMessaging()
      return -1
    return 0

  @staticmethod
  def _SplitPathComponents(path):
    """Splits the given path into an array of all of its components."""
    components = path.split(os.sep)
    # Patch up the first component if path started with an os.sep
    if not components[0]:
      components[0] = os.sep
    return components

  def _RunSubprocess(self, cmd):
    """Runs the given command as a subprocess, returning (exit_code, output)."""
    self._PrintVerbose('%r' % cmd, 1)
    process = subprocess.Popen(cmd,
                               stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT)
    output, _ = process.communicate()
    return (process.returncode, output)

  def _PrintVerbose(self, msg, level=0):
    if self.verbose > level:
      sys.stdout.write(msg + '\n')
      sys.stdout.flush()


if __name__ == '__main__':
  _LockFileAcquire('/tmp/tulsi_bazel_build.lock')
  _timer = Timer('Everything', 'complete_build').Start()
  signal.signal(signal.SIGINT, _InterruptHandler)
  _exit_code = BazelBuildBridge().Run(sys.argv)
  _timer.End()
  sys.exit(_exit_code)
