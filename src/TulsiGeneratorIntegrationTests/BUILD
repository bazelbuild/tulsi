licenses(["notice"])  # Apache 2.0

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load(":tulsi_integration_test.bzl", "tulsi_integration_test")

test_suite(
    name = "TulsiGeneratorIntegrationTests",
)

swift_library(
    name = "BazelIntegrationTestCase",
    srcs = [
        "BazelFakeWorkspace.swift",
        "BazelIntegrationTestCase.swift",
    ],
    module_name = "BazelIntegrationTestCase",
    resources = [
        "//:strings",
    ],
    deps = ["//src/TulsiGenerator:tulsi_generator_lib"],
)

tulsi_integration_test(
    name = "AspectTests",
    srcs = [
        "AspectTests.swift",
        "PlatformDependentAspectTests.swift",
    ],
)

tulsi_integration_test(
    name = "EndToEndGenerationTests",
    srcs = ["EndToEndGenerationTests.swift"],
    deps = [":EndToEndIntegrationTestCase"],
)

swift_library(
    name = "EndToEndIntegrationTestCase",
    srcs = ["EndToEndIntegrationTestCase.swift"],
    module_name = "EndToEndIntegrationTestCase",
    deps = [":BazelIntegrationTestCase"],
)

tulsi_integration_test(
    name = "PlatformDependentEndToEndGenerationTests",
    srcs = ["PlatformDependentEndToEndGenerationTests.swift"],
    deps = [":EndToEndIntegrationTestCase"],
)

tulsi_integration_test(
    name = "QueryTests",
    srcs = ["QueryTests.swift"],
)
