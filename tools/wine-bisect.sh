#!/usr/bin/env bash
# wine-bisect.sh — unattended Wine regression hunting with swappable tests.
#
# Builds Wine from a dedicated clone (~/Documents/GitHub/wine-mirror) at each bisect step,
# prepares a Wine prefix, runs a TEST against it and reports good/bad to `git bisect run`.
# Build failures are skipped (125); harness failures abort (255), so a broken environment
# is never blamed on a Wine commit.
#
# The test decides what "good" means. Tests live in bisect-tests/ next to this script;
# choose one with TEST=<name> in the config or environment (default: logos-starts).
# See bisect-tests/README.md for the available tests and how to write one.
#
# Usage:
#   wine-bisect.sh setup                           clone/update wine-mirror, check tools
#   wine-bisect.sh tests                           list the available tests
#   wine-bisect.sh settle                          let the test prepare the prefix once, if it
#                                                  needs to (logos-starts: finish indexing)
#   wine-bisect.sh test-wine [AppImage|wine-dir]   test a prebuilt Wine, no build. No argument =
#                                                  the install's own bin/ Wine (sanity check)
#   wine-bisect.sh run <good-ref> <bad-ref>        verify both ends, then bisect unattended
#   wine-bisect.sh test                            build + test current checkout (git bisect run calls this)
#   wine-bisect.sh status                          show paths, bisect state and results so far
#   wine-bisect.sh cleanup                         kill leftover wineserver, unmount scratch prefix
#   wine-bisect.sh purge                           cleanup + delete build dir and scratch (keeps logs)
#
# Where things live (all overridable in the config):
#   ~/Documents/GitHub/wine-mirror   dedicated Wine clone; bisect state lives here only
#   ~/wine-bisect-prefix             a copied OuDedetai install (or any folder with a Wine
#                                    prefix), plus this script, bisect-tests/ and the config
#   ~/.cache/wine-bisect/            build tree, logs, summary.tsv (and scratch prefixes)
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
: "${TEST:=logos-starts}"               # test name in bisect-tests/, or a path to a test file
: "${GITHUB_DIR:=$HOME/Documents/GitHub}"
: "${WINE_SRC:=$GITHUB_DIR/wine-mirror}"
: "${UPSTREAM_URL:=https://gitlab.winehq.org/wine/wine.git}"
: "${REFERENCE_REPO:=}"                 # optional existing local wine clone to copy objects from (fast, then dissociated)
# install folder (an OuDedetai install has data/ and bin/). If this script lives in it, that's the default.
if [[ -d $SCRIPT_DIR/data/wine64_bottle ]]; then : "${INSTALL_DIR:=$SCRIPT_DIR}"; fi
: "${INSTALL_DIR:=$HOME/wine-bisect-prefix}"
: "${PRISTINE_PREFIX:=}"                # derived from INSTALL_DIR if empty
: "${WORK_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/wine-bisect}"
: "${BUILD_DIR:=$WORK_DIR/build}"
: "${MAKE_JOBS:=$(nproc)}"
: "${PREFIX_MODE:=inplace}"             # inplace = use the prefix itself (default);
                                        # overlay | copy = throwaway copy per run
: "${RUNS:=2}"                          # attempts per step; good on the first pass, bad if all fail
: "${WINEBOOT:=1}"                      # 0 = skip the explicit wineboot -u (Wine then updates the prefix implicitly)
: "${WINEBOOT_TIMEOUT:=300}"
: "${USE_XVFB:=0}"
: "${VERIFY_ENDPOINTS:=1}"
declare -p CONFIGURE_ARGS >/dev/null 2>&1 || CONFIGURE_ARGS=(--enable-archs=i386,x86_64 --disable-tests)
declare -p EXTRA_ENV      >/dev/null 2>&1 || EXTRA_ENV=(WINEDEBUG=-all "WINEDLLOVERRIDES=winemenubuilder.exe=d")
# Applied on top of EXTRA_ENV for the wineboot -u step only: stops the Wine Mono / Gecko
# install prompts. Tests run their programs with EXTRA_ENV alone.
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
STEP_DIR=""
WINE="" WINESERVER="" LAUNCH_PID="" XVFB_PID=""
FAIL_REASON="" STEP_NOTE="-"

