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

Logos's media plays through FFmpeg by default: the FFmpeg media source and FFmpeg's H.264
and AAC decoders, with video decoded on the GPU where possible (NVIDIA through NVDEC; AMD and
Intel through VA-API; otherwise Vulkan Video), and in software otherwise. GStreamer isn't
needed. It's still used as a fallback when FFmpeg can't open something, and can be chosen
with these DWORD values under `HKCU\Software\Wine\MediaFoundation`:

| Value | Effect |
|---|---|
| `DisableGstByteStreamHandler=0` | Use GStreamer's media source instead of FFmpeg's. |
| `DisableGstDecoders=0` | Decode H.264/AAC with GStreamer first (needs the host's GStreamer plugins). |

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

## Quick setup for testers

Switches an existing OuDedetai install to this build and sets its prefix up in one go:
DXVK (or OpenGL where the GPU can't run it), the FFmpeg media source, the Logos update
setting and printing. Close Logos first. It assumes the AppImage was saved to `~/Downloads`
and OuDedetai is installed in its default folder (otherwise change the first two lines).
With the tarball instead, skip the `--set-appimage` line and set `WINE` to the `bin/wine`
inside the extracted folder; the rest works for both.

```bash
APPIMAGE=~/Downloads/@NAME@.AppImage
OUD=~/.local/share/FaithLife-Community/oudedetai
"$OUD/oudedetai" --set-appimage "$APPIMAGE"     # OuDedetai copies it into its bin folder and uses it from now on
WINE="$OUD/data/bin/wine"
export WINEPREFIX="$OUD/data/wine64_bottle"
"$WINE" --version                               # should say: wine-11.21 (oinos)
# The tarball has dxvk-install next to bin/wine; the AppImage runs it as "wine dxvk-install"
TOOL="$(dirname "$(readlink -f "$WINE")")/dxvk-install"
if [ -x "$TOOL" ]; then "$TOOL"; else "$WINE" dxvk-install; fi
case $? in 0) echo "Renderer: DXVK" ;; 3) echo "Renderer: OpenGL (no Vulkan 1.4 for DXVK)" ;; *) echo "dxvk-install failed" ;; esac
"$WINE" reg add 'HKCU\Software\Wine\MediaFoundation' /v DisableGstByteStreamHandler /t REG_DWORD /d 1 /f
"$WINE" reg add 'HKCU\Software\Wine\MSI' /v IgnoreFailedActions /t REG_MULTI_SZ /d RegisterStubMsixPackage /f
# Printing: WPF prints through GDI (wineps -> CUPS), and stand-ins for the fonts Logos's print preview needs
"$WINE" reg add 'HKCU\Software\Microsoft\.NETFramework\Windows Presentation Foundation\Printing' /v DisableXPSOMPrinting /t REG_DWORD /d 1 /f
R='HKCU\Software\Wine\Fonts\Replacements'
"$WINE" reg add "$R" /v "Segoe UI" /t REG_MULTI_SZ /d 'Selawik\0Noto Sans\0Liberation Sans\0DejaVu Sans' /f
"$WINE" reg add "$R" /v "Times New Roman" /t REG_MULTI_SZ /d 'Liberation Serif\0Tinos\0Nimbus Roman' /f
"$WINE" reg add "$R" /v "Courier New" /t REG_MULTI_SZ /d 'Liberation Mono\0Cousine\0Nimbus Mono PS' /f
"$WINE" reg add "$R" /v "Microsoft Sans Serif" /t REG_MULTI_SZ /d 'Liberation Sans\0Arimo\0Nimbus Sans' /f
"$WINE" reg add "$R" /v "Calibri" /t REG_MULTI_SZ /d 'Carlito\0Liberation Sans\0Arimo' /f
"$WINE" wineserver -w
```

The printing and font settings match what current OuDedetai sets on install; they're here for
prefixes made by older versions. To compare with GStreamer decoding:
`"$WINE" reg add 'HKCU\Software\Wine\MediaFoundation' /v DisableGstDecoders /t REG_DWORD /d 0 /f`
(`/d 1` goes back to FFmpeg). `"$WINE" dxvk-uninstall` goes back to Wine's own Direct3D.

## Reporting problems

Say which file you used (the name includes the version and the Wine commit), whether
DXVK or OpenGL was in use, and attach OuDedetai's log or the terminal output. Issues:
[FaithLife-Community/OuDedetai](https://github.com/FaithLife-Community/OuDedetai/issues).
More detail on every patch:
[docs/patches.md](https://github.com/FaithLife-Community/wine-appimages/blob/main/docs/patches.md).
