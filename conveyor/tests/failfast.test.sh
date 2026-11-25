#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#1616): the rule Stop a card's tests at the first failure (rules.failfast, lib/testrun.sh failfast()).
# On, a card's Test step (tests()) ends at its first failed case: no further file starts, the files still running
# are ended (lib/fileeach.sh), the engine's runner starts no further case (../conveyor.test.sh), and the result names
# the failed case and the files not run. Off, and in a release's run (test.full), every case runs.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# ffwt: the card's worktree $T/$CASE/wt of a fresh main, on a pool of the case's own of three slots.
# ffcard: that worktree, with its change two
# staged test files, each run alone with bash (test.fileCommand): a.test.sh, whose first case `first` fails at once
# (each run adds a line to $T/$CASE/a-runs), and b.test.sh, whose case `early` passes and whose case `late` runs only
# once a.test.sh has failed and a few seconds more, and leaves $T/$CASE/late. So `late` runs only in a run that goes on
# past the first failure.
ffwt() {
  local d=$T/$CASE
  export XDG_CONFIG_HOME=$d/config
  setup '[]'; git -C "$R" worktree add -q --detach "$d/wt" && mkdir -p "$XDG_CONFIG_HOME/conveyor" \
    && echo "{\"testSlots\": 3, \"testSlotsDir\": \"$d/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the worktree and its pool"
}
ffcard() {
  local d=$T/$CASE w=$T/$CASE/wt
  ffwt
  printf '%s\n' "echo run >> '$d/a-runs'; echo 'FAIL [first]: broken'; : > '$d/a-done'; exit 1" > "$w/a.test.sh"
  printf '%s\n' 'echo "ok early"' "i=0; while [ ! -e '$d/a-done' ] && [ \$i -lt $(loadlimit 200) ]; do i=\$((i + 1)); sleep 0.05; done" \
    "sleep $(loadlimit 3); : > '$d/late'; echo 'ok late'" > "$w/b.test.sh" # sleep: the later case, past the first failure by enough that a stop ends it first
  git -C "$w" add a.test.sh b.test.sh || fail "the card's change could not be staged"
  # The release's command names no file (a glob): a file a suite command names is its runner, on no card's list.
  tune '.test.fileCommand = "bash" | .test.full = "for f in *.test.sh; do echo \"== $f\"; bash \"$f\" || { r=1; [ \"${CONVEYOR_TEST_FAILFAST:-}\" != 1 ] || exit 1; }; done; exit ${r:-0}"'
}
# The card's Test step, tests() as card() calls it ([the pack's field]: test.full is the release's run), with the
# engine as serve.sh loads it. Exits as the step; testfails()'s reading of its last run is in $T/$CASE/fails.
ffrun() { # [test.full]
  local w=$T/$CASE/wt
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && names || exit 99
    tests "$w" "$@"; rc=$?; testfails "$w.test" "$rc" > "$T/$CASE/fails"; exit $rc ) > "$T/$CASE/out" 2>&1
}

# Bug it catches (#1616): a card's Test step went on after its first failed case, and waited for every other selected
# file to end before the fix session could start. With the rule on (the default), the step fails, b.test.sh's later
# case never runs, and the result names a.test.sh's case `first` and b.test.sh as not run, never as passed. The flaky
# check still runs the failure that ended the run again: a.test.sh ran twice, and the first run is kept (.first).
t_failfastcard() {
  local rc w=$T/$CASE/wt l
  ffcard
  ffrun; rc=$?
  [ "$rc" != 0 ] || fail "the card's Test step with a failing case passed: $(cat "$T/$CASE/out" "$w.test")"
  [ ! -e "$T/$CASE/late" ] || fail "the step ran b.test.sh's later case after a.test.sh's case failed: $(cat "$w.test")"
  [ "$(jq -c '[(.files | map([.file, (.cases | map(.name))])), .notRun, .passed]' "$T/$CASE/fails")" = '[[["a.test.sh",["first"]]],["b.test.sh"],[]]' ] \
    || fail "the step's result does not name a.test.sh's case first and b.test.sh as not run: $(cat "$T/$CASE/fails") $(cat "$w.test")"
  grep -q '^conveyor: b.test.sh did not finish, and is not run: the run stopped at its first failure$' "$w.test" \
    || fail "the step's output does not name b.test.sh as not run: $(cat "$w.test")"
  [ "$(grep -c . "$T/$CASE/a-runs")" = 2 ] && jq -e '.failures.files[0].cases[0].name == "first"' "$w.first" > /dev/null \
    || fail "the failure that ended the run was not run again (a.test.sh runs: $(grep -c . "$T/$CASE/a-runs"); first run: $(cat "$w.first" 2>&1))"
  # Bug it catches (#1616): the record check refused a failures object with notRun, so the card's test line (failline(),
  # lib/card.sh) and its first run's record (rerun: <worktree>.first) were set aside.
  l=$(jq -c '{card: "c7", issue: 7, step: "test", result: "fail", reason: "", sha: "", time: "2026-01-01T00:00:00Z", tokens: {claude: 0, codex: 0},
    failures: .failures, rerun: .}' "$w.first") && jq -e '.failures.notRun == ["b.test.sh"]' <<<"$l" > /dev/null \
    || fail "the first run's record does not name b.test.sh as not run: $(cat "$w.first" 2>&1)"
  [ -z "$(jq -Rn -f "$SRC/jq/check.jq" <<<"$l")" ] || fail "the record check refuses a test line whose failures name files not run: $l"
}

