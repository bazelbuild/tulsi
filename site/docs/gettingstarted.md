---
layout: default
title: Getting started
---

# How does it work?

Tulsi uses information in Bazel `BUILD` files in order to generate Xcode
projects. Tulsi projects use Bazel to compile and sign binaries, rather than
Xcode's native infrastructure. This means that the binary you use during
development will be exactly the same as the one you make via a command line
build. In addition, Tulsi projects can operate on a subset of the source files
in your project. For large projects this can mean a significant reduction in the
amount of time Xcode spends indexing files.

Tulsi's reliance on Bazel also has some interesting side effects. For instance,
Tulsi-generated projects do not include Info.plist files directly as they are
governed by the Bazel BUILD infrastructure. It also means that changes made to
your BUILD files, such as adding new library dependencies, are incorporated
automatically when building your generated project. The only time you need to
re-run Tulsi is if you want to add additional build targets or have new source
files show up in Xcode for editing.

# How do I build and install Tulsi?

Instructions can be found in the project's
[README](https://github.com/bazelbuild/tulsi#building-and-installing)

# What Bazel flags are used when building?

__Note__: this list is limited to "interesting" flags and is not necessarily
perfectly up to date. The current set of flags can be seen in the
[`bazel_build.py`
script](https://bazel.googlesource.com/tulsi/+/master/src/TulsiGenerator/Scripts/bazel_build.py)
and their operation can be retrieved from Bazel's help.

Flags used for all build modes:

*   `--cpu=$(platform)_$(arch)` - sets up predefined Bazel options for the
    architecture exposed by Xcode.
*   `--apple_platform_type=` - corresponds to the above option mostly.
*   `--xcode_version` - passes the version of Xcode that invokes the compilation
    script.

Mode dependent flags:

*   `--compilation_mode` - set to `dbg` or `opt` depending on the Xcode build
    mode (Debug or Release).

Debug mode flags:

*   `--copt` flags:
    *   `-fdebug-compilation-dir` - instructs the compiler to use the specified
        path when generating debug symbols. This allows Xcode to find source
        files when debugging Bazel-generated binaries.
*   `--objccopt` flags:
    *   `-fdebug-compilation-dir` - as above.
*   `--apple_generate_dsym` - generates dSYM bundles.

Release mode flags:

*   `--apple_generate_dsym` - generates dSYM bundles.

# How do I use it?

## The Tulsi project editor

### 1. Create a new Tulsi project

Tulsi leverages a project bundle which captures the set of Bazel packages in
your project and provides a convenient location to store shared generator
configuration files. Generator configuration files ("gen configs") capture a set
of Bazel targets to build, sources to expose in Xcode, and associated options
and are translated directly into Xcode projects by Tulsi.

The first step is to create a Tulsi project by launching the Tulsi app.

![NewProject](/images/0000_NewProject.png "New project")

Give your project a name and select the location of your Bazel WORKSPACE file,
then click "Next".

![SelectWorkspace](/images/0010_SelectWorkspace.png "Select workspace")

At this point you should see the "Packages" tab for your project. This is where
you'll add any BUILD files in your project as well as set the path to the Bazel
binary that will be used both to generate an Xcode project and to compile.

![EmptyPackages](/images/0020_EmptyPackages.png "Empty package tab")

### 2. Add BUILD files

Click on the "+" button to add your BUILD file. Repeat this step if you have
more than one BUILD file containing targets you wish to build directly. For
example, you might have one BUILD file with your `ios_application` and another
containing `ios_unit_test` rules.

![SelectBUILDFile](/images/0030_SelectBUILDFile.png "Add a BUILD file")

### 3. Set default options if applicable

Tulsi allows you to set various options that are used by the generated Xcode
project. Probably the most interesting are the "'build' options", which are used
directly by Bazel during compilation. Tulsi options may be set in two places, at
the project level (via the "Default options" tab) and on a per-gen config basis.
The values set in the "Default options" tab will be used when creating new Tulsi
gen configs and are most useful for options that will be the same for every
developer working on your project.

![DefaultOptions](/images/0040_DefaultOptions.png "Set default options")

### 4. Create project generator configs

The final step in setting up your project is to create one or more generator
configurations. A larger project might have several gen configs, perhaps one
with sources for the UI layer, another with an important supporting library,
etc... Gen configs allow you to tailor the set of sources indexed by Xcode to
your preference without needing to include every source file in order to
compile.

![EmptyConfigs](/images/0050_EmptyConfigs.png "Empty configs tab")

Clicking the "+" button will allow you to add new generator configs. Double
clicking on an existing config will allow you to edit it, and the "-" button can
be used to permanently delete previously created configs.

Note that if you haven't already saved the project, you'll be asked to do so the
first time you add a config. You can save the project pretty much wherever you
like, but you'll get the most benefit out of checking it into your source tree
so it may be shared by other developers on your team. The project bundle is
entirely shareable apart from the `tulsiconf-user` files, which contain settings
that are likely to be user specific (such as absolute paths).

![ForcedProjectSave](/images/0060_ForcedProjectSave.png "Save project")

## The Tulsi generator configuration editor

Tulsi generator configuration files are created through a simple wizard flow.

### 1. Select build targets

The first page of the config editor shows the full list of targets contained in
the BUILD files associated with the project.

![ConfigBuildTargets](/images/0070_ConfigBuildTargets.png "Config build targets")

Select one or more targets that you want to build in Xcode. For a typical
project, like the PrenotCalculator demo, you'll choose your `ios_application`
and maybe associated `ios_unit_test` targets.

![ConfigBuildTargetSelected](/images/0080_ConfigBuildTargetSelected.png "Select one or more build targets")

### 2. Set options

If you need to set any options for your config, this is the place. The option
editor will be prepopulated with the values set in the "Default options" tab in
the project, but you may modify or add anything you'd like here.

Options may be set both at a project-level (affecting all build targets)...

![ConfigProjectOptions](/images/0100_ConfigProjectOptions.png "Set options for this config")

... and a per-target level, affecting only one selected build target.
![ConfigTargetOptions](/images/0110_ConfigTargetOptions.png "Set per-target options")

To edit an option's value, click on the cell. Values may also be double clicked
in order to pop a larger editor.
![ConfigEditingProjectOption](/images/0120_ConfigEditingProjectOption.png "Example of an edited option")
![ConfigModifiedProjectOption](/images/0130_ConfigModifiedProjectOption.png "An edited option")

### 3. Select source targets

The wizard will then show the dependencies of the build targets you've selected
that contain source files. This allows you to select a working set from your
full source tree that best matches the portion of the project that you're likely
to edit. There is also a "recursive" option, which will include the selected
folder and any folder inside of it (even folders that are created after the
config). PrenotCalculator is a small enough project that it makes sense to
select all of the source targets.

![ConfigAllSourceTargetsSelected](/images/0090_ConfigAllSourceTargetsSelected.png "Select source targets")

### 4. Set the config's name if necessary

If this is a new generator config, you'll be asked to provide a name before
saving. This name is used only to differentiate configs and does not have a
direct effect on the generated Xcode project.

![ConfigSetName](/images/0140_ConfigSetName.png "Set the name of the config")

For instance, if the "PrenotCalculator" project had two configs named "Small
config" and "Full config", both would generate an Xcode bundle named
PrenotCalculator.xcodeproj.

## Generating Xcode projects

Once your project is set up, you'll want to generate an Xcode project from one
of your configs. This is done by navigating to the "Configs" tab...

![GeneratedConfig](/images/0160_GeneratedConfig.png "Project configs")

... then selecting the config to generate and pressing the "Generate" button.
![SelectedConfig](/images/0170_SelectedConfig.png "Select the config you want to generate")

Tulsi will ask you where to save the generated Xcode project...

![XcodeProjectFolderSelection](/images/0180_XcodeProjectFolderSelection.png "Choose where to generate the Xcode project")

... and will then do the actual generation. This process can take some time for
larger projects. Progress bars will be displayed so you know something
interesting is happening.

Finally, Tulsi will launch Xcode with the newly generated project file.

![XcodeProject](/images/0300_XcodeProject.png "Xcode opens with your new project")

### Tulsi-Xcode project features

Of note is the fact that the generated file does not have an Info.plist, as the
contents are entirely driven by the contents of your Bazel BUILD files.
![XcodeEmptyInfoPlist](/images/0310_XcodeEmptyInfoPlist.png "Note that there is no Info.plist")

Also, rather than associating source files with your build target, a "Run
Script" phase is generated that uses a helper script to invoke Bazel when you
build the project. This also means that the majority of the Build Settings
displayed in Xcode do not affect the build; Bazel's BUILD files are used for
more or less everything.

![XcodeRunScript](/images/0320_XcodeRunScript.png "The Run Script phase uses Bazel to build")

One or more "\_\_indexer\_" targets will also be created, this is how Tulsi
interacts with Xcode's indexer to get things like autocomplete and cmd-click
navigation to work.

# Generating Xcode projects from the command-line

Tulsi can also create Xcode projects from generator configs without launching
the Tulsi UI. There is a [helper
script](https://bazel.googlesource.com/tulsi/+/master/src/tools/generate_xcodeproj.sh)
to seek out and apply command line parameters to the Tulsi app binary.

Running this script with no arguments will print information on usage.

__Note__: the script uses mdfind by default, so Tulsi must be installed in a
Spotlight-indexed location or the `TULSI_APP` environment variable must be used.
Please see the script for details.
