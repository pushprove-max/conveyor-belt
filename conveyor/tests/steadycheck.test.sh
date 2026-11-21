#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the check of a Fix failures card (speedproof.sh steadyproof(), #188): its test file runs alone 10 times in a row with
# the change, on a test slot, and every run must pass.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# speedproof.sh steadyproof() called as card() calls it, on card c7 of #7, whose change runs <change> in its worktree on main, where
# f.test.sh is a test file. Each run under cards/mainrun/ counts itself in $STUB/steady-runs and runs the file its list
# names `fail`: its case one passes, and its case two fails in the run whose number <failing run> gives (none with
# 0). The check's exit is in $RC, the first line of what the review is shown in $WHY.
steadyrun() { # <change> <failing run>
  local wt=$T/$CASE/cards/c7
  setup '[]'
  echo 'echo ok' > "$R/f.test.sh" && echo 'exit 1' > "$R/g.test.sh" && git -C "$R" add f.test.sh g.test.sh && git -C "$R" commit -qm 'tests' || fail "main's files"
  echo "$2" > "$STUB/steady-bad"
  # As .conveyor/test-changed.sh does, the command runs what the change selects (both files here) and the files its
  # list names `fail`, less those it names `pass`; g.test.sh always fails.
  cat > "$STUB/mainrun-cmd" <<'EOF'
echo run >> "$STUB/steady-runs"; n=$(wc -l < "$STUB/steady-runs"); x=0
for f in $( { printf '%s\n' f.test.sh g.test.sh; awk -F'\t' '$1 == "fail" {print $2}' "$CONVEYOR_TEST_RERUN"; } | sort -u); do
  grep -qxF "pass"$'\t'"$f" "$CONVEYOR_TEST_RERUN" && continue
  echo "== $f"; echo "== $f" >> "$CONVEYOR_TEST_LOG/r.log"; echo "ok one"
  if [ "$f" = g.test.sh ] || [ "$n" = "$(cat "$STUB/steady-bad")" ]; then echo "FAIL [two]: the port is in use"; echo "-- FAIL $f" >> "$CONVEYOR_TEST_LOG/r.log"; x=1
  else echo "ok two"; echo "-- ok $f" >> "$CONVEYOR_TEST_LOG/r.log"; fi
done
[ "$x" = 0 ]
EOF
  git -C "$R" worktree add -q --detach "$wt" && (cd "$wt" && eval "$1") && git -C "$wt" add -A || fail "the card's change could not be staged"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 9
    names || exit 9
    steadyproof c7 "$wt" f.test.sh ) > "$T/$CASE/run.out" 2>&1; RC=$?
  [ "$RC" != 9 ] || fail "the engine could not be loaded: $(cat "$T/$CASE/run.out")"
  WHY=$(head -n 1 "$wt.unfixed" 2>/dev/null)
}
# Named STEADY*: every case file is sourced into one shell, and bugproof.test.sh reads FIX.
STEADYFIX='echo "echo steady" > f.test.sh'

# Bug it catches: a Fix failures card landed on one run that passed, while the file still failed one run in a few. It
# passes once each of its 10 runs in a row passed with the change. And: the runs were not alone, as the command ran
# the other files the change selects too (g.test.sh, which fails), as their list named only the file.
t_steadypass() {
  steadyrun "$STEADYFIX" 0
  [ "$RC" = 0 ] || fail "a file that passed 10 runs in a row was refused: $WHY $(cat "$T/$CASE/run.out")"
  [ "$(wc -l < "$STUB/steady-runs")" = 10 ] || fail "the file did not run 10 times: $(wc -l < "$STUB/steady-runs")"
  grep -qF 'it passed in each of 10 runs in a row' "$T/$CASE/cards/c7.unfixed" || fail "the review is not told the file passed 10 runs: $(cat "$T/$CASE/cards/c7.unfixed")"
}

# Bug it catches: a file that still fails one run in ten landed as fixed. The card is refused naming the run that
# failed and its failing case, and no run is made after it.
t_steadyfail() {
  steadyrun "$STEADYFIX" 4
  [ "$RC" != 0 ] || fail "a file that failed its 4th run passed the check"
  [ "$WHY" = 'the test file f.test.sh failed in run 4 of 10 with the change, alone on a test slot (exit 1): its failing cases: two' ] || fail "the reason: $WHY"
  grep -qF 'FAIL [two]: the port is in use' "$T/$CASE/cards/c7.unfixed" || fail "the review is not shown the end of the run that failed: $(cat "$T/$CASE/cards/c7.unfixed")"
  [ "$(wc -l < "$STUB/steady-runs")" = 4 ] || fail "runs were made after the one that failed: $(wc -l < "$STUB/steady-runs")"
}

# A whole card, for what only it proves: card() checks a bug card filed by the Board's Fix failures by its title.
# Bug it catches: such a card, whose test passes on main by design, was held to the bug-card check (a test that fails
# on main without the fix) and blocked, or landed with no proof it passes reliably. Its file runs 10 times with the
# change, the review is shown the Fix failures check, and the card lands.
t_steadycard() {
  setup "[$(issue 7 2026-01-01 bug | jq -c '.title = "Fix the failures of the test file f.test.sh"')]"
  echo 'echo flaky' > "$R/f.test.sh" && git -C "$R" add f.test.sh && git -C "$R" commit -qm 'a test' && git -C "$R" push -q origin main || fail "main's file"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"; echo "$STEADYFIX" > "$STUB/build"
  cat > "$STUB/mainrun-cmd" <<'EOF'
while IFS=$'\t' read -r k f; do
  [ "$k" = fail ] || continue; echo "$f: $(cat "$f")" >> "$STUB/steady-runs"
  echo "== $f"; echo "ok one"; printf '== %s\n-- ok %s\n' "$f" "$f" >> "$CONVEYOR_TEST_LOG/r.log"
done < "$CONVEYOR_TEST_RERUN"
EOF
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(sort -u "$STUB/steady-runs")" = 'f.test.sh: echo steady' ] && [ "$(wc -l < "$STUB/steady-runs")" = 10 ] || fail "the file did not run 10 times with the change: $(cat "$STUB/steady-runs" 2>&1)"
  grep -qx '# The Fix failures check' "$STUB/asked" && grep -qF 'it passed in each of 10 runs in a row' "$STUB/asked" || fail "the review was not shown the Fix failures check"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "a Fix failures card that passed 10 runs did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}

# Bug it catches: a card that deleted the failing file passed the check, as nothing was left to fail.
t_steadygone() {
  steadyrun 'rm f.test.sh' 0
  [ "$RC" != 0 ] && [ "$WHY" = 'the change removes the test file f.test.sh: a Fix failures card keeps it and what it tests' ] || fail "a change that removes the file was not refused: $RC $WHY"
  [ ! -e "$STUB/steady-runs" ] || fail "the removed file was run"
}
