#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the standing kinds of routine yes (the pack's auto.standing, lib/standing.sh): the Rules tab's switch
# (`conveyor.sh auto standing`), the Foreman's log of an act (`auto act`), and the follow-up the engine itself does not
# hold under review-followup (followups(), lib/followups.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a kind turned on in the Rules tab is not in the pack, or not in what the Foreman is told (auto standing); an act
# under a kind that is on is not logged in the ruling log with its kind and source "standing", or gives the owner no
# line; an act under a kind that is off is logged, so the Foreman takes a step the owner never said yes to.
t_standing() {
  local out id; setup '[]'; export CONVEYOR_RULING_LOG=$T/$CASE/rulings.jsonl
  out=$(cd "$R" && loop auto standing) && [ -z "$out" ] || fail "auto standing with no kind on: $out"
  out=$(cd "$R" && loop auto standing fixed-block on && loop auto standing asked-fix on && loop auto standing asked-fix on) || fail "standing on failed: $out"
  [ "$(jq -c .auto.standing "$R/.conveyor/project.json")" = '["asked-fix","fixed-block"]' ] || fail "the pack's kinds: $(jq -c .auto "$R/.conveyor/project.json")"
  # The Rules tab reads the kinds from the snapshot, and the pack's push.check (#395, Test before a push): one it is
  # not given shows the owner the wrong switch.
  tune '.push.check = false'
  [ "$(cd "$R" && loop snapshot | jq -c '[.standing, .pushCheck]')" = '[["asked-fix","fixed-block"],false]' ] || fail "the snapshot's kinds and push.check: $(cd "$R" && loop snapshot | jq -c '[.standing, .pushCheck]')"
  out=$(cd "$R" && loop auto standing)
  grep -qF -- '- asked-fix: ' <<<"$out" && grep -qF -- '- fixed-block: ' <<<"$out" && ! grep -qF -- '- release-check: ' <<<"$out" \
    && grep -qF -- '- Still ask the owner, whatever the kind: ' <<<"$out" || fail "auto standing does not list the kinds on, with their limits: $out"
  # auto rules is this machine's auto mode only: the kinds of this checkout's pack in it would overrule those of the
  # host's pack, which the Foreman's start asks for (foreman.sh), in the setup where the belt runs on another host.
  out=$(cd "$R" && loop auto rules) && [ -z "$out" ] || fail "auto rules with auto off names this checkout's kinds: $out"
  out=$(cd "$R" && loop auto act asked-fix 'filed #12 as the owner asked, and released it') || fail "act failed: $out"
  id=$(jq -r 'select(.source == "standing" and .kind == "asked-fix" and .answer == "filed #12 as the owner asked, and released it") | .id' "$CONVEYOR_RULING_LOG")
  [[ $id == *-s-* ]] && [ "$out" = "Done without asking (asked-fix): filed #12 as the owner asked, and released it; logged as $id." ] \
    || fail "the act's log row or its line for the owner: $out; $(cat "$CONVEYOR_RULING_LOG")"
  out=$(cd "$R" && loop auto act release-check 'filed a fix card' 2>&1) && fail "an act under a kind that is off passed: $out"
  out=$(cd "$R" && loop auto standing asked-fix off && loop auto act asked-fix 'filed #13' 2>&1) && fail "an act under a kind turned off passed: $out"
  [ "$(wc -l < "$CONVEYOR_RULING_LOG")" = 1 ] && [ "$(jq -c .auto.standing "$R/.conveyor/project.json")" = '["fixed-block"]' ] \
    || fail "a kind that is off logged an act, or was not turned off: $(cat "$CONVEYOR_RULING_LOG") $(jq -c .auto "$R/.conveyor/project.json")"
}

# Bug (#758): the Foreman filed a red release run's fix cards with no line the engine reads, so nothing knew they were
# that run's fixes and release-prep never started again once they landed (relfixes(), lib/fulltest.sh).
t_standingrelfix() {
  local out; setup '[]'
  tune '.auto.standing = ["release-check"]'
  out=$(cd "$R" && loop auto standing) || fail "auto standing failed: $out"
  grep -F -- '- release-check: ' <<<"$out" | grep -qF 'with the line `Release fix: <version>` in its body' \
    || fail "release-check does not tell the Foreman to write the Release fix line in each fix card: $out"
}

# A card's worktree beside main, its change to the pipeline file a.txt staged, and its NO-GO review with three findings
# on a.txt: one names only a.txt, one names lib/b.sh too (another pipeline file, not in the change), and one names only
# a.txt but holds "security", a word of the default auto.reserved. followups()
# files them, as a landing card does; the pack's kinds are <auto.standing json>.
stfu() { # <auto.standing json>
  local w=$T/$CASE/wt
  setup "[$(issue 7 2026-01-01 P1)]"; tune --argjson k "$1" '.pipelineFiles = ["a.txt", "lib/"] | .auto.standing = $k'
  export CONVEYOR_RULING_LOG=$T/$CASE/rulings.jsonl
  git -C "$R" worktree add -q --detach "$w" && echo two >> "$w/a.txt" && git -C "$w" add a.txt || fail "the card's worktree"
  printf '%s\n' '[P1] a.txt:2 the new line is wrong' '[P1] a.txt:2 does not match lib/b.sh:3' '[P1] a.txt:2 Fix the Security check' \
    'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$w.review"
  out=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && followups c1-7 "$(issue 7 2026-01-01 P1)" "$w.review" ) \
    && [ "$out" = '[100101,100102,100103]' ] || fail "the three follow-ups were not filed: $out"
}
# Bugs: with review-followup on, a follow-up that only corrects its parent card's change waits held for the owner's
# yes, or is not held but not logged; one that names another file of the pipeline, or holds a word of auto.reserved,
# is not held.
t_standingfu() {
  stfu '["review-followup"]'
  [ "$(jq -c .held "$ST/control.json")" = '[100102,100103]' ] || fail "held with the kind on: $(jq -c .held "$ST/control.json"), not #100102 and #100103"
  [ "$(jq -r 'select(.source == "standing" and .kind == "review-followup") | .answer | test("^#100101, a follow-up of #7 \\(card c1-7\\)")' "$CONVEYOR_RULING_LOG")" = true ] \
    || fail "the follow-up not held was not logged once: $(cat "$CONVEYOR_RULING_LOG" 2>&1)"
}
# Bug: with the kind off (as setup writes the pack), a follow-up on a pipeline file goes unheld with no one asked.
t_standingfuoff() {
  stfu '[]'
  [ "$(jq -c .held "$ST/control.json")" = '[100101,100102,100103]' ] && [ ! -s "$CONVEYOR_RULING_LOG" ] \
    || fail "with the kind off: held $(jq -c .held "$ST/control.json"); log $(cat "$CONVEYOR_RULING_LOG" 2>&1)"
}
