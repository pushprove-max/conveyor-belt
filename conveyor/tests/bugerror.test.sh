#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a run of the bug-card check on main's code (bugproof.sh testfailed()) that failed is proof only when its
# test command could run and, when the issue gives the bug's own error (a body line `Bug error: <text>`), its output holds
# that text. The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run
# alone, this file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# bugtest() (bugproof.test.sh; the runner sources every case file before it runs a case) on an issue whose body is <body>,
# with the new test <test>, which fails on main's code (the fix adds the line it greps for). RC and BW are the check's
# exit and reason.
bugerr() { # <body> <test>
  local ISSUE
  # shellcheck disable=SC2034 # ISSUE is read by bugwt(), which bugtest() calls
  ISSUE=$(jq -cn --arg b "$1" '{number: 7, body: $b}')
  bugtest "$2"
}
# The check refused the failed run with NOTBUG, and the result the review is shown says <text>.
notbug() { # <text the result must say>
  local nb="the new tests fail without the fix, but not with the bug's own error"
  [ "$RC" = 1 ] && [ "$BW" = "$nb" ] && grep -qF -- "$1" "$FXWT.unfixed" && grep -qF -- "$nb" "$FXWT.unfixed" \
    || fail "the failed run was not refused with NOTBUG saying '$1' (exit $RC, reason '$BW'): $(head -n 8 "$FXWT.unfixed" 2>&1)"
}

# Bug it catches: a test file whose command could not run (exit 127: a runner that is not installed) counted as a test
# that fails without the fix. The file runner (fileeach()) turns the file's exit into 1 and logs `-- FAIL`, which is
# proof for an issue that names no error. The check fails with the NOTBUG reason, and the result says the command could
# not run.
t_bugcmdnotrun() {
  bugtest 'exit 127'
  notbug 'the test command could not run (exit 127'
}

# Bug it catches: a test command that exits 126 or 127 itself (a command that writes no logs, so any exit but 0 was
# proof) counted as a failing test. Called as the check calls it, with the exit and no logs; an exit of 1 is still proof.
t_bugcmdexit() {
  setup '[]'
  local w=$T/$CASE/w r
  r=$(eng "for x in 126 127 1; do testfailed '$w' \$x '{}' && echo \"\$x proof\" || echo \"\$x none: \$NOTBUGWHY\"; done")
  [ "$r" = $'126 none: the test command could not run (exit 126)\n127 none: the test command could not run (exit 127)\n1 proof' ] \
    || fail "testfailed() did not refuse exits 126 and 127 and accept exit 1 with no logs: $r"
}

# Bug it catches: a file that runs past its time limit without the bug's own error in its output was blocked (exit 2) as
# a run with no result for the file, as noresult() sees no result for a timed out file, so the build never heard that its
# test fails for another reason. The check fails with NOTBUG (exit 1), as for any other failure without the error.
t_bugerrorhung() {
  TUNE='.tunables.testTimeout = 15' bugerr $'Bug error: index out of range' $'# timeout: 1\n'"$(wait_fn)"$'\nwait_poll grep -qx two a.txt' # the new test's own wait, which goes on past its limit on main's code
  notbug 'does not hold "index out of range"'
}

# Bug it catches: bugnamed() (a change that selects no test of its own, proved by the test file its issue's Done-when
# names) did not give the issue to testfailed(), so a named test that fails without the fix with another error proved
# it. The named test fails on main's comment, with no word of the issue's error.
t_bugnamederror() {
  commentwt '! grep -q old s.sh' $'body\nBug error: index out of range\n\n## Done when\nw.test.sh fails on main and passes with the fix.'
  notbug 'does not hold "index out of range"'
}

# Bug it catches: a new test that fails without the fix with the bug's own error was refused, or the error was not
# found through the colour codes the runner puts in its output.
t_bugerrorfound() {
  bugerr $'Title\nBug error: index out of range' 'printf "panic: \033[31mindex out\033[0m of range\n"; grep -qx two a.txt' # no single quote: bugtest() puts the test in one
  [ "$RC" = 0 ] || fail "a new test that fails without the fix with the issue's Bug error text did not prove it (exit $RC): $BW: $(head -n 8 "$FXWT.unfixed" 2>&1)"
}

# Bug it catches: a new test that fails without the fix for another reason (a typo, a missing file) proved the fix.
# The check fails with NOTBUG, and the result names the text that was not found.
t_bugerrorother() {
  bugerr $'Bug error: index out of range' 'echo "cannot find module"; grep -qx two a.txt'
  notbug 'does not hold "index out of range"'
}

# Bug it catches: the compare of the error was not exact in case (a fixed string), so a failure with other letters
# in the text proved the fix.
t_bugerrorcase() {
  bugerr $'Bug error: index out of range' 'echo "INDEX OUT OF RANGE"; grep -qx two a.txt'
  notbug 'does not hold "index out of range"'
}

# Bug it catches: a `Bug error:` line of under 8 characters was taken for the error, or a later line was read when
# the first was too short. Only the first such line is read, and it names no error here, so the check is as it is with
# no such line: a failure by an assertion proves the fix.
t_bugerrorshort() {
  bugerr $'Bug error: x\nBug error: index out of range' 'echo "cannot find module"; grep -qx two a.txt'
  [ "$RC" = 0 ] || fail "a Bug error line of under 8 characters held the check to a later line (exit $RC): $BW: $(head -n 8 "$FXWT.unfixed" 2>&1)"
}
