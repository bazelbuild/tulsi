codesign --verbose --force --deep -o runtime \
    --sign "Developer ID Application" \
    "src/Sparkle/Sparkle.framework/Versions/A/AutoUpdate"

codesign --verbose --force --deep -o runtime \
    --sign "Developer ID Application" \
    "src/Sparkle/Sparkle.framework/AutoUpdate"

codesign --verbose --force --deep -o runtime \
    --sign "Developer ID Application" \
    "src/Sparkle/Sparkle.framework/Versions/A/Updater.app"

codesign --verbose --force --deep -o runtime \
    --sign "Developer ID Application" \
    "src/Sparkle/Sparkle.framework/Updater.app"