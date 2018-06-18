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
    ":tulsi_aspects_paths.bzl",
    "AppleBundleInfo",
    "AppleTestInfo",
    "IosExtensionBundleInfo",
    "LegacySwiftInfo",
    "SwiftInfo",
)

# List of all of the attributes that can link from a Tulsi-supported rule to a
# Tulsi-supported dependency of that rule.
# For instance, an ios_application's "binary" attribute might link to an
# objc_binary rule which in turn might have objc_library's in its "deps"
# attribute.
_TULSI_COMPILE_DEPS = [
    "binary",
    "bundles",
    "deps",
    "extension",
    "extensions",
    "frameworks",
    "settings_bundle",
    "srcs",  # To propagate down onto rules which generate source files.
    "tests",  # for test_suite when the --noexpand_test_suites flag is used.
    "_implicit_tests",  # test_suites without a `tests` attr have an '$implicit_tests' attr instead.
    "test_bundle",
    "test_host",
    # Special attribute name which serves as an escape hatch intended for custom
    # rule creators who use non-standard attribute names for rule dependencies
    # and want those dependencies to show up in Xcode.
    "tulsi_deps",
    "watch_application",
    "xctest_app",
]

# These are attributes that contain bundles but should not be considered as
# embedded bundles. For example, test bundles depend on app bundles
# to be test hosts in bazel semantics, but in reality, Xcode treats the test
# bundles as an embedded bundle of the app.
_TULSI_NON_EMBEDDEDABLE_ATTRS = [
    "test_host",
    "xctest_app",
]

# List of all attributes whose contents should resolve to "support" files; files
# that are used by Bazel to build but do not need special handling in the
# generated Xcode project. For example, Info.plist and entitlements files.
_SUPPORTING_FILE_ATTRIBUTES = [
    "app_icons",
    "entitlements",
    "infoplist",
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

# Whitelist of all extensions to include when scanning target.files for generated
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
]

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

    Tulsi root is located at WORKSPACE/bazel-exec-root-link/_tulsi-includes/x/x/.
    The two "x" directories are stubs to match the number of path components, so
    that relative paths work with the new location. Some Bazel outputs, like
    module maps, use relative paths to reference other files in the build.

    The leading underscore in _tulsi-includes is present as Bazel will clear
    all directories that don't start with '.', '_', or 'bazel-' when it builds.
    Otherwise, upon a build failure, _tulsi-includes would be removed and
    indexing and auto-completion for generated files would no longer work until
    the next successful build.

    In short, this method will transform
      bazel-out/ios-x86_64-min7.0/genfiles/foo
    to
      _tulsi-includes/x/x/foo

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
    #   _tulsi-includes/x/x/symlink[/.*]
    first_dash = path.find("-")
    components = path.split("/")
    if (len(components) > 2 and
        first_dash >= 0 and
        first_dash < len(components[0])):
        return "_tulsi-includes/x/x/" + "/".join(components[3:])
    return path

def _is_bazel_external_file(f):
    """Returns True if the given file is a Bazel external file."""
    return f.path.startswith("external/")

def _file_metadata(f):
    """Returns metadata about a given File."""
    if not f:
        return None

    # Special case handling for Bazel external files which have a path that starts
    # with 'external/' but their short_path and root.path have no mention of being
    # external.
    out_path = f.path if _is_bazel_external_file(f) else f.short_path
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

    # At the moment (Oct. 2016), Bazel disallows most files without extensions.
    # As a temporary hack, Tulsi treats File instances pointing at extension-less
    # paths as directories. This is extremely fragile and must be replaced with
    # logic properly homed in Bazel.
    is_dir = (f.basename.find(".") == -1)

    return _struct_omitting_none(
        path = out_path,
        src = f.is_source,
        root = root_execution_path_fragment,
        is_dir = is_dir,
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
    """"Converts a depset of files into a list of _file_metadata structs."""
    return [_file_metadata(f) for f in a_depset.to_list()]

def _collect_artifacts(obj, attr_path):
    """Returns a list of Artifact objects for the attr_path in obj."""
    return [
        f
        for src in _getattr_as_list(obj, attr_path)
        for f in _get_opt_attr(src, "files")
    ]

def _collect_files(obj, attr_path, convert_to_metadata = True):
    """Returns a list of artifact_location's for the attr_path in obj."""
    if convert_to_metadata:
        return [_file_metadata(f) for f in _collect_artifacts(obj, attr_path)]
    else:
        return _collect_artifacts(obj, attr_path)

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
        )
    return all_files

