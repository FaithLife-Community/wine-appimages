#!/usr/bin/env bash
# wine-bisect.sh — unattended "does Logos still launch?" regression hunting for Wine.
#
# Builds Wine from a dedicated clone (~/Documents/GitHub/wine-mirror) at each bisect step,
# runs Logos from a known-good OuDedetai install (directly in its bottle by default),
# waits, checks Logos is alive with a visible window and no crash dialog, closes it
# gracefully, and reports good/bad to `git bisect run`. Build failures are skipped (125);
# harness failures abort (255) so a broken environment is never blamed on a Wine commit.
#
# Usage:
#   wine-bisect.sh setup                           clone/update wine-mirror, create work dir, check tools
#   wine-bisect.sh settle                          run Logos once in the snapshot itself until the indexer
#                                                  finishes, so test runs don't re-index every time
#   wine-bisect.sh test-wine [AppImage|wine-dir]   test a prebuilt Wine, no build. No argument =
#                                                  the snapshot install's own bin/ Wine (sanity check)
#   wine-bisect.sh run <good-ref> <bad-ref>        verify both ends, then bisect unattended
#   wine-bisect.sh test                            build + test current checkout (git bisect run calls this)
#   wine-bisect.sh status                          show paths, bisect state and results so far
#   wine-bisect.sh cleanup                         kill leftover wineserver, unmount scratch prefix
#   wine-bisect.sh purge                           cleanup + delete build dir and scratch (keeps logs)
#
# Where things live (all overridable in the config):
#   ~/Documents/GitHub/wine-mirror   dedicated Wine clone; bisect state lives here only
#   ~/wine-bisect-prefix             your copied OuDedetai install, plus this script and its
#                                    config; Logos runs directly in its data/wine64_bottle
#   ~/.cache/wine-bisect/            build tree, logs, summary.tsv (and scratch copies if PREFIX_MODE≠inplace)
# Config is read from $WINE_BISECT_CONF, else wine-bisect.conf next to this script,
# else ~/.config/wine-bisect/wine-bisect.conf.

set -uo pipefail   # deliberately not -e: every failure is mapped to a bisect exit code

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
EXIT_GOOD=0 EXIT_BAD=1 EXIT_SKIP=125 EXIT_ABORT=255

# ---------- config ----------
CONF=${WINE_BISECT_CONF:-}
if [[ -z $CONF ]]; then
  for c in "$SCRIPT_DIR/wine-bisect.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/wine-bisect/wine-bisect.conf"; do
    [[ -f $c ]] && { CONF=$c; break; }
  done
fi
[[ -n $CONF && -f $CONF ]] && source "$CONF"

# defaults — applied after the config so derived paths follow overrides
: "${GITHUB_DIR:=$HOME/Documents/GitHub}"
: "${WINE_SRC:=$GITHUB_DIR/wine-mirror}"
: "${UPSTREAM_URL:=https://gitlab.winehq.org/wine/wine.git}"
: "${REFERENCE_REPO:=}"                 # optional existing local wine clone to copy objects from (fast, then dissociated)
# copied OuDedetai install folder (has data/ and bin/). If this script lives in it, that's the default.
if [[ -d $SCRIPT_DIR/data/wine64_bottle ]]; then : "${INSTALL_DIR:=$SCRIPT_DIR}"; fi
: "${INSTALL_DIR:=$HOME/wine-bisect-prefix}"
: "${PRISTINE_PREFIX:=}"                # derived from INSTALL_DIR if empty
: "${WORK_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/wine-bisect}"
: "${BUILD_DIR:=$WORK_DIR/build}"
: "${MAKE_JOBS:=$(nproc)}"
: "${PREFIX_MODE:=inplace}"             # inplace = run Logos in the bottle itself (default);
                                        # overlay | copy = throwaway copy per run (Logos re-indexes in these)
