#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a test file the slow-test record names comes off card test steps until the card of its "Slow test"
# issue lands, and runs only in the full test suite (testrun.sh slowoffs(), slowoff()), in whole card runs. Its own
# file, so its whole card run runs beside budgetkept.test.sh's.
# The helpers (reviews, landedone) are budget.test.sh's, ftended fulltest.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue 457 (the owner, 2026-11-14: a heavy test took the machine from every other card). The slow-test record holds
# #100101 for s.test, as the "Slow test" filing the test rules replaced (#519) kept it: s.test at 6.5 CPU s in card
# c0-8's run, 6 in c0-5's, over a 5 CPU s budget. The test command reads its list as a runner does: it runs no file the
# list names as passed. Bug it catches: card #7's test step ran s.test again, and every card waited for it. It does
# not, and the full test suite, given no list, runs it. Health lists it with why (the snapshot's slowOff); the card of
# #100101 itself runs it; and once that card lands it is back on card test steps.
t_budgetoff() {
  setup "$(jq -cs . <(issue 7 2026-01-01))"
  for i in 1 2 3 4; do echo "$GO" > "$STUB/review.$i"; done
  echo '9 6.5' > "$R/s.test"; git -C "$R" add s.test; git -C "$R" commit -qm s; git -C "$R" push -q origin main
  tune '.test.full = ". \"$STUB/test-cmd\""'
  cat >> "$STUB/test-cmd" <<'EOF'
for f in *.test; do
  [ -f "$f" ] && ! awk -F'\t' -v f="$f" '$1 == "pass" && $2 == f { x = 1 } END { exit !x }' "${CONVEYOR_TEST_RERUN:-/dev/null}" || continue
  echo "$PWD $f" >> "$STUB/timedruns"; printf '== %s\n-- ok %s\nTESTRUN sec\t%s\t%s\t%s\n' "$f" "$f" "$f" $(tail -n 1 "$f") >> "$CONVEYOR_TEST_LOG/r.log"
done
EOF
  jq -cn '{filed: [{file: "s.test", issue: 100101, cpu: 6.5, sec: 9, budget: 5, card: "c0-8", last: {cpu: 6, card: "c0-5"}, since: "2026-11-02T00:00:00Z"}]}' > "$ST/slow.json"
  loop run --only 7 1 > /dev/null 2>&1 && landedone 7 || fail "#7 did not land"
  ! grep -q -- '-7 s\.test$' "$STUB/timedruns" 2> /dev/null || fail "#7's test step ran s.test, kept off card test steps: $(cat "$STUB/timedruns")"
  loop full-test > /dev/null || fail "the full test suite did not start"; ftended 1
  [ "$(grep -c ' s\.test$' "$STUB/timedruns")" = 1 ] || fail "the full test suite did not run s.test: $(cat "$STUB/timedruns")"
  [ ! -s "$STUB/filed" ] || fail "an issue was filed: $(cat "$STUB/filed")"
  [ "$(loop snapshot | jq -c '.slowOff | map({file, issue, cpu, budget, card, last})')" = '[{"file":"s.test","issue":100101,"cpu":6.5,"budget":5,"card":"c0-8","last":{"cpu":6,"card":"c0-5"}}]' ] \
    || fail "the snapshot does not list s.test kept off with why: $(loop snapshot | jq -c .slowOff)"
  # The card of #100101 itself runs s.test (its change is what makes it cheaper): its list keeps nothing off; another's does.
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && slowoff "$T/$CASE/c0-100101" && slowoff "$T/$CASE/c0-9" ) \
    || fail "slowoff failed"
  [ ! -e "$T/$CASE/c0-100101.rerun" ] && [ "$(cat "$T/$CASE/c0-9.rerun" 2>&1)" = $'pass\ts.test\noff\ts.test' ] \
    || fail "the card of s.test's own issue keeps it off, or another card does not: $(cat "$T/$CASE/c0-100101.rerun" "$T/$CASE/c0-9.rerun" 2>&1)"
  landed 100101 >> "$ST/cards.jsonl"
  [ "$(loop snapshot | jq -c .slowOff)" = '[]' ] || fail "s.test stayed off after its issue's card landed: $(loop snapshot | jq -c .slowOff)"
}
