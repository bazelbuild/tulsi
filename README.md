# Tulsi++ - an Xcode Project Generator For Bazel

<p align="center"><img width="200" src="src/Tulsi/Assets.xcassets/AppIcon.appiconset/tulsi_plus_plus.png"></p>

<p align="center">
    <a href="https://github.com/wendyliga/tulsi-plus-plus/releases">
        <img src="https://img.shields.io/github/v/release/wendyliga/tulsi-plus-plus" alt="Latest Release" />
    </a>
    <a href="#">
        <img src="https://img.shields.io/github/license/wendyliga/tulsi-plus-plus" />
    </a>
    <a href="https://twitter.com/wendyliga">
        <img src="https://img.shields.io/badge/contact-@wendyliga-blue.svg?style=flat" alt="Twitter: @wendyliga" />
    </a>
</p>

Tulsi++ is steroid version of Tulsi with lots of improvement on UX side.

## Difference from standart Tulsi
- OTA Update 
- Improvement to support latest Xcode
- and many more

## Installing
### Download latest
Download latest `dmg` or `zip` at [release page](https://github.com/wendyliga/tulsi-plus-plus/releases)
### Build it yourself
Run `make install`. This will install Tulsi.app inside `$HOME/Applications` by default.

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

## License
```
Copyright 2021 Wendy Liga. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```