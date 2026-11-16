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
  cat > "$STUB/test-cmd" <<'EOF'
cat "$CONVEYOR_TEST_RERUN" > "$STUB/tr-list"; echo $$ > "$STUB/tr-pid"
if flock -n "$STUB/../slots/1" true; then echo free; else echo held; fi > "$STUB/tr-held"
echo "running tests/x.test.sh"
printf 'TESTRUN sec\ttests/x.test.sh\t3.5\t2.25\n' > "$CONVEYOR_TEST_LOG/r.log"
until [ -e "$STUB/tr-go" ]; do sleep 0.1; done
exit "$(cat "$STUB/tr-rc" 2>/dev/null || echo 0)"
EOF
}
trfree() { flock -n "$T/$CASE/slots/1" true; } # the pool's one slot is free

# Bugs this guards (issue 517): the owner could not time one test file without a card. A run by hand ran more than the
# file, or ran it with no test slot, beside the cards' runs; its record did not say how it went or how long it took;
# its slot stayed taken; its time was lost to the next card that changed the file, which had no before.
t_tarun() {
  trsetup; local id got w=$T/$CASE/wt
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
  # A later card whose change modifies the file, over a 1 CPU s budget, gets the run's time as its before.
  tune '.test.fileBudget = 1'
  git -C "$R" worktree add -q --detach "$w" && echo more >> "$w/tests/x.test.sh" && git -C "$w" add tests && mkdir -p "$w.testlog" \
    && printf 'TESTRUN sec\ttests/x.test.sh\t9\t9\n' > "$w.testlog/r.log" || fail "the later card's worktree"
  got=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && slowtests "$w" && jq -c 'map({file, before, from})' "$w.slow" ) )
  [ "$got" = "[{\"file\":\"tests/x.test.sh\",\"before\":2.25,\"from\":\"run by hand, $(tarec "$id" '.end[:10]')\"}]" ] || fail "the later card's before is not the run by hand's: $got"
}

# Bug this guards (issue 517): a file that fails run by hand lost its output, or its record said it passed.
t_tarunfail() {
  trsetup; local id
  echo 3 > "$STUB/tr-rc"; : > "$STUB/tr-go"
  id=$(loop testaction run tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the run did not start: $id"
  wait_until "[ \"\$(tarec $id .state)\" != running ]" "cat '$ST/testactions/$id.json' '$ST/testactions/$id.err'" || fail "the failing run did not end"
  [ "$(tarec "$id" '[.state, .result, .cpu] | tojson')" = '["done","fail",2.25]' ] || fail "the record of a failing file does not say fail: $(cat "$ST/testactions/$id.json")"
  grep -q 'running tests/x.test.sh' "$ST/testactions/$id.txt" || fail "the failing file's output was not kept: $(cat "$ST/testactions/$id.txt")"
}

# Bug this guards (issue 517): a run by hand of a path that is not a test file of main (a source file, a file main has
# not, a path out of the repo, a helper main has in a __tests__ folder) ran something, or took a slot.
t_tarunrefused() {
  trsetup; local p out
  mkdir -p "$R/tests/__tests__/lib" && echo 'helper() { :; }' > "$R/tests/__tests__/lib/helper.sh" && git -C "$R" add tests \
    && git -C "$R" commit -qm 'a test helper' || fail "the helper could not be committed"
  for p in a.txt tests/none.test.sh tests/../tests/x.test.sh "$R/tests/x.test.sh" tests/__tests__/lib/helper.sh; do
    out=$(loop testaction run "$p" 2>&1); [ $? = 2 ] && grep -q 'is not a test file' <<<"$out" || fail "the run of $p was not refused: $out"
  done
  [ ! -e "$STUB/tr-held" ] && [ -z "$(ls "$ST/testactions" 2>/dev/null)" ] && { [ ! -e "$T/$CASE/slots/1" ] || trfree; } || fail "a refused run ran, or took the slot: $(ls "$ST/testactions" 2>&1)"
}
