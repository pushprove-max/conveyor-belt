#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: an Optimize card's build told the target (speedbrief()), and the owner's yes to a budget of its own for
# a test file whose cases cannot fit the budget (ownbudget(), card()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# One card of #7, an Optimize issue for f.test.sh (on main, `echo slow`), whose median on record is 10 CPU s (whole-suite
# runs of 9, 10 and 11), against the pack's test.fileBudget of 8. Each run under cards/mainrun/ names the cases one and
# two of each file of its list as passed and times each at 9 CPU s; the run for the build's brief (<card>.cases) logs
# them under its runner, run.test.sh, as a runner of case files does (the engine's conveyor/conveyor.test.sh). Its build speeds f.test.sh up and ends its reply
# with an OWN-BUDGET line for 9 CPU s; one GO review. The build's brief is kept in $STUB/brief.
ownstart() {
  setup "[$(issue 7 2026-01-01 bug | jq -c '.title = "Optimize the test file f.test.sh"')]"
  echo 'echo slow' > "$R/f.test.sh"
  git -C "$R" add f.test.sh && git -C "$R" commit -qm 'a slow test' && git -C "$R" push -q origin main || fail "main's file"
  echo "$GO" > "$STUB/review.1"; : > "$STUB/comments"
  echo 'echo fast > f.test.sh; echo "{\"type\":\"result\",\"result\":\"Done.\\nOWN-BUDGET: 9 CPU s: each case starts a whole loop\"}"' > "$STUB/build"
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
  STOP="visible to customers or staff: needs Dana's yes: a budget of its own for the test file f.test.sh: 9 CPU s: each case starts a whole loop"
  steps() { st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,; }
  budget() { jq -c '.test.files["f.test.sh"].budget' "$R/.conveyor/project.json"; }
}

# Bugs it catches: the build of an Optimize card is not told the target (#158 split into 4 files where a split alone
# needed many more), so it splits blindly; its brief says the count of cases is not known when the runner logs them
# under its own name; a build that finds the cases cannot fit the budget has no way out but to be
# blocked and retried. Its brief gives the CPU seconds on record, the budget, the cases with their average, the files a
# split alone would need and how a split is checked; the card it ends with an OWN-BUDGET line stops for the owner's yes
# under Needs you, with nothing landed and no budget set. Retried with no yes (the owner's no), it stops again with no
# build and no review, and still no budget is set; the owner's yes does not set the budget, or the card is built or
# reviewed again for it: the approval line, given back by the next turn, sets test.files' budget of f.test.sh to 9 in
# the pack, and the card lands from its kept patch with no second build or review. One card on one main, as each step
# needs the one before it.
t_ownbudget() {
  ownstart
  for l in 'The test file f.test.sh used 10 CPU s on record (the median of its runs), and its budget is 8 CPU s (the pack'"'"'s test.fileBudget).' \
    'It has 2 cases, about 5 CPU s each on average (its runner does not give the CPU seconds of each case).' \
    'A split alone would need 2 files of at most 1 cases each to fit the budget, with a start-up allowance of 1 CPU s for each file.'; do
    grep -qxF "$l" "$STUB/brief" || fail "the build's brief lacks the line: $l"
  done
  grep -qF 'The check passes a split only when every case passes, each file is at or under its budget, and the files'"'"' CPU seconds summed are at most the CPU seconds on record plus the start-up allowance for each file the split adds. So a split into fewer files does not pass: make the heavy cases faster, or make the split finer.' "$STUB/brief" \
    && grep -qF 'end your reply with one line, exactly: `OWN-BUDGET: <the CPU s the file reached> CPU s: <why its cases cannot fit the budget>`' "$STUB/brief" \
    || fail "the build's brief does not say how a split is checked, or how to propose a budget of its own"
  # The reason starts as a visible change's stop does (YES), which is what lists a card under Needs you.
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = "$STOP" ] || fail "the card did not stop for Dana's yes to the budget: $(steps)"
  [ "$(budget)" = null ] && [ -z "$(st 'select(.step == "landed")')" ] || fail "the stop set the budget or landed: $(budget), $(steps)"
  sessions=$(wc -l < "$STUB/sessions")
  out=$(loop retry 7) && grep -q "stops again for Dana's yes on the kept patch" <<<"$out" || fail "retry with no yes does not say the card stops again: $out"
  loop run >/dev/null || fail "run of the retry with no yes exited non-zero"
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason' | tail -n 1)" = "$STOP" ] && [ "$(wc -l < "$STUB/sessions")" = "$sessions" ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] \
    || fail "a retry with no yes did not stop again with no build and no review: $(steps)"
  [ "$(budget)" = null ] || fail "the budget was set with no yes: $(budget)"
  issue 7 2026-01-01 bug | jq -c '[.title = "Optimize the test file f.test.sh" | .body += "\n\nVisible change approved: Dana 2026-01-02 (yes)\n"]' > "$STUB/issues.json"
  loop run >/dev/null || fail "run after the approval line exited non-zero"
  [ "$(budget)" = 9 ] || fail "the yes did not set the budget of f.test.sh: $(budget)"
  [ "$(st 'select(.issue == 7 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] \
    || fail "the approved card did not land from its kept patch with no second build or review: $(steps)"
}

# Bug it catches: only Claude's result event is read for the OWN-BUDGET line, so a Codex or OpenCode build that ends
# its reply with one is blocked and retried in place of stopping for the owner's yes. Each reply's last line is the
# proposal, read from that builder's own output: Codex's agent message (exec --json), OpenCode's text part (run
# --format json), each after an earlier message that is not the reply.
t_ownbudgetagents() {
  local w=$T/$CASE/w got
  mkdir -p "$T/$CASE"
  jq -cn '{type: "thread.started"}, {type: "item.completed", item: {type: "agent_message", text: "Reading the file."}},
    {type: "item.completed", item: {type: "agent_message", text: "Done.\nOWN-BUDGET: 9 CPU s: each case starts a whole loop"}}, {type: "turn.completed"}' > "$w.out"
  got=$(export STATE=$T/$CASE/cards.jsonl; . "$SRC/lib/testrun.sh" && ownbudget "$w") && [ "$got" = $'9\teach case starts a whole loop' ] || fail "a Codex build's OWN-BUDGET line was not read: '$got'"
  jq -cn '{type: "text", part: {text: "Reading the file."}}, {type: "text", part: {text: "Done.\nOWN-BUDGET: 9.5 CPU s: each case starts a whole loop"}}, {type: "step_finish"}' > "$w.out"
  got=$(export STATE=$T/$CASE/cards.jsonl; . "$SRC/lib/testrun.sh" && ownbudget "$w") && [ "$got" = $'9.5\teach case starts a whole loop' ] || fail "an OpenCode build's OWN-BUDGET line was not read: '$got'"
}
