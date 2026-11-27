#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#765): the judge replay study (replay(), lib/replay.sh), which gives the findings the project's judge
# ruled on, with their diffs, to another judge and compares the rulings, and the snapshot's last replay (cost.replay).
# Each case calls replay() with a stub judge (judgecall() defined again in the case's shell), so no model runs.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The recorded reviews, each judged on claude-sonnet-5-5 with 1M input tokens ($2.00):
# - c1-7 (issue 7, landed as a commit that adds "three" to a.txt): F1 accepted, F2 declined. Its review sat on B0;
#   another card landed between them, which adds "zero" at the top of a.txt, so the landed commit's parent is not B0.
# - c1-6 (issue 8, in the retried lines, as `retry 8 --fresh` leaves it): F-nine accepted; no diff, so it is skipped.
# - c1-8 (issue 8, blocked, in the retried lines; its kept patch adds "four" to a.txt): F1 of a kind always accepted,
#   that the judge declined, so its own ruling is a decline. Built from nothing after c1-6, its judge was given no
#   findings of a fix round before it (no back).
# - c1-9 (issue 9): no landed commit and no kept patch, so it has no diff and is skipped.
# - c1-10: a review the record marks as failed, with F-five accepted and F-eight undecided (no readable decision).
# - c1-11 (issue 9, landed as the same commit as c1-7): F1 accepted; the replay judge's call on it fails. Its judge
#   was given the finding E2 (F-eight) of the card's own fix round before it (back), not c1-10's F-five.
# - c1-12 (issue 9, landed as the same commit, but its review read the change of c1-8): skipped.
# Each review line keeps the patch-id of the change it read, and when it read the declined list (judge.read: its time
# less its judge's 5 s); c1-7 has a decline of an earlier round and its own.
# The replay judge is claude-haiku-5-5, allowed for the review here: 1M input tokens a call cost $0.10.
replaysetup() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-01),$(issue 9 2026-01-01)]"
  tune '.models.allowed["claude-reviewer"] += ["claude-haiku-5-5"]'
  printf '%s\n' one l2 l3 l4 l5 l6 > "$R/a.txt"; git -C "$R" commit -qam six; B0=$(git -C "$R" rev-parse HEAD)
  { echo zero; cat "$R/a.txt"; } > "$R/a.new"; mv "$R/a.new" "$R/a.txt"; git -C "$R" commit -qam zero
  echo three >> "$R/a.txt"; git -C "$R" commit -qam seven; local sha base=$B0; sha=$(git -C "$R" rev-parse HEAD)
  # The patch-id each review line keeps of the change it read, made as cardpatch() makes it.
  P7=$(git -C "$R" diff --binary --no-renames -U0 "$sha^" "$sha" | diffid)
  mkdir -p "$ST/kept/c1-8"; echo four >> "$R/a.txt"; git -C "$R" diff > "$ST/kept/c1-8/c1-8.patch"
  git -C "$R" add a.txt; P8=$(git -C "$R" diff --cached --binary --no-renames -U0 HEAD | diffid); git -C "$R" reset -q; git -C "$R" checkout -q -- a.txt
  U='{"input":1000000,"write":0,"write1h":0,"read":0,"output":0}'
  # The repo name the engine reads an issue's records by ($REPO): a review line of another card of the issue is the
  # issue's only when its repo is this one (outsideruled()).
  rp=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && printf '%s' "$REPO" ) && [ -n "$rp" ] || fail "the engine's repo name could not be read"
  rline() { # <card> <issue> <minute> <patch> <judge json> [<file>]
    jq -cn --arg c "$1" --argjson i "$2" --arg t "2026-11-01T00:0$3:00Z" --arg m "$base" --arg p "$4" --argjson j "$5" --argjson u "$U" --arg r "$rp" \
      '{card: $c, issue: $i, repo: $r, step: "review", time: $t, tokens: {claude: 0, codex: 0}, result: "GO", sha: "", reason: "", main: $m, patch: $p,
        judge: ({model: "claude-sonnet-5-5", effort: "medium", sec: 5, tokens: {claude: 1000000, codex: 0}, usage: $u,
          read: ($t | fromdateiso8601 - 5 | todate)} + $j)}' >> "${6:-$ST/cards.jsonl}"
  }
  landed() { jq -cn --arg c "$1" --argjson i "$2" --arg t "$3" --arg s "$sha" '{card: $c, issue: $i, step: "landed", time: $t, tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: ""}' >> "$ST/cards.jsonl"; } # <card> <issue> <time>
  rline c1-7 7 1 "$P7" '{"accepted":[{"n":1,"finding":"[P1] a.txt:2 F-one. Proof: p. At a.txt:2: `l2`","place":"inside","reason":"real","cost":"none"}],"declined":[{"n":2,"finding":"[P2] a.txt:1 F-two","place":"outside","reason":"style"}]}'
  landed c1-7 7 2026-11-01T00:02:00Z
  # Findings ruled OUTSIDE on issue 7 (#1734): c1-0, before c1-7's judge ran, one in judge.outside and one that went to the
  # self-heals list (outside: true); c1-13, after it ran. Neither review has a ruling to replay, so neither is a case.
  rline c1-0 7 0 "$P7" '{"outside":[{"n":1,"finding":"[P2] b.txt:1 F-out","place":"outside","reason":"old code too","effect":"harm"}],"selfheals":[{"n":2,"finding":"[P3] b.txt:2 F-heal","place":"outside","reason":"a typo","effect":"self-heals","outside":true}]}'
  rline c1-13 7 8 "$P7" '{"outside":[{"n":1,"finding":"[P2] b.txt:3 F-late","place":"outside","reason":"later"}]}'
  # c1-7's declines: one of an earlier round, before its judge ran (00:00:55, when its review read the list), which
  # the replay judge is given, and the one its judge declined (written after its call), which it is not.
  printf '%s\n' '{"id":"d000000000001","time":"2026-11-01T00:00:30Z","card":"c1-7","issue":7,"finding":"[P2] a.txt:1 F-old","by":"judge","why":"nothing new","kind":"claim wrong","repo":"r"}' \
    '{"id":"d000000000002","time":"2026-11-01T00:00:58Z","card":"c1-7","issue":7,"finding":"[P2] a.txt:1 F-two","by":"judge","why":"style","repo":"r"}' >> "$ST/declined.jsonl"
  rline c1-6 8 2 "$P8" '{"accepted":[{"n":1,"finding":"[P1] a.txt:3 F-nine","place":"inside","reason":"real","cost":"none"}],"declined":[]}' "$ST/retried.jsonl"
  base=$sha rline c1-8 8 3 "$P8" '{"accepted":[{"n":1,"finding":"[P1][security] a.txt:3 F-three","place":"inside","reason":"always accepted: a security finding (the judge declined it: weak)","cost":"none"}],"declined":[]}' "$ST/retried.jsonl"
  jq -cn '{card: "c1-8", issue: 8, step: "blocked", time: "2026-11-01T00:04:00Z", tokens: {claude: 0, codex: 0}, result: "blocked", sha: "", reason: "tests failed", kept: "kept/c1-8"}' >> "$ST/retried.jsonl"
  rline c1-9 9 5 "$P7" '{"accepted":[{"n":1,"finding":"[P1] a.txt:1 F-four","place":"inside","reason":"real","cost":"none"}],"declined":[]}'
  rline c1-10 9 6 "$P7" '{"failed":"the judge call failed","accepted":[{"n":1,"finding":"[P1] a.txt:1 F-five","place":"inside","reason":"real","cost":"none"},{"n":2,"finding":"[P1] a.txt:1 F-eight","place":"inside","reason":"the judge gave no line for this finding that could be read","cost":null}]}'
  rline c1-11 9 7 "$P7" '{"accepted":[{"n":1,"finding":"[P1] a.txt:2 F-six","place":"inside","reason":"real","cost":"none"}],"declined":[],"back":["- E2 [P1] a.txt:1 F-eight"]}'
  landed c1-11 9 2026-11-01T00:08:00Z
  # c1-12: its review read another change (P8) than the commit that landed after a fix round, so it is skipped.
  rline c1-12 9 9 "$P8" '{"accepted":[{"n":1,"finding":"[P1] a.txt:2 F-seven","place":"inside","reason":"real","cost":"none"}],"declined":[]}'
  landed c1-12 9 2026-11-01T00:09:30Z
  # What a replay must leave as it was: the card records, the retried lines, the control record, the pack and main.
  SUMS='cat "$ST/cards.jsonl" "$ST/retried.jsonl" "$ST/declined.jsonl" "$ST/control.json" "$R/.conveyor/project.json" | cksum; git -C "$R" rev-parse HEAD; git -C "$R" status --porcelain; git -C "$R" worktree list | wc -l'
  eval "$SUMS" > "$STUB/before"
}
# The stub judge: it keeps the staged change and what it was given ($STUB/judged) and c1-7's whole staged diff
# ($STUB/c1-7.diff), answers the findings of c1-7 with F1 ACCEPT and F2 OUTSIDE (so F2 differs from the recorded
# decline), the one of c1-8 with a DECLINE (as its judge did), and fails on c1-11 (a timeout) with the usage the call
# had used, as judgecall() prints it.
STUBJUDGE='judgecall() {
  { echo "== $CALLACT"; git -C "$1" diff --cached | grep "^+[a-z]\|^@@"; printf "%s\n" "$3"; } >> "$STUB/judged"; printf "%s\n" "$2" >> "$STUB/judge-prompt"
  case $CALLACT in
    *c1-7) git -C "$1" diff --cached > "$STUB/c1-7.diff"
      printf "%s\n" "F1 ACCEPT: real. Cost to every card: none" "F2 OUTSIDE: harm: b.txt:1 was already ruled outside" > "$1.judge"
      echo "{\"model\":\"claude-haiku-5-5\",\"effort\":\"low\",\"sec\":3,\"usage\":$U}" ;;
    *c1-8) echo "F1 DECLINE: weak" > "$1.judge"; echo "{\"model\":\"claude-haiku-5-5\",\"effort\":\"low\",\"sec\":3,\"usage\":$U}" ;;
    *) echo "{\"model\":\"claude-haiku-5-5\",\"effort\":\"low\",\"sec\":9,\"usage\":$U,\"failed\":\"the judge call failed (timeout)\"}"; return 1 ;;
  esac
}'
# fx_in() with the libraries `conveyor.sh pick replay` loads (the replay branch of commands/pick.sh), not the run command's:
# a function replay() calls from a library the command does not load is missing here as it is there. A list that
# yields no library leaves names() undefined, which ends the shell with 9 and fails the case.
fx_pick() { # <commands>
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(sed -n '/= replay \]/,/^fi$/p' "$SRC/commands/pick.sh" | grep '^  \. "\$HERE/lib/')" || exit 9
    names || exit 9
    eval "$1" ) > "$T/$CASE/run.out" 2>&1; RC=$?
  [ "$RC" != 9 ] || fail "the replay command's libraries could not be loaded: $(cat "$T/$CASE/run.out")"
}

