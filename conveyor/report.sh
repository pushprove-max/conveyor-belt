#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Conveyor's only readout. For the week and per day: cards landed, tokens, time and the share blocked; then the
# cards that stopped with no closing line (flagged past 5 reviews: no cap stops a card that never gets a GO), the
# blocked cards for the owner (the project pack's owner.name), and findings that want a new card.
# The numbers come from cards.jsonl only. Usage: report.sh
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
STATE=$("$HERE/conveyor.sh" state-dir)/cards.jsonl
"$HERE/conveyor.sh" check
# The pack of main's checkout, found as conveyor.sh finds it.
MAIN=${CONVEYOR_MAIN:-$(cd "$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir)/.." && pwd -P)}
OWNER=$("$HERE/lib/pack.sh" get owner.name "$MAIN/.conveyor/project.json")
since=$(date -u -d '6 days ago' +%F)

# One row per finished card: {day, landed, product, tokens, minutes}. A card's tokens are every step's fresh tokens,
# Claude and Codex; a card with no closing line is not finished and is listed below instead.
# A card that closed its issue as already fixed (closing line `closed`) is counted like a landed one. A card whose
# issue was closed while it was blocked (a closed line after its blocked one) landed nothing: it is counted blocked, at its block.
cards() {
  jq -cs --arg since "$since" 'group_by(.card)[] | (map(select(.step == "landed" or .step == "closed" or .step == "blocked"))
      | if length > 1 and last.step == "closed" and .[-2].step == "blocked" then .[-2] else last end) as $end
    | select($end != null and $end.time[0:10] >= $since)
    | {day: $end.time[0:10], landed: ($end.step != "blocked"), product: ($end.product == true),
       tokens: (map(.tokens.claude + .tokens.codex) | add), minutes: ((($end.time | fromdate) - (.[0].time | fromdate)) / 60 | floor)}' "$STATE"
}
cards | jq -rs --arg since "$since" '
  def med: sort | (.[(length - 1) / 2 | floor] + .[length / 2 | floor]) / 2;
  def fig(f): if length == 0 then "-" else f end;
  def pad($n): tostring | (" " * ($n - length)) + .;
  def col: map(select(.landed)) as $l
    | [($l | length), ($l | map(select(.product)) | length),
       ($l | map(.tokens) | fig(add / length | floor)), ($l | map(.minutes) | fig(med)),
       (if length == 0 then "-" else "\((map(select(.landed | not)) | length) * 100 / length | floor)%" end)];
  def block($name): col as $a
    | "== \($name) ==",
      (["cards landed", "landed, changed product code", "fresh tokens per landed card", "median start-to-landed (min)", "share of cards blocked"]
        | to_entries[] | "\(.value)\(" " * (30 - (.value | length)))\($a[.key] | pad(22))"), "";
  block("week from \($since)"), (group_by(.day)[] | block(.[0].day))'

jq -rs --arg o "$OWNER" 'group_by(.card)[] | select(any(.step == "landed" or .step == "closed" or .step == "blocked") | not)
  | (map(select(.step == "review")) | length) as $r
  | "open (no closing line): \(.[0].card) issue #\(.[0].issue), last step \(last.step) at \(last.time)",
    (select($r > 5) | "open past 5 reviews, for \($o) to stop by hand: \(.[0].card) issue #\(.[0].issue): \($r) reviews")' "$STATE"
# A card with a closed line no longer waits for the owner: its issue was closed while it was blocked.
jq -rs --arg o "$OWNER" 'group_by(.card)[] | select(any(.step == "closed") | not) | .[] | select(.step == "blocked") | "blocked, for \($o): \(.card) issue #\(.issue): \(.reason | gsub("\n"; "; "))"' "$STATE"
jq -r 'select(.step == "review") | .issue as $i | .reason | split("\n")[] | select(startswith("NEW CARD:")) | "from #\($i): \(.)"' "$STATE"
