# Testing

## Trying an AppImage with Logos

Download the `.AppImage` from the release, make it executable, and point OuDedetai
at it:

```bash
chmod +x wine-custom_11.20_logosc37cb58-x86_64.AppImage
oudedetai --set-appimage ~/Downloads/wine-custom_11.20_logosc37cb58-x86_64.AppImage
```

This works when OuDedetai's Wine choice is an AppImage (including the Recommended
option). Then start
Logos from OuDedetai as usual. At a minimum, check that:

- Logos starts and reaches its main window
- panels open and render text in the expected fonts
- memory use is sensible with several panels open (`ps -eo rss,cmd | grep -i cef`)

To go back, run `--set-appimage` again with the previous AppImage.

## Finding which Wine change broke Logos: `tools/wine-bisect.sh`

The bisect harness builds Wine at each step of a `git bisect`, launches Logos, and
marks the step good if Logos is still running with a visible window after 60
seconds. It runs unattended; a bisect across a few thousand commits took about
7 hours on an old 4-core i5.

### What you need

- A Linux desktop with Wine's build dependencies, including the mingw cross-compilers
- `xdotool`; optionally `ccache` (much faster steps) and `imagemagick` (screenshots)
- A copy of a **working** OuDedetai install folder: Logos installed, logged in,
  fully indexed, and with updates turned off

### Setup

```bash
cp -a <your OuDedetai install folder> ~/wine-bisect-prefix
cp tools/wine-bisect.sh tools/wine-bisect.conf.example ~/wine-bisect-prefix/
cd ~/wine-bisect-prefix
mv wine-bisect.conf.example wine-bisect.conf        # optional; defaults are fine
./wine-bisect.sh setup     # clones Wine into ~/Documents/GitHub/wine-mirror
./wine-bisect.sh settle    # lets Logos finish indexing in the copy, once
```

The harness keeps everything in three places: the install copy (Logos runs directly
in its `data/wine64_bottle`), the dedicated Wine clone, and `~/.cache/wine-bisect`
for builds and logs. It refuses to bisect any other Wine checkout.

### Running

```bash
./wine-bisect.sh test-wine                          # the install's own Wine should PASS
./wine-bisect.sh test-wine ~/Downloads/<newer>.AppImage   # find the first release that FAILs
./wine-bisect.sh run wine-10.13 wine-11.20          # last good, first bad; leave it running
./wine-bisect.sh status                             # progress, from another terminal
```

`run` first checks that the good end passes and the bad end fails with your own
build, so it stops early instead of bisecting nonsense. When it finishes you get a
desktop notification with the first bad commit. Per-step logs and screenshots are in
`~/.cache/wine-bisect/logs/<commit>/`.

To test a fix, commit it on a branch in the Wine clone and run `./wine-bisect.sh test`.

### Useful settings in `wine-bisect.conf`

| Setting | Use |
|---|---|
| `export CC="ccache gcc" x86_64_CC="ccache x86_64-w64-mingw32-gcc" i386_CC="ccache i686-w64-mingw32-gcc"` | much faster rebuilds |
| `EXTRA_ENV=(WINEDEBUG=warn+dwrite ...)` | Wine debug output in the step log |
| `USE_XVFB=1` | keep Logos windows off your desktop (check that the good end still passes) |
| `LAUNCH_WAIT`, `RUNS` | how long Logos must survive, and attempts per step |

Run `./wine-bisect.sh` with no arguments for the full command list.
