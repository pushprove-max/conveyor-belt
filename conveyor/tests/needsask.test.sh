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

# mmain <issue>...: the nightly whole test's record naming each issue as filed for a failing case ("case <issue>"), the
# control record holding each one with issue 8 first in `order` (the owner's earlier pick), every issue open on GitHub, and the
# ledger in the case's folder.
mmain() {
  export CONVEYOR_LEDGER=$T/$CASE/decisions.jsonl; mkdir -p "$ST"
  jq -cn --args '{sha: "abc", filed: [$ARGS.positional[] | {issue: tonumber, cases: ["x.test.sh: case \(.)"]}]}' "$@" > "$ST/maintest.json" || fail "the whole test's record could not be made"
  echo OPEN > "$STUB/state" # GitHub's state of every issue (the gh stub); a case closes one with state.<issue>
  loop control hold "$@" > /dev/null && loop control order 8 > /dev/null || fail "the held issues or the order could not be set"
}
# nmain: one pass of needsmain(); its output is in run.out.
nmain() { fx_in needsmain; [ "$RC" = 0 ] || fail "needsmain exited $RC: $(cat "$T/$CASE/run.out")"; }
# mdec <issue>: the ledger's latest snapshot of the issue's decision, as one JSON line.
mdec() { jq -cs --arg id "mainred-$1" 'map(select(.id == $id)) | last // empty' "$CONVEYOR_LEDGER" 2>/dev/null; }
# manswer <issue> <answer> [--by owner]: an answer that names no one, as `auto decide` records it; with --by owner, as
# the Board records the owner's.
manswer() { bash "$SRC/../.claude/scripts/decision.sh" answer "mainred-$1" "$2" "${@:3}" > /dev/null || fail "the answer $2 to mainred-$1 was not recorded"; }

# Bug (#1167): an issue the nightly whole test filed for a test that fails on main stayed held until the owner released
# it by hand, and no ledger decision held it, so `auto decide` had nothing to decide. One pass puts one open decision in
# the ledger for it, naming the issue, with releasing it first in the order recommended and leaving it held as the other
# option. A held issue the whole test did not file (#9), and a second pass, add none.
t_needsmain() {
  local d
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 9 2026-01-02))"; mmain 7; loop control hold 9 > /dev/null || fail "#9 was not held"
  nmain; nmain
  d=$(mdec 7); [ -n "$d" ] || fail "no decision mainred-7 in the ledger: $(cat "$CONVEYOR_LEDGER" 2>&1) $(cat "$T/$CASE/run.out")"
  jq -e '.answeredAt == null and .proposedDefault == "Release it, first in the order" and .options == ["Release it, first in the order", "Leave it held"]
    and (.question | contains("#7") and contains("case 7"))' <<<"$d" > /dev/null \
    || fail "the decision is not open, naming the issue, with the recommended release and the other option: $d"
  [ "$(jq -sr 'map(.id) | join(" ")' "$CONVEYOR_LEDGER")" = "mainred-7" ] || fail "a pass added a second decision, or one for #9: $(cat "$CONVEYOR_LEDGER")"
}

# Bug (#1167): the answer did nothing, so the owner's pick was carried out by hand. Answered "Release it, first in the
# order", the next pass releases #7 and puts it first in `order`, before #8 that was first. Read again, the answer
# changes nothing more. Bug (#1627): the release dated #7 as the owner's (released), though the answer names no one
# (auto's are so), so foreman status could credit the owner for auto's pick.
t_needsrelease() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; mmain 7
  nmain; manswer 7 'Release it, first in the order'
  nmain; nmain
  [ "$(jq -c '[.held, .order, .released]' "$ST/control.json")" = '[[],[7,8],{}]' ] \
    || fail "#7 was not released first in the order, or its release was dated as the owner's: $(cat "$ST/control.json") $(cat "$T/$CASE/run.out")"
}

# Bug (#1167): "Leave it held" must take no step: #7 stays held, however often the answered decision is read. #8,
# released by hand before its decision was answered, has the decision closed (the engine's closing text, not a step).
t_needsmainheld() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; mmain 7 8
  nmain; manswer 7 'Leave it held'; loop control release 8 > /dev/null || fail "the release by hand failed"
  nmain; nmain
  [ "$(jq -c '.held' "$ST/control.json")" = '[7]' ] || fail "an answer that leaves it held released it: $(cat "$ST/control.json") $(cat "$T/$CASE/run.out")"
  jq -e '.answeredAt != null and (.answer | startswith("Closed"))' <<<"$(mdec 8)" > /dev/null || fail "the decision of the issue released by hand was not closed: $(mdec 8)"
}

# Bug (review of #1170): two answers read in one pass: the second release was built from the record as the pass began, so
# it dropped the first issue from `order`. With #7 and #9 both answered "Release it, first in the order", both are
# released and `order` holds both (the later release first), and #8, first before, stays in it.
t_needstwo() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01) <(issue 9 2026-03-01))"; mmain 7 9
  nmain; manswer 7 'Release it, first in the order'; manswer 9 'Release it, first in the order'
  nmain
  [ "$(jq -c '[.held, .order]' "$ST/control.json")" = '[[],[9,7,8]]' ] \
    || fail "the second release in a pass dropped the first from the order: $(cat "$ST/control.json") $(cat "$T/$CASE/run.out")"
}

# Bug (review of #1170): the answer stayed "Release it, first in the order" after its step, so when the owner held #7
# again the next pass read the old answer and released it against the hold. Held again after its release, #7 stays held.
# The engine does not rewrite the owner's answer to remember this: the Board's digest would report a correction.
t_needsrehold() {
  setup "[$(issue 7 2026-01-01)]"; mmain 7
  nmain; manswer 7 'Release it, first in the order'; nmain
  [ "$(jq -c '.held' "$ST/control.json")" = '[]' ] || fail "the answer did not release #7: $(cat "$ST/control.json") $(cat "$T/$CASE/run.out")"
  loop control hold 7 > /dev/null || fail "#7 was not held again"
  nmain; nmain
  [ "$(jq -c '.held' "$ST/control.json")" = '[7]' ] || fail "an old answer released #7 against a new hold: $(cat "$ST/control.json") $(cat "$T/$CASE/run.out")"
  jq -e '.answer == "Release it, first in the order" and (.history // []) == []' <<<"$(mdec 7)" > /dev/null \
    || fail "the engine changed the owner's answer, so the digest reports a correction: $(mdec 7)"
}

# Bug (review of #1170): needsmain() read the whole test's `filed` list without the control record's `held`, so an issue
# the nightly test filed that is already in Queue (released) was put to the owner. #7 is held, #8 released: only #7 has one.
t_needsqueue() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; mmain 7 8
  loop control release 8 > /dev/null || fail "#8 was not released"
  nmain
  [ -n "$(mdec 7)" ] && [ -z "$(mdec 8)" ] || fail "the held issue has no decision, or the issue in Queue has one: $(cat "$CONVEYOR_LEDGER" 2>&1) $(cat "$T/$CASE/run.out")"
}

# Bug (review of #1170): an issue closed on GitHub stayed in `held`, the only state the pass read, so its decision stayed
# open (and a closed issue was put as a new one). #7 is closed on GitHub: no decision is put for it, and #8's, open
# before it closed, is closed with the engine's closing text, not a step (#8 stays held).
t_needsclosed() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; mmain 7 8
  echo CLOSED > "$STUB/state.7"; nmain; echo CLOSED > "$STUB/state.8"; nmain; nmain
  [ -z "$(mdec 7)" ] && jq -e '.answeredAt != null and (.answer | startswith("Closed"))' <<<"$(mdec 8)" > /dev/null \
    || fail "a closed issue has a decision, or #8's decision stays open: $(cat "$CONVEYOR_LEDGER") $(cat "$T/$CASE/run.out")"
  [ "$(jq -c '.held' "$ST/control.json")" = '[7,8]' ] || fail "the engine took a step for closed issues: $(cat "$ST/control.json")"
}

# Bug (review of #1170): the loop's job beside the cards called needsask() only, so no held issue was put to the owner.
# turnopen() (lib/run.sh) is called as the serving loop calls it, with needsask() and needsmain() recording that they ran:
# the job must run both. Bug (#1168): a turn that runs the two alone runs no auto pass (needsauto()) and no standing
# review-retry (needsretry()), so the engine never decides; both record that they ran too, needsauto() as a pass that
# did not run. A real turn is run: no direct check shows which functions the loop's turn starts.
t_needsturn() {
  setup "[$(issue 7 2026-01-01)]"
  fx_in 'needsask() { echo ask >> "$T/$CASE/jobs"; }; needsmain() { echo main >> "$T/$CASE/jobs"; }
    needsauto() { echo auto >> "$T/$CASE/jobs"; return 1; }; needsretry() { echo retry >> "$T/$CASE/jobs"; }
    serve=1 nopack= IDLE=0 atried=-1000000 asker= pusher= taker= fixer= rtried=0 ttook=0 htold= mhold= told= lim=
    turnopen; wait'
  [ "$(sort "$T/$CASE/jobs" 2>/dev/null | tr '\n' ' ')" = "ask auto main retry " ] \
    || fail "the turn's job did not run needsretry, needsask, needsmain and needsauto once each: $(cat "$T/$CASE/jobs" 2>&1) $(head -5 "$T/$CASE/run.out")"
}

# Bug (#1171): the docs said nothing of which `needs you` items become decisions for `auto decide`, nor what step it picks,
# so an owner could not tell what auto does with a blocked card or a held main-red issue. docs/foreman.md must name both
# items and the recommended step of each, as the engine's own option labels read. Text check: a doc page has no behaviour to run.
# Each label is matched in its own item's sentence: matched anywhere on the page, the two steps swapped passed.
t_needsdoc() {
  local d v l item; d=$(tr '\n' ' ' < "$SRC/../docs/foreman.md" | tr -s ' ')
  for v in 'NEEDSASK_RETRY:A card that is blocked with its work kept' 'NEEDSMAIN_RELEASE:that fails on main, and the engine holds'; do
    l=$(sed -n "s/.*\b${v%%:*}='\([^']*\)'.*/\1/p" "$SRC/lib/needsask.sh" | head -1) item=${v#*:}
    [ -n "$l" ] || fail "lib/needsask.sh has no recommended-step label to check the docs against"
    grep -qF "$item: the recommended step is \"$l\"" <<<"$d" \
      || fail "docs/foreman.md does not give the recommended step \"$l\" in the item that starts \"$item\", which auto decides"
  done
}

# naauto <on|narrow>: auto turned on in the case's state folder, with an empty ruling log of the case's unless one is
# written; AUTOLOG is its log. najob: one run of the loop's job beside the cards (needsjob()), as the serving loop runs it.
naauto() {
  export CONVEYOR_RULING_LOG=$T/$CASE/rulings.jsonl; touch "$CONVEYOR_RULING_LOG"
  loop auto "$1" > "$T/$CASE/auto.out" 2>&1 && AUTOLOG=$(jq -r .log "$ST/auto/mode.json") || fail "auto $1 failed: $(cat "$T/$CASE/auto.out")"
}
najob() { fx_in needsjob; [ "$RC" = 0 ] || fail "needsjob exited $RC: $(cat "$T/$CASE/run.out")"; }
# naretried <card>: 0 when the card was given back, as `retry` does.
naretried() { [ "$(jq -r --arg c "$1" 'select(.card == $c and .step == "blocked") | .retriedAt != null' "$ST/retried.jsonl" 2>/dev/null)" = true ]; }

# Bug (#1168): only the Foreman session ran `auto decide`, so while the owner's machine was off, or the session ran no
# turn, auto decided nothing for hours. With auto on and no Foreman, one run of the loop's job answers the new decision
# with its recommended option, logs it under "## Decisions", and retries the card at once. The Foreman's `auto decide`
# after it finds the decision decided once: one log entry, one answer in the ledger.
t_needsauto() {
  local out
  setup "[$(issue 7 2026-01-01)]"; nainit 7; naauto on
  najob
  [ "$(nadec c0-7 | jq -r .answer)" = 'Retry keeping the work' ] || fail "the engine did not answer blocked-c0-7: $(nadec c0-7) $(cat "$T/$CASE/run.out")"
  awk '/^## Decisions$/ { on = 1 } /^## Waiting for the owner$/ { on = 0 } on' "$AUTOLOG" | grep -q '^### [0-9][0-9]:[0-9][0-9] blocked-c0-7: ' \
    || fail "the engine's answer is not logged under Decisions: $(cat "$AUTOLOG")"
  naretried c0-7 || fail "the card was not retried in the same job: $(cat "$T/$CASE/run.out") $(cat "$ST/retried.jsonl" 2>&1)"
  out=$(loop auto decide 2>&1) || fail "the Foreman's auto decide failed: $out"
  [ "$(grep -c '^### .* blocked-c0-7: ' "$AUTOLOG")" = 1 ] && grep -qF 'Decided for the owner: 1.' "$AUTOLOG" \
    && [ "$(jq -s '[.[] | select(.id == "blocked-c0-7" and .answer != null)] | length' "$CONVEYOR_LEDGER")" = 1 ] \
    || fail "after the engine decided blocked-c0-7, the Foreman's auto decide ($out) decided it again: $(cat "$AUTOLOG") $(cat "$CONVEYOR_LEDGER")"
}

# Bug (#1168): the engine's pass must honour auto off. Turned on, then off, the job leaves the decision open, writes
# nothing in the ended log and retries nothing.
t_needsautooff() {
  setup "[$(issue 7 2026-01-01)]"; nainit 7; naauto on
  loop auto off > "$T/$CASE/off.out" 2>&1 || fail "auto off failed: $(cat "$T/$CASE/off.out")"
  najob
  [ "$(nadec c0-7 | jq .answeredAt)" = null ] && ! grep -q blocked-c0-7 "$AUTOLOG" && ! naretried c0-7 \
    || fail "with auto off the engine decided: $(nadec c0-7) $(cat "$AUTOLOG") $(cat "$T/$CASE/run.out")"
}

# Bug (#1168): the engine's pass on narrow must decide only a formality, as `auto decide` narrow does. The owner gave
# "Retry keeping the work" to blocked-c0-7's own question before (the ruling log); blocked-c0-8 has no such ruling. Only
# c0-7 is answered and retried; c0-8 stays open, listed as not a formality.
t_needsautonarrow() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; nainit 7 8; nask; naauto narrow
  nadec c0-7 | jq -c '{id: "x-1", source: "ask", question, answer: "Retry keeping the work (Recommended)", pick: "recommended"}' > "$CONVEYOR_RULING_LOG"
  najob
  [ "$(nadec c0-7 | jq -r .answer)" = 'Retry keeping the work' ] && naretried c0-7 \
    || fail "narrow did not decide the formality blocked-c0-7: $(nadec c0-7) $(cat "$T/$CASE/run.out")"
  [ "$(nadec c0-8 | jq .answeredAt)" = null ] && ! naretried c0-8 && grep -q '^- blocked-c0-8: .*(narrow: not a formality' "$AUTOLOG" \
    || fail "narrow decided blocked-c0-8, which the owner never answered: $(nadec c0-8) $(cat "$AUTOLOG")"
}

# Bug (#1168): the engine's pass must leave what the pack reserves for the owner. The card's reason names "delete" (the
# default auto.reserved), so its decision stays open and is listed under "Waiting for the owner". A second job, with no
# new decision, runs no pass (the log is the same file, not written again) and lists it no second time.
t_needsautores() {
  local ino
  setup "[$(issue 7 2026-01-01)]"; nainit 7
  jq -c '.reason |= sub("it failed"; "it would delete the old table")' "$ST/cards.jsonl" > "$T/$CASE/cards.new" && mv "$T/$CASE/cards.new" "$ST/cards.jsonl" || fail "the card's reason"
  naauto on; najob
  [ "$(nadec c0-7 | jq .answeredAt)" = null ] && ! naretried c0-7 \
    && awk '/^## Waiting for the owner$/ { on = 1; next } on' "$AUTOLOG" | grep -q '^- blocked-c0-7: .*(reserved: delete)$' \
    || fail "the reserved decision was answered, or is not waiting for the owner: $(nadec c0-7) $(cat "$AUTOLOG")"
  ino=$(ls -i "$AUTOLOG"); najob
  [ "$(ls -i "$AUTOLOG")" = "$ino" ] && [ "$(grep -c '^- blocked-c0-7: ' "$AUTOLOG")" = 1 ] \
    || fail "a job with no new decision ran the auto pass again: $(cat "$AUTOLOG") $(cat "$T/$CASE/run.out")"
}

# Bug (O212, review): needsask() cut the block reason at 300 characters, so "delete" (the default auto.reserved) past
# the cut never reached the question auto decide reads, and the engine's pass answered it and retried the card. The
# question names the word after the cut, and the decision waits for the owner.
t_needsautolong() {
  local pad
  setup "[$(issue 7 2026-01-01)]"; nainit 7
  pad=$(printf 'the build stopped. %.0s' {1..17})
  jq -c --arg p "$pad" '.reason |= "\($p)it would delete the old table"' "$ST/cards.jsonl" > "$T/$CASE/cards.new" && mv "$T/$CASE/cards.new" "$ST/cards.jsonl" || fail "the card's reason"
  naauto on; najob
  [ "$(nadec c0-7 | jq .answeredAt)" = null ] && ! naretried c0-7 && nadec c0-7 | jq -e '.question | contains("(it names: delete)")' > /dev/null \
    || fail "for a block reason of ${#pad} characters before \"it would delete the old table\", the decision was answered, or its question does not name delete: $(nadec c0-7)"
}

# Bug (E14, review): the cut named past it only the words of auto.reserved, so an item of the owner's profile (its
# "Never decide; ask" section) past the cut never reached the question auto decide reads: the engine's pass answered it
# "Retry keeping the work" and retried the card. The question names the item, and the decision waits for the owner.
t_needsautoprofile() {
  local pad
  setup "[$(issue 7 2026-01-01)]"; nainit 7
  mkdir -p "$ST/foreman" && printf '%s\n' '## Never decide; ask' '- `.claude/scripts/__tests__/`' > "$ST/foreman/owner-way.md" || fail "the profile"
  pad=$(printf 'the build stopped. %.0s' {1..17})
  jq -c --arg p "$pad" '.reason |= "\($p)it moves .claude/scripts/__tests__/ away"' "$ST/cards.jsonl" > "$T/$CASE/cards.new" && mv "$T/$CASE/cards.new" "$ST/cards.jsonl" || fail "the card's reason"
  naauto on; najob
  [ "$(nadec c0-7 | jq .answeredAt)" = null ] && ! naretried c0-7 && nadec c0-7 | jq -e '.question | contains("(it names: .claude/scripts/__tests__/)")' > /dev/null \
    || fail "for a block reason of ${#pad} characters before \"it moves .claude/scripts/__tests__/ away\", which the profile holds, the decision was answered, or its question does not name the item: $(nadec c0-7)"
}

# Bug (follow-up of #1571): the question was cut once, when it was put, so one put before the host got the owner's
# profile named no profile item past the cut; after `auto on` sent the profile there (`auto rulings`, the
# {source: "profile"} row of auto/rulings.jsonl), the engine's pass answered it "Retry keeping the work" and retried the
# card. auto decide reads the whole block reason the engine kept, and the decision waits for the owner. The kept text is
# removed after the question is put, as an engine before this fix kept none (review E1). auto decide, run before the
# loop's next pass keeps it again for the decision already in the ledger, leaves the cut question for the owner.
t_needsautolate() {
  local pad
  setup "[$(issue 7 2026-01-01)]"; nainit 7
  pad=$(printf 'the build stopped. %.0s' {1..17})
  jq -c --arg p "$pad" '.reason |= "\($p)it moves .claude/scripts/__tests__/ away"' "$ST/cards.jsonl" > "$T/$CASE/cards.new" && mv "$T/$CASE/cards.new" "$ST/cards.jsonl" || fail "the card's reason"
  nask
  nadec c0-7 | jq -e '.answeredAt == null and (.question | contains("__tests__") | not)' > /dev/null || fail "the question was not put, or it names the item before the profile came: $(nadec c0-7)"
  grep -qF '.claude/scripts/__tests__/ away' "$ST/auto/asked/blocked-c0-7.txt" 2>/dev/null \
    || fail "the question was put, but the whole block reason was not kept in auto/asked/blocked-c0-7.txt: $(cat "$ST/auto/asked/blocked-c0-7.txt" 2>&1)"
  rm -f "$ST/auto/asked/blocked-c0-7.txt"
  printf '%s\n' '{"source":"profile","held":[".claude/scripts/__tests__/"]}' > "$ST/auto/rulings.jsonl" || fail "the profile sent to the host"
  naauto on
  loop auto decide > "$T/$CASE/decide.out" 2>&1 || fail "auto decide failed: $(cat "$T/$CASE/decide.out")"
  [ "$(nadec c0-7 | jq .answeredAt)" = null ] && grep -qF -- '- blocked-c0-7: ' "$AUTOLOG" \
    || fail "auto decide, run before the loop kept the whole block reason again, answered the cut question or did not leave it for the owner: $(nadec c0-7) $(cat "$T/$CASE/decide.out")"
  najob
  grep -qF '.claude/scripts/__tests__/ away' "$ST/auto/asked/blocked-c0-7.txt" 2>/dev/null \
    || fail "the loop's pass did not keep the whole block reason again for the decision already in the ledger"
  # Review E5: the job ran no decide pass on a decision already waiting, so this pass is the one that reads the kept text.
  loop auto decide > "$T/$CASE/decide.out" 2>&1 || fail "auto decide failed: $(cat "$T/$CASE/decide.out")"
  [ "$(nadec c0-7 | jq .answeredAt)" = null ] && ! naretried c0-7 \
    || fail "for a block reason of ${#pad} characters before \"it moves .claude/scripts/__tests__/ away\", put before the profile that holds it came, the decision was answered or the card retried: $(nadec c0-7) $(cat "$T/$CASE/run.out")"
}

# Bug (follow-up of #1571, review E2): the same for a held issue of the nightly whole test. Its list of failing tests was
# cut once, when the question was put, and kept by no file in an engine before this fix, so a profile item that came
# later and is named past the cut did not hold the decision: the engine's pass released the issue. The kept list is
# removed after the question is put, as such an engine kept none. auto decide, run
# before the loop's next pass keeps it again, leaves it for the owner; the decision waits, and #7 stays held.
t_needsmainlate() {
  setup "[$(issue 7 2026-01-01)]"; mmain 7
  jq -cn '{sha: "abc", filed: [{issue: 7, cases: ([range(20) | "x.test.sh: case pad\(.)"] + [".claude/scripts/__tests__/board.test.js: board"])}]}' > "$ST/maintest.json" || fail "the whole test's record"
  nmain
  mdec 7 | jq -e '.answeredAt == null and (.question | contains("__tests__") | not)' > /dev/null || fail "the question was not put, or it names the item before the profile came: $(mdec 7)"
  grep -qF '.claude/scripts/__tests__/board.test.js' "$ST/auto/asked/mainred-7.txt" 2>/dev/null \
    || fail "the question was put, but the whole list of tests was not kept in auto/asked/mainred-7.txt: $(cat "$ST/auto/asked/mainred-7.txt" 2>&1)"
  rm -f "$ST/auto/asked/mainred-7.txt"
  printf '%s\n' '{"source":"profile","held":[".claude/scripts/__tests__/"]}' > "$ST/auto/rulings.jsonl" || fail "the profile sent to the host"
  naauto on
  loop auto decide > "$T/$CASE/decide.out" 2>&1 || fail "auto decide failed: $(cat "$T/$CASE/decide.out")"
  [ "$(mdec 7 | jq .answeredAt)" = null ] && grep -qF -- '- mainred-7: ' "$AUTOLOG" \
    || fail "auto decide, run before the loop kept the whole list of tests again, answered the cut question or did not leave it for the owner: $(mdec 7) $(cat "$T/$CASE/decide.out")"
  najob
  grep -qF '.claude/scripts/__tests__/board.test.js' "$ST/auto/asked/mainred-7.txt" 2>/dev/null \
    || fail "the loop's pass did not keep the whole list of tests again for the decision already in the ledger"
  # Review E5: the job ran no decide pass on a decision already waiting, so this pass is the one that reads the kept text.
  loop auto decide > "$T/$CASE/decide.out" 2>&1 || fail "auto decide failed: $(cat "$T/$CASE/decide.out")"
  [ "$(mdec 7 | jq .answeredAt)" = null ] && [ "$(jq -c .held "$ST/control.json")" = '[7]' ] \
    || fail "for a list of 21 failing tests whose last, .claude/scripts/__tests__/board.test.js, is past the cut, put before the profile that holds it came, the decision was answered or #7 released: $(mdec 7) $(cat "$ST/control.json") $(cat "$T/$CASE/run.out")"
}

# Bug (review E3): askkeep() wrote the kept text in place, so the file was empty from the open until the write, and an
# `auto decide` that read it then saw no text and answered the cut question. What must stay true: auto decide (the other
# reader) reads the whole text or none. The loop's pass (needsask, the writer) keeps the text again for the decision in
# the ledger; its printf is paused after it has written the first 300 characters, before the reserved path, and auto
# decide runs there: the decision must still wait. The pause writes part of the text, not none: a file written in place
# and still empty is taken as missing, and auto decide holds for that too, so only a part shows an in-place write.
t_needsautokeep() {
  local pad
  setup "[$(issue 7 2026-01-01)]"; nainit 7
  pad=$(printf 'the build stopped. %.0s' {1..17})
  jq -c --arg p "$pad" '.reason |= "\($p)it moves .claude/scripts/__tests__/ away"' "$ST/cards.jsonl" > "$T/$CASE/cards.new" && mv "$T/$CASE/cards.new" "$ST/cards.jsonl" || fail "the card's reason"
  nask
  printf '%s\n' '{"source":"profile","held":[".claude/scripts/__tests__/"]}' > "$ST/auto/rulings.jsonl" || fail "the profile sent to the host"
  naauto on
  # shellcheck disable=SC2016 # run by fx_in's eval, in the engine's shell
  fx_in 'printf() { if [ "$1" = %s ] && [[ ${2-} == *"__tests__/ away" ]] && [ ! -e "$T/$CASE/paused" ]; then
      : > "$T/$CASE/paused"; builtin printf %s "${2:0:300}"; loop auto decide > "$T/$CASE/decide.out" 2>&1
      builtin printf %s "${2:300}"; return; fi; builtin printf "$@"; }; needsask'
  [ "$RC" = 0 ] && [ -e "$T/$CASE/paused" ] || fail "needsask exited $RC, or it did not keep the block reason again: $(cat "$T/$CASE/run.out")"
  [ "$(nadec c0-7 | jq .answeredAt)" = null ] && ! naretried c0-7 \
    || fail "auto decide, run while needsask kept the block reason again, answered the decision whose reason names .claude/scripts/__tests__/ past the cut: $(nadec c0-7) $(cat "$T/$CASE/decide.out")"
  grep -qF '.claude/scripts/__tests__/ away' "$ST/auto/asked/blocked-c0-7.txt" || fail "the whole block reason is not kept after the pass"
}

# Bug (review E4): a question of exactly 300 characters is not cut, so the engine kept no text for it, and auto decide,
# which cannot tell from 300 characters whether a question was cut, left it for the owner on every pass. The engine keeps
# its text too, and auto decide answers it when nothing in it is reserved.
t_needsauto300() {
  local r
  setup "[$(issue 7 2026-01-01)]"; nainit 7
  r=$(printf 'the build stopped. %.0s' {1..16}); r=${r:0:300}
  jq -c --arg r "$r" '.reason = $r' "$ST/cards.jsonl" > "$T/$CASE/cards.new" && mv "$T/$CASE/cards.new" "$ST/cards.jsonl" || fail "the card's reason"
  naauto on; najob
  nadec c0-7 | jq -e '.answer == "Retry keeping the work"' > /dev/null && naretried c0-7 \
    || fail "for a block reason of exactly 300 characters that names nothing reserved, the decision was not answered with its recommended option, or the card not retried: $(nadec c0-7) $(cat "$AUTOLOG")"
}

# nareview: the case's blocked card (nainit) blocked by its review instead, as card.sh words that block; auto on, with
# the standing kind review-retry on in the pack.
nareview() {
  jq -c 'if .step == "blocked" then .reason = "the fix for [P1] a.txt:1 drops the line did not hold after 3 rounds" else . end' "$ST/cards.jsonl" > "$T/$CASE/cards.new" \
    && mv "$T/$CASE/cards.new" "$ST/cards.jsonl" || fail "the card's reason"
  tune '.auto.standing = ["review-retry"]'; naauto on
}

# Bug (#1168, review): the engine left the standing review-retry to the Foreman's watcher, so while the watcher was
# down, a card blocked by its review was put to the owner as a decision, not given back as the owner said ahead of
# time. With auto on and review-retry on, one job gives the card back, logs the act as `auto act` does (the ruling
# log, source "standing", kind review-retry, naming #7), and puts no decision to the owner.
t_needsautoretry() {
  setup "[$(issue 7 2026-01-01)]"; nainit 7; nareview
  najob
  naretried c0-7 || fail "the card blocked by its review was not given back: $(cat "$T/$CASE/run.out") $(cat "$ST/retried.jsonl" 2>&1)"
  [ "$(jq -sc '[.[] | select(.source == "standing" and .kind == "review-retry" and (.answer | contains("#7")))] | length' "$CONVEYOR_RULING_LOG")" = 1 ] \
    || fail "the review-retry of #7 is not logged once in the ruling log: $(cat "$CONVEYOR_RULING_LOG")"
  [ -z "$(nadec c0-7)" ] || fail "the card given back by review-retry was put to the owner too: $(nadec c0-7)"
}

# Bug (O212): needsretry() gave back every card blocked by its review, with no look at auto.reserved: a finding tagged
# [security] (a word of the pack's default auto.reserved) put "security" in the block reason, and the card was retried
# though anything auto.reserved holds waits for the owner. The card stays blocked, put to the owner, and is not logged.
# The same holds for an item of the owner's profile (E14, review: its "Never decide; ask" section) in the reason.
nrheld() { # <the finding the review blocked on> [a "- " line of the profile's Never decide; ask]
  setup "[$(issue 7 2026-01-01)]"; nainit 7; nareview
  [ -z "${2:-}" ] || { mkdir -p "$ST/foreman" && printf '%s\n' '## Never decide; ask' "$2" > "$ST/foreman/owner-way.md"; } || fail "the profile"
  jq -c --arg f "$1" 'if .step == "blocked" then .reason = "the fix for \($f) did not hold after 2 rounds" else . end' "$ST/cards.jsonl" > "$T/$CASE/cards.new" \
    && mv "$T/$CASE/cards.new" "$ST/cards.jsonl" || fail "the card's reason"
  najob
  ! naretried c0-7 && [ -n "$(nadec c0-7)" ] && ! grep -q 'review-retry' "$CONVEYOR_RULING_LOG" 2>/dev/null \
    || fail "the card blocked for the finding \"$1\" (profile item: ${2:-none}) was given back by review-retry, or not put to the owner: $(cat "$T/$CASE/run.out") $(cat "$ST/retried.jsonl" 2>&1)"
}
t_needsretryreserved() { nrheld '[P1][security] a.txt:1 drops the line'; }
t_needsretryprofile() { nrheld '[P1] a.txt:1 drops the billing table' '- billing table'; }

# Bug (#1168, review): a review-retry that fails (here #7 has a card that landed, so retry refuses) must be tried once,
# not again in each job every IDLE seconds: the card stays blocked for the owner. The second job tries no retry.
t_needsretryonce() {
  setup "[$(issue 7 2026-01-01)]"; nainit 7; landed 7 | jq -c '.card = "c1-7"' >> "$ST/cards.jsonl"; nareview
  najob
  grep -q 'the review-retry of #7 (card c0-7) failed' "$T/$CASE/run.out" || fail "the failed review-retry of #7 was not tried and named: $(cat "$T/$CASE/run.out")"
  najob
  ! grep -q 'review-retry of #7' "$T/$CASE/run.out" || fail "a second job tried the failed review-retry of #7 again: $(cat "$T/$CASE/run.out")"
}

# naback <id>: the ledger's rows of the decision get an asking time long before the case: decision.sh's times are whole
# seconds, and a decision asked again in the second of its first asking keeps that time, so a case could not tell them apart.
naback() { jq -c --arg id "$1" 'if .id == $id then .askedAt = "2026-01-01T00:00:00Z" else . end' "$CONVEYOR_LEDGER" > "$T/$CASE/led.new" \
  && mv "$T/$CASE/led.new" "$CONVEYOR_LEDGER" || fail "the asking time of $1 was not set back"; }

# Bug it catches (R280): needsauto() took a decision its log listed by id as seen, so x-1, held for the owner (it names
# "delete", the default auto.reserved), answered, then asked again under the same id with nothing reserved, ran no auto
# pass, and stayed open until the Foreman ran one. The first pass is the Foreman's `auto decide`, not the engine's: the
# engine kept the asking time only of the ones its own look found listed, so it took the second asking as the seen one.
t_needsautoreask() {
  local d=$SRC/../.claude/scripts/decision.sh out
  setup '[]'; export CONVEYOR_LEDGER=$T/$CASE/decisions.jsonl; mkdir -p "$ST"; naauto on
  bash "$d" add x-1 'Delete the old table?' yes 'a test' > /dev/null && naback x-1 || fail "x-1 was not asked"
  out=$(loop auto decide 2>&1) && grep -q '^- x-1: .*(reserved: delete)$' "$AUTOLOG" \
    || fail "the Foreman's auto decide did not hold x-1 ($out): $(cat "$AUTOLOG")"
  bash "$d" answer x-1 no > /dev/null && bash "$d" add x-1 'Keep the new table?' yes 'a test' --reask 'asked again' > /dev/null || fail "x-1 was not asked again"
  fx_in needsauto
  [ "$RC" = 0 ] && [ "$(jq -cs 'map(select(.id == "x-1")) | last | .answer' "$CONVEYOR_LEDGER")" = '"yes"' ] \
    || fail "x-1, asked again under the id the log lists, was not decided by the auto pass ($RC): $(cat "$CONVEYOR_LEDGER") $(cat "$T/$CASE/run.out")"
  # Bug it catches: the pass that answered x-1 left its old "- x-1:" line under "Waiting for the owner", and the summary
  # counted the answered decision as still waiting.
  ! grep -q '^- x-1: ' "$AUTOLOG" && grep -q 'Waiting for the owner: 0\.' "$AUTOLOG" \
    || fail "x-1, answered by the auto pass, still waits for the owner in the log: $(cat "$AUTOLOG")"
}

# Bug it catches (R280 fix): <log>.seen kept a held decision's id and asking time, and decision.sh stamps whole seconds,
# so x-1, held for the owner, then asked again by the picker under its id in the same second (the hook's re-ask) with
# nothing reserved, matched the line of the first asking: needsauto() ran no pass, and x-1 stayed open.
t_needsautosame() {
  setup '[]'; export CONVEYOR_LEDGER=$T/$CASE/decisions.jsonl; mkdir -p "$ST"; naauto on
  bash "$SRC/../.claude/scripts/decision.sh" add x-1 'Delete the old table?' yes AskUserQuestion > /dev/null || fail "x-1 was not asked"
  loop auto decide > /dev/null 2>&1 && grep -q '^- x-1: .*(reserved: delete)$' "$AUTOLOG" || fail "auto decide did not hold x-1: $(cat "$AUTOLOG")"
  # The re-ask decision.sh appends, its asking time the first one's (the same second).
  jq -c 'select(.id == "x-1") | .question = "Keep the new table?" | .source = "AskUserQuestion; re-ask: picker repeats x-2"' "$CONVEYOR_LEDGER" > "$T/$CASE/reask" \
    && cat "$T/$CASE/reask" >> "$CONVEYOR_LEDGER" || fail "x-1 was not asked again"
  fx_in needsauto
  [ "$RC" = 0 ] && [ "$(jq -cs 'map(select(.id == "x-1")) | last | .answer' "$CONVEYOR_LEDGER")" = '"yes"' ] \
    || fail "x-1, held, then asked again in the same second with nothing reserved, was not decided by the auto pass ($RC): $(cat "$CONVEYOR_LEDGER") $(cat "$AUTOLOG.seen") $(cat "$T/$CASE/run.out")"
}

# Bug it catches (R280 fix): <log>.seen kept a held decision's whole row, and decision.sh's reopen writes the row again
# with an asking time of whole seconds, so x-1, held for the owner, then answered and reopened in the second it was
# asked, had the row of its first asking: needsauto() ran no pass for the reopened decision.
t_needsautoreopen() {
  local d=$SRC/../.claude/scripts/decision.sh
  setup '[]'; export CONVEYOR_LEDGER=$T/$CASE/decisions.jsonl; mkdir -p "$ST"; naauto on
  bash "$d" add x-1 'Delete the old table?' yes 'a test' > /dev/null && naback x-1 || fail "x-1 was not asked"
  loop auto decide > /dev/null 2>&1 && grep -q '^- x-1: .*(reserved: delete)$' "$AUTOLOG" || fail "auto decide did not hold x-1: $(cat "$AUTOLOG")"
  # naback again: the reopen in the asking's own second, so its row is the first asking's row.
  bash "$d" answer x-1 no > /dev/null && bash "$d" reopen x-1 > /dev/null && naback x-1 || fail "x-1 was not answered and reopened"
  fx_in needsauto
  [ "$RC" = 0 ] && grep -qx 'x-1 3' "$AUTOLOG.seen" \
    || fail "x-1, held, then answered and reopened in the second it was asked, got no auto pass ($RC): $(cat "$CONVEYOR_LEDGER") $(cat "$AUTOLOG.seen" 2>&1) $(cat "$T/$CASE/run.out")"
}

# narecard <card> <issue> <finding> [<reason>]: the card the last retry of <issue> started, blocked by its review on
# <finding> (the fix did not hold after one round), or for <reason> when given, its work kept as the first card's.
narecard() {
  mkdir -p "$ST/kept/$1" && cp "$ST/kept/c0-$2/c0-$2.patch" "$ST/kept/$1/$1.patch" || fail "the kept patch of $1"
  landed "$2" | jq -c --arg c "$1" --arg f "$3" --arg r "${4:-}" '.card = $c | (.step = "picked"), (.step = "blocked" | .result = "blocked"
    | .reason = (if $r == "" then "the fix for \($f) did not hold after 1 round" else $r end) | .kept = "kept/\($c)")' >> "$ST/cards.jsonl"
}
# Bug (#1589): review-retry remembered the card, not the issue, and each retry is a new card, so an issue whose fix did
# not hold came back on a narrower finding each time and was given back again with no end. Its first review block is
# given back once, marked as review-retry's in retriedBy, not retriedWhy (the Board shows retriedWhy after the reason,
# which then hid the block's finding). The card that retry started, blocked by its review again, is not: it is open in
# Needs you with both block reasons and its kept patch, and the auto pass of the same job (auto on) leaves it to the
# owner, with no retry. That block names a new P0 before the P1 whose fix did not hold (card.sh), so a cut of its
# reason dropped the P1: both reasons are asked whole. A review-retry that comes late (the watcher's, from a snapshot
# made before the engine's retry) is refused by `retry` itself and gives the second card back to no one. The owner's
# answer to that decision is the owner's own retry, which resets the count: the next card's review block is given back.
t_needsretryissue() {
  local d out p0; p0="[P0] b.txt:2 deletes the file. Proof: $(printf 'step %s, ' {1..30})end"
  setup "[$(issue 7 2026-01-01)]"; nainit 7; nareview
  najob
  naretried c0-7 && [ "$(jq -c 'select(.card == "c0-7" and .step == "blocked") | [.retriedBy, .retriedWhy]' "$ST/retried.jsonl")" = '["review-retry",null]' ] \
    || fail "the first review block of #7 was not given back as review-retry's: $(cat "$T/$CASE/run.out") $(cat "$ST/retried.jsonl" 2>&1)"
  narecard c1-7 7 "$p0; [P1] a.txt:1 drops the last line"
  najob
  ! naretried c1-7 || fail "review-retry gave #7 back a second time: $(cat "$T/$CASE/run.out")"
  [ "$(jq -sc '[.[] | select(.kind == "review-retry")] | length' "$CONVEYOR_RULING_LOG")" = 1 ] \
    || fail "review-retry was logged more than once for #7: $(cat "$CONVEYOR_RULING_LOG")"
  d=$(nadec c1-7)
  jq -e --arg p0 "$p0" '.answeredAt == null and (.question | contains("this block: the fix for \($p0); [P1] a.txt:1 drops the last line did not hold after 1 round; the block review-retry gave back: the fix for [P1] a.txt:1 drops the line did not hold after 3 rounds")
    and contains("/kept/c1-7/c1-7.patch"))' <<<"$d" >/dev/null \
    || fail "the second block is not open in Needs you with both whole block reasons and its kept patch: $d $(cat "$T/$CASE/run.out")"
  grep -qF 'end; [P1] a.txt:1 drops the last line did not hold after 1 round' "$ST/auto/asked/blocked-c1-7.txt" \
    || fail "the whole text of the second block's question is not kept: $(cat "$ST/auto/asked/blocked-c1-7.txt" 2>&1)"
  # The watcher's review-retry of #7 as the host runs it (CONVEYOR_REVIEWRETRY), chosen from a snapshot made before the
  # engine gave #7 back: it reaches the host only now, with c1-7 blocked.
  out=$(CONVEYOR_REVIEWRETRY=1 loop retry 7 2>&1) && fail "a late review-retry of #7 was not refused: $out"
  grep -qF 'review-retry already gave issue #7 back once (its card c0-7' <<<"$out" && ! naretried c1-7 \
    || fail "a late review-retry of #7 gave c1-7 back, or did not say why it was refused: $out"
  grep -qF -- '- blocked-c1-7: ' "$AUTOLOG" && grep -qF 'review-retry already gave this issue back once' "$AUTOLOG" \
    || fail "the auto pass did not leave the second block to the owner: $(cat "$AUTOLOG")"
  nanswer c1-7 'Retry keeping the work'; najob
  [ "$(jq -r 'select(.card == "c1-7" and .step == "blocked") | .retriedBy' "$ST/retried.jsonl" 2>/dev/null)" = owner ] \
    || fail "the owner's answer to blocked-c1-7 did not retry #7 as the owner's own: $(cat "$T/$CASE/run.out" "$ST/retried.jsonl")"
  narecard c2-7 7 '[P1] a.txt:1 drops the first line'
  najob
  naretried c2-7 || fail "after the owner's answer, the next review block of #7 was not given back: $(cat "$T/$CASE/run.out")"
}

# Bug (#1589, review): a retry the engine ran itself counted as the owner's own, which resets review-retry's count of an
# issue. With auto on, #7's first review block is given back by review-retry; its next card is blocked for another
# reason, which the auto pass answers with the recommended retry (needsask() takes it, not as the owner's: retriedBy
# decision); the card after that is blocked by its review again. It is not given back by review-retry: with auto on,
# the engine's retry of it is review-land's (#1612), which lands it.
t_needsretryauto() {
  setup "[$(issue 7 2026-01-01)]"; nainit 7; nareview
  najob
  naretried c0-7 || fail "the first review block of #7 was not given back: $(cat "$T/$CASE/run.out")"
  narecard c1-7 7 '' 'review: review 2 is the last review, and it found [P2] a.txt:1'
  najob
  [ "$(jq -r 'select(.card == "c1-7" and .step == "blocked") | .retriedBy' "$ST/retried.jsonl" 2>/dev/null)" = decision ] \
    || fail "the auto pass's answer did not retry c1-7 as a decision's, not the owner's: $(cat "$T/$CASE/run.out" "$ST/retried.jsonl")"
  narecard c2-7 7 '[P1] a.txt:1 drops the first line'
  najob
  [ "$(jq -r 'select(.card == "c2-7" and .step == "blocked") | .retriedBy' "$ST/retried.jsonl" 2>/dev/null)" = review-land ] \
    || fail "after the auto pass's retry, the second review block of #7 was given back by review-retry, or not by review-land: $(cat "$T/$CASE/run.out" "$ST/retried.jsonl")"
}
