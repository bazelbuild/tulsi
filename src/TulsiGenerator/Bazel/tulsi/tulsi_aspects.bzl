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

load(
    ":tulsi/tulsi_aspects_paths.bzl",
    "AppleBinaryInfo",
    "AppleBundleInfo",
    "AppleTestInfo",
    "IosApplicationBundleInfo",
    "IosExtensionBundleInfo",
    "SwiftInfo",
)
load(
    ":tulsi/tulsi_aspects_propagation_attrs.bzl",
    "TULSI_COMPILE_DEPS",
    "attrs_for_target_kind",
)
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

ObjcInfo = apple_common.Objc

# Defensive list of features that can appear in the C++ toolchain, but that we
# definitely don't want to enable (meaning we don't want them to contribute
# command line flags).
UNSUPPORTED_FEATURES = [
    "thin_lto",
    "module_maps",
    "use_header_modules",
    "fdo_instrument",
    "fdo_optimize",
]

# These are attributes that contain bundles but should not be considered as
# embedded bundles. For example, test bundles depend on app bundles
# to be test hosts in bazel semantics, but in reality, Xcode treats the test
# bundles as an embedded bundle of the app.
_TULSI_NON_EMBEDDEDABLE_ATTRS = [
    "test_host",
]

# List of all attributes whose contents should resolve to "support" files; files
# that are used by Bazel to build but do not need special handling in the
# generated Xcode project. For example, Info.plist and entitlements files.
_SUPPORTING_FILE_ATTRIBUTES = [
    "app_icons",
    "data",
    "entitlements",
    "infoplists",
    "resources",
    "strings",
    "structured_resources",
    "storyboards",
    "xibs",
]

# List of rules whose outputs should be treated as generated sources.
_SOURCE_GENERATING_RULES = [
    "j2objc_library",
]

# List of rules whose outputs should be treated as generated sources that do not
# use ARC.
_NON_ARC_SOURCE_GENERATING_RULES = [
    "objc_proto_library",
]

# List of all extensions to include when scanning target.files for generated
# files. This helps avoid but not prevent the following:
#
# _tulsi-include maps generated files from multiple configurations into one
# directory for inclusion in the generated project. This can cause issues when
# conflicting files are generated, e.g.
#
# library/subpath/foobar (an executable)
# library/subpath/foobar/dependency/dep_lib.a
#
# Tulsi would fail trying to copy both of these as it would require `foobar` to
# be both a file and directory. As a partial workaround, we only copy in files
# that we believe to be 'source files' and thus unlikely to also be folders.
_GENERATED_SOURCE_FILE_EXTENSIONS = [
    "c",
    "cc",
    "cpp",
    "h",
    "hpp",
    "m",
    "mm",
    "swift",
    "swiftmodule",
    "swiftsourceinfo",
    "swiftdoc",
]

TulsiSourcesAspectInfo = provider(
    fields = {
        "transitive_info_files": """
The file actions used to save this rule's info and that of all of its transitive dependencies as
well as any Info plists required for extensions.
""",
        "inheritable_attributes": """
The inheritable attributes of this rule, expressed as a dict instead of a struct to allow easy
joining.
""",
        "transitive_attributes": """
Transitive attributes that should be applied to every rule that depends on this rule.
""",
        "artifacts": """
Artifacts from this rule.
""",
        "filtering_info": """
Filtering information for this target. Only for test target, otherwise is None.
""",
    },
)

TulsiOutputAspectInfo = provider(
    doc = """Provides information about an Apple target's outputs.""",
    fields = {
        "transitive_explicit_modules": "Depset of all explicit modules built by this target.",
        "transitive_generated_files": "Depset of tulsi generated files.",
        "transitive_embedded_bundles": "Depset of all bundles embedded into this target.",
    },
)

def _dict_omitting_none(**kwargs):
    """Creates a dict from the args, dropping keys with None or [] values."""
    return {
        name: kwargs[name]
        for name in kwargs
        # Skylark doesn't support "is"; comparison is explicit for correctness.
        # pylint: disable=g-equals-none,g-explicit-bool-comparison
        if kwargs[name] != None and kwargs[name] != []
    }

def _struct_omitting_none(**kwargs):
    """Creates a struct from the args, dropping keys with None or [] values."""
    return struct(**_dict_omitting_none(**kwargs))

def _convert_outpath_to_symlink_path(path):
    """Converts full output paths to their tulsi-symlink equivalents.

    Bazel output paths are unstable, prone to change with architecture,
    platform or flag changes. Therefore we can't rely on them to supply to Xcode.
    Instead, we will root all outputs under a stable tulsi dir,
    and the bazel_build.py script will link the artifacts into the correct
    location under it.

    Tulsi root is located at WORKSPACE/bazel-exec-root-link/bazel-tulsi-includes/x/x/.
    The two "x" directories are stubs to match the number of path components, so
    that relative paths work with the new location. Some Bazel outputs, like
    module maps, use relative paths to reference other files in the build.

    The prefix of bazel-tulsi-includes is present as Bazel will clear all
    directories that don't start with 'bazel-' when it builds.
    Otherwise, upon a build failure, bazel-tulsi-includes would be removed and
    indexing and auto-completion for generated files would no longer work until
    the next successful build.

    In short, this method will transform
      bazel-out/ios-x86_64-min7.0/genfiles/foo
    to
      bazel-tulsi-includes/x/x/foo

    This is currently enabled for everything although it will only affect
    generated files.

    Args:
      path: path to transform

    Returns:
      A string that is the original path modified according to the rules.
    """

    # Transform paths of the form:
    #   bazel-[whatever]/[platform-config]/symlink[/.*]
    # to:
    #   bazel-tulsi-includes/x/x/symlink[/.*]
    first_dash = path.find("-")
    components = path.split("/")
    if (len(components) > 2 and
        first_dash >= 0 and
        first_dash < len(components[0])):
        return "bazel-tulsi-includes/x/x/" + "/".join(components[3:])
    return path

