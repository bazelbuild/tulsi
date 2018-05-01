licenses(["notice"])  # Apache 2.0

package(default_visibility = ["//:__subpackages__"])

exports_files(
    ["WORKSPACE"],
)

genrule(
    name = "aspect_build",
    srcs = [":tulsi/aspect.BUILD"],
    outs = ["tulsi/BUILD"],
    cmd = "cp $< $@",
    visibility = ["//visibility:private"],
)

filegroup(
    name = "tulsi",
    srcs = [
        "tulsi/tulsi_aspects.bzl",
        "tulsi/tulsi_aspects_paths.bzl",
        ":aspect_build",
    ],
)
