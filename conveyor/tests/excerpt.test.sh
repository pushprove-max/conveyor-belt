#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the lines a review's findings cite, kept from the tree the review read (#307).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: once the card's worktree is gone the owner cannot read the lines a finding cites, and main may hold other code
# there; an excerpt read from the disk rather than the reviewed tree (a file edited after staging, or a path outside
# the repository); a deleted file's lines lost, as the staged tree no longer has it; a citation of a deleted line kept
# as only the staged line now at that number, or a line a fix round deleted (one HEAD never had) lost from the review
# after that fix; an early line of a big file lost (git ended by SIGPIPE, read as a
# failure under pipefail); a wide range or a long line kept whole. It calls excerpts() alone: no card runs.
t_excerpts() {
  local w=$T/$CASE/w x fx
  mkdir -p "$w" && git -C "$w" init -q && printf '%s\n' one two three > "$w/a.txt" && printf '%s\n' old1 old2 > "$w/gone.txt" \
    && printf '%s\n' m1 m2 m3 > "$w/mid.txt" && seq 1 50 > "$w/long.txt" && seq 1 40000 > "$w/big.txt" \
    && git -C "$w" add -A && git -C "$w" -c user.name=t -c user.email=t@example.com commit -qm base \
    && printf '%s\n' one TWO three > "$w/a.txt" && git -C "$w" rm -q gone.txt && printf '%s\n' "$(printf 'y%.0s' {1..400})" >> "$w/long.txt" \
    && printf '%s\n' m1 m3 > "$w/mid.txt" && printf '%s\n' f1 f2 f3 > "$w/f.txt" && git -C "$w" add -A && fx=$(git -C "$w" write-tree) \
    && printf '%s\n' f1 f3 > "$w/f.txt" && git -C "$w" add -A && echo 'unstaged' > "$w/a.txt" && echo 'outside' > "$T/$CASE/out.txt" \
    || fail "the worktree could not be made"
  # fx: the tree before a fix round, whose fix deleted f2, a line the change added and HEAD never had.
  # The finding on a.txt names it by the worktree's whole path, as a reviewer run there may.
  printf '%s\n' "[P1] $w/a.txt:2 wrong case" '[P1] gone.txt:2 still read' '[P2] ../out.txt:1 outside' "[P2] $T/$CASE/out.txt:1 abs" \
    '[P2] long.txt:45-80 too wide' '[P2] long.txt:51 long line' '[P2] a.txt:9 no such line' '[P1] mid.txt:2 the deleted m2 was needed' \
    '[P3] big.txt:1 early' '[P1] f.txt:2 the fix deleted f2' 'NEW CARD: a.txt:1 is stale' 'VERDICT: NO-GO' > "$w.review"
  # pipefail, as the loop runs with it.
  # shellcheck disable=SC2034 # STE is read by the sourced lib/review.sh
  x=$(set -o pipefail; eval "$(grep -E '^(ROLLOUT|NOTFINDING)=' "$SRC/lib/prompts.sh")"; STE=''; . "$SRC/lib/review.sh"; excerpts "$w" "$fx")
  [ "$(jq -c '.[0]' <<<"$x")" = '{"at":"a.txt:2","side":"new","from":2,"lines":["TWO"]}' ] \
    || fail "the cited line is not the staged one, with its side: $x"
  [ "$(jq -c '.[2] | [.at, .side, .lines]' <<<"$x")" = '["gone.txt:2","old",["old2"]]' ] || fail "a deleted file's line is not kept from the old side: $x"
  [ "$(jq -c '.[3] | [.at, .from, (.lines | length), .lines[0]]' <<<"$x")" = '["long.txt:45-80",45,7,"45"]' ] || fail "a range is not cut at the file's end: $x"
  [ "$(jq -c '.[4] | [.at, (.lines[0] | length)]' <<<"$x")" = '["long.txt:51",300]' ] || fail "a long line is not cut to 300 characters: $x"
  [ "$(jq -c '[.[] | select(.at == "mid.txt:2") | [.side, .lines]]' <<<"$x")" = '[["new",["m3"]],["old",["m2"]]]' ] \
    || fail "a cited deleted line is not kept beside the staged line at its number: $x"
  [ "$(jq -c '[.[] | select(.at == "big.txt:1") | .lines]' <<<"$x")" = '[["1"]]' ] || fail "an early line of a big file is lost: $x"
  [ "$(jq -c '[.[] | select(.at == "f.txt:2") | [.side, .lines]]' <<<"$x")" = '[["new",["f3"]],["fix",["f2"]]]' ] \
    || fail "a review after a fix round lost the line that fix deleted (HEAD never had it): $x"
  [ "$(jq -c 'map(.at)' <<<"$x")" = '["a.txt:2","a.txt:2","gone.txt:2","long.txt:45-80","long.txt:51","mid.txt:2","mid.txt:2","big.txt:1","f.txt:2","f.txt:2"]' ] \
    || fail "a path outside the repository, a line no tree has or a line that is no finding gave lines, or a changed line lost its old side: $x"
  # A range wider than EXCERPTLINES keeps that many lines.
  printf '%s\n' '[P2] long.txt:1-50 all of it' > "$w.review"
  # shellcheck disable=SC2034 # STE is read by the sourced lib/review.sh
  x=$(eval "$(grep -E '^(ROLLOUT|NOTFINDING)=' "$SRC/lib/prompts.sh")"; STE=''; . "$SRC/lib/review.sh"; excerpts "$w")
  [ "$(jq -c '.[0].lines | length' <<<"$x")" = 20 ] || fail "a wide range is kept whole: $x"
  # A finding the judge declined is a DECLINED line (judge step); the Board lists it with its Reviewed lines, so they are
  # kept as for an accepted finding, from the finding's place, never from one the judge's reason names.
  printf '%s\n' '[P1] a.txt:1 kept' 'DECLINED: [P2] mid.txt:2 declined (judge: rare, see long.txt:3)' > "$w.review"
  # shellcheck disable=SC2034 # STE is read by the sourced lib/review.sh
  x=$(eval "$(grep -E '^(ROLLOUT|NOTFINDING)=' "$SRC/lib/prompts.sh")"; STE=''; . "$SRC/lib/review.sh"; excerpts "$w")
  [ "$(jq -c '[.[].at] | unique' <<<"$x")" = '["a.txt:1","mid.txt:2"]' ] \
    || fail "a declined finding's lines are not kept (a DECLINED line was read as no finding), for the review: $(cat "$w.review"): $x"
}

