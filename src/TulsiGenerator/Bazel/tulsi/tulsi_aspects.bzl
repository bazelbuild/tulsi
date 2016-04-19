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
    "binary",

    # ios_extension_binary, ios_framework_binary, objc_binary, j2objc_library,
    # objc_library, objc_proto_library, ios_test
    "deps",

    # ios_application
    "extensions",

    # ios_test
    "xctest_app",
]


def _dict_omitting_none(**kwargs):
  """Creates a dict from the args, dropping keys with None or [] values."""
  return {name: kwargs[name]
          for name in kwargs
          if kwargs[name] != None and kwargs[name] != []
          }


def _struct_omitting_none(**kwargs):
  """Creates a struct from the args, dropping keys with None or [] values."""
  return struct(**_dict_omitting_none(**kwargs))


def _file_metadata(file):
  """Returns metadata about a given file label."""
  if not file:
    return None

  if not file.is_source:
    # The root path will be something like "bazel-out/darwin_x86_64-fastbuild/genfiles". Tulsi needs
    # to use the automatic symlink as the actual build type is unlikely to be the same as that used
    # to run the aspect (i.e., the darwin_x86_64-fastbuild part).
    root_path = file.root.path
    first_dash = root_path.find("-")
    components = root_path.split("/")
    if first_dash >= 0 and len(components) > 2:
      symlink_path = root_path[:first_dash + 1] + "/".join(components[2:])
      root_execution_path_fragment = symlink_path
    else:
      print('Unexpected root path "%s". Please report.' % root_path)
      root_execution_path_fragment = root_path
  else:
    root_execution_path_fragment = None

  return _struct_omitting_none(
      path = file.short_path,
      src = file.is_source,
      rootPath = root_execution_path_fragment
  )


def _collect_files(obj, attr_path):
  """Returns a list of artifact_location's for the attr_path in obj."""
  return [_file_metadata(file)
          for src in _getattr_as_list(obj, attr_path)
          for file in _get_opt_attr(src, 'files')]


def _collect_first_file(obj, attr_path):
  """Returns a the first artifact_location for the attr_path in obj."""
  files = _collect_files(obj, attr_path)
  if not files:
    return None
  return files[0]


def _collect_xcdatamodeld_files(obj, attr_path):
  """Returns artifact_location's for xcdatamodeld's for attr_path in obj."""
  files = _collect_files(obj, attr_path)
  if not files:
    return []
  discovered_paths = set()
  datamodelds = []
  for file in files:
    end = file.path.find('.xcdatamodel/')
    if end < 0:
      continue
    end += 12

    path = file.path[:end]
    rootPath = _get_opt_attr(file, 'rootPath')
    full_path = str(rootPath) + ':' + path
    if full_path in discovered_paths:
      continue
    discovered_paths += [full_path]
    datamodelds.append(_struct_omitting_none(
        path = path,
        src = file.src,
        rootPath = rootPath))
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
  return [str(dep.label) for dep in deps if hasattr(dep, 'label')]


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


def _tulsi_sources_aspect(target, ctx):
  """Extracts information from a given rule, emitting it as a JSON struct."""
  rule = ctx.rule
  target_kind = rule.kind
  rule_attr = _get_opt_attr(rule, 'attr')

  tulsi_info_files = set()
  for attr_name in _TULSI_COMPILE_DEPS:
    deps = _getattr_as_list(rule_attr, attr_name)
    for dep in deps:
      if hasattr(dep, 'tulsi_info_files'):
        tulsi_info_files += dep.tulsi_info_files

  srcs = (_collect_files(rule, 'attr.srcs') +
          _collect_files(rule, 'attr.hdrs') +
          _collect_files(rule, 'attr.non_arc_srcs'))
  src_outputs = None
  if target_kind == "objc_proto_library":
    src_outputs = [_file_metadata(file)
                   for file in _get_opt_attr(target, 'files')]
  compile_deps = _collect_dependency_labels(rule, _TULSI_COMPILE_DEPS)
  binary_rule = _get_opt_attr(rule_attr, 'binary')

  # Keys for attribute and inheritable_attributes keys must be kept in sync
  # with defines in Tulsi's RuleEntry.
  attributes = _dict_omitting_none(
      asset_catalogs = _collect_files(rule_attr, 'asset_catalogs'),
      binary = _get_label_attr(rule_attr, 'binary.label'),
      copts = _get_opt_attr(rule_attr, 'copts'),
      datamodels = _collect_xcdatamodeld_files(rule_attr, 'datamodels'),
      xctest = _get_opt_attr(rule_attr, 'xctest'),
      xctest_app = _get_label_attr(rule_attr, 'xctest_app.label'),
  )

  # Inheritable attributes are pulled up through dependencies of type 'binary'
  # to simplify handling in Tulsi (so it appears as though bridging_header is
  # defined on an ios_application rather than its associated objc_binary, for
  # example).
  inheritable_attributes = _dict_omitting_none(
      bridging_header = _collect_first_file(rule_attr, 'bridging_header'),
      defines = _getattr_as_list(rule_attr, 'defines'),
      compiler_defines = _extract_compiler_defines(ctx),
      includes = _getattr_as_list(rule_attr, 'includes'),
      launch_storyboard = _collect_first_file(rule_attr, 'launch_storyboard'),
      pch = _collect_first_file(rule_attr, 'pch'),
      storyboards = _collect_files(rule_attr, 'storyboards'),
  )

  # Merge any attributes on the "binary" dependency into this container rule.
  binary_attributes = _get_opt_attr(binary_rule, 'inheritable_attributes')
  if binary_attributes:
    inheritable_attributes = binary_attributes + inheritable_attributes

  all_attributes = attributes + inheritable_attributes
  info = _struct_omitting_none(
      attr = _struct_omitting_none(**all_attributes),
      build_file = ctx.build_file_path,
      deps = compile_deps,
      label = str(target.label),
      srcs = srcs,
      src_outputs = src_outputs,
      type = target_kind,
  )

  output = ctx.new_file(target.label.name + '.tulsiinfo')
  ctx.file_action(output, info.to_json())
  tulsi_info_files += set([output])

  return struct(
      # Matches the --output_groups on the bazel commandline.
      output_groups = {
        'tulsi-info': tulsi_info_files,
      },
      # The file actions used to save this rule's info and that of all of its
      # transitive dependencies.
      tulsi_info_files = tulsi_info_files,
      # The metadata about this rule.
      tulsi_info = info,
      # The inheritable attributes of this rule, expressed as a dict instead of
      # a struct to allow easy joining.
      inheritable_attributes = inheritable_attributes,
  )


tulsi_sources_aspect = aspect(
    implementation = _tulsi_sources_aspect,
    attr_aspects = _TULSI_COMPILE_DEPS,
    fragments = ['cpp', 'objc'],
)
