#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases (#157): the records the engine's own writers write pass the record check (jq/check.jq), and a record
# that does not is set aside while the loop goes on. Bug caught: #147 added a list field to test lines (testrec()) but
# not to check.jq; the first card that wrote one stopped the loop and every snapshot, and no test had run check.jq
# on a line the real writers made.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# recok (lib.sh) fails on each line the check refuses. The writers the cases here do not reach are checked by recok in
# the cases that already make their lines: the rebase line (port.test.sh t_rebase), the filed line and a landed line
# with leftover and followups (port.test.sh t_portfix, resume.test.sh t_resume), a land-branch card's picked line with branch
# (branch.test.sh t_branch) and a landed line with yesFrom (visibleinherit.test.sh t_inheritpart).
# Fails unless the records hold a line of each step named.
recsteps() { # <what wrote them> <step>...
  local s have; have=$(jq -r .step "$ST/cards.jsonl" | sort -u)
  for s in "${@:2}"; do grep -qxF "$s" <<<"$have" || fail "$1 wrote no $s line, so its fields went unchecked: $(tr '\n' ' ' <<<"$have")"; done
}

# A whole card of the loop, with a NO-GO review, a fix and the GO after it, its changed tests (the test line's list:
# the test file linked to its change, run alone) and its landing and push: each line it writes, with the fields each
# writer adds (picked's title and created, worktree's pid and account, a session's model, effort and usage, a review's
# counts and visible, the test line's list, selected and why, landed's diff and product, pushed's head), checks.
# The records start with a line of a field the check does not know: it is set aside, named with its line and field,
# and the loop still picks and lands the card (the loop did not stop for it).
t_recloop() {
  setup "[$(issue 7 2026-01-01)]"; echo "$NOGO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  good='{"card":"c0-4","issue":4,"step":"picked","time":"2026-11-01T00:00:00Z","tokens":{"claude":0,"codex":0},"result":"ok","sha":"","reason":""}'
  printf '%s\n' "$good" "${good/\"reason\":\"\"/\"reason\":\"\",\"later\":1}" > "$ST/cards.jsonl"
  out=$(loop run --only 7 1 2>&1) || fail "the loop stopped on a line with a field the check does not know: $out"
  jq -se 'length == 1 and (.[0] | .line == 2 and .field == "later" and (.record | fromjson | .later == 1))' "$ST/quarantined.jsonl" > /dev/null \
    || fail "the line was not set aside with its line number and field: $(cat "$ST/quarantined.jsonl" 2>&1)"
  grep -qF '"later"' "$ST/cards.jsonl" && fail "the line set aside is still in the card records"
  [ "$(st 'select(.issue == 7 and .step == "picked") | .issue')" = 7 ] || fail "the loop did not pick #7 after the line was set aside: $out"
  loop health | jq -e '.quarantined == [{line: 2, field: "later", time: .quarantined[0].time}]' > /dev/null || fail "health does not name the line set aside: $(loop health)"
  recsteps "a card of the loop" picked worktree brief start build review fix test landed pushed
  [ "$(st 'select(.issue == 7 and .step == "test") | .list.mode')" = changed ] || fail "the test line has no list of the changed tests: $(st 'select(.step == "test")')"
  recok "$ST/cards.jsonl" "a card of the loop"
}

# A card whose build session fails after changing a file: its blocked line, with its kept patch, the files it changed,
# the end of what the session said and what it spent, checks.
t_recblocked() {
  setup "[$(issue 7 2026-01-01)]"; echo 'echo two >> a.txt; echo "FAIL schema mismatch" >&2; exit 3' > "$STUB/build"
  loop run --only 7 1 > /dev/null 2>&1
  [ "$(st 'select(.issue == 7 and .step == "blocked") | [.kept != "", (.paths | length), (.tail | length > 0)] | tojson')" = '[true,1,true]' ] \
    || fail "the blocked line has no kept patch, files or tail, so they went unchecked: $(st 'select(.step == "blocked")')"
  recok "$ST/cards.jsonl" "a blocked card"
}

# A card whose first test run fails b.test's flaky, as does the run again, and main's run of it passes: its failed test
# line (card.sh's fail record) with its failures, the end of the run's output, each case's verdict and main's run,
# then its passing run after the fix, checks. Bug it catches: no case above wrote a failed test line, so a field only
# that writer adds (failures, tail, verdicts, mainRun) went unchecked.
t_recfailed() {
  rerunsetup '1 fail flaky' '2 fail flaky'; rerunfiles
  loop run 1 > "$STUB/run.out" 2>&1 || fail "run exited non-zero: $(cat "$STUB/run.out")"
  [ "$(st 'select(.step == "test" and .result == "fail") | [(.failures.files | length > 0), (.tail | length > 0), .verdicts[0].verdict, (.mainRun.sha | length > 0)] | tojson')" = '[true,true,"card",true]' ] \
    || fail "the failed test line has no failures, tail, verdicts or main's run, so they went unchecked: $(st 'select(.step == "test")')"
  recok "$ST/cards.jsonl" "a card whose test run failed"
}

