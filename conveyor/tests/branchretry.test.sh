#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a blocked land-branch card of a branch that names no issue, given back by `retry <card id>` and named
# by its branch.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# brsetup [keep | drift] [branch, lb if none]: the branch (s.txt "tip", branchsetup() of branch.test.sh) landed by
# land-branch, its card (BRC) blocked by a card() stand-in, as card() blocks it. With keep, the card kept a patch of its
# worktree whose s.txt says "kept", not the tip's "tip": a next card that holds "kept" started from that patch, not
# from the branch again. With drift, main's s.txt is "a b c" (a line each), the branch changes line 3 to "C" and main
# then changes line 1 to "A": the tip still merges cleanly, but the branch's diff against its fork point no longer
# applies to main.
brsetup() {
  local b=${2:-lb}
  branchsetup
  # part: a split part of #7 in the record of the cards with no GitHub issue (PART, its id), its branch named by that
  # id, so land-branch lands it as that part (slicetake()).
  if [ "$b" = part ]; then
    fx_in 'tcadd "" "A part" "Body." "" "Split part of #7" "[]" 7 > /dev/null'
    PART=$(jq -r '.cards[-1].id' "$ST/testactions/cards.json"); b=$PART
    [[ $PART == c*-0 ]] || fail "the split part was not added: $PART $(cat "$T/$CASE/run.out")"
  fi
  if [ "${1:-}" = drift ]; then
    printf 'a\nb\nc\n' > "$R/s.txt" && git -C "$R" add s.txt && git -C "$R" commit -qm 'test: s.txt' && lane "$b" s.txt "$(printf 'a\nb\nC')" \
      && printf 'A\nb\nc\n' > "$R/s.txt" && git -C "$R" commit -qam 'test: main changes line 1' || fail "the drifted branch $b could not be made"
  else
    lane "$b" s.txt tip || fail "branch $b could not be made"
  fi
  if [ "${1:-}" = keep ]; then
    lane kw s.txt kept && git -C "$R" diff --binary main kw > "$T/$CASE/kept.patch" || fail "the kept patch could not be made"
  fi
  fx_in 'card() { local k=""; if [ -s "$T/$CASE/kept.patch" ]; then k=kept/$1; mkdir -p "$ST/$k" && cp "$T/$CASE/kept.patch" "$ST/$k/$1.patch" || return 1; fi
      append "$(line "$1" "$2" blocked fail "$(jq -cn --arg k "$k" "{reason: \"the review found a fault\", kept: \$k}")")"; }; landbranch "'"$b"'"'
  BRC=$(newest)
  [[ $BRC == c*-0 ]] && [ "$(st "select(.card == \"$BRC\") | .step" | tail -n 1)" = blocked ] || fail "land-branch $b did not leave a blocked card of issue 0: $(cat "$T/$CASE/run.out")"
}
# brnext: the pick takes the card given back as a new card (its id printed), and resumeplan() (lib/card.sh), as card()
# calls it on that card's new worktree, prints its mode and the s.txt it staged (its lines joined by spaces).
brnext() {
  fx_in 'read -r c n _ <<<"$(locked pick "" "" "[]")" && [ "$n" = 0 ] || { echo "pick took ${c:-nothing}"; exit 3; }
    echo "$c"; br="" wt=$T/$CASE/wt vrule=on heldto="" inh="" mode="" from=""
    git worktree add -q --detach "$wt" "refs/heads/$BRANCH" && issue=$(testcardissue "$c") && resumeplan || exit 4
    echo "$mode $from $(git -C "$wt" show :s.txt 2>&1 | paste -sd " " -)"'
  [ "$RC" = 0 ] || fail "the next card of $BRC could not be picked or resumed (exit $RC): $(cat "$T/$CASE/run.out")"
}

