# DESCRIPTION: Logos starts and shows its main window, with no crash, within 60 seconds
#
# Good: after LAUNCH_WAIT seconds Logos.exe is still running in the prefix, has a visible
#       window whose title matches WINDOW_REGEX, and no winedbg crash dialog appeared.
# Bad:  Logos exits, crashes, or never shows its window.
# After a pass it waits for the Logos indexer to finish, then closes Logos gracefully.
#
# Needs a copy of a working OuDedetai install (INSTALL_DIR): logged in, fully indexed,
# updates off. Run `wine-bisect.sh settle` once so test runs don't re-index.
#
# Settings (override in wine-bisect.conf):
: "${LOGOS_EXE_REL:=drive_c/users/*/AppData/Local/Logos/Logos.exe}"
: "${LAUNCH_WAIT:=60}"           # seconds Logos must survive
: "${POLL_INTERVAL:=5}"
: "${EARLY_FAIL_POLLS:=3}"       # Logos absent this many polls in a row (after 15s) → fail early
: "${REQUIRE_WINDOW:=1}"         # also require a visible window (needs xdotool)
: "${WINDOW_REGEX:=Logos}"
: "${SHUTDOWN_WAIT:=45}"         # seconds to wait for a graceful close before forcing
: "${INDEXER_REGEX:=LogosIndexer\.exe}"
: "${INDEXER_WAIT:=600}"         # max seconds to wait for the indexer after a pass
: "${SETTLE_WAIT:=7200}"         # max seconds `settle` waits for a full index
declare -p LOGOS_ARGS >/dev/null 2>&1 || LOGOS_ARGS=()

[[ $REQUIRE_WINDOW == 1 ]] && TEST_TOOLS=(xdotool)

test_check() {
  compgen -G "$PRISTINE_PREFIX/$LOGOS_EXE_REL" >/dev/null || abort "Logos.exe not found at $PRISTINE_PREFIX/$LOGOS_EXE_REL"
}

logos_exe() { compgen -G "$WINEPREFIX/$LOGOS_EXE_REL" | head -n1; }

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
  wine_run taskkill /IM Logos.exe   # no /F → WM_CLOSE
  local t=0
  while [[ -n $(prefix_pids 'Logos\.exe') ]] && (( t < SHUTDOWN_WAIT )); do sleep 1; ((t++)); done
  [[ -n $(prefix_pids 'Logos\.exe') ]] && log "Logos ignored close after ${SHUTDOWN_WAIT}s — forcing"
  kill_wine
}

test_run() {
  local exe t=0 missing=0 idx_seen=0
  exe=$(logos_exe)
  [[ -n $exe ]] || { FAIL_REASON="Logos.exe missing in $WINEPREFIX"; return 2; }

  log "run $RUN_NO: launching Logos, waiting ${LAUNCH_WAIT}s"
  wine_start "$exe" "${LOGOS_ARGS[@]}"

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
    elif [[ $REQUIRE_WINDOW == 1 ]] && ! window_visible 'Logos\.exe' "$WINDOW_REGEX"; then
      FAIL_REASON="Logos running but no visible '$WINDOW_REGEX' window"
    fi
  fi
  screenshot "$STEP_DIR/run$RUN_NO.png"
  [[ -n $FAIL_REASON ]] && return 1

  wait_for_indexer "$INDEXER_WAIT"
  if   (( INDEXER_SECS < 0 ));             then STEP_NOTE="indexer still running after ${INDEXER_WAIT}s"
  elif (( INDEXER_SECS > 30 ));            then STEP_NOTE="indexer ran ~$(( LAUNCH_WAIT + INDEXER_SECS ))s — prefix may need 'settle'"
  elif (( idx_seen || INDEXER_SECS > 0 )); then STEP_NOTE="indexer: quick"
  fi
  shutdown_logos
  return 0
}

# Run Logos in the real prefix with the install's own Wine until the indexer finishes.
test_settle() {
  local exe t=0
  exe=$(logos_exe)
  [[ -n $exe ]] || { log "Logos.exe missing in $WINEPREFIX"; return 1; }
  log "settle: launching Logos in $WINEPREFIX"
  wine_start "$exe" "${LOGOS_ARGS[@]}"
  log "settle: waiting up to 120s for the indexer to start"
  while [[ -z $(prefix_pids "$INDEXER_REGEX") ]] && (( t < 120 )); do
    [[ -z $(prefix_pids 'Logos\.exe') ]] && (( t >= 15 )) && { log "Logos exited during settle"; return 1; }
    sleep 5; (( t += 5 ))
  done
  if [[ -z $(prefix_pids "$INDEXER_REGEX") ]]; then
    log "settle: indexer never started — nothing to index"
  else
    wait_for_indexer "$SETTLE_WAIT" || { shutdown_logos; log "indexer didn't finish within ${SETTLE_WAIT}s"; return 1; }
  fi
  shutdown_logos
  return 0
}
