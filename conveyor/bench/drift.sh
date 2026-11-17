#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The drift watch: the cards that ran on one engine commit against those that ran on the engine commit before it.
# Input: the card records (the lines of cards.jsonl and retried.jsonl, in any order). A card ran on the engine its
# worktree line names (engine). The engine commits are in the order their first worktree line was written, a card still
# running counting as one that ended does, so a commit whose cards all still run is never skipped; <engine commit> (a
# prefix of one) is the after group and the commit before it the before group; with none, the latest engine commit is
# the after group. A group holds the cards of its commit that ended: a card ends at its first landed, closed or blocked
# line (a blocked card whose issue is closed later stays blocked, its minutes to the block).
# Each group: cards, landed, blocked, and a mean a card of tokens (every line's Claude and Codex tokens), minutes
# (picked line to end), fix rounds (fix lines) and minutes waited (the end line's waitSec: on other cards and on main;
# only the cards whose end line has it), and reviews to land (review lines, landed cards only). A group of fewer than 5
# cards is too small to mean anything: small names it.
# Usage: drift.sh [--json] <records file> [<engine commit>]
# Prints the two groups side by side, or with --json one object {before, after, small}; exit 1 with a reason when
# there is nothing to compare.
set -euo pipefail
JSON=''; [ "${1:-}" != --json ] || { JSON=1; shift; }
[ $# -ge 1 ] && [ $# -le 2 ] || { echo "usage: drift.sh [--json] <records file> [<engine commit>]" >&2; exit 2; }
WANT=${2:-}
[ -z "$WANT" ] || [[ $WANT =~ ^[0-9a-f]{4,40}$ ]] || { echo "drift: $WANT is no engine commit (4 to 40 hex digits)" >&2; exit 2; }
OUT=$(jq -nc --arg want "$WANT" '
  [inputs | objects | select((.card | type) == "string")] | group_by(.card)
  | map(sort_by(.time) as $l
      | ($l | map(select(.step == "worktree" and (.engine | type) == "string")) | first) as $w
      | ($l | map(select(.step | IN("landed", "closed", "blocked"))) | first) as $end
      | select($w != null)
      | {engine: $w.engine, at: $w.time, ended: ($end != null)}
        + if $end == null then {} else
          {landed: ($end.step == "landed"), blocked: ($end.step == "blocked"),
           tokens: ([$l[] | (.tokens.claude // 0) + (.tokens.codex // 0)] | add),
           minutes: ((($end.time | fromdate) - ($l[0].time | fromdate)) / 60),
           reviews: ([$l[] | select(.step == "review")] | length), fixes: ([$l[] | select(.step == "fix")] | length),
           wait: ($end.waitSec | if type == "number" then . / 60 else null end)} end) as $all
  | ($all | group_by(.engine) | map({engine: .[0].engine, at: (map(.at) | min)}) | sort_by(.at) | map(.engine)) as $order
  | [$all[] | select(.ended)] as $cards
  | (if $want == "" then ($order | length) - 1 else [$order | to_entries[] | select(.value | startswith($want)) | .key] | if length == 1 then .[0] else null end end) as $i
  | if $want != "" and $i == null then error("no card ran on an engine commit \($want), or more than one commit begins so")
    elif $want != "" and $i == 0 then error("no card ran on an engine commit before \($order[0][:8])")
    elif $i < 1 then error("the cards ran on fewer than two engine commits, so there is nothing to compare")
    else . end
  | def mean(f): [.[] | f | numbers] | if length == 0 then null else add / length | . * 10 | round / 10 end;
    def group($e): [$cards[] | select(.engine == $e)]
      | {engine: $e, cards: length, landed: map(select(.landed)) | length, blocked: map(select(.blocked)) | length,
         tokens: (mean(.tokens) | if . == null then null else round end), minutes: mean(.minutes),
         reviews: (map(select(.landed)) | mean(.reviews)), fixes: mean(.fixes), waits: mean(.wait)};
    {before: group($order[$i - 1]), after: group($order[$i])} | .small = [to_entries[] | select(.value.cards < 5) | .key]
' "$1" 2>&1) || { echo "drift: $(sed 's/^jq: error (at [^)]*): //' <<<"${OUT:-the records could not be read}")" >&2; exit 1; }
[ -z "$JSON" ] || { printf '%s\n' "$OUT"; exit 0; }
# jq lines the table up: column(1) is not on every machine (bsdextrautils on Ubuntu) and setup does not install it.
jq -r '
  def v: if . == null then "-" else tostring end;
  def row($n; f): [$n, (.before | f | v), (.after | f | v)];
  def pad($w): . + " " * ($w - length + 2);
  [["Figure", "before \(.before.engine[:8])", "after \(.after.engine[:8])"],
   row("Cards"; .cards), row("Landed"; .landed), row("Blocked"; .blocked), row("Tokens a card"; .tokens),
   row("Minutes a card"; .minutes), row("Reviews to land"; .reviews), row("Fix rounds a card"; .fixes),
   row("Minutes waited a card"; .waits)]
  | (map(.[0] | length) | max) as $w0 | (map(.[1] | length) | max) as $w1
  | .[] | "\(.[0] | pad($w0))\(.[1] | pad($w1))\(.[2])"
' <<<"$OUT"
jq -r '.small[] as $g | "The \($g) group holds \(.[$g].cards) \(if .[$g].cards == 1 then "card" else "cards" end): too small to mean anything (fewer than 5 cards)."' <<<"$OUT"
