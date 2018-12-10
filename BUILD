# Description:
#   Tulsi, an Xcode project generator for Bazel-bazed projects.

package(default_visibility = ["//:__subpackages__"])

licenses(["notice"])  # Apache 2.0

exports_files(["LICENSE"])

load(
    ":version.bzl",
    "fill_info_plist",
    "TULSI_VERSION_MAJOR",
)
load("@build_bazel_rules_apple//apple:versioning.bzl", "apple_bundle_version")

fill_info_plist(
    name = "info_plist",
    out = "Info.plist",
    template = "//src/Tulsi:Info.plist",
)

apple_bundle_version(
    name = "AppVersion",
    build_label_pattern = "{project}_{date}_[A-Za-z]*{buildnum}",
    build_version = "%s.{date}.{buildnum}" % TULSI_VERSION_MAJOR,
    capture_groups = {
        "project": "[^_]*",
        "date": "\d+",
        "buildnum": "\d+",
    },
    fallback_build_label = "tulsi_999999999_build88",
)

genrule(
    name = "combine_strings",
    srcs = [
        "//src/Tulsi:en.lproj/Localizable.strings",
        "//src/TulsiGenerator:en.lproj/Localizable.strings",
    ],
    outs = [
        "en.lproj/Localizable.strings",
    ],
    cmd = (
        "cat $(location //src/Tulsi:en.lproj/Localizable.strings) > $(location en.lproj/Localizable.strings); " +
        "echo '\n\n' >> $(location en.lproj/Localizable.strings); " +
        "cat $(location //src/TulsiGenerator:en.lproj/Localizable.strings) >> $(location en.lproj/Localizable.strings); "
    ),
)

filegroup(
    name = "strings",
    srcs = [
        "en.lproj/Localizable.strings",
        "//src/TulsiGenerator:en.lproj/Options.strings",
    ],
)

load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")

macos_application(
    name = "tulsi",
    app_icons = ["//src/Tulsi:Icon"],
    bundle_id = "com.google.Tulsi",
    bundle_name = "Tulsi",
    infoplists = [":Info.plist"],
    minimum_os_version = "10.13",
    strings = [":strings"],
    version = ":AppVersion",
    deps = [
        "//src/Tulsi:tulsi_lib",
    ],
)

test_suite(
    name = "tests",
    tests = [
        "//src/TulsiGeneratorIntegrationTests",
        "//src/TulsiGeneratorTests",
    ],
)

filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = [
        "WORKSPACE",
        "@build_bazel_rules_apple//:for_bazel_tests",
    ],
)
