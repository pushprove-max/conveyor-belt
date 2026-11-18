#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the loop picks a main-red fix card from a big main-is-red record (redpick()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue 369. Bug it catches: redpick() gave the record, without its document cases, to jq as an argument, which Linux
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
