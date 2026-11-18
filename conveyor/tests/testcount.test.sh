#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: how far a running test run has got, in its live record and the snapshot (conveyor.sh watch(),
# track.tests). The engine's own runner's part in it is testcountrunner.test.sh's: together they were over the test
# step's CPU budget for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A card's test run, held open until $STUB/go, after its command <prints> and names cases in the folders of its log:
# ok/ and failed/ for those that ended, and one still running. Waits until the live record's <field> is <want> (an empty
# <field>: no wait, for a run that is stopped, whose live record goes with it).
# The card c7 is at its test step by its records, and the command is run and watched as its test step does it
# (lib/testrun.sh testonce(): the engine's own watch(), on the output and logs where a card's worktree has them). A
# whole loop run to that step cost each case about 3 s more; views.test.sh's t_live reads a real run's test step.
countrun() { # <prints> <field> <want> [the card's test list, <worktree>.testlist]
  local w=$T/$CASE/cards/c7 now
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$ST" "$w.testlog"; now=$(date -u +%FT%TZ)
  [ -z "${4:-}" ] || printf '%s\n' "$4" > "$w.testlist"
  printf '%s\n' picked worktree deps brief start:build build start:review review:GO start:test | jq -cR --arg t "$now" 'split(":") as [$s, $x]
    | {card:"c7",issue:7,step:$s,time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
      + if $s == "start" then {of: $x} elif $x then {result: $x} else {} end' > "$ST/cards.jsonl"
  { printf '%s\n' "$1"; cat <<'EOF'
C=$CONVEYOR_TEST_LOG/cases; mkdir -p "$C/ok" "$C/failed"; : > "$C/ok/a"; : > "$C/ok/b"; : > "$C/failed/c"; : > "$C/d"
while [ -d "$STUB" ] && [ ! -e "$STUB/go" ]; do sleep 0.1; done
EOF
  } > "$STUB/test-cmd"
  # shellcheck disable=SC2034 # LIVE is read by watch(), defined by the eval
  ( . "$SRC/lib/portable.sh"; eval "$(for f in watch testlogs testcases testdone testprogress endall; do sed -n "/^$f() {/,/^}/p" "$SRC/lib/session.sh"; done)"; LIVE=0.2
    (cd "$T/$CASE" && CONVEYOR_TEST_LOG=$w.testlog exec bash "$STUB/test-cmd" > "$w.test" 2>&1 < /dev/null) &
    watch $! "$w.test" "$w.live" test ) > "$T/$CASE/run.out" 2>&1 & run=$!
  [ -z "$2" ] || wait_until "jq -e --argjson w '$3' '.$2 == \$w' '$w.live'" "cat '$w.live'" \
    || { : > "$STUB/go"; wait $run; fail "the live record's $2 is never $3: $(cat "$T/$CASE/run.out")"; }
}

# Bug: a card in its Test step showed only "0 turns", and a run of one test file with 205 cases read "0 of 1" until it
# ended. A command that says it selected 5 cases (two lines, 3 and 2, that add up) and whose runner has named three
# cases as ended, one failed, and one as running: the live record and the snapshot's track say 3 done of 5, 1 failed.
t_testcountcases() {
  countrun $'echo "TESTRUN cases=3"\necho "TESTRUN cases=2"' tests '{"done":3,"of":5,"failed":1}'
  [ "$(loop snapshot --fresh | jq -c '.belt[0].track | [.tests, .files]')" = '[{"done":3,"of":5,"failed":1},{"run":0,"of":null}]' ] \
    || { : > "$STUB/go"; wait $run; fail "the snapshot's track does not count the cases: $(loop snapshot --fresh | jq -c '.belt[0].track')"; }
  : > "$STUB/go"; wait $run || fail "the watch of the test run exited non-zero: $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#147): a test step that ran 20 minutes on a loaded machine was called stuck by the Foreman while its
# cases still finished: a quiet runner's output, written long ago (here 2000), was all health read of it, and a run's
# record started with no time at all until its first output. The run's start and each case that ends are its progress:
# a case that ends (e, once $STUB/more is there) after the run's start, with no output, moves it on; and with the
# card's lines and its output as old as 2000, health lists no stuck card.
t_testcountprogress() {
  local p0
  countrun 'touch -t 200001010000 "${CONVEYOR_TEST_LOG%log}"
( while [ -d "$STUB" ] && [ ! -e "$STUB/more" ]; do sleep 0.1; done; : > "$CONVEYOR_TEST_LOG/cases/ok/e" ) &' 'cases | length' 1
  jq -c '.time = "2000-01-01T00:00:00Z"' "$ST/cards.jsonl" > "$ST/cards.new" && mv "$ST/cards.new" "$ST/cards.jsonl"
  p0=$(jq -r .progress "$T/$CASE/cards/c7.live")
  # The case ends in a later second than the start, so a progress the start alone set is told apart from it.
  wait_until "[ \"\$(date -u +%FT%TZ)\" '>' '$p0' ]" || { : > "$STUB/go"; wait $run; fail "the clock did not pass $p0"; }
  : > "$STUB/more"
  wait_until "jq -e '.progress > \"$p0\"' '$T/$CASE/cards/c7.live'" "cat '$T/$CASE/cards/c7.live'" \
    || { : > "$STUB/go"; wait $run; fail "a case that ended after the run's start did not move its progress on"; }
  [ "$(loop health | jq -c '[.stuck[] | .card]')" = '[]' ] \
    || { : > "$STUB/go"; wait $run; fail "health calls a test run whose cases finish stuck: $(loop health | jq -c .stuck)"; }
  : > "$STUB/go"; wait $run || fail "the watch of the test run exited non-zero: $(cat "$T/$CASE/run.out")"
}

# A command that gives no case count leaves tests null, its runner's case records or not, and its files as they were
# counted before: of from `TESTRUN files=N`, run from its `-- ok` lines.
t_testcountnone() {
  countrun $'echo "TESTRUN files=2"\necho "-- ok x.test.sh"' files '{"run":1,"of":2}'
  jq -e 'has("tests") and .tests == null' "$T/$CASE/cards"/*.live >/dev/null \
    || { : > "$STUB/go"; wait $run; fail "a run with no case count does not have tests null: $(cat "$T/$CASE/cards"/*.live)"; }
  [ "$(loop snapshot --fresh | jq -c '.belt[0].track | [has("tests"), .tests, .files]')" = '[true,null,{"run":1,"of":2}]' ] \
    || { : > "$STUB/go"; wait $run; fail "the snapshot's track with no case count: $(loop snapshot --fresh | jq -c '.belt[0].track')"; }
  : > "$STUB/go"; wait $run || fail "the watch of the test run exited non-zero: $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#385): a run of whole area files printed `TESTRUN cases=0 of=3491` and no files total, and the
# Test step showed "0 of 0 tests" while 19 files ran. With a card's list of 37 files, its files are 19 of 37 (of from
# the list) and tests stays null.
t_testcountcasesnone() {
  countrun "echo 'TESTRUN cases=0 of=3491'; for i in \$(seq 1 19); do echo \"-- ok f\$i.test.sh\"; done" \
    files '{"run":19,"of":37}' '{"mode":"changed","files":37,"by":"area"}'
  jq -e 'has("tests") and .tests == null' "$T/$CASE/cards/c7.live" >/dev/null \
    || { : > "$STUB/go"; wait $run; fail "a run that says cases=0 has a case count: $(cat "$T/$CASE/cards/c7.live")"; }
  : > "$STUB/go"; wait $run || fail "the watch of the test run exited non-zero: $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#360): "N of M test files" with N above M. A run that selected 1 test file and ran 2 has files 1 of
# 1 and over 1 in its live record and the snapshot's track, so the Board says the extra file apart.
t_testcountover() {
  countrun "$WIDER" files '{"run":1,"of":1,"over":1}'
  [ "$(loop snapshot --fresh | jq -c '.belt[0].track.files')" = '{"run":1,"of":1,"over":1}' ] \
    || { : > "$STUB/go"; wait $run; fail "the snapshot's track of a run wider than it selected: $(loop snapshot --fresh | jq -c '.belt[0].track')"; }
  : > "$STUB/go"; wait $run || fail "the watch of the test run exited non-zero: $(cat "$T/$CASE/run.out")"
}
WIDER=$'echo "TESTRUN files=1"\necho "-- ok a.test.sh"\necho "-- ok b.test.sh"'

# #360, #350. Bug it catches: once run stops at of, the stop of a run given more test files than TEST_GIVEN (watch())
# read the run above as 1 file, no more than the 1 it was given, and let it run on. It reads the 2 it ran: the run is
# ended, and c7.wide names 2.
t_testcountwide() {
  TEST_GIVEN=1 countrun "$WIDER" '' ''
  wait_until "[ -s '$T/$CASE/cards/c7.wide' ]" || { : > "$STUB/go"; wait $run; fail "a run given 1 test file that ran 2 was not stopped"; }
  [ "$(cat "$T/$CASE/cards/c7.wide")" = 2 ] || fail "the stopped run's count is not the 2 files it ran: $(cat "$T/$CASE/cards/c7.wide")"
  : > "$STUB/go"; wait $run; : # the stop ends the run, so its exit is that of an ended run
}

# Bug it catches (#433): a card's Test step in one-file mode (test.fileCommand, lib/testrun.sh filecmd()) looked stuck:
# each file's own run prints its own count, so the live record had no count of the files given (files.of null), and
# nothing named the file that ran or since when. The card's fourth run, given 3 files and held in the second: the live
# record says 1 of 3 ended and names the second with the time it began, and the snapshot's track passes that on, with
# the run's number on Test (n 4), which the views show apart from the earlier runs' seconds (Test's sec).
# The first Test step ran twice (its line has rerun: two runs, not one, or n is 3). The fourth run is the run again of
# a second Test step (TEST_BEFORE, lib/testrun.sh tests()): no test line has the second step's first run yet, so
# without the live record's before the snapshot lost it (n 3, sec 0).
t_testcountfile() {
  # shellcheck disable=SC2034 # TEST_BEFORE is read by watch() (lib/session.sh), which countrun runs
  local got w=$T/$CASE/cards/c7.live TEST_BEFORE=120
  eval "$(sed -n '/^filecmd() {/,/^}/p' "$SRC/lib/testrun.sh")"
  # shellcheck disable=SC2016 # the file command's text, expanded where it runs
  CONVEYOR_TEST_FILES=$'t/a.test.sh\nt/b.test.sh\nt/c.test.sh' countrun "$(filecmd 'w() { case "$1" in */b.test.sh) while [ -d "$STUB" ] && [ ! -e "$STUB/go" ]; do sleep 0.1; done ;; esac; }; w' files)" \
    files.now.file '"t/b.test.sh"'
  got=$(jq -c '.files | [.run, .of, (.now.at | fromdate | type)]' "$w")
  [ "$got" = '[1,3,"number"]' ] || { : > "$STUB/go"; wait $run; fail "the live record of the second of 3 files: $(cat "$w")"; }
  # One failed Test step that ran twice (rerun) before the one that goes (the last line, start:test), at the same time:
  # its seconds are 0, so Test's sec is the second step's first run's 120.
  jq -cs '.[:-1] + [.[-1] | del(.of) | .step = "test" | .result = "fail" | .rerun = {exit: 1, failures: {of: null, files: [], timeout: null}}] + [.[-1]] | .[]' "$ST/cards.jsonl" > "$ST/cards.new" \
    && mv "$ST/cards.new" "$ST/cards.jsonl"
  got=$(loop snapshot --fresh | jq -c '.belt[0].track | [.files.run, .files.of, .files.now.file, .steps[3].n, .steps[3].sec]')
  [ "$got" = '[1,3,"t/b.test.sh",4,120]' ] || { : > "$STUB/go"; wait $run; fail "the snapshot's track of the fourth run, in its second file: $got"; }
  : > "$STUB/go"; wait $run || fail "the watch of the test run exited non-zero: $(cat "$T/$CASE/run.out")"
}