# Bug it catches (#1616): the rule could not be turned off, so a card could not run every selected case. With
# `control rules failfast=off`, the same card's step runs b.test.sh's later case, and names no file as not run.
t_failfastoff() {
  local rc w=$T/$CASE/wt
  ffcard
  loop control rules failfast=off > /dev/null || fail "control rules failfast=off was refused"
  ffrun; rc=$?
  [ "$rc" != 0 ] || fail "the card's Test step with a failing case passed: $(cat "$T/$CASE/out" "$w.test")"
  [ -e "$T/$CASE/late" ] || fail "with the rule off, the step did not run b.test.sh's later case: $(cat "$w.test")"
  [ "$(jq -c '[.notRun, (.files | map(.file))]' "$T/$CASE/fails")" = '[null,["a.test.sh"]]' ] \
    || fail "with the rule off, the step's result names a file not run, or not a.test.sh alone as failed: $(cat "$T/$CASE/fails")"
}

# Bug it catches: a main-red fix card's run stopped at its first failure, another entry's case, before its other
# cases ran (in that file too), so no verdict named them: it could land with a case it broke unseen, or wait for main
# with another fix card failing its case first, each for good (cardland.sh redelse()). With the rule on, the same card,
# which an entry of the main-red record names (its worktree's name, wt), runs b.test.sh's later case, and names no
# file as not run.
t_failfastredfix() {
  # shellcheck disable=SC2034 # FXWT is read by fx_in, a fix card's worktree; this case has none
  local rc w=$T/$CASE/wt FXWT=$T/$CASE/none
  ffcard
  fx_in 'jq -cn "{reds: [{sha: \"1111\", cases: [{case: \"a.test.sh: first\", by: \"c1\"}], card: \"wt\"}]}" > "$MAINRED"'
  [ "$RC" = 0 ] || fail "the main-red record could not be written: $(cat "$T/$CASE/run.out")"
  ffrun; rc=$?
  [ "$rc" != 0 ] || fail "the fix card's Test step with a failing case passed: $(cat "$T/$CASE/out" "$w.test")"
  [ -e "$T/$CASE/late" ] || fail "the main-red fix card's step stopped at its first failure, and did not run b.test.sh's later case: $(cat "$w.test")"
  [ "$(jq -c '[.notRun, (.files | map(.file))]' "$T/$CASE/fails")" = '[null,["a.test.sh"]]' ] \
    || fail "the main-red fix card's step names a file not run, or not a.test.sh alone as failed: $(cat "$T/$CASE/fails")"
}

# Bug it catches (#1616): a release's run is not a card's: each failure there becomes its own fix card, so it runs
# every case. With the rule on, the release's run of the same two files (test.full, whose command stops at its first
# failure when it is given CONVEYOR_TEST_FAILFAST=1) runs b.test.sh's later case too.
t_failfastrelease() {
  local rc w=$T/$CASE/wt
  ffcard
  ffrun test.full; rc=$?
  [ "$rc" != 0 ] || fail "the release's run with a failing case passed: $(cat "$T/$CASE/out" "$w.test")"
  [ -e "$T/$CASE/late" ] || fail "the release's run stopped at its first failure, and did not run b.test.sh's later case: $(cat "$w.test")"
}

