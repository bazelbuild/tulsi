---
layout: default
title: FAQ
---

# How do I build for debug or release?

Tulsi generated projects behave just like Xcode projects in this respect. You
simply change the build configuration for your target scheme. Note that Tulsi
does not support Bazel's fastbuild compilation mode due to debugging
limitations.

1. Open up the scheme editor. You can do this via cmd-< or through the UI.
2. Change the current build configuration in the "Info" pane.

# I'm trying to profile my app and am getting a `permission denied` error. What's wrong?

If Instruments reports an error along the lines of

```
Target failed to run: Permission to debug <your_app_id> was denied.
The app must be signed with a development identity (e.g. iOS Developer).
```

it usually means that your entitlements are missing `get-task-allow`. To fix
this, you will want to add

```
<key>get-task-allow</key><true/>
```

to your entitlements file for builds which you do not plan to submit to Apple
for signing.

# I'm attempting to debug Objective-C projects with Xcode 8 or later and breakpoints aren't working. Why?

Xcode 8 fixes a bug preventing the use of LLDB's target.source-map setting via
`~/.lldbinit-Xcode` files. Tulsi makes use of this feature to remove the need to
inject environment-specific information into Bazel-generated binaries.

Unfortunately, the lldbinit file is parsed by Xcode once and then cached until
Xcode restarts, meaning that loading additional projects without restarting
Xcode will lead to incorrect behavior. Anytime you load a different
Tulsi-generated Xcode project and find that breakpoints no longer work, you
should close any other projects and restart Xcode in order to resolve the issue.

As background: the use of `.lldbinit` was initially an attempt to fix Swift
debugging but various other issues were discovered, necessitating the addition
of a dSYM post-processor which may someday replace Tulsi's use of lldbinit
entirely.

# How do I set Bazel options for my project (like --config=awesome)?

The Tulsi options pane provides settings for flags that can be passed through to
Bazel.

# What should I check in to source control?
As mentioned in the user guide "The project bundle is entirely shareable apart
from the `tulsiconf-user` files, which contain settings that are likely to be
user specific (such as absolute paths)."

So you'll want to `.gitignore` `.tulsiconf-user` files but otherwise the entire
`.tulsiproj` bundle is encouraged to be revision controlled and shared across
your team.

# How can I run all of my tests in a single Xcode scheme?

Tests can be grouped via Bazel's `test_suite` rule, with one small caveat. Tests
that are not xctest-based (where the `xctest` attribute is set to the
non-default `0`) must be run as standalone targets. When building the Xcode
scheme for a `test_suite` rule, Tulsi will print a warning and ignore any
non-xctest tests that are included in the suite.

# Somebody asked me for a "full Xcode build log," where do I get that?

The Tulsi build script produces a ton of interesting debugging data that isn't
shown by default in the Xcode UI. Luckily it's very simple to retrieve:

## To expand everything:

Open up the Xcode Report navigator, right click anyplace in the build log and
select "Expand All Transcripts."

## To expand one particular action:

Open up the Xcode Report navigator, scroll down to the action you'd like to
expand, and click on the expander button on the right hand side.

![Getting to the Report navigator](/images/FAQ_Expanded_Build_Log_01.png "Expanding the build log")

Once things are expanded, you can right click on the build log and select "Copy
Transcript for Shown Results" to copy everything to the pasteboard.

![After expansion](/images/FAQ_Expanded_Build_Log_02.png "After expansion")

# Somebody asked me for a simulator log, where do I get that?

Simulator logs may be retrieved via Console.app (`/Applications/Utilities`) or
by grabbing the files directly.

Generally you'll need to provide two logs, both of which may be found under
`~/Library/Logs`.

* `CoreSimulator.log`
* `<simulator ID>/system.log`

Where `<simulator ID>` is the GUID of the simulator you were using when you
encountered a problem. If you don't know the simulator ID, you can retrieve it
through the "Devices" window in Xcode (under the `Window` menu or shift+cmd+2).

# Somebody asked me for a device log, where do I get that?

Device logs may be retrieved via the Xcode "Devices" window (under the `Window`
menu or shift+cmd+2 in Xcode). If the console log is not already showing, you
can click the disclosure button on the lower right to open it.

![Opening the console log](/images/FAQ_Device_Log_01.png "Opening the console log")

# Why the name "tulsi"?

tulsi - /ˈto͝olsē/ A kind of [basil](http://bazel.build) that is venerated by
Hindus as a sacred plant.