def _is_file_a_directory(f):
    """Returns True is the given file is a directory."""
    # Starting Bazel 3.3.0, the File type as a is_directory attribute.
    if getattr(f, "is_directory", None):
        return f.is_directory
    # If is_directory is not in the File type, fall back to the old method:
    # As of Oct. 2016, Bazel disallows most files without extensions.
    # As a temporary hack, Tulsi treats File instances pointing at extension-less
    # paths as directories. This is extremely fragile and must be replaced with
    # logic properly homed in Bazel.
    return (f.basename.find(".") == -1)

def _is_file_external(f):
    """Returns True if the given file is an external file."""
    return f.owner.workspace_root != ""

def _file_metadata(f):
    """Returns metadata about a given File."""
    if not f:
        return None

    # Special case handling for external files.
    is_external = _is_file_external(f)

    out_path = f.path if is_external else f.short_path
    if not f.is_source and not is_external:
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
        path = out_path,
        src = f.is_source,
        root = root_execution_path_fragment,
        is_dir = _is_file_a_directory(f),
    )

def _file_metadata_by_replacing_path(f, new_path, new_is_dir = None):
    """Returns a copy of the f _file_metadata struct with the given path."""
    root_path = _get_opt_attr(f, "rootPath")
    if new_is_dir == None:
        new_is_dir = f.is_dir

    return _struct_omitting_none(
        path = new_path,
        src = f.src,
        root = root_path,
        is_dir = new_is_dir,
    )

def _depset_to_file_metadata_list(a_depset):
    """Converts a depset of files into a list of _file_metadata structs."""
    return [_file_metadata(f) for f in a_depset.to_list()]

def _collect_artifacts(obj, attr_path, exclude_xcdatamodel = False, exclude_xcassets = False):
    """Returns a list of Artifact objects for the attr_path in obj."""
    return [
        f
        for src in _getattr_as_list(obj, attr_path)
        for f in _get_opt_attr(src, "files").to_list()
        if (not exclude_xcdatamodel or ".xcdatamodel" not in f.path) and
           (not exclude_xcassets or ".xcassets" not in f.path) and
           (not exclude_xcassets or ".xcstickers" not in f.path)
    ]

def _collect_files(
        obj,
        attr_path,
        convert_to_metadata = True,
        exclude_xcdatamodel = False,
        exclude_xcassets = False):
    """Returns a list of artifact_location's for the attr_path in obj."""
    if convert_to_metadata:
        return [_file_metadata(f) for f in _collect_artifacts(
            obj,
            attr_path,
            exclude_xcdatamodel = exclude_xcdatamodel,
            exclude_xcassets = exclude_xcassets,
        )]
    else:
        return _collect_artifacts(
            obj,
            attr_path,
            exclude_xcdatamodel = exclude_xcdatamodel,
            exclude_xcassets = exclude_xcassets,
        )

def _collect_first_file(obj, attr_path):
    """Returns a the first artifact_location for the attr_path in obj."""
    files = _collect_files(obj, attr_path)
    if not files:
        return None
    return files[0]

def _collect_supporting_files(rule_attr, convert_to_metadata = True):
    """Extracts 'supporting' files from the given rule attributes."""
    all_files = []
    for attr in _SUPPORTING_FILE_ATTRIBUTES:
        all_files += _collect_files(
            rule_attr,
            attr,
            convert_to_metadata = convert_to_metadata,
            exclude_xcdatamodel = True,
            exclude_xcassets = True,
        )
    return all_files

def _collect_bundle_paths(rule_attr, bundle_attributes, bundle_ext):
    """Extracts subpaths with the given bundle_ext for the given attributes."""
    discovered_paths = dict()
    bundles = []
    if not bundle_ext.endswith("/"):
        bundle_ext += "/"
    bundle_ext_len = len(bundle_ext) - 1

    for attr in bundle_attributes:
        for f in _collect_files(rule_attr, attr):
            end = f.path.find(bundle_ext)
            if end < 0:
                continue
            end += bundle_ext_len

            path = f.path[:end]
            root_path = _get_opt_attr(f, "rootPath")
            full_path = str(root_path) + ":" + path
            if full_path in discovered_paths:
                continue

            # Using the 'discovered_paths' as a set, we will only be checking for the existence of a
            # key, the actual value does not matter so assign it 'None'.
            discovered_paths[full_path] = None

            # Generally Xcode treats bundles as special files so they should not be
            # flagged as directories.
            bundles.append(_file_metadata_by_replacing_path(f, path, False))
    return bundles