# Bug it catches (#1616): the engine's runner went on after a failed case, so a card's run of an engine case file
# waited for all its cases. With CONVEYOR_TEST_FAILFAST=1 (as a card's run with the rule on gives each file) on two
# slots, fxslow runs, fxbad fails, and fxlate is next: the runner ends fxslow, never starts fxlate, and names both as
# not run. The runner of a fixture engine (fxengine(), gitfence.test.sh) is run whole: only its run shows which cases
# it starts and ends; no case of the real suite fails on purpose.
t_failfastcases() {
  local d=$T/$CASE rc n=t_
  # The fixture's cases start with ${n}, never a line's own t_: the runner and a run of this file alone take each
  # `t_<name>() {` line of a case file for a case of their own, and found no such function here.
  fxengine "$d" "${n}fxslow() { local i=0; while [ \$i -lt $(loadlimit 200) ]; do i=\$((i + 1)); sleep 0.05; done; : > '$d/slow'; }
${n}fxbad() { echo 'FAIL [fxbad]: broken'; return 1; }
${n}fxlate() { : > '$d/late'; }" # sleep: fxslow runs past the stop, unless the runner ends it
  echo "{\"testSlots\": 2, \"testSlotsDir\": \"$d/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the fixture's pool of two"
  CONVEYOR_TEST_FAILFAST=1 CONVEYOR_SHELL_TEST_CASE='fxslow fxbad fxlate' timeout 60 bash "$d/src/conveyor.test.sh" > "$d/run" 2>&1; rc=$?
  [ "$rc" = 1 ] && grep -q '^FAIL \[fxbad\]: broken$' "$d/run" || fail "the run with fxbad failing did not fail naming it (exit $rc): $(cat "$d/run")"
  [ ! -e "$d/late" ] || fail "the runner started fxlate after fxbad failed: $(cat "$d/run")"
  [ ! -e "$d/slow" ] && ! grep -qx 'ok fxslow' "$d/run" || fail "the runner let fxslow run on after fxbad failed: $(cat "$d/run")"
  grep -qx 'conveyor: the run stopped at its first failed case, fxbad; not run: fxslow fxlate' "$d/run" \
    || fail "the runner did not name fxslow and fxlate as not run: $(cat "$d/run")"
}

# Bug it catches (#1616): the run again of a run that stopped at its first failure ran only the failed case, so a
# pass of it there (a flaky failure) passed the step though the file's later cases never ran. The one file of the
# card, a.test.sh, selects its cases as the pack's test-changed.sh does: those of `fail` lines naming one of its
# cases (CONVEYOR_TEST_RERUN), all of them when a `fail` line names it alone or none names it. Its case `first`
# fails once, and the file stops there (CONVEYOR_TEST_FAILFAST); its case `later` leaves $T/$CASE/later. The step
# passes on re-run, and `later` ran in it.
t_failfastrerun() {
  local rc d=$T/$CASE
  ffwt
  printf '%s\n' "s=\$(awk -F '\t' '\$1 == \"fail\" && \$2 == \"a.test.sh\" { print (\$3 == \"\" ? \"all\" : \$3) }' \"\${CONVEYOR_TEST_RERUN:-/dev/null}\" | tr '\n' ' ')" \
    'case " $s " in "  "|*" all "*) s="first later" ;; esac' \
    'for c in $s; do case $c in' \
    "  first) if [ -e '$d/flaky' ]; then echo 'ok first'; else : > '$d/flaky'; echo 'FAIL [first]: flaky'; exit 1; fi ;;" \
    "  later) : > '$d/later'; echo 'ok later' ;;" \
    'esac; done' > "$d/wt/a.test.sh"
  git -C "$d/wt" add a.test.sh || fail "the card's change could not be staged"
  tune '.test.fileCommand = "bash"'
  ffrun; rc=$?
  [ "$rc" = 0 ] || fail "the card's Test step with a flaky first case did not pass on re-run (exit $rc): $(cat "$d/out" "$d/wt.test")"
  [ -e "$d/later" ] || fail "the step passed on re-run though a.test.sh's case later never ran: $(cat "$d/wt.test")"
  jq -e '.failures.files[0].cases[0].name == "first"' "$d/wt.first" > /dev/null \
    || fail "the first run's failure was not kept for the flaky record: $(cat "$d/wt.first" 2>&1)"
}

# A push's claim on the next free slot of the case's pool (slot_first(), lib/slots.sh), held by this shell's
# descriptor FFCLAIM until ffunclaim: each worker that takes a slot gives it back (slot_yield), so a run waits.
ffclaim() { mkdir -p "$1/first" && exec {FFCLAIM}>>"$1/first/1" && flock "$FFCLAIM" || fail "the push's claim could not be made"; }
ffunclaim() { exec {FFCLAIM}>&-; }

