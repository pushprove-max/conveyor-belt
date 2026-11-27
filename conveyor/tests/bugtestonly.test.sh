#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the bug-card check (bugproof.sh bugproof(), pagesonly()) on a change whose fix lives in a test file it
# changes, with a page beside it that no test reads, and on changes whose other files can be the fix (#1819).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# #1819 D1. Bug it catches: a bug card that fixes a bug in its own test file and changes a page beside it (a skill's
# notes) was blocked twice with "the new tests pass without the fix": its fixed test passes on main's code, and no
# build could make it fail there. No test reads notes.md (no map, no link, no file but a page names it), so the change is test-only: it is not run
# on main, the check holds, and the result and the card's `bugproof` line (result skipped) say why, naming the page.
t_bugtestmd() {
  FIX='echo "The test reads one." > notes.md' bugtest 'grep -qx one a.txt'
  [ "$RC" = 0 ] && [ ! -e "$STUB/mainran" ] \
    || fail "a change of a.test.sh and notes.md (a page no test reads) was run on main or failed the check (exit $RC): $BW $(cat "$STUB/mainran" 2>&1)"
  local why='the change is test-only but for pages that no test reads (no file but a page names them, and the test map and its links give them no test: notes.md), so it has no fix to take out'
  grep -qxF -- "${why^}, and its tests were not run on main's code." "$FXWT.unfixed" \
    || fail "the result of a change of a.test.sh and notes.md does not say it is test-only but for notes.md: $(cat "$FXWT.unfixed" 2>&1)"
  [ "$(st 'select(.step == "bugproof") | [.result, .reason] | join(": ")')" = "skipped: $why" ] \
    || fail "the record of a change of a.test.sh and notes.md has no bugproof line, result skipped, naming notes.md: $(st 'select(.step == "bugproof")')"
}

# #1819. Bug it catches: a page that tests read taken as no fix, so a change of a page a program loads (the fix) and a
# test that passes on main's code skipped the check. .conveyor/test-links.json links notes.md to a.test.sh: the test
# runs on main's code, passes there, and the card is refused as before, with no `bugproof` line saying it was skipped.
t_bugmdtest() {
  FIX='echo "The steps." > notes.md' bugtest 'grep -qx one a.txt' .conveyor/test-links.json '{"notes.md": ["a.test.sh"]}'
  [ "$RC" = 1 ] && [ "$BW" = "the new tests pass without the fix, so they do not prove it" ] && [ "$(grep -c '/cards/mainrun/' "$STUB/mainran")" = 1 ] \
    || fail "a change of notes.md (linked to a.test.sh) and a.test.sh (passes on main) was not refused after a run on main (exit $RC): $BW $(cat "$STUB/mainran" 2>&1)"
  [ -z "$(st 'select(.step == "bugproof")' 2>/dev/null)" ] || fail "a change of notes.md (linked to a.test.sh) and a.test.sh was recorded as skipping the check: $(st 'select(.step == "bugproof")')"
}

# #1819. Bug it catches: a change of pages alone (no test file) taken as test-only, so it skipped the proof by the
# tests its issue names (bugnamed()) and its result said it was test-only. Its issue names none, so it is skipped as
# before, with that reason.
t_bugmdonly() {
  FIX='echo "The steps." > notes.md' bugtest ''
  [ "$RC" = 0 ] && ! grep -q 'test-only' "$FXWT.unfixed" && [ "$(st 'select(.step == "bugproof") | .reason')" != "" ] \
    && ! st 'select(.step == "bugproof") | .reason' | grep -q 'test-only' \
    || fail "a change of notes.md alone was taken as test-only, or not proved by its issue's tests (exit $RC): $(cat "$FXWT.unfixed" 2>&1) $(st 'select(.step == "bugproof")')"
}

# #1819 D2. Bug it catches: the check of a change with product code and a test it adds gets weaker, or a page beside
# them makes it count as test-only. A change of a.txt (the fix), notes.md (a page no test reads) and a new b.test.sh
# that passes on main's code is run there and refused as before, with no `bugproof` line saying it was skipped.
t_bugcodeadd() {
  FIX='echo two >> a.txt; echo "The steps." > notes.md' TF=b.test.sh bugtest 'grep -qx one a.txt'
  [ "$RC" = 1 ] && [ "$BW" = "the new tests pass without the fix, so they do not prove it" ] && [ "$(grep -c '/cards/mainrun/' "$STUB/mainran")" = 1 ] \
    || fail "a change of a.txt, notes.md and a new b.test.sh (passes on main) was not refused after a run on main (exit $RC): $BW $(cat "$STUB/mainran" 2>&1)"
  [ -z "$(st 'select(.step == "bugproof")' 2>/dev/null)" ] || fail "a change of a.txt, notes.md and b.test.sh was recorded as skipping the check: $(st 'select(.step == "bugproof")')"
}