def _collect_asset_catalogs(rule_attr):
    """Extracts xcassets directories from the given rule attributes."""
    attrs = ["app_asset_catalogs", "asset_catalogs", "data"]
    bundles = _collect_bundle_paths(rule_attr, attrs, ".xcassets")
    bundles.extend(_collect_bundle_paths(rule_attr, attrs, ".xcstickers"))

    return bundles

def _collect_bundle_imports(rule_attr):
    """Extracts bundle directories from the given rule attributes."""
    return _collect_bundle_paths(
        rule_attr,
        ["bundle_imports", "settings_bundle"],
        ".bundle",
    )

def _collect_framework_imports(rule_attr):
    """Extracts framework directories from the given rule attributes."""
    return _collect_bundle_paths(
        rule_attr,
        ["framework_imports"],
        ".framework",
    )

def _collect_xcdatamodeld_files(obj, attr_path):
    """Returns artifact_location's for xcdatamodeld's for attr_path in obj."""
    files = _collect_files(obj, attr_path)
    if not files:
        return []
    discovered_paths = dict()
    datamodelds = []
    for f in files:
        end = f.path.find(".xcdatamodel/")
        if end < 0:
            continue
        end += 12

        path = f.path[:end]
        root_path = _get_opt_attr(f, "rootPath")
        full_path = str(root_path) + ":" + path
        if full_path in discovered_paths:
            continue

        # Using the 'discovered_paths' as a set, we will only be checking for the existence of a
        # key, the actual value does not matter so assign it 'None'.
        discovered_paths[full_path] = None
        datamodelds.append(_file_metadata_by_replacing_path(f, path, False))
    return datamodelds

def _collect_dependencies(rule_attr, attr_name):
    """Collects Bazel targets for a dependency attr.

    Args:
      rule_attr: The Bazel rule.attr whose dependencies should be collected.
      attr_name: attribute name to inspect for dependencies.

    Returns:
      A list of the Bazel target dependencies of the given rule.
    """
    return [
        dep
        for dep in _getattr_as_list(rule_attr, attr_name)
        if type(dep) == "Target" and
           (TulsiSourcesAspectInfo in dep or TulsiOutputAspectInfo in dep)
    ]

def _collect_dependency_labels(rule, filter, attr_list):
    """Collects Bazel labels for a list of dependency attributes.

    Args:
      rule: The Bazel rule whose dependencies should be collected.
      filter: Filter to apply when gathering dependencies.
      attr_list: List of attribute names potentially containing Bazel labels for
          dependencies of the given rule.

    Returns:
      A list of the Bazel labels of dependencies of the given rule.
    """
    attr = rule.attr
    deps = [
        dep
        for attribute in attr_list
        for dep in _filter_deps(
            filter,
            _collect_dependencies(attr, attribute),
        )
    ]
    return [dep.label for dep in deps if hasattr(dep, "label")]

def _get_opt_provider(target, provider):
    """Returns the given provider on target, if present."""
    return target[provider] if provider in target else None

def _get_opt_attr(obj, attr_path):
    """Returns the value at attr_path on the given object if it is set."""
    attr_path = attr_path.split(".")
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

    if type(val) == "list":
        return val
    elif type(val) == "dict":
        return val.keys()
    return [val]

def _extract_defines_from_option_list(lst):
    """Extracts preprocessor defines from a list of -D strings."""
    defines = []
    for item in lst:
        if item.startswith("-D"):
            defines.append(item[2:])
    return defines

def _extract_compiler_defines(ctx):
    """Extracts preprocessor defines from compiler fragments."""
    defines = []

    cpp_fragment = _get_opt_attr(ctx.fragments, "cpp")

    # Enabled in Bazel 0.17
    if hasattr(cpp_fragment, "copts"):
        cc_toolchain = find_cpp_toolchain(ctx)
        copts = cpp_fragment.copts
        cxxopts = cpp_fragment.cxxopts
        conlyopts = cpp_fragment.conlyopts

        feature_configuration = cc_common.configure_features(
            ctx = ctx,
            cc_toolchain = cc_toolchain,
            requested_features = ctx.features,
            unsupported_features = ctx.disabled_features + UNSUPPORTED_FEATURES,
        )
        c_variables = cc_common.create_compile_variables(
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            user_compile_flags = copts + conlyopts,
        )
        cpp_variables = cc_common.create_compile_variables(
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            add_legacy_cxx_options = True,
            user_compile_flags = copts + cxxopts,
        )
        c_options = cc_common.get_memory_inefficient_command_line(
            feature_configuration = feature_configuration,
            # TODO(hlopko): Replace with action_name once Bazel >= # 0.16 is assumed
            action_name = "c-compile",
            variables = c_variables,
        )
        cpp_options = cc_common.get_memory_inefficient_command_line(
            feature_configuration = feature_configuration,
            # TODO(hlopko): Replace with action_name once Bazel >= # 0.16 is assumed
            action_name = "c++-compile",
            variables = cpp_variables,
        )
        defines += _extract_defines_from_option_list(c_options)
        defines += _extract_defines_from_option_list(cpp_options)
    elif cpp_fragment:
        c_options = _get_opt_attr(cpp_fragment, "c_options")
        defines += _extract_defines_from_option_list(c_options)

        compiler_options = cpp_fragment.compiler_options([])
        defines += _extract_defines_from_option_list(compiler_options)

        unfiltered = cpp_fragment.unfiltered_compiler_options([])
        defines += _extract_defines_from_option_list(unfiltered)

        cxx = cpp_fragment.cxx_options([])
        defines += _extract_defines_from_option_list(cxx)

    objc_fragment = _get_opt_attr(ctx.fragments, "objc")
    if objc_fragment:
        objc_copts = _get_opt_attr(objc_fragment, "copts")
        defines += _extract_defines_from_option_list(objc_copts)

    return defines