: "${LOGOS_EXE_REL:=drive_c/users/*/AppData/Local/Logos/Logos.exe}"
: "${LAUNCH_WAIT:=60}"
: "${POLL_INTERVAL:=5}"
: "${EARLY_FAIL_POLLS:=3}"
: "${REQUIRE_WINDOW:=1}"
: "${WINDOW_REGEX:=Logos}"
: "${RUNS:=2}"
: "${SHUTDOWN_WAIT:=45}"
: "${INDEXER_REGEX:=LogosIndexer\.exe}"
: "${INDEXER_WAIT:=600}"                # max seconds to wait for the indexer to exit before closing Logos
: "${SETTLE_WAIT:=7200}"                # max seconds `settle` waits for a full index
: "${WINEBOOT:=1}"                      # 0 = skip the explicit wineboot -u (Wine then updates the prefix implicitly at launch)
: "${WINEBOOT_TIMEOUT:=300}"
: "${USE_XVFB:=0}"
: "${VERIFY_ENDPOINTS:=1}"
declare -p CONFIGURE_ARGS >/dev/null 2>&1 || CONFIGURE_ARGS=(--enable-archs=i386,x86_64 --disable-tests)
declare -p LOGOS_ARGS     >/dev/null 2>&1 || LOGOS_ARGS=()
declare -p EXTRA_ENV      >/dev/null 2>&1 || EXTRA_ENV=(WINEDEBUG=-all "WINEDLLOVERRIDES=winemenubuilder.exe=d")
# Applied on top of EXTRA_ENV for the wineboot -u step only: stops the Wine Mono / Gecko
# install prompts on every fresh scratch prefix. Logos itself launches with EXTRA_ENV alone.
declare -p WINEBOOT_ENV   >/dev/null 2>&1 || WINEBOOT_ENV=("WINEDLLOVERRIDES=mscoree=;mshtml=;winemenubuilder.exe=d")

if [[ -z $PRISTINE_PREFIX ]]; then
  if   [[ -d $INSTALL_DIR/data/wine64_bottle/drive_c ]]; then PRISTINE_PREFIX=$INSTALL_DIR/data/wine64_bottle
  elif [[ -d $INSTALL_DIR/drive_c ]];                    then PRISTINE_PREFIX=$INSTALL_DIR
  else PRISTINE_PREFIX=$INSTALL_DIR/data/wine64_bottle
  fi
fi

RUN_DIR="$WORK_DIR/run"
LOG_DIR="$WORK_DIR/logs"
SUMMARY="$WORK_DIR/summary.tsv"
MAIN_LOG="$WORK_DIR/bisect.log"
STEP_LOG=/dev/null
WINE="" WINESERVER="" LAUNCH_PID="" XVFB_PID=""

mkdir -p "$WORK_DIR" "$LOG_DIR"

log()   { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$MAIN_LOG" >&2; [[ $STEP_LOG != /dev/null ]] && printf '### %s\n' "$*" >>"$STEP_LOG"; }
abort() { log "ABORT: $*"; cleanup; exit $EXIT_ABORT; }
have()  { command -v "$1" >/dev/null 2>&1; }

# ---------- environment checks ----------
check_common() {
  [[ -d $PRISTINE_PREFIX/drive_c ]] || abort "no Wine prefix at $PRISTINE_PREFIX (set INSTALL_DIR or PRISTINE_PREFIX)"
  compgen -G "$PRISTINE_PREFIX/$LOGOS_EXE_REL" >/dev/null || abort "Logos.exe not found at $PRISTINE_PREFIX/$LOGOS_EXE_REL"
  case $PREFIX_MODE in inplace|overlay|copy) ;; *) abort "PREFIX_MODE must be inplace, overlay or copy" ;; esac
  [[ $PREFIX_MODE == overlay ]] && ! have fuse-overlayfs && abort "PREFIX_MODE=overlay but fuse-overlayfs is not installed"
  [[ $REQUIRE_WINDOW == 1 ]] && ! have xdotool && abort "REQUIRE_WINDOW=1 needs xdotool (or set REQUIRE_WINDOW=0)"
  if [[ $USE_XVFB == 1 ]]; then
    have Xvfb || abort "USE_XVFB=1 but Xvfb is not installed"
    local d=:97
    Xvfb "$d" -screen 0 1920x1080x24 -nolisten tcp >/dev/null 2>&1 &
    XVFB_PID=$!; disown "$XVFB_PID"; export DISPLAY=$d; sleep 2
    kill -0 "$XVFB_PID" 2>/dev/null || abort "Xvfb failed to start"
  fi
  [[ -n ${DISPLAY:-} ]] || abort "no DISPLAY — run from your desktop session or set USE_XVFB=1"
}

