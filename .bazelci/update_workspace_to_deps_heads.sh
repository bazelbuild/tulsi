#!/bin/bash

set -euo pipefail

# Modify the WORKSPACE to pull in the master branches of some deps.
/usr/bin/sed \
  -i "" \
  -e \
    's/apple_rules_dependencies()/apple_rules_dependencies(ignore_version_differences = True)/' \
  -e \
    '1i \
\
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")\
\
git_repository(\
\    name = "bazel_skylib",\
\    remote = "https://github.com/bazelbuild/bazel-skylib.git",\
\    branch = "master",\
)\
\
git_repository(\
\    name = "build_bazel_apple_support",\
\    remote = "https://github.com/bazelbuild/apple_support.git",\
\    branch = "master",\
)\
\
git_repository(\
\    name = "build_bazel_rules_swift",\
\    remote = "https://github.com/bazelbuild/rules_swift.git",\
\    branch = "master",\
)\
\
git_repository(\
\    name = "build_bazel_rules_apple",\
\    remote = "https://github.com/bazelbuild/rules_apple.git",\
\    branch = "master",\
)\
' \
  WORKSPACE

# rules_swift at HEAD changed the path of module map.
# TODO: Remove once rules_swift has a new release.
file=src/TulsiGeneratorIntegrationTests/Resources/GoldenProjects/SwiftProject.xcodeproj/project.pbxproj
/usr/bin/sed -i "" -e \
  's/[.]modulemaps\/module[.]modulemap/.swift.modulemap/' $file
# sed appends a newline at EOF; remove it.
/bin/dd if=/dev/null of=$file obs="$(($(wc -c < $file)-1))" seek=1
