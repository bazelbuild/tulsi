package(default_visibility = ["//:__subpackages__"])

licenses(["notice"])  # Apache 2.0

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

exports_files(
    [
        "en.lproj/Localizable.strings",
        "en.lproj/Options.strings",
    ],
)

filegroup(
    name = "tulsi_generator_srcs",
    srcs = glob(["*.swift"]),
)

filegroup(
    name = "tulsi_generator_resources",
    srcs = glob([
        "GeneratedProjectResources/*",
        "*.entitlements",
    ]) + [
        "//src/TulsiGenerator/Bazel:WORKSPACE",
        "//src/TulsiGenerator/Scripts",
    ],
)

swift_library(
    name = "tulsi_generator_lib",
    srcs = [":tulsi_generator_srcs"],
    data = [
        ":tulsi_generator_resources",
        "//src/TulsiGenerator/Bazel:tulsi",
    ],
    module_name = "TulsiGenerator",
    tags = ["nobuilder"],
)