# testprogress() (lib/session.sh) over <output> and <log>... in $T/$CASE: the function itself, with no watch.
progress() { # <output> [<log>...]
  ( . "$SRC/lib/portable.sh"; eval "$(sed -n '/^testprogress() {/,/^}/p' "$SRC/lib/session.sh")"; cd "$T/$CASE" && testprogress "$@" )
}
# A run in the forms of a host project's test command, in $T/$CASE: its output (out) says 75 web test files are
# selected; a root log of 11 files, `TESTRUN files=11` and a `-- ok   <file> <seconds>s` line each; and a vitest log
# of 75 files, in color, each with its `== web/<file>`, vitest's ` ✓ <file> (N tests)` and its reporter's
# `-- ok web/<file>` and `TESTRUN sec` lines.
hostrun() {
  local i; mkdir -p "$T/$CASE"
  echo 'test-changed: 75 web test file(s) selected' > "$T/$CASE/out"
  { echo 'TESTRUN files=11'; for i in $(seq 1 11); do printf -- '-- ok   test/r%d.test.ts %ds\n' "$i" "$i"; done; } > "$T/$CASE/root.log"
  { echo 'TESTRUN files=? root=/x'; for i in $(seq 1 75); do
      printf '== web/src/w%d.test.tsx\n \033[32m✓\033[39m src/w%d.test.tsx \033[2m(3 tests)\033[22m 12ms\n-- ok web/src/w%d.test.tsx\nTESTRUN sec\tweb/src/w%d.test.tsx\t1.20\n' "$i" "$i" "$i" "$i"
    done; } > "$T/$CASE/web.log"
}

# Bug it catches (#360): the Test step showed "101 of 86 test files", and it climbed: each vitest file counted twice,
# by vitest's line and by its reporter's `-- ok web/<file>` line, which names it from the repo root. A run of 11 root
# and 75 vitest files counts 86 of 86.
t_testcounthost() {
  local got; hostrun; got=$(progress out root.log web.log)
  [ "$got" = '{"run":86,"of":86,"cases":null}' ] || fail "a run of 86 test files of 86 counts: $got"
}

# Bug it catches (#360): a file named twice counted twice. Root's r1 runs again (a `-- FAIL` line, then a later
# `-- ok` one with another time) and a second log names r2 too: still 86 of 86.
t_testcountonce() {
  local got; hostrun
  printf -- '-- FAIL test/r1.test.ts 3s\n-- ok   test/r1.test.ts 1s\n' >> "$T/$CASE/root.log"; echo '-- ok test/r2.test.ts' > "$T/$CASE/again.log"
  got=$(progress out root.log web.log again.log)
  [ "$got" = '{"run":86,"of":86,"cases":null}' ] || fail "a file named twice counts once: $got"
}
