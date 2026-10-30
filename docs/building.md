# Building a patched Wine AppImage

One GitHub Actions run does everything: it compiles a Wine branch, wraps it into an
AppImage, and publishes a prerelease in this repository. Expect 40–60 minutes.
You need write access to this repository to start it.

## Before you start

1. **A patch branch exists** in
   [FaithLife-Community/wine](https://github.com/FaithLife-Community/wine).
   See [patches.md](patches.md) for which branch is current and how to make a new one.
2. **The Bootstraps artifact is fresh.** Wine is compiled inside Ubuntu chroots stored
   as the "Bootstraps" artifact of the *Bootstraps CI* workflow. It runs on the 1st
   of each month and the artifact lasts 90 days. If the build fails at "Download
   bootstraps artifact", run *Bootstraps CI* by hand first (about 3 hours).

## Running a build

Actions → **Build Wine AppImage** → *Run workflow*:

| Input | Value | Example |
|---|---|---|
| `wine_repo` | Git URL of the Wine source | `https://github.com/FaithLife-Community/wine.git` (default) |
| `wine_branch` | the patch branch | `logos-master` (default) |
| `label` | short name for this build, **no hyphens** | `logosc37cb58` |
| `wine_version` | leave empty to use the branch's `VERSION` | |

Or from the command line, with the GitHub CLI logged in as a maintainer:

```bash
gh workflow run build.yml -R FaithLife-Community/wine-appimages \
  -f wine_branch=logos-master -f label=logosc37cb58
```

### Choosing a label

The label appears in the file name and the release tag. OuDedetai splits AppImage file
names on hyphens to read the version, so the workflow refuses labels containing
hyphens. Between Wine releases, the source still reports the previous version number,
so include the upstream commit: `logosc37cb58` means the Logos patches on upstream
commit `c37cb58e`. For a build on a release tag, `logos` alone is fine
(`wine-custom_11.21_logos-x86_64.AppImage`).

## What you get

A **draft** release tagged `<version>-<label>` (for example `11.20-logosc37cb58`),
containing, in this order:

- `wine-custom_<version>_<label>-x86_64.AppImage`
- `wine-custom_<version>_<label>-x86_64.bundle.tar.xz`: the same folder as a plain
  tarball, for systems without FUSE or that dislike AppImages. Unpack anywhere and run
  `./<folder>/AppRun`.

The bare Wine tarball is kept for 30 days as the run's `wine-tarball` artifact, which
is useful for local testing. Both jobs' summary pages show the source commit, the sizes,
and the newest glibc the build needs. Wine is compiled on Ubuntu bionic so that it runs
on old distros.

Running the workflow again with the same label **replaces** that release while it is
still a draft. Once it has been published (as a prerelease or full release) the run
fails at the release step instead, so a live build can't be swapped out by accident;
pick a new label.

Drafts are visible only to maintainers, on the repository's Releases page.

The build uses `EXPERIMENTAL_WOW64=true`: a 64-bit Wine that also runs 32-bit Windows
programs without 32-bit Linux libraries. Keep it that way.

## Testing and publishing

**OuDedetai reads this repository's releases directly**, so publishing a release changes
what users get:

| Release state | What OuDedetai does with it |
|---|---|
| Draft | Nothing: invisible to users |
| Prerelease | Offered as the **beta** AppImage, but only while it's the most recently updated release in the repository |
| Full release | Becomes **Recommended** for every user: the most recently updated full release wins |

OuDedetai downloads a release's **first** file, so the AppImage must come first.
GitHub lists a release's files **by name, not upload order**, which is why the tarball
is named `….bundle.tar.xz`: it sorts after `….AppImage`. The workflow checks the order
before finishing. If you add files by hand, give them names that sort after the
AppImage's, and check the release's file list afterwards.

The steps:

1. Download the AppImage from the draft and test it with Logos (see [testing.md](testing.md)).
2. If it works, edit the draft, tick *Set as a pre-release*, add what you tested to the
   notes, and click *Publish release*. It becomes OuDedetai's beta, replacing any
   earlier beta, so let the other maintainers know.
3. Once beta users have confirmed it, edit it again and untick *Set as a pre-release*.
   That makes it Recommended for everyone.

## When a build fails

- **"Download bootstraps artifact" fails**: the artifact expired, or Bootstraps CI has
  never succeeded. Run *Bootstraps CI* by hand.
- **"Release" fails with "already published"**: a published release already has
  this tag. Run again with a new label.
- **"Check the label" fails**: the label contains a hyphen or other character that isn't
  allowed.
- **Compile error in "Build Wine"**: usually a patch that no longer fits the newer Wine.
  Fix it on its branch (see [patches.md](patches.md)), ideally after a local build.
- **"Build AppImage" fails while downloading packages**: the recipe pulls Ubuntu focal
  packages and winetricks from the internet; a mirror being down is usually temporary.
  Run it again.

## How it works

1. **Compile Wine** (`ubuntu-22.04`): unpacks the Bootstraps chroots and runs
   `build/build_wine.sh` with `CUSTOM_SRC_PATH`/`CUSTOM_SRC_BRANCH` set to the inputs.
   This clones the branch and builds it in the chroot with bubblewrap. The tarball is
   passed to the next job as an artifact.
2. **Package AppImage and release** (`ubuntu-24.04`, pinned because appimage-builder
   uses the host's apt): `appimage-builder` builds an
   AppDir from `appimage/recipe.yml` (Ubuntu focal runtime libraries, winetricks, the
   Wine build, and the `wrapper` launcher), `appimagetool` turns it into the AppImage,
   and `gh release create` uploads it to a draft release.

The recipe deliberately has no AppImage update information, so AppImage updaters can't
replace a patched build with someone else's.
