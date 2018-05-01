# Tulsi Generator Scripts

package(default_visibility = ["//:__subpackages__"])

licenses(["notice"])

filegroup(
    name = "Scripts",
    srcs = glob(
        ["**/*"],
        exclude = [
            "BUILD",
            "**/*_tests.py",
        ],
    ),
)

py_binary(
    name = "bazel_build_events",
    srcs = ["bazel_build_events.py"],
)

py_test(
    name = "bazel_build_events_tests",
    size = "small",
    srcs = ["bazel_build_events_tests.py"],
    deps = [":bazel_build_events"],
)

py_binary(
    name = "symbol_cache_schema",
    srcs = ["symbol_cache_schema.py"],
)

py_binary(
    name = "update_symbol_cache",
    srcs = ["update_symbol_cache.py"],
    deps = [":symbol_cache_schema"],
)

py_binary(
    name = "clean_symbol_cache",
    srcs = ["clean_symbol_cache.py"],
    deps = [":symbol_cache_schema"],
)

py_binary(
    name = "install_genfiles",
    srcs = ["install_genfiles.py"],
)

py_test(
    name = "install_genfiles_tests",
    size = "small",
    srcs = ["install_genfiles_tests.py"],
    deps = [":install_genfiles"],
)

py_binary(
    name = "bootstrap_lldbinit",
    srcs = ["bootstrap_lldbinit.py"],
)

test_suite(
    name = "all_tests",
    visibility = ["//visibility:public"],
)
