# wine-appimages

Wine AppImages for running **Logos Bible Software** on Linux through
[OuDedetai](https://github.com/FaithLife-Community/OuDedetai).

Upstream Wine sometimes breaks Logos or runs it badly. This project builds Wine
with a small set of patches that fix those problems, packages it as an AppImage
(plus a plain tarball for distros that dislike AppImages), and publishes it as a
GitHub prerelease that OuDedetai users can test. A maintainer promotes a build
by hand once it has been tested.

## The pieces

| Repository | What it holds |
|---|---|
| [FaithLife-Community/wine](https://github.com/FaithLife-Community/wine) | Fork of Wine. `master` mirrors upstream; each patched build is a branch on top of an upstream commit. See [docs/patches.md](docs/patches.md). |
| **this repository** | Everything else: the build workflows, the build scripts, the docs, and the testing tools. Releases are published here. |

### What's in this repository

| Path | Purpose |
|---|---|
| `.github/workflows/build.yml` | **Build Wine AppImage**: compiles a Wine branch and publishes the AppImage. Run by hand. |
| `.github/workflows/bootstraps.yml` | **Bootstraps CI**: builds the Ubuntu chroots Wine is compiled in. Runs monthly. |
| `build/` | Scripts used by the workflows (`build_wine.sh`, `create_ubuntu_bootstraps.sh`) |
| `appimage/` | AppImage recipe, launcher `wrapper` and icon |
| `tools/wine-bisect.sh` | Finds which Wine commit broke something, using a swappable test from `tools/bisect-tests/`; see [docs/testing.md](docs/testing.md) |
| `docs/` | How to build, patch and test |

The build scripts and AppImage recipe came from mmtrt's Wine-Builds and WINE_AppImage
(via the temporary forks jg00dman/Wine-Builds and jg00dman/WINE_AppImage, which are no
longer needed for builds).

## Quick start

| I want to… | Read |
|---|---|
| Build an AppImage from a patch branch | [docs/building.md](docs/building.md) |
| Add a patch, or move the patches to a newer Wine | [docs/patches.md](docs/patches.md) |
| Try a build with Logos, or find which Wine commit broke Logos | [docs/testing.md](docs/testing.md) |

## Naming

AppImages are named `wine-custom_<wine version>_<label>-x86_64.AppImage`, for
example `wine-custom_11.20_logosc37cb58-x86_64.AppImage`. OuDedetai splits the
file name on hyphens to read the version, so **labels must not contain hyphens**.

When a build is from a Wine commit between releases, Wine still reports the
previous release number, so put the commit in the label (`logosc37cb58` = based
on upstream commit `c37cb58e`).

## Licences

The build scripts come from mmtrt's projects, both MIT licensed; see
[LICENSES](LICENSES). Wine itself is LGPL-2.1-or-later.
