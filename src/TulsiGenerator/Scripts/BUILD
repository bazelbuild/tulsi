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
    python_version = "PY3",
    srcs_version = "PY2AND3",
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
    python_version = "PY3",
    srcs_version = "PY2AND3",
    deps = [":symbol_cache_schema_lib"],
)

py_library(
    name = "symbol_cache_schema_lib",
    srcs = ["symbol_cache_schema.py"],
    srcs_version = "PY2AND3",
)

py_binary(
    name = "update_symbol_cache",
    srcs = ["update_symbol_cache.py"],
    python_version = "PY3",
    srcs_version = "PY2AND3",
    deps = [":symbol_cache_schema_lib"],
)

py_binary(
    name = "clean_symbol_cache",
    srcs = ["clean_symbol_cache.py"],
    python_version = "PY3",
    srcs_version = "PY2AND3",
    deps = [":symbol_cache_schema_lib"],
)

py_binary(
    name = "install_genfiles",
    srcs = ["install_genfiles.py"],
    python_version = "PY3",
    srcs_version = "PY2AND3",
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
    python_version = "PY3",
    srcs_version = "PY2AND3",
)

test_suite(
    name = "all_tests",
    visibility = ["//visibility:public"],
)
