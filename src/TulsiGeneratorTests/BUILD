load("@build_bazel_rules_apple//apple:macos.bzl", "macos_unit_test")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

licenses(["notice"])

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
    minimum_os_version = "11.0",
    shard_count = 5,
    deps = [":TulsiGeneratorTestsLib"],
)
