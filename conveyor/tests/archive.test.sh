#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the archive of finished cards' lines and the landed list, as their readers read them: allrecs() and
# archrows() (the all-time totals), landedall() (the pick and adopted()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# archline <card> <issue> <step> <time> [<dollars>]: one line of the card records; with dollars, a build step that
# cost them at $20 per million output tokens.
archline() {
  jq -cn --arg c "$1" --argjson n "$2" --arg s "$3" --arg t "$4" --argjson o "$(jq -n --argjson d "${5:-0}" '$d * 50000 | round')" --arg repo "${R##*/}" \
    '{card:$c,issue:$n,step:$s,time:$t,tokens:{claude:$o,codex:0},result:"ok",sha:(if $s == "landed" then "ab" * 20 else "" end),reason:"",repo:$repo}
     + if $s == "build" then {model:"claude-opus-5-5",usage:{input:0,write:0,write1h:0,read:0,output:$o}} elif $s == "landed" then {product:true} else {} end'
}
# The cost of the build lines on stdin, as spent() prices a card's steps (SPENTSTEPS, stepsusd()), in whole cents:
# stepsusd prints a float (7.0), and the cases compare the amount, not its form.
ARCHCOST='jq -cs "$SPENTSTEPS" | stepsusd | jq ". * 100 | round"'

# Bugs: allrecs() leaves out an archive month, a gzip member after a file's first, or the live records; prints a month
# out of order (by the files' times, not their names), or the live lines before the archive; with no archive folder,
# prints anything but what recs() prints; or a cost total over it is not the total of the same lines all live.
t_allrecs() {
  setup '[]'; mkdir -p "$ST/archive"
  { archline cA 1 picked 2026-09-01T00:00:00Z; archline cA 1 build 2026-09-01T00:10:00Z 1; archline cA 1 landed 2026-09-01T00:20:00Z; } > "$T/$CASE/sep"
  { archline cB 2 picked 2026-10-01T00:00:00Z; archline cB 2 build 2026-10-01T00:10:00Z 2; archline cB 2 landed 2026-10-01T00:20:00Z; } > "$T/$CASE/oct"
  { archline cC 3 picked 2026-11-01T00:00:00Z; archline cC 3 build 2026-11-01T00:10:00Z 4; } > "$ST/cards.jsonl"
  # Each month in two gzip members, as two archive runs append them; October's file written first, so it is the older file.
  for m in oct sep; do
    f=$ST/archive/cards-2026-$([ $m = sep ] && echo 09 || echo 10).jsonl.gz
    head -n 1 "$T/$CASE/$m" | gzip -c > "$f" && tail -n +2 "$T/$CASE/$m" | gzip -c >> "$f" || fail "the archive fixture could not be written"
  done
  touch -t 200001010000 "$ST/archive/cards-2026-10.jsonl.gz"
  fx_in "allrecs; echo cost; allrecs | $ARCHCOST"
  [ "$(cat "$T/$CASE/run.out")" = "$(cat "$T/$CASE/sep" "$T/$CASE/oct" "$ST/cards.jsonl"; echo cost; echo 700)" ] \
    || fail "allrecs did not print September's lines, October's, then the live ones, or their cost is not \$7: $(cat "$T/$CASE/run.out")"
  # The same lines all live, no archive folder: allrecs prints what recs prints, and the cost total is the same.
  rm -rf "$ST/archive"; cat "$T/$CASE/sep" "$T/$CASE/oct" "$ST/cards.jsonl" > "$T/$CASE/all" && mv "$T/$CASE/all" "$ST/cards.jsonl"
  fx_in "[ \"\$(allrecs)\" = \"\$(recs)\" ] || echo differs; allrecs | $ARCHCOST"
  [ "$(cat "$T/$CASE/run.out")" = 700 ] || fail "with no archive, allrecs is not recs, or the cost total over it is not \$7: $(cat "$T/$CASE/run.out")"
}

# archcard <card> <issue> <time> <dollars>: a landed and pushed card's lines (its push's head named for the card).
archcard() {
  archline "$1" "$2" picked "$3"; archline "$1" "$2" build "$3" "$4"; archline "$1" "$2" landed "$3"
  archline "$1" "$2" pushed "$3" | jq -c --arg h "$1" '.head = $h'
}
# Bugs: the snapshot read the live records alone, so a card whose lines went to the archive dropped out of its landed
# count, its cost list, the week's pushes and the history the Board reads: the all-time totals (archrows(),
# lib/snapshot.sh); or a later snapshot reused the archive's kept rows and pushes after an archive run appended a gzip
# member to a month's file.
t_archrows() {
  local now f q='[.landedCount, ([.landed[].card] | sort), .landedUsd, .cost.today, .metrics.week.pushes.ok]' out
  setup '[]'; mkdir -p "$ST/archive"; now=$(date -u +%FT%TZ); f=$ST/archive/cards-${now:0:7}.jsonl.gz
  archcard cA 1 "$now" 1 | gzip -c > "$f"
  archcard cB 2 "$now" 2 > "$ST/cards.jsonl"
  out=$(loop snapshot --fresh | jq -c "$q") && [ "$out" = '[2,["cA","cB"],3,3,2]' ] \
    || fail "the snapshot did not count the archived card's landing, cost and push beside the live one's: $out"
  # A later archive run appends a member to the same month's file: the next snapshot reads it, not the kept rows.
  archcard cC 3 "$now" 4 | gzip -c >> "$f"
  out=$(loop snapshot --fresh | jq -c "$q") && [ "$out" = '[3,["cA","cB","cC"],7,7,3]' ] \
    || fail "the second snapshot left out the archive's new gzip member (cC): $out"
  out=$(loop history | jq -c '[.cost.cards[].card] | sort') && [ "$out" = '["cA","cB","cC"]' ] \
    || fail "the history's cost list left out an archived card: $out"
}

# Bugs: an issue whose card landed and whose lines left the live records (it is only in landed.tsv) is picked again, by
# the pick or a dry pick of a state folder that holds the list; or adopted() keeps it pinned in order as not landed.
t_landedtsv() {
  local d=$T/$CASE/frozen out
  setup "$(jq -cs . <(issue 4 2026-01-01 P1) <(issue 5 2026-02-01 P1))"
  printf 'c9-4\t4\t%s\t2026-09-01T00:00:00Z\n' "$(printf 'ab%.0s' {1..20})" > "$T/$CASE/landed.tsv"
  # A dry pick of another folder reads that folder's landed list, not the state folder's (which has none here).
  mkdir -p "$d" && cp "$ST/control.json" "$T/$CASE/landed.tsv" "$d/" && : > "$d/cards.jsonl"
  out=$(loop pick --dry --issues "$STUB/issues.json" --state "$d") && [ "$out" = 5 ] || fail "the dry pick took '$out', not 5: #4 is landed in its folder's landed.tsv"
  cp "$T/$CASE/landed.tsv" "$ST/landed.tsv"
  out=$(pickfn upnext "$(cat "$STUB/issues.json")" | jq -c 'map(.number)') && [ "$out" = '[5]' ] || fail "the pick's list is $out, not [5]: #4 is landed in landed.tsv"
  fx_in 'adopted "$(ctl | jq -c ".order = [4, 5]")" "$(cat "$STUB/issues.json")" | jq -c .order'
  [ "$(cat "$T/$CASE/run.out")" = '[5]' ] || fail "adopted() kept #4, landed in landed.tsv, in order: $(cat "$T/$CASE/run.out")"
}
