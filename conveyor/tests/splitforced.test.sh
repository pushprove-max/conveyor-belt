#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the forced check of the rule Split large issues (splitforce(), splitcheck(), lib/slices.sh). An issue with
# SPLIT_TRIES blocked cards goes to the judge again, whatever its hash line and its size say, once for each text of the
# issue, and not when its last kept patch waits only for the owner's yes or was given back by review-land. What must
# stay true: the judge is asked at most once for a text (a card after the forced one asks none), and a card that takes
# up a kept patch that only waits for the owner's yes is not stopped by a split.
# The fixtures (slices, big, SPLIT2, judged) are those of slices.test.sh: the runner sources every case file into one shell.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue #7 (three Done-when items, under split.doneWhen 9), the rule On, the judge answering <answer>; card c1-7 has
# checked it (its split line holds the issue's text, verdict under), and the judge has not been asked.
forcedissue() { # <answer>
  slices on "$1" "[$(big 7)]"; tune '.split.doneWhen = 9'
  fx_in 'splitcheck c1-7 7'
  [ "$RC" = 0 ] && [ "$(st 'select(.step == "split") | .split.verdict')" = under ] && [ "$(judged)" = 0 ] \
    || fail "card c1-7's check of #7 was not under the limits with no judge call (exit $RC): $(cat "$T/$CASE/run.out")"
}
# <card> of #7 blocked, given back by <by> (the owner when empty), with <reason>; with a kept patch and a review that gave
# a verdict and said whether the change is visible when a third word is given.
blocked7() { # <card> <reason> [<kept: 1 or ''> [<by>]]
  mkdir -p "$ST/kept/$1"
  if [ -n "${3:-}" ]; then
    echo 'a patch' > "$ST/kept/$1/$1.patch"
    printf 'The change is fine.\nUSER-VISIBLE: yes: a button\nVERDICT: GO\n' > "$ST/kept/$1/$1.review"
  fi
  jq -cn --arg c "$1" --arg r "$2" --arg k "kept/$1" --arg by "${4:-}" '{card: $c, issue: 7, step: "blocked", time: "2026-11-01T0\(($c | ltrimstr("c") | .[0:1])):00:00Z", tokens: {claude: 0, codex: 0}, result: "blocked", sha: "", reason: $r, kept: $k}
    + (if $by == "" then {} else {retriedBy: $by} end)' >> "$ST/retried.jsonl"
}
# What `retry` does to the card's lines: the card's records, its split line too, move into retried.jsonl.
retried7() { cat "$ST/cards.jsonl" >> "$ST/retried.jsonl" && : > "$ST/cards.jsonl" || fail "the card's lines could not move into retried.jsonl"; }
forcedline() { st 'select(.step == "split" and .card == "'"$1"'") | [.result, .split.verdict, .split.forced, .split.mode] | @json'; }

# Bug caught: an issue under the limits, built twice and blocked twice, was built a third time whole, as its split line
# kept it. The third card asks the judge, its prompt names the reasons of the two blocked cards (cut to 300 characters)
# and says that the issue was built twice, its slices are filed, nothing is built, and its split line holds forced.
t_splitforcedsplit() {
  forcedissue "$SPLIT2"
  blocked7 c1-7 'the review found a P1 in the first build' 1; blocked7 c2-7 "$(printf 'x%.0s' {1..400})"; retried7
  fx_in 'splitcheck c3-7 7'
  [ "$RC" = 1 ] && [ "$(judged)" = 1 ] || fail "the third card of #7 did not file the judge's slices with one judge call (exit $RC, judged $(judged)): $(cat "$T/$CASE/run.out")"
  [ "$(forcedline c3-7)" = '["split","split",true,"on"]' ] && [ "$(jq -sc 'map(.number)' "$STUB/filed")" = '[100101,100102]' ] \
    || fail "the forced check's line is not a forced split with the two slices filed: $(forcedline c3-7) $(cat "$STUB/filed" 2>&1)"
  grep -qF 'the review found a P1 in the first build' "$STUB/prompt" && grep -qF 'built twice and nothing landed' "$STUB/prompt" \
    && ! grep -qF "$(printf 'x%.0s' {1..301})" "$STUB/prompt" && grep -qF "$(printf 'x%.0s' {1..300})" "$STUB/prompt" \
    || fail "the prompt lacks the first reason, the words that the issue was built twice, or holds the second reason cut wrong: $(tail -n 6 "$STUB/prompt" | cut -c1-200)"
  recok "$ST/cards.jsonl" "a forced check that split"
}