check_mirror() {
  [[ -d $WINE_SRC/.git ]] || abort "no wine clone at $WINE_SRC — run '$0 setup' first"
  [[ -f $WINE_SRC/.wine-bisect ]] || abort "$WINE_SRC was not created by '$0 setup' — refusing to bisect in another repo"
}

# ---------- scratch prefix ----------
cleanup_prefix() {
  [[ -d $RUN_DIR ]] || return 0
  if mountpoint -q "$RUN_DIR/prefix" 2>/dev/null; then
    fusermount -u "$RUN_DIR/prefix" 2>/dev/null || { sleep 2; fusermount -uz "$RUN_DIR/prefix" 2>/dev/null; }
    # never rm -rf through a live mount
    mountpoint -q "$RUN_DIR/prefix" 2>/dev/null && { log "ERROR: $RUN_DIR/prefix still mounted"; return 1; }
  fi
  case $RUN_DIR in "$WORK_DIR"/*) rm -rf --one-file-system "$RUN_DIR" ;; esac
}

setup_prefix() {
  cleanup_prefix || return 1
  if [[ $PREFIX_MODE == inplace ]]; then
    export WINEPREFIX="$PRISTINE_PREFIX"
    [[ -n $(prefix_pids 'Logos\.exe') ]] && abort "Logos is already running in $WINEPREFIX — close it first"
    return 0
  fi
  mkdir -p "$RUN_DIR"
  if [[ $PREFIX_MODE == overlay ]]; then
    mkdir -p "$RUN_DIR"/{upper,work,prefix}
    fuse-overlayfs -o "lowerdir=$PRISTINE_PREFIX,upperdir=$RUN_DIR/upper,workdir=$RUN_DIR/work" "$RUN_DIR/prefix" || return 1
  else
    cp -a --reflink=auto "$PRISTINE_PREFIX" "$RUN_DIR/prefix" || return 1
  fi
  export WINEPREFIX="$RUN_DIR/prefix"
}

# ---------- process helpers (scoped to our prefix only) ----------
prefix_pids() {
  local pid
  for pid in $(pgrep -f -- "$1" 2>/dev/null); do
    tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -qxF "WINEPREFIX=$WINEPREFIX" && echo "$pid"
  done
}

logos_window_visible() {
  local pid
  for pid in $(prefix_pids 'Logos\.exe'); do
    xdotool search --all --onlyvisible --pid "$pid" --name "$WINDOW_REGEX" >/dev/null 2>&1 && return 0
  done
  return 1
}

screenshot() {
  if have import; then import -window root "$1" 2>/dev/null
  elif have grim; then grim "$1" 2>/dev/null
  fi
}

kill_wine() {
  [[ -n ${WINEPREFIX:-} && -n $WINESERVER ]] || return 0
  "$WINESERVER" -k >/dev/null 2>&1
  timeout 30 "$WINESERVER" -w >/dev/null 2>&1
  [[ -n $LAUNCH_PID ]] && { kill "$LAUNCH_PID" 2>/dev/null; LAUNCH_PID=""; }
}

cleanup() {
  kill_wine
  cleanup_prefix
  [[ -n $XVFB_PID ]] && kill "$XVFB_PID" 2>/dev/null
  XVFB_PID=""
}

# wait for the indexer to exit; sets INDEXER_SECS (-1 = timed out)
wait_for_indexer() {   # $1 = max seconds
  local max=$1 t=0
  INDEXER_SECS=0
  [[ -z $(prefix_pids "$INDEXER_REGEX") ]] && return 0
  log "indexer running — waiting up to ${max}s for it to finish"
  while [[ -n $(prefix_pids "$INDEXER_REGEX") ]]; do
    (( t >= max )) && { INDEXER_SECS=-1; log "indexer still running after ${max}s"; return 1; }
    sleep 5; (( t += 5 ))
    (( t % 300 == 0 )) && log "indexer still running (${t}s)"
  done
  INDEXER_SECS=$t; log "indexer finished after ~${t}s"
  return 0
}

shutdown_logos() {
  log "closing Logos gracefully"
  env "${EXTRA_ENV[@]}" "$WINE" taskkill /IM Logos.exe >>"$STEP_LOG" 2>&1   # no /F → WM_CLOSE
  local t=0
  while [[ -n $(prefix_pids 'Logos\.exe') ]] && (( t < SHUTDOWN_WAIT )); do sleep 1; ((t++)); done
  [[ -n $(prefix_pids 'Logos\.exe') ]] && log "Logos ignored close after ${SHUTDOWN_WAIT}s — forcing"
  kill_wine
}

# ---------- one launch attempt: returns 0 pass / 1 fail; sets FAIL_REASON ----------
run_once() {
  local n=$1 shotdir=$2 exe t=0 missing=0 idx_seen=0
  FAIL_REASON="" STEP_NOTE="-"
  setup_prefix || abort "could not prepare prefix ($PREFIX_MODE)"
  exe=$(compgen -G "$WINEPREFIX/$LOGOS_EXE_REL" | head -n1)
  [[ -n $exe ]] || abort "Logos.exe missing in $WINEPREFIX"
  export WINESERVER

  if [[ $WINEBOOT == 1 ]]; then
    log "run $n: wineboot -u"
    if ! timeout "$WINEBOOT_TIMEOUT" env "${EXTRA_ENV[@]}" "${WINEBOOT_ENV[@]}" "$WINE" wineboot -u >>"$STEP_LOG" 2>&1; then
      FAIL_REASON="wineboot failed or timed out"; kill_wine; return 1
    fi
    timeout 120 "$WINESERVER" -w >/dev/null 2>&1
  fi

  log "run $n: launching Logos, waiting ${LAUNCH_WAIT}s"
  ( cd "$(dirname "$exe")" && exec env "${EXTRA_ENV[@]}" "$WINE" "$exe" "${LOGOS_ARGS[@]}" ) >>"$STEP_LOG" 2>&1 &
  LAUNCH_PID=$!; disown "$LAUNCH_PID"

  while (( t < LAUNCH_WAIT )); do
    sleep "$POLL_INTERVAL"; (( t += POLL_INTERVAL ))
    if [[ -n $(prefix_pids 'winedbg') ]]; then FAIL_REASON="crash (winedbg) after ~${t}s"; break; fi
    [[ -n $(prefix_pids "$INDEXER_REGEX") ]] && idx_seen=1
    if [[ -z $(prefix_pids 'Logos\.exe') ]]; then
      (( t >= 15 )) && (( ++missing >= EARLY_FAIL_POLLS )) && { FAIL_REASON="Logos exited after ~${t}s"; break; }
    else
      missing=0
    fi
  done

  if [[ -z $FAIL_REASON ]]; then
    if [[ -z $(prefix_pids 'Logos\.exe') ]]; then FAIL_REASON="Logos not running at ${LAUNCH_WAIT}s"
    elif [[ $REQUIRE_WINDOW == 1 ]] && ! logos_window_visible; then FAIL_REASON="Logos running but no visible '$WINDOW_REGEX' window"
    fi
  fi
  screenshot "$shotdir/run$n.png"

  if [[ -z $FAIL_REASON ]]; then
    log "run $n: PASS"
    wait_for_indexer "$INDEXER_WAIT"
    if   (( INDEXER_SECS < 0 ));                 then STEP_NOTE="indexer still running after ${INDEXER_WAIT}s"
    elif (( INDEXER_SECS > 30 ));                then STEP_NOTE="indexer ran ~$(( LAUNCH_WAIT + INDEXER_SECS ))s — snapshot may need '$0 settle'"
    elif (( idx_seen || INDEXER_SECS > 0 ));     then STEP_NOTE="indexer: quick"
    fi
    shutdown_logos; return 0
  fi
  log "run $n: FAIL — $FAIL_REASON"; kill_wine; return 1
}

test_current_wine() {   # $1 = label, $2 = step dir
  local label=$1 dir=$2 n
  for (( n = 1; n <= RUNS; n++ )); do
    if run_once "$n" "$dir"; then
      printf '%s\t%s\tGOOD\t%s\n' "$(date '+%F %T')" "$label" "$STEP_NOTE" >>"$SUMMARY"; return 0
    fi
  done
  printf '%s\t%s\tBAD\t%s\n' "$(date '+%F %T')" "$label" "$FAIL_REASON" >>"$SUMMARY"
  return 1
}

# ---------- build ----------
build_wine() {
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR" || return 1
  if [[ ! -f Makefile || "$WINE_SRC/configure" -nt config.status ]]; then
    log "configure"
    "$WINE_SRC/configure" "${CONFIGURE_ARGS[@]}" >>"$STEP_LOG" 2>&1 || return 1
  fi
  log "make -j$MAKE_JOBS"
  if ! make -j"$MAKE_JOBS" >>"$STEP_LOG" 2>&1; then
    log "build failed — reconfiguring and retrying once"
    "$WINE_SRC/configure" "${CONFIGURE_ARGS[@]}" >>"$STEP_LOG" 2>&1 || return 1
    make -j"$MAKE_JOBS" >>"$STEP_LOG" 2>&1 || return 1
  fi
  WINE="$BUILD_DIR/wine"; WINESERVER="$BUILD_DIR/server/wineserver"
  [[ -x $WINE && -x $WINESERVER ]]
}

# point WINE/WINESERVER at an AppImage or a directory of wine binaries
use_prebuilt() {   # $1 = target, $2 = scratch dir for argv0 symlinks
  local target=$1 bindir d
  if [[ -f $target ]]; then           # AppImage: dispatches on argv0, like OuDedetai's symlinks
    bindir="$2/bin"; mkdir -p "$bindir"
    ln -sf "$target" "$bindir/wine"; ln -sf "$target" "$bindir/wine64"; ln -sf "$target" "$bindir/wineserver"
    [[ -x $target ]] || chmod +x "$target"
    WINE="$bindir/wine64"; WINESERVER="$bindir/wineserver"; return 0
  fi
  for d in "$target/bin" "$target"; do
    if [[ -e $d/wine64 || -e $d/wine ]]; then
      if [[ -e $d/wine64 ]]; then WINE="$d/wine64"; else WINE="$d/wine"; fi
      WINESERVER="$d/wineserver"
      [[ -e $WINESERVER ]] || return 1
      return 0
    fi
  done
  return 1
}

# ---------- commands ----------
cmd_setup() {
  mkdir -p "$GITHUB_DIR"
  if [[ -d $WINE_SRC/.git ]]; then
    [[ -f $WINE_SRC/.wine-bisect ]] || abort "$WINE_SRC exists but wasn't made by this script — move it or set WINE_SRC"
    log "updating $WINE_SRC from $UPSTREAM_URL"
    git -C "$WINE_SRC" fetch --tags --prune origin || abort "fetch failed"
  else
    [[ -e $WINE_SRC ]] && abort "$WINE_SRC exists and is not a git repo"
    log "cloning $UPSTREAM_URL → $WINE_SRC (first time; this takes a while)"
    local ref=()
    [[ -n $REFERENCE_REPO ]] && ref=(--reference-if-able "$REFERENCE_REPO" --dissociate)
    git clone "${ref[@]}" "$UPSTREAM_URL" "$WINE_SRC" || abort "clone failed"
    : >"$WINE_SRC/.wine-bisect"
    printf '.wine-bisect\n' >>"$WINE_SRC/.git/info/exclude"   # marker stays untracked and invisible
    git -C "$WINE_SRC" config gc.auto 0                        # no surprise gc pauses mid-bisect
  fi
  log "latest tags: $(git -C "$WINE_SRC" tag --sort=-creatordate -l 'wine-*' | head -n5 | tr '\n' ' ')"
  echo
  echo "clone:   $WINE_SRC"
  echo "install: $INSTALL_DIR"
  echo "prefix:  $PRISTINE_PREFIX $( [[ -d $PRISTINE_PREFIX/drive_c ]] && echo '(ok)' || echo '(NOT FOUND)')"
  echo "work:    $WORK_DIR"
  echo "config:  ${CONF:-none (using defaults)}"
  local missing=() t
  for t in xdotool fuse-overlayfs ccache import; do have "$t" || missing+=("$t"); done
  (( ${#missing[@]} )) && echo "optional tools missing: ${missing[*]} (xdotool needed unless REQUIRE_WINDOW=0; import is from imagemagick)"
  return 0
}

cmd_test() {
  check_mirror
  check_common
  local commit subject dir
  commit=$(git -C "$WINE_SRC" rev-parse --short=12 HEAD)
  subject=$(git -C "$WINE_SRC" log -1 --format=%s HEAD)
  dir="$LOG_DIR/$commit"; mkdir -p "$dir"; STEP_LOG="$dir/step.log"; : >"$STEP_LOG"
  log "=== $commit $subject ==="
  if ! build_wine; then
    log "build failed → skip"
    printf '%s\t%s\tSKIP\tbuild failed\n' "$(date '+%F %T')" "$commit" >>"$SUMMARY"
    cleanup; exit $EXIT_SKIP
  fi
  if test_current_wine "$commit" "$dir"; then cleanup; exit $EXIT_GOOD; fi
  cleanup; exit $EXIT_BAD
}

cmd_test_wine() {
  local target=${1:-$INSTALL_DIR/bin}
  target=$(readlink -f "$target") || abort "$1 not found"
  check_common
  local label dir
  label=$(basename "$target"); [[ $target == "$(readlink -f "$INSTALL_DIR/bin")" ]] && label="install-bin"
  dir="$LOG_DIR/prebuilt-$label"; mkdir -p "$dir"
  STEP_LOG="$dir/step.log"; : >"$STEP_LOG"
  use_prebuilt "$target" "$dir" || abort "$target is not an AppImage or a folder with wine/wine64 and wineserver"
  [[ -e $(readlink -f "$WINE") ]] || abort "$WINE is a broken link — the install's bin/ may point at the original install's AppImage; pass the AppImage path instead"
  log "=== prebuilt $label ($WINE) ==="
  if test_current_wine "prebuilt:$label" "$dir"; then
    cleanup; echo "PASS  $label"; exit 0
  fi
  cleanup; echo "FAIL  $label — $FAIL_REASON"; exit 1
}

# Run Logos once IN the snapshot itself (the one deliberate write to it) with the install's
# own Wine, let the indexer finish, close cleanly — so every scratch copy starts settled.
cmd_settle() {
  REQUIRE_WINDOW=0
  check_common
  local dir="$LOG_DIR/settle" exe t=0
  mkdir -p "$dir"; STEP_LOG="$dir/step.log"; : >"$STEP_LOG"
  use_prebuilt "$(readlink -f "$INSTALL_DIR/bin")" "$dir" || abort "no usable Wine in $INSTALL_DIR/bin"
  [[ -e $(readlink -f "$WINE") ]] || abort "$WINE is a broken link"
  export WINEPREFIX="$PRISTINE_PREFIX" WINESERVER
  [[ -n $(prefix_pids 'Logos\.exe') ]] && abort "Logos is already running in the snapshot — close it first"
  exe=$(compgen -G "$WINEPREFIX/$LOGOS_EXE_REL" | head -n1)
  log "settle: launching Logos in the snapshot itself ($PRISTINE_PREFIX)"
  ( cd "$(dirname "$exe")" && exec env "${EXTRA_ENV[@]}" "$WINE" "$exe" "${LOGOS_ARGS[@]}" ) >>"$STEP_LOG" 2>&1 &
  LAUNCH_PID=$!; disown "$LAUNCH_PID"
  log "settle: waiting up to 120s for the indexer to start"
  while [[ -z $(prefix_pids "$INDEXER_REGEX") ]] && (( t < 120 )); do
    [[ -z $(prefix_pids 'Logos\.exe') ]] && (( t >= 15 )) && abort "Logos exited during settle — see $STEP_LOG"
    sleep 5; (( t += 5 ))
  done
  if [[ -z $(prefix_pids "$INDEXER_REGEX") ]]; then
    log "settle: indexer never started — nothing to index"
  else
    wait_for_indexer "$SETTLE_WAIT" || { shutdown_logos; abort "indexer didn't finish within ${SETTLE_WAIT}s"; }
  fi
  shutdown_logos
  WINEPREFIX=""   # keep cleanup away from the snapshot
  log "settle: done — run '$0 test-wine' and check the indexer note in '$0 status'"
}

cmd_run() {
  local good=${1:-} bad=${2:-}
  [[ -n $good && -n $bad ]] || abort "usage: $0 run <good-ref> <bad-ref>"
  check_mirror
  exec 9>"$WORK_DIR/.lock"; flock -n 9 || abort "another bisect is already running"
  cd "$WINE_SRC" || abort "cannot cd to $WINE_SRC"
  [[ -z $(git status --porcelain --untracked-files=no) ]] || abort "wine-mirror has local changes — it should stay pristine"
  git bisect reset >/dev/null 2>&1

  if [[ $VERIFY_ENDPOINTS == 1 ]]; then
    local orig rc; orig=$(git rev-parse HEAD)
    log "verifying good end: $good"
    git checkout -q "$good" || abort "cannot check out $good"
    "$SCRIPT_PATH" test; rc=$?
    (( rc == 0 )) || { git checkout -q "$orig"; abort "good ref $good did not pass (exit $rc) — fix the harness or choose another good ref"; }
    log "verifying bad end: $bad"
    git checkout -q "$bad" || abort "cannot check out $bad"
    "$SCRIPT_PATH" test; rc=$?
    (( rc == 1 )) || { git checkout -q "$orig"; abort "bad ref $bad did not fail (exit $rc) — regression not reproduced with this build"; }
    git checkout -q "$orig"
  fi

  log "starting bisect: good=$good bad=$bad (~$(git rev-list --count "$good..$bad") commits)"
  git bisect start "$bad" "$good" || abort "git bisect start failed"
  git bisect run "$SCRIPT_PATH" test
  local rc=$?
  git bisect log >"$WORK_DIR/bisect-$(date +%Y%m%d-%H%M).log"
  local result; result=$(git bisect log | grep -m1 '^# first bad commit' || echo "no result (git bisect run exit $rc)")
  log "DONE: $result"
  have notify-send && notify-send "Wine bisect finished" "$result"
  log "inspect with 'git -C $WINE_SRC bisect log'; finish with 'git -C $WINE_SRC bisect reset'"
}

cmd_status() {
  echo "clone:   $WINE_SRC"
  echo "prefix:  $PRISTINE_PREFIX"
  echo "work:    $WORK_DIR ($(du -sh "$WORK_DIR" 2>/dev/null | cut -f1))"
  if [[ -d $WINE_SRC/.git ]] && git -C "$WINE_SRC" bisect log >/dev/null 2>&1; then
    echo "bisect:  in progress, HEAD $(git -C "$WINE_SRC" log -1 --format='%h %s')"
    git -C "$WINE_SRC" bisect visualize --oneline 2>/dev/null | wc -l | xargs -I{} echo "         {} commits left in range"
  else
    echo "bisect:  none in progress"
  fi
  [[ -f $SUMMARY ]] && { echo; echo "results:"; tail -n 20 "$SUMMARY"; }
  return 0
}

case ${1:-} in
  setup)     cmd_setup ;;
  settle)    cmd_settle ;;
  test)      cmd_test ;;
  test-wine) shift; cmd_test_wine "$@" ;;
  run)       shift; cmd_run "$@" ;;
  status)    cmd_status ;;
  cleanup)   WINESERVER=${WINESERVER:-wineserver}; export WINEPREFIX="$RUN_DIR/prefix"; cleanup; echo cleaned ;;
  purge)     WINESERVER=${WINESERVER:-wineserver}; export WINEPREFIX="$RUN_DIR/prefix"; cleanup
             case $BUILD_DIR in "$WORK_DIR"/*) rm -rf --one-file-system "$BUILD_DIR" ;; esac
             echo "removed build and scratch; logs kept in $LOG_DIR" ;;
  *)         sed -n '2,30p' "$SCRIPT_PATH"; exit 2 ;;
esac
