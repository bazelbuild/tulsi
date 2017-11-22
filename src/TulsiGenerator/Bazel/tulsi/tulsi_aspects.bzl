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

"""Skylark rules supporting Tulsi.

This file provides Bazel aspects used to obtain information about a given
project and pass it back to Tulsi.
"""

load(':tulsi_aspects_paths.bzl', 'TULSI_CURRENT_XCODE_CONFIG')

# List of all of the attributes that can link from a Tulsi-supported rule to a
# Tulsi-supported dependency of that rule.
# For instance, an ios_application's "binary" attribute might link to an
# objc_binary rule which in turn might have objc_library's in its "deps"
# attribute.
_TULSI_COMPILE_DEPS = [
    'binary',
    'bundles',
    'deps',
    'extension',
    'extensions',
    'frameworks',
    'settings_bundle',
    'non_propagated_deps',
    'test_bundle',
    'test_host',
    'watch_application',
    'xctest_app',
]

# List of all attributes whose contents should resolve to "support" files; files
# that are used by Bazel to build but do not need special handling in the
# generated Xcode project. For example, Info.plist and entitlements files.
_SUPPORTING_FILE_ATTRIBUTES = [
    'app_icons',
    'entitlements',
    'infoplist',
    'infoplists',
    'resources',
    'strings',
    'structured_resources',
    'storyboards',
    'xibs',
]

# List of rules with implicit <label>.ipa IPA outputs.
# TODO(b/33050780): This is only used for the native rules and will be removed
# in the future
_IPA_GENERATING_RULES = [
    'ios_application',
    'ios_extension',
    'ios_test',
    'objc_binary',
    'tvos_application',
]

# List of rules that generate MergedInfo.plist files as part of the build.
_MERGEDINFOPLIST_GENERATING_RULES = [
    'ios_application',
    'tvos_application',
]

# List of rules whose outputs should be treated as generated sources.
_SOURCE_GENERATING_RULES = [
    'j2objc_library',
]

# List of rules whose outputs should be treated as generated sources that do not
# use ARC.
_NON_ARC_SOURCE_GENERATING_RULES = [
    'objc_proto_library',
]

def _dict_omitting_none(**kwargs):
  """Creates a dict from the args, dropping keys with None or [] values."""
  return {name: kwargs[name]
          for name in kwargs
          # Skylark doesn't support "is"; comparison is explicit for correctness.
          # pylint: disable=g-equals-none,g-explicit-bool-comparison
          if kwargs[name] != None and kwargs[name] != []
         }


def _struct_omitting_none(**kwargs):
  """Creates a struct from the args, dropping keys with None or [] values."""
  return struct(**_dict_omitting_none(**kwargs))


def _convert_outpath_to_symlink_path(path, use_tulsi_symlink=False):
  """Converts full output paths to their tulsi-symlink equivalents.

  Bazel output paths are unstable, prone to change with architecture,
  platform or flag changes. Therefore we can't rely on them to supply to Xcode.
  Instead, we will root all outputs under a stable tulsi dir,
  and the bazel_build.py script will link the artifacts into the correct
  location under it.

  Tulsi root is located at WORKSPACE/bazel-exec-root-link/tulsi-includes/x/x/.
  The two "x" directories are stubs to match the number of path components, so
  that relative paths work with the new location. Some Bazel outputs, like
  module maps, use relative paths to reference other files in the build.

  In short, when `use_tulsi_symlink` is `True`, this method will transform
    bazel-out/ios-x86_64-min7.0/genfiles/foo
  to
    tulsi-includes/x/x/foo

  When `use_tulsi_symlink` is `False`, this method will transform
    bazel-outbin/ios-x86_64-min7.0/genfiles/foo
  to
    bazel-genfiles/foo

  This flag is currently enabled for generated headers, sources, Swift modules,
  and module maps. Disabled for everything else to keep backwards compatibility.
  TODO(tulsi-team): Phase out the older bazel symlink completely and remove
  the flag.

  Args:
    path: path to transform
    use_tulsi_symlink: whether to use the new tulsi symlink, or the older bazel
      format.

  Returns:
    A string that is the original path modified according to the rules.
  """
  # The path will be of the form:
  # if use_tulsi_symlink:
  #   tulsi-includes/x/x/symlink[/.*]
  # otherwise:
  #   bazel-[whatever]/[platform-config]/symlink[/.*]
  first_dash = path.find('-')
  components = path.split('/')
  if (len(components) > 2 and
      first_dash >= 0 and
      first_dash < len(components[0])):
    if use_tulsi_symlink:
      return 'tulsi-includes/x/x/' + '/'.join(components[3:])
    else:
      return path[:first_dash + 1] + '/'.join(components[2:])
  return path

