---
layout: default
title: Walkthrough
---

# Background

This brief walkthrough explores setting up a new Tulsi project for a team
building a hypothetical app called Albahaca which uses computer vision to
identify garden herbs.

The app team is roughly divided into two groups:

1.  An infrastructure team, working on the computer vision portion of the app
1.  A UI team, responsible for the application's user interface

The team just finished switching over to build their app with
[Bazel](https://bazel.build) and have an `ios_application` rule called
`//albahaca:Application` under the `albahaca` folder, an `objc_library` rule
called `AppLibrary` in the `albahaca/App` folder and an `objc_library` named
`Vision` in the `albahaca/Vision` folder.

Kay, the team's tech lead, is about to use Tulsi to allow her teammates to use
Xcode for development. She has read the [getting
started](/docs/gettingstarted.html) documentation and, since she's decided to
use the command-line to generate Xcode projects, knows that she has to
accomplish four steps:

1.  Creating a Tulsi project
1.  Creating Tulsi generator configs
1.  Writing up a helper script that her team may use to generate Xcode projects
1.  Checking everything into source control

# Creating a Tulsi project

Kay starts off by running Tulsi.app and clicking the "Create new project..."
button. In the resulting popup, she enters _Albahaca_ as her project name and
selects the location of her `WORKSPACE` file.

She then adds the `albahaca/BUILD` file to the Tulsi project using the "+"
button.

Kay's team uses a bazelrc file to set up their common build options, so she
switches to the "Shared options" segment and adds _--bazelrc=albahaca/bazelrc_
to the "'build startup options".

Finally, she is ready to add configs for her team, so she switches to the
"Configs" segment.

# Creating Tulsi generator configs

Kay has decided to create three configs for her team.

1.  One that includes all of the sources and targets and can be used to build
    and debug issues that cut across the UI and infrastructure layers
1.  Another for her UI team that omits the computer vision sources to reduce the
    amount of time Xcode spends indexing files
1.  A final one for her infrastructure team that leaves out the UI sources for
    the same reason

She starts off by clicking the "+" button on the "Configs" segment, saving her
Tulsi project as _Albahaca_ in the `albahaca` directory when asked.

For her first config, Kay selects her `ios_application`, _Albahaca_ and clicks
"Next." She doesn't need to set any special build options, so she skips the
options screen and goes to the source selection step. Since she wants to include
all sources, she checks the "Recursive" box for the `albahaca` directory and
clicks the "Save" button. Kay wants this to be the default config for
command-line builds, so she names it _Albahaca_ in order to match the name of
her Tulsi project.

Next up she creates the config for her UI team. Kay follows the same steps as
for the complete config but, instead of including the `albahaca` folder
recursively, she expands it and checks the "Recursive" box for the `App` folder.
This excludes the `Vision` sources and will create a smaller, more focused Xcode
project that will index faster than the full _Albahaca_ config. This time she
saves her config as _App_.

Finally, she sets up the config for her infrastructure team in the same way,
using the `Vision` folder and saving the config as _Vision_.

# Generating xcodeproj bundles from the command-line

Kay knows that the team could use the Tulsi UI to generate their project, but
her team is more comfortable with something scriptable. She decides to write a
simple wrapper for the
[generate_xcodeproj.sh](https://github.com/bazelbuild/tulsi/blob/master/src/tools/generate_xcodeproj.sh)
script in the Tulsi tools folder. She knows that the team has the
`generate_xcodeproj.sh` script in their shared `/tools/Tulsi` mount and Bazel in
`/tools/Bazel` so it'll be safe to refer to them there.

```
#!/bin/bash -eu

readonly config=${1:-Albahaca}
readonly tulsi_script="/tools/Tulsi/generate_xcodeproj.sh"

if [[ ! -d "Albahaca.tulsiproj" ]]; then
  echo "$0 must be run from the albahaca directory"
  exit 1
fi

exec "${tulsi_script}" --bazel /tools/Bazel/bazel \
    --genconfig "Albahaca.tulsiproj:${config}"
```

# Checking files into git

Kay's team are git users, so she starts off by creating a `.gitignore` file for
her project.

```
# Tulsi user-specific data.
*.tulsiconf-user

# Xcode user data.
xcuserdata
# Alternatively, if all Xcode projects in this repository are going to be Tulsi-
# generated, the entire xcodeproj bundle may be ignored by uncommenting the
# following line.
# *.xcodeproj

# Tulsi-related Bazel symlinks (which are generally self-cleaned).
tulsigen-*
```

She then adds the `Albahaca.tulsiproj` bundle and her `generate_project.sh`
script to git and submits it.

```
git add generate_xcodeproj.sh Albahaca.tulsiproj
git commit -am "Adds Tulsi project for Albahaca."
```

At this point, Kay has finished setting everything up and emails her team to let
them know that they can use `generate_project.sh` to leverage Xcode going
forward.