# Bug it catches (#1616): a card's run that waited for a slot (a pool of two, both held: s.test.sh, slow, and
# a.test.sh) did not see a.test.sh fail while a push took each slot that came free (slot_yield()): it stayed in
# slot_take() and let s.test.sh run on. The claim is made while both files run; a.test.sh fails once it is. The run
# ends s.test.sh, never starts l.test.sh, and names both as not run.
t_failfastfileslot() {
  local d=$T/$CASE w=$T/$CASE/wt
  sidewt 2
  # sleep: s.test.sh runs past the stop, unless the run ends it; a.test.sh waits for the claim, then fails
  printf '%s\n' "i=0; while [ \$i -lt $(loadlimit 300) ]; do i=\$((i + 1)); sleep 0.05; done; : > '$d/slow'; echo 'ok slow'" > "$w/s.test.sh"
  printf '%s\n' ": > '$d/a-start'; i=0; while [ ! -e '$d/claimed' ] && [ \$i -lt 400 ]; do i=\$((i + 1)); sleep 0.05; done" \
    "echo 'FAIL [bad]: broken'; exit 1" > "$w/a.test.sh"
  printf '%s\n' ": > '$d/late'; echo 'ok late'" > "$w/l.test.sh"
  ( SIDEFAST=1 SIDELIMIT=40 siderun s.test.sh a.test.sh l.test.sh > "$d/out" 2>&1; echo $? > "$d/rc" ) &
  wait_until "[ -e '$d/a-start' ]" || fail "a.test.sh did not start: $(cat "$d/out" "$w.test" 2>&1)"
  ffclaim "$d/slots"; : > "$d/claimed"
  wait_until "[ -s '$d/rc' ]"; ffunclaim; wait
  [ "$(cat "$d/rc")" != 0 ] || fail "the run with a.test.sh failing passed: $(cat "$w.test")"
  [ ! -e "$d/slow" ] && [ ! -e "$d/late" ] || fail "the run, waiting for a slot a push took, let s.test.sh run on or started l.test.sh after a.test.sh failed: $(cat "$w.test")"
  [ "$(jq -c '.notRun' "$d/fails")" = '["l.test.sh","s.test.sh"]' ] || fail "the run did not name s.test.sh and l.test.sh as not run: $(cat "$d/fails")"
}

# Bug it catches (#1616): the engine's runner, waiting for a slot for fxlate (a pool of two, both held: fxslow and
# fxbad), did not see fxbad fail while a push took each slot that came free: it stayed in slot_take() and let fxslow
# run on. The claim is made while both cases run; fxbad fails once it is. The runner of a fixture engine (fxengine(),
# gitfence.test.sh) is run whole: only its run shows which cases it starts and ends.
t_failfastslot() {
  local d=$T/$CASE n=t_
  # sleep: fxslow runs past the stop, unless the runner ends it; fxbad waits for the claim, then fails
  fxengine "$d" "${n}fxslow() { local i=0; while [ \$i -lt $(loadlimit 300) ]; do i=\$((i + 1)); sleep 0.05; done; : > '$d/slow'; }
${n}fxbad() { local i=0; : > '$d/bad-start'; while [ ! -e '$d/claimed' ] && [ \$i -lt 400 ]; do i=\$((i + 1)); sleep 0.05; done; echo 'FAIL [fxbad]: broken'; return 1; }
${n}fxlate() { : > '$d/late'; }"
  echo "{\"testSlots\": 2, \"testSlotsDir\": \"$d/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the fixture's pool of two"
  ( CONVEYOR_TEST_FAILFAST=1 CONVEYOR_SHELL_TEST_CASE='fxslow fxbad fxlate' timeout 60 bash "$d/src/conveyor.test.sh" > "$d/run" 2>&1; echo $? > "$d/rc" ) &
  wait_until "[ -e '$d/bad-start' ]" || fail "fxbad did not start: $(cat "$d/run")"
  ffclaim "$d/slots"; : > "$d/claimed"
  wait_until "[ -s '$d/rc' ]"; ffunclaim; wait
  [ "$(cat "$d/rc")" = 1 ] || fail "the run with fxbad failing did not exit 1 (exit $(cat "$d/rc")): $(cat "$d/run")"
  [ ! -e "$d/slow" ] && [ ! -e "$d/late" ] || fail "the runner, waiting for a slot a push took, let fxslow run on or started fxlate after fxbad failed: $(cat "$d/run")"
  grep -qx 'conveyor: the run stopped at its first failed case, fxbad; not run: fxslow fxlate' "$d/run" \
    || fail "the runner did not name fxslow and fxlate as not run: $(cat "$d/run")"
}

