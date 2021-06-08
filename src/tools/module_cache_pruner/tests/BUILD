load("@build_bazel_rules_apple//apple:macos.bzl", "macos_unit_test")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

licenses(["notice"])

package(default_visibility = ["//:__subpackages__"])

swift_library(
    name = "module_cache_pruner_tests_lib",
    testonly = 1,
    srcs = glob(["*.swift"]),
    deps = [
        "//src/tools/module_cache_pruner:module_cache_pruner_lib",
    ],
)

macos_unit_test(
    name = "module_cache_pruner_tests",
    minimum_os_version = "10.13",
    deps = [":module_cache_pruner_tests_lib"],
)