# Bugs caught: the replay did not give the judge the recorded findings with their diff (the landed commit, or the
# kept patch of a blocked card in the retried lines), counted a case with no diff, compared with the reason of a kind
# always accepted in place of the judge's own decline, or gave a wrong agreement count, list of differences or cost;
# a failed judge call left no usage; the replay wrote a card line, changed a setting or left a worktree behind.
t_replayjudge() {
  replaysetup
  # Bug caught: the replay judge was given another decline rule than a review's judge is now (the control record's
  # rare-case levels, judgeprompt()).
  loop control judge rare P2 >/dev/null || fail "control judge rare P2 failed"; eval "$SUMS" > "$STUB/before"
  # Bug caught (#1749): replay() marked every finding's proof line `none` when run as `conveyor.sh pick replay` runs it,
  # because proofline() came from a library that only the run command loads; so it runs with the replay command's libraries.
  fx_pick "$STUBJUDGE"'; replay judge claude-haiku-5-5 low'
  [ "$RC" = 0 ] || fail "the replay failed: $(cat "$T/$CASE/run.out")"
  out=$(tail -n 1 "$T/$CASE/run.out")
  jq -e '{reviews, skipped, findings, agree, unanswered, usd, recordedUsd, model, effort} == {"reviews":3,"skipped":3,"findings":3,"agree":2,"unanswered":1,"usd":0.3,"recordedUsd":6,"model":"claude-haiku-5-5","effort":"low"}' <<<"$out" >/dev/null \
    || fail "the replay's counts and costs: $out"
  # Bug caught: the replay read only ACCEPT and DECLINE lines, so c1-7's F2 OUTSIDE (a repeat of an OUTSIDE ruling, as the
  # judge's rules ask) counted as unanswered.
  [ "$(jq -c .differ <<<"$out")" = '[{"card":"c1-7","issue":7,"n":2,"finding":"[P2] a.txt:1 F-two","recorded":"decline","replay":"outside","reason":"harm: b.txt:1 was already ruled outside"}]' ] \
    || fail "the findings where the rulings differ: $(jq -c .differ <<<"$out")"
  [ "$(jq -c '.calls | map([.card, .usage.input, .failed // ""])' <<<"$out")" = '[["c1-7",1000000,""],["c1-8",1000000,""],["c1-11",1000000,"the judge call failed (timeout)"]]' ] \
    || fail "each call's usage, the failed one's too, is not recorded: $(jq -c .calls <<<"$out")"
  [ "$(cat "$ST/replays.jsonl")" = "$out" ] || fail "the replay's line is not the one line of $ST/replays.jsonl: $(cat "$ST/replays.jsonl" 2>&1)"
  grep -q '^+three$' "$STUB/judged" && grep -q '^+four$' "$STUB/judged" && grep -q '^F1 \[inside the diff; proof line: match\] \[P1\] a.txt:2 F-one. Proof: p. At a.txt:2: `l2`$' "$STUB/judged" \
    && grep -q '^F2 \[outside the diff; proof line: none\] \[P2\] a.txt:1 F-two$' "$STUB/judged" && grep -q '^#7 title 7$' "$STUB/judged" \
    || fail "the judge was not given each case's diff, issue and findings: $(cat "$STUB/judged")"
  # Bug caught (#1381): the replay judge's prompt says each finding is followed by the lines it cites and a small staged
  # change is in the message, but replay sent the finding text alone, so it judged with less than the live judge has.
  # The message is checked from the diff heading to its end: the diff's own lines and the last finding's (F2) lines
  # too, so an empty inline diff or a finding with no lines beside it fails here. The diff is the one the stub read
  # from c1-7's replay worktree; it must hold the "three" line, so an empty one cannot match itself.
  grep -qx '+three' "$STUB/c1-7.diff" && [ "$(awk '/^== /{on = /c1-7$/} on' "$STUB/judged" | sed -n '/^# The staged change /,$p')" = '# The staged change (git diff --cached)
'"$(cat "$STUB/c1-7.diff")"'

# The findings
F1 [inside the diff; proof line: match] [P1] a.txt:2 F-one. Proof: p. At a.txt:2: `l2`
  Lines at a.txt:2 (the staged change):
    1: one
    2: l2
    3: l3
    4: l4
    5: l5
F2 [outside the diff; proof line: none] [P2] a.txt:1 F-two
  Lines at a.txt:1 (the staged change):
    1: one
    2: l2
    3: l3
    4: l4' ] \
    || fail "the replay judge was not given the lines each finding cites, or the small staged change: $(awk '/^== /{on = /c1-7$/} on' "$STUB/judged")"
  [ "$(grep -cF 'really runs, its defect is already fixed on main, or, at P2 only, it is a rare case' "$STUB/judge-prompt")" = 3 ] \
    || fail "a replay judge's prompt does not hold the record's rare-case level P2: $(grep -n -i 'rare case' "$STUB/judge-prompt")"
  # Bug caught: c1-7's landed commit was staged on its parent, a later main than its review read, so the judge saw
  # other hunk line numbers (line 5, below "zero") than its review did (line 4, on B0).
  grep -q '^@@ -4,3 +4,4 @@' "$STUB/judged" && ! grep -q '^@@ -5,3 +5,4 @@' "$STUB/judged" \
    || fail "c1-7's change was not staged on the commit its review sat on: $(cat "$STUB/judged")"
  # Bug caught: the replay judge was given a change its review never read (c1-12's, landed after a fix round).
  ! grep -q 'c1-12$' "$STUB/judged" || fail "c1-12, whose review read another change, was replayed: $(cat "$STUB/judged")"
  # Bug caught: the replay judge was not told what was declined on the issue before, so it could not decline a
  # finding raised again with nothing new; nor may it be told the declines its own review made after its call; nor
  # told each earlier decline without its kind, which JUDGE needs to decline a repeat (#1522).
  grep -q '^# Findings already declined on the cards of this issue$' "$STUB/judged" && grep -q '^- \[P2\] a.txt:1 F-old (declined: nothing new) \[kind: claim wrong\]$' "$STUB/judged" \
    && ! grep -q '(declined: style)' "$STUB/judged" || fail "the earlier declines given to the judge: $(cat "$STUB/judged")"
  # Bug caught (#1734): the replay judge used the rule that gives a repeat of an OUTSIDE ruling its earlier ruling again,
  # but was not given the findings ruled OUTSIDE (the live judge is, outsideruled()), nor the ones that went to the
  # self-heals list, and not only the ones from before its own review.
  [ "$(awk '/^== /{on = /c1-7$/} on' "$STUB/judged" | sed -n '/^# Findings ruled OUTSIDE on the cards of this issue$/,/^$/p')" = '# Findings ruled OUTSIDE on the cards of this issue
- [P2] b.txt:1 F-out (ruled OUTSIDE: harm: old code too)
- [P3] b.txt:2 F-heal (ruled OUTSIDE: self-heals: a typo)' ] || fail "the replay judge of c1-7 was not given the findings ruled OUTSIDE before its review, or was given a later one: $(grep -n 'OUTSIDE\|F-late\|^== ' "$STUB/judged")"
  # Bug caught: a review's judge is told the findings the fix round before it was told to fix, each with the reason it
  # accepted it with (#1379), but the replay judge was not, so it ruled on a finding back after its fix as on a new
  # one. Bugs caught: the replay judge was given the findings another card's review (c1-10's F-five, before c1-11 on
  # issue 9) accepted, which no fix round of c1-11 was told (after `retry <issue> --fresh` its card builds from
  # nothing), and was given them without their E<n> ids. c1-11's own line keeps the section its judge was given (E2,
  # F-eight); c1-7 and c1-8 have none, and c1-8 must not fall back to c1-6's F-nine, accepted before it on issue 8.
  [ "$(grep -c '^# The findings the last fix round was told to fix$' "$STUB/judged")" = 1 ] \
    && [ "$(awk '/^== /{on = /c1-11$/} on' "$STUB/judged" | grep -cxF -- '- E2 [P1] a.txt:1 F-eight')" = 1 ] \
    && ! grep -q 'F-five\|F-nine' "$STUB/judged" \
    || fail "the replay judge of c1-11 was not given the section its review's judge was given (E2 F-eight), was given c1-10's F-five or c1-6's F-nine, or c1-7 or c1-8 was given a section: $(grep -n 'fix round\|F-five\|F-nine\|F-eight\|^== ' "$STUB/judged")"
  # Bug caught: F-eight, which c1-10's judge gave no readable line for (kept in accepted with cost null), reached the
  # replay judge labelled as accepted, with "the judge gave no line ... could be read" as the reason, though the fix
  # round before c1-11 was told to fix it with no label, as the live review lists it (fixedbefore(), lib/review.sh).
  ! grep -q 'F-eight (accepted' "$STUB/judged" \
    || fail "the replay judge of c1-11 was given F-eight, undecided in c1-10, with an acceptance label: $(grep -n 'F-eight\|^== ' "$STUB/judged")"
  [ "$(eval "$SUMS")" = "$(cat "$STUB/before")" ] || fail "the replay changed a card line, a setting or main: $(eval "$SUMS") was $(cat "$STUB/before")"
}

# Bugs caught: the estimate called the judge or wrote a replay line, or did not price the recorded judges' token use
# at the model asked; a model the pack does not allow the judge was replayed.
t_replayestimate() {
  replaysetup
  local before; before=$(cd "$ST" && find . -type f | sort)
  fx_in '. "$HERE/lib/replay.sh"; judgecall() { echo called >> "$STUB/judged"; return 1; }; replay judge claude-haiku-5-5 --estimate; replay judge m9 --estimate; echo "rc $?"'
  # Bug caught (#855): the header of lib/replay.sh said the replay writes only its result line, while an estimate
  # makes the lock file (and the records' read makes the state database). The estimate's new files are listed from
  # the run; that the header names each one is read from its text, as a comment's truth has no behaviour to run.
  [ "$(comm -13 <(echo "$before") <(cd "$ST" && find . -type f | sort) | tr '\n' ' ')" = './replays.jsonl.lock ./state.db ' ] \
    || fail "the estimate wrote other files than the lock and the state database: $(cd "$ST" && find . -type f | sort | comm -13 <(echo "$before") - | tr '\n' ' ')"
  local head; head=$(sed -n '/^# SPDX/,/^[^#]/p' "$SRC/lib/replay.sh")
  grep -q 'REPLAYS\.lock' <<<"$head" && grep -q 'state\.db' <<<"$head" || fail "the header of lib/replay.sh does not name each file an estimate makes"
  head -n 1 "$T/$CASE/run.out" | jq -e '. == {"estimate":true,"model":"claude-haiku-5-5","effort":"medium","reviews":3,"skipped":3,"findings":4,"usd":0.3,"recordedUsd":6}' >/dev/null \
    || fail "the estimate: $(cat "$T/$CASE/run.out")"
  # Bug caught: `conveyor.sh pick replay` (commands/pick.sh) did not reach replay(), which the cases above call
  # directly; the estimate is the one replay the CLI can run here with no judge.
  cli=$(loop pick replay judge claude-haiku-5-5 --estimate 2>&1) && [ "$cli" = "$(head -n 1 "$T/$CASE/run.out")" ] \
    || fail "conveyor.sh pick replay did not give the estimate: $cli"
  grep -q '^rc 2$' "$T/$CASE/run.out" && grep -q 'm9 is not one of the models' "$T/$CASE/run.out" || fail "a model the pack does not allow was taken: $(cat "$T/$CASE/run.out")"
  [ ! -e "$STUB/judged" ] && [ ! -e "$ST/replays.jsonl" ] || fail "the estimate called the judge or wrote a replay"
  # Bug caught: an estimate passed while a replay ran, so the Board started a second replay that ended at once.
  fx_in '. "$HERE/lib/replay.sh"; exec 7>>"$REPLAYS.lock"; flock 7; replay judge claude-haiku-5-5 --estimate'
  [ "$RC" = 1 ] && grep -q 'a replay is running already' "$T/$CASE/run.out" || fail "an estimate while a replay runs was not refused: $RC $(cat "$T/$CASE/run.out")"
}

# Bug caught: the cases were added up in one command argument, so 40 more reviews of 4,000-character findings (over
# the 131,072 bytes Linux takes in one argument) made a valid --last fail the estimate.
t_replaylong() {
  replaysetup
  jq -cn --arg p "$P7" --arg m "$B0" --arg f "[P2] a.txt:1 $(printf 'x%.0s' {1..4000})" --argjson u "$U" 'range(10; 50) as $i
    | {card: "c1-7", issue: 7, step: "review", time: "2026-11-01T01:\($i):00Z", tokens: {claude: 0, codex: 0}, result: "GO", sha: "", reason: "", main: $m, patch: $p,
       judge: {model: "claude-sonnet-5-5", effort: "medium", sec: 5, tokens: {claude: 1000000, codex: 0}, usage: $u, accepted: [{n: 1, finding: $f, place: "inside", reason: "real", cost: "none"}]}}' >> "$ST/cards.jsonl"
  fx_in '. "$HERE/lib/replay.sh"; replay judge claude-haiku-5-5 --estimate --last 50'
  [ "$RC" = 0 ] && head -n 1 "$T/$CASE/run.out" | jq -e '{reviews, skipped, findings} == {"reviews":43,"skipped":3,"findings":44}' >/dev/null \
    || fail "the estimate of 46 reviews (43 replayed, 3 skipped): $RC $(head -c 2000 "$T/$CASE/run.out")"
}

# Bug caught: a finding declined on issue 9 as a rare case (00:04:20), then as claim wrong (00:05:30), then as other
# (00:08:00), was given to a replay judge with a ruling that judge never saw, or without the one it did: c1-9's judge
# (ran 00:04:55) must get rare case, c1-11's (00:06:55) claim wrong and c1-12's (00:08:55) other. declined() kept the
# first time on the rewritten line, or dated the claim-wrong ruling it moved into was with the first ruling's time
# (only a third ruling moves a replaced ruling there), or the replay left out the current ruling of a line ruled again.
# Bug caught: c1-13's review read the list at 00:05:00, then waited for its judge's CLI (seatwait()) until 00:06:55; the
# replay took the judge's start from its line's time less its seconds, so it gave claim wrong, made during the wait.
# Bug caught: c1-14's line was written before judged() kept judge.read; the replay gave it no earlier declines, not
# the claim wrong of before its line's time less its judge's 5 s (00:06:55).
t_replayrekind() {
  replaysetup
  base=$B0 rline c1-13 9 7 "$P7" '{"accepted":[{"n":1,"finding":"[P1] a.txt:2 F-wait","place":"inside","reason":"real","cost":"none"}],"declined":[],"read":"2026-11-01T00:05:00Z"}'
  base=$B0 rline c1-14 9 7 "$P7" '{"accepted":[{"n":1,"finding":"[P1] a.txt:2 F-old-line","place":"inside","reason":"real","cost":"none"}],"declined":[],"read":null}'
  CONVEYOR_NOW=$(p_date 2026-11-01T00:04:20Z +%s) loop declined add c1-9 9 judge 'rare: needs two hosts' '[P2] a.txt:4 F-rk' 'rare case' \
    && CONVEYOR_NOW=$(p_date 2026-11-01T00:05:30Z +%s) loop declined add c1-9 9 judge 'claim wrong: guarded' '[P2] a.txt:4 F-rk' 'claim wrong' \
    && CONVEYOR_NOW=$(p_date 2026-11-01T00:08:00Z +%s) loop declined add c1-9 9 judge 'other: style' '[P2] a.txt:4 F-rk' 'other' \
    || fail "declined add of F-rk on c1-9 as rare case at 00:04:20, claim wrong at 00:05:30, then other at 00:08:00, failed"
  fx_in '. "$HERE/lib/replay.sh"; replaycases 20'
  local c want got
  for c in 'c1-9|rare: needs two hosts|rare case' 'c1-11|claim wrong: guarded|claim wrong' 'c1-12|other: style|other' 'c1-13|rare: needs two hosts|rare case' 'c1-14|claim wrong: guarded|claim wrong'; do
    IFS='|' read -r c want got <<<"$c"; want="- [P2] a.txt:4 F-rk (declined: $want) [kind: $got]"
    got=$(jq -r --arg c "$c" 'select(.card == $c) | .before[]' "$T/$CASE/run.out" | grep F-rk)
    [ "$RC" = 0 ] && [ "$got" = "$want" ] \
      || fail "replaycases 20, after F-rk was declined on issue 9 as rare case, claim wrong, then other: $c's earlier declines give '$got', not '$want': $(cat "$T/$CASE/run.out" "$ST/declined.jsonl")"
  done
}

# Bug caught: replay gave a judge a ruling that the review's judge never read. judged() reads the declined list before
# seatwait() waits for the judge's CLI, and the judge's seconds start after that wait, so a ruling made during the wait
# looked older than the judge's run. The real judged() and seatwait() run: claude is off PATH, and the wait's first
# pause (its sleep) rules on F-rk as claim wrong and puts claude back. With <first> 0, F-rk was declined as rare case
# before the wait and the wait replaces that ruling; with 1, the wait's ruling is F-rk's first, so the judge read no
# declined line, and replay must keep that empty list rather than fall back to the declined list.
replayseat() { # <first>
  local rk='[P2] a.txt:4 F-rk' want='[]' nc
  judging "[$(issue 9 2026-01-01)]"
  if [ "$1" = 0 ]; then
    CONVEYOR_NOW=$(p_date 2026-11-01T00:04:20Z +%s) loop declined add c9 9 judge 'rare: needs two hosts' "$rk" 'rare case' >/dev/null \
      || fail "declined add of F-rk on c9 as rare case failed"
    want=$(jq -cn --arg w "- $rk (declined: rare: needs two hosts) [kind: rare case]" '[$w]')
  fi
  printf '%s\n' '[P2] a.txt:2 F-new' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"; echo 'F1 ACCEPT: real. Cost to every card: none' > "$STUB/judge.1"
  # This host's report lists claude, so seatwait() waits for it; the PATH then keeps the stubs but no host's own
  # claude, which would otherwise be found in place of the moved stub.
  fx_in 'hostclis fresh'; [ "$RC" = 0 ] || fail "the host's CLIs report could not be written: $(cat "$T/$CASE/run.out")"
  nc=$(tr ':' '\n' <<< "$PATH" | while IFS= read -r d; do [ "$d" != "$STUB" ] && [ -e "$d/claude" ] || printf '%s\n' "$d"; done | paste -sd: -)
  sleep() { # seatwait()'s pause: F-rk is ruled on while the judge waits, then claude is back
    [ "${FUNCNAME[1]:-}" = seatwait ] && [ -e "$STUB/claude.off" ] || { command sleep "$@"; return; } # sleep: any other caller's own pause, passed on as called
    CONVEYOR_NOW=$(p_date 2026-11-01T00:05:30Z +%s) loop declined add c9 9 judge 'claim wrong: guarded' "$rk" 'claim wrong' >/dev/null \
      && mv "$STUB/claude.off" "$STUB/claude" && echo waited >> "$STUB/waits" # stub: judging()'s own claude stub, put back on PATH as a reinstall would
  }
  ( export PATH=$nc; mv "$STUB/claude" "$STUB/claude.off" && judgeone 9 "$STUB/review" )
  unset -f sleep
  [ "$(cat "$STUB/waits" 2>/dev/null)" = waited ] && [ "$(grep -F -- "$rk" "$STUB/judge-asked" | jq -cR . | jq -cs .)" = "$want" ] \
    || fail "the judge did not wait once for claude, or was not given F-rk's declined lines as they were before the wait ($want): $(cat "$STUB/waits" "$STUB/judge-asked" 2>&1)"
  # The review's line, as card() writes it, a minute after the wait's ruling (00:05:30) with the judge's few seconds.
  jq -c '{card: "c9", issue: 9, step: "review", time: "2026-11-01T00:06:00Z", tokens: {claude: 0, codex: 0}, result: "GO", sha: "", reason: "", judge}' \
    "$T/$CASE/cards/c9.fields" >> "$ST/cards.jsonl"
  fx_in '. "$HERE/lib/replay.sh"; replaycases 20'
  [ "$RC" = 0 ] && [ "$(jq -c 'select(.card == "c9") | .before' "$T/$CASE/run.out")" = "$want" ] \
    || fail "replaycases 20 does not give c9's judge the declined lines it read before F-rk's claim wrong ruling during seatwait() ($want): $(cat "$T/$CASE/run.out" "$T/$CASE/cards/c9.fields")"
}
t_replayseatwait() { replayseat 0; }  # a ruling replaced during the wait
t_replayseatfirst() { replayseat 1; } # a first decline made during the wait: the judge read none

# Bug caught (issue 1559): a review whose judge only sent findings to the self-heals list (judge.selfheals) is no
# case, and a mixed one drops those rulings, so the replay never compares a self-heals ACCEPT. An OUTSIDE one is left
# out, as every OUTSIDE ruling is.
t_replayheals() {
  setup '[]'
  jq -cn '{card: "c1-20", issue: 20, step: "review", time: "2026-11-01T00:10:00Z", result: "GO", judge: {model: "m", sec: 1, selfheals: [
    {n: 1, finding: "[P2] a.txt:1 F-heal", place: "inside", reason: "the next turn", effect: "self-heals", cost: "none"},
    {n: 2, finding: "[P2] b.txt:1 F-out", place: "outside", reason: "not the change", effect: "self-heals", outside: true}]}}' >> "$ST/cards.jsonl"
  fx_in '. "$HERE/lib/replay.sh"; replaycases 20'
  [ "$RC" = 0 ] && [ "$(jq -c 'select(.card == "c1-20") | .findings' "$T/$CASE/run.out")" = '[{"n":1,"finding":"[P2] a.txt:1 F-heal","place":"inside","accept":true}]' ] \
    || fail "replaycases 20 does not give c1-20's self-heals ACCEPT as an accepted finding alone: $(cat "$T/$CASE/run.out")"
}

# Bug caught: the Board was not given the last replay (the snapshot's cost.replay), was given every call's usage
# with it, or was given only the first 50 findings where the rulings differ. The snapshot reads the last line of the
# replays file.
t_replaysnap() {
  setup '[]'
  { echo '{"time":"2026-11-01T00:00:00Z","model":"old"}'
    jq -cn '{time: "2026-11-02T00:00:00Z", seat: "judge", model: "claude-haiku-5-5", effort: "low", reviews: 60, findings: 60, agree: 0,
      differ: [range(1; 61) | {card: "c1-\(.)", issue: ., n: 1, finding: "F\(.)", recorded: "accept", replay: "decline", reason: "weak"}], usd: 0.2, recordedUsd: 4, calls: [{card: "c1-7"}]}'; } > "$ST/replays.jsonl"
  [ "$(loop snapshot | jq -c '.cost.replay | [.model, .agree, .calls, (.differ | length), .differ[-1].finding]')" = '["claude-haiku-5-5",0,null,60,"F60"]' ] \
    || fail "the snapshot's last replay: $(loop snapshot | jq -c .cost.replay)"
}