def _collect_secondary_artifacts(target, ctx):
    """Returns a list of file metadatas for implicit outputs of 'target'."""
    artifacts = []
    if AppleBundleInfo in target:
        infoplist = target[AppleBundleInfo].infoplist

        if infoplist:
            artifacts.append(_file_metadata(infoplist))

    return artifacts

def _extract_generated_sources(target):
    """Returns (source_metadatas, includes) generated by the given target."""
    transitive_depsets = []
    objc_provider = _get_opt_provider(target, ObjcInfo)
    if hasattr(objc_provider, "source"):
        transitive_depsets.append(objc_provider.source)
    cc_info = _get_opt_provider(target, CcInfo)
    if cc_info:
        transitive_depsets.append(cc_info.compilation_context.headers)
    file_metadatas = _depset_to_file_metadata_list(depset(transitive = transitive_depsets))

    return file_metadatas

def _get_deployment_info(target, ctx):
    """Returns (platform_type, minimum_os_version) for the given target."""
    if AppleBundleInfo in target:
        apple_bundle_provider = target[AppleBundleInfo]
        minimum_os_version = apple_bundle_provider.minimum_os_version
        platform_type = apple_bundle_provider.platform_type
        return (platform_type, minimum_os_version)

    attr_platform_type = _get_platform_type(ctx)
    return (attr_platform_type, _minimum_os_for_platform(ctx, attr_platform_type))

def _get_xcode_version(ctx):
    """Returns the current Xcode version as a string."""
    return str(ctx.attr._tulsi_xcode_config[apple_common.XcodeVersionConfig].xcode_version())

def _get_platform_type(ctx):
    """Return the current apple_common.platform_type as a string."""
    current_platform = (_get_opt_attr(ctx, "rule.attr.platform_type") or
                        _get_opt_attr(ctx, "rule.attr._platform_type"))
    if not current_platform:
        apple_frag = _get_opt_attr(ctx.fragments, "apple")
        current_platform = str(apple_frag.single_arch_platform.platform_type)
    return current_platform

def _minimum_os_for_platform(ctx, platform_type_str):
    """Extracts the minimum OS version for the given apple_common.platform."""
    min_os = _get_opt_attr(ctx, "rule.attr.minimum_os_version")
    if min_os:
        return min_os

    platform_type = getattr(apple_common.platform_type, platform_type_str)
    min_os = (ctx.attr._tulsi_xcode_config[apple_common.XcodeVersionConfig].minimum_os_for_platform_type(platform_type))

    if not min_os:
        return None

    # Convert the DottedVersion to a string suitable for inclusion in a struct.
    return str(min_os)

def _is_swift_target(target):
    """Returns whether a target is a Swift target"""
    if SwiftInfo not in target:
        return False

    # Containing a SwiftInfo provider is insufficient to determine whether a target is a Swift
    # target so check whether it contains at least one Swift direct module.
    for module in target[SwiftInfo].direct_modules:
        if module.swift != None:
            return True

    return False

def _collect_swift_modules(target):
    """Returns a list of Swift modules found on the given target."""
    return [
        module.swift.swiftmodule
        for module in target[SwiftInfo].transitive_modules.to_list()
        if module.swift
    ]

def _collect_clang_modules(target):
    """Returns a struct with lists of Clang pcms and module maps found on the given target."""
    if not _is_swift_target(target):
        return struct(module_maps = [], precompiled_modules = [])

    module_maps = []
    precompiled_modules = []

    for module in target[SwiftInfo].transitive_modules.to_list():
        if module.clang == None:
            continue

        # Collect precompiled modules
        if module.clang.precompiled_module:
            precompiled_module = struct(
                module = module.clang.precompiled_module,
                name = module.name,
            )
            precompiled_modules.append(precompiled_module)

        # Collect module maps
        if type(module.clang.module_map) == "File":
            module_maps.append(module.clang.module_map)

    return struct(module_maps = module_maps, precompiled_modules = precompiled_modules)

def _collect_objc_strict_includes(target, rule_attr):
    """Returns a depset of strict includes found on the deps of given target."""
    depsets = []
    for dep in _collect_dependencies(rule_attr, "deps"):
        if ObjcInfo in dep:
            objc = dep[ObjcInfo]
            if hasattr(objc, "strict_include"):
                depsets.append(objc.strict_include)
    return depset(transitive = depsets)

# TODO(b/64490743): Add these files to the Xcode project.
def _collect_swift_header(target):
    """Returns a depset of Swift generated headers found on the given target."""

    # swift_* targets put the generated header into CcInfo.
    if SwiftInfo in target and CcInfo in target:
        return target[CcInfo].compilation_context.headers
    return depset()

