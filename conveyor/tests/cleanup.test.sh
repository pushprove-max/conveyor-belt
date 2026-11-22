#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a cleanup follow-up (#872): a last review's finding marked [cleanup] (its fix changes no behaviour) is
# filed without the bug label (followups(), lib/followups.sh), so its card skips the bug-card check (card(), lib/card.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: a finding marked [cleanup] is filed as a bug, so its card, which changes one line and holds no test file, is
# sent back to build and blocked by the bug-card check, as no test can fail on main for it; or a finding with no mark
# is filed as a cleanup, so its card skips the check. The two findings of one last NO-GO of #7 are filed as the card
# files them; then the cleanup follow-up's card runs. That part is a whole card run (the loop): the check is skipped
# in cardbuild() by the issue's labels, which no engine function returns alone.
t_cleanup() {
  setup "[$(issue 7 2026-01-01)]"
  printf '%s\n' '[P3][cleanup] a.txt:1 the second check is redundant. Proof: line 1 already checks it' \
    '[P3] a.txt:2 the word is wrong. Proof: a.txt line 2 reads "two"' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[100101,100102]' ] || fail "the two follow-ups were not filed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -rs 'map(.labels | map(.name) | join(" ")) | join("|")' "$STUB/filed")" = 'conveyor-followup|conveyor-followup bug' ] \
    || fail "the cleanup finding was filed with the bug label, or the unmarked one without it: $(cat "$STUB/filed")"
  [ "$(jq -rs 'map(.body | test("\nCleanup: the finding changes no behaviour")) | tojson' "$STUB/filed")" = '[true,false]' ] \
    || fail "the cleanup follow-up's body does not say it changes no behaviour, or the bug's does: $(cat "$STUB/filed")"
  # The cleanup follow-up's card, its parent landed: it changes one line of a.txt and holds no test file (as a bug, the
  # check would find no test file and block it). The reviewer's prompt is kept in $STUB/asked.
  jq -cs '[.[0] + {authorAssociation: "OWNER"}]' "$STUB/filed" > "$STUB/issues.json" && landed 7 '[100101,100102]' >> "$ST/cards.jsonl" \
    || fail "the follow-up's issue"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"; echo 'echo two >> a.txt' > "$STUB/build"
  echo 'pwd >> "$STUB/mainran"' > "$STUB/mainrun-cmd"
  loop run --only 100101 >/dev/null || fail "run of #100101 exited non-zero"
  [ "$(st 'select(.issue == 100101 and .step == "build") | .result' | wc -l)" = 1 ] && [ ! -e "$STUB/mainran" ] \
    && [ -z "$(st 'select(.issue == 100101 and .step == "blocked")')" ] && [ -n "$(st 'select(.issue == 100101 and .step == "landed") | .sha')" ] \
    || fail "the cleanup card was checked as a bug, sent back to build or blocked: $(st 'select(.issue == 100101 and (.step | IN("build", "bugproof", "blocked", "landed")))')"
  grep -q '^Cleanup: the finding changes no behaviour' "$STUB/asked" || fail "the review was not given the issue's Cleanup line: $(head -c 2000 "$STUB/asked")"
}
