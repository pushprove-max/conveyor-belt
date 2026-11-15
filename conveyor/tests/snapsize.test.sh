#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the snapshot's size bound (lib/snapshot.sh SNAPKEEP, PUSHKEEP) and `conveyor.sh history`.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug (#524): the snapshot, read by the Board every second, carried every card landed today, every card of the 7 days
# with its measurements, every cost row, unpriced step, push and old declined line, and every land-branch card that
# ever landed (branches): it grew with each landed card (2.8 MB on a busy day) until a reader with a 4 MB cap showed nothing. Each list that grows with landed cards must stay
# at its newest SNAPKEEP (100 for pushes), so the record stays under the bound README.md states (512 KB) however many
# land, and the whole of each list must still be in `conveyor.sh history`, where the Board's panels read the older ones.
t_snapsize() {
  local n=110 out hist d L
  export TZ=UTC; setup "[$(issue 1 2026-01-01)]"; mkdir -p "$ST"; d=$(date -u +%F)
  # 110 cards land-branch made (branches), landed and pushed today, each with a build and a review unpriced (their
  # lines name no model), and 30 declined lines dismissed (declinedRest). The oldest, c1, has its issue still open on
  # GitHub, so it is still on the belt; c3 landed the Fast lane's change (issue 0, titled with the lane's first
  # commit), and the lane was left as it was.
  jq -cn --arg d "$d" --argjson n "$n" 'range(1; $n + 1) as $i | ("\($d)T00:00:00Z" | fromdate) + $i * 10 as $t
    | ["picked", "worktree", "brief", "build", "review", "test", "landed", "pushed"] | to_entries[]
    | {card: "c\($i)", issue: (if $i == 3 then 0 else $i end), step: .value, time: ($t + .key | todate), tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""}
      + {picked: {title: (if $i == 3 then "fix(tooling): lane change" else "landed card \($i) " * 8 end), branch: "lane-\($i)"}, review: {result: "GO"}, test: {result: "pass", sec: 60},
         landed: {sha: "abc\($i)", product: false}, pushed: {sha: "abc\($i)", sec: 5, head: "abc\($i)"}}[.value] // {}' > "$ST/cards.jsonl"
  L=${R%/*}/main-fast-lane
  git -C "$R" worktree add -q -b fast-lane "$L" main && git -C "$L" commit -q --allow-empty -m 'fix(tooling): lane change' || fail "the lane could not be made"
  jq -cn --arg d "$d" 'range(1; 31) as $i | {id: "d\($i)", time: ("\($d)T00:00:00Z" | fromdate) + $i | todate, card: "c\($i)", issue: $i,
    finding: ("[P2] a.txt:\($i) a finding " * 20), by: "code", why: "a reason", repo: "x", dismissed: {time: "\($d)T01:00:00Z", by: "owner"}}' > "$ST/declined.jsonl"
  out=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.landedCount, .landedUsd, (.landed, .metrics.cards, .cost.cards, .cost.unpriced, .declinedRest, .branches, .pushedCards | length)]' <<<"$out")" = '[110,null,21,20,20,20,20,21,100]' ] \
    || fail "the lists of the snapshot are not cut to their newest: $(jq -c '[.landedCount, .landedUsd, (.landed, .metrics.cards, .cost.cards, .cost.unpriced, .declinedRest, .branches, .pushedCards | length)]' <<<"$out")"
  # Past the cut: the landed card still on the belt (else the Board shows it in Building as landed on an earlier day),
  # and the lane's own row (else the Board says the lane's change never landed: dashboard.sh landing()).
  [ "$(jq -c '[.landed[-1].card, (.branches[-1] | [.card, .issue, .title])]' <<<"$out")" = '["c1",["c3",0,"fix(tooling): lane change"]]' ] \
    || fail "the snapshot drops the on-belt landed card or the lane's landing: $(jq -c '[.landed[-1].card, .branches[-1]]' <<<"$out")"
  # The newest of each, never the oldest.
  [ "$(jq -c '[.landed[0].card, .metrics.cards[0].card, .cost.cards[0].card, .declinedRest[0].id, .branches[0].card, .pushedCards[0].card]' <<<"$out")" = '["c110","c110","c110","d30","c110","c110"]' ] \
    || fail "the snapshot keeps other than the newest: $(jq -c '[.landed[0].card, .metrics.cards[0].card, .cost.cards[0].card, .declinedRest[0].id, .branches[0].card, .pushedCards[0].card]' <<<"$out")"
  [ "${#out}" -lt 524288 ] || fail "the snapshot of $n landed cards is ${#out} bytes, over the 512 KB README.md states"
  hist=$(loop history) || fail "history exited non-zero"
  # pushedCards whole too (#544): the Foreman's watcher reads it there for an awaited push past the snapshot's 100.
  [ "$(jq -c '[(.landed, .metrics.cards, .cost.cards, .cost.unpriced, .declinedRest, .pushedCards | length), .landed[-1].card]' <<<"$hist")" = '[110,110,110,220,30,110,"c1"]' ] \
    || fail "history does not hold every entry: $(jq -c '[(.landed, .metrics.cards, .cost.cards, .cost.unpriced, .declinedRest, .pushedCards | length), .landed[-1].card]' <<<"$hist")"
}

# Bug (#530): `conveyor.sh history` on a new state (no history.json yet) takes a snapshot first, and the snapshot's
# tests part reads the test rules (lib/testrules.sh). The history command's script (commands/history.sh) did not load
# that file, so the first history printed shell errors (TESTRULES unset, testrulesettings not found).
t_historyfirst() {
  local hist
  setup "[$(issue 1 2026-01-01)]"; mkdir -p "$ST"
  hist=$(loop history 2> "$T/$CASE/err") || fail "history exited non-zero: $(cat "$T/$CASE/err")"
  [ ! -s "$T/$CASE/err" ] && jq -e 'objects' <<<"$hist" > /dev/null || fail "the first history printed errors or no record: $(cat "$T/$CASE/err")"
}
