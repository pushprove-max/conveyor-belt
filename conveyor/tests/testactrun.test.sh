#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the test actions' run by hand (lib/testaction.sh, issue 517): `testaction run <test file>` runs one test
# file of main on a test slot. Their fixture is trsetup here, on testaction.test.sh's tasetup and tarec; the stop of a
# run is in testactstop.test.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The setup of a run by hand (testaction run, issue 517): tasetup's main, and a pool of the case's own of one slot
# ($T/$CASE/slots, the host file's testSlotsDir, written before setup), so the slot the run takes can be seen. The
# test command keeps the list it is given ($STUB/tr-list), its own pid ($STUB/tr-pid) and whether slot 1 is held
# while it runs ($STUB/tr-held); writes its words; times tests/x.test.sh in its log at 3.5 s and 2.25 CPU s; waits
# for $STUB/tr-go; and exits with $STUB/tr-rc, 0 when there is none.
trsetup() {
  export XDG_CONFIG_HOME=$T/$CASE/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the host file was not written"
  tasetup
  wait_fn > "$STUB/test-cmd"; cat >> "$STUB/test-cmd" <<'EOF'
cat "$CONVEYOR_TEST_RERUN" > "$STUB/tr-list"; echo $$ > "$STUB/tr-pid"
if flock -n "$STUB/../slots/1" true; then echo free; else echo held; fi > "$STUB/tr-held"
echo "running tests/x.test.sh"
printf 'TESTRUN sec\ttests/x.test.sh\t3.5\t2.25\n' > "$CONVEYOR_TEST_LOG/r.log"
wait_poll [ -e "$STUB/tr-go" ]
exit "$(cat "$STUB/tr-rc" 2>/dev/null || echo 0)"
EOF
}
trfree() { flock -n "$T/$CASE/slots/1" true; } # the pool's one slot is free

# Bug it catches (#1036): the Tests page lists the files the pack's tests.patterns match, but Run refused each one
# whose name has no .test. in it. tafile() takes src/test-a.mjs, which the pack's test-*.mjs matches, and still
# refuses src/helper.mjs, which no pattern matches. The ask itself (taask) is stubbed: what runs is t_tarun's.
t_tarunpattern() {
  setup '[]'; tune '.tests.patterns = ["test-*.mjs"]'; local out
  mkdir -p "$R/src" && echo 'export {};' > "$R/src/test-a.mjs" && cp "$R/src/test-a.mjs" "$R/src/helper.mjs" && git -C "$R" add src \
    && git -C "$R" commit -qm 'a test file and a helper' || fail "main's files"
  out=$(export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && . "$SRC/lib/prompts.sh" \
    && . "$SRC/lib/issues.sh" && . "$SRC/lib/testaction.sh" && names || exit 1
    taask() { echo "asked"; }
    for p in src/test-a.mjs src/helper.mjs; do e=$(tafile "$p" 2>&1); echo "$? $p: $e"; done) || fail "the engine could not be loaded: $out"
  [ "$(grep -oE '^[0-9]+ src/[^:]*' <<<"$out" | paste -sd, -)" = '0 src/test-a.mjs,2 src/helper.mjs' ] || fail "the paths tafile took and refused: $out"
}

# Bug it catches (release 1.12.0, tarun): a run by hand of the suite runner is refused at once by its runner
# (tarunfile(), "is left off the card's list"), and when that refusal had written the record as failed before the ask
# read it, the ask said the action did not start and gave no id, so `testaction run` failed though the run (with the
# refusal as its reason, for the Board) was there. taask() itself, on the record that race leaves: failed, with its
# <id>.txt (the runner wrote it, so it started; a regular file by then). A record failed with no <id>.txt (tafail(): it never started) is still
# refused with its reason.
t_taaskended() {
  setup '[]'; local out
  out=$(export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && . "$SRC/lib/prompts.sh" \
    && . "$SRC/lib/issues.sh" && . "$SRC/lib/testaction.sh" && names || exit 1
    TESTACTS=$T/$CASE/ta; mkdir -p "$TESTACTS" || exit 1
    echo '{"id": "aaaaaaaaaaaa", "state": "failed", "reason": "it did not run: conveyor: tests/run.test.sh is left off the card'"'"'s list: the test runner, not a test"}' > "$TESTACTS/aaaaaaaaaaaa.json"
    # A regular file, as tarunfile() leaves it: it copies <worktree>.test over its link before it records failed.
    echo "conveyor: tests/run.test.sh is left off the card's list: the test runner, not a test" > "$TESTACTS/aaaaaaaaaaaa.txt"
    echo '{"id": "bbbbbbbbbbbb", "state": "failed", "reason": "the copy of main the session reads could not be made"}' > "$TESTACTS/bbbbbbbbbbbb.json"
    for id in aaaaaaaaaaaa bbbbbbbbbbbb; do e=$(taask "$id" 2>&1); echo "$? $id: $e"; done) || fail "the engine could not be loaded: $out"
  grep -qx '0 aaaaaaaaaaaa: aaaaaaaaaaaa' <<<"$out" \
    || fail "taask aaaaaaaaaaaa (record failed by its runner's refusal, <id>.txt there): the ask did not give the id: $out"
  grep -qx '1 bbbbbbbbbbbb: conveyor: the test action bbbbbbbbbbbb did not start: the copy of main the session reads could not be made' <<<"$out" \
    || fail "taask bbbbbbbbbbbb (record failed before it started, no <id>.txt): the ask was not refused with its reason: $out"
}

