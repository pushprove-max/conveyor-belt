#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a card blocked with its work kept is put to the owner as one open decision in the decision ledger, and
# the answer takes its step (needsask(), lib/needsask.sh, which the loop calls every IDLE seconds as a job beside the
# cards). Each case calls needsask() as the loop's job does, through fx_in (lib.sh), with the ledger in the case's folder.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# nainit <issue>...: the ledger in the case's folder, and the blocked card c0-<issue> of each, its patch kept in
# kept/c0-<issue>/ (a.txt gets the line two), as the engine blocks a card whose work it keeps.
nainit() {
  local n; export CONVEYOR_LEDGER=$T/$CASE/decisions.jsonl; mkdir -p "$ST"
  for n; do
    mkdir -p "$ST/kept/c0-$n" && echo two >> "$R/a.txt" && git -C "$R" diff > "$ST/kept/c0-$n/c0-$n.patch" && git -C "$R" reset -q --hard || fail "the kept patch of c0-$n"
    landed "$n" | jq -c --arg k "kept/c0-$n" '(.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed" | .kept = $k)' >> "$ST/cards.jsonl"
  done
}
# nask: one pass of needsask(); its output is in run.out.
nask() { fx_in needsask; [ "$RC" = 0 ] || fail "needsask exited $RC: $(cat "$T/$CASE/run.out")"; }
# nadec <card>: the ledger's latest snapshot of the card's decision, as one JSON line.
nadec() { jq -cs --arg id "blocked-$1" 'map(select(.id == $id)) | last // empty' "$CONVEYOR_LEDGER" 2>/dev/null; }
# nanswer <card> <answer>: the owner's answer, as the Board records it.
nanswer() { bash "$SRC/../.claude/scripts/decision.sh" answer "blocked-$1" "$2" > /dev/null || fail "the answer $2 to blocked-$1 was not recorded"; }

# Bug (#1167): a card blocked with its work kept was a "needs you" item the owner learned of only from the Foreman, by
# hand, and no ledger decision held it, so `auto decide` had nothing to decide. One pass puts one open decision in the
# ledger for it, naming the card, with "Retry keeping the work" recommended and the two other steps as options. A second
# pass, and a pass after a card of another issue blocks, add no second decision for it.
t_needsask() {
  local d
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; nainit 7
  nask
  d=$(nadec c0-7); [ -n "$d" ] || fail "no decision blocked-c0-7 in the ledger: $(cat "$CONVEYOR_LEDGER" 2>&1) $(cat "$T/$CASE/run.out")"
  jq -e '.answeredAt == null and .proposedDefault == "Retry keeping the work" and .options == ["Retry keeping the work", "Fresh retry", "Leave it held"]
    and (.question | contains("c0-7") and contains("#7") and contains("build: it failed"))' <<<"$d" > /dev/null \
    || fail "the decision is not open, naming the card, with the recommended retry and the two other options: $d"
  nainit 8; nask; nask
  [ "$(jq -sr 'map(.id) | sort | join(" ")' "$CONVEYOR_LEDGER")" = "blocked-c0-7 blocked-c0-8" ] \
    || fail "a pass added a second decision for a card, or none for #8's: $(cat "$CONVEYOR_LEDGER")"
}

# Bug (#1167): the answer to the decision did nothing, so the owner's pick had to be carried out by hand. Answered
# "Retry keeping the work", the next pass gives #7 back as `retry 7` does: the card's lines move to the retried file with
# a retriedAt, its kept patch stays where it is for the next card, and it is moved nowhere. No other decision answered.
t_needsretry() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; nainit 7 8
  nask; nanswer c0-7 'Retry keeping the work'; nask
  [ "$(jq -r 'select(.card == "c0-7" and .step == "blocked") | .retriedAt != null' "$ST/retried.jsonl")" = true ] \
    || fail "#7's card was not given back: $(cat "$T/$CASE/run.out") $(cat "$ST/retried.jsonl" 2>&1)"
  [ "$(st 'select(.card == "c0-7") | .step' | wc -l)" = 0 ] && [ "$(st 'select(.card == "c0-8") | .step' | tail -n 1)" = blocked ] \
    || fail "#7's lines did not leave the card records, or #8's did: $(cat "$ST/cards.jsonl")"
  [ -s "$ST/kept/c0-7/c0-7.patch" ] && [ ! -e "$ST/kept-dropped" ] || fail "the kept work was moved aside: $(ls -R "$ST" 2>&1 | head -20)"
  [ "$(nadec c0-8 | jq .answeredAt)" = null ] || fail "#8's decision was answered: $(nadec c0-8)"
}

