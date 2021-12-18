load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# TODO: Remove once https://github.com/bazelbuild/bazel-skylib/pull/307 is merged and patch is removed from rules_apple
http_archive(
    name = "io_bazel_stardoc",
    sha256 = "f89bda7b6b696c777b5cf0ba66c80d5aa97a6701977d43789a9aee319eef71e8",
    strip_prefix = "stardoc-d93ee5347e2d9c225ad315094507e018364d5a67",
    url = "https://github.com/bazelbuild/stardoc/archive/d93ee5347e2d9c225ad315094507e018364d5a67.tar.gz",
)

# TODO: Remove with next rules_swift + rules_apple release
http_archive(
    name = "build_bazel_rules_swift",
    sha256 = "fff70e28e9b28a4249fbfb413f860cb9b5df567fe20a1bc4017dd89e678dd9b5",
    strip_prefix = "rules_swift-35ddf9f6e8c0fcd8bcb521e92dd4fd11c3f181b6",
    url = "https://github.com/bazelbuild/rules_swift/archive/35ddf9f6e8c0fcd8bcb521e92dd4fd11c3f181b6.tar.gz",
)

http_archive(
    name = "build_bazel_rules_apple",
    sha256 = "2e6c88b66c671b4abb7cebc5d072804d6fc42bd18aa31586b060e2629aae7251",
    strip_prefix = "rules_apple-0bba769a9aafe9bd3349b32a326e599553886e98",
    url = "https://github.com/bazelbuild/rules_apple/archive/0bba769a9aafe9bd3349b32a326e599553886e98.tar.gz",
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
