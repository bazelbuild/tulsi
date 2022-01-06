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
    data = ["//:strings"],
    module_name = "BazelIntegrationTestCase",
    visibility = ["//:__subpackages__"],
    deps = ["//src/TulsiGenerator:tulsi_generator_lib"],
)

tulsi_integration_test(
    name = "AspectTests",
    timeout = "long",
    srcs = [
        "AspectTests.swift",
        "PlatformDependentAspectTests.swift",
    ],
)

tulsi_integration_test(
    name = "EndToEndGenerationTests",
    timeout = "eternal",
    srcs = ["EndToEndGenerationTests.swift"],
    env = {
        "SWIFT_DETERMINISTIC_HASHING": "1",
    },
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
    timeout = "long",
    srcs = ["PlatformDependentEndToEndGenerationTests.swift"],
    env = {
        "SWIFT_DETERMINISTIC_HASHING": "1",
    },
    deps = [":EndToEndIntegrationTestCase"],
)

tulsi_integration_test(
    name = "QueryTests",
    srcs = ["QueryTests.swift"],
)