# Bug (#1167): the same, answered "Fresh retry": the next card builds from nothing, so the kept patch moves to the
# dated kept-dropped folder, as `retry 7 --fresh` does.
t_needsfresh() {
  setup "[$(issue 7 2026-01-01)]"; nainit 7
  nask; nanswer c0-7 'Fresh retry'; nask
  [ "$(jq -r 'select(.card == "c0-7" and .step == "blocked") | .retriedAt != null' "$ST/retried.jsonl")" = true ] && [ ! -e "$ST/kept/c0-7" ] \
    && [ -n "$(find "$ST/kept-dropped" -name 'c0-7.patch' 2>/dev/null)" ] \
    || fail "the card was not given back with its work moved aside: $(cat "$T/$CASE/run.out") $(ls -R "$ST" 2>&1 | head -20)"
}

# Bug (#1167): "Leave it held" must take no step: the card stays blocked with its work, however often the answered
# decision is read.
t_needsheld() {
  setup "[$(issue 7 2026-01-01)]"; nainit 7
  nask; nanswer c0-7 'Leave it held'; nask; nask
  [ ! -e "$ST/retried.jsonl" ] && [ "$(st 'select(.card == "c0-7") | .step' | tail -n 1)" = blocked ] && [ -s "$ST/kept/c0-7/c0-7.patch" ] \
    || fail "the card was given back, or its work moved, on an answer that leaves it held: $(cat "$T/$CASE/run.out") $(cat "$ST/cards.jsonl")"
}

# Bug (#1167): a card the owner retried by hand left its decision open on the Board for good, and answering it later
# would retry the issue's next card behind the owner's back. Retried by hand, the next pass closes the decision (answered
# with the engine's closing text, not a step); the issue's next card, c1-7, then blocks with its own work; the closed
# decision read again takes no step (c1-7 stays blocked, nothing is given back) and c1-7 has a decision of its own.
t_needsgone() {
  setup "[$(issue 7 2026-01-01)]"; nainit 7
  nask; loop retry 7 > "$T/$CASE/hand.out" 2>&1 || fail "the retry by hand failed: $(cat "$T/$CASE/hand.out")"
  nask
  jq -e '.answeredAt != null and (.answer | startswith("Closed"))' <<<"$(nadec c0-7)" > /dev/null || fail "the decision was not closed by the retry by hand: $(nadec c0-7) $(cat "$T/$CASE/hand.out" "$T/$CASE/run.out")"
  mkdir -p "$ST/kept/c1-7" && cp "$ST/kept/c0-7/c0-7.patch" "$ST/kept/c1-7/c1-7.patch" \
    && landed 7 | jq -c --arg k kept/c1-7 '.card = "c1-7" | (.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = "tests failed" | .kept = $k)' >> "$ST/cards.jsonl" \
    || fail "the next card's kept work could not be made"
  nask; nask
  [ "$(st 'select(.card == "c1-7") | .step' | tail -n 1)" = blocked ] && [ -z "$(jq -r 'select(.card == "c1-7")' "$ST/retried.jsonl")" ] \
    || fail "the closed decision gave the issue's next card back: $(cat "$T/$CASE/run.out") $(cat "$ST/retried.jsonl")"
  [ "$(nadec c1-7 | jq .answeredAt)" = null ] || fail "the next card has no decision of its own, or it was answered: $(nadec c1-7)"
}

# Bug (review of #1169): `conveyor.sh serve` is the loop that calls needsask() every IDLE seconds, but its command file
# did not source lib/needsask.sh, so every pass in the service log read "needsask: command not found" and no decision
# was posted or acted on. The other cases load the libraries of `run`; this one loads those `serve` loads (the lines of
# commands/serve.sh, as the cases of testreport.test.sh do) and checks that needsask() is defined and posts the decision.
t_needsserve() {
  setup "[$(issue 7 2026-01-01)]"; nainit 7
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && names \
      && needsask ) > "$T/$CASE/run.out" 2>&1 || fail "needsask did not run with the libraries serve loads: $(cat "$T/$CASE/run.out")"
  [ -n "$(nadec c0-7)" ] || fail "serve's libraries did not post the decision blocked-c0-7: $(cat "$T/$CASE/run.out")"
}
