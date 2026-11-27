#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 180
# Engine cases: the attempts record of an issue (#1820, lib/attempts.sh): what each earlier attempt tried and how it
# ended, written when a fix round ends, a Test step fails and a card blocks, and given to the next fix round, Test-step
# fix, retried card and follow-up card.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# att_fix <pass> <reply> <review line> <prompt file> [<card prompt>]: afterreview() and cardfix() of card c7 (issue 7)
# on the review beside $W, as card() calls them after review <pass>: its fix session is stubbed to keep its prompt in
# <prompt file>, reply <reply> in its output and change a.txt; the review line (rline) carries the judge's reasons.
# checked() is stubbed to replace that output, as its Done-when or checks fix session does: the round's approach is
# its own reply all the same. With ACHECK=1, checked() fails, as it does when it blocks the card.
att_fix() {
  rm -f "${T:?}/${CASE:?}/go"
  AREPLY=$2 ARL=$3 APF=$4 ASP=${5:-} ACHECK=${ACHECK:-0} FXWT=$W afterrun "$(issue 7 2026-01-01)" "pass=$1" \
    'c=c7 n=7 rline=$ARL fixed=0 sprompt=$ASP br=""; checked() { jq -cn "{type: \"result\", result: \"CHECK-REPLY\"}" > "$3.out"; return "$ACHECK"; }
    session() { printf "%s\n" "$2" > "$APF"; jq -cn --arg r "$AREPLY" "{type: \"result\", result: \$r}" > "$1.out"; echo fixed >> "$1/a.txt"; }
    cardfix; echo "${go:-}" > "$T/$CASE/go"'
  { [ "${ACHECK:-0}" != 0 ] || [ "$(cat "$T/$CASE/go" 2>/dev/null)" = next ]; } && [ -s "$4" ] || fail "cardfix() on the review '$(tr '\n' ' ' < "$W.review")' started no fix session: $AFTER $(cat "$T/$CASE/run.out")"
}
# att_wt: the worktree $W of card c7, a.txt of 20 lines committed, and the review beside it of one P1 finding at
# a.txt:9, which ATTJUDGE (a review line) has the judge accept with its reason JUDGE-ONE.
att_wt() {
  setup "[$(issue 7 2026-01-01)]"
  W=$T/$CASE/w; mkdir -p "$W" && git -C "$W" init -q && seq 1 20 | sed 's/^/line /' > "$W/a.txt" && git -C "$W" add -A \
    && git -C "$W" -c user.name=t -c user.email=t@example.com commit -qm a || fail "the worktree could not be made"
  printf '%s\n' '[P1] a.txt:9 the guard reads a stale flag' 'VERDICT: NO-GO' > "$W.review"
  ATTJUDGE=$(jq -cn '{judge: {accepted: [{finding: "[P1] a.txt:9 the guard reads a stale flag", reason: "JUDGE-ONE: the flag is set before the lock", cost: "small"}]}}')
}

# Bug it catches: a second fix round was told nothing of the first one, so it could try the same approach again. The
# entry cardfix() writes when round 1 ends holds that round's reply (its approach) and the judge's reason for the
# finding it fixed; round 2's prompt holds both. Also catches: the section the brief got when it was made (carried())
# left in the prompt beside the new one, so the fix read a stale record twice.
t_attemptsfix() {
  local l
  att_wt
  att_fix 1 'APPROACH-ONE: recorded the flag where the lock writes it' "$ATTJUDGE" "$T/$CASE/p1"
  ! grep -qF '# Earlier attempts at this issue' "$T/$CASE/p1" || fail "round 1's prompt holds an attempts section, with no attempt recorded: $(cat "$T/$CASE/p1")"
  printf '%s\n' '[P1] a.txt:12 a new bug' 'VERDICT: NO-GO' > "$W.review"
  att_fix 2 'APPROACH-TWO' '' "$T/$CASE/p2" $'brief start\n\n# Earlier attempts at this issue\nSTALE-ENTRY\n# End of the earlier attempts\n\nbrief end'
  for l in '## fix round 1 of card c7' 'Outcome: review 1 said NO-GO' 'Approach: APPROACH-ONE: recorded the flag where the lock writes it' \
    '- E1: JUDGE-ONE: the flag is set before the lock' "Diff: $W.rounds/1.diff" 'brief end'; do
    grep -qxF -- "$l" "$T/$CASE/p2" || fail "round 2's prompt (after round 1 replied 'APPROACH-ONE...' and the judge kept E1 for 'JUDGE-ONE...') lacks the line '$l': $(cat "$T/$CASE/p2")"
  done
  [ "$(grep -c '^# Earlier attempts at this issue$' "$T/$CASE/p2")" = 1 ] && ! grep -qF STALE-ENTRY "$T/$CASE/p2" \
    || fail "round 2's prompt, its card prompt holding a stale attempts section, kept that section: $(cat "$T/$CASE/p2")"
}

