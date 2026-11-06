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
| `tools/wine-bisect.sh` | Finds which Wine commit broke Logos; see [docs/testing.md](docs/testing.md) |
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

The workflow names builds by release type (see
[docs/building.md](docs/building.md#running-a-build)):

| Type | Built from | AppImage |
|---|---|---|
| release | `oinos-master` | `wine-custom_11.21_oinos-x86_64.AppImage` |
| prerelease | `oinos-prerelease` | `wine-custom_11.21_oinos-pre-a5d413a-x86_64.AppImage` |
| draft | any branch | `wine-custom_11.21_media-9ce4a22-x86_64.AppImage` |

`11.21` is the Wine version the branch is based on, and the hash is its commit. OuDedetai
reads the version from between the first two hyphens of the file name, so keep the
`wine-custom_<version>_<label>` start and **don't put hyphens in labels**.

## Licences

The build scripts come from mmtrt's projects, both MIT licensed; see
[LICENSES](LICENSES). Wine itself is LGPL-2.1-or-later.

The AppImage also bundles unmodified copies of the Liberation fonts (Sans, Serif
and Mono), Carlito and Microsoft's Selawik in Wine's font folder
(`opt/wine-devel/share/wine/fonts`), under the SIL Open Font License 1.1. Their
licences sit next to them and in [appimage/fonts](appimage/fonts). They are
metric-compatible stand-ins for Arial, Times New Roman, Courier New, Calibri and
Segoe UI. Logos's print preview needs fonts with those names, and OuDedetai maps
the Windows names onto these fonts through `HKCU\Software\Wine\Fonts\Replacements`.
Selawik comes from its 1.01 GitHub release, pinned by SHA-256.

The Wine build also bundles unmodified FFmpeg shared libraries (`libavformat`,
`libavcodec`, `libavutil`, `libswresample`) in `lib/wine/x86_64-unix`, under the
GNU LGPL 2.1 or later. The version, source link and licence text sit next to them.
