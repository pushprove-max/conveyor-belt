#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: land-branch, a NO-GO and its fix session, the issue a branch lands as, and refused branches.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Split from branch.test.sh, whose setup (branchsetup) and bugs these cases share, so no one file is over the
# CPU budget (test.fileBudget): its six cases cost about 17 CPU s together.
t_branchfix() {
  branchsetup
  # A NO-GO gets a fix session, then a new review. The branch is named as the engine names a card of issue #7 (its
  # card id): the card is #7's and the commit closes it. Bug (issue 601): taking no number from a branch's name would
  # land it as issue 0.
  lane c20260101T000000-main-7 c.txt sea; echo "$NOGO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"; m=$(git -C "$R" rev-parse main)
  out=$(loop land-branch c20260101T000000-main-7) || fail "a branch whose second review is a GO did not land: $out"
  c=$(newest); count "1 2 1"
  [ "$(steps "$c")" = "picked worktree deps brief start review start fix start review start test start landed " ] &&[ "$(st "select(.card == \"$c\" and .step == \"review\") | .result" | tr '\n' ' ')" = "NO-GO GO " ] \
    || fail "a NO-GO was not followed by a fix session and a new review: $(steps "$c")"
  # Bug (R314 fix, E13): the picked line kept no main commit, so Needs you read what the card was picked to land from
  # main's reflog, by whole seconds. It keeps main's commit the branch was weighed against (base).
  [ "$(st "select(.card == \"$c\" and .step == \"picked\") | [.issue, .branch, .title, .base] | join(\"|\")")" = "7|c20260101T000000-main-7|title 7|$m" ] \
    || fail "the card is not issue #7's, or its picked line does not keep main's commit $m: $(st "select(.card == \"$c\" and .step == \"picked\")")"
  grep -q '# Issue #7: title 7' "$STUB/brief" && grep -q '# This card skipped the build' "$STUB/brief" && grep -q 'wrong word' "$STUB/brief" || fail "the fix session was not handed the issue, the skipped build and the findings"
  git -C "$R" log -1 --format=%B main | grep -q 'feat(billing): title 7 (#7)' && [ "$(git -C "$R" show --name-only --format= main | tr '\n' ' ')" = "a.txt c.txt " ] \
    || fail "the landed commit is not the branch's change plus the fix, under the issue's name: $(git -C "$R" show --name-only --format=%s main | tr '\n' ' ')"
  # Issue #7 has an open card: a branch named as a card of #7 is refused and nothing is recorded.
  lane c20260101T000001-main-7 d.txt dee; n=$(wc -l < "$ST/cards.jsonl")
  line7=$(jq -cn '{card:"c1-7",issue:7,step:"picked",time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}'); echo "$line7" >> "$ST/cards.jsonl"
  out=$(loop land-branch c20260101T000001-main-7 2>&1) && fail "a branch naming an issue with an open card was taken"; grep -q 'issue #7 has a card that is still open' <<<"$out" || fail "open card: $out"
  grep -v '"c1-7"' "$ST/cards.jsonl" > "$STUB/open"; cat "$STUB/open" > "$ST/cards.jsonl"
  [ "$(wc -l < "$ST/cards.jsonl")" = "$n" ] || fail "a refused branch left a line in the card records"
}
t_branchnumber() {
  branchsetup
  # Bug (issue 601): the number at the end of a hand fix's branch was taken as its issue, so hand/snapexec-290 was
  # reviewed against #290, closed as already done, and could have closed #290 on GitHub. With #290 open, the branch
  # hand/fix-290 lands as issue 0, and #290 gets no card, no comment and no close.
  jq -c --argjson i "$(issue 290 2026-01-01 area:billing)" '. + [$i]' "$STUB/issues.json" > "$STUB/i" && mv "$STUB/i" "$STUB/issues.json"
  lane hand/fix-290 e.txt eee; echo "$GO" > "$STUB/review.1"
  out=$(loop land-branch hand/fix-290) || fail "a hand fix whose name ends in a number did not land: $out"
  c=$(newest)
  [ "${c##*-}" = 0 ] && [ "$(st 'select(.step == "picked") | [.issue, .branch, .title] | join("|")')" = "0|hand/fix-290|fix(tooling): hand/fix-290 change" ] \
    || fail "the hand fix is not a card of issue 0: $(st 'select(.step == "picked")')"
  [ "$(steps "$c")" = "picked worktree deps brief start review start test start landed " ] && [ "$(cat "$R/e.txt")" = eee ] || fail "the hand fix did not land: $(steps "$c")"
  ! git -C "$R" log -1 --format=%B main | grep -q '#290' || fail "the landed commit names #290: $(git -C "$R" log -1 --format=%B main)"
  [ -z "$(st 'select(.issue == 290)')" ] && ! grep -qs '^290\b' "$STUB/closed" "$STUB/comments" || fail "issue #290 got a card, a comment or a close"
}
t_branchrefused() {
  branchsetup
  # Refused with nothing recorded: no such branch, main itself, and a branch whose change conflicts with main (which
  # changed a.txt since the branch began).
  echo moved > "$R/a.txt"; git -C "$R" commit -qam 'main moves a.txt'; touch "$ST/cards.jsonl"
  lane clash a.txt other 'fix(tooling): clash' "$init"; n=$(wc -l < "$ST/cards.jsonl"); at=$(git -C "$R" rev-parse main)
  loop land-branch nope >/dev/null 2>&1; [ $? = 2 ] || fail "a missing branch is not exit 2"
  loop land-branch main >/dev/null 2>&1; [ $? = 2 ] || fail "main itself is not exit 2"
  out=$(loop land-branch clash 2>&1); [ $? = 1 ] && grep -q 'does not merge into main' <<<"$out" || fail "a branch that conflicts with main: $out"
  [ "$(wc -l < "$ST/cards.jsonl")" = "$n" ] && [ "$(git -C "$R" rev-parse main)" = "$at" ] && [ -z "$(git -C "$R" status --porcelain)" ] || fail "a refused branch left a record line or touched main"
  loop check || fail "the record check fails after the branch cards"
}
