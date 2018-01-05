# Tulsi - an Xcode Project Generator For Bazel

<span style="background-color:OldLace; padding:10px">
tulsi - /ˈto͝olsē/  A kind of basil that is venerated by Hindus as a sacred
plant.
</span>

## Building and installing

1.  Open src/Tulsi.xcodeproj, and within Xcode, build the **TulsiApp**.

2.  Run the **TulsiApp**.

## Notes

Tulsi-generated Xcode projects use Bazel to build, **not** Xcode via xcbuild. This means
that many common components of an Xcode project are handled differently than you
may be used to. Notable differences:

*   **BUILD files are the source of truth**; most changes made to your Xcode project
    won't affect the build.
    *   Adding new sources to the Xcode project won't include them in your app;
        they must be added to BUILD files.
    *   Changes made to your BUILD files, such as adding new library
        dependencies, are incorporated automatically when building your
        generated project. The only time you need to re-run Tulsi is if you want
        to add additional build targets or have new source files show up in
        Xcode for editing.
    *   The Info.plist file is governed entirely by BUILD rules in Bazel and is
        not displayed in the Xcode UI.
    *   Changes to compilation flags (i.e. -DHELLO) should be made in the BUILD
        files in order to affect the build; changes made to compilation settings
        in the Xcode UI will only affect indexing. You may want to regenerate
        your project using Tulsi after modifying compilation flags.
