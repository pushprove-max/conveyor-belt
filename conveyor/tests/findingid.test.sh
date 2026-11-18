#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the id a review finding keeps across fix rounds (lib/testrun.sh numbered(), rounded(), repeats()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A finding was the same as an earlier one only when its first file:line and first six words were: lines added above
# the defect, or other words, made it look new after a fix that did not hold, and a finding whose lines the fix
# replaced was joined to whatever code now sat at that line. Each case calls the engine's own functions, as card.sh
# calls them around one fix round, on a worktree whose fix is a real git diff; no card runs.
# fid_eng runs engine functions in a subshell with lib/testrun.sh and the engine's NOTFINDING (and ROLLOUT, which it reads). fid_round makes the
# worktree $W, a.txt holding "line 1" to "line 20", and gives the first review's findings their ids (IDS) and the
# lines its fix session is told (FL); the edit is fix round 1, its git diff recorded with those ids; then the second
# review is written beside $W.
fid_eng() { # <commands>
  # shellcheck disable=SC2034 # STATE is read by the sourced lib/testrun.sh (SUITERUNS=${STATE%/*}/...)
  ( STATE=$T/$CASE/cards.jsonl; eval "$(grep -E '^(ROLLOUT|NOTFINDING)=' "$SRC/lib/prompts.sh")"; . "$SRC/lib/testrun.sh"
    stdb() { :; }; REREVIEW='' REREVIEWALL=''; eval "$1" )
}
fid_round() { # <first review> <fix edit (a command run in the worktree)> <second review> [more files (a command run in the worktree)]
  W=$T/$CASE/w; mkdir -p "$W" "$W.rounds"
  git -C "$W" init -q && seq 1 20 | sed 's/^/line /' > "$W/a.txt" && (cd "$W" && eval "${4:-:}") && git -C "$W" add -A \
    && git -C "$W" -c user.name=t -c user.email=t@example.com commit -qm a || fail "the worktree could not be made"
  local old; old=$(git -C "$W" write-tree)
  printf '%s\n' "$1" 'VERDICT: NO-GO' > "$W.review"
  IDS=$(fid_eng 'numbered "$W"') && [ -n "$IDS" ] && FL=$(fid_eng 'fixlines "$W" "$IDS"') || fail "the first review's findings were not numbered: $IDS"
  (cd "$W" && eval "$2") && git -C "$W" add -A && git -C "$W" diff "$old" "$(git -C "$W" write-tree)" > "$W.rounds/1.diff" \
    && fid_eng 'rounded "$W" 1 "$IDS"' || fail "fix round 1 could not be recorded"
  printf '%s\n' "$3" 'VERDICT: NO-GO' > "$W.review"
}

# Bug: two lines added above the defect gave the same finding a new key, so it came back as new after its fix.
t_fidmoved() {
  fid_round '[P1] a.txt:10 the guard is wrong. Proof: line 10 reads x' '{ printf "new 1\nnew 2\n"; cat a.txt; } > a.new && mv a.new a.txt' \
    '[P1] a.txt:12 the guard is wrong. Proof: line 12 still reads x'
  [ "$(jq -r '[.id, .moved] | join(" ")' "$W.rounds/findings.jsonl")" = 'E1 a.txt:12' ] || fail "the finding's location was not followed through the diff: $(cat "$W.rounds/findings.jsonl")"
  grep -qx '  The fix moved its location to a.txt:12.' <<<"$(fid_eng 'rereview c "$W" 1')" || fail "the next review was not told where the finding is now"
  local rep; rep=$(fid_eng 'repeats "$W"')
  [ "$(jq -r '[.id, .rounds, .before] | join("|")' <<<"$rep")" = 'E1|1|[P1] a.txt:10 the guard is wrong. Proof: line 10 reads x' ] \
    || fail "a finding whose lines moved was not known as the one its fix round was told: $rep"
  # Recorded for the next round, it keeps its id and its first location and proof beside the later answer.
  IDS=$(fid_eng 'numbered "$W"'); : > "$W.rounds/2.diff"; fid_eng 'rounded "$W" 2 "$IDS"'
  [ "$(jq -sc 'map(select(.round == 2) | [.id, .line, .first.at, .first.line])' "$W.rounds/findings.jsonl")" \
    = '[["E1","[P1] a.txt:12 the guard is wrong. Proof: line 12 still reads x","a.txt:10","[P1] a.txt:10 the guard is wrong. Proof: line 10 reads x"]]' ] \
    || fail "the later record lacks the finding's id or its first location and proof: $(cat "$W.rounds/findings.jsonl")"
}