mkdir -p "$WORK_DIR" "$LOG_DIR"

# ---------- helpers (also used by tests) ----------
log()   { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$MAIN_LOG" >&2; [[ $STEP_LOG != /dev/null ]] && printf '### %s\n' "$*" >>"$STEP_LOG"; }
abort() { log "ABORT: $*"; cleanup; exit $EXIT_ABORT; }
have()  { command -v "$1" >/dev/null 2>&1; }

# PIDs of processes whose command line matches $1 AND that run in our prefix
prefix_pids() {
  local pid
  for pid in $(pgrep -f -- "$1" 2>/dev/null); do
    tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -qxF "WINEPREFIX=$WINEPREFIX" && echo "$pid"
  done
}

# true once no wineserver runs for our prefix (an idle one lingers a few seconds after programs exit)
prefix_idle() {
  local t=0
  while [[ -n $(prefix_pids 'wineserver') ]]; do (( t++ >= 15 )) && return 1; sleep 1; done
  return 0
}

# visible X window owned by a process in our prefix whose command line matches $1, title matching $2
window_visible() {
  local pid
  for pid in $(prefix_pids "$1"); do
    xdotool search --all --onlyvisible --pid "$pid" --name "$2" >/dev/null 2>&1 && return 0
  done
  return 1
}

screenshot() {   # $1 = file
  if have import; then import -window root "$1" 2>/dev/null
  elif have grim; then grim "$1" 2>/dev/null
  fi
}

# run a Wine command in the foreground with EXTRA_ENV, output to the step log
wine_run() { env "${EXTRA_ENV[@]}" "$WINE" "$@" >>"$STEP_LOG" 2>&1; }

# start a Windows program in the background from its own folder; sets LAUNCH_PID
wine_start() {   # $1 = program path (Unix), rest = arguments
  local exe=$1; shift
  ( cd "$(dirname "$exe")" && exec env "${EXTRA_ENV[@]}" "$WINE" "$exe" "$@" ) >>"$STEP_LOG" 2>&1 &
  LAUNCH_PID=$!; disown "$LAUNCH_PID"
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

# ---------- load the test ----------
if [[ $TEST == */* ]]; then TEST_FILE=$(readlink -f "$TEST"); else TEST_FILE="$SCRIPT_DIR/bisect-tests/$TEST.sh"; fi
if [[ -f $TEST_FILE ]]; then
  TEST_NAME=$(basename "$TEST_FILE" .sh)
  TEST_TOOLS=()
  # shellcheck source=/dev/null
  source "$TEST_FILE"
  declare -F test_run >/dev/null || { echo "test $TEST_FILE does not define test_run" >&2; exit $EXIT_ABORT; }
else
  TEST_NAME="" TEST_FILE_MISSING=$TEST_FILE
fi

# ---------- environment checks ----------
check_test_loaded() {
  [[ -n $TEST_NAME ]] || abort "test '$TEST' not found ($TEST_FILE_MISSING) — keep bisect-tests/ next to $SCRIPT_PATH, or run '$0 tests'"
}

check_common() {
  check_test_loaded
  [[ -d $PRISTINE_PREFIX/drive_c ]] || abort "no Wine prefix at $PRISTINE_PREFIX (set INSTALL_DIR or PRISTINE_PREFIX)"
  case $PREFIX_MODE in inplace|overlay|copy) ;; *) abort "PREFIX_MODE must be inplace, overlay or copy" ;; esac
  [[ $PREFIX_MODE == overlay ]] && ! have fuse-overlayfs && abort "PREFIX_MODE=overlay but fuse-overlayfs is not installed"
  local t
  for t in "${TEST_TOOLS[@]}"; do have "$t" || abort "test '$TEST_NAME' needs '$t' — install it, or see the test's settings"; done
  if [[ $USE_XVFB == 1 ]]; then
    have Xvfb || abort "USE_XVFB=1 but Xvfb is not installed"
    local d=:97
    Xvfb "$d" -screen 0 1920x1080x24 -nolisten tcp >/dev/null 2>&1 &
    XVFB_PID=$!; disown "$XVFB_PID"; export DISPLAY=$d; sleep 2
    kill -0 "$XVFB_PID" 2>/dev/null || abort "Xvfb failed to start"
  fi
  [[ -n ${DISPLAY:-} ]] || abort "no DISPLAY — run from your desktop session or set USE_XVFB=1"
  if declare -F test_check >/dev/null; then test_check; fi
}

check_mirror() {
  [[ -d $WINE_SRC/.git ]] || abort "no wine clone at $WINE_SRC — run '$0 setup' first"
  [[ -f $WINE_SRC/.wine-bisect ]] || abort "$WINE_SRC was not created by '$0 setup' — refusing to bisect in another repo"
}

# ---------- prefix ----------
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
    prefix_idle || abort "something is already running in $WINEPREFIX — close it first"
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

# ---------- one attempt: prefix, wineboot, then the test ----------
run_once() {   # $1 = attempt number
  RUN_NO=$1
  FAIL_REASON="" STEP_NOTE="-"
  setup_prefix || abort "could not prepare prefix ($PREFIX_MODE)"
  export WINESERVER

  if [[ $WINEBOOT == 1 ]]; then
    log "run $RUN_NO: wineboot -u"
    if ! timeout "$WINEBOOT_TIMEOUT" env "${EXTRA_ENV[@]}" "${WINEBOOT_ENV[@]}" "$WINE" wineboot -u >>"$STEP_LOG" 2>&1; then
      FAIL_REASON="wineboot failed or timed out"; log "run $RUN_NO: FAIL — $FAIL_REASON"; kill_wine; return 1
    fi
    timeout 120 "$WINESERVER" -w >/dev/null 2>&1
  fi

  local rc
  log "run $RUN_NO: test '$TEST_NAME'"
  test_run; rc=$?
  kill_wine
  case $rc in
    0) if [[ $STEP_NOTE == - ]]; then log "run $RUN_NO: PASS"; else log "run $RUN_NO: PASS ($STEP_NOTE)"; fi
       return 0 ;;
    1) [[ -n $FAIL_REASON ]] || FAIL_REASON="test failed"
       log "run $RUN_NO: FAIL — $FAIL_REASON"; return 1 ;;
    *) abort "test '$TEST_NAME' returned $rc (${FAIL_REASON:-no reason}) — that's a test problem, not a Wine result" ;;
  esac
}

test_current_wine() {   # $1 = label, $2 = step dir
  local label=$1 n
  STEP_DIR=$2
  for (( n = 1; n <= RUNS; n++ )); do
    if run_once "$n"; then
      printf '%s\t%s\t%s\tGOOD\t%s\n' "$(date '+%F %T')" "$TEST_NAME" "$label" "$STEP_NOTE" >>"$SUMMARY"; return 0
    fi
  done
  printf '%s\t%s\t%s\tBAD\t%s\n' "$(date '+%F %T')" "$TEST_NAME" "$label" "$FAIL_REASON" >>"$SUMMARY"
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
  echo "test:    ${TEST_NAME:-NOT FOUND ($TEST)}"
  echo "config:  ${CONF:-none (using defaults)}"
  local missing=() t
  for t in "${TEST_TOOLS[@]}"; do have "$t" || missing+=("$t"); done
  (( ${#missing[@]} )) && echo "needed by the test but missing: ${missing[*]}"
  missing=()
  for t in fuse-overlayfs ccache import; do have "$t" || missing+=("$t"); done
  (( ${#missing[@]} )) && echo "optional tools missing: ${missing[*]} (import is from imagemagick, for screenshots)"
  return 0
}

cmd_tests() {
  local f
  echo "available tests (choose with TEST=<name>; current: ${TEST_NAME:-$TEST}):"
  for f in "$SCRIPT_DIR"/bisect-tests/*.sh; do
    [[ -f $f ]] || continue
    printf '  %-16s %s\n' "$(basename "$f" .sh)" "$(sed -n 's/^# *DESCRIPTION: *//p' "$f" | head -n1)"
  done
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
    printf '%s\t%s\t%s\tSKIP\tbuild failed\n' "$(date '+%F %T')" "$TEST_NAME" "$commit" >>"$SUMMARY"
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

# Let the test prepare the prefix itself, once, with the install's own Wine
# (logos-starts: let the indexer finish so test runs don't re-index).
cmd_settle() {
  check_common
  declare -F test_settle >/dev/null || { echo "test '$TEST_NAME' needs no settling"; return 0; }
  STEP_DIR="$LOG_DIR/settle"; mkdir -p "$STEP_DIR"; STEP_LOG="$STEP_DIR/step.log"; : >"$STEP_LOG"
  use_prebuilt "$(readlink -f "$INSTALL_DIR/bin")" "$STEP_DIR" || abort "no usable Wine in $INSTALL_DIR/bin"
  [[ -e $(readlink -f "$WINE") ]] || abort "$WINE is a broken link"
  export WINEPREFIX="$PRISTINE_PREFIX" WINESERVER
  prefix_idle || abort "something is already running in $WINEPREFIX — close it first"
  test_settle || { kill_wine; WINEPREFIX=""; abort "settle failed — see $STEP_LOG"; }
  kill_wine
  WINEPREFIX=""   # keep cleanup away from the real prefix
  log "settle: done — now run '$0 test-wine'"
}

cmd_run() {
  local good=${1:-} bad=${2:-}
  [[ -n $good && -n $bad ]] || abort "usage: $0 run <good-ref> <bad-ref>"
  check_mirror
  check_test_loaded
  exec 9>"$WORK_DIR/.lock"; flock -n 9 || abort "another bisect is already running"
  cd "$WINE_SRC" || abort "cannot cd to $WINE_SRC"
  [[ -z $(git status --porcelain --untracked-files=no) ]] || abort "wine-mirror has local changes — it should stay pristine"
  git bisect reset >/dev/null 2>&1

  if [[ $VERIFY_ENDPOINTS == 1 ]]; then
    local orig rc; orig=$(git rev-parse HEAD)
    log "verifying good end: $good (test '$TEST_NAME')"
    git checkout -q "$good" || abort "cannot check out $good"
    "$SCRIPT_PATH" test; rc=$?
    (( rc == 0 )) || { git checkout -q "$orig"; abort "good ref $good did not pass (exit $rc) — fix the harness or choose another good ref"; }
    log "verifying bad end: $bad"
    git checkout -q "$bad" || abort "cannot check out $bad"
    "$SCRIPT_PATH" test; rc=$?
    (( rc == 1 )) || { git checkout -q "$orig"; abort "bad ref $bad did not fail (exit $rc) — regression not reproduced with this build"; }
    git checkout -q "$orig"
  fi

  log "starting bisect: good=$good bad=$bad test='$TEST_NAME' (~$(git rev-list --count "$good..$bad") commits)"
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
  echo "test:    ${TEST_NAME:-NOT FOUND ($TEST)}"
  echo "work:    $WORK_DIR ($(du -sh "$WORK_DIR" 2>/dev/null | cut -f1))"
  if [[ -d $WINE_SRC/.git ]] && git -C "$WINE_SRC" bisect log >/dev/null 2>&1; then
    echo "bisect:  in progress, HEAD $(git -C "$WINE_SRC" log -1 --format='%h %s')"
    git -C "$WINE_SRC" bisect visualize --oneline 2>/dev/null | wc -l | xargs -I{} echo "         {} commits left in range"
  else
    echo "bisect:  none in progress"
  fi
  [[ -f $SUMMARY ]] && { echo; echo "results (time, test, build, result, note):"; tail -n 20 "$SUMMARY"; }
  return 0
}

case ${1:-} in
  setup)     cmd_setup ;;
  tests)     cmd_tests ;;
  settle)    cmd_settle ;;
  test)      cmd_test ;;
  test-wine) shift; cmd_test_wine "$@" ;;
  run)       shift; cmd_run "$@" ;;
  status)    cmd_status ;;
  cleanup)   WINESERVER=${WINESERVER:-wineserver}; export WINEPREFIX="$RUN_DIR/prefix"; cleanup; echo cleaned ;;
  purge)     WINESERVER=${WINESERVER:-wineserver}; export WINEPREFIX="$RUN_DIR/prefix"; cleanup
             case $BUILD_DIR in "$WORK_DIR"/*) rm -rf --one-file-system "$BUILD_DIR" ;; esac
             echo "removed build and scratch; logs kept in $LOG_DIR" ;;
  *)         sed -n '2,33p' "$SCRIPT_PATH"; exit 2 ;;
esac
