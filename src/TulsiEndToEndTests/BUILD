licenses(["notice"])  # Apache 2.0

load("//src/TulsiGeneratorIntegrationTests:tulsi_integration_test.bzl", "tulsi_integration_test")

test_suite(
    name = "TulsiEndToEndTests",
)

tulsi_integration_test(
    name = "TulsiEndToEndTest",
    size = "large",
    srcs = ["TulsiEndToEndTest.swift"],
    data = [
        "Resources/Buttons.tulsiproj",
        "//:tulsi.zip",
        "@build_bazel_rules_apple//examples/multi_platform/Buttons:all_files",
    ],
)