def collect_swift_version(copts):
    """Returns the value of the `-swift-version` argument, if found.

    Args:
        copts: The list of copts to be scanned.

    Returns:
        The value of the `-swift-version` argument, or None if it was not found
        in the copt list.
    """

    # Note that the argument can occur multiple times, and the last one wins.
    last_swift_version = None

    count = len(copts)
    for i in range(count):
        copt = copts[i]
        if copt == "-swift-version" and i + 1 < count:
            last_swift_version = copts[i + 1]

    return last_swift_version

def _target_filtering_info(ctx):
    """Returns filtering information for test rules."""
    rule = ctx.rule

    # TODO(b/72406542): Clean this up to use a test provider if possible.
    if rule.kind.endswith("_test"):
        # Note that a test's size is considered a tag for filtering purposes.
        size = _getattr_as_list(rule, "attr.size")
        tags = _getattr_as_list(rule, "attr.tags")
        return struct(tags = tags + size)
    else:
        return None

def _tulsi_sources_aspect(target, ctx):
    """Extracts information from a given rule, emitting it as a JSON struct."""
    rule = ctx.rule
    target_kind = rule.kind
    attrs = attrs_for_target_kind(ctx.rule.kind)
    rule_attr = _get_opt_attr(rule, "attr")
    filter = _filter_for_rule(rule)

    transitive_info_files = []
    transitive_attributes = dict()
    for attr_name in attrs:
        deps = _collect_dependencies(rule_attr, attr_name)
        for dep in _filter_deps(filter, deps):
            if TulsiSourcesAspectInfo in dep:
                transitive_info_files.append(dep[TulsiSourcesAspectInfo].transitive_info_files)
                transitive_attributes.update(dep[TulsiSourcesAspectInfo].transitive_attributes)

    artifacts = _get_opt_attr(target, "files")
    if artifacts:
        # Ignore any generated Xcode projects as they are not useful to Tulsi.
        artifacts = [
            _file_metadata(f)
            for f in artifacts.to_list()
            if not f.short_path.endswith("project.pbxproj")
        ]
    else:
        # artifacts may be an empty set type, in which case it must be explicitly
        # set to None to allow Skylark's serialization to work.
        artifacts = None

    srcs = (_collect_files(rule, "attr.srcs") +
            _collect_files(rule, "attr.hdrs") +
            _collect_files(rule, "attr.textual_hdrs"))
    generated_files = []
    generated_non_arc_files = []
    if target_kind in _SOURCE_GENERATING_RULES:
        generated_files = _extract_generated_sources(target)
    elif target_kind in _NON_ARC_SOURCE_GENERATING_RULES:
        generated_non_arc_files = _extract_generated_sources(target)

    is_swift_target = _is_swift_target(target)

    if is_swift_target:
        clang_modules = _collect_clang_modules(target)
        swift_transitive_modules = depset([_file_metadata(f) for f in _collect_swift_modules(target)])
        objc_module_maps = depset([_file_metadata(f) for f in clang_modules.module_maps])
    else:
        swift_transitive_modules = depset()
        objc_module_maps = depset()

    # Collect the dependencies of this rule, dropping any .jar files (which may be
    # created as artifacts of java/j2objc rules).
    dep_labels = _collect_dependency_labels(rule, filter, attrs)
    compile_deps = [str(d) for d in dep_labels if not d.name.endswith(".jar")]

    supporting_files = (_collect_supporting_files(rule_attr) +
                        _collect_asset_catalogs(rule_attr) +
                        _collect_bundle_imports(rule_attr))

    copts_attr = _get_opt_attr(rule_attr, "copts")
    is_swift_library = target_kind == "swift_library"

    datamodels = _collect_xcdatamodeld_files(rule_attr, "datamodels")
    datamodels.extend(_collect_xcdatamodeld_files(rule_attr, "data"))

    # Keys for attribute and inheritable_attributes keys must be kept in sync
    # with defines in Tulsi's RuleEntry.
    attributes = _dict_omitting_none(
        copts = None if is_swift_library else copts_attr,
        swiftc_opts = copts_attr if is_swift_library else None,
        datamodels = datamodels,
        supporting_files = supporting_files,
        test_host = _get_label_attr(rule_attr, "test_host.label"),
    )

    # Inheritable attributes are pulled up through dependencies of type 'binary'
    # to simplify handling in Tulsi (so it appears as though bridging_header is
    # defined on an ios_application rather than its associated objc_binary, for
    # example).
    inheritable_attributes = _dict_omitting_none(
        bridging_header = _collect_first_file(rule_attr, "bridging_header"),
        compiler_defines = _extract_compiler_defines(ctx),
        enable_modules = _get_opt_attr(rule_attr, "enable_modules"),
        launch_storyboard = _collect_first_file(rule_attr, "launch_storyboard"),
        pch = _collect_first_file(rule_attr, "pch"),
    )

    # Collect extensions for bundled targets.
    extensions = []
    if AppleBundleInfo in target:
        extensions = [str(t.label) for t in _getattr_as_list(rule_attr, "extensions")]

    # Tulsi considers WatchOS apps and extensions as an "extension"
    if target_kind == "watchos_application":
        watch_ext = _get_label_attr(rule_attr, "extension.label")
        extensions.append(watch_ext)
    if target_kind == "ios_application":
        watch_app = _get_label_attr(rule_attr, "watch_application.label")
        if watch_app:
            extensions.append(watch_app)

    # Collect app clips for iOS app targets
    app_clips = None
    if IosApplicationBundleInfo in target:
        app_clips = [str(t.label) for t in _getattr_as_list(rule_attr, "app_clips")]

    # Record the Xcode version used for all targets, although it will only be used by bazel_build.py
    # for targets that are buildable in the xcodeproj.
    xcode_version = _get_xcode_version(ctx)

    # Collect bundle related information and Xcode version only for runnable targets.
    if AppleBundleInfo in target:
        apple_bundle_provider = target[AppleBundleInfo]

        bundle_name = apple_bundle_provider.bundle_name
        bundle_id = apple_bundle_provider.bundle_id
        product_type = apple_bundle_provider.product_type

        # We only need the infoplist from iOS extension targets.
        infoplist = apple_bundle_provider.infoplist if IosExtensionBundleInfo in target else None
    else:
        bundle_name = None
        product_type = None
        infoplist = None

        # For macos_command_line_application, which does not have a
        # AppleBundleInfo provider but does have a bundle_id attribute for use
        # in the Info.plist.
        if target_kind == "macos_command_line_application":
            bundle_id = _get_opt_attr(rule_attr, "bundle_id")
        else:
            bundle_id = None

    # Collect Swift related attributes.
    swift_defines = []

    if is_swift_target:
        attributes["has_swift_info"] = True
        swift_version = collect_swift_version(copts_attr) if is_swift_library else None
        transitive_attributes["swift_language_version"] = swift_version
        transitive_attributes["has_swift_dependency"] = True
        defines = {}
        for module in target[SwiftInfo].transitive_modules.to_list():
            swift_module = module.swift
            if swift_module and swift_module.defines:
                for x in swift_module.defines:
                    defines[x] = None
        swift_defines = defines.keys()

    all_attributes = dict(attributes)
    all_attributes.update(inheritable_attributes)
    all_attributes.update(transitive_attributes)

    objc_strict_includes = _collect_objc_strict_includes(target, rule_attr)

    cc_provider = _get_opt_provider(target, CcInfo)
    objc_defines = []

    if cc_provider:
        cc_ctx = cc_provider.compilation_context
        includes_depsets = [
            objc_strict_includes,
            cc_ctx.includes,
            cc_ctx.quote_includes,
            cc_ctx.system_includes,
        ]
    else:
        includes_depsets = [objc_strict_includes]

    if includes_depsets:
        # Use a depset here to remove duplicates which is possible since
        # converting the output path can strip some path information.
        target_includes = depset([
            _convert_outpath_to_symlink_path(x)
            for x in depset(transitive = includes_depsets).to_list()
        ]).to_list()
    else:
        target_includes = []

    if cc_provider:
        objc_defines = cc_provider.compilation_context.defines.to_list()

    platform_type, os_deployment_target = _get_deployment_info(target, ctx)
    non_arc_srcs = _collect_files(rule, "attr.non_arc_srcs")

    # Collect test information.
    if AppleTestInfo in target:
        provider = target[AppleTestInfo]
        srcs = _depset_to_file_metadata_list(provider.sources)
        non_arc_srcs = _depset_to_file_metadata_list(provider.non_arc_sources)
        target_includes = [_convert_outpath_to_symlink_path(x) for x in provider.includes.to_list()]
        swift_transitive_modules = _depset_to_file_metadata_list(provider.swift_modules)
        objc_module_maps = _depset_to_file_metadata_list(provider.module_maps)
        test_deps = provider.deps.to_list()
        module_name = provider.module_name
    else:
        swift_transitive_modules = swift_transitive_modules.to_list()
        objc_module_maps = objc_module_maps.to_list()
        test_deps = None
        module_name = None

    info = _struct_omitting_none(
        artifacts = artifacts,
        attr = _struct_omitting_none(**all_attributes),
        build_file = ctx.build_file_path,
        bundle_id = bundle_id,
        bundle_name = bundle_name,
        objc_defines = objc_defines,
        swift_defines = swift_defines,
        deps = compile_deps,
        test_deps = test_deps,
        extensions = extensions,
        app_clips = app_clips,
        framework_imports = _collect_framework_imports(rule_attr),
        generated_files = generated_files,
        generated_non_arc_files = generated_non_arc_files,
        includes = target_includes,
        os_deployment_target = os_deployment_target,
        label = str(target.label),
        non_arc_srcs = non_arc_srcs,
        secondary_product_artifacts = _collect_secondary_artifacts(target, ctx),
        srcs = srcs,
        swift_transitive_modules = swift_transitive_modules,
        objc_module_maps = objc_module_maps,
        module_name = module_name,
        type = target_kind,
        infoplist = infoplist.path if infoplist else None,
        platform_type = platform_type,
        product_type = product_type,
        xcode_version = xcode_version,
    )

    # Create an action to write out this target's info.
    output = ctx.actions.declare_file(target.label.name + ".tulsiinfo")
    ctx.actions.write(output, info.to_json())
    output_files = [output]

    if infoplist:
        output_files.append(infoplist)

    info_files = depset(output_files, transitive = transitive_info_files)
    artifacts_depset = depset(artifacts) if artifacts else depset()

    return [
        OutputGroupInfo(tulsi_info = info_files),
        TulsiSourcesAspectInfo(
            transitive_info_files = info_files,
            inheritable_attributes = inheritable_attributes,
            transitive_attributes = transitive_attributes,
            artifacts = artifacts_depset,
            filtering_info = _target_filtering_info(ctx),
        ),
    ]

def _bundle_dsym_path(apple_bundle):
    """Compute the dSYM path for the bundle.

    Due to b/110264170 dSYMs are not fully exposed via a provider. We instead
    rely on the fact that `rules_apple` puts them next to the bundle just like
    Xcode.
    """
    bin_path = apple_bundle.archive.dirname
    dsym_name = apple_bundle.bundle_name + apple_bundle.bundle_extension + ".dSYM"
    return bin_path + "/" + dsym_name

def _collect_bundle_info(target):
    """Returns Apple bundle info for the given target, None if not a bundle."""
    if AppleBundleInfo in target:
        apple_bundle = target[AppleBundleInfo]
        has_dsym = _has_dsym(target)
        return struct(
            archive_root = apple_bundle.archive_root,
            dsym_path = _bundle_dsym_path(apple_bundle),
            bundle_name = apple_bundle.bundle_name,
            bundle_extension = apple_bundle.bundle_extension,
            has_dsym = has_dsym,
        )

    return None

def _has_dsym(target):
    """Returns True if the given target provides dSYM, otherwise False."""
    if apple_common.AppleDebugOutputs in target:
        debug_outputs_provider = target[apple_common.AppleDebugOutputs]
        outputs_map = debug_outputs_provider.outputs_map
        for _, arch_outputs in outputs_map.items():
            if "dsym_binary" in arch_outputs:
                return True
    return False

