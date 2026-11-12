## Which file?

| File | What it is | Use it when |
|---|---|---|
| `….AppImage` | Wine, our DXVK and a small runtime in one file. | You want a single file that runs on almost any distro, including older ones. |
| `….tar.xz` | Just the Wine folder (with FFmpeg, fonts and our DXVK), compressed once. | You want Logos to start faster: no AppImage to mount on every launch. OuDedetai's **Recommended Bundled** Wine choice downloads this file. |

Both contain the same Wine build, the same patches (table below) and the same DXVK.
The tarball relies on the system's usual libraries, as any Wine build does (OuDedetai
installs them for you).

**AppImage:** make it executable and run Wine through it:

    chmod +x wine-custom_….AppImage
    WINEPREFIX=<prefix> ./wine-custom_….AppImage <program.exe>      # or: … wine <program.exe>
    WINEPREFIX=<prefix> ./wine-custom_….AppImage winecfg

**Tarball:** unpack it anywhere and use the `bin` folder inside:

    tar -xf wine-custom_….tar.xz
    WINEPREFIX=<prefix> ./wine-custom_…/bin/wine <program.exe>

## Renderer: DXVK, with OpenGL as the fallback

Both files carry our patched DXVK (the Logos fixes from
[FaithLife-Community/dxvk](https://github.com/FaithLife-Community/dxvk)); the version is
named below. It isn't used until you put it into a prefix:

    WINEPREFIX=<prefix> ./wine-custom_….AppImage dxvk-install       # AppImage
    WINEPREFIX=<prefix> ./wine-custom_…/bin/dxvk-install            # tarball

`dxvk-install` first checks, through Wine's own Vulkan, for a GPU with Vulkan 1.4, which
DXVK needs (Mesa 25 or newer, NVIDIA 575 or newer). If there is one, it installs DXVK
(d3d8, d3d9, d3d10core, d3d11, dxgi) and exits with 0. If not, it sets Wine's OpenGL
renderer instead (`HKCU\Software\Wine\Direct3D\renderer=gl`), takes out any DXVK it put
there before, and exits with 3. Options: `--check` only reports (exit 0 = DXVK can run),
`--force` installs DXVK without checking. `dxvk-uninstall` goes back to Wine's own
Direct3D.

DXVK writes log files next to the program unless `DXVK_LOG_LEVEL=none` is set (the
AppImage sets it for you).

## Logos media settings

DWORD values under `HKCU\Software\Wine\MediaFoundation`:

| Value | Effect |
|---|---|
| `DisableGstByteStreamHandler=1` | Use the FFmpeg-based media source (winedmo) for Logos videos. Recommended. |
| `DisableGstDecoders=1` | Also decode H.264/AAC with FFmpeg instead of GStreamer (being tested; leave at 0 unless asked). |

## Reporting problems

Say which file you used (the name includes the version and the Wine commit), whether
DXVK or OpenGL was in use, and attach OuDedetai's log or the terminal output. Issues:
[FaithLife-Community/OuDedetai](https://github.com/FaithLife-Community/OuDedetai/issues).
More detail on every patch:
[docs/patches.md](https://github.com/FaithLife-Community/wine-appimages/blob/main/docs/patches.md).
