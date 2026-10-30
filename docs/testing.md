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

## Finding which Wine change broke something: `tools/wine-bisect.sh`

The bisect harness builds Wine at each step of a `git bisect` and runs a **test**
that decides whether that Wine is good or bad. It runs unattended; a bisect across a
few thousand commits took about 7 hours on an old 4-core i5.

The test is swappable. Tests live in `tools/bisect-tests/`:

| Test | Good when… |
|---|---|
| `logos-starts` (default) | Logos starts, shows its main window and doesn't crash within 60 s |
| `run-program` | any Windows program exits with the expected code and/or prints the expected text |

Choose one with `TEST=<name>` in `wine-bisect.conf`. If a regression can be checked by
a script, it can be bisected: see [tools/bisect-tests/README.md](../tools/bisect-tests/README.md)
for how to write a test, and how to check one before trusting it.

### What you need

- A Linux desktop with Wine's build dependencies, including the mingw cross-compilers
- `xdotool` (for `logos-starts`); optionally `ccache` (much faster steps) and `imagemagick` (screenshots)
- A copy of a **working** OuDedetai install folder: Logos installed, logged in,
  fully indexed, and with updates turned off

### Setup

```bash
cp -a <your OuDedetai install folder> ~/wine-bisect-prefix
cp -r tools/wine-bisect.sh tools/wine-bisect.conf.example tools/bisect-tests ~/wine-bisect-prefix/
cd ~/wine-bisect-prefix
mv wine-bisect.conf.example wine-bisect.conf        # optional; defaults are fine
./wine-bisect.sh setup     # clones Wine into ~/Documents/GitHub/wine-mirror
./wine-bisect.sh settle    # lets Logos finish indexing in the copy, once
./wine-bisect.sh tests     # lists the available tests
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

If you already had an older copy of `wine-bisect.sh` in your install folder, copy the
`bisect-tests/` folder next to it as well; the script now needs it.

### Useful settings in `wine-bisect.conf`

| Setting | Use |
|---|---|
| `export CC="ccache gcc" x86_64_CC="ccache x86_64-w64-mingw32-gcc" i386_CC="ccache i686-w64-mingw32-gcc"` | much faster rebuilds |
| `EXTRA_ENV=(WINEDEBUG=warn+dwrite ...)` | Wine debug output in the step log |
| `USE_XVFB=1` | keep Logos windows off your desktop (check that the good end still passes) |
| `TEST` | which test decides good or bad |
| `RUNS` | attempts per step; a step is bad only if every attempt fails |
| `LAUNCH_WAIT` | (`logos-starts`) how long Logos must survive |
| `PROGRAM`, `PROGRAM_ARGS`, `EXPECT_EXIT`, `EXPECT_REGEX` | (`run-program`) what to run and what counts as good |

To try a test once without editing the config: `TEST=run-program PROGRAM=… ./wine-bisect.sh test-wine`.

Run `./wine-bisect.sh` with no arguments for the full command list.
