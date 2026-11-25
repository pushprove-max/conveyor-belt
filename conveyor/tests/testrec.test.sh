#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: what a card's test record holds of its run (conveyor.sh testrec()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A test line that holds the slot wait and the run apart, what was selected, how the run ended and the slots free:
# slots.test.sh t_slotclock, whose card's test step already waits 4 s at least for the pool's one slot (t_testrecwait
# was a card of its own for it here).

# The fields a card's test line takes of its run (lib/testrun.sh testrec()): the test command $T/$CASE/cmd run as a
# card's test step runs it, its output and its runners' logs where a card's worktree <w> has them (<w>.test,
# <w>.testlog), then read with the exit it ended with, and put on a test line the record check (jq/check.jq) is given.
# A whole loop run to read them cost each case 3 to 7 s more, a fix round and a second run for the killed one. A card's
# test line is testrec()'s fields with its own (card.sh): batch.test.sh t_batchmask reads a card's .ended, and
# rerun.test.sh and batchreuse.test.sh its .selected.
recline() { # <result>
  local w=$T/$CASE/wt rc; mkdir -p "$w.testlog"
  (cd "$T/$CASE" && CONVEYOR_TEST_LOG=$w.testlog exec bash cmd > "$w.test" 2>&1 < /dev/null); rc=$?
  ( eval "$(sed -n '/^testrec() {/,/^}/p' "$SRC/lib/testrun.sh"; sed -n '/^testcounts() {/,/^}/p' "$SRC/lib/records.sh"
      sed -n '/^testlogs() {/,/^}/p' "$SRC/lib/session.sh")"
    testrec "$w" "$rc" 1 ) | jq -c --arg r "$1" '{card: "c1", issue: 7, step: "test", result: $r, reason: "", sha: "", time: "2026-01-01T00:00:00Z",
      tokens: {claude: 0, codex: 0}} + .'
}
# The line refused by the record check, or nothing.
refused() { [ -z "$(jq -Rn -f "$SRC/jq/check.jq" <<<"$1")" ] || echo "the record check refuses the test line: $1"; }

# How a run ended, from its exit and its log: the test command is killed by a signal (KILL), so its line says
# "killed", not that a case failed.
t_testrecended() {
  local l e; mkdir -p "$T/$CASE"; echo 'kill -KILL $$' > "$T/$CASE/cmd"
  l=$(recline fail) || fail "the test line could not be made"
  [ "$(jq -r .ended <<<"$l")" = killed ] || fail "a run killed by a signal is not recorded as killed: $l"
  e=$(refused "$l"); [ -z "$e" ] || fail "$e"
}
# Bug (#1537): the record check did not know partial, so each test line the step wrote with it was set aside in quarantined.jsonl.
# A list of file names passes; a string or a list holding a number is refused, and the check names partial.
t_testrecpartial() {
  local l v f; mkdir -p "$T/$CASE"; echo 'true' > "$T/$CASE/cmd"
  l=$(recline pass) || fail "the test line could not be made"
  v=$(jq -c '. + {partial: ["conveyor/tests/x.test.sh"]}' <<<"$l"); [ -z "$(refused "$v")" ] || fail "a test line with partial as a list of file names is refused: $(refused "$v")"
  for p in '"x"' '[1]'; do
    v=$(jq -c --argjson p "$p" '. + {partial: $p}' <<<"$l"); f=$(jq -Rrn -f "$SRC/jq/check.jq" <<<"$v" | cut -f2)
    [ "$f" = partial ] || fail "a test line with partial $p is not refused naming partial (the check named '$f'): $v"
  done
}
# Bug (#1713): the record check did not know rerun.failures.ownLimit, so each test line whose first run had a file
# stopped by its own limit was set aside in quarantined.jsonl. The first run's failures are testfails()'s, kept in
# <w>.first as tests() keeps them; the pass line is testrec() with firstrun(), as the loop writes it. Its line passes,
# and an ownLimit that is not a list of strings is refused, the check naming rerun.
t_testrecownlimit() {
  local w=$T/$CASE/wt l v f e; mkdir -p "$T/$CASE"
  printf '%s\n' 'printf "== a.test.sh\n-- timeout a.test.sh\n" > "$CONVEYOR_TEST_LOG/r.log"; exit 1' > "$T/$CASE/cmd"
  mkdir -p "$w.testlog"; (cd "$T/$CASE" && CONVEYOR_TEST_LOG=$w.testlog exec bash cmd > "$w.test" 2>&1 < /dev/null)
  ( eval "$(sed -n '/^testfails() {/,/^}/p; /^RECJQ=/p' "$SRC/lib/testrun.sh"; sed -n '/^testlogs() {/,/^}/p' "$SRC/lib/session.sh")"
    packget() { return 1; }; testfails "$w.test" 1 ) | jq -c '{exit: 1, failures: del(.passed, .okcases, .passcases, .host)}' > "$w.first"
  jq -e '.failures.ownLimit == ["a.test.sh"]' "$w.first" >/dev/null || fail "a first run whose a.test.sh hit its own limit has no ownLimit: $(cat "$w.first")"
  rm -rf "$w.testlog"; echo 'true' > "$T/$CASE/cmd"; l=$(recline pass) || fail "the test line could not be made"
  l=$(jq -c --slurpfile r <(eval "$(sed -n '/^NOTPASSED=/,/unique;.$/p; /^firstrun() {/,/^}/p' "$SRC/lib/testrun.sh")"; firstrun "$w" pass) '. + $r[0]' <<<"$l")
  jq -e '.rerun.failures.ownLimit == ["a.test.sh"]' <<<"$l" >/dev/null || fail "the pass line has no rerun.failures.ownLimit: $l"
  e=$(refused "$l"); [ -z "$e" ] || fail "$e"
  for p in '"a.test.sh"' '[1]' null false; do
    v=$(jq -c --argjson p "$p" '.rerun.failures.ownLimit = $p' <<<"$l"); f=$(jq -Rrn -f "$SRC/jq/check.jq" <<<"$v" | cut -f2)
    [ "$f" = rerun ] || fail "a test line with rerun.failures.ownLimit $p is not refused naming rerun (the check named '$f'): $v"
  done
}
# A runner that selects no file of 4 and no case of 9 passes, and its line says "nothing selected", not "passed".
t_testrecnothing() {
  local l e; mkdir -p "$T/$CASE"; echo 'printf "TESTRUN files=0 of=4\nTESTRUN cases=0 of=9\n" > "$CONVEYOR_TEST_LOG/r.log"' > "$T/$CASE/cmd"
  l=$(recline pass) || fail "the test line could not be made"
  jq -e '.ended == "nothing selected" and .selected == {files: 0, filesOf: 4, cases: 0, casesOf: 9, kept: null}' <<<"$l" >/dev/null \
    || fail "a run that selected nothing is not recorded so: $l"
  e=$(refused "$l"); [ -z "$e" ] || fail "$e"
}

