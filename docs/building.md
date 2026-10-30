# Building a patched Wine AppImage

Building takes two GitHub Actions runs, both started by hand from the
**Actions** tab. Allow about 30–45 minutes for the first and 5–10 for the second.

> These workflows currently live in `jg00dman/Wine-Builds` and
> `jg00dman/WINE_AppImage` (see the migration status in the
> [README](../README.md)). You need write access to those repositories to run them.

## Before you start

1. **A patch branch exists** in
   [FaithLife-Community/wine](https://github.com/FaithLife-Community/wine).
   See [patches.md](patches.md) for which branch is current and how to make a new one.
2. **The Bootstraps artifact is fresh.** The Wine build compiles inside Ubuntu chroots
   stored as the "Bootstraps" artifact of the *Bootstraps CI* workflow, in the same
   repository as the Wine build. Artifacts expire after 90 days. If the build fails
   at "Download bootstraps artifact", run *Bootstraps CI* by hand first (it takes
   about 3 hours).

## Step 1: compile Wine into a tarball

In **jg00dman/Wine-Builds** → Actions → **Wine custom build** → *Run workflow*:

| Input | Value | Example |
|---|---|---|
| Branch (the "Use workflow from" dropdown) | `ci/custom-build` | |
| `wine_version` | ignored when `custom_src` is set; leave as is | |
| `custom_src` | Git URL of the Wine fork | `https://github.com/FaithLife-Community/wine.git` |
| `custom_branch` | the patch branch | `logos-master` |
| `label` | short name, **no hyphens** | `logosc37cb58` |

The run publishes a prerelease tagged `custom-<label>` containing
`wine-<version>-custom-<label>-amd64.tar.xz`. The version comes from the `VERSION`
file of the branch you built. The run's summary page shows the tarball size and the
newest glibc the build needs (it is built on Ubuntu bionic, so it runs on old distros).

The build uses `EXPERIMENTAL_WOW64=true`: a 64-bit Wine that also runs 32-bit
Windows programs without 32-bit Linux libraries. Keep it that way.

## Step 2: wrap the tarball into an AppImage

In **jg00dman/WINE_AppImage** → Actions → **Custom Wine AppImage** → *Run workflow*,
from branch `ci/custom-wine`:

| Input | Value | Example |
|---|---|---|
| `wine_builds_repo` | where step 1 published | `jg00dman/Wine-Builds` |
| `wine_builds_tag` | `custom-<label>` from step 1 | `custom-logosc37cb58` |
| `tarball` | exact file name from step 1's release | `wine-11.20-custom-logosc37cb58-amd64.tar.xz` |
| `wine_version` | version for the file name | `11.20` |
| `label` | same label, **no hyphens** | `logosc37cb58` |

This publishes a prerelease tagged `appimage-<label>` with two files:

- `wine-custom_<version>_<label>-x86_64.AppImage`
- `wine-custom_<version>_<label>-x86_64-bundled.tar.xz`: the same folder as a
  tarball. Unpack it anywhere and run `./<folder>/AppRun`; it needs no FUSE.

Running it again with the same label **replaces** that release.

## Step 3: test and promote

Test the AppImage with Logos as described in [testing.md](testing.md). When it is
good, a maintainer edits the release and unticks *Set as a pre-release*. Note in
the release text which patch branch and upstream commit it was built from.

## Doing it from the command line

With the GitHub CLI (`gh`) logged in as someone with write access:

```bash
gh workflow run wine-custom.yml -R jg00dman/Wine-Builds --ref ci/custom-build \
  -f wine_version=11.20 \
  -f custom_src=https://github.com/FaithLife-Community/wine.git \
  -f custom_branch=logos-master -f label=logosc37cb58

# when that finishes:
gh workflow run custom.yml -R jg00dman/WINE_AppImage --ref ci/custom-wine \
  -f wine_builds_repo=jg00dman/Wine-Builds -f wine_builds_tag=custom-logosc37cb58 \
  -f tarball=wine-11.20-custom-logosc37cb58-amd64.tar.xz \
  -f wine_version=11.20 -f label=logosc37cb58
```

## When a build fails

- **"Download bootstraps artifact" fails**: the artifact expired. Run *Bootstraps CI*.
- **Compile error**: usually a patch that no longer fits the newer Wine. Rebuild it
  locally (see [patches.md](patches.md)) and fix the patch on its branch.
- **AppImage step can't find the tarball**: check `wine_builds_tag` and `tarball`
  against the actual release in Wine-Builds; they must match exactly.
