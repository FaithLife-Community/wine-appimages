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
| **this repository** | The build pipeline (workflows and scripts), the docs, and the testing tools. |
| [jg00dman/Wine-Builds](https://github.com/jg00dman/Wine-Builds) *(temporary)* | Workflow that compiles Wine into a tarball. Fork of mmtrt/Wine-Builds. |
| [jg00dman/WINE_AppImage](https://github.com/jg00dman/WINE_AppImage) *(temporary)* | Workflow that wraps the tarball into an AppImage. Fork of mmtrt/WINE_AppImage. |

### Migration status

The pipeline is being moved into this repository so it no longer depends on a
personal account:

- [x] **Bootstraps CI** — builds the Ubuntu chroots that Wine is compiled in.
      Runs on the 1st of each month (the artifact expires after 90 days).
- [ ] **Wine build** — still runs in `jg00dman/Wine-Builds` (`wine-custom.yml`).
- [ ] **AppImage packaging** — still runs in `jg00dman/WINE_AppImage` (`custom.yml`).

Until the last two boxes are ticked, follow [docs/building.md](docs/building.md),
which describes the current two-step process.

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
