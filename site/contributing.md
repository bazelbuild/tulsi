---
layout: default
title: Contributing to Tulsi
---

<p class="lead">We welcome contributions! This page covers setting up your
machine to develop Tulsi and, when you've made a patch, how to submit it.</p>

## How can I contribute to Tulsi?

In general, we prefer contributions that fix bugs or add features (as opposed to
stylistic, refactoring, or "cleanup" changes). Please check with us on the
[dev list](https://groups.google.com/forum/#!forum/tulsi-dev) before investing
a lot of time in a patch.

## Patch Acceptance Process

<!-- Our markdown parser doesn't support nested lists. -->
<ol>
<li>Read the <a href="governance.html">Tulsi governance plan</a>.</li>
<li>Discuss your plan and design, and get agreement on our <a href="https://groups.google.com/forum/#!forum/tulsi-dev">mailing list</a>.
<li>Prepare a git commit that implements the feature. Don't forget to add tests!
<li>Create a new code review on <a href="https://bazel-review.googlesource.com">Gerrit</a>
   by running:
   <pre>$ git push https://bazel.googlesource.com/tulsi HEAD:refs/for/master</pre>
   Gerrit upload requires that you:
   <ul>
     <li>Have signed a
       <a href="https://cla.developers.google.com">Contributor License Agreement</a>.
     <li>Have an automatically generated "Change Id" line in your commit message.
       If you haven't used Gerrit before, it will print a bash command to create
       a git hook which will generate change IDs. You will then need to run
       `git commit --amend` to add the line.
   </ul>
   The HTTP password required by Gerrit can be obtained from your
   <a href="https://bazel-review.googlesource.com/#/settings/http-password">Gerrit settings page</a>.
   See the
   <a href="https://gerrit-review.googlesource.com/Documentation/user-upload.html">Gerrit documentation</a>
   for more information about uploading changes.
<li>Complete a code review with a
   <a href="governance.html#core-contributors">core contributor</a>. Amend your existing
   commit and re-push to make changes to your patch.
<li>An engineer at Google applies the patch to our internal version control
   system.
<li>The patch is exported as a Git commit, at which point the Gerrit code review
   is closed.
</ol>

## Setting up your coding environment

Simply open up the `Tulsi.xcodeproj` in Xcode or AppCode.
