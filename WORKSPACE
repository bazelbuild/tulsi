git_repository(
    name = "build_bazel_rules_apple",
    remote = "https://github.com/bazelbuild/rules_apple.git",
    tag = "0.8.0",
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

http_file(
    name = "xctestrunner",
    executable = 1,
    url = "https://github.com/google/xctestrunner/releases/download/0.2.2/ios_test_runner.par",
)