# Bug it catches: when the checks after a review fix (checked(): the Done-when check and its own fix) blocked the
# card, the record lost that fix's approach and the judge's reasons, as cardfix() wrote the entry only after them.
t_attemptscheck() {
  att_wt
  ACHECK=1 att_fix 1 'APPROACH-ONE' "$ATTJUDGE" "$T/$CASE/p1"
  [ "$(jq -c 'select(.kind == "fix") | [.card, .round, .approach, .outcome, .findings]' "$ST/attempts/7.jsonl" 2>/dev/null)" \
    = '["c7",1,"APPROACH-ONE","review 1 said NO-GO",[{"id":"E1","reason":"JUDGE-ONE: the flag is set before the lock"}]]' ] \
    || fail "a review fix of #7 (reply APPROACH-ONE, E1 kept by the judge for JUDGE-ONE) whose checks blocked the card left no fix entry with both: $(cat "$ST/attempts/7.jsonl" 2>&1)"
}

# Bug it catches: the failure after the last Test-step fix round blocked the card with no testfix entry, and the block
# entry held only the end of the output, not the failing cases. The fixture is redcycle() (redcycle.test.sh): card cA
# at its last fix round (tfix TESTFIXES) fails its own case again; block() is stubbed to make the call to
# blockattempt() it makes, as the real one also posts, moves and records the card's evidence.
t_attemptstestblock() {
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  redcycle 'a.test: one' '{"files": [{"file": "a.test", "cases": [{"name": "one"}]}]}' \
    'tfix=$TESTFIXES; echo "TESTFIXES=$TESTFIXES"; keepbody() { :; }; block() { blockattempt "$(attemptkey "$2" "$1")" "$1" "$3" "$4"; echo "blocked: $4" | head -n 1; }
    jq -cn "{type: \"result\", result: \"LAST-FIX-REPLY\"}" > "$wt.out"; printf "%s\n" "not ok 1 one" "TEST-TAIL" > "$wt.test"'
  grep -q '^blocked: the changed tests failed again' "$T/$CASE/run.out" || fail "cA at its last Test-step fix round did not block: $(tr '\n' '|' < "$T/$CASE/run.out")"
  [ "$(jq -sc --argjson t "$(sed -n 's/^TESTFIXES=//p' "$T/$CASE/run.out")" \
    'map([.kind, .round, .approach, (.tests | contains("- a.test: one") and contains("TEST-TAIL"))]) == [["testfix", $t + 1, "LAST-FIX-REPLY", true], ["block", 0, "LAST-FIX-REPLY", true]]' "$ST/attempts/cA.jsonl" 2>&1)" = true ] \
    || fail "the failure of a.test: one after cA's last fix round did not write a testfix entry then a block entry, each with the case: $(cat "$ST/attempts/cA.jsonl" 2>&1)"
}