# Bug it catches (#1616): when a.test.sh ran past its time limit, the run ended b.test.sh, still running, as not run,
# and its result blamed the timeout on b.test.sh, the last file begun and not ended. It names a.test.sh, the file
# that timed out, as the timeout and the only file stopped, and b.test.sh as not run, never as passed. b.test.sh logs
# its own `== ` line in a second log of the run, test-changed.log, as .conveyor/test-changed.sh does: that log is read
# after the run's `files` log, which says b.test.sh was not run, and its `== ` line made b.test.sh open again.
t_failfasttimeout() {
  local d=$T/$CASE w=$T/$CASE/wt rc
  sidewt 2
  # a.test.sh first waits for b.test.sh to begin, so both are begun when its limit stops it
  printf '%s\n' '# timeout: 5' "i=0; while [ ! -e '$d/b-start' ] && [ \$i -lt 400 ]; do i=\$((i + 1)); sleep 0.05; done; sleep 120" > "$w/a.test.sh" # sleep: a.test.sh runs past its limit
  printf '%s\n' 'echo "== b.test.sh" >> "$CONVEYOR_TEST_LOG/test-changed.log"' ": > '$d/b-start'; sleep 120" > "$w/b.test.sh" # sleep: b.test.sh runs on until the stop ends it
  SIDEFAST=1 SIDELIMIT=60 siderun a.test.sh b.test.sh > "$d/out" 2>&1; rc=$?
  [ "$rc" = 124 ] && grep -q '^== b.test.sh$' "$w.test" || fail "the run with a.test.sh past its limit and b.test.sh begun did not end as timed out (exit $rc): $(cat "$d/out" "$w.test")"
  [ "$(jq -c '[.timeout.file, .stopped, .notRun, .passed]' "$d/fails")" = '["a.test.sh",["a.test.sh"],["b.test.sh"],[]]' ] \
    || fail "the run's result does not blame the timeout on a.test.sh alone and name b.test.sh as not run: $(cat "$d/fails") $(cat "$w.test")"
}

# Bug it catches (#1629): a card's run of files learned of a failed engine case only once the case's file ended, but
# the case's keeper writes its status before it ends what the case left (case_end, lib.sh), so the other files
# started cases through that cleanup. a.test.sh's runner runs fxbad, which fails and leaves a process that ignores
# TERM, so its cleanup takes 3 s; b.test.sh's runner runs fxwait, which ends 1.5 s after fxbad failed, then fxlate on
# the same slot (a pool of two, one a file). The run ends b.test.sh before fxlate starts, and names fxbad as failed and
# b.test.sh as not run. The runners of a fixture engine (fxengine(), gitfence.test.sh) are run whole: only their run
# shows when a file's runner tells the run of files of a failed case, and which cases the other one starts.
t_failfastcleanup() {
  local d=$T/$CASE w=$T/$CASE/wt n=t_ rc bad wt
  sidewt 2
  bad="${n}fxbad() { ( trap '' TERM; exec sleep 30 ) & : > '$d/bad'; echo 'FAIL [fxbad]: broken'; return 1; }" # sleep: a leftover that ignores TERM, so the case's cleanup takes 3 s
  wt="${n}fxwait() { local i=0; while [ ! -e '$d/bad' ] && [ \$i -lt $(loadlimit 300) ]; do i=\$((i + 1)); sleep 0.05; done; sleep 1.5; }" # sleep: fxwait ends inside fxbad's 3 s cleanup
  fxengine "$d" "$bad
$wt
${n}fxlate() { : > '$d/late'; }"
  echo "{\"testSlots\": 2, \"testSlotsDir\": \"$d/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the pool of two"
  echo "CONVEYOR_SHELL_TEST_CASE=fxbad exec bash '$d/src/conveyor.test.sh'" > "$w/a.test.sh"
  echo "CONVEYOR_SHELL_TEST_CASE='fxwait fxlate' exec bash '$d/src/conveyor.test.sh'" > "$w/b.test.sh"
  SIDEFAST=1 SIDELIMIT=60 siderun a.test.sh b.test.sh > "$d/out" 2>&1; rc=$?
  [ "$rc" != 0 ] || fail "the run with fxbad failing passed: $(cat "$d/out" "$w.test")"
  [ ! -e "$d/late" ] || fail "b.test.sh started fxlate after a.test.sh's fxbad failed, while fxbad's cleanup ran: $(cat "$w.test")"
  [ "$(jq -c '[(.files | map([.file, (.cases | map(.name))])), .notRun]' "$d/fails")" = '[[["a.test.sh",["fxbad"]]],["b.test.sh"]]' ] \
    || fail "the run does not name a.test.sh's fxbad as failed and b.test.sh as not run: $(cat "$d/fails") $(cat "$w.test")"
  [ ! -e "$w.testlog/files.out" ] || fail "the run left its files' output folder, with: $(ls -A "$w.testlog/files.out")"
}