def _collect_bundle_paths(rule_attr, bundle_attributes, bundle_ext):
    """Extracts subpaths with the given bundle_ext for the given attributes."""
    discovered_paths = depset()
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
            discovered_paths += [full_path]

            # Generally Xcode treats bundles as special files so they should not be
            # flagged as directories.
            bundles.append(_file_metadata_by_replacing_path(f, path, False))
    return bundles

def _collect_asset_catalogs(rule_attr):
    """Extracts xcassets directories from the given rule attributes."""
    attrs = ["app_asset_catalogs", "asset_catalogs"]
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
    discovered_paths = depset()
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
        discovered_paths += [full_path]
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
        if hasattr(dep, "tulsi_info_files") or
           hasattr(dep, "tulsi_generated_files")
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
    if cpp_fragment:
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
    file_metadatas = []
    objc_provider = _get_opt_attr(target, "objc")
    if hasattr(objc_provider, "source") and hasattr(objc_provider, "header"):
        all_files = depset(objc_provider.source)
        all_files += objc_provider.header
        file_metadatas = [_file_metadata(f) for f in all_files]

    return file_metadatas

def _get_deployment_info(target, ctx):
    """Returns (platform_type, minimum_os_version) for the given target."""
    platform_type = _get_platform_type(ctx)

    if AppleBundleInfo in target:
        apple_bundle_provider = target[AppleBundleInfo]
        minimum_os_version = apple_bundle_provider.minimum_os_version
        return (platform_type, minimum_os_version)
    return (platform_type, _minimum_os_for_platform(ctx, platform_type))

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

def _collect_swift_modules(target):
    """Returns a depset of Swift modules found on the given target."""
    swift_modules = depset()
    if SwiftInfo in target:
        swift_info = target[SwiftInfo]
        for modules in _getattr_as_list(swift_info, "transitive_swiftmodules"):
            swift_modules += modules
    elif LegacySwiftInfo in target:
        swift_info = target[LegacySwiftInfo]
        for modules in _getattr_as_list(swift_info, "transitive_modules"):
            swift_modules += modules
    return swift_modules

def _collect_module_maps(target):
    """Returns a depset of Clang module maps found on the given target."""
    maps = depset()
    if LegacySwiftInfo in target or SwiftInfo in target:
        objc = target[apple_common.Objc]
        for module_maps in _getattr_as_list(objc, "module_map"):
            maps += module_maps
    return maps

