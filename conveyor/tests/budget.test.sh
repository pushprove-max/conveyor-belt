#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a test file that uses more than the pack's CPU budget (test.fileBudget, CPU seconds, not clock seconds)
# in a card's run is a note on its test line, never a finding of its review (testrun.sh slowtests(), card.sh); only a
# test rule files an issue about it (testrules.test.sh). Its cases of whole card runs are split, so that no file is
# over that budget itself: budgetrun.test.sh, budgetkept.test.sh and budgetwait.test.sh, which use this file's helpers.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A test command that, in a worktree, times each <name>.test at the clock and CPU seconds its last line holds
# (`<sec> <cpu>`), as a runner does in its log (`TESTRUN sec`): the time is the file's own, so main's s.test and a
# card's edit of it time apart. Each file it runs is noted in $STUB/timedruns, `<folder> <file>`.
budgetcmd() { echo 'for f in *.test; do [ ! -f "$f" ] || { echo "$PWD $f" >> "$STUB/timedruns"; printf "== %s\n-- ok %s\nTESTRUN sec\t%s\t%s\t%s\n" "$f" "$f" "$f" $(tail -n 1 "$f") >> "$CONVEYOR_TEST_LOG/r.log"; }; done' >> "$STUB/test-cmd"; }
# Issues 7 and 8, every review a GO. With '<main seconds> <main CPU seconds>', main has s.test of those, before any card.
budgetsetup() { # [main seconds and CPU seconds]
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-01-02))"
  for i in 1 2 3 4; do echo "$GO" > "$STUB/review.$i"; done
  [ -z "${1:-}" ] || { echo "$1" > "$R/s.test"; git -C "$R" add s.test; git -C "$R" commit -qm s; git -C "$R" push -q origin main; }
  budgetcmd
}
reviews() { st "select(.step == \"review\" and .issue == $1) | .result" | tr '\n' ' '; } # <issue>
slowof() { st "select(.step == \"test\" and .issue == $1) | .slow | tojson" | head -n 1; } # <issue>: its first test line's slow
landedone() { [ "$(st "select(.step == \"landed\" and .issue == $1) | .issue")" = "$1" ]; } # <issue>

# The owner, 2026-11-14: a slow-test finding is a note and never stops a card. Bug caught (#459): a card whose test step
# passed with a file over the budget went back through review, a fix and its whole test step again, for a file slowed
# only by the machine's load. A card adds a test file that burns 10 CPU s (10.2 s clock), over the default 8 CPU s
# budget: it lands on its one passing run, with one review and one test step, and its test line names the file. No
# card run before it timed the file, so nothing is reported.
t_budgetover() {
  budgetsetup; echo 'echo two >> a.txt; echo 10.2 10 > s.test' > "$STUB/build"
  loop run --only 7 1 > /dev/null 2>&1 || fail "run exited non-zero"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test landed " ] \
    || fail "a slow file sent #7 to another review or test step: $(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')"
  [ "$(reviews 7)" = "GO " ] || fail "the review was given the slow file as a finding: $(reviews 7)"
  [ "$(slowof 7)" = '[{"file":"s.test","sec":10.2,"cpu":10,"budget":8,"changed":true}]' ] || fail "the test line does not record the slow file: $(slowof 7)"
  [ ! -s "$STUB/filed" ] || fail "a file slow in one card run was reported: $(cat "$STUB/filed")"
  [ -z "$(jq -Rn -f "$SRC/jq/check.jq" < "$ST/cards.jsonl")" ] || fail "the record check refuses a line"
  landedone 7 || fail "the card did not land"
  # The Board's Tests bar shows the note (jq/rows.jq, jq/track.jq): bug caught, it was on the test line alone.
  [ "$(loop snapshot | jq -c '[.landed[0].track.records[] | select(.name == "tests passed") | .slow]')" = '[[{"file":"s.test","cpu":10}]]' ] \
    || fail "the snapshot's track does not carry the note: $(loop snapshot | jq -c '.landed[0].track.records')"
}

# The before of a file the change modifies, read from the records (slowtests(), beforetimes()), with slowtests()
# called alone: main has s.test, u.test and o.test; a worktree of main ($T/$CASE/wt) whose staged change edits each,
# and its run's log timing them at <s> <u> <o> CPU s, with a 1 CPU s budget. With <survey json>, main's
# .conveyor/test-times.json holds it, written by a commit of 2026-11-10 (the fixture's .gitignore names .conveyor, so -f). bt_slow: the files over the budget, as the
# test line holds them (slow).
bt_wt() { # <s> <u> <o> [survey json]
  local w=$T/$CASE/wt f
  setup '[]'; tune '.test.fileBudget = 1'
  for f in s u o; do echo "$f" > "$R/$f.test"; done; git -C "$R" add s.test u.test o.test && git -C "$R" commit -qm tests || fail "main's tests"
  [ -z "${4:-}" ] || { echo "$4" > "$R/.conveyor/test-times.json" && git -C "$R" add -f .conveyor/test-times.json \
    && GIT_COMMITTER_DATE=2026-11-10T00:00:00Z git -C "$R" commit -qm survey; } || fail "main's survey"
  git -C "$R" worktree add -q --detach "$w" && for f in s u o; do echo more >> "$w/$f.test"; done && git -C "$w" add s.test u.test o.test \
    && mkdir -p "$w.testlog" || fail "the card's worktree"
  printf 'TESTRUN sec\ts.test\t%s\t%s\nTESTRUN sec\tu.test\t%s\t%s\nTESTRUN sec\to.test\t%s\t%s\n' 9 "$1" 9 "$2" 9 "$3" > "$w.testlog/r.log"
}
bt_test() { jq -cn --arg c "$1" --argjson n "$2" --arg t "$3" --argjson x "$4" '{card: $c, issue: $n, step: "test", time: $t, # <card> <issue> <time> <times>
  tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: "", times: $x}'; }
bt_landed() { landed "$1" | jq -c --arg t "$2" '.time = $t'; } # <issue> <time>
bt_slow() {
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && slowtests "$T/$CASE/wt" \
    && jq -c 'map({file, before, from})' "$T/$CASE/wt.slow" )
}
# Bug caught (#429): the before came from running the file again on main. Here it is the record of the newest card that
# ran the file and landed: #5 recorded s.test at 2 CPU s; #6, which did not land, at 3. s.test, now 3, has #5's 2;
# o.test, at 1.5 with no record, over the budget, has none; u.test, at 0.5, under it, is not on the line.
t_budgetrecord() {
  bt_wt 3 0.5 1.5
  { bt_test c0-5 5 2026-11-01T00:00:00Z '{"s.test": 2}'; bt_landed 5 2026-11-01T01:00:00Z
    bt_test c0-6 6 2026-11-02T00:00:00Z '{"s.test": 3}'; } >> "$ST/cards.jsonl"
  got=$(bt_slow) || fail "slowtests failed: $got"
  [ "$got" = '[{"file":"s.test","before":2,"from":"card #5, 2026-11-01"},{"file":"o.test","before":null,"from":null}]' ] \
    || fail "the files over the budget and their befores: $got"
}
# Bug caught: a before taken from one record when a newer one holds the file. s.test: card #5 (landed 2026-11-01) at
# 2, the survey of 2026-11-10 at 2.6: 2.6. o.test: the survey at 2.6, card #6 (landed 2026-11-12) at 2: 2.
t_budgetnewer() {
  bt_wt 3 0.5 3 '{"files": {"s.test": {"sec": 3, "cpu": 2.6}, "o.test": {"sec": 3, "cpu": 2.6}}}'
  { bt_test c0-5 5 2026-11-01T00:00:00Z '{"s.test": 2}'; bt_landed 5 2026-11-01T01:00:00Z
    bt_test c0-6 6 2026-11-12T00:00:00Z '{"o.test": 2}'; bt_landed 6 2026-11-12T01:00:00Z; } >> "$ST/cards.jsonl"
  got=$(bt_slow) || fail "slowtests failed: $got"
  [ "$got" = '[{"file":"s.test","before":2.6,"from":"test-speed survey, 2026-11-10"},{"file":"o.test","before":2,"from":"card #6, 2026-11-12"}]' ] \
    || fail "the before of each file is not its newest record: $got"
}

# Bug caught: the engine's runner timed no case file, so an engine case file a card added or slowed was never a
# finding. Each case is timed (run_case), and a case file is timed only when the run ran its every case: the sum of
# their times. Bug caught too (the budget is CPU seconds): no case's CPU seconds were measured, so a case file's were
# not known. The probe case burns CPU in the process the case runs in: run_case's measure of it is that CPU, its
# children's times after the case less those before (`times`, in either locale's point).
t_budgetcasetimes() {
  local d=$T/$CASE i
  mkdir -p "$d/in"
  t_budget_probe() { local i=0; while [ $i -lt 100000 ]; do i=$((i + 1)); done; } # no case of the runner's (no t_ name has a _)
  ( T=$d/in; CASE=budget_probe; run_case ) > /dev/null 2>&1
  [[ $(cat "$d/in/budget_probe.sec" 2>/dev/null) =~ ^[0-9]+$ ]] || fail "run_case did not time its case: $(cat "$d/in/budget_probe.sec" 2>&1)"
  CASE_CPU=''; case_cpu "$d/in/budget_probe.cpu" && [ "$CASE_CPU" -ge 50 ] && [ "$CASE_CPU" -le $(( $(cat "$d/in/budget_probe.sec") / 1000 + 50 )) ] \
    || fail "run_case did not measure its case's CPU: '$CASE_CPU' ms: $(cat "$d/in/budget_probe.cpu" 2>&1)"
  printf 't_one() {\n}\nt_two() {\n}\n' > "$d/x.test.sh"; printf 't_one() {\n}\nt_three() {\n}\n' > "$d/y.test.sh"
  echo 2500000 > "$d/one.sec"; echo 3000000 > "$d/two.sec"; echo 1000000 > "$d/three.sec"
  for i in one three; do printf '0m0.010s 0m0.000s\n0m1.000s 0m0.500s\n0m0.010s 0m0.000s\n0m3.250s 0m0.750s\n' > "$d/$i.cpu"; done
  printf '0m0,000s 0m0,000s\n0m0,000s 0m0,000s\n0m0,000s 0m0,000s\n1m0,100s 0m0,000s\n' > "$d/two.cpu"
  got=$(T=$d SEL='one two' case_times "$d/x.test.sh" "$d/y.test.sh")
  [ "$got" = "x.test.sh	5.5	62.6" ] || fail "the case files' times: '$got', want x.test.sh alone, its two cases' 5.5 s and 62.6 CPU s"
}
