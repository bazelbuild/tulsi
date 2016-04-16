# Tulsi - an Xcode Project Generator For Bazel

<span style="background-color:OldLace; padding:10px">
tulsi - /ˈto͝olsē/  A kind of basil that is venerated by Hindus as a sacred
plant.
</span>

## Building and installing

1.  Open src/Tulsi.xcodeproj, and within Xcode, build the **TulsiApp**.

2.  Run the **TulsiApp**.

## Notes

Tulsi-generated Xcode projects use Bazel to build, rather than Xcode. This means
that many common components of an Xcode project are handled differently than you
may be used to. For example, the Info.plist file is governed entirely by BUILD
rules in Bazel and is not displayed in the Xcode UI.
It also means that changes made to your BUILD files, such as adding new library
dependencies, are incorporated automatically when building your generated
project. The only time you need to re-run Tulsi is if you want to add additional
build targets or have new source files show up in Xcode for editing.
