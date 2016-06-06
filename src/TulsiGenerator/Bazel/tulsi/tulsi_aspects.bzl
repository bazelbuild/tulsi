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

# List of all of the attributes that can link from a Tulsi-supported rule to a
# Tulsi-supported dependency of that rule.
# For instance, an ios_application's "binary" attribute might link to an
# objc_binary rule which in turn might have objc_library's in its "deps"
# attribute.
_TULSI_COMPILE_DEPS = [
    # ios_application, ios_extension, ios_framework
    'binary',

    # ios_extension_binary, ios_framework_binary, objc_binary, j2objc_library,
    # objc_library, objc_proto_library, ios_test
    'deps',

    # ios_application
    'extensions',

    # apple_watch_extension_binary, ios_extension_binary, ios_framework_binary,
    # objc_binary, objc_library, ios_test
    'non_propagated_deps',

    # ios_test
    'xctest_app',
]

# List of all attributes whose contents should resolve to "support" files; files
# that are used by Bazel to build but do not need special handling in the
# generated Xcode project. For example, Info.plist and entitlements files.
_SUPPORTING_FILE_ATTRIBUTES = [
    # apple_watch1_extension
    'app_entitlements',
    'app_infoplists',
    'app_resources',
    'app_structured_resources',
    'ext_entitlements',
    'ext_infoplists',
    'ext_resources',
    'ext_structured_resources',

    'entitlements',
    'infoplist',
    'infoplists',
    'resources',
    'structured_resources',
    'storyboards',
    'xibs',
]

# Set of rules with implicit <label>.ipa IPA outputs.
_IPA_GENERATING_RULES = set([
    'apple_watch1_extension',
    'ios_application',
    'ios_extension',
    'ios_test',
    'objc_binary',
])

# Set of rules that generate MergedInfo.plist files as part of the build.
_MERGEDINFOPLIST_GENERATING_RULES = set([
    'apple_watch1_extension',
    'ios_application',
])

# Set of rules whose outputs should be treated as generated sources.
_SOURCE_GENERATING_RULES = set([
    'j2objc_library',
    'objc_proto_library',
])

# Set of rules who should be ignored entirely (including their dependencies).
_IGNORED_RULES = set([
    'java_library',
])

def _dict_omitting_none(**kwargs):
  """Creates a dict from the args, dropping keys with None or [] values."""
  return {name: kwargs[name]
          for name in kwargs
          if kwargs[name] != None and kwargs[name] != []
         }


def _struct_omitting_none(**kwargs):
  """Creates a struct from the args, dropping keys with None or [] values."""
  return struct(**_dict_omitting_none(**kwargs))


def _convert_outpath_to_symlink_path(path):
  """Converts full output paths to their bazel-symlink equivalents."""
  # The path will be of the form
  # bazel-[whatever]/[platform-config]/symlink[/.*]
  first_dash = path.find('-')
  components = path.split('/')
  if (len(components) > 2 and
      first_dash >= 0 and
      first_dash < len(components[0])):
    return path[:first_dash + 1] + '/'.join(components[2:])
  return path


def _file_metadata(f):
  """Returns metadata about a given File."""
  if not f:
    return None

  if not f.is_source:
    root_path = f.root.path
    symlink_path = _convert_outpath_to_symlink_path(root_path)
    if symlink_path == root_path:
      # The root path should always be bazel-out/... and thus is expected to be
      # updated.
      print('Unexpected root path "%s". Please report.' % root_path)
      root_execution_path_fragment = root_path
    else:
      root_execution_path_fragment = symlink_path
  else:
    root_execution_path_fragment = None

  return _struct_omitting_none(
      path=f.short_path,
      src=f.is_source,
      root=root_execution_path_fragment
  )


def _file_metadata_by_replacing_path(f, new_path):
  """Returns a copy of the f _file_metadata struct with the given path."""
  root_path = _get_opt_attr(f, 'rootPath')
  return _struct_omitting_none(
      path=new_path,
      src=f.src,
      root=root_path
  )


def _collect_files(obj, attr_path):
  """Returns a list of artifact_location's for the attr_path in obj."""
  return [_file_metadata(f)
          for src in _getattr_as_list(obj, attr_path)
          for f in _get_opt_attr(src, 'files')]


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


def _collect_asset_catalogs(rule_attr):
  """Extracts xcassets directories from the given rule attributes."""
  discovered_paths = set()
  bundles = []
  for attr in ['app_asset_catalogs', 'asset_catalogs']:
    for f in _collect_files(rule_attr, attr):
      end = f.path.find('.xcassets/')
      if end < 0:
        continue
      end += 9

      path = f.path[:end]
      root_path = _get_opt_attr(f, 'rootPath')
      full_path = str(root_path) + ':' + path
      if full_path in discovered_paths:
        continue
      discovered_paths += [full_path]
      bundles.append(_file_metadata_by_replacing_path(f, path))

  return bundles


def _collect_xcdatamodeld_files(obj, attr_path):
  """Returns artifact_location's for xcdatamodeld's for attr_path in obj."""
  files = _collect_files(obj, attr_path)
  if not files:
    return []
  discovered_paths = set()
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
    datamodelds.append(_file_metadata_by_replacing_path(f, path))
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


# TODO(abaire): Remove this when its single invocation is removed below.
def _includes_for_objc_proto_files(generated_files, rule_name):
  """Extracts generated include paths for objc_proto_library rule_name."""
  ret = set()
  # _generated_protos comes from the ProtoSupport class in Bazel's objc rule
  # package and will need to be updated here if it changes at any point.
  generated_root_subpath = '_generated_protos/' + rule_name
  generated_root_subpath_len = len(generated_root_subpath)
  for f in generated_files:
    generated_path_index = f.path.find(generated_root_subpath)
    if generated_path_index < 0:
      continue
    path = f.path[:generated_path_index + generated_root_subpath_len]
    root = _get_opt_attr(f, 'root')
    if root:
      include = '%s/%s' % (root, path)
    else:
      include = path
    ret += [include]
  return ret


def _collect_secondary_artifacts(target, ctx):
  """Returns a list of file metadatas for implicit outputs of 'rule'."""
  artifacts = []
  rule = ctx.rule
  if rule.kind in _MERGEDINFOPLIST_GENERATING_RULES:
    bin_dir = _convert_outpath_to_symlink_path(ctx.configuration.bin_dir.path)
    package = target.label.package
    basename = target.label.name
    artifacts.append(_struct_omitting_none(
        path='%s/%s-MergedInfo.plist' % (package, basename),
        src=False,
        root=bin_dir
    ))

  return artifacts


