#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: an Optimize card's build told the target (speedbrief()), and no budget of its own for a test file: no
# test file has a CPU budget (#349), so an OWN-BUDGET line a build ends with stops nothing and sets nothing (card()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# One card of #7, an Optimize issue for f.test.sh (on main, `echo slow`), whose median on record is 10 CPU s (whole-suite
# runs of 9, 10 and 11); the pack still holds the old test.fileBudget of 8. Each run under cards/mainrun/ names the
# cases one and two of each file of its list as passed and times each at 9 CPU s; the run for the build's brief
# (<card>.cases) logs them under its runner, run.test.sh, as a runner of case files does (the engine's
# conveyor/conveyor.test.sh). Its build speeds f.test.sh up and ends its reply with an OWN-BUDGET line for 9 CPU s; one
# GO review. The build's brief is kept in $STUB/brief. With an argument, the build is that reply's text alone: it
# changes no file.
ownstart() {
  setup "[$(issue 7 2026-01-01 bug | jq -c '.title = "Optimize the test file f.test.sh"')]"
  tune '.test.fileBudget = 8'
  echo 'echo slow' > "$R/f.test.sh"
  git -C "$R" add f.test.sh && git -C "$R" commit -qm 'a slow test' && git -C "$R" push -q origin main || fail "main's file"
  echo "$GO" > "$STUB/review.1"; : > "$STUB/comments"
  echo 'echo fast > f.test.sh; echo "{\"type\":\"result\",\"result\":\"Done.\\nOWN-BUDGET: 9 CPU s: each case starts a whole loop\"}"' > "$STUB/build"
  [ -z "${1:-}" ] || jq -cn --arg r "$1" '{type: "result", result: $r}' | jq -Rr '"echo \(@sh)"' > "$STUB/build"
  for c in 9 10 11; do
    jq -cn --argjson c "$c" '{time: "2026-11-01T00:00:00Z", how: "full", sha: "abc", files: {"f.test.sh": {result: "ok", sec: $c, cpu: $c}}}' >> "$ST/suiteruns.jsonl"
  done
  cat > "$STUB/mainrun-cmd" <<'EOF'
while IFS=$'\t' read -r k f; do
  [ "$k" = fail ] || continue; l=$f; [[ $PWD != *.cases ]] || l=run.test.sh; printf '== %s\nok one\nok two\n' "$l"
  printf '== %s\n-- ok %s\nTESTRUN sec\t%s\t1\t9\n' "$l" "$l" "$f" >> "$CONVEYOR_TEST_LOG/r"
done < "$CONVEYOR_TEST_RERUN"
EOF
  loop run >/dev/null || fail "run exited non-zero"
  steps() { st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,; }
  files() { jq -c '.test.files' "$R/.conveyor/project.json"; }
}

# Bugs it catches: the build of an Optimize card is not told the target (#158 split into 4 files where a split alone
# needed many more), so it splits blindly; its brief says the count of cases is not known when the runner logs them
# under its own name. Its brief gives the CPU seconds on record, the cases with their average and how a split is
# checked, and names no budget (#349: the pack's test.fileBudget is ignored). A build that ends with an OWN-BUDGET line
# (the old way out for cases that could not fit the budget) does not stop for the owner's yes: the card lands on its
# one review, and no budget is set in the pack.
t_ownbudget() {
  ownstart
  for l in 'The test file f.test.sh used 10 CPU s on record (the median of its runs).' \
    'It has 2 cases, about 5 CPU s each on average (its runner does not give the CPU seconds of each case).'; do
    grep -qxF "$l" "$STUB/brief" || fail "the build's brief lacks the line: $l"
  done
  grep -qF 'The check passes a split only when every case passes and the files'"'"' CPU seconds summed are at most the CPU seconds on record plus a start-up allowance of 1 CPU s' "$STUB/brief" \
    && ! grep -qiE 'OWN-BUDGET|fileBudget|budget of' "$STUB/brief" \
    || fail "the build's brief does not say how a split is checked, or still names a budget: $(grep -iE 'budget|split' "$STUB/brief")"
  [ -z "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" ] \
    && [ "$(st 'select(.issue == 7 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] \
    || fail "the card with an OWN-BUDGET line did not land on its one review: $(steps)"
  [ "$(files)" = null ] || fail "an OWN-BUDGET line set a budget in the pack: $(files)"
}

# Bug it catches: a build that changes nothing and ends with an OWN-BUDGET line stops for the owner's yes to a budget
# no file can have now. It is blocked as a session that made no change (nochange()), with no review and no budget set.
t_ownnochange() {
  ownstart $'Nothing to split.\nOWN-BUDGET: 9 CPU s: each case starts a whole loop'
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = "the session made no change, so there is nothing to review" ] && [ ! -s "$STUB/reviews" ] \
    || fail "the no-change build with an OWN-BUDGET line did not go to nochange(): $(steps)"
  [ "$(files)" = null ] || fail "an OWN-BUDGET line set a budget in the pack: $(files)"
}
