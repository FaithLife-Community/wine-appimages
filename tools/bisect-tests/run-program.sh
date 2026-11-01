# DESCRIPTION: run any Windows program; good if it exits with the expected code and/or prints the expected text
#
# A general test for regressions you can reproduce with one command, so no new test
# code is needed. Examples:
#
#   Wine's own conformance test, built for Windows (see docs/testing.md):
#     TEST=run-program
#     PROGRAM="$HOME/tests/dwrite_test.exe"
#     PROGRAM_ARGS=(font)
#
#   A program in the prefix that crashes in the bad Wine:
#     TEST=run-program
#     PROGRAM='C:\Program Files\Example\app.exe'
#     PROGRAM_ARGS=(--version)
#     EXPECT_EXIT=0
#
# Settings (set in wine-bisect.conf):
: "${PROGRAM:=}"               # Unix path, or a Windows path inside the prefix (C:\...)
: "${PROGRAM_TIMEOUT:=300}"    # seconds; a program still running then counts as bad
: "${EXPECT_EXIT:=0}"          # exit code that means good; empty = don't check
: "${EXPECT_REGEX:=}"          # extended regex the output must match; empty = don't check
: "${REJECT_REGEX:=}"          # extended regex the output must NOT match; empty = don't check
declare -p PROGRAM_ARGS >/dev/null 2>&1 || PROGRAM_ARGS=()

test_check() {
  [[ -n $PROGRAM ]] || abort "TEST=run-program needs PROGRAM set in the config"
  if [[ $PROGRAM != [A-Za-z]:\\* ]]; then
    [[ -f $PROGRAM ]] || abort "PROGRAM '$PROGRAM' not found"
  fi
  [[ -n $EXPECT_EXIT || -n $EXPECT_REGEX || -n $REJECT_REGEX ]] ||
    abort "run-program: set at least one of EXPECT_EXIT, EXPECT_REGEX, REJECT_REGEX"
}

test_run() {
  local out="$STEP_DIR/run$RUN_NO.out" rc
  log "run $RUN_NO: $PROGRAM ${PROGRAM_ARGS[*]} (timeout ${PROGRAM_TIMEOUT}s)"
  timeout "$PROGRAM_TIMEOUT" env "${EXTRA_ENV[@]}" "$WINE" "$PROGRAM" "${PROGRAM_ARGS[@]}" >"$out" 2>&1
  rc=$?
  cat "$out" >>"$STEP_LOG"
  if (( rc == 124 )); then FAIL_REASON="still running after ${PROGRAM_TIMEOUT}s"; return 1; fi
  if [[ -n $EXPECT_EXIT ]] && (( rc != EXPECT_EXIT )); then
    FAIL_REASON="exit code $rc, expected $EXPECT_EXIT"; return 1
  fi
  if [[ -n $EXPECT_REGEX ]] && ! grep -Eq -- "$EXPECT_REGEX" "$out"; then
    FAIL_REASON="output doesn't match '$EXPECT_REGEX'"; return 1
  fi
  if [[ -n $REJECT_REGEX ]] && grep -Eq -- "$REJECT_REGEX" "$out"; then
    FAIL_REASON="output matches '$REJECT_REGEX': $(grep -Em1 -- "$REJECT_REGEX" "$out" | cut -c1-120)"; return 1
  fi
  STEP_NOTE="exit $rc"
  return 0
}