# Due to b/71744111 we have to manually re-create tag filtering for test_suite
# rules.
def _tags_conform_to_filter(tags, filter):
    """Mirrors Bazel tag filtering for test_suites.

    This makes sure that the target has all of the required tags and none of
    the excluded tags before we include them within a test_suite.

    For more information on filtering inside Bazel, see
    com.google.devtools.build.lib.packages.TestTargetUtils.java.

    Args:
      tags: all of the tags for the test target
      filter: a struct containing excluded_tags and required_tags

    Returns:
      True if this target passes the filter and False otherwise.

    """

    # None of the excluded tags can be present.
    for exclude in filter.excluded_tags:
        if exclude in tags:
            return False

    # All of the required tags must be present.
    for required in filter.required_tags:
        if required not in tags:
            return False

    # All filters have been satisfied.
    return True

def _filter_for_rule(rule):
    """Returns a filter for test_suite rules and None for other rules."""
    if rule.kind != "test_suite":
        return None

    excluded_tags = []
    required_tags = []

    tags = _getattr_as_list(rule, "attr.tags")

    for tag in tags:
        if tag.startswith("-"):
            excluded_tags.append(tag[1:])
        elif tag.startswith("+"):
            required_tags.append(tag[1:])
        elif tag == "manual":
            # The manual tag is treated specially; it is ignored for filters.
            continue
        else:
            required_tags.append(tag)
    return struct(
        excluded_tags = excluded_tags,
        required_tags = required_tags,
    )

def _filter_deps(filter, deps):
    """Filters dep targets based on tags."""
    if not filter:
        return deps

    kept_deps = []
    for dep in deps:
        info = None
        if TulsiSourcesAspectInfo in dep:
            info = dep[TulsiSourcesAspectInfo].filtering_info

        # Only attempt to filter targets that support filtering.
        # test_suites in a test_suite are not filtered, but their
        # tests are.
        if not info or _tags_conform_to_filter(info.tags, filter):
            kept_deps.append(dep)
    return kept_deps

