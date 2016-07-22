---
layout: default
title: FAQ
---

# How do I build for debug/fastbuild/release?

Tulsi generated projects behave just like Xcode projects in this respect. You
simply change the build configuration for your target scheme.

1. Open up the scheme editor. You can do this via cmd-< or through the UI.
2. Change the current build configuration in the "Info" pane.

# How do I set Bazel options for my project (like --config=awesome)?

The Tulsi options pane provides settings for flags that can be passed through to
Bazel.

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

tulsi - /ˈto͝olsē/ A kind of [basil](http://bazel.io) that is venerated by
Hindus as a sacred plant.
