#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: each hold the control record drops is logged with who or what dropped it (ctlput(), lib/control.sh,
# in holds-dropped.jsonl beside the card records), and only the owner's retry of a held issue drops its hold (again(),
# commands/retry.sh; needsask(), lib/needsask.sh, for an answer to a blocked card's decision).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# #1676: the owner's holds left `held` and the control record logged no release. Bugs caught: a hold dropped with no
# line naming who dropped it, and a Foreman's retry of a held issue that released it with no release by the owner. The
# owner's release is logged as the owner's; the Foreman's retry gives the card back and leaves the hold; a release of an
# issue the record does not hold, or a hold, logs nothing.
t_holdlogrelease() {
  local out cmd
  setup "$(jq -cs . <(issue 4 2026-01-01) <(issue 5 2026-01-02) <(issue 6 2026-01-03))"
  landed 6 | jq -c '.step = "blocked" | .result = "blocked" | .reason = "build: it failed"' >> "$ST/cards.jsonl"
  loop control hold 4 5 6 >/dev/null || fail "control hold 4 5 6 failed"
  [ ! -e "$ST/holds-dropped.jsonl" ] || fail "control hold 4 5 6 logged a dropped hold: $(cat "$ST/holds-dropped.jsonl")"
  cmd='control release 4'; loop control release 4 >/dev/null || fail "$cmd failed"
  cmd='CONVEYOR_RETRYBY=foreman retry 6'; out=$(CONVEYOR_RETRYBY=foreman loop retry 6 2>&1) || fail "$cmd failed: $out"
  cmd='control release 7 (an issue not held)'; loop control release 7 >/dev/null 2>&1
  # Bugs caught too: the retry said #6 could be picked again, then that it stays held; and it joined the value of
  # HELDSTAYS to the line ("stays held1").
  grep -qF 'issue #6 is given back, and stays held; its old lines are in' <<<"$out" && grep -qF 'issue #6 is held, and stays held' <<<"$out" \
    && ! grep -qF 'can be picked again' <<<"$out" || fail "CONVEYOR_RETRYBY=foreman retry 6 did not say #6 stays held alone: $out"
  jq -se 'any(.[]; .issue == 6 and .step == "blocked" and .retriedBy == "foreman")' "$ST/retried.jsonl" >/dev/null 2>&1 \
    || fail "CONVEYOR_RETRYBY=foreman retry 6 did not give the card of #6 back: $(cat "$ST/retried.jsonl" 2>&1)"
  [ "$(jq -c .held "$ST/control.json")" = '[5,6]' ] \
    || fail "after control release 4, CONVEYOR_RETRYBY=foreman retry 6 and $cmd, held is not [5,6]: $(cat "$ST/control.json")"
  out=$(jq -sc 'map({issue, by})' "$ST/holds-dropped.jsonl" 2>&1)
  [ "$out" = '[{"issue":4,"by":"owner"}]' ] \
    || fail "control release 4, CONVEYOR_RETRYBY=foreman retry 6 and control release 7 did not log #4 by the owner alone: $out"
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

# holdask [again] [--by owner]: #7, held, has its card c0-7 blocked with its work kept; one pass of needsask() asks
# decision blocked-c0-7, the answer "Retry keeping the work" is recorded (with no --by, as auto decide records it), and
# a second pass takes its step. With again, c0-7 is blocked by its review after review-retry gave #7 back once (card
# cp-7), so the decision is asked as RRAGAIN (lib/standing.sh) says.
holdask() {
  local why='build: it failed'
  export CONVEYOR_LEDGER=$T/$CASE/decisions.jsonl
  setup "$(issue 7 2026-01-01 | jq -cs .)"; mkdir -p "$ST/kept/c0-7"
  echo two >> "$R/a.txt" && git -C "$R" diff > "$ST/kept/c0-7/c0-7.patch" && git -C "$R" show HEAD:a.txt > "$R/a.txt" || fail "the kept patch of c0-7"
  if [ "${1:-}" = again ]; then
    shift; why='the fix for [P1] a.txt:1 drops the line did not hold after 1 round'
    landed 7 | jq -c '.card = "cp-7" | (.step = "picked"), (.step = "blocked" | .result = "blocked" | .kept = "kept/cp-7"
      | .reason = "the fix for [P1] a.txt:1 drops the first line did not hold after 3 rounds" | .retriedAt = "2026-11-02T00:00:00Z" | .retriedBy = "review-retry")' >> "$ST/retried.jsonl"
  fi
  landed 7 | jq -c --arg why "$why" '(.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = $why | .kept = "kept/c0-7")' >> "$ST/cards.jsonl"
  loop control hold 7 >/dev/null || fail "control hold 7 failed"
  fx_in needsask; [ "$RC" = 0 ] || fail "needsask exited $RC: $(cat "$T/$CASE/run.out")"
  bash "$SRC/../.claude/scripts/decision.sh" answer blocked-c0-7 'Retry keeping the work' "$@" > /dev/null \
    || fail "the answer to blocked-c0-7 ($*) was not recorded"
  fx_in needsask; [ "$RC" = 0 ] || fail "needsask exited $RC: $(cat "$T/$CASE/run.out")"
  jq -se 'any(.[]; .card == "c0-7" and .step == "blocked" and .retriedAt != null)' "$ST/retried.jsonl" >/dev/null 2>&1 \
    || fail "blocked-c0-7 answered \"Retry keeping the work\" ($*) did not give c0-7 back: $(cat "$T/$CASE/run.out")"
}
# Bug: auto decide's answer "Retry keeping the work" to the decision of a held issue's blocked card ran the retry as
# `decision`, which released the hold, so the loop picked an issue the owner never released. #7 stays held.
t_holdlogauto() {
  holdask
  [ "$(jq -c '[.held, .released]' "$ST/control.json")" = '[[7],{}]' ] && [ ! -s "$ST/holds-dropped.jsonl" ] \
    || fail "needsask, blocked-c0-7 of the held #7 answered \"Retry keeping the work\" by auto decide (no --by), released #7: $(jq -c '[.held, .released]' "$ST/control.json"); $(cat "$ST/holds-dropped.jsonl" 2>&1); $(cat "$T/$CASE/run.out")"
}
# Bug: an answer that named no one (a Foreman's `decision.sh answer` with no --by) to the decision of a held issue's
# card blocked by its review again, after review-retry gave the issue back once, ran the retry as the owner's from the
# question's heading alone, which released the hold. #7 stays held.
t_holdlogagain() {
  holdask again
  jq -se 'any(.[]; .id == "blocked-c0-7" and (.question | contains("is blocked by its review again, after review-retry")))' "$CONVEYOR_LEDGER" >/dev/null \
    || fail "needsask did not ask blocked-c0-7 as a card blocked by its review again: $(cat "$CONVEYOR_LEDGER")"
  [ "$(jq -c '[.held, .released]' "$ST/control.json")" = '[[7],{}]' ] && [ ! -s "$ST/holds-dropped.jsonl" ] \
    || fail "needsask, blocked-c0-7 (blocked by its review again) of the held #7 answered \"Retry keeping the work\" with no --by, released #7: $(jq -c '[.held, .released]' "$ST/control.json"); $(cat "$ST/holds-dropped.jsonl" 2>&1); $(cat "$T/$CASE/run.out")"
}
# The owner's answer on the Board (decision.sh answer --by owner) is the owner's retry: it releases the held #7, dated
# in released and logged as the owner's. Bug caught: with auto's answer kept off the release, the owner's own answer
# left the issue held too.
t_holdlogboard() {
  holdask --by owner
  jq -e '.held == [] and (.released["7"] | type == "string")' "$ST/control.json" >/dev/null \
    && [ "$(jq -sc 'map({issue, by})' "$ST/holds-dropped.jsonl" 2>&1)" = '[{"issue":7,"by":"owner"}]' ] \
    || fail "needsask, blocked-c0-7 of the held #7 answered \"Retry keeping the work\" --by owner, did not release #7 as the owner's: $(cat "$ST/control.json"); $(cat "$ST/holds-dropped.jsonl" 2>&1); $(cat "$T/$CASE/run.out")"
}