def _tulsi_outputs_aspect(target, ctx):
    """Collects outputs of each build invocation."""

    rule = ctx.rule
    target_kind = rule.kind
    attrs = attrs_for_target_kind(ctx.rule.kind)
    rule_attr = _get_opt_attr(rule, "attr")
    transitive_generated_files = []

    # A collective list of bundle infos that has been gathered by each dependency of this target.
    # We intentionally do not collect info about _current_ target to exclude the
    # root target, which will be covered by other structs in this aspect, from the
    # list.
    transitive_embedded_bundles = []

    # A list of bundle infos corresponding to the dependencies of this target.
    direct_embedded_bundles = []

    # A list of all explicit modules that have been built from this targets dependencies.
    transitive_explicit_modules = []

    for attr_name in attrs:
        deps = _collect_dependencies(rule_attr, attr_name)
        for dep in deps:
            if TulsiOutputAspectInfo in dep:
                transitive_generated_files.append(dep[TulsiOutputAspectInfo].transitive_generated_files)
                transitive_embedded_bundles.append(dep[TulsiOutputAspectInfo].transitive_embedded_bundles)
                transitive_explicit_modules.append(dep[TulsiOutputAspectInfo].transitive_explicit_modules)

            # Retrieve the bundle info for embeddable attributes.
            if attr_name not in _TULSI_NON_EMBEDDEDABLE_ATTRS:
                dep_bundle_info = _collect_bundle_info(dep)
                if dep_bundle_info:
                    direct_embedded_bundles.append(dep_bundle_info)

    embedded_bundles = depset(direct_embedded_bundles, transitive = transitive_embedded_bundles)

    artifact = None
    dsym_path = None
    bundle_name = None
    archive_root = None
    infoplist = None
    if AppleBundleInfo in target:
        bundle_info = target[AppleBundleInfo]

        artifact = bundle_info.archive.path
        dsym_path = _bundle_dsym_path(bundle_info)
        archive_root = bundle_info.archive_root
        infoplist = bundle_info.infoplist

        bundle_name = bundle_info.bundle_name
    elif AppleBinaryInfo in target:
        # Support for non-bundled binary targets such as
        # `macos_command_line_application`. These still have dSYMs support and
        # should be located next to the binary.
        artifact = target[AppleBinaryInfo].binary.path
        dsym_path = artifact + ".dSYM"
    elif (target_kind == "cc_binary" or target_kind == "cc_test"):
        # Special support for cc_* targets which do not have AppleBinaryInfo or
        # AppleBundleInfo providers.
        #
        # At the moment these don't have support for dSYMs (b/124859331), but
        # in case they do in the future we filter out the dSYM files.
        artifacts = [
            x
            for x in target.files.to_list()
            if x.extension == "" and
               "Contents/Resources/DWARF" not in x.path
        ]
        if len(artifacts) > 0:
            artifact = artifacts[0].path
    else:
        # Special support for *_library targets, which Tulsi allows building at
        # the top-level.
        artifacts = [
            x
            for x in target.files.to_list()
            if x.extension == "a"
        ]
        if len(artifacts) > 0:
            artifact = artifacts[0].path

    # Collect generated files for bazel_build.py to copy under Tulsi root.
    all_files_depsets = []
    if target_kind in _SOURCE_GENERATING_RULES + _NON_ARC_SOURCE_GENERATING_RULES:
        objc_provider = _get_opt_provider(target, ObjcInfo)
        if hasattr(objc_provider, "source"):
            all_files_depsets.append(objc_provider.source)
        cc_info = _get_opt_provider(target, CcInfo)
        if cc_info:
            all_files_depsets.append(cc_info.compilation_context.headers)

    clang_modules = _collect_clang_modules(target)
    if _is_swift_target(target):
        all_files_depsets.append(_collect_swift_header(target))
        all_files_depsets.append(depset(_collect_swift_modules(target)))
        all_files_depsets.append(depset(clang_modules.module_maps))

    source_files = [
        x
        for x in target.files.to_list()
        if x.extension.lower() in _GENERATED_SOURCE_FILE_EXTENSIONS
    ]
    if infoplist:
        source_files.append(infoplist)

    source_files.extend(_collect_artifacts(rule, "attr.srcs"))
    source_files.extend(_collect_artifacts(rule, "attr.hdrs"))
    source_files.extend(_collect_artifacts(rule, "attr.textual_hdrs"))
    source_files.extend(_collect_supporting_files(rule_attr, convert_to_metadata = False))

    all_files = depset(source_files, transitive = all_files_depsets)

    generated_files = depset(
        [x for x in all_files.to_list() if not x.is_source],
        transitive = transitive_generated_files,
    )

    explicit_modules = depset([
        struct(name = m.name, path = m.module.path)
        for m in clang_modules.precompiled_modules
    ], transitive = transitive_explicit_modules)

    has_dsym = _has_dsym(target)

    info = _struct_omitting_none(
        artifact = artifact,
        archive_root = archive_root,
        dsym_path = dsym_path,
        generated_sources = [(x.path, x.short_path) for x in generated_files.to_list()],
        bundle_name = bundle_name,
        embedded_bundles = embedded_bundles.to_list(),
        has_dsym = has_dsym,
        explicit_modules = explicit_modules.to_list(),
    )

    output = ctx.actions.declare_file(target.label.name + ".tulsiouts")
    ctx.actions.write(output, info.to_json())

    return [
        OutputGroupInfo(tulsi_outputs = [output]),
        TulsiOutputAspectInfo(
            transitive_explicit_modules = explicit_modules,
            transitive_generated_files = generated_files,
            transitive_embedded_bundles = embedded_bundles,
        ),
    ]

tulsi_sources_aspect = aspect(
    attr_aspects = TULSI_COMPILE_DEPS,
    attrs = {
        "_tulsi_xcode_config": attr.label(default = configuration_field(
            name = "xcode_config_label",
            fragment = "apple",
        )),
        "_cc_toolchain": attr.label(default = Label(
            "@bazel_tools//tools/cpp:current_cc_toolchain",
        )),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = [
        "apple",
        "cpp",
        "objc",
    ],
    implementation = _tulsi_sources_aspect,
)

# This aspect does not propagate past the top-level target because we only need
# the top target outputs.
tulsi_outputs_aspect = aspect(
    attr_aspects = TULSI_COMPILE_DEPS,
    attrs = {
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
    fragments = [
        "apple",
        "cpp",
        "objc",
    ],
    implementation = _tulsi_outputs_aspect,
)
