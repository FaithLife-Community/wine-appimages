# Building a patched Wine AppImage

One GitHub Actions run does everything: it compiles a Wine branch, wraps it into an
AppImage, and publishes a prerelease in this repository. Expect 40–60 minutes for a
first build; rebuilds after small changes are quicker thanks to the compiler cache.
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

Actions → **Build Wine AppImage** → *Run workflow*. Choose the **release type** first;
it decides which branch may be built and how the build is named:

| `release_type` | Branch | Release tag | AppImage |
|---|---|---|---|
| `release` | `oinos-master` only | `11.21-oinos` (then `11.21-oinos-2`, …) | `wine-custom_11.21_oinos-x86_64.AppImage` |
| `prerelease` | `oinos-prerelease` only | `11.21-oinos-pre-a5d413a` | `wine-custom_11.21_oinos-pre-a5d413a-x86_64.AppImage` |
| `draft` (default) | any branch or tag | `11.21-media-9ce4a22` | `wine-custom_11.21_media-9ce4a22-x86_64.AppImage` |

`11.21` is the Wine version of the branch (its `VERSION` file) and the hash is the
branch's commit. A draft is named after the last part of its branch:
`oinos-testing/media` gives `media`. `release` and `prerelease` builds must come from
FaithLife-Community/wine. The run stops before compiling if the branch doesn't fit the
type.

The other inputs are optional:

| Input | Value |
|---|---|
| `wine_branch` | the branch to build (see [patches.md](patches.md#branches)); empty = `oinos-master` or `oinos-prerelease` for those types. Drafts must name one. |
| `wine_repo` | Git URL of the Wine source (default `https://github.com/FaithLife-Community/wine.git`) |
| `label` | replaces `oinos` or the topic name in the tag and file name, **no hyphens** |
| `wine_version` | leave empty to use the branch's `VERSION` |

Or from the command line, with the GitHub CLI logged in as a maintainer:

```bash
gh workflow run build.yml -R FaithLife-Community/wine-appimages -f release_type=prerelease
gh workflow run build.yml -R FaithLife-Community/wine-appimages \
  -f release_type=draft -f wine_branch=oinos-testing/media
```

### Naming rules

OuDedetai reads the Wine version from the AppImage's file name, from between the first
two hyphens (`custom_11.21_oinos`), and compares it with the installed Wine. So the file
name must start `wine-custom_<version>_<label>`, and the label itself can't contain
hyphens; the workflow refuses such labels. Everything after the label (`-pre-…`, the
commit, `-2`) may use hyphens. OuDedetai only displays the release tag; it picks the
newest release by publication date.

## What you get

A **draft** release with the tag from the table above, containing, in this order:

- `wine-custom_<version>_<name>-x86_64.AppImage`
- `wine-custom_<version>_<name>-x86_64.tar.xz`: just the Wine folder (`bin/`, `lib/`,
  `share/` with FFmpeg and the stand-in fonts), our DXVK in `dxvk/` with
  `bin/dxvk-install` and `bin/dxvk-uninstall`, and `README.md` (the usage guide). None of
  the AppImage's runtime, wrapper or bundled tools, and compressed once. It starts
  faster than the AppImage, and is what OuDedetai's *Recommended Bundled* choice
  downloads (one top-level folder with `bin/wine`). Unpack anywhere and run
  `./<folder>/bin/wine`.

The release notes (`build/release-notes.sh`) give a download guide, the DXVK version,
a table of **every patch**: each commit on the branch that isn't on the Wine
repository's `master` (FaithLife-Community/wine's `master` mirrors upstream), merges
left out, oldest first, with links, and the usage guide from `docs/release-usage.md`.

The bare Wine tarball is kept for 30 days as the run's `wine-tarball` artifact, which
is useful for local testing. Both jobs' summary pages show the source commit, the sizes,
and the newest glibc the build needs. Wine is compiled on Ubuntu bionic so that it runs
on old distros.

Every build starts as a draft, whatever its type. A `release` draft publishes as a full
release; the others publish as prereleases.

Running the workflow again for the same tag **replaces** that release while it is
still a draft. Once it has been published, a `prerelease` or `draft` run for the same
commit fails at the release step instead, so a live build can't be swapped out by
accident. A `release` run picks the next free tag (`-2`, `-3`, …) instead.

Drafts are visible only to maintainers, on the repository's Releases page.

**FFmpeg.** The 64-bit chroot carries a minimal LGPL build of FFmpeg (demuxing
libraries only; `ffmpeg_version` in `build/create_ubuntu_bootstraps.sh`). Wine's
configure finds it, which builds `winedmo.so`, the FFmpeg-based Media Foundation source
Logos video needs. `build_wine.sh` then copies `libavformat`, `libavcodec`, `libavutil`
and `libswresample` next to `winedmo.so` in `lib/wine/x86_64-unix`, sets their RUNPATH
to `$ORIGIN` with `patchelf`, and adds `FFMPEG-README.txt` and the LGPL text there. So
the build doesn't depend on the host's FFmpeg version. It stops with an error if the
chroot has FFmpeg but `winedmo.so` wasn't linked against it. Bootstraps made before
FFmpeg was added have none, and then builds have no `winedmo.so`: run *Bootstraps CI*
again.

**DXVK.** With the `dxvk_ref` input (default `logos/combined`; empty for none), the
*Build DXVK* job builds that branch, tag or commit of
[FaithLife-Community/dxvk](https://github.com/FaithLife-Community/dxvk) the way the
fork's own *Artifacts (Package)* workflow does, and the AppImage carries it in
`opt/dxvk/` (`x64/`, `x32/`, `VERSION`, `LICENSE`). The tarball carries it in `dxvk/`. It is
**not** used until it is put into a prefix:

    WINEPREFIX=<prefix> ./wine-custom_….AppImage dxvk-install     # or <folder>/bin/dxvk-install
    WINEPREFIX=<prefix> ./wine-custom_….AppImage dxvk-uninstall   # back to Wine's own Direct3D

`dxvk-install` first runs `vk14probe.exe` (`appimage/vk14probe.c`, built in the DXVK
job) through Wine, which asks Wine's own Vulkan for a GPU with Vulkan 1.4, as DXVK needs
(Mesa 25+, NVIDIA 575+). Found: it installs d3d8/9/10core/11 and dxgi as native and exits
0. Not found: it removes any DXVK it installed before, sets
`HKCU\Software\Wine\Direct3D\renderer=gl` and exits 3. `--check` only reports;
`--force` skips the check.

For a test tool that wants a DXVK folder instead (`DXVK_DIR` in the renderer-test kit),
use the tarball's `dxvk/`, or `./wine-custom_….AppImage --appimage-extract 'opt/dxvk/*'`
(unpacks to `squashfs-root/opt/dxvk`). The release notes name the DXVK commit.

**Vulkan in the AppImage.** The AppImage doesn't bundle a Vulkan loader (the one
`vulkan-tools` pulls in from focal is too old for current drivers), and the wrapper
only sets `VK_ICD_FILENAMES` to driver files that exist.

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

1. Test patches with `draft` builds of their `oinos-testing/<topic>` branch, then merge
   them into `oinos-prerelease`.
2. Build a `prerelease`, download its AppImage from the draft and test it with Logos (see
   [testing.md](testing.md)). If it works, add what you tested to the notes and click
   *Publish release*. It becomes OuDedetai's beta, replacing any earlier beta, so let
   the other maintainers know.
3. Once beta users have confirmed it, merge `oinos-prerelease` into `oinos-master`,
   build a `release`, check it the same way and publish it. That makes it Recommended
   for everyone.

## When a build fails

- **"Download bootstraps artifact" fails**: the artifact expired, or Bootstraps CI has
  never succeeded. Run *Bootstraps CI* by hand.
- **"Release" fails with "already published"**: a published prerelease or draft-type
  build already has this tag, i.e. this commit was published before. Push a new commit,
  or run again with a different `label`.
- **"Check the branch and work out the name" fails**: the branch doesn't fit the release
  type, doesn't exist, or the label contains a hyphen or another character that isn't
  allowed. The error message says which.
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
   The compiler cache (ccache) is kept between runs with `actions/cache`, keyed by
   branch: a rebuild after a small patch only recompiles the files that changed, and a
   new branch starts from the newest cache of any branch. A cold build is slightly
   slower than without ccache. To start cold, delete the `ccache-*` entries under
   Actions → Caches. The step log ends with `ccache -s` hit statistics.
2. **Package AppImage and release** (`ubuntu-24.04`, pinned because appimage-builder
   uses the host's apt): `appimage-builder` builds an
   AppDir from `appimage/recipe.yml` (Ubuntu focal runtime libraries, winetricks, the
   Wine build, and the `wrapper` launcher), `appimagetool` turns it into the AppImage,
   and `gh release create` uploads it to a draft release.

The recipe deliberately has no AppImage update information, so AppImage updaters can't
replace a patched build with someone else's.