# Bug it catches: a card with no GitHub issue given back by `retry <card id>` (a new card, issue 0) was told nothing
# of the attempts of the card before it: their record was under the old card id, and its brief read no record.
t_attemptsgivenback() {
  setup '[]'
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  FXWT=$T/$CASE/none fx_in 'mkdir -p "${TACARDS%/*}" && echo "{\"cards\": [{\"id\": \"p1\", \"card\": \"cOLD-0\"}]}" > "$TACARDS" || exit 3
    attempt "$(attemptkey 0 cOLD-0)" "{\"card\": \"cOLD-0\", \"kind\": \"block\", \"outcome\": \"OLD-BLOCK\"}" || exit 3
    echo "{\"cards\": [{\"id\": \"p1\", \"card\": \"cNEW-0\", \"was\": [\"cOLD-0\"]}]}" > "$TACARDS" || exit 3
    carried 0 "$CARDS/none" cNEW-0 > "$T/$CASE/brief"; fixprompt "card prompt" "E1 x" "" "$(attemptkey 0 cNEW-0)" > "$T/$CASE/fix"'
  [ "$RC" = 0 ] || fail "the record of cOLD-0 could not be written or read: $(cat "$T/$CASE/run.out")"
  grep -qxF 'Outcome: OLD-BLOCK' "$T/$CASE/brief" && grep -qxF 'Outcome: OLD-BLOCK' "$T/$CASE/fix" \
    || fail "card cNEW-0, given back from cOLD-0 (blocked: OLD-BLOCK), lacks that attempt in its brief or its fix prompt: $(cat "$T/$CASE/brief" "$T/$CASE/fix")"
}

# Bug it catches: a retry's brief named a round's diff beside the old worktree after block() had moved it to the
# card's kept folder, or `retry --fresh` on to kept-dropped. A diff is named where it is now, and not when it is gone.
t_attemptsdiff() {
  setup '[]'
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  FXWT=$T/$CASE/none fx_in 'mkdir -p "$ST/kept/cK-7/cK-7.rounds" "$ST/kept-dropped/20260101T000000Z-7/cD-7/cD-7.rounds" && touch "$ST/kept/cK-7/cK-7.rounds/1.diff" "$ST/kept-dropped/20260101T000000Z-7/cD-7/cD-7.rounds/2.diff" || exit 3
    for e in cK-7:1 cD-7:2 cG-7:3; do attempt 7 "{\"card\": \"${e%:*}\", \"round\": ${e#*:}, \"kind\": \"fix\", \"diff\": \"$CARDS/${e%:*}.rounds/${e#*:}.diff\"}" || exit 3; done
    attempts 7 > "$T/$CASE/out"'
  [ "$RC" = 0 ] || fail "the entries could not be written or read: $(cat "$T/$CASE/run.out")"
  [ "$(grep '^Diff: ' "$T/$CASE/out" | tr '\n' ,)" = "Diff: $ST/kept-dropped/20260101T000000Z-7/cD-7/cD-7.rounds/2.diff,Diff: $ST/kept/cK-7/cK-7.rounds/1.diff," ] \
    || fail "the diffs of cK-7 (in kept), cD-7 (in kept-dropped) and cG-7 (gone) are not named where they are now: $(cat "$T/$CASE/out")"
}

# Bug it catches: a Test-step fix was told nothing of the earlier attempts, and its failure was recorded nowhere. The
# fixture is redcycle() (redcycle.test.sh): cardfailed() of card cA, its own case failing, goes to a fix round. Its
# prompt (the real testfixprompt()) holds the entry written before; the entry of this failure, written after the
# prompt was made, holds the reply of the session whose change failed, the exit and the failing case.
t_attemptstestfix() {
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  redcycle 'a.test: one' '{"files": [{"file": "a.test", "cases": [{"name": "one"}]}]}' \
    'eval "$(sed -n "/^testfixprompt() {/,/^}/p" "'"$SRC"'/lib/card.sh")"; session() { printf "%s\n" "$2" > "$T/$CASE/prompt"; echo "a fix session ran" >&2; }
    attempt cA "{\"card\": \"cZ\", \"kind\": \"block\", \"outcome\": \"EARLIER-BLOCK\"}" || exit 3
    jq -cn "{type: \"result\", result: \"BUILD-REPLY: changed the guard\"}" > "$wt.out"; printf "%s\n" "not ok 1 one" "TEST-TAIL" > "$wt.test"'
  fixround "failing a.test: one, with an earlier attempts entry"
  grep -qxF 'Outcome: EARLIER-BLOCK' "$T/$CASE/prompt" || fail "the Test-step fix prompt lacks the earlier attempts entry: $(cat "$T/$CASE/prompt" 2>&1)"
  ! grep -qF 'BUILD-REPLY' "$T/$CASE/prompt" || fail "the Test-step fix prompt holds the entry of its own failure, which it gives whole: $(cat "$T/$CASE/prompt")"
  [ "$(jq -c 'select(.kind == "testfix") | [.card, .round, .approach, .outcome, (.tests | contains("- a.test: one") and contains("TEST-TAIL"))]' "$ST/attempts/cA.jsonl")" \
    = '["cA",1,"BUILD-REPLY: changed the guard","the changed tests failed (exit 1)",true]' ] \
    || fail "the failed Test step of cA (exit 1, a.test: one) wrote no testfix entry with the build's reply, the exit and the case: $(cat "$ST/attempts/cA.jsonl" 2>&1)"
}

