# Tulsi - an Xcode Project Generator For Bazel

<span style="background-color:OldLace; padding:10px">
tulsi - /ˈto͝olsē/  A kind of basil that is venerated by Hindus as a sacred
plant.
</span>

## Building and installing

1.  Open src/Tulsi.xcodeproj, and within Xcode, build the **TulsiApp** and
    **TulsiPlugin** targets.

2.  Run the **TulsiPlugin** project.

    Xcode will present a warning that the plugin is not from Apple. You need to
    tell it to go ahead and _Load Bundle_. Once the plugin is loaded, Xcode will
    now display a _Tulsi_ menu item under the File menu.

    If you accidentally hit _Skip Bundle_ in the warning above, you'll need to
    clear out the setting under `com.apple.dt.Xcode` and restart Xcode.

    For example, for Xcode 7.1:

        defaults delete com.apple.dt.Xcode DVTPlugInManagerNonApplePlugIns-Xcode-7.1

    If Xcode has flagged Tulsi as skipped, it'll just silently fail to show up
    in the Xcode UI.

3.  Select _File > Tulsi > New Tulsi Project..._ (or _Open Tulsi Project..._ if
    your team already has a shared project).

## Notes

Tulsi-generated Xcode projects use Bazel to build, rather than Xcode. This means
that many common components of an Xcode project are handled differently than you
may be used to. For example, the Info.plist file is governed entirely by BUILD
rules in Bazel and is not displayed in the Xcode UI.
It also means that changes made to your BUILD files, such as adding new library
dependencies, are incorporated automatically when building your generated
project. The only time you need to re-run Tulsi is if you want to add additional
build targets or have new source files show up in Xcode for editing.