def _is_bazel_external_file(f):
  """Returns True if the given file is a Bazel external file."""
  return f.path.startswith('external/')


def _file_metadata(f, use_tulsi_symlink=False):
  """Returns metadata about a given File."""
  if not f:
    return None

  # Special case handling for Bazel external files which have a path that starts
  # with 'external/' but their short_path and root.path have no mention of being
  # external.
  out_path = f.path if _is_bazel_external_file(f) else f.short_path
  if not f.is_source:
    root_path = f.root.path
    symlink_path = _convert_outpath_to_symlink_path(
        root_path,
        use_tulsi_symlink=use_tulsi_symlink)
    if symlink_path == root_path:
      # The root path should always be bazel-out/... and thus is expected to be
      # updated.
      print('Unexpected root path "%s". Please report.' % root_path)
      root_execution_path_fragment = root_path
    else:
      root_execution_path_fragment = symlink_path
  else:
    root_execution_path_fragment = None

  # TODO(abaire): Remove once Skylark File objects can reference directories.
  # At the moment (Oct. 2016), Bazel disallows most files without extensions.
  # As a temporary hack, Tulsi treats File instances pointing at extension-less
  # paths as directories. This is extremely fragile and must be replaced with
  # logic properly homed in Bazel.
  is_dir = (f.basename.find('.') == -1)

  return _struct_omitting_none(
      path=out_path,
      src=f.is_source,
      root=root_execution_path_fragment,
      is_dir=is_dir
  )


def _file_metadata_by_replacing_path(f, new_path, new_is_dir=None):
  """Returns a copy of the f _file_metadata struct with the given path."""
  root_path = _get_opt_attr(f, 'rootPath')
  if new_is_dir == None:
    new_is_dir = f.is_dir

  return _struct_omitting_none(
      path=new_path,
      src=f.src,
      root=root_path,
      is_dir=new_is_dir
  )


def _collect_artifacts(obj, attr_path):
  """Returns a list of Artifact objects for the attr_path in obj."""
  return [f for src in _getattr_as_list(obj, attr_path)
          for f in _get_opt_attr(src, 'files')]


def _collect_files(obj, attr_path):
  """Returns a list of artifact_location's for the attr_path in obj."""
  return [_file_metadata(f) for f in _collect_artifacts(obj, attr_path)]


def _collect_first_file(obj, attr_path):
  """Returns a the first artifact_location for the attr_path in obj."""
  files = _collect_files(obj, attr_path)
  if not files:
    return None
  return files[0]


def _collect_supporting_files(rule_attr):
  """Extracts 'supporting' files from the given rule attributes."""
  all_files = []
  for attr in _SUPPORTING_FILE_ATTRIBUTES:
    all_files += _collect_files(rule_attr, attr)
  return all_files


def _collect_bundle_paths(rule_attr, bundle_attributes, bundle_ext):
  """Extracts subpaths with the given bundle_ext for the given attributes."""
  discovered_paths = depset()
  bundles = []
  if not bundle_ext.endswith('/'):
    bundle_ext += '/'
  bundle_ext_len = len(bundle_ext) - 1

  for attr in bundle_attributes:
    for f in _collect_files(rule_attr, attr):
      end = f.path.find(bundle_ext)
      if end < 0:
        continue
      end += bundle_ext_len

      path = f.path[:end]
      root_path = _get_opt_attr(f, 'rootPath')
      full_path = str(root_path) + ':' + path
      if full_path in discovered_paths:
        continue
      discovered_paths += [full_path]
      # Generally Xcode treats bundles as special files so they should not be
      # flagged as directories.
      bundles.append(_file_metadata_by_replacing_path(f, path, False))
  return bundles


def _collect_asset_catalogs(rule_attr):
  """Extracts xcassets directories from the given rule attributes."""
  attrs = ['app_asset_catalogs', 'asset_catalogs']
  bundles = _collect_bundle_paths(rule_attr, attrs, '.xcassets')
  bundles.extend(_collect_bundle_paths(rule_attr, attrs, '.xcstickers'))

  return bundles


def _collect_bundle_imports(rule_attr):
  """Extracts bundle directories from the given rule attributes."""
  return _collect_bundle_paths(rule_attr,
                               ['bundle_imports', 'settings_bundle'],
                               '.bundle')


def _collect_framework_imports(rule_attr):
  """Extracts framework directories from the given rule attributes."""
  return _collect_bundle_paths(rule_attr,
                               ['framework_imports'],
                               '.framework')


def _collect_xcdatamodeld_files(obj, attr_path):
  """Returns artifact_location's for xcdatamodeld's for attr_path in obj."""
  files = _collect_files(obj, attr_path)
  if not files:
    return []
  discovered_paths = depset()
  datamodelds = []
  for f in files:
    end = f.path.find('.xcdatamodel/')
    if end < 0:
      continue
    end += 12

    path = f.path[:end]
    root_path = _get_opt_attr(f, 'rootPath')
    full_path = str(root_path) + ':' + path
    if full_path in discovered_paths:
      continue
    discovered_paths += [full_path]
    datamodelds.append(_file_metadata_by_replacing_path(f, path, False))
  return datamodelds


def _collect_dependency_labels(rule, attr_list):
  """Collects Bazel labels for a list of dependency attributes.

  Args:
    rule: The Bazel rule whose dependencies should be collected.
    attr_list: List of attribute names potentially containing Bazel labels for
        dependencies of the given rule.

  Returns:
    A list of the Bazel labels of dependencies of the given rule.
  """
  rule_attrs = rule.attr
  deps = [dep
          for attribute in attr_list
          for dep in _getattr_as_list(rule_attrs, attribute)]
  return [dep.label for dep in deps if hasattr(dep, 'label')]


def _get_opt_attr(obj, attr_path):
  """Returns the value at attr_path on the given object if it is set."""
  attr_path = attr_path.split('.')
  for a in attr_path:
    if not obj or not hasattr(obj, a):
      return None
    obj = getattr(obj, a)
  return obj


def _get_label_attr(obj, attr_path):
  """Returns the value at attr_path as a label string if it is set."""
  label = _get_opt_attr(obj, attr_path)
  return str(label) if label else None


def _getattr_as_list(obj, attr_path):
  """Returns the value at attr_path as a list.

  This handles normalization of attributes containing a single value for use in
  methods expecting a list of values.

  Args:
    obj: The struct whose attributes should be parsed.
    attr_path: Dotted path of attributes whose value should be returned in
        list form.

  Returns:
    A list of values for obj at attr_path or [] if the struct has
    no such attribute.
  """
  val = _get_opt_attr(obj, attr_path)
  if not val:
    return []

  if type(val) == 'list':
    return val
  return [val]


def _extract_defines_from_option_list(lst):
  """Extracts preprocessor defines from a list of -D strings."""
  defines = []
  for item in lst:
    if item.startswith('-D'):
      defines.append(item[2:])
  return defines


def _extract_compiler_defines(ctx):
  """Extracts preprocessor defines from compiler fragments."""
  defines = []

  cpp_fragment = _get_opt_attr(ctx.fragments, 'cpp')
  if cpp_fragment:
    c_options = _get_opt_attr(cpp_fragment, 'c_options')
    defines += _extract_defines_from_option_list(c_options)

    compiler_options = cpp_fragment.compiler_options([])
    defines += _extract_defines_from_option_list(compiler_options)

    unfiltered = cpp_fragment.unfiltered_compiler_options([])
    defines += _extract_defines_from_option_list(unfiltered)

    cxx = cpp_fragment.cxx_options([])
    defines += _extract_defines_from_option_list(cxx)

  objc_fragment = _get_opt_attr(ctx.fragments, 'objc')
  if objc_fragment:
    objc_copts = _get_opt_attr(objc_fragment, 'copts')
    defines += _extract_defines_from_option_list(objc_copts)

  return defines


def _collect_secondary_artifacts(target, ctx):
  """Returns a list of file metadatas for implicit outputs of 'rule'."""
  artifacts = []
  rule = ctx.rule
  if rule.kind in _MERGEDINFOPLIST_GENERATING_RULES:
    bin_dir = _convert_outpath_to_symlink_path(ctx.bin_dir.path)
    package = target.label.package
    basename = target.label.name
    artifacts.append(_struct_omitting_none(
        path='%s/%s-MergedInfo.plist' % (package, basename),
        src=False,
        root=bin_dir
    ))

  return artifacts


def _extract_generated_sources(target):
  """Returns (source_metadatas, includes) generated by the given target."""
  file_metadatas = []
  objc_provider = _get_opt_attr(target, 'objc')
  if hasattr(objc_provider, 'source') and hasattr(objc_provider, 'header'):
    all_files = depset(objc_provider.source)
    all_files += objc_provider.header
    file_metadatas = [_file_metadata(f) for f in all_files]

  return file_metadatas

def _get_platform_type(ctx):
  """Return the current apple_common.platform_type as a string."""
  current_platform = (_get_opt_attr(ctx, 'rule.attr.platform_type')
                      or _get_opt_attr(ctx, 'rule.attr._platform_type'))
  if not current_platform:
    apple_frag = _get_opt_attr(ctx.fragments, 'apple')
    current_platform = str(apple_frag.single_arch_platform.platform_type)
  return current_platform

def _extract_minimum_os_for_platform(ctx, platform_type_str):
  """Extracts the minimum OS version for the given apple_common.platform."""
  min_os = _get_opt_attr(ctx, 'rule.attr.minimum_os_version')
  if min_os:
    return min_os

  platform_type = getattr(apple_common.platform_type, platform_type_str)
  min_os = (ctx.attr._tulsi_xcode_config[apple_common.XcodeVersionConfig]
            .minimum_os_for_platform_type(platform_type))

  if not min_os:
    return None

  # Convert the DottedVersion to a string suitable for inclusion in a struct.
  return str(min_os)


def _extract_swift_language_version(ctx):
  """Returns the Swift version of a swift_library rule."""

  if ctx.rule.kind != 'swift_library':
    return None
  return _get_label_attr(ctx, 'rule.attr.swift_version') or "3.0"


def _collect_swift_modules(target):
  """Returns a depset of Swift modules found on the given target."""
  swift_modules = depset()
  for modules in _getattr_as_list(target, 'swift.transitive_modules'):
    swift_modules += modules
  return swift_modules


def _collect_module_maps(target):
  """Returns a depset of Clang module maps found on the given target."""
  maps = depset()
  if hasattr(target, 'swift'):
    for module_maps in _getattr_as_list(target, 'objc.module_map'):
      maps += module_maps
  return maps

# TODO(b/64490743): Add these files to the Xcode project.
def _collect_swift_header(target):
  """Returns a depset of Swift generated headers found on the given target."""
  headers = depset()
  # swift_* targets put the generated header into their objc provider HEADER
  # field.
  if hasattr(target, 'swift') and hasattr(target, 'objc'):
    headers += target.objc.header
  return headers


