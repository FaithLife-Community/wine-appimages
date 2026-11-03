#!/usr/bin/env bash
set -euo pipefail

image=$(readlink -f -- "$1")
bundle=$(readlink -f -- "$2")
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
export WINEPREFIX="$test_dir/prefix"
export APPIMAGE_EXTRACT_AND_RUN=1
export URUNTIME_PRELOAD=0

check_winetricks() {
    local version
    version=$(timeout 60s "$@" --version)
    printf '%s\n' "$version"
    grep -Eq '^20260125([[:space:]]|$)' <<< "$version"
}

# Exercise both supported ways to invoke the bundled script. If dispatch sends
# --version to Wine instead, its wine-* output cannot pass the assertion.
check_winetricks "$image" winetricks
ln -s "$image" "$test_dir/winetricks"
check_winetricks "$test_dir/winetricks"
check_winetricks "$bundle/bin/winetricks"

for entry in wine wine64 wineserver; do
    ln -s "$image" "$test_dir/$entry"
    timeout 60s "$test_dir/$entry" --version
    timeout 60s "$bundle/bin/$entry" --version
done

echo 'AppImage and extracted-bundle runtime dispatch checks passed.'
