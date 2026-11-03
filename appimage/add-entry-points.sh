#!/usr/bin/env bash
set -euo pipefail

appdir=$(readlink -f -- "$1")
scriptdir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# appimage-builder normalises the filesystem before after_runtime completes.
# Install the public launchers only after it has finished. Keep a separate bin
# directory: overwriting usr/bin/wine would replace our internal Wine loader.
if [ -L "$appdir/bin" ]; then
    target=$(readlink -f -- "$appdir/bin")
    case "$target" in
        "$appdir"/*) ;;
        *) echo 'Bundle bin symlink points outside AppDir' >&2; exit 1 ;;
    esac
    rm "$appdir/bin"
    mkdir "$appdir/bin"
    for binary in "$target"/*; do
        [ -e "$binary" ] || [ -L "$binary" ] || continue
        ln -s "../${target#"$appdir"/}/${binary##*/}" "$appdir/bin/${binary##*/}"
    done
else
    mkdir -p "$appdir/bin"
fi

for name in wine wine64 wineserver winetricks; do
    rm -f -- "$appdir/bin/$name"
    cp "$scriptdir/runtime-entry" "$appdir/bin/$name"
    chmod +x "$appdir/bin/$name"
done