# Bug it catches (#1595, review): a run again that started no file (the selection named none of the files its list kept as
# passed) logs only `TESTRUN kept=<n>`, no `TESTRUN cases=` line; passlist() then wrote cases: null, so a batch that takes the card
# (batchkeep()) counted none of the n cases it kept. The list keeps lib/a.test.sh as passed, and the run kept 3 cases: the card's
# .passed says 3 cases, and still lib/a.test.sh as its unit. With no log line of either, the runner says no count: null.
t_passlistkept() {
  local w=$T/$CASE/wt; mkdir -p "$w.testlog"; : > "$w.test"; printf 'pass\tlib/a.test.sh\n' > "$w.rerun"
  # passlisted <the run's log text>: passlist() of the worktree, as the loop calls it, over a run whose log holds that text.
  passlisted() {
    printf '%s\n' "$1" > "$w.testlog/test-changed.log"
    ( eval "$(sed -n '/^passlist() {/,/^}/p' "$SRC/lib/testlist.sh"; sed -n '/^testrec() {/,/^}/p;/^testfails() {/,/^}/p' "$SRC/lib/testrun.sh"
        sed -n '/^testcounts() {/,/^}/p' "$SRC/lib/records.sh"; sed -n '/^testlogs() {/,/^}/p' "$SRC/lib/session.sh")"
      passlist "$w" ) || fail "passlist() failed for the run with the log: $1"
  }
  passlisted $'TESTRUN files=0\nTESTRUN kept=3'
  jq -e '.cases == 3 and .units == ["lib/a.test.sh"]' "$w.passed" >/dev/null || fail "a run that kept 3 cases and ran none was not recorded as 3 cases passed, lib/a.test.sh its unit: $(cat "$w.passed")"
  passlisted 'TESTRUN files=0'
  jq -e '.cases == null' "$w.passed" >/dev/null || fail "a run whose runner says no case count was given one: $(cat "$w.passed")"
}

# Issue 517: a test line said why a file ran only on a run again, and a reader counted files to tell whether a step ran
# every engine case file. A first run's log gives the reasons of each file it ran and says it ran the whole engine
# test (`TESTRUN whole-suite`): its line has them in why and wholeSuite. A run of chosen cases has why, no wholeSuite.
t_testrecwhy() {
  local l e; mkdir -p "$T/$CASE"
  printf '%s\n' 'printf "TESTRUN why\tr.test.sh\tthe card changed lib/core.sh\nTESTRUN why\tr.test.sh\tthe area core runs all engine tests\nTESTRUN whole-suite\nTESTRUN why\tb.test.mjs\tthe card changed b.js\n" > "$CONVEYOR_TEST_LOG/r.log"' > "$T/$CASE/cmd"
  l=$(recline pass) || fail "the test line could not be made"
  jq -e '.why == {"r.test.sh": ["the area core runs all engine tests", "the card changed lib/core.sh"], "b.test.mjs": ["the card changed b.js"]} and .wholeSuite == true' <<<"$l" >/dev/null \
    || fail "a first run's line does not have why for each file and wholeSuite: $l"
  e=$(refused "$l"); [ -z "$e" ] || fail "$e"
  printf '%s\n' 'printf "TESTRUN why\tr.test.sh\tthe card changed lib/x.sh\nTESTRUN case\tr.test.sh\ttwo\nTESTRUN case\tr.test.sh\tone\n" > "$CONVEYOR_TEST_LOG/r.log"' > "$T/$CASE/cmd"
  l=$(recline pass) || fail "the test line could not be made"
  jq -e '.why == {"r.test.sh": ["the card changed lib/x.sh"]} and has("wholeSuite") == false' <<<"$l" >/dev/null || fail "a run of chosen cases has wholeSuite, or no why: $l"
  # Issue 604: its line names the cases it ran (ranCases), so the search for the landing that broke a case (mainred.sh brokeby()) counts it.
  jq -e '.ranCases == {"r.test.sh": ["one", "two"]}' <<<"$l" >/dev/null || fail "a run of chosen cases does not name them in ranCases: $l"
  e=$(refused "$l"); [ -z "$e" ] || fail "$e"
}

# A pass reused, not run again, has a test line that says so and passes the record check: batch.test.sh t_batchmask
# (#7's tests pass after its fix and are reused on main as #8 left it), where t_testrecreused ran two cards here for it.