# TODO(b/64490743): Add these files to the Xcode project.
def _collect_swift_header(target):
    """Returns a depset of Swift generated headers found on the given target."""
    headers = depset()

    # swift_* targets put the generated header into their objc provider HEADER
    # field.
    if ((LegacySwiftInfo in target or SwiftInfo in target) and
        apple_common.Objc in target):
        headers += target[apple_common.Objc].header
    return headers

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
    rule_attr = _get_opt_attr(rule, "attr")
    filter = _filter_for_rule(rule)

    tulsi_info_files = depset()
    transitive_attributes = dict()
    for attr_name in _TULSI_COMPILE_DEPS:
        deps = _collect_dependencies(rule_attr, attr_name)
        for dep in _filter_deps(filter, deps):
            if hasattr(dep, "tulsi_info_files"):
                tulsi_info_files += dep.tulsi_info_files
            if hasattr(dep, "transitive_attributes"):
                transitive_attributes += dep.transitive_attributes

    artifacts = _get_opt_attr(target, "files")
    if artifacts:
        # Ignore any generated Xcode projects as they are not useful to Tulsi.
        artifacts = [
            _file_metadata(f)
            for f in artifacts
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

    swift_transitive_modules = depset(
        [
            _file_metadata(f)
            for f in _collect_swift_modules(target)
        ],
    )

    # Collect ObjC module maps dependencies for Swift targets.
    objc_module_maps = depset(
        [
            _file_metadata(f)
            for f in _collect_module_maps(target)
        ],
    )

    # Collect the dependencies of this rule, dropping any .jar files (which may be
    # created as artifacts of java/j2objc rules).
    dep_labels = _collect_dependency_labels(rule, filter, _TULSI_COMPILE_DEPS)
    compile_deps = [str(d) for d in dep_labels if not d.name.endswith(".jar")]

    binary_rule = _get_opt_attr(rule_attr, "binary")
    if binary_rule and type(binary_rule) == "list":
        binary_rule = binary_rule[0]

    supporting_files = (_collect_supporting_files(rule_attr) +
                        _collect_asset_catalogs(rule_attr) +
                        _collect_bundle_imports(rule_attr))

    copts_attr = _get_opt_attr(rule_attr, "copts")
    is_swift_library = target_kind == "swift_library"

    # Keys for attribute and inheritable_attributes keys must be kept in sync
    # with defines in Tulsi's RuleEntry.
    attributes = _dict_omitting_none(
        binary = _get_label_attr(binary_rule, "label"),
        copts = None if is_swift_library else copts_attr,
        swiftc_opts = copts_attr if is_swift_library else None,
        datamodels = _collect_xcdatamodeld_files(rule_attr, "datamodels"),
        supporting_files = supporting_files,
        xctest_app = _get_label_attr(rule_attr, "xctest_app.label"),
        test_host = _get_label_attr(rule_attr, "test_host.label"),
        test_bundle = _get_label_attr(rule_attr, "test_bundle.label"),
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

    # Merge any attributes on the "binary" dependency into this container rule.
    binary_attributes = _get_opt_attr(binary_rule, "inheritable_attributes")
    if binary_attributes:
        inheritable_attributes = binary_attributes + inheritable_attributes

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

    # Collect bundle related information.
    if AppleBundleInfo in target:
        apple_bundle_provider = target[AppleBundleInfo]

        bundle_name = apple_bundle_provider.bundle_name
        bundle_id = apple_bundle_provider.bundle_id
        product_type = apple_bundle_provider.product_type

        # We only need the infoplist from iOS extension targets.
        infoplist = apple_bundle_provider.infoplist if IosExtensionBundleInfo in target else None
    else:
        bundle_name = None

        # For macos_command_line_application, which does not have a AppleBundleInfo
        # provider but does have a bundle_id attribute for use in the Info.plist.
        bundle_id = _get_opt_attr(rule_attr, "bundle_id")
        product_type = None
        infoplist = None

    # Collect Swift related attributes.
    swift_info = None
    if SwiftInfo in target:
        swift_info = target[SwiftInfo]
    elif LegacySwiftInfo in target:
        swift_info = target[LegacySwiftInfo]

    if swift_info:
        attributes["has_swift_info"] = True
        transitive_attributes["swift_language_version"] = swift_info.swift_version
        transitive_attributes["has_swift_dependency"] = True

    all_attributes = attributes + inheritable_attributes + transitive_attributes

    objc_provider = _get_opt_attr(target, "objc")
    target_includes = []
    target_defines = []
    if objc_provider:
        target_includes = [
            _convert_outpath_to_symlink_path(x)
            for x in objc_provider.include
        ]
        target_defines = objc_provider.define.to_list()

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
    else:
        swift_transitive_modules = swift_transitive_modules.to_list()
        objc_module_maps = objc_module_maps.to_list()

    info = _struct_omitting_none(
        artifacts = artifacts,
        attr = _struct_omitting_none(**all_attributes),
        build_file = ctx.build_file_path,
        bundle_id = bundle_id,
        bundle_name = bundle_name,
        defines = target_defines,
        deps = compile_deps,
        extensions = extensions,
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
        type = target_kind,
        infoplist = infoplist.basename if infoplist else None,
        platform_type = platform_type,
        product_type = product_type,
    )

    # Create an action to write out this target's info.
    output = ctx.new_file(target.label.name + ".tulsiinfo")
    ctx.file_action(output, info.to_json())
    tulsi_info_files += depset([output])

    if infoplist:
        tulsi_info_files += [infoplist]

    artifacts_depset = depset(artifacts) if artifacts else depset()

    return struct(
        # Matches the --output_groups on the bazel commandline.
        output_groups = {
            "tulsi-info": tulsi_info_files,
        },
        # The file actions used to save this rule's info and that of all of its
        # transitive dependencies.
        tulsi_info_files = tulsi_info_files,
        # The inheritable attributes of this rule, expressed as a dict instead of
        # a struct to allow easy joining.
        inheritable_attributes = inheritable_attributes,
        # Transitive info that should be applied to every rule that depends on
        # this rule.
        transitive_attributes = transitive_attributes,
        # Artifacts from this rule.
        artifacts = artifacts_depset,
        # Filtering information for this target.
        filtering_info = _target_filtering_info(ctx),
    )

def _collect_bundle_info(target):
    """Returns Apple bundle info for the given target, None if not a bundle."""
    if AppleBundleInfo in target:
        apple_bundle = target[AppleBundleInfo]
        has_dsym = (apple_common.AppleDebugOutputs in target)
        return [struct(
            archive_root = apple_bundle.archive_root,
            bundle_name = apple_bundle.bundle_name,
            bundle_extension = apple_bundle.bundle_extension,
            has_dsym = has_dsym,
        )]

    return None

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
        info = dep.filtering_info

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
    rule_attr = _get_opt_attr(rule, "attr")
    tulsi_generated_files = depset()

    # A set of all bundles embedded into this target, including deps.
    # We intentionally do not collect info about _current_ target to exclude the
    # root target, which will be covered by other structs in this aspect, from the
    # set.
    embedded_bundles = depset()

    for attr_name in _TULSI_COMPILE_DEPS:
        deps = _collect_dependencies(rule_attr, attr_name)
        for dep in deps:
            if hasattr(dep, "tulsi_generated_files"):
                tulsi_generated_files += dep.tulsi_generated_files

            # Retrieve the bundle info for embeddable attributes.
            if attr_name not in _TULSI_NON_EMBEDDEDABLE_ATTRS:
                dep_bundle_info = _collect_bundle_info(dep)
                if dep_bundle_info:
                    embedded_bundles += dep_bundle_info
            if hasattr(dep, "transitive_embedded_bundles"):
                embedded_bundles += dep.transitive_embedded_bundles

    artifact = None
    bundle_name = None
    archive_root = None
    bundle_dir = None
    infoplist = None
    if AppleBundleInfo in target:
        bundle_info = target[AppleBundleInfo]

        artifact = bundle_info.archive.path
        archive_root = bundle_info.archive_root
        infoplist = bundle_info.infoplist

        bundle_name = bundle_info.bundle_name
        bundle_dir = bundle_info.bundle_dir
    elif target_kind == "macos_command_line_application":
        # Special support for macos_command_line_application which does not have an
        # AppleBundleInfo provider.

        # Both the dSYM binary and executable binary don't have an extension, so
        # pick the first extension-less file not in a DWARF folder.
        artifacts = [
            x.path
            for x in target.files.to_list()
            if x.extension == "" and
               "Contents/Resources/DWARF" not in x.path
        ]
        if len(artifacts) > 0:
            artifact = artifacts[0]

    # Collect generated files for bazel_build.py to copy under Tulsi root.
    all_files = depset()
    if target_kind in _SOURCE_GENERATING_RULES + _NON_ARC_SOURCE_GENERATING_RULES:
        objc_provider = _get_opt_attr(target, "objc")
        if hasattr(objc_provider, "source") and hasattr(objc_provider, "header"):
            all_files += objc_provider.source
            all_files += objc_provider.header

    all_files += _collect_swift_header(target)
    all_files += _collect_swift_modules(target)
    all_files += _collect_module_maps(target)
    all_files += (_collect_artifacts(rule, "attr.srcs") +
                  _collect_artifacts(rule, "attr.hdrs") +
                  _collect_artifacts(rule, "attr.textual_hdrs"))
    all_files += _collect_supporting_files(rule_attr, convert_to_metadata = False)
    source_files = [
        x
        for x in target.files.to_list()
        if x.extension.lower() in _GENERATED_SOURCE_FILE_EXTENSIONS
    ]
    if infoplist:
        source_files.append(infoplist)
    all_files = depset(source_files, transitive = [all_files])

    tulsi_generated_files += depset(
        [x for x in all_files.to_list() if not x.is_source],
    )

    has_dsym = False
    if hasattr(ctx.fragments, "objc"):
        # Check the fragment directly, as macos_command_line_application does not
        # propagate apple_common.AppleDebugOutputs.
        has_dsym = ctx.fragments.objc.generate_dsym

    info = _struct_omitting_none(
        artifact = artifact,
        bundle_dir = bundle_dir,
        archive_root = archive_root,
        generated_sources = [(x.path, x.short_path) for x in tulsi_generated_files],
        bundle_name = bundle_name,
        embedded_bundles = embedded_bundles.to_list(),
        has_dsym = has_dsym,
    )

    output = ctx.new_file(target.label.name + ".tulsiouts")
    ctx.file_action(output, info.to_json())

    return struct(
        output_groups = {
            "tulsi-outputs": [output],
        },
        tulsi_generated_files = tulsi_generated_files,
        transitive_embedded_bundles = embedded_bundles,
    )

tulsi_sources_aspect = aspect(
    attr_aspects = _TULSI_COMPILE_DEPS,
    attrs = {
        "_tulsi_xcode_config": attr.label(default = configuration_field(
            name = "xcode_config_label",
            fragment = "apple",
        )),
    },
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
    attr_aspects = _TULSI_COMPILE_DEPS,
    fragments = [
        "apple",
        "cpp",
        "objc",
    ],
    implementation = _tulsi_outputs_aspect,
)
