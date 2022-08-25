licenses(["notice"])

package(default_visibility = ["//:__subpackages__"])

load("@build_bazel_rules_apple//apple:macos.bzl", "macos_command_line_application")

objc_library(
    name = "bazel_cache_reader_lib",
    srcs = ["bazel_cache_reader/main.c"],
    sdk_dylibs = [
        "libsqlite3",
    ],
)

macos_command_line_application(
    name = "bazel_cache_reader",
    minimum_os_version = "11.0",
    deps = [":bazel_cache_reader_lib"],
)