# Bug it catches (#1629): a run stopped by a file's failed mark (CONVEYOR_TEST_RED, lib/fileeach.sh) passed when that
# file then passed, though it ended the other file and named it not run. a.test.sh makes its mark and passes once
# b.test.sh has begun; b.test.sh runs until the stop ends it. The run fails.
t_failfastmarkpass() {
  local d=$T/$CASE w=$T/$CASE/wt rc
  sidewt 2
  echo "i=0; while [ ! -e '$d/b-start' ] && [ \$i -lt $(loadlimit 200) ]; do i=\$((i + 1)); sleep 0.05; done; : > \"\$CONVEYOR_TEST_RED\"; sleep 1; echo 'ok one'" > "$w/a.test.sh" # sleep: a.test.sh passes after the run read its mark
  echo ": > '$d/b-start'; sleep 120" > "$w/b.test.sh" # sleep: b.test.sh runs on until the stop ends it
  SIDEFAST=1 SIDELIMIT=60 siderun a.test.sh b.test.sh > "$d/out" 2>&1; rc=$?
  [ "$rc" != 0 ] || fail "the run that a.test.sh's failed mark stopped passed when a.test.sh passed: $(cat "$d/out" "$w.test")"
  [ "$(jq -c '.notRun' "$d/fails")" = '["b.test.sh"]' ] || fail "the run did not name b.test.sh as not run: $(cat "$d/fails") $(cat "$w.test")"
}

# Issue 1662 (E7, review). Bug it catches: a file its runner did not start for want of room in the temp space (its
# runner logs `TESTRUN host<TAB><file><TAB><why>` and exits 1, as .conveyor/test-changed.sh does) was the run's first
# failure, so the run ended b.test.sh, which could finish, and named it not run. h.test.sh is refused so once b.test.sh
# has begun; b.test.sh ends 2 s (times the load factor) after that: it finishes and passes, and h.test.sh is named as a host problem alone.
t_failfasthost() {
  local d=$T/$CASE w=$T/$CASE/wt rc
  sidewt 2
  printf '%s\n' "i=0; while [ ! -e '$d/b-start' ] && [ \$i -lt $(loadlimit 200) ]; do i=\$((i + 1)); sleep 0.05; done" \
    'printf "TESTRUN host\th.test.sh\tno room\n" >> "$CONVEYOR_TEST_LOG/test-changed.log"; echo "test-changed: h.test.sh did not start: no room"' \
    ": > '$d/h-done'; exit 1" > "$w/h.test.sh"
  printf '%s\n' ": > '$d/b-start'; i=0; while [ ! -e '$d/h-done' ] && [ \$i -lt $(loadlimit 200) ]; do i=\$((i + 1)); sleep 0.05; done" \
    "sleep $(loadlimit 2); : > '$d/late'; echo 'ok one'" > "$w/b.test.sh" # sleep: b.test.sh ends past the run's read of h.test.sh's exit, so a stop then would end it first
  SIDEFAST=1 SIDELIMIT=60 siderun h.test.sh b.test.sh > "$d/out" 2>&1; rc=$?
  [ "$rc" != 0 ] || fail "the run with h.test.sh not started for want of room passed, so no Test step reads it as a host problem: $(cat "$d/out" "$w.test")"
  [ -e "$d/late" ] || fail "with the rule on, the run ended b.test.sh after h.test.sh's runner logged it not started for want of room (TESTRUN host): $(cat "$w.test")"
  [ "$(jq -c '[.notRun, .passed, .host, (.files | map(.file))]' "$d/fails")" = '[null,["b.test.sh"],["h.test.sh"],[]]' ] \
    || fail "the run with h.test.sh not started for want of room (TESTRUN host) does not name b.test.sh as passed and h.test.sh as host alone: $(cat "$d/fails") $(cat "$w.test")"
}
