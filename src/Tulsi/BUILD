package(default_visibility = ["//:__subpackages__"])

licenses(["notice"])

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

exports_files(["Info.plist"])

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
    module_name = "Tulsi",
    resources = [":tulsi_resources"],
    tags = ["nobuilder"],
    deps = ["//src/TulsiGenerator:tulsi_generator_lib"],
)
