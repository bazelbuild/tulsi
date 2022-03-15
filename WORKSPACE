load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# Using a newer revision of rules_apple to work around the drop of
# `should_lipo` in `apple_common.link_multi_arch_binary`.
# TODO: Switch back to a release once rules_apple gets a new release
http_archive(
    name = "build_bazel_rules_apple",
    sha256 = "1c883b02ac84abe42eb6e9ee0b99aa7f1bad8e1ebda5b2143d6d8cb2014ea4be",
    strip_prefix = "rules_apple-2efc349db20823fc64f1487d80943aceee2a6195",
    url = "https://github.com/bazelbuild/rules_apple/archive/2efc349db20823fc64f1487d80943aceee2a6195.tar.gz",
)

load(
    "@build_bazel_rules_apple//apple:repositories.bzl",
    "apple_rules_dependencies",
)

apple_rules_dependencies()

# @build_bazel_rule_swift is already defined via apple_rules_dependencies above.
# This helps ensure that Tulsi, rules_apple, etc. are using the same versions.
load(
    "@build_bazel_rules_swift//swift:repositories.bzl",
    "swift_rules_dependencies",
)

swift_rules_dependencies()

# @build_bazel_apple_support is already defined via apple_rules_dependencies above.
# This helps ensure that Tulsi, rules_apple, etc. are using the same versions.
load(
    "@build_bazel_apple_support//lib:repositories.bzl",
    "apple_support_dependencies",
)

apple_support_dependencies()

load("@bazel_skylib//lib:versions.bzl", "versions")

versions.check(minimum_bazel_version = "5.0.0")
