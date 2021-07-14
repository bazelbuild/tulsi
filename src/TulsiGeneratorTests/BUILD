licenses(["notice"])  # Apache 2.0

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:macos.bzl", "macos_unit_test")

swift_library(
    name = "TulsiGeneratorTestsLib",
    testonly = 1,
    srcs = glob(["*.swift"]),
    deps = ["//src/TulsiGenerator:tulsi_generator_lib"],
)

macos_unit_test(
    name = "TulsiGeneratorTests",
    additional_contents = {
        "//src/tools/bazel_cache_reader": "MacOS",
        "//src/tools/module_cache_pruner": "MacOS",
    },
    minimum_os_version = "10.13",
    deps = [":TulsiGeneratorTestsLib"],
)