# A card's test line when its change narrows the run (test.list args): its list is the changed tests, how many and by
# what. Written as card.sh writes a passing first run: testrec(), firstrun() and testlist.sh slowrec() of the run tests() made,
# through record(). Each call moves into main's checkout first, where the engine's load leaves the loop (lib/records.sh)
# and engine_once does not: speedproof() and closed() run git there with no -C.
t_reclist() {
  local wt=$T/$CASE/cards/c7
  setup '[]'
  mkdir -p "$R/lib" && echo x > "$R/lib/cartsum.js" && echo x > "$R/lib/cartsum.test.js" && git -C "$R" add -A && git -C "$R" commit -qm files || fail "main's files"
  printf '%s\n' 'echo "$*" > "$STUB/got"' > "$STUB/list-cmd"
  tune '.test.list = "args" | .test.command = "bash \"$STUB/list-cmd\""'
  git -C "$R" worktree add -q --detach "$wt" && echo y >> "$wt/lib/cartsum.js" && git -C "$wt" add -A || fail "the card's change could not be staged"
  wt=$wt engine_once 'cd "$CONVEYOR_MAIN" && tests "$wt" || exit 1
    record c7 7 test pass "$(jq -cn --argjson x "$(testrec "$wt" 0 1)" --argjson r "$(firstrun "$wt" pass)" --argjson s "$(slowrec "$wt")" "\$x + \$r + \$s")"' \
    > "$T/$CASE/run.out" 2>&1 || fail "the test step failed: $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "test") | .list | tojson')" = '{"mode":"changed","files":1,"by":"name"}' ] || fail "the test line has no list of the changed tests: $(cat "$ST/cards.jsonl")"
  recok "$ST/cards.jsonl" "a card's narrowed test run"
}

# The writers no card above reaches, each called as the engine calls it, on one card whose change speeds up f.test.sh:
# its test line, whose list is its own changed test file (testrec()), the speed-up check's bugproof line with its speed
# (speedproof.sh speedproof(): 10 CPU s on record, 4 now), a push its pre-push hook refuses (push(): kind check, naming the check) and
# the closed line of a card main already fixes (closed()).
t_recother() {
  local wt=$T/$CASE/cards/c7 c
  setup '[]'
  echo slow > "$R/f.test.sh" && git -C "$R" add f.test.sh && git -C "$R" commit -qm 'a slow test' || fail "main's file"
  for c in 9 10 11; do
    jq -cn --argjson c "$c" '{time: "2026-11-01T00:00:00Z", how: "full", sha: "abc", files: {"f.test.sh": {result: "ok", sec: $c, cpu: $c}}}' >> "$ST/suiteruns.jsonl"
  done
  echo 'printf "TESTRUN sec\tf.test.sh\t1\t4\n" > "$CONVEYOR_TEST_LOG/r"' > "$STUB/mainrun-cmd"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "push-checks: FAILED fast-checks" >&2; exit 1' > "$R/.git/hooks/pre-push" && chmod +x "$R/.git/hooks/pre-push"
  git -C "$R" worktree add -q --detach "$wt" && echo fast > "$wt/f.test.sh" && git -C "$wt" add -A || fail "the card's change could not be staged"
  wt=$wt engine_once 'cd "$CONVEYOR_MAIN" && tests "$wt" || exit 1
    record c7 7 test pass "$(jq -cn --argjson x "$(testrec "$wt" 0 1)" --argjson r "$(firstrun "$wt" pass)" --argjson s "$(slowrec "$wt")" "\$x + \$r + \$s")"
    speedproof c7 "$wt" "{\"number\":7}" f.test.sh || exit 1
    push c7 7; closed c7 7 "$wt" "ALREADY-DONE: f.test.sh is fast"' > "$T/$CASE/run.out" 2>&1 || fail "a writer failed: $(cat "$T/$CASE/run.out")"
  recsteps "the other writers" test bugproof push closed
  [ "$(st 'select(.step == "test") | .list | tojson')" = '{"mode":"changed","files":1,"by":"own"}' ] || fail "the test line's list is not the card's own test file: $(st 'select(.step == "test")')"
  [ "$(st 'select(.step == "bugproof") | .speed | tojson')" = '{"file":"f.test.sh","before":10,"after":4,"fix":"sped up","into":[]}' ] \
    || fail "the bugproof line has no speed with both CPU numbers: $(st 'select(.step == "bugproof")')"
  [ "$(st 'select(.step == "push") | [.result, .kind, .check] | join(" ")')" = 'fail check fast-checks' ] || fail "the push line has no kind and check: $(st 'select(.step == "push")')"
  recok "$ST/cards.jsonl" "the other writers"
}
