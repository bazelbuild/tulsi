# CovmapPatcher - a utility to mutate LLVM coverage maps in Mach-O files.

CovmapPatcher is a small utility that can read and modify the LLVM coverage map
data used by Xcode's code coverage reporting. Its primary intent is to shift the
sandboxed absolute paths used by Bazel to match the original source paths
understood by a Tulsi-generated Xcode project.

CovmapPatcher is a part of the Tulsi project (tulsi.bazel.io) and all Tulsi
licensing and contribution policies apply.
