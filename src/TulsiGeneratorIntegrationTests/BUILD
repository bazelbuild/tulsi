load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load(":tulsi_integration_test.bzl", "tulsi_integration_test")

licenses(["notice"])

test_suite(
    name = "TulsiGeneratorIntegrationTests",
)

swift_library(
    name = "BazelIntegrationTestCase",
    testonly = 1,
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
    timeout = "eternal",
    srcs = [
        "AspectTests.swift",
        "PlatformDependentAspectTests.swift",
    ],
)

tulsi_integration_test(
    name = "EndToEndGenerationTests",
    timeout = "eternal",
    testonly = 1,
    srcs = ["EndToEndGenerationTests.swift"],
    env = {
        "SWIFT_DETERMINISTIC_HASHING": "1",
    },
    deps = [":EndToEndIntegrationTestCase"],
)

swift_library(
    name = "EndToEndIntegrationTestCase",
    testonly = 1,
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