def _tulsi_sources_aspect(target, ctx):
  """Extracts information from a given rule, emitting it as a JSON struct."""
  rule = ctx.rule
  target_kind = rule.kind
  if target_kind in _IGNORED_RULES:
    return struct(skipped_labels=set([target.label]))

  rule_attr = _get_opt_attr(rule, 'attr')

  tulsi_info_files = set()
  skipped_labels = set()
  for attr_name in _TULSI_COMPILE_DEPS:
    deps = _getattr_as_list(rule_attr, attr_name)
    for dep in deps:
      if hasattr(dep, 'tulsi_info_files'):
        tulsi_info_files += dep.tulsi_info_files
      if hasattr(dep, 'skipped_labels'):
        skipped_labels += dep.skipped_labels

  srcs = (_collect_files(rule, 'attr.srcs') +
          _collect_files(rule, 'attr.hdrs'))
  generated_files = None
  generated_includes = None
  if target_kind in _SOURCE_GENERATING_RULES:
    # TODO(abaire): Make the provider-driven method the only supported one.
    #               This should be done once the provider exposure has been
    #               rolled out long enough for users to adopt it.
    objc_provider = _get_opt_attr(target, 'objc')

    if hasattr(objc_provider, 'source') and hasattr(objc_provider, 'header'):
      all_files = set(objc_provider.source)
      all_files += objc_provider.header
      generated_files = [_file_metadata(f)
                         for f in all_files]
    else:
      generated_files = [_file_metadata(f)
                         for f in _get_opt_attr(target, 'files')]

    if objc_provider and hasattr(objc_provider, 'include'):
      generated_includes = [_convert_outpath_to_symlink_path(x)
                            for x in objc_provider.include]
    else:
      print('Falling back to generated file scraping for includes due to ' +
            'missing objc provider. This may result in missing includes and ' +
            'partially indexed sources in the generated Xcode project. Your ' +
            'Bazel version probably needs to be updated.')
      generated_includes = list(
          _includes_for_objc_proto_files(generated_files, target.label.name))
  compile_deps = _collect_dependency_labels(rule, _TULSI_COMPILE_DEPS)
  # Filter out any deps that were skipped by the attribute and convert the
  # labels to strings.
  compile_deps = [str(dep)
                  for dep in compile_deps
                  if dep not in skipped_labels]
  binary_rule = _get_opt_attr(rule_attr, 'binary')

  supporting_files = (_collect_supporting_files(rule_attr) +
                      _collect_asset_catalogs(rule_attr))

  # Keys for attribute and inheritable_attributes keys must be kept in sync
  # with defines in Tulsi's RuleEntry.
  attributes = _dict_omitting_none(
      binary=_get_label_attr(rule_attr, 'binary.label'),
      copts=_get_opt_attr(rule_attr, 'copts'),
      datamodels=_collect_xcdatamodeld_files(rule_attr, 'datamodels'),
      supporting_files=supporting_files,
      xctest=_get_opt_attr(rule_attr, 'xctest'),
      xctest_app=_get_label_attr(rule_attr, 'xctest_app.label'),
  )

  # Inheritable attributes are pulled up through dependencies of type 'binary'
  # to simplify handling in Tulsi (so it appears as though bridging_header is
  # defined on an ios_application rather than its associated objc_binary, for
  # example).
  inheritable_attributes = _dict_omitting_none(
      bridging_header=_collect_first_file(rule_attr, 'bridging_header'),
      compiler_defines=_extract_compiler_defines(ctx),
      defines=_getattr_as_list(rule_attr, 'defines'),
      enable_modules=_get_opt_attr(rule_attr, 'enable_modules'),
      includes=_getattr_as_list(rule_attr, 'includes'),
      launch_storyboard=_collect_first_file(rule_attr, 'launch_storyboard'),
      pch=_collect_first_file(rule_attr, 'pch'),
  )

  # Merge any attributes on the "binary" dependency into this container rule.
  binary_attributes = _get_opt_attr(binary_rule, 'inheritable_attributes')
  if binary_attributes:
    inheritable_attributes = binary_attributes + inheritable_attributes

  ipa_output_label = None
  if target_kind in _IPA_GENERATING_RULES:
    ipa_output_label = str(target.label) + '.ipa'

  all_attributes = attributes + inheritable_attributes
  info = _struct_omitting_none(
      attr=_struct_omitting_none(**all_attributes),
      build_file=ctx.build_file_path,
      deps=compile_deps,
      generated_files=generated_files,
      generated_includes=generated_includes,
      ipa_output_label=ipa_output_label,
      label=str(target.label),
      non_arc_srcs=_collect_files(rule, 'attr.non_arc_srcs'),
      secondary_product_artifacts=_collect_secondary_artifacts(target, ctx),
      srcs=srcs,
      type=target_kind,
  )

  # Create an action to write out this target's info.
  output = ctx.new_file(target.label.name + '.tulsiinfo')
  ctx.file_action(output, info.to_json())
  tulsi_info_files += set([output])

  return struct(
      # Matches the --output_groups on the bazel commandline.
      output_groups={
          'tulsi-info': tulsi_info_files,
      },
      # The file actions used to save this rule's info and that of all of its
      # transitive dependencies.
      tulsi_info_files=tulsi_info_files,
      # The accumulated set of labels which have been excluded from info
      # generation.
      skipped_labels=skipped_labels,
      # The inheritable attributes of this rule, expressed as a dict instead of
      # a struct to allow easy joining.
      inheritable_attributes=inheritable_attributes,
  )


tulsi_sources_aspect = aspect(
    implementation=_tulsi_sources_aspect,
    attr_aspects=_TULSI_COMPILE_DEPS,
    fragments=['cpp', 'objc'],
)
