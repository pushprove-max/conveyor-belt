#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the running summary of the card records and the retried file that the snapshot makes its rows from
# (lib/snapshot.sh snaprows).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The cases call snaprows() itself, as snapshot() calls it: a whole `loop snapshot` (3 a case) cost each case about 5 s
# for the one function under test. The records are in $ST, each summary beside its file ($ST/<file>.rows, as
# $STATE.rows), and what a call writes in $D/d (rows for the card records, old for the retried file, as snapshot()).
# Every run of rows.jq is noted in $D/rows as the name of the file it read and that file's lines: rows() is wrapped
# around the engine's own. snapsum_ran <file name> counts the runs on that file.
# Every case file is sourced into one shell (conveyor.test.sh), so these helpers carry the file's name: a plain name
# such as ran() would replace another file's helper of that name (rerun.test.sh has its own ran()).
snapsum_engine() {
  D=$T/$CASE; ST=$D/state
  # shellcheck disable=SC2034 # HERE and YES are read by the engine's snaprows() and rows(), eval'd below
  HERE=$SRC YES="visible to customers or staff: needs the owner's yes: "
  mkdir -p "$ST" "$D/d" && : > "$D/rows" && : >> "$ST/cards.jsonl" && : >> "$ST/retried.jsonl" || fail "the case's folders could not be made"
  eval "$(sed -n '/^snaprows() {/,/^}/p' "$SRC/lib/snapshot.sh"; sed -n '/^rows() {/,/^}/p' "$SRC/lib/views.sh" | sed '1s/^rows()/snapsum_realrows()/'
    grep -h '^MAX_REVIEWS=\|^NODEPS=\|^SHUT=' "$SRC/lib/paths.sh" "$SRC/lib/push.sh" "$SRC/lib/issues.sh")"
  declare -F snaprows snapsum_realrows > /dev/null && [ -n "$MAX_REVIEWS" ] && [ -n "$NODEPS" ] && [ -n "$SHUT" ] || fail "snaprows, rows or their settings were not found in the engine"
  rows() { echo "${1##*/} $(wc -l < "$1")" >> "$D/rows"; snapsum_realrows "$@"; }
}
snapsum_snap() { snaprows "$ST/$1" "$ST/$1.rows" "$D/d/$2" || fail "snaprows failed on $1"; } # <records file name> <rows|old>
snapsum_ran() { grep -c "^$1 " "$D/rows"; }
snapsum_line() { printf '{"card":"%s","issue":%s,"step":"%s","time":"%s","tokens":{"claude":0,"codex":0},"result":"%s","sha":"","reason":"%s","repo":"r"}\n' "$@"; }
# The offset the summary of a records file has read to (the second of its first line's numbers past the key).
snapsum_offset() { head -n 1 "$1.rows" | cut -d' ' -f3; }
# A long history: 80 cards, 79 landed with five lines each and the last on the belt, one issue each.
snapsum_history80() {
  jq -cn 'range(1; 81) as $i | ("2026-03-01T00:00:00Z" | fromdate) + $i * 600 as $t
    | (if $i == 80 then ["picked", "worktree", "brief"] else ["picked", "worktree", "brief", "build", "landed"] end) | to_entries[]
    | {card: "c\($i)", issue: $i, step: .value, time: ($t + .key * 60 | todate), tokens: {claude: 1, codex: 0}, result: "ok", sha: "", reason: ""}
      + ({picked: {title: "card \($i)"}, landed: {sha: "abc\($i)", product: false}}[.value] // {})' > "$ST/cards.jsonl"
}

# Bug: every snapshot makes the rows of every card ever recorded anew, the retried file's too, though that file
# changes only at a `retry`: a fifth of the work of a snapshot that took 20 to 40 s on a busy host. Or, keeping the
# rows, a snapshot shows the ones of a file that has changed since.
t_snaprows() {
  local one
  snapsum_engine
  snapsum_line c1 5 picked 2026-03-02T00:00:00Z ok '' >> "$ST/cards.jsonl"; snapsum_line c1 5 blocked 2026-03-02T00:10:00Z blocked 'build: failed' >> "$ST/cards.jsonl"
  snapsum_snap cards.jsonl rows; snapsum_snap retried.jsonl old
  [ "$(snapsum_ran cards.jsonl)" = 1 ] && [ "$(snapsum_ran retried.jsonl)" = 1 ] || fail "the first snapshot did not make the rows of each file once: $(tr '\n' ' ' < "$D/rows")"
  one=$(cat "$D/d/rows")
  [ "$(jq -c 'map([.card, .step])' <<<"$one")" = '[["c1","blocked"]]' ] || fail "the blocked card is not in the first rows: $one"
  # Nothing recorded since: the next snapshot makes no rows, and has the same rows.
  : > "$D/rows"; snapsum_snap cards.jsonl rows; snapsum_snap retried.jsonl old
  [ ! -s "$D/rows" ] || fail "a snapshot of unchanged records made their rows again: $(tr '\n' ' ' < "$D/rows")"
  [ "$(cat "$D/d/rows")" = "$one" ] || fail "the kept rows differ from the ones made before: $(cat "$D/d/rows")"
  # `retry` rewrites the card records and adds to the retried file (moveout(), lib/issues.sh): the next snapshot makes
  # the rows of the records anew, and of the retried file those of the card its new lines name, and the card is no
  # longer in the records' rows.
  grep '"card":"c1"' "$ST/cards.jsonl" >> "$ST/retried.jsonl" && { grep -v '"card":"c1"' "$ST/cards.jsonl" || :; } > "$D/rest" && mv "$D/rest" "$ST/cards.jsonl" \
    || fail "the fixture's retry could not move the card's lines"
  : > "$D/rows"; snapsum_snap cards.jsonl rows; snapsum_snap retried.jsonl old
  [ "$(snapsum_ran cards.jsonl)" = 1 ] && [ "$(snapsum_ran retried.jsonl)" = 0 ] && [ "$(snapsum_ran old.lines)" = 1 ] || fail "after a retry the rows of each file were not made once: $(tr '\n' ' ' < "$D/rows")"
  [ "$(cat "$D/d/rows")" = '[]' ] || fail "the rows after a retry keep the records' rows as they were: $(cat "$D/d/rows")"
  [ "$(jq -c 'map([.card, .step])' "$D/d/old")" = '[["c1","blocked"]]' ] && [ "$(jq -c . "$D/d/old")" = "$(snapsum_realrows "$ST/retried.jsonl")" ] \
    || fail "the retried file's rows after a retry differ from the ones made from the whole file: $(cat "$D/d/old")"
}

# Bug (#531): each snapshot made the rows of every card from the whole history (3.8 MB, 8,900 lines, on a busy belt
# one snapshot after another), where only the lines added since the last one are new. With a running summary, a
# snapshot after one more line reads that line alone and makes the row of its card alone, and has the rows a snapshot
# made from the whole file has: a row kept from before, or one made anew from too few lines, would differ.
t_snapsum() {
  local size two
  snapsum_engine; snapsum_history80
  snapsum_snap cards.jsonl rows
  size=$(wc -c < "$ST/cards.jsonl")
  [ "$(snapsum_offset "$ST/cards.jsonl")" = "$size" ] || fail "the summary has not read the whole file: offset $(snapsum_offset "$ST/cards.jsonl") of $size bytes"
  # The card on the belt builds: one line more.
  snapsum_line c80 80 build 2026-03-01T14:00:00Z ok '' >> "$ST/cards.jsonl"
  : > "$D/rows"; snapsum_snap cards.jsonl rows; two=$(cat "$D/d/rows")
  [ "$(snapsum_offset "$ST/cards.jsonl")" = "$(wc -c < "$ST/cards.jsonl")" ] && [ "$(($(wc -c < "$ST/cards.jsonl") - size))" = "$(snapsum_line c80 80 build 2026-03-01T14:00:00Z ok '' | wc -c)" ] \
    || fail "the summary's offset did not move by the new line alone: $size, then $(snapsum_offset "$ST/cards.jsonl")"
  # rows.jq read the four lines of c80 alone, never the 399 of the file.
  [ "$(cat "$D/rows")" = "rows.lines 4" ] || fail "the second snapshot did not make the row of the new line's card alone: $(tr '\n' ' ' < "$D/rows")"
  # Built, c80 is at its review (it was at its build).
  [ "$(jq -c 'map(select(.card == "c80") | .step)' <<<"$two")" = '["review"]' ] || fail "the rows do not show the new line: $(jq -c 'map(select(.card == "c80"))' <<<"$two")"
  # The same rows, and the same summary, as made from the whole file.
  mv "$ST/cards.jsonl.rows" "$D/kept.rows"
  : > "$D/rows"; snapsum_snap cards.jsonl rows
  [ "$(snapsum_ran cards.jsonl)" = 1 ] || fail "with no summary, the rows were not made from the whole file: $(tr '\n' ' ' < "$D/rows")"
  [ "$two" = "$(cat "$D/d/rows")" ] || fail "the rows from the summary differ from the ones from the whole file: $(diff <(jq . <<<"$two") <(jq . "$D/d/rows") | head -n 20)"
  cmp -s "$D/kept.rows" "$ST/cards.jsonl.rows" || fail "the summary brought up to date differs from one made from the whole file: $(diff "$D/kept.rows" "$ST/cards.jsonl.rows" | head -n 5)"
}

# Bug (#531): a summary of a file rewritten since (`retry` moves a card's lines out of the card records) read on from
# its offset: past the end of a shorter file, or, once lines were added past it again, from the middle of a line,
# with the rows of moved cards kept. Either way the summary is made anew from the whole file.
t_snapsumshort() {
  local was t
  snapsum_engine; snapsum_history80
  snapsum_snap cards.jsonl rows
  # Shorter: the lines of c1 are gone.
  grep -v '"card":"c1"' "$ST/cards.jsonl" > "$D/short" && mv "$D/short" "$ST/cards.jsonl"
  # #282: snaprows says the summary is made anew before rows.jq's long run on the whole file, so a reader that stops
  # a slow snapshot (the Foreman's 45 s wait) has the reason; said after that run, a stopped one says nothing.
  rows() { { grep -c 'the snapshot is being made anew' "$D/err" || :; } >> "$D/said"; echo "${1##*/} $(wc -l < "$1")" >> "$D/rows"; snapsum_realrows "$@"; }
  : > "$D/rows"; snaprows "$ST/cards.jsonl" "$ST/cards.jsonl.rows" "$D/d/rows" 2>"$D/err" || fail "snaprows failed on the shorter file: $(cat "$D/err")"
  [ "$(cat "$D/said")" = 1 ] || fail "snaprows did not say the summary is made anew before it made the rows: $(cat "$D/said"), $(cat "$D/err")"
  [ "$(cat "$D/rows")" = "cards.jsonl 393" ] && [ "$(snapsum_offset "$ST/cards.jsonl")" = "$(wc -c < "$ST/cards.jsonl")" ] \
    || fail "the summary of a file rewritten shorter was not made anew from the whole file: $(tr '\n' ' ' < "$D/rows"), offset $(snapsum_offset "$ST/cards.jsonl")"
  [ "$(jq -c '[(map(select(.step == "landed")) | length), any(.card == "c1")]' "$D/d/rows")" = '[78,false]' ] \
    || fail "the rows of the shorter file still hold the moved card: $(jq -c 'map(.card)' "$D/d/rows")"
  # Rewritten again (c2 gone), and grown past the offset since: new lines of c90.
  was=$(snapsum_offset "$ST/cards.jsonl")
  grep -v '"card":"c2"' "$ST/cards.jsonl" > "$D/short" && mv "$D/short" "$ST/cards.jsonl"
  for t in 0 1 2 3 4 5 6 7 8 9; do snapsum_line c90 90 picked "2026-03-01T15:0${t}:00Z" ok '' >> "$ST/cards.jsonl"; done
  [ "$(wc -c < "$ST/cards.jsonl")" -gt "$was" ] || fail "the fixture is wrong: the rewritten file is not longer than the summary's offset"
  : > "$D/rows"; snapsum_snap cards.jsonl rows
  [ "$(cat "$D/rows")" = "cards.jsonl 398" ] || fail "the summary of a file rewritten and grown past its offset was not made anew: $(tr '\n' ' ' < "$D/rows")"
  [ "$(jq -c '[(map(select(.step == "landed")) | length), map(select(.step != "landed") | .card)]' "$D/d/rows")" = '[77,["c80","c90"]]' ] \
    || fail "the rows of the rewritten file hold a moved card or miss a new one: $(jq -c 'map([.card, .step])' "$D/d/rows")"
}
