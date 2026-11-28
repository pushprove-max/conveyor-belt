#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (issue 1827): a main-red fix card that closes as already done (bugproof.sh redclosed()) adds one entry
# to the flaky-test record (lib/flaky.sh) for each case that passed in each run alone (REDPASS), the card its source.
# A case that fails on main only beside other files closes its card as already done each time; three such closes in
# FLAKY_DAYS days file its flaky issue, and card test steps keep it off (flakyoff()).
# The fixtures are mainredproof.test.sh's (redsetup) and mainred.test.sh's (eng): the runner sources every
# case file before it runs a case.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The main-red record with one entry for each <card>, each holding the case `a.test: one` (file a.test).
redflakyrec() { # <card>...
  jq -cn '{reds: [$ARGS.positional[] | {card: ., sha: "s1", cases: [{case: "a.test: one", file: "a.test"}]}]}' --args "$@" > "$ST/mainred.json" \
    || fail "the main-red record could not be made"
}
# redclosed() on <card>, under the records' lock as its callers take it, after a run of its cases (REDRAN, as
# redproof() sets it) that left <REDPASS>, on main's commit 0123456789abcdef. Prints its stderr, then `rc=<exit>`.
redflakyclose() { # <card> <REDPASS json> [shell code run first, in the engine]
  eng "${3:-}"'REDRAN=$(redcases '"$1"') REDPASS='"'$2'"' REDSHA=0123456789abcdef
    locked redclosed '"$1"' "$(line '"$1"' 0 closed ok "{\"reason\":\"r\"}")"; echo "rc=$?"' 2>&1
}

# D1. Bug it catches: a fix card whose cases pass alone on main (bugproof.sh redgreen(), before its build session)
# closed as already done and nothing was recorded, so a case that fails only beside other files closed card after
# card while main stayed red. The real close (cardbuild(), greenclose()) adds one entry per case, from the card.
# Each run's result (mainred.sh redrun()) is given, every case passing: the real runs (tests()) are mainredproof.test.sh's
# to prove, and under a loaded test step they give no result at times, so the card did not close.
t_redflakygreen() {
  redsetup ''
  local s out w=$T/$CASE/cards/cfix; s=$(git -C "$R" rev-parse HEAD)
  jq -c '.reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json"
  git -C "$R" worktree add -q --detach "$w" HEAD || fail "the fix card's worktree could not be made"
  out=$(eng 'session() { return 1; }; redrun() { jq -c "map(. + {verdict: \"pass\"})" <<<"$2"; }
    c=cfix n=0 br="" mode="" wt=$CONVEYOR_CARDS/cfix sprompt=brief sf="" waitsec=4 mainsec=0 go=end; issue=$(redissue cfix) && cardbuild; echo "go $go"' 2>&1)
  [ -n "$(st 'select(.card == "cfix" and .step == "closed")')" ] || fail "the fix card did not close as already done: $out: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(jq -c '[.entries[] | [.case, .source, .card, .note]]' "$ST/flaky.json" 2>&1)" = "$(jq -cn --arg n "failed on main, then passed 3 runs alone on main at ${s:0:12}: closed as already done" \
    '[["a.test: one", "cfix", "cfix", $n], ["c.test", "cfix", "cfix", $n]]')" ] \
    || fail "the close of cfix (cases \`a.test: one\` and \`c.test\` passing) did not add one entry per case from cfix: $(cat "$ST/flaky.json" 2>&1)"
}

# D2. Three main-red cards, each closed as already done for `a.test: one`, are three sources: the third close files the
# flaky issue (one), and while it is open a card's test step keeps the case off (flakyoff()). Bug it catches: three
# such closes in 40 minutes kept the test on every card's run, and main went red for it a fourth time.
t_redflakythree() {
  setup '[]'
  local c out w=$T/$CASE/wt
  redflakyrec c1-0 c2-0 c3-0
  for c in c1-0 c2-0 c3-0; do
    out=$(redflakyclose "$c" '["a.test: one"]')
    [[ $out == *rc=0* ]] && [ -n "$(st "select(.card == \"$c\" and .step == \"closed\")")" ] || fail "redclosed $c with REDPASS [\"a.test: one\"] did not close it: $out"
  done
  [ "$(jq -c '[.entries[].source]' "$ST/flaky.json")" = '["c1-0","c2-0","c3-0"]' ] || fail "the three closes are not three sources: $(cat "$ST/flaky.json")"
  [ "$(jq -sc 'map(.title)' "$STUB/filed" 2>&1)" = '["Flaky test: a.test: one fails at random"]' ] \
    || fail "three closes from three cards did not file exactly one flaky issue for a.test: one: $(cat "$STUB/filed" 2>&1)"
  echo OPEN > "$STUB/state.100101"; : > "$w.rerun"
  eng 'flakyoff "'"$w"'"' || fail "flakyoff failed"
  grep -qxF "off"$'\t'"a.test"$'\t'"one" "$w.rerun" || fail "flakyoff on an empty test list did not keep a.test: one off while its flaky issue is open: $(cat "$w.rerun")"
}

# D3. A close with no case passing in each run (REDPASS empty: redproof()'s close with no test.fileCommand) adds no
# entry. Nor does a REDPASS left from another card's run: only this card's cases (REDRAN) count. Bug it catches: an
# entry for a case the card never ran.
t_redflakyempty() {
  setup '[]'
  local out
  redflakyrec c1-0 c2-0
  out=$(redflakyclose c1-0 '[]'); [[ $out == *rc=0* ]] || fail "redclosed c1-0 with REDPASS [] did not close it: $out"
  out=$(redflakyclose c2-0 '["b.test: two"]'); [[ $out == *rc=0* ]] || fail "redclosed c2-0 with REDPASS [\"b.test: two\"] did not close it: $out"
  [ "$(jq -c '.entries | length' "$ST/flaky.json" 2>/dev/null || echo 0)" = 0 ] \
    || fail "a close with REDPASS [], or one naming a case not of the card (b.test: two), added an entry: $(cat "$ST/flaky.json")"
}

# A flaky-test record that cannot be written does not stop the close: the closed line stays, and the card's log says
# which cases were not recorded. Bug it catches: the close failing (and the card blocked) for a record's write.
t_redflakyfail() {
  setup '[]'
  local out
  redflakyrec c1-0
  out=$(redflakyclose c1-0 '["a.test: one"]' 'flaky() { return 1; }; ')
  [[ $out == *rc=0* ]] && [ -n "$(st 'select(.card == "c1-0" and .step == "closed")')" ] \
    || fail "redclosed c1-0 with REDPASS [\"a.test: one\"] and flaky() failing did not close it: $out"
  [[ $out == *'conveyor: card c1-0: the flaky-test record could not be written: a.test: one'* ]] \
    || fail "redclosed c1-0 with flaky() failing did not say which case was not recorded: $out"
}
