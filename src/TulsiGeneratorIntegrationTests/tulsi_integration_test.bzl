""" Macro for Tulsi integration tests.
"""

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:macos.bzl", "macos_unit_test")

def tulsi_integration_test(
        name,
        srcs,
        data = None,
        deps = None,
        **kwargs):
    lib_name = "%s_lib" % name

    swift_library(
        name = lib_name,
        srcs = srcs,
        testonly = 1,
        deps = [
            "//src/TulsiGeneratorIntegrationTests:BazelIntegrationTestCase",
            "//src/TulsiGenerator:tulsi_generator_lib",
        ] + (deps or []),
    )

    macos_unit_test(
        name = name,
        minimum_os_version = "10.13",
        deps = [":%s" % lib_name],
        data = [
            "//:for_bazel_tests",
            "//src/TulsiGeneratorIntegrationTests/Resources",
        ] + (data or []),
        **kwargs
    )