# Bug caught: a judge that keeps the issue was asked again by every later card (or: the third card did not build). The
# third card builds (0), with a forced keep line; a fourth card of the same text asks no judge; an edited issue is
# asked once more.
t_splitforcedkeep() {
  forcedissue '{"verdict":"keep","why":"one part"}'
  printf '%s\n' "$GO" > "$STUB/review.1"; printf '%s\n' 'echo build >> "$STUB/did"' 'echo two >> a.txt' > "$STUB/build"
  blocked7 c1-7 'first reason'; blocked7 c2-7 'second reason'; retried7
  # loop: only a whole card run shows that the third card, after a keep, runs its build session and lands
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(judged)" = 1 ] && [ "$(st 'select(.step == "split") | [.result, .split.verdict, .split.forced, .split.mode] | @json')" = '["kept","keep",true,"on"]' ] \
    && [ "$(yesdid)" = build ] && yeslanded \
    || fail "the third card did not build and land after a keep, with a forced keep line (judged $(judged)): $(yessteps); $(yesdid)"
  blocked7 c3-7 'third reason'
  fx_in 'splitcheck c4-7 7'
  [ "$RC" = 0 ] && [ "$(judged)" = 1 ] || fail "the fourth card of #7 asked the judge again (exit $RC, judged $(judged)): $(cat "$T/$CASE/run.out")"
  jq -c '.[0].body += "\n- fourth"' "$STUB/issues.json" > "$STUB/i.new" && mv "$STUB/i.new" "$STUB/issues.json"
  fx_in 'splitcheck c5-7 7'
  [ "$RC" = 0 ] && [ "$(judged)" = 2 ] || fail "an edited #7 did not get its own forced check (exit $RC, judged $(judged)): $(cat "$T/$CASE/run.out")"
}

# Bug caught: the forced check split an issue whose two blocked cards stopped for the owner's yes: its third card must take
# up the kept patch and land it, and a split would have left that patch to rot. No judge call, one build session in all
# (the first card's), the kept patch landed.
t_splitforcedyes() {
  yessetup 'mkdir -p web; echo pay >> web/pay.ts' $'USER-VISIBLE: yes: guests see a new Pay button\nVERDICT: GO'
  jq -c '.rules.split = "on"' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  export CONVEYOR_SPLIT_CMD='cat > "$STUB/prompt"; echo x >> "$STUB/judged"; cat "$STUB/answer"'; echo "$SPLIT2" > "$STUB/answer"
  # loop: the stop for the yes, the retry that gives it back and the landing after the approval line are turns of a card's path
  loop run > /dev/null && loop retry 7 > /dev/null && loop run > /dev/null && loop retry 7 > /dev/null || fail "two cards of #7 did not stop for the yes and be given back"
  [ "$(blocks | wc -l)" = 2 ] && ! yeslanded || fail "#7 did not have two cards blocked for the yes: $(blocks | paste -sd'|'); $(yessteps)"
  approve
  # loop: as above, the third card finds the approval line
  loop run > /dev/null || fail "the run after the approval line exited non-zero"
  [ "$(judged)" = 0 ] && yeslanded && [ "$(yesdid)" = build ] \
    || fail "the third card of #7 did not land the kept patch with no judge call and no build (judged $(judged)): $(yesdid); $(yessteps)"
}

# Bug caught: the forced check split an issue that review-land gave back to land its kept patch.
t_splitforcedland() {
  forcedissue "$SPLIT2"
  blocked7 c1-7 'the review found a P1' 1; blocked7 c2-7 'the review found a P1' 1 review-land
  fx_in 'splitcheck c3-7 7'
  [ "$RC" = 0 ] && [ "$(judged)" = 0 ] || fail "the third card of #7 asked the judge though review-land gave it back (exit $RC, judged $(judged)): $(cat "$T/$CASE/run.out")"
}

# Bug caught: a forced check made for one blocked card whose blocked line is there twice (a card that was ending when
# `retry` took its lines writes a second one, issues.sh retry): the count is of distinct cards. The second card of #7
# asks no judge: its text has a split line, in retried.jsonl where `retry` puts it, and one card is under SPLIT_TRIES.
t_splitforcedone() {
  forcedissue "$SPLIT2"
  blocked7 c1-7 'the review found a P1' 1; blocked7 c1-7 'the review found a P1' 1; retried7
  fx_in 'splitcheck c2-7 7'
  [ "$RC" = 0 ] && [ "$(judged)" = 0 ] || fail "the second card of #7 asked the judge with one blocked card (exit $RC, judged $(judged)): $(cat "$T/$CASE/run.out")"
}

# Bug caught: a forced check in shadow filed slices, or stopped the card. It writes its line (result split, forced, as
# the judge answered) and the card builds (0); nothing is filed.
t_splitforcedshadow() {
  forcedissue "$SPLIT2"
  jq -c '.rules.split = "shadow"' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  blocked7 c1-7 'first reason'; blocked7 c2-7 'second reason'
  fx_in 'splitcheck c3-7 7'
  [ "$RC" = 0 ] && [ "$(judged)" = 1 ] && [ "$(forcedline c3-7)" = '["split","split",true,"shadow"]' ] && [ ! -s "$STUB/filed" ] \
    || fail "the forced check in shadow did not write its line and go on, filing nothing (exit $RC, judged $(judged)): $(forcedline c3-7) $(cat "$STUB/filed" 2>&1)"
}