# Bug: a reviewer that worded the finding again, at another line, made it a new finding; its id names it, and the fix
# session is given that id.
t_fidreworded() {
  fid_round $'[P2] a.txt:5 a nit here\n[P1] a.txt:9 another bug' 'echo more >> a.txt' '[P2] [E1] a.txt:6 The name still reads badly. Proof: line 6'
  grep -qx 'E1 \[P2\] a.txt:5 a nit here' <<<"$FL" && grep -qx 'E2 \[P1\] a.txt:9 another bug' <<<"$FL" || fail "the fix session is not given the findings' ids: $FL"
  local rep; rep=$(fid_eng 'repeats "$W"')
  [ "$(jq -r '[.id, .level, .before] | join("|")' <<<"$rep")" = 'E1|P2|[P2] a.txt:5 a nit here' ] || fail "a reworded finding with its id was not the same finding: $rep"
  [ "$(fid_eng 'numbered "$W"' | jq -r .id)" = E1 ] || fail "the reworded finding did not keep its id"
}

# Bug: a fix that replaced the finding's line left its key on that line, so a later finding there, about other code,
# was joined to it silently.
t_fidreplaced() {
  fid_round '[P1] a.txt:7 bad value. Proof: line 7' 'awk "NR == 7 {\$0 = \"something else\"} 1" a.txt > a.new && mv a.new a.txt' '[P1] a.txt:7 bad value. Proof: the new line 7'
  [ "$(jq -c '[.id, .location, .moved, .line]' "$W.rounds/findings.jsonl")" = '["E1","needs review",null,"[P1] a.txt:7 bad value. Proof: line 7"]' ] \
    || fail "a finding whose lines were replaced was not marked, or lost its first evidence: $(cat "$W.rounds/findings.jsonl")"
  grep -q '^  Its location needs review' <<<"$(fid_eng 'rereview c "$W" 1')" || fail "the next review was not told the location needs review"
  [ -z "$(fid_eng 'repeats "$W"')" ] && [ "$(fid_eng 'numbered "$W"' | jq -r .id)" = E2 ] || fail "a finding on the replaced line was joined to the earlier one"
}

# Bugs: a review's answers (a finding again, or `EARLIER: E1 holds`) were kept beside the first proof only when
# another fix ran; and a finding the review said holds kept its key from the round before, so when the next fix
# replaced its line, a later finding there, about other code, was joined to it.
t_fidheld() {
  fid_round $'[P1] a.txt:7 bad value. Proof: line 7\n[P2] a.txt:12 a nit' 'true' $'EARLIER: E1 holds\n[P2] [E2] a.txt:12 a nit still. Proof: line 12'
  [ "$(fid_eng 'answers "$W"' | jq -c 'map([.id, .answer, .first.at, .first.line])')" \
    = '[["E2","[P2] [E2] a.txt:12 a nit still. Proof: line 12","a.txt:12","[P2] a.txt:12 a nit"],["E1","holds","a.txt:7","[P1] a.txt:7 bad value. Proof: line 7"]]' ] \
    || fail "the review's answers were not given beside each finding's first location and proof: $(fid_eng 'answers "$W"')"
  # Fix round 2 is told E2 alone, and replaces line 7, E1's.
  local old; old=$(git -C "$W" write-tree); IDS=$(fid_eng 'numbered "$W"')
  (cd "$W" && awk 'NR == 7 {$0 = "other code"} 1' a.txt > a.new && mv a.new a.txt) && git -C "$W" add -A \
    && git -C "$W" diff "$old" "$(git -C "$W" write-tree)" > "$W.rounds/2.diff" && fid_eng 'rounded "$W" 2 "$IDS"' || fail "fix round 2 could not be recorded"
  ! grep -q '^E1 ' <<<"$(fid_eng 'rereview c "$W" 2')" || fail "the review after round 2 was told E1 as a finding round 2 was told to fix"
  printf '%s\n' '[P1] a.txt:7 bad value. Proof: the other code' 'VERDICT: NO-GO' > "$W.review"
  [ "$(fid_eng 'numbered "$W"' | jq -r .id)" = E3 ] && [ -z "$(fid_eng 'repeats "$W"')" ] || fail "a finding on the line that replaced a held finding's was joined to it: $(fid_eng 'numbered "$W"')"
}

# Bug: a finding at README.md:5 followed conveyor/README.md, another file of the same name, when the fix changed
# only that one, so the finding was marked as needing review.
t_fidsamename() {
  fid_round '[P1] README.md:5 wrong text. Proof: line 5' 'awk "NR == 5 {\$0 = \"new\"} 1" sub/README.md > r.new && mv r.new sub/README.md' \
    '[P1] README.md:5 wrong text. Proof: still' 'seq 1 9 > README.md && mkdir sub && cp README.md sub/'
  [ "$(jq -c '[.id, .moved, .location]' "$W.rounds/findings.jsonl")" = '["E1","README.md:5",null]' ] || fail "the finding followed another file of the same name: $(cat "$W.rounds/findings.jsonl")"
}
