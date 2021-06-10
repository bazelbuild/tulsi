load("@build_bazel_rules_apple//apple:macos.bzl", "macos_command_line_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

licenses(["notice"])

package(default_visibility = ["//:__subpackages__"])

swift_library(
    name = "module_cache_pruner_lib",
    srcs = glob(["*.swift"]),
    module_name = "ModuleCachePruner",
)

# This tool handles pruning the LLDB module cache of any modules that are found in a metadata file
# that is intended to be created by a bazel aspect that collects explicit module build outputs. This
# tool is needed to avoid a crash with LLDB that occurs when the LLDB module cache contains a module
# that is also generated in a build as an explicit module.
macos_command_line_application(
    name = "module_cache_pruner",
    minimum_os_version = "10.13",
    deps = [":module_cache_pruner_lib"],
)
