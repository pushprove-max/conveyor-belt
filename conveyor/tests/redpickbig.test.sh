#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the loop picks a main-red fix card from a big main-is-red record (mainred.sh redpick()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue 369. Bug it catches: mainred.sh redpick() gave the record, without its document cases, to jq as an argument, which Linux
# refuses over 128 KiB ("Argument list too long"): the document's entry stayed and no fix card was picked. The record
# holds a document's entry and main's entry of 300 cases with long names (about 170 KB): the document's entry goes,
# and main's commit gets its fix card. eng() is mainred.test.sh's.
t_redpickbig() {
  setup "[]"
  local s out c
  s=$(git -C "$R" rev-parse HEAD)
  jq -cn --arg s "$s" '{reds: [{sha: "1111111111111111111111111111111111111111", cases: [{case: "tests/speed/page.md", file: "tests/speed/page.md", by: "c1", files: [], last: ""}], card: null},
    {sha: $s, cases: [range(300) as $i | {case: "a.test: case-\($i)-\("0" * 480)", file: "a.test", by: "c1", files: ["a.test"], last: ""}], card: null}]}' > "$ST/mainred.json"
  [ "$(wc -c < "$ST/mainred.json")" -gt 131072 ] || fail "the record is not over 128 KiB"
  out=$(eng 'locked redpick' 2>&1) || fail "redpick failed: ${out:0:300}"
  c=${out%% *}
  [[ $out == *-0\ 0\ false ]] && [ "$(jq -c --arg c "$c" '[.reds[] | [.sha, .card == $c, (.cases | length)]]' "$ST/mainred.json")" = "[[\"$s\",true,300]]" ] \
    || fail "the document's entry was kept or main's commit got no fix card: ${out:0:300} $(jq -c '[.reds[] | [.sha, .card, (.cases | length)]]' "$ST/mainred.json")"
}
# R331. Bug it catches: redpick() dropped a document's entry (one an engine before #367 made) whose fix card cb is
# blocked, not ended, though that card's brief and commit are made from its entry (redissue()). It is kept whole.
t_redpickblocked() {
  setup "[]"
  local out
  jq -cn '{reds: [{sha: "1111111111111111111111111111111111111111", cases: [{case: "tests/speed/page.md", file: "tests/speed/page.md", by: "c1", files: [], last: ""}], card: "cb"}]}' > "$ST/mainred.json"
  eng 'append "$(line cb 0 picked ok "{\"title\":\"Main is red\"}")" && append "$(line cb 0 blocked fail "{}")"' || fail "card cb's lines could not be written"
  out=$(eng 'locked redpick' 2>&1) || fail "redpick failed: $out"
  [ -z "$out" ] && [ "$(jq -c '[.reds[] | [.card, (.cases | length)]]' "$ST/mainred.json")" = '[["cb",1]]' ] \
    || fail "with its fix card cb blocked, the document's entry was dropped, or a card was picked: $out $(cat "$ST/mainred.json")"
}
# E5. Bug it catches: a blocked fix card given back by `retry` has no lines (moveout()), and redpick() kept its
# document-only entry whole as if the card were still open, then picked a new card for the document case again.
t_redpickretried() {
  setup "[]"
  local out
  jq -cn '{reds: [{sha: "1111111111111111111111111111111111111111", cases: [{case: "tests/speed/page.md", file: "tests/speed/page.md", by: "c1", files: [], last: ""}], card: "c20260101T000000-x-0"}]}' > "$ST/mainred.json"
  out=$(eng 'append "$(line c20260101T000000-x-0 0 picked ok "{\"title\":\"Main is red\",\"mainRed\":\"1111111111111111111111111111111111111111\"}")" && append "$(line c20260101T000000-x-0 0 blocked fail "{}")" && retry c20260101T000000-x-0' 2>&1) \
    && [ -z "$(eng 'stdb ask card c20260101T000000-x-0')" ] || fail "the blocked card could not be given back by retry: $out"
  out=$(eng 'locked redpick' 2>&1) || fail "redpick failed: $out"
  [ -z "$out" ] && [ "$(jq -c '.reds' "$ST/mainred.json")" = '[]' ] \
    || fail "with its fix card given back by retry, the document-only entry was kept, or a card was picked for it: $out $(cat "$ST/mainred.json")"
}
