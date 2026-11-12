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
| `DisableGstDecoders=1` | Also decode H.264/AAC with FFmpeg instead of GStreamer. Optional: it works, including pause, seek and speed changes, but uses a little more CPU than GStreamer for now. |

With `DisableGstDecoders=1`, FFmpeg decodes video on the GPU when it can (NVIDIA through
NVDEC; AMD and Intel through VA-API; otherwise Vulkan Video), and in software otherwise.
`WINEDMO_HWACCEL=0` in the environment forces software decoding.

## Logos updates

`wine --version` says `(oinos)` for these builds. They carry two installer fixes that
make Logos's own updates safe under Wine:

- An update no longer deletes Logos's `Data` folder (the removal of the old version now
  sees `UPGRADINGPRODUCTCODE`, as on Windows).
- Custom actions named in `HKCU\Software\Wine\MSI\IgnoreFailedActions` (REG_MULTI_SZ,
  or REG_SZ separated by `;`) may fail without rolling the installation back. Logos
  needs `RegisterStubMsixPackage` listed: it registers an MSIX package, which Wine can't.

OuDedetai sets this up and lets Logos update itself only when it sees an `(oinos)` Wine;
with any other Wine it keeps suppressing Logos's application updates.

## Reporting problems

Say which file you used (the name includes the version and the Wine commit), whether
DXVK or OpenGL was in use, and attach OuDedetai's log or the terminal output. Issues:
[FaithLife-Community/OuDedetai](https://github.com/FaithLife-Community/OuDedetai/issues).
More detail on every patch:
[docs/patches.md](https://github.com/FaithLife-Community/wine-appimages/blob/main/docs/patches.md).
