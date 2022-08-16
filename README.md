# Tulsi - an Xcode Project Generator For Bazel

<span style="background-color:OldLace; padding:10px">
tulsi - /ˈto͝olsē/  A kind of basil that is venerated by Hindus as a sacred
plant.
</span>

## Building and installing

To use Tulsi, clone this repository and run `build_and_run.sh`. By default this will install the Tulsi.app inside `$HOME/Applications`. Additionally, following options are available:

* `-b`: Bazel binary that Tulsi should use to build and install the app (Default is `bazel`)
* `-d`: The folder where to install the Tulsi app into (Default is `$HOME/Applications`)
* `-x`: The Xcode version Tulsi should be built for (Default is `13.4.1`)

## Integrating into your project

If your project can be built with Bazel 5.0.0 or newer, you can integrate Tulsi
into your project.

Put the following content into your WORKSPACE file:

```
TULSI_COMMIT_HASH = "518f18da4948192c72074e07fa1dfe15858d40f4"

http_archive(
    name = "tulsi",
    url = "https://github.com/bazelbuild/tulsi/archive/{0}.tar.gz".format(TULSI_COMMIT_HASH),
    strip_prefix = "tulsi-{0}".format(TULSI_COMMIT_HASH),
    sha256 = "92c89fcabfefc313dafea1cbc96c9f68d6f2025f2436ee11f7a4e4eb640fa151",
)
```

Now you can run Tulsi with the following command:

```bash
bazel run @tulsi//:tulsi
```

You can also generate an Xcode project with the following command:

```bash
bazel run  -- @tulsi//:tulsi -- --genconfig "/path/to/your.tulsiproj:target" --outputfolder="/path/to/output"
```

Replace `"/path/to/your.tulsiproj:target` with the location of your Tulsi
project and the target you want to generate the Xcode project for. Replace the
`/path/to/output` with the directory's path where you want the generated Xcode
project to be. Both paths need to be absolute path since` bazel run` will change
the execution directory.


The `TULSI_COMMIT_HASH` is the git commit hash of the Tulsi you want to use.
When you want to update Tulsi, you can replace the value of `TULSI_COMMIT_HASH`
with the new commit hash you want. In this way, you can easily update Tulsi
across the whole team.

If you do not know the `sha256` of the new Tulsi archive you want to use, you
can remove the `sha256` attribute. Then when you do `bazel run @tulsi//:tulsi`
you will say a debug log like this:

```bash
DEBUG: Rule 'tulsi' indicated that a canonical reproducible form can be obtained by modifying arguments sha256 = "92c89fcabfefc313dafea1cbc96c9f68d6f2025f2436ee11f7a4e4eb640fa151"
```

If you trust the source, you can then use the `sha256` value in the log.


## Notes

Tulsi-generated Xcode projects use Bazel to build, **not** Xcode.  Building in
Xcode will cause it to only run a script; the script invokes Bazel to build
the configured Bazel target and copies the artifacts to where Xcode expects
them to be. This means that many common components of an Xcode project are
handled differently than you may be used to. Notable differences:

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
*   Tulsi will set some Tulsi-specific flags for `bazel` invocations, some of
    which may affect Bazel caching. In order to maximize cache re-use when
    building from the command line, try using the `user_build.py` script which
    is located in the generated xcodeproj at
    `<xcodeproj>/.tulsi/Scripts/user_build.py`.

## Tulsi project and config settings

Tulsi projects contain a few settings which control various behaviors during
project generation and builds.

*   Bazel `build` flags, customizable per compilation mode (`dbg` and `opt`)
*   Bazel `build` startup flags, also customizable per compilation mode
*   Generation platform configuration: Target platform and arch used during project
    generation.
    *   Can change from targeting iOS sim to iOS device or from iOS to macOS.
        Setting this improperly shouldn't break your project although it may
        potentially worsen generation and build performance.
*   Generation compilation mode: Bazel compilation mode (`dbg` or `opt`, no
    `fastbuild`) used during project generation.
    *   Defaults to `dbg`, swap to `opt` if you normally build Release builds in
        Xcode (i.e. profiling your app). Setting this improperly shouldn't break
        your project although it may potentially worsen generation and build
        performance.
*   Prioritize Swift: set this to inform Tulsi that it should use Swift-specific
    flags during project generation.
    *   Defaults to `No`, swap to `Yes` if your project contains Swift (even
        in its dependencies). Setting this improperly shouldn't break your
        project although it may potentially worsen generation and build
        performance.