def _tulsi_sources_aspect(target, ctx):
  """Extracts information from a given rule, emitting it as a JSON struct."""
  rule = ctx.rule
  target_kind = rule.kind
  rule_attr = _get_opt_attr(rule, 'attr')
  bundle_name = _get_opt_attr(target, 'apple_bundle.bundle_name')

  tulsi_info_files = depset()
  transitive_attributes = dict()
  for attr_name in _TULSI_COMPILE_DEPS:
    deps = _getattr_as_list(rule_attr, attr_name)
    for dep in deps:
      if hasattr(dep, 'tulsi_info_files'):
        tulsi_info_files += dep.tulsi_info_files
      if hasattr(dep, 'transitive_attributes'):
        transitive_attributes += dep.transitive_attributes

  artifacts = _get_opt_attr(target, 'files')
  if artifacts:
    # Ignore any generated Xcode projects as they are not useful to Tulsi.
    artifacts = [_file_metadata(f)
                 for f in artifacts
                 if not f.short_path.endswith('project.pbxproj')]
  else:
    # artifacts may be an empty set type, in which case it must be explicitly
    # set to None to allow Skylark's serialization to work.
    artifacts = None

  srcs = (_collect_files(rule, 'attr.srcs') +
          _collect_files(rule, 'attr.hdrs') +
          _collect_files(rule, 'attr.textual_hdrs'))
  generated_files = []
  generated_non_arc_files = []
  if target_kind in _SOURCE_GENERATING_RULES:
    generated_files = _extract_generated_sources(target)
  elif target_kind in _NON_ARC_SOURCE_GENERATING_RULES:
    generated_non_arc_files = _extract_generated_sources(target)

  swift_transitive_modules = depset(
      [_file_metadata(f, use_tulsi_symlink=True)
       for f in _collect_swift_modules(target)])

  # Collect ObjC module maps dependencies for Swift targets.
  objc_module_maps = depset(
      [_file_metadata(f, use_tulsi_symlink=True)
       for f in _collect_module_maps(target)])

  # Collect the dependencies of this rule, dropping any .jar files (which may be
  # created as artifacts of java/j2objc rules).
  dep_labels = _collect_dependency_labels(rule, _TULSI_COMPILE_DEPS)
  compile_deps = [str(d) for d in dep_labels if not d.name.endswith('.jar')]

  binary_rule = _get_opt_attr(rule_attr, 'binary')
  if binary_rule and type(binary_rule) == 'list':
    binary_rule = binary_rule[0]

  supporting_files = (_collect_supporting_files(rule_attr) +
                      _collect_asset_catalogs(rule_attr) +
                      _collect_bundle_imports(rule_attr))

  # Keys for attribute and inheritable_attributes keys must be kept in sync
  # with defines in Tulsi's RuleEntry.
  attributes = _dict_omitting_none(
      binary=_get_label_attr(binary_rule, 'label'),
      copts=_get_opt_attr(rule_attr, 'copts'),
      datamodels=_collect_xcdatamodeld_files(rule_attr, 'datamodels'),
      supporting_files=supporting_files,
      xctest=_get_opt_attr(rule_attr, 'xctest'),
      xctest_app=_get_label_attr(rule_attr, 'xctest_app.label'),
      test_host=_get_label_attr(rule_attr, 'test_host.label'),
      test_bundle=_get_label_attr(rule_attr, 'test_bundle.label'),
  )

  # Inheritable attributes are pulled up through dependencies of type 'binary'
  # to simplify handling in Tulsi (so it appears as though bridging_header is
  # defined on an ios_application rather than its associated objc_binary, for
  # example).
  inheritable_attributes = _dict_omitting_none(
      bridging_header=_collect_first_file(rule_attr, 'bridging_header'),
      compiler_defines=_extract_compiler_defines(ctx),
      enable_modules=_get_opt_attr(rule_attr, 'enable_modules'),
      launch_storyboard=_collect_first_file(rule_attr, 'launch_storyboard'),
      pch=_collect_first_file(rule_attr, 'pch'),
  )

  # Merge any attributes on the "binary" dependency into this container rule.
  binary_attributes = _get_opt_attr(binary_rule, 'inheritable_attributes')
  if binary_attributes:
    inheritable_attributes = binary_attributes + inheritable_attributes

  extensions = [str(t.label) for t in _getattr_as_list(rule_attr, 'extensions')]
  # Tulsi considers WatchOS apps and extensions as an "extension"
  if target_kind == 'watchos_application':
    watch_ext = _get_label_attr(rule_attr, 'extension.label')
    extensions.append(watch_ext)
  if target_kind == 'ios_application':
    watch_app = _get_label_attr(rule_attr, 'watch_application.label')
    if watch_app:
      extensions.append(watch_app)

  bundle_id = _get_opt_attr(rule_attr, 'bundle_id')

  # Build up any local transitive attributes and apply them.
  swift_language_version = _extract_swift_language_version(ctx)
  if swift_language_version:
    transitive_attributes['swift_language_version'] = swift_language_version
    transitive_attributes['has_swift_dependency'] = True

  # Collect Info.plist files from an extension to figure out its type.
  infoplist = None

  # Only Skylark versions of ios_extension have the 'apple_bundle' provider.
  # TODO(b/37912213): Migrate to the new-style providers.
  if target_kind == 'ios_extension' and hasattr(target, 'apple_bundle'):
    infoplist = target.apple_bundle.infoplist

  all_attributes = attributes + inheritable_attributes + transitive_attributes

  objc_provider = _get_opt_attr(target, 'objc')
  target_includes = []
  target_defines = []
  if objc_provider:
    target_includes = [_convert_outpath_to_symlink_path(x, use_tulsi_symlink=True)
                       for x in objc_provider.include]
    target_defines = objc_provider.define.to_list()

  platform_type = _get_platform_type(ctx)

  info = _struct_omitting_none(
      artifacts=artifacts,
      attr=_struct_omitting_none(**all_attributes),
      build_file=ctx.build_file_path,
      bundle_id=bundle_id,
      bundle_name=bundle_name,
      defines=target_defines,
      deps=compile_deps,
      extensions=extensions,
      framework_imports=_collect_framework_imports(rule_attr),
      generated_files=generated_files,
      generated_non_arc_files=generated_non_arc_files,
      includes=target_includes,
      os_deployment_target=_extract_minimum_os_for_platform(ctx, platform_type),
      label=str(target.label),
      non_arc_srcs=_collect_files(rule, 'attr.non_arc_srcs'),
      secondary_product_artifacts=_collect_secondary_artifacts(target, ctx),
      srcs=srcs,
      swift_transitive_modules=swift_transitive_modules.to_list(),
      objc_module_maps=list(objc_module_maps),
      type=target_kind,
      infoplist=infoplist.basename if infoplist else None,
      platform_type=platform_type,
  )

  # Create an action to write out this target's info.
  output = ctx.new_file(target.label.name + '.tulsiinfo')
  ctx.file_action(output, info.to_json())
  tulsi_info_files += depset([output])

  if infoplist:
    tulsi_info_files += [infoplist]

  return struct(
      # Matches the --output_groups on the bazel commandline.
      output_groups={
          'tulsi-info': tulsi_info_files,
      },
      # The file actions used to save this rule's info and that of all of its
      # transitive dependencies.
      tulsi_info_files=tulsi_info_files,
      # The inheritable attributes of this rule, expressed as a dict instead of
      # a struct to allow easy joining.
      inheritable_attributes=inheritable_attributes,
      # Transitive info that should be applied to every rule that depends on
      # this rule.
      transitive_attributes=transitive_attributes,
  )


def _collect_bundle_info(target):
  """Returns Apple bundle info for the given target, None if not a bundle."""
  # TODO(b/37912213): Migrate to the new-style providers.
  if hasattr(target, 'apple_bundle'):
    apple_bundle = target.apple_bundle
    bundle_full_name = apple_bundle.bundle_name + apple_bundle.bundle_extension
    has_dsym = (apple_common.AppleDebugOutputs in target)
    return [struct(
        archive_root=apple_bundle.archive_root,
        bundle_full_name=bundle_full_name,
        has_dsym=has_dsym)]

  return None


def _tulsi_outputs_aspect(target, ctx):
  """Collects outputs of each build invocation."""

  rule = ctx.rule
  target_kind = rule.kind
  rule_attr = _get_opt_attr(rule, 'attr')
  tulsi_generated_files = depset()

  # A set of all bundles embedded into this target, including deps.
  # We intentionally do not collect info about _current_ target to exclude the
  # root target, which will be covered by other structs in this aspect, from the
  # set.
  embedded_bundles = depset()

  for attr_name in _TULSI_COMPILE_DEPS:
    deps = _getattr_as_list(rule_attr, attr_name)
    for dep in deps:
      if hasattr(dep, 'tulsi_generated_files'):
        tulsi_generated_files += dep.tulsi_generated_files

      dep_bundle_info = _collect_bundle_info(dep)
      if dep_bundle_info:
        embedded_bundles += dep_bundle_info
      if hasattr(dep, 'transitive_embedded_bundles'):
        embedded_bundles += dep.transitive_embedded_bundles

  bundle_name = _get_opt_attr(target, 'apple_bundle.bundle_name')
  # TODO(b/37912213): Migrate to the new-style providers.
  if hasattr(target, 'apple_bundle'):
    artifacts = [target.apple_bundle.archive.path]
  else:  # TODO(b/33050780): Remove this branch when native rules are deleted.
    ipa_output_name = None
    if target_kind in _IPA_GENERATING_RULES:
      ipa_output_name = target.label.name

    artifacts = [x.path for x in target.files]
    if ipa_output_name:
      # Some targets produce more than one IPA or ZIP (e.g. ios_test will
      # generate two IPAs for the test and host bundles), we want to filter only
      # exact matches to label name.
      output_ipa = '/%s.ipa' % ipa_output_name
      output_zip = '/%s.zip' % ipa_output_name

      artifacts = [x for x in artifacts if x.endswith(output_ipa)
                   or x.endswith(output_zip)]

  # Collect generated files for bazel_build.py to copy under Tulsi root.
  all_files = depset()
  if target_kind in _SOURCE_GENERATING_RULES + _NON_ARC_SOURCE_GENERATING_RULES:
    objc_provider = _get_opt_attr(target, 'objc')
    if hasattr(objc_provider, 'source') and hasattr(objc_provider, 'header'):
      all_files += objc_provider.source
      all_files += objc_provider.header

  all_files += _collect_swift_header(target)
  all_files += _collect_swift_modules(target)
  all_files += _collect_module_maps(target)
  all_files += (_collect_artifacts(rule, 'attr.srcs')
                + _collect_artifacts(rule, 'attr.hdrs')
                + _collect_artifacts(rule, 'attr.textual_hdrs'))

  tulsi_generated_files += depset(
      [x for x in all_files.to_list() if not x.is_source])

  info = _struct_omitting_none(
      artifacts=artifacts,
      generated_sources=[(x.path, x.short_path) for x in tulsi_generated_files],
      bundle_name=bundle_name,
      embedded_bundles=embedded_bundles.to_list())

  output = ctx.new_file(target.label.name + '.tulsiouts')
  ctx.file_action(output, info.to_json())

  return struct(
      output_groups={
          'tulsi-outputs': [output],
      },
      tulsi_generated_files=tulsi_generated_files,
      transitive_embedded_bundles=embedded_bundles,
  )


tulsi_sources_aspect = aspect(
    implementation=_tulsi_sources_aspect,
    attrs = {
        '_tulsi_xcode_config': attr.label(default=TULSI_CURRENT_XCODE_CONFIG) },
    attr_aspects=_TULSI_COMPILE_DEPS,
    fragments=['apple', 'cpp', 'objc'],
)


# This aspect does not propagate past the top-level target because we only need
# the top target outputs.
tulsi_outputs_aspect = aspect(
    implementation=_tulsi_outputs_aspect,
    attr_aspects=_TULSI_COMPILE_DEPS,
    fragments=['apple', 'cpp', 'objc'],
)