# Bug it catches: `retry --fresh` dropped the block reason with the kept work, so the next card started knowing nothing
# of what failed. block() writes the block entry of #7's card; the retry keeps the record, adds the line naming
# kept-dropped/<folder>/<card>, and the next card's brief (carried()) holds both, beside the attempt recorded before.
t_attemptsfresh() {
  local b d why l
  setup "[$(issue 7 2026-01-01)]"; echo 'echo seven >> a.txt; exit 3' > "$STUB/build"
  FXWT=$T/$CASE/none fx_in 'attempt 7 "{\"card\": \"c0-7\", \"round\": 1, \"kind\": \"fix\", \"approach\": \"EARLIER-APPROACH\", \"outcome\": \"review 1 said NO-GO\"}"'
  [ "$RC" = 0 ] || fail "the earlier entry could not be written: $(cat "$T/$CASE/run.out")"
  # loop: a real card of #7 blocked with kept work, as block() writes its entry and moves its evidence, which retry --fresh then moves
  loop run >/dev/null
  b=$(st 'select(.issue == 7 and .step == "blocked") | .card'); why=$(st 'select(.issue == 7 and .step == "blocked") | .reason')
  [ -n "$b" ] && [ -d "$ST/kept/$b" ] || fail "#7 was not blocked with kept work: $(st 'select(.issue == 7) | .step' | tr '\n' ,)"
  loop retry 7 --fresh >/dev/null || fail "retry 7 --fresh exited non-zero"
  d=$(ls -d "$ST"/kept-dropped/*-7 2>/dev/null) && [ -d "$d/$b" ] || fail "retry --fresh did not move $b's kept work: $(ls -R "$ST/kept-dropped" 2>&1)"
  FXWT=$T/$CASE/none fx_in 'carried 7 "$CARDS/none" > "$T/$CASE/brief"'
  for l in "## fresh of card $b" "Outcome: retry --fresh moved the kept work to ${d#"$ST"/}/$b; this record stays" "## block of card $b" "Outcome: ${why:0:200}" 'Approach: EARLIER-APPROACH'; do
    grep -qF -- "$l" "$T/$CASE/brief" || fail "the brief after retry --fresh of #7 (blocked: '$why') lacks '$l': $(cat "$T/$CASE/brief")"
  done
}

# Bug it catches: a follow-up card did not say how many fix rounds its finding had already beaten, nor how. Its body
# (followups()) gets one line from its parent's record: the fix rounds and the last approach, its newlines as spaces.
t_attemptsfollowup() {
  setup "[$(issue 7 2026-01-01)]"
  printf '%s\n' '[P2] a.txt:1 the word is wrong' 'VERDICT: NO-GO' > "$STUB/r.review"
  jq -cn '{number: 7, title: "t", body: "b", labels: [], milestone: null}' > "$STUB/parent.json" || fail "the parent's JSON could not be written"
  FXWT=$T/$CASE/none fx_in 'attempt 7 "{\"card\": \"c7\", \"round\": 1, \"kind\": \"fix\", \"approach\": \"first try\"}" && attempt 7 "{\"card\": \"c7\", \"round\": 2, \"kind\": \"fix\", \"approach\": \"second\\ntry\"}" \
    && attempt 7 "{\"card\": \"c7\", \"kind\": \"testfix\", \"round\": 1}" && followups c7 "$(cat "$STUB/parent.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && jq -e -s 'length == 1 and (.[0].body | split("\n") | index("Earlier attempts: 2 fix rounds on #7; last approach: second try") != null)' "$STUB/filed" > /dev/null \
    || fail "the follow-up of c7 (two fix rounds, the last approach 'second\\ntry') lacks the line of its parent's attempts (exit $RC): $(cat "$T/$CASE/run.out") $(cat "$STUB/filed" 2>&1)"
}

# Bug it catches: a record of long entries filled the brief. Each line is cut to its fields' limits when written, and
# attempts() prints the last 3, newest first, in 4000 characters at most with its end line kept.
t_attemptslimit() {
  local o s
  setup '[]'
  for s in 1 2 3 4 5; do
    jq -cn --arg i "$s" '{card: "c\($i)-9", round: ($i | tonumber), kind: "fix", approach: ("A" * 900), outcome: ("O" * 900),
      findings: [range(7) | {id: "E\(.)", reason: ("R" * 500)}], tests: ("T" * 3000), diff: "d"}'
    jq -cn --arg i "$s" '{card: "c\($i)-8", kind: "block", outcome: "short \($i)"}'
  done > "$T/$CASE/in"
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  FXWT=$T/$CASE/none fx_in 'while read -r a && read -r b; do attempt 9 "$a" && attempt 8 "$b" || exit 3; done < "$T/$CASE/in"; attempts 9 > "$T/$CASE/out9"; attempts 8 > "$T/$CASE/out8"'
  [ "$RC" = 0 ] || fail "the entries could not be written or read: $(cat "$T/$CASE/run.out")"
  [ "$(jq -sc 'map([(.approach | length), (.outcome | length), (.findings | length), (.findings | map(.reason | length) | max), (.tests | length)]) | unique' "$ST/attempts/9.jsonl")" = '[[600,400,5,300,2000]]' ] \
    || fail "an entry was not cut to its limits (approach 600, outcome 400, 5 findings of 300, tests 2000): $(head -c 600 "$ST/attempts/9.jsonl")"
  o=$(cat "$T/$CASE/out9")
  [ "${#o}" -le 4000 ] && [ "${o##*$'\n'}" = '# End of the earlier attempts' ] && ! grep -qF 'card c1-9' <<<"$o" \
    || fail "attempts of 5 long entries printed ${#o} characters, or an entry older than the last 3, or lost its end line: ${o:0:300} ... ${o: -200}"
  # Also catches: the newest long entry filled the room, so the two before it were not shown at all.
  [ "$(grep -o '^## fix round [0-9] of card c[0-9]-9' <<<"$o" | tr '\n' ,)" = '## fix round 5 of card c5-9,## fix round 4 of card c4-9,## fix round 3 of card c3-9,' ] \
    && [ "$(grep -c '^Approach: AAAA' <<<"$o")" = 3 ] \
    || fail "attempts of 5 long entries did not show each of the last 3, newest first, each with its approach: ${o:0:300} ... ${o: -200}"
  [ "$(grep -o '^## block of card c[0-9]-8' "$T/$CASE/out8" | tr '\n' ,)" = '## block of card c5-8,## block of card c4-8,## block of card c3-8,' ] \
    || fail "attempts of 5 short entries did not print the last 3, newest first: $(cat "$T/$CASE/out8")"
}

# Bug it catches: a record outlived its issue, so a later card of it was told of attempts on a change that had landed.
# The record of #7 goes when #7's card lands; until then its build brief (carried()) holds it.
t_attemptsland() {
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"
  FXWT=$T/$CASE/none fx_in 'attempt 7 "{\"card\": \"c0-7\", \"kind\": \"block\", \"outcome\": \"EARLIER-BLOCK\"}"'; [ "$RC" = 0 ] || fail "the entry could not be written: $(cat "$T/$CASE/run.out")"
  # loop: a real landing of #7, as only landone() (lib/claim.sh) ends the record
  loop run >/dev/null
  [ -n "$(st 'select(.issue == 7 and .step == "landed") | .card')" ] || fail "#7 did not land: $(st 'select(.issue == 7) | .step' | tr '\n' ,)"
  grep -qxF 'Outcome: EARLIER-BLOCK' "$STUB/brief" || fail "the build brief of #7 lacks its attempts record: $(head -c 2000 "$STUB/brief")"
  [ ! -e "$ST/attempts/7.jsonl" ] || fail "#7 landed and its attempts record is still there: $(cat "$ST/attempts/7.jsonl")"
}