# One case on one fixture (trsetup): its refused paths, then a run that passes, then one that fails. Each case of
# its own paid the fixture again.
# Bugs this guards (issue 517): the owner could not time one test file without a card. A run by hand of a path that is
# not a test file of main (a source file, a file main has not, a path out of the repo, a helper main has in a __tests__
# folder) ran something, or took a slot. A run by hand ran more than the file, or ran it with no test slot, beside the
# cards' runs; its record did not say how it went or how long it took; its slot stayed taken. A file that fails run by
# hand lost its output, or its record said it passed.
t_tarun() {
  trsetup; local id p out
  mkdir -p "$R/tests/__tests__/lib" && echo 'helper() { :; }' > "$R/tests/__tests__/lib/helper.sh" && git -C "$R" add tests \
    && git -C "$R" commit -qm 'a test helper' || fail "the helper could not be committed"
  # tafile() itself, the function `testaction run` hands the path to, in one shell for the five paths: a whole
  # conveyor.sh a path paid its start-up five times over.
  out=$(export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && . "$SRC/lib/prompts.sh" \
    && . "$SRC/lib/issues.sh" && . "$SRC/lib/testaction.sh" && names || exit 1
    for p in a.txt tests/none.test.sh tests/../tests/x.test.sh "$R/tests/x.test.sh" tests/__tests__/lib/helper.sh; do
      e=$(tafile "$p" 2>&1); echo "$? $p: $e"
    done) || fail "the engine could not be loaded: $out"
  [ "$(grep -c '^2 .*: conveyor: .* is not a test file' <<<"$out")" = 5 ] || fail "a run of a path that is not a test file was not refused: $out"
  # Once through the command itself: `testaction run` must hand tafile's refusal on as exit 2, not swallow it.
  out=$(loop testaction run a.txt 2>&1); [ $? = 2 ] && grep -q 'is not a test file' <<<"$out" || fail "the command did not refuse a.txt with exit 2: $out"
  [ ! -e "$STUB/tr-held" ] && [ -z "$(ls "$ST/testactions" 2>/dev/null)" ] && { [ ! -e "$T/$CASE/slots/1" ] || trfree; } || fail "a refused run ran, or took the slot: $(ls "$ST/testactions" 2>&1)"

  id=$(loop testaction run tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the run did not start: $id"
  wait_until '[ -s "$STUB/tr-held" ]' "cat '$ST/testactions/$id.err'" || fail "the test command did not start"
  [ "$(cat "$STUB/tr-list")" = $'fail\ttests/x.test.sh' ] || fail "the command was not told to run that file alone: $(cat "$STUB/tr-list")"
  [ "$(cat "$STUB/tr-held")" = held ] && ! trfree || fail "the run does not hold the test slot while it runs"
  # limit (issue 571): the test run's time limit (testTimeout, 3600 in the test pack), not a session's (testActionTimeout).
  [ "$(tarec "$id" '[.state, .action, .file, .result, .end, (.load | type), .limit] | tojson')" = '["running","run","tests/x.test.sh",null,null,"number",3600]' ] \
    || fail "the record does not say running, with the machine's load and the test run's time limit: $(cat "$ST/testactions/$id.json")"
  wait_until "grep -q 'running tests/x.test.sh' '$ST/testactions/$id.txt'" || fail "the output is not in the text file while it runs"
  : > "$STUB/tr-go"
  wait_until "[ \"\$(tarec $id .state)\" != running ]" "cat '$ST/testactions/$id.json' '$ST/testactions/$id.err'" || fail "the record still says running after the run ended"
  [ "$(tarec "$id" '[.state, .result, .sec, .cpu, (.wait | type), (.end | type), has("pid")] | tojson')" = '["done","pass",3.5,2.25,"number","string",false]' ] \
    || fail "the record of the ended run has not its result, clock and CPU seconds and slot wait: $(cat "$ST/testactions/$id.json")"
  trfree || fail "the slot is still held once the run ended"
  grep -q 'running tests/x.test.sh' "$ST/testactions/$id.txt" && [ ! -L "$ST/testactions/$id.txt" ] || fail "the output was not kept: $(ls -l "$ST/testactions")"
  [ ! -e "$T/$CASE/cards/testactions/$id" ] && [ "$(git -C "$R" worktree list | wc -l)" = 1 ] || fail "the copy of main it ran in was left: $(git -C "$R" worktree list)"

  # A file that fails: its record says fail, and its output is kept. Bug it catches too (E9): at a load factor of 2
  # the run's limit is 7200 s (testTimeout 3600 scaled), but the record said 3600 while it ran (the Board's Running
  # line gave that limit), and only its end wrote 7200.
  echo 3 > "$STUB/tr-rc"; rm -f "$STUB/tr-go" "$STUB/tr-held"
  id=$(CONVEYOR_LOAD_FACTOR=2 loop testaction run tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the failing run did not start: $id"
  wait_until '[ -s "$STUB/tr-held" ]' "cat '$ST/testactions/$id.err'" || fail "the failing run's test command did not start"
  [ "$(tarec "$id" '[.state, .limit] | tojson')" = '["running",7200]' ] \
    || fail "testaction run tests/x.test.sh at a load factor of 2: the record while it runs does not give the scaled limit 7200: $(cat "$ST/testactions/$id.json")"
  : > "$STUB/tr-go"
  wait_until "[ \"\$(tarec $id .state)\" != running ]" "cat '$ST/testactions/$id.json' '$ST/testactions/$id.err'" || fail "the failing run did not end"
  [ "$(tarec "$id" '[.state, .result, .cpu, .limit] | tojson')" = '["done","fail",2.25,7200]' ] \
    || fail "the record of a failing file run at a load factor of 2 does not say fail with the scaled limit 7200: $(cat "$ST/testactions/$id.json")"
  grep -q 'running tests/x.test.sh' "$ST/testactions/$id.txt" || fail "the failing file's output was not kept: $(cat "$ST/testactions/$id.txt")"

  # Bug it catches (E9): a run that ended before it started (a suite runner, refused, so it had no scaled limit) had
  # its limit read from an empty value: jq failed on it and the record was written empty, so the Board lost the run.
  # Bug it catches too: the runner's refusal ended the run before the ask read its record, so the ask said it did not
  # start and gave no id, though its record (with the refusal as its reason) was there for the Board.
  echo 'echo all' > "$R/tests/run.test.sh" && git -C "$R" add tests/run.test.sh && git -C "$R" commit -qm 'a suite runner' || fail "the runner could not be committed"
  tune '.test.full = "bash tests/run.test.sh"'
  id=$(loop testaction run tests/run.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the run of the suite runner did not start: $id"
  wait_until "[ \"\$(tarec $id .state)\" != running ]" "cat '$ST/testactions/$id.json' '$ST/testactions/$id.err'" || fail "the run of the suite runner did not end"
  [ "$(tarec "$id" '[.state, .file, .limit] | tojson')" = '["failed","tests/run.test.sh",3600]' ] \
    || fail "testaction run tests/run.test.sh (the pack's test.full runs it): the record of the refused run does not say failed with its limit 3600: $(cat "$ST/testactions/$id.json")"
  # The Board shows this reason: it must say the file is the test runner, so the user runs a test file in its place.
  [[ $(tarec "$id" .reason) == *"tests/run.test.sh is left off the card's list: the test runner, not a test"* ]] \
    || fail "testaction run tests/run.test.sh (the pack's test.full runs it): the refused run's reason does not say it is the test runner: $(cat "$ST/testactions/$id.json")"
}
