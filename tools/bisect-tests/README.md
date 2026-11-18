# Bisect tests

`wine-bisect.sh` builds Wine and prepares the prefix; a **test** decides whether that
Wine is good or bad. Choose one with `TEST=<name>` in `wine-bisect.conf`, or for a
single command: `TEST=run-program ./wine-bisect.sh test-wine`.
`./wine-bisect.sh tests` lists what's available.

| Test | Good when… |
|---|---|
| `logos-starts` (default) | Logos starts, shows its main window and doesn't crash within 60 s |
| `run-program` | any Windows program exits with the expected code and/or prints the expected text |

Each test's settings are at the top of its file. Put the ones you change in
`wine-bisect.conf`.

## Before trusting a new test

`wine-bisect.sh run` first checks that the good end passes and the bad end fails, and
stops if not. Still, try the test by hand with `test-wine` on a known-good and a
known-bad Wine (AppImages are fine) **twice each**. A test that sometimes passes on a
bad Wine sends the bisect the wrong way without any warning. `RUNS=2` (the default)
counts a step as bad only if every attempt fails, which protects against occasional
failures on a good Wine, but not against occasional passes on a bad one.

## Writing a test

A test is a bash file in this folder, `<name>.sh`. The harness sources it, so it can
use the harness's variables and helpers. Start the file with a description line, which
`wine-bisect.sh tests` shows:

```bash
# DESCRIPTION: what "good" means, in one line
```

Then define settings with defaults, so the config can override them:

```bash
: "${MY_TIMEOUT:=60}"
TEST_TOOLS=(xdotool)          # optional: commands the test needs
```

and these functions:

| Function | Required | Called | Return |
|---|---|---|---|
| `test_run` | yes | once per attempt, after the prefix is ready and `wineboot -u` has run | `0` good, `1` bad (set `FAIL_REASON`), anything else = the test itself is broken, which stops the bisect |
| `test_check` | no | once before anything else | call `abort "message"` if something it needs is missing |
| `test_settle` | no | by `wine-bisect.sh settle`, with the install's own Wine in the real prefix | `0` done, `1` failed |

Inside these functions you have:

| Name | What |
|---|---|
| `$WINE`, `$WINESERVER`, `$WINEPREFIX` | the Wine under test and the prefix to use |
| `$PRISTINE_PREFIX`, `$INSTALL_DIR` | the configured prefix and install folder |
| `$STEP_DIR` | folder for this step's files (screenshots, output) |
| `$STEP_LOG` | the step's log file; Wine output goes here |
| `$RUN_NO` | attempt number (1…`RUNS`) |
| `"${EXTRA_ENV[@]}"` | environment for Wine commands, e.g. `WINEDEBUG` |
| `FAIL_REASON=…` | why it failed, shown in the log and `status` |
| `STEP_NOTE=…` | a short note on a pass, shown in `status` |
| `log "text"` | write to the screen and the logs |
| `abort "text"` | stop the whole bisect (problem with the test setup, not with Wine) |
| `wine_run args…` | run a Wine command in the foreground, output to the step log |
| `wine_start exe args…` | start a program in the background from its own folder (sets `LAUNCH_PID`) |
| `prefix_pids regex` | PIDs of matching processes running in this prefix |
| `window_visible proc-regex title-regex` | true if such a process has a visible window (needs `xdotool`) |
| `screenshot file` | screenshot of the display (needs `import` or `grim`) |
| `kill_wine` | stop everything in the prefix (the harness also does this after each attempt) |

Rules that keep bisects honest:

- **Only return `1` for a Wine problem.** If the test can't run (missing file, wrong
  setting), use `abort` or return `2`, so no commit gets blamed for it.
- **Leave nothing running.** The harness kills the prefix's wineserver after every
  attempt, but close programs gracefully if they write state (as `logos-starts` does).
- **Don't change the prefix permanently** unless that's the point. With the default
  `PREFIX_MODE=inplace`, every step uses the same prefix.

`logos-starts.sh` is a full example; `run-program.sh` is a short one.
