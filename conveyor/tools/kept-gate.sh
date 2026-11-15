#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The gate the move of kept work under the state folder lands behind, and the cutover repeats (plan section 12).
# Since that move a blocked line names its kept folder relative to the state folder (kept/<card>), and the engine
# reads no other shape. A blocked line in the card records or retried.jsonl that still names its kept folder by an
# absolute path, while that folder still holds work no card has used, is listed here with its patch size, for the
# owner to carry into a landed card or discard.
# Used: a card whose worktree line says it took up this card's kept patch (applied it, brought it onto main or reviewed
# it) then landed, or closed the issue as already fixed, or blocked with its own kept patch used in turn, however many
# retries deep. Another card of the issue landing does not use it (a retry takes up only the last kept patch), nor does
# a retry alone, nor a card that found the patch unreadable.
# Discarded: the folder is gone.
# Usage: kept-gate.sh. Exit 0 when nothing is listed, 1 when something is or the records cannot be read.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
st=$(bash "$HERE/../conveyor.sh" state-dir) || { echo "kept-gate: the state folder cannot be named" >&2; exit 1; }
left=$(cat -- "$st/cards.jsonl" "$st/retried.jsonl" | jq -rs '
  (map(select(.step == "landed" or .step == "closed") | {key: .card, value: true}) | from_entries) as $done
  | (reduce (.[] | select(.step == "worktree" and (.reason | type) == "string") | select(.reason | contains("cannot be read") | not)
       | {to: .card, from: (.reason | capture("kept patch of card (?<c>[^: ]+)[: ]")?.c)} | select(.from != null)) as $e
       ({}; .[$e.from] += [$e.to])) as $took
  | def used: . as $c | $done[$c] or any($took[$c][]?; used);
  .[] | select(.step == "blocked" and (.kept | type) == "string" and (.kept | startswith("/"))) as $b
  | select([$took[$b.card][]? | used] | any | not)
  | [$b.card, ($b.issue | tostring), $b.kept] | @tsv') || { echo "kept-gate: the card records in $st cannot be read" >&2; exit 1; }
n=0
while IFS=$'\t' read -r card issue kept; do
  [ -n "$card" ] && [ -d "$kept" ] || continue
  if [ -f "$kept/$card.patch" ]; then size="patch $(wc -c < "$kept/$card.patch") bytes"; else size="no patch"; fi
  echo "kept-gate: card $card (#$issue) has unused kept work at $kept ($size): carry it into a landed card or discard it"
  n=$((n + 1))
done <<<"$left"
[ "$n" = 0 ] || { echo "kept-gate: $n blocked card(s) still name kept work by an absolute path; the move of kept work does not land until none does" >&2; exit 1; }
echo "kept-gate: no blocked card names unused kept work by an absolute path"
