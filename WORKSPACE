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
    sha256 = "653e8756001616500b110fd156694de7899278bb7480aba22b2f156438a1d810",
    url = "https://github.com/bazelbuild/rules_swift/releases/download/0.22.0/rules_swift.0.22.0.tar.gz",
)

http_archive(
    name = "build_bazel_rules_apple",
    sha256 = "0052d452af7742c8f3a4e0929763388a66403de363775db7e90adecb2ba4944b",
    url = "https://github.com/bazelbuild/rules_apple/releases/download/0.31.3/rules_apple.0.31.3.tar.gz",
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
