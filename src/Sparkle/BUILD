load('@build_bazel_rules_apple//apple:apple.bzl', 'apple_dynamic_framework_import')

apple_dynamic_framework_import(
    name = 'Sparkle',
    framework_imports = glob(['Sparkle.framework/**']),
    visibility = ['//visibility:public']
)