Want to contribute? Great! First, read this page (including the
fine print at the end).

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
All submissions, including submissions by project members, require review.

Tulsi is developed internally with our own version control system and then
pushed out externally to Gerrit and GitHub using Copybara.

We prefer contributors send PRs on [GitHub](https://github.com/bazelbuild/tulsi)
instead of code reviews on [Gerrit](https://bazel.googlesource.com/tulsi).

Instructions to contribute via a GitHub PR:

1. Prepare a git commit for your change. Don't forget to add tests.
1. Create a PR as you would normally on GitHub (push your commit to a fork and
   then open a PR against Tulsi from there).
1. You may need to sign a `Contributor License Agreement (CLA)` if you haven't
   already. If so, `googlebot` will comment on the PR and give you instructions
   on how to do so. Follow them and you should see a `cla: yes` tag added to the
   PR.
1. Complete a code review with a core contributor. Amend your existing commit
   and re-push to make changes to your patch.
1. When the PR is accepted, an engineer at Google will apply the patch to our
   internal version control system.
1. The patch will be exported as a Git commit, at which point the GitHub PR will
   be closed.

## Code layout

Tulsi is split into several components.
* `Tulsi/` the project editor UI and CLI. Also known as the "Tulsi App"
* `TulsiEndToEndTests/` contains tests that verify Tulsi end to end including
   Xcodeproj generation and running/testing schemes in the generated Xcodeproj.
   Like the `TulsiGeneratorIntegrationTests`, these tests themselves invoke
   Bazel. Note: These tests only work internally, they should be OK to ignore
   unless you modify the test handling in `TulsiGeneratorIntegrationTests`.
* `TulsiGenerator/` a framework that does all of the interesting non-UI work,
   including invoking Bazel to fetch project information and creating an
   Xcodeproj in memory.
* `TulsiGeneratorIntegrationTests/` contains tests that verify Xcodeproj
   generation using golden xcodeprojs. These are a bit tricky and heavy-handed
   since the tests themselves need to run Bazel using a fake WORKSPACE.
* `tools/` contains helper scripts and binaries.

## The fine print
Contributions made by corporations are covered by a different agreement than
the one above, the
[Software Grant and Corporate Contributor License Agreement]
(https://cla.developers.google.com/about/google-corporate).
