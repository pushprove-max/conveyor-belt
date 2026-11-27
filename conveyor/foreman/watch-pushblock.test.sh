#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, on a push blocked by its check (health pushError, kind check): one
# poll (--once) at a time of a snapshot given by CONVEYOR_FOREMAN_ASK, the clock set by CONVEYOR_FOREMAN_NOW. Each case
# has a Foreman folder of its own.
# Bug (issue 1683): each landing after a blocked push is a new commit, so a new wake, and the wake for the same block
# (same check, same error, the next card's name) read as a new block; and nothing told the Foreman when the push went
# through, so its next reply could not say so.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0 NOW=$(date +%s) M=$T/alpha
export HOME=$T/home XDG_CONFIG_HOME=$T/config
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CLAUDE_PROJECT_DIR
mkdir -p "$HOME" "$XDG_CONFIG_HOME/conveyor" && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
  && git init -q "$M" && mkdir -p "$M/.conveyor" && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
  || { echo "FAIL [watch-pushblock]: the fixture was not made" >&2; exit 1; }
# A snapshot of the case <case> whose push failed its check <check> on commit <sha> after issue <issue>, the hook's
# test failing at <where> (the failat line lib/push.sh puts in the reason; with none, the reason has no failat line and
# the same output each time), its fix card needing the owner or not, the push's time limit <limit> seconds; with no
# sha, the push works. A card on the belt, so the record is not idle. Each has a health time of its own.
SNAPN=0
snap() { # <case> [<sha> <issue> <check> <where> <needsYou> <limit>]
  SNAPN=$((SNAPN + 1))
  jq -cn --argjson n "$SNAPN" --arg s "${2-}" --arg i "${3-0}" --arg c "${4-}" --arg w "${5-}" --arg y "${6-true}" --arg l "${7-900}" '(1762862400 + 60 * $n | todate) as $t
    | {belt: [{card: "x"}], queue: {next: []}, health: {time: $t, loop: true, gh: true, ghReached: true, state: "running", reason: null,
      stuck: [], waiting: [], blocked: [],
      pushError: (if $s == "" then null else {time: $t, sha: $s, kind: "check", check: $c, card: "c\($i)", issue: ($i | tonumber),
        reason: "exit 1 (124 is the \($l)s timeout): \(if $w == "" then "" else "run \($n): " end)\($c) FAILED \($c)\(if $w == "" then "" else "\nconveyor: a test of the hook failed at \($w)" end)",
        fix: {card: "cfix", issue: 0, state: "blocked", needsYou: ($y == "true")}} end),
      pushFailingSince: (if $s == "" then null else "2025-11-11T12:00:00Z" end)}}' > "$T/$1.snap"
}
# One poll of the case's Foreman, <n> polls after the first; 0 with a wake put in pending, which wake holds.
poll() { # <case> <n>
  local fd=$T/$1/foreman; rm -f "$fd"/pending/*.wake; wake=
  CONVEYOR_FOREMAN_DIR=$fd CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_NOW=$((NOW + 60 * $2)) CONVEYOR_FOREMAN_ASK="cat $T/$1.snap" \
    bash "$SRC/watch-conveyor.sh" --once 2>> "$T/$1.err" || return
  wake=$(cat "$fd"/pending/*.wake)
}
check() { if "${@:3}"; then echo "ok [watch-pushblock]: $2"; else echo "FAIL [watch-pushblock]: $2: ${wake:-no wake} $(cat "$T/$1.err" 2>/dev/null)" >&2; fails=$((fails + 1)); fi; }

S1=1111111111111111111111111111111111111111 S2=2222222222222222222222222222222222222222 S3=3333333333333333333333333333333333333333
# Two blocks with the same check and the same failing test (the hook's output around it differs): the second wake names
# the first as a repeat. A third with the same check failing at another test is a new block, named as no repeat.
repeat() {
  snap repeat "$S1" 12 typecheck-web apps/web/a.test.ts:4; poll repeat 0 && grep -qF 'push blocked: typecheck-web failed after #12' <<<"$wake" \
    && ! grep -qF 'repeat' <<<"$wake" || return 1
  snap repeat "$S2" 13 typecheck-web apps/web/a.test.ts:4; poll repeat 1 && grep -qF 'push blocked: typecheck-web failed after #13' <<<"$wake" \
    && grep -qF "the same check and error as the push block of ${S1:0:12} after #12 (since " <<<"$wake" && grep -qF 'a repeat of that block, not a new one' <<<"$wake" || return 1
  snap repeat "$S3" 14 typecheck-web apps/web/b.test.ts:9; poll repeat 2 && grep -qF 'push blocked: typecheck-web failed after #14' <<<"$wake" && ! grep -qF 'repeat' <<<"$wake"
}
check repeat 'a second push block with the same check and error names the first; one with another error does not' repeat

# Bug (review of issue 1683): a hook failure with no failat line was compared by its whole reason, whose time limit
# push.sh sets by the machine's load, so the same failure under another load read as a new block.
load() {
  snap load "$S1" 12 typecheck-web '' true 900; poll load 0 && ! grep -qF 'repeat' <<<"$wake" || return 1
  snap load "$S2" 13 typecheck-web '' true 1350; poll load 1 && grep -qF "the same check and error as the push block of ${S1:0:12} after #12 (since " <<<"$wake"
}
check load 'the same failure with no failat line under another time limit is named a repeat' load

# A woken block whose push then works wakes once, "the push went through", also after a poll while its fix card runs
# (needsYou false: no push line, so the watcher's reported keys drop it); a block that never woke (its fix card left the
# owner nothing to do) wakes nothing when it clears. Bug caught (review of issue 1683): the clear looked only at the
# reported keys, so the poll while the fix card ran lost the wake that the push went through.
through() {
  snap through "$S1" 12 typecheck-web apps/web/a.test.ts:4; poll through 0 || return 1
  snap through "$S1" 12 typecheck-web apps/web/a.test.ts:4 false; ! poll through 1 || return 1
  snap through; poll through 2 && grep -qF 'the push went through: the push block of typecheck-web failed after #12' <<<"$wake" || return 1
  ! poll through 3 || return 1
  snap through "$S2" 13 typecheck-web apps/web/a.test.ts:4 false; ! poll through 4 || return 1
  snap through; ! poll through 5
}
check through 'a woken push block that clears wakes once that the push went through; one never woken wakes nothing' through

[ "$fails" = 0 ] || exit 1
echo "ok watch-pushblock" # the pass of the case its FAIL lines name, as the main-red proof reads it
