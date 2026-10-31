# Patches and branches

All patches live as commits on branches of
[FaithLife-Community/wine](https://github.com/FaithLife-Community/wine), a fork of
upstream Wine. The goal for every patch is to get it accepted upstream, so it can be
dropped from here.

## Branches

| Branch | Base | Contents | Status |
|---|---|---|---|
| `master` | upstream | Mirror of upstream Wine. Never commit here. | |
| **`logos-master`** | upstream `c37cb58e` (29 Oct 2026, after 11.20) | Patches 1–3 | **Current.** Includes the upstream fix for the 11.20 startup crash ([bug 60528](https://bugs.winehq.org/show_bug.cgi?id=60528)). |
| `wineps-glyph-names` | `logos-master` | Patches 1–6 (printing). To be folded into `logos-master`. |
| `logos-11.20` | `wine-11.20` | All patches below | Superseded: 11.20 itself crashes at startup on some systems. |
| `cef-share` | `wine-10.13` | The two CEF memory patches | Original development branch. |
| `cef-vprot` | `wine-10.13` | The first CEF memory patch only | Original development branch. |

Name new combined branches `logos-<base>`: `logos-11.21` for a release, or
`logos-master` (force-pushed) for a commit between releases. Write the upstream
commit in the build label (see the [README](../README.md#naming)).

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

Printing also needs OuDedetai's prefix settings: WPF's `DisableXPSOMPrinting` switch,
because Wine doesn't implement the Print Document Package API that WPF otherwise uses,
plus font replacements for the Windows fonts Logos expects. The fonts themselves are
bundled in the AppImage.

## Moving the patches to a newer Wine

With a local clone of the fork, and upstream added as a remote:

```bash
git remote add upstream https://gitlab.winehq.org/wine/wine.git   # once
git fetch upstream --tags

# e.g. moving from logos-master to wine-11.21
git checkout -b logos-11.21 logos-master
git rebase --onto wine-11.21 <old base commit or tag>
```

The `ntdll/unix/virtual.c` patches conflict most often, because upstream reworks that
file regularly. When resolving a conflict, check that every place that writes to
`pages_vprot` still sets the per-chunk flag whenever it stores a non-zero value.
Patch 1 depends on that.

Build it once locally before pushing. Then push the branch and build it as in
[building.md](building.md).

## Adding a new patch

1. Branch from the current combined branch, commit the patch with a clear Wine-style
   message (`component: Do something.`), and say in the message what problem it fixes.
2. Add an entry to the list above: problem, fix, effect, upstream status.
3. Build and test it (see [testing.md](testing.md)) before it goes into a release.