# #1673 D1. Bug it catches: `retry <card id>` refused a blocked land-branch card of issue 0 ("no main-red fix card and
# no card with no GitHub issue"), `retry 0` did not list it, and no card ever started from its kept work: the owner
# had to shut it and land the branch again, reviewed from the start. Now `retry 0` names it by its branch, `retry
# <card id>` gives it back, the loop's pick takes it again as a new card named by its branch, and that card starts
# from the kept patch ("kept"), not from the branch's tip ("tip").
t_branchretry() {
  local out c2
  brsetup keep
  out=$(loop retry 0 2>&1); grep -qF "blocked now: $BRC (Branch: lb)" <<<"$out" || fail "retry 0 does not name the blocked land-branch card $BRC by its branch: $out"
  # A fast lane holding another change: retry checks branch lb against it (laneheld(), lanein()), which reads main's
  # name. Bug it catches: retry read no pack names first, so it stopped with "BRANCH: unbound variable", and the
  # entry's brief (branchissue()) lost the branch's commit messages.
  lane fast-lane f.txt lane || fail "the fast lane could not be made"
  out=$(loop retry "$BRC" 2>&1) && [ -z "$(st "select(.card == \"$BRC\")")" ] || fail "retry $BRC (fast-lane present) did not give back the blocked land-branch card: $out"
  jq -e 'any(.cards[]; .label == "Branch: lb" and (.body | contains("fix(tooling): lb change")))' "$ST/testactions/cards.json" > /dev/null \
    || fail "retry $BRC: the entry of branch lb does not carry its commit message fix(tooling): lb change: $(cat "$ST/testactions/cards.json")"
  brnext; c2=$(head -n 1 "$T/$CASE/run.out")
  [ "$c2" != "$BRC" ] && [ "$(st "select(.card == \"$c2\" and .step == \"picked\") | [.issue, .noIssue] | @json")" = '[0,"Branch: lb"]' ] \
    || fail "after retry $BRC, the pick did not take it again as a new card named Branch: lb: $(cat "$T/$CASE/run.out") $(st 'select(.step == "picked")')"
  [ "$(sed -n 2p "$T/$CASE/run.out")" = "session $BRC kept" ] \
    || fail "the next card $c2 of $BRC did not start from its kept patch (want: session $BRC kept): $(cat "$T/$CASE/run.out")"
  # Bug it catches (#1673 review follow-up): the entry `retry` added had no labels, so the next card's stand-in issue
  # (testcardissue()) got the pack's type label, unlike the first landing (branchissue(): none), and cardbuild() then
  # held the branch's change to a bug fix's proof (bugproof()).
  fx_in 'testcardissue "'"$c2"'" | jq -c .labels'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[]' ] \
    || fail "the stand-in issue of card $c2, given back from land-branch card $BRC, has labels (want [], as the first landing had): $(cat "$T/$CASE/run.out")"
}

# #1673, its Cause: with no kept patch, `retry <card id>` keeps the branch's change as the card's patch, so the next
# card lands the branch's tip merged into main, as land-branch squash-merges it, main's own change since the fork kept.
# Bugs it catches: the next card had no kept work and was built from nothing against the branch's commit messages;
# and the patch kept was the branch's diff against its fork point, whose context main had changed, so the next card
# took the port path with nothing staged though the tip merges cleanly.
t_branchretrytip() {
  local out
  brsetup drift
  out=$(loop retry "$BRC" 2>&1) || fail "retry $BRC of a land-branch card with no kept patch failed: $out"
  brnext
  [ "$(sed -n 2p "$T/$CASE/run.out")" = "session $BRC A b C" ] \
    || fail "the next card of $BRC, which kept no patch, did not start from branch lb's tip merged into main (want: session $BRC A b C): $(cat "$T/$CASE/run.out")"
}

# #1673, review E3. Bug it catches: a split part landed by hand (its branch named as the part's id: slicetake() makes
# the landing card the entry's card) that blocked with no kept patch was given back with no patch at all, as retry
# left a card the record already held as it was: the part's next card was built from nothing, not from the branch.
t_branchretryslice() {
  local out
  brsetup "" part
  jq -e --arg p "$PART" --arg c "$BRC" 'any(.cards[]; .id == $p and .card == $c)' "$ST/testactions/cards.json" > /dev/null \
    || fail "land-branch $PART did not land as split part $PART (its entry's card is not $BRC): $(cat "$ST/testactions/cards.json")"
  out=$(loop retry "$BRC" 2>&1) || fail "retry $BRC of the hand-landed split part $PART failed: $out"
  brnext
  [ "$(sed -n 2p "$T/$CASE/run.out")" = "session $BRC tip" ] \
    || fail "the next card of split part $PART, whose landing card $BRC kept no patch, did not start from its branch's tip (want: session $BRC tip): $(cat "$T/$CASE/run.out")"
}

# #1673, review E1. Bug it catches: `retry <card id>` queued a blocked landing of the fast lane's branch from a Foreman
# session, which land-branch itself refuses there (owneronly()): the lane's change lands on the owner's command alone.
t_branchretrylane() {
  local out
  brsetup "" fast-lane
  out=$(CONVEYOR_FOREMAN=1 loop retry "$BRC" 2>&1); [ $? != 0 ] && grep -qF "the owner's alone" <<<"$out" \
    || fail "retry $BRC (CONVEYOR_FOREMAN=1) of the blocked fast-lane landing was not refused as the owner's alone: $out"
  [ "$(st "select(.card == \"$BRC\") | .step" | tail -n 1)" = blocked ] && ! grep -qF "$BRC" "$ST/testactions/cards.json" 2>/dev/null \
    || fail "retry $BRC (CONVEYOR_FOREMAN=1) was refused but still gave the card back: $(st "select(.card == \"$BRC\")") $(cat "$ST/testactions/cards.json" 2>&1)"
}

# #1673 D2. Bug it catches: Needs you and `foreman status` named a blocked land-branch card of issue 0 "#0", which
# `retry 0` refuses. Health's blocked list names it "Branch: lb", and the Foreman's status (watch-conveyor.sh --status)
# shows that name with its card id, read from the engine's own snapshot.
t_branchneeds() {
  local snap out h
  brsetup
  snap=$T/$CASE/snap.json; loop snapshot --fresh > "$snap" || fail "the snapshot failed"
  h=$(jq -c --arg c "$BRC" '[.health.blocked[] | select(.card == $c) | .name]' "$snap")
  [ "$h" = '["Branch: lb"]' ] || fail "health's blocked list does not name card $BRC Branch: lb: $h"
  # The Board's Needs you reads its cards' names from needsYou.blocked (rows.jq row()), not from health.
  h=$(jq -c --arg c "$BRC" '[.needsYou.blocked[] | select(.card == $c) | .name]' "$snap")
  [ "$h" = '["Branch: lb"]' ] || fail "the Board's Needs you (needsYou.blocked) does not name card $BRC Branch: lb: $h"
  mkdir -p "$T/$CASE/xdg/conveyor" && jq -n --arg m "$R" '{records: [{repo: "alpha", main: $m}]}' > "$T/$CASE/xdg/conveyor/host.json" || fail "the host file could not be written"
  out=$(XDG_CONFIG_HOME=$T/$CASE/xdg CONVEYOR_FOREMAN_DIR=$T/$CASE/foreman CONVEYOR_FOREMAN_ASK="cat $snap" CONVEYOR_MAIN=$R bash "$SRC/foreman/watch-conveyor.sh" --status 2>&1)
  grep -qF "Branch: lb (card $BRC)" <<<"$out" && ! grep -qF '#0' <<<"$out" \
    || fail "foreman status (watch-conveyor.sh --status on the snapshot of blocked card $BRC) does not name it Branch: lb (card $BRC), or says #0: $out"
}
