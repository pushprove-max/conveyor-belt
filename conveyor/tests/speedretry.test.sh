#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a card an older speed check blocked is retried by the loop itself once the check's version rises
# (speedretry(), lib/run.sh; SPEEDCHECK, lib/testrun.sh), with no one to run `retry` by hand.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# One blocked card a line of <issue> <speedcheck or null> <reason>: picked and blocked lines in the card records, its
# kept work in kept/c<issue>.
sr_blocked() { # <issue> <speedcheck> <reason>
  mkdir -p "$ST/kept/c$1" && echo patch > "$ST/kept/c$1/c$1.patch"
  jq -cn --argjson n "$1" --argjson v "$2" --arg r "$3" '{card: "c\($n)", issue: $n, tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""}
    | (. + {step: "picked", time: "2026-11-01T00:00:00Z"}), (. + {step: "blocked", result: "blocked", time: "2026-11-01T01:00:00Z", reason: $r, kept: "kept/c\($n)"}
      + (if $v == null then {} else {speedcheck: $v} end))' >> "$ST/cards.jsonl"
}
# speedretry() as the loop calls it at its start, with SPEEDCHECK at <version>; its output in $T/$CASE/run.out.
sr_start() { # <version>
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 9
    SPEEDCHECK=$1 speedretry ) > "$T/$CASE/run.out" 2>&1 || fail "speedretry failed: $(cat "$T/$CASE/run.out")"
}
sr_gone() { [ -z "$(st "select(.card == \"c$1\") | .card")" ]; } # <issue>: its card's lines left the card records

# Bug it catches (#180): a card blocked by the first speed check stays blocked once the fixed check is in, in every
# project with no Foreman to retry it. Each of its two reasons is retried at the loop's start as `retry --fresh`
# retries it (kept work moved to kept-dropped), with the line in the log and on the Board's earlier attempt (rows);
# a card the owner holds, and cards the current check blocked (its version, or its reason with no version), are not.
# A second start retries none again (SPEEDRETRIED), and a later version retries what the one before it blocked.
t_speedretry() {
  setup '[]'
  sr_blocked 11 null 'build: the file is not faster: 10 CPU s on record, 10 CPU s now'
  sr_blocked 12 null 'build: the files of the split are not faster: f.test.sh has 10 CPU s on record, f1.test.sh, f2.test.sh took 11 CPU s now'
  sr_blocked 13 2 'build: the split does not fit: f1.test.sh takes 9 CPU s, 1 over its budget of 8 CPU s'
  sr_blocked 14 null 'build: the file is not faster: 10 CPU s on record, 10 CPU s now; its budget is 8 CPU s'
  sr_blocked 15 null 'build: the file is not faster: 10 CPU s on record, 12 CPU s now'
  sr_blocked 16 null 'review: the review said NO-GO'
  sr_blocked 17 null 'build: the split does not fit: f1.test.sh takes 9 CPU s, 1 over its budget of 8 CPU s'
  sr_blocked 18 null 'build: the file is over the budget of its own that the build proposes: f.test.sh takes 9 CPU s'
  jq '.held = [15]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the hold"
  sr_start 2
  sr_gone 11 && sr_gone 12 || fail "a card the first check blocked was not retried: $(cat "$T/$CASE/run.out")"
  for n in 13 14 15 16 17 18; do sr_gone "$n" && fail "card c$n was retried: $(cat "$T/$CASE/run.out")"; done
  grep -qx 'conveyor: card c11 of issue #11: retried: the speed check that blocked it has changed' "$T/$CASE/run.out" \
    && grep -qx 'conveyor: card c12 of issue #12: retried: the speed check that blocked it has changed' "$T/$CASE/run.out" \
    || fail "the log does not say why: $(cat "$T/$CASE/run.out")"
  [ ! -e "$ST/kept/c11" ] && ls -d "$ST"/kept-dropped/*-11/c11 >/dev/null 2>&1 || fail "c11's kept work was not moved as --fresh moves it"
  [ "$( (export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && rows "$RETRIED") | jq -r '.[] | select(.card == "c11") | .reason')" \
    = 'build: the file is not faster: 10 CPU s on record, 10 CPU s now; retried: the speed check that blocked it has changed' ] \
    || fail "the Board's row of c11 does not say why it was retried: $(cat "$ST/retried.jsonl")"
  # A second start, with c11's blocked line back in the records: the record of its retry keeps it from a second one.
  jq -c 'select(.card == "c11") | del(.retriedAt, .retriedWhy)' "$ST/retried.jsonl" >> "$ST/cards.jsonl"
  sr_start 2
  sr_gone 11 && fail "a second loop start retried c11 again: $(cat "$T/$CASE/run.out")"
  # A later change to the check (version 3) retries what version 2 blocked, with its version on the line or, on a
  # line written before lines carried it (c14, c17, c18), told by its reason.
  sr_start 3
  for n in 13 14 17 18; do sr_gone "$n" || fail "card c$n, which version 2 blocked, was not retried once the version rose to 3: $(cat "$T/$CASE/run.out")"; done
  [ "$(jq -r .card "$ST/speedretried.jsonl" | sort | tr '\n' ' ')" = 'c11 c12 c13 c14 c17 c18 ' ] || fail "the record of retried cards: $(cat "$ST/speedretried.jsonl")"
}