# Bug: the Board reads a card's reviewed lines on demand, as the snapshot leaves them out: history excerpts gives
# another card's, or leaves out which review kept each (its line's time, the Board's review step's at), so an earlier
# review shows a later one's lines at the same place. The reader is called on record lines alone.
t_exdetail() {
  setup '[]'
  jq -c . >> "$ST/cards.jsonl" <<'EOF'
{"card":"c1","issue":5,"step":"review","time":"2026-01-01T00:01:00Z","reason":"","excerpts":[{"at":"a.sh:2","side":"new","from":2,"lines":["x"]}]}
{"card":"c2","issue":6,"step":"review","time":"2026-01-01T00:01:30Z","reason":"","excerpts":[{"at":"b.sh:1","side":"new","from":1,"lines":["y"]}]}
{"card":"c1","issue":5,"step":"fix","reason":""}
{"card":"c1","issue":5,"step":"review","time":"2026-01-01T00:02:00Z","reason":"","excerpts":[{"at":"a.sh:2","side":"new","from":2,"lines":["z"]}]}
EOF
  [ "$(loop history excerpts c1 | jq -c '[.card, (.excerpts | map([.review, .at, .lines[0]]))]')" = '["c1",[["2026-01-01T00:01:00Z","a.sh:2","x"],["2026-01-01T00:02:00Z","a.sh:2","z"]]]' ] \
    || fail "history excerpts does not give the card's reviewed lines with the review that kept each: $(loop history excerpts c1)"
  [ "$(loop history excerpts c9)" = '{"card":"c9","excerpts":[]}' ] || fail "a card with no reviewed lines is not an empty list: $(loop history excerpts c9)"
}
