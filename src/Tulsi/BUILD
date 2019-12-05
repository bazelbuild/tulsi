package(default_visibility = ["//:__subpackages__"])

licenses(["notice"])

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

exports_files(["Info.plist"])

exports_files(
    ["BazelSelectionPanel.swift"],
    visibility = ["//:__subpackages__"],
)

filegroup(
    name = "Icon",
    srcs = glob(["Assets.xcassets/AppIcon.appiconset/*"]),
)

exports_files(["en.lproj/Localizable.strings"])

filegroup(
    name = "tulsi_srcs",
    srcs = glob(["*.swift"]),
)

filegroup(
    name = "tulsi_resources",
    srcs = glob(
        [
            "*.lproj/*",
            "Assets.xcassets/**/*",
        ],
        exclude = [
            "Assets.xcassets/AppIcon.appiconset/*",
            "en.lproj/Localizable.strings",
        ],
    ),
)

swift_library(
    name = "tulsi_lib",
    srcs = [":tulsi_srcs"],
    data = [":tulsi_resources"],
    module_name = "Tulsi",
    tags = ["nobuilder"],
    deps = ["//src/TulsiGenerator:tulsi_generator_lib"],
)
