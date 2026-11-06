# Patches and branches

All patches live as commits on branches of
[FaithLife-Community/wine](https://github.com/FaithLife-Community/wine), a fork of
upstream Wine. The goal for every patch is to get it accepted upstream, so it can be
dropped from here.

## Branches

| Branch | Purpose |
|---|---|
| `master` | Mirror of upstream Wine. Never commit here; only fast-forward it to upstream. |
| **`oinos-master`** | **Stable.** Releases for OuDedetai users are built from here. Patches arrive only from `oinos-prerelease`, once they have been tested there. |
| **`oinos-prerelease`** | Tested patches waiting for the next stable release. Beta builds come from here. |
| `oinos-testing/<topic>` | Work in progress, one branch per topic, e.g. `oinos-testing/media` or `oinos-testing/printing`. Merge into `oinos-prerelease` with a pull request once tested. |

A patch moves `oinos-testing/<topic>` → `oinos-prerelease` → `oinos-master`. Branch new
work from `oinos-prerelease`.

Older branches kept for reference (all their patches are already in `oinos-prerelease`
unless noted):

| Branch | Was |
|---|---|
| `oinos-testing/logos-master` | Patches 1–3 on upstream `c37cb58e` (after 11.20, with the fix for the 11.20 startup crash, [bug 60528](https://bugs.winehq.org/show_bug.cgi?id=60528)). |
| `oinos-testing/logos-11.20` | Patches 1–3 on `wine-11.20`, which crashes at startup on some systems. |
| `oinos-testing/logos-11.21-media`, `oinos-testing/logos-11.21-revertdc` | Media development on `wine-11.21`. |
| `oinos-testing/media` | Patches 14–15 (focus fixes), merged in PR #13. |
| `oinos-testing/overlay-only` | Patch 15 alone, to show patch 14 is also needed. |
| `oinos-testing/wineps-glyph-names` | Printing development (patches 1–8). |
| `oinos-testing/prntvpt-devmode` | Patch 4 alone, for the upstream merge request. |
| `oinos-testing/xpsprint-stubs` | Patch 6 alone, for upstream. |
| `oinos-testing/printing` | **Not in prerelease:** a throwaway debug trace dumping fonts' GSUB and cmap tables. Never build releases from it. |
| `oinos-testing/dcfix` | **Not in prerelease:** "wined3d: Stop using a swapchain DC once it no longer belongs to the window", an alternative to the wined3d reverts. |
| `oinos-testing/cef-share`, `oinos-testing/cef-vprot` | The original CEF memory patches (1–2) on `wine-10.13`. |

Put the upstream commit in the build label (see [building.md](building.md#choosing-a-label)).

## The patches

### 1. ntdll: Don't write zeros into untouched page protection chunks

- **Problem:** Chromium (CEF inside Logos) reserves a ~1.3 TiB no-access region.
  Wine's page protection table is zero-filled memory, but Wine wrote zeros over the
  whole range anyway, which made ~330 MB of the table resident in every CEF process.
- **Fix:** remember per 1 MiB chunk whether it ever held a non-zero byte, and skip
  zero writes into chunks that never did.
- **Effect:** CEF renderer anonymous memory fell from about 400 MB to 65 MB (on 10.13).
- **Upstream:** related to [Wine bug 58805](https://bugs.winehq.org/show_bug.cgi?id=58805)
  and OuDedetai issue #452; under discussion with Wine developers, not merged.
- **Porting note:** from Wine 11.x the table pointers are allocated separately, so the
  per-chunk flags are now a separate `calloc` in `virtual_init()`. The logic is unchanged.

### 2. server, ntdll: Share page-aligned copies of misaligned read-only image sections

- **Problem:** `libcef.dll` (~234 MB) has 0x200 file alignment, so its large
  read-only sections can't be memory-mapped from the file, and every renderer process
  reads its own private copy (~220 MB each).
- **Fix:** the server keeps a page-aligned copy in the image's shared temporary file,
  and processes map that copy, so they share the same pages.
- **Upstream:** as patch 1.

### 3. dwrite: Skip unsupported files when creating custom collections (plus test)

- **Problem:** since upstream commit `604e43d34a00` (September 2025), one file that DirectWrite can't use makes `CreateCustomFontCollection()`
  fail completely. WPF passes its `.CompositeFont` XML files along with the real fonts,
  so Logos gets no fonts and exits during startup.
- **Fix:** skip such files again, as Wine did before that commit, with a test.
- **Upstream:** WineHQ bug report filed 30 Oct 2026; merge request to follow.
  Found with the bisect harness in [testing.md](testing.md).

### 4. prntvpt: Return the driver's full DEVMODE from PTConvertPrintTicketToDevMode (plus test)

- **Problem:** Logos (through WPF) passes the DEVMODE from `PTConvertPrintTicketToDevMode`
  straight back to `DocumentPropertiesW` as both input and output buffer when it shows the
  printer's Properties dialog. Wine returned only the 220-byte public part. wineps then
  copied its full DEVMODE (~7.4 KB) into that buffer, which corrupted the .NET heap and
  crashed Logos. Paper sizes chosen in the dialog (e.g. A4) were also lost.
- **Fix:** start from the driver's own DEVMODE, private part included (as Windows does),
  and apply the ticket's settings on top.
- **Upstream:** not yet submitted.

### 5. wineps: Name glyphs after their character when the font has no glyph names

- **Problem:** fonts with a format 3.0 `post` table have no glyph names, so glyphs were
  downloaded as `g<index>`. Ghostscript (cups-pdf) uses glyph names to rebuild the text,
  so PDFs printed from Logos looked right but their text couldn't be searched or copied.
- **Fix:** map glyph indices back to characters through the font's cmap and use AGL
  `uniXXXX` names.
- **Upstream:** not yet submitted.

### 6. xpsprint: Don't export StartXpsPrintJob stubs

- **Problem:** WPF prints through `StartXpsPrintJob` whenever xpsprint.dll exports it.
  Wine only has a stub, which raises an exception, so printing crashed.
- **Fix:** drop the stub exports. WPF then falls back to GDI printing through wineps.
- **Upstream:** not yet submitted.

### 7. wineps: Map ligatures and alternate glyphs back to their text through GSUB

- **Problem:** ligatures such as "Th" and alternate glyphs have no cmap entry, so patch 5
  can't name them and they stayed unsearchable.
- **Fix:** read the font's GSUB table (single, alternate, ligature and extension lookups)
  to work out the text each glyph stands for. Single-character alternates go into the
  font's `FontInfo /GlyphNames2Unicode`, as Windows' PostScript driver does.
- **Upstream:** not yet submitted.

### 8. wineps: Mark ligature glyphs with their text through ActualText spans

- **Problem:** Ghostscript drops `GlyphNames2Unicode` entries longer than one character
  for these fonts, so ligatures from patch 7 still couldn't be selected.
- **Fix:** wrap each ligature in a `/Span <</ActualText ...>> /BDC` pdfmark. The prolog
  makes `pdfmark` a no-op on printers that don't know it.
- **Upstream:** not yet submitted.

### 9. d3d9: Wait for GetRenderTargetData() to complete

- **Problem:** the copy was queued and the call returned at once; Logos reads the
  destination memory straight away, so video frames were black or late.
- **Fix:** map and unmap the destination after the blit.
- **Upstream:** not yet submitted.

### 10. wined3d: Use the texture size for blits to swapchain textures through an FBO

- **Problem:** blits into any swapchain texture were clipped to the window's client
  size. Logos's video presenter draws into back buffers of tiny or message-only
  windows, so every frame was lost.
- **Upstream:** not yet submitted.

### 11–13. evr and mf: keep frames flowing across resize and seek

- **11. evr/mixer: Request input whenever ProcessOutput() needs more input.** After a
  repaint or a flush the mixer never asked for more, so the picture froze.
- **12. evr/mixer: Send sample requests after releasing the mixer lock.** Fixes a
  deadlock with the renderer.
- **13. mf/evr: Handle sample requests from the mixer without the renderer lock.**
  Fixes a deadlock with Logos's presenter thread on seek.
- **Upstream:** not yet submitted; tests still to write.

### 14–15. winex11: stop Logos popups and the read-aloud overlay taking focus

- **Problem:** on KDE Plasma (X11), typing during read-aloud went to the Plasma panel,
  which popped up whenever the orange read-aloud circles flashed. This started with the
  Wine 10.5 menu fixes ([bug 52380](https://bugs.winehq.org/show_bug.cgi?id=52380)).
- **14. winex11: Don't let no-activate popups steal X focus or become WM-activated.**
  Logos calls `SetActiveWindow` on its WPF popups (WS_EX_NOACTIVATE). Wine moved X focus
  into them directly, so it fell to the root window when they closed, and handed them to
  the window manager. Without it, typing pauses briefly and the screen flickers black.
- **15. winex11: Don't let click-through layered overlay windows be managed.** The circles
  are a caption-less WS_EX_LAYERED | WS_EX_TRANSPARENT window that Wine had handed to the
  window manager at creation, so KWin saw a new window appear on every flash. This one
  stops the panel.
- **Upstream:** not yet submitted; planned as a two-patch series, 15 first.

Media playback also needs Wine built with FFmpeg: winedmo, Wine's FFmpeg-based media
source, is what OuDedetai's `DisableGstByteStreamHandler=1` switches Logos to. The build
bundles FFmpeg (see [building.md](building.md)); decoding still uses the host's
GStreamer. OuDedetai also needs `renderer=gl`.

Printing also needs OuDedetai's prefix settings: WPF's `DisableXPSOMPrinting` switch,
because Wine doesn't implement the Print Document Package API that WPF otherwise uses,
plus font replacements for the Windows fonts Logos expects. The fonts themselves are
bundled in the AppImage.

## Moving the patches to a newer Wine

With a local clone of the fork, and upstream added as a remote:

```bash
git remote add upstream https://gitlab.winehq.org/wine/wine.git   # once
git fetch upstream --tags

# e.g. moving oinos-prerelease from wine-11.21 to wine-11.22
git checkout -b oinos-testing/rebase-11.22 oinos-prerelease
git rebase --onto wine-11.22 <old base commit or tag>
```

The `ntdll/unix/virtual.c` patches conflict most often, because upstream reworks that
file regularly. When resolving a conflict, check that every place that writes to
`pages_vprot` still sets the per-chunk flag whenever it stores a non-zero value.
Patch 1 depends on that.

Build it once locally before pushing. Then push the branch and build it as in
[building.md](building.md).

## Adding a new patch

1. Branch `oinos-testing/<topic>` from `oinos-prerelease`, commit the patch with a clear Wine-style
   message (`component: Do something.`), and say in the message what problem it fixes.
2. Add an entry to the list above: problem, fix, effect, upstream status.
3. Build and test it (see [testing.md](testing.md)), then merge it into
   `oinos-prerelease` with a pull request. It reaches `oinos-master` with the next
   stable release.
