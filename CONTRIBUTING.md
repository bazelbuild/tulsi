Want to contribute? Great! First, read this page (including the
[fine print](fineprint) at the end).

## Before you contribute
Before we can use your code, you must sign the
[Google Individual Contributor License Agreement]
(https://cla.developers.google.com/about/google-individual)
(CLA), which you can do online. The CLA is necessary mainly because you own the
copyright to your changes, even after your contribution becomes part of our
codebase, so we need your permission to use and distribute your code. We also
need to be sure of various other things — for instance that you'll tell us if
you know that your code infringes on other people's patents. You don't have to
sign the CLA until after you've submitted your code for review and a member has
approved it, but you must do it before we can put your code into our codebase.
Before you start working on a larger contribution, you should get in touch with
us first through the issue tracker with your idea so that we can help out and
possibly guide you. Coordinating up front makes it much easier to avoid
frustration later on.

## Code reviews
All submissions, including submissions by project members, require review. We
use Gerrit for this purpose.

To propose a patch:

1. Discuss your plan and design, getting agreement on our
   [mailing list](https://groups.google.com/forum/#!forum/tulsi-dev).
1. Prepare a git commit that implements the feature. Don't forget to add tests.
1. Create a new code review on Gerrit by running:

       $ git push https://bazel.googlesource.com/tulsi HEAD:refs/for/master

   Gerrit upload requires that you:
   * Have signed a Contributor License Agreement.
   * Have an automatically generated "Change Id" line in your commit message.
     If you haven't used Gerrit before, it will print a bash command to create
     the git hook and then you will need to run `git commit --amend` to add the
     line.
   The HTTP password required by Gerrit can be obtained from your
   [Gerrit settings page](https://bazel-review.googlesource.com/#/settings/).
   See the
   [Gerrit documentation](https://gerrit-review.googlesource.com/Documentation/user-upload.html)
   for more information about uploading changes.
1. Complete a code review with a core contributor. Amend your existing commit
   and re-push to make changes to your patch.
1. An engineer at Google will apply the patch to our internal version control
   system.
1. The patch is exported as a Git commit, at which point the Gerrit code review
   is closed.

## Code layout

Tulsi is split into several blocks.
* `Tulis/` the project editor UI. Also known as the "App."
* `TulsiGenerator/` a framework that does all of the interesting non-UI work.
* `TulsiPlugin/` the Xcode plugin used to interact with the Tulsi app. Known as
  the "Plugin."
* `TulsiShared/` code that is common between the App and Plugin.

## The fine print {fineprint}
Contributions made by corporations are covered by a different agreement than
the one above, the
[Software Grant and Corporate Contributor License Agreement]
(https://cla.developers.google.com/about/google-corporate).
