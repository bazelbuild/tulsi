# PostProcessor - a utility to mutate Mach-O files for Xcode debugging.

PostProcessor is a general utility that can read and modify the various
debugging information in Mach-O binaries. Its primary intent is to shift the
sandboxed absolute paths used by Bazel to match the original source paths
understood by a Tulsi-generated Xcode project.

PostProcessor is a part of the Tulsi project (tulsi.bazel.build) and all Tulsi
licensing and contribution policies apply.
