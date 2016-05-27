---
layout: default
title: FAQ
nav: faq
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

# Why the name "tulsi"?

tulsi - /ˈto͝olsē/ A kind of [basil](http://bazel.io) that is venerated by
Hindus as a sacred plant.
