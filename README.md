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
    now display an _Open BUILD..._ menu item under the File menu.

    If you accidentally hit _Skip Bundle_ in the warning above, you'll need to
    clear out the setting under `com.apple.dt.Xcode` and restart Xcode.

    For example, for Xcode 7.1:

        defaults delete com.apple.dt.Xcode DVTPlugInManagerNonApplePlugIns-Xcode-7.1

    If Xcode has flagged Tulsi as skipped, it'll just silently fail to show up
    in the Xcode UI.

3.  Select _File > Open Build..._ and select the BUILD file of your project.

    Since Tulsi-generated Xcode projects use Bazel to build, changes made to
    your BUILD file, such as adding dependencies to BUILD targets, will be
    picked up automatically. You'll only need to re-run Tulsi if you want to
    edit the newly added files or have their contents available for code
    completion.
