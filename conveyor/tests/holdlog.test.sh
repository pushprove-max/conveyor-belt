#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: each hold the control record drops is logged with who or what dropped it (ctlput(), lib/control.sh,
# in holds-dropped.jsonl beside the card records).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# #1676: the owner's holds left `held` and the control record logged no release: a release not by the owner (a
# Foreman's retry, CONVEYOR_RELEASEBY) dates nothing in `released`. Bug caught: a hold dropped with no line naming who
# dropped it. The owner's release is logged as the owner's, the Foreman's retry of a held issue as the Foreman's, and a
# release of an issue the record does not hold, or a hold, logs nothing.
t_holdlogrelease() {
  local out cmd
  setup "$(jq -cs . <(issue 4 2026-01-01) <(issue 5 2026-01-02) <(issue 6 2026-01-03))"
  landed 6 | jq -c '.step = "blocked" | .result = "blocked" | .reason = "build: it failed"' >> "$ST/cards.jsonl"
  loop control hold 4 5 6 >/dev/null || fail "control hold 4 5 6 failed"
  [ ! -e "$ST/holds-dropped.jsonl" ] || fail "control hold 4 5 6 logged a dropped hold: $(cat "$ST/holds-dropped.jsonl")"
  cmd='control release 4'; loop control release 4 >/dev/null || fail "$cmd failed"
  cmd='CONVEYOR_RETRYBY=foreman retry 6'; out=$(CONVEYOR_RETRYBY=foreman loop retry 6 2>&1) || fail "$cmd failed: $out"
  cmd='control release 7 (an issue not held)'; loop control release 7 >/dev/null 2>&1
  [ "$(jq -c .held "$ST/control.json")" = '[5]' ] || fail "after control release 4 and $cmd, held is not [5]: $(cat "$ST/control.json")"
  out=$(jq -sc 'map({issue, by})' "$ST/holds-dropped.jsonl" 2>&1)
  [ "$out" = '[{"issue":4,"by":"owner"},{"issue":6,"by":"foreman"}]' ] \
    || fail "control release 4, CONVEYOR_RETRYBY=foreman retry 6 and control release 7 did not log #4 by the owner and #6 by the Foreman alone: $out"
  jq -se 'all(.[]; .at | test("^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))' "$ST/holds-dropped.jsonl" >/dev/null \
    || fail "a dropped hold's line has no time: $(cat "$ST/holds-dropped.jsonl")"
}
# Bug caught: a writer whose copy of the record is older than the file (read before a `control hold`) drops that hold
# when it writes, and only a log of what the file held, not of its own copy, names the drop. The hold of #5 came after
# the copy; ctlput, given that copy with a new cap and no one named, logs #5 by the function that called it.
t_holdlogstale() {
  setup "$(jq -cs . <(issue 4 2026-01-01) <(issue 5 2026-01-02))"
  loop control hold 4 >/dev/null || fail "control hold 4 failed"
  cp "$ST/control.json" "$T/$CASE/old.json"
  loop control hold 5 >/dev/null || fail "control hold 5 failed"
  fx_in 'stalewrite() { local c; c=$(cat "'"$T/$CASE/old.json"'") && ctlput "$c" "$(jq -c ".cap = 3" <<<"$c")"; }; stalewrite'
  [ "$RC" = 0 ] || fail "ctlput of the copy from before control hold 5 failed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -sc 'map({issue, by})' "$ST/holds-dropped.jsonl" 2>&1)" = '[{"issue":5,"by":"stalewrite"}]' ] \
    || fail "ctlput (from stalewrite) of a copy of [4] over a record holding [4,5] did not log #5 by stalewrite: $(cat "$ST/holds-dropped.jsonl" 2>&1)"
}
