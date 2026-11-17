#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what the snapshot (lib/snapshot.sh) reads of the machine beyond the cards' records: the test slots, and
# a bug card's proof run on main's code.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Board 3D's deck shows the machine's free test slots (issue 393): the snapshot's testSlots must be the pool's own
# count, read as a test run reads it (the host file's testSlots and testSlotsDir), and change as a slot is taken and
# given back; a count of the card cap or a fixed figure would show slots free while every test run waits for one.
t_snapslots() {
  local f
  export XDG_CONFIG_HOME=$T/$CASE/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 2, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup "[]"
  [ "$(loop snapshot | jq -c .testSlots)" = '{"used":0,"of":2}' ] || fail "with no slot held: $(loop snapshot | jq -c .testSlots)"
  # A test run holds slot 1, as slot_try takes it: a lock on its file.
  exec {f}>>"$T/$CASE/slots/1"; flock -n "$f" || fail "slot 1 could not be taken"
  [ "$(loop snapshot | jq -c .testSlots)" = '{"used":1,"of":2}' ] || fail "with slot 1 held: $(loop snapshot | jq -c .testSlots)"
  exec {f}>&-
  [ "$(loop snapshot | jq -c .testSlots)" = '{"used":0,"of":2}' ] || fail "once slot 1 was given back: $(loop snapshot | jq -c .testSlots)"
}

# Bug (#281): while a bug card's new tests ran on main's code without its fix (testrun.sh bugproof(), its live record
# $CARDS/mainrun/<card>.unfixed.live), the card's records ended with its build line, so the snapshot named the review
# after it ("review 1 of 3", the reviewer's model) though no review ran. That run is the card's step in progress: proof,
# on Build, with its files run. Once the review starts, a proof record left behind is not shown over it.
t_snapproof() {
  local s c=c20261117T100000-r-7
  setup "[]"
  # A line of the card's records: <step> <result> <minute of 2026-11-17T10> [extra json].
  snapproof_line() { jq -cn --arg c "$c" --arg s "$1" --arg r "$2" --arg t "2026-11-17T10:$3:00Z" --argjson x "${4:-{\}}" \
    '{card: $c, issue: 7, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: $r, sha: "", reason: "", repo: "r"} * $x'; }
  { snapproof_line picked ok 00 '{"title": "a bug", "created": "2026-11-17T09:59:00Z"}'; snapproof_line worktree ok 01
    snapproof_line deps ok 01; snapproof_line brief ok 02; snapproof_line start ok 02 '{"of": "build"}'; snapproof_line build ok 05; } > "$ST/cards.jsonl"
  mkdir -p "$T/$CASE/cards/mainrun"
  echo '{"step": "test", "at": "2026-11-17T10:06:00Z", "last": null, "turns": 0, "files": {"run": 297, "of": 1161}, "tests": null}' \
    > "$T/$CASE/cards/mainrun/$c.unfixed.live"
  s=$(loop snapshot | jq -c '.belt[0] | [.step, .review, .model, .track.label, .track.at, .track.detailAt, .track.files, .track.since]')
  [ "$s" = '["proof",null,null,"proof run",0,5,{"run":297,"of":1161},"2026-11-17T10:06:00Z"]' ] || fail "a card in its proof run: $s"
  # While it waits for a test slot (testrun.sh writes that action, no file run), the belt says so, not that tests run.
  echo '{"step": "test", "at": "2026-11-17T10:06:00Z", "last": null, "turns": 0, "files": {"run": 0, "of": null}, "tests": null, "action": "waiting for a test slot (2 of 2 in use)"}' \
    > "$T/$CASE/cards/mainrun/$c.unfixed.live"
  s=$(loop snapshot | jq -c '.belt[0] | [.step, .live.action]')
  [ "$s" = '["proof","waiting for a test slot (2 of 2 in use)"]' ] || fail "a proof run waiting for a test slot: $s"
  snapproof_line start ok 30 '{"of": "review"}' >> "$ST/cards.jsonl"
  s=$(loop snapshot | jq -c '.belt[0] | [.step, .review, .track.label, .track.files]')
  [ "$s" = '["review",1,"review 1 of 3",null]' ] || fail "a proof record left behind is shown over the review: $s"
}
