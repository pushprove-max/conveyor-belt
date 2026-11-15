#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the running summary of the card records and the retried file that the snapshot makes its rows from
# (lib/snapshot.sh snaprows).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Every run of rows.jq is noted in $STUB/rows as the name of the file it read and that file's lines: the stub stands
# before the real jq, which it then runs. snapsum_ran <file name> counts the runs on that file.
# Every case file is sourced into one shell (conveyor.test.sh), so these helpers carry the file's name: a plain name
# such as ran() would replace another file's helper of that name (rerun.test.sh has its own ran()).
snapsum_rowsstub() {
  local real; real=$(command -v jq)
  printf '#!/usr/bin/env bash\ncase " $* " in *"/rows.jq "*) f=${@: -1}; echo "${f##*/} $(wc -l < "$f")" >> "$STUB/rows" ;; esac\nexec %q "$@"\n' "$real" > "$STUB/jq"
  chmod +x "$STUB/jq"; : > "$STUB/rows"
}
snapsum_ran() { grep -c "^$1 " "$STUB/rows"; }
snapsum_line() { printf '{"card":"%s","issue":%s,"step":"%s","time":"%s","tokens":{"claude":0,"codex":0},"result":"%s","sha":"","reason":"%s","repo":"r"}\n' "$@"; }
# The offset the summary of a records file has read to (the second of its first line's numbers past the key).
snapsum_offset() { head -n 1 "$1.rows" | cut -d' ' -f3; }
# A snapshot less what the machine reads afresh each time (free disk, load, the test slots in use).
snapsum_fixed() { jq -S 'del(.health.machineNow, .health.diskFreeKb, .testSlots)' <<<"$1"; }
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
  setup "[$(issue 5 2026-03-01 P2)]"
  snapsum_line c1 5 picked 2026-03-02T00:00:00Z ok '' >> "$ST/cards.jsonl"; snapsum_line c1 5 blocked 2026-03-02T00:10:00Z blocked 'build: failed' >> "$ST/cards.jsonl"
  snapsum_rowsstub; export CONVEYOR_NOW; CONVEYOR_NOW=$(date -u -d 2026-03-04 +%s)
  one=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(snapsum_ran cards.jsonl)" = 1 ] && [ "$(snapsum_ran retried.jsonl)" = 1 ] || fail "the first snapshot did not make the rows of each file once: $(tr '\n' ' ' < "$STUB/rows")"
  [ "$(jq -c '.needsYou.blocked | map(.card)' <<<"$one")" = '["c1"]' ] || fail "the blocked card is not in the first snapshot: $(jq -c .needsYou <<<"$one")"
  # Nothing recorded since: the next snapshot makes no rows, and shows the same cards.
  : > "$STUB/rows"; two=$(loop snapshot) || fail "snapshot exited non-zero"
  [ ! -s "$STUB/rows" ] || fail "a snapshot of unchanged records made their rows again: $(tr '\n' ' ' < "$STUB/rows")"
  [ "$(jq -c '.needsYou.blocked | map(.card)' <<<"$two")" = '["c1"]' ] || fail "the kept rows do not show the blocked card: $(jq -c .needsYou <<<"$two")"
  # `retry` rewrites the card records and adds to the retried file: the next snapshot makes the rows of the records
  # anew, and of the retried file those of the card its new lines name, and the card is no longer blocked.
  loop retry 5 >/dev/null 2>&1 || fail "retry was refused"
  : > "$STUB/rows"; out=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(snapsum_ran cards.jsonl)" = 1 ] && [ "$(snapsum_ran retried.jsonl)" = 0 ] && [ "$(snapsum_ran old.lines)" = 1 ] || fail "after a retry the rows of each file were not made once: $(tr '\n' ' ' < "$STUB/rows")"
  [ "$(jq -c '[(.needsYou.blocked | length), (.metrics.cards | map(select(.card == "c1") | .state))]' <<<"$out")" = '[0,["retried"]]' ] \
    || fail "the snapshot after a retry shows kept rows of the records as they were: $(jq -c '[.needsYou.blocked, (.metrics.cards | map({card, state}))]' <<<"$out")"
}

# Bug (#531): each snapshot made the rows of every card from the whole history (3.8 MB, 8,900 lines, on a busy belt
# one snapshot after another), where only the lines added since the last one are new. With a running summary, a
# snapshot after one more line reads that line alone and makes the row of its card alone, and shows what a snapshot
# made from the whole file shows: a row kept from before, or one made anew from too few lines, would differ.
t_snapsum() {
  local size two whole
  setup "[$(issue 80 2026-03-01 P2)]"; snapsum_history80
  snapsum_rowsstub; export CONVEYOR_NOW; CONVEYOR_NOW=$(date -u -d 2026-03-04 +%s)
  loop snapshot > /dev/null || fail "snapshot exited non-zero"
  size=$(wc -c < "$ST/cards.jsonl")
  [ "$(snapsum_offset "$ST/cards.jsonl")" = "$size" ] || fail "the summary has not read the whole file: offset $(snapsum_offset "$ST/cards.jsonl") of $size bytes"
  # The card on the belt builds: one line more.
  snapsum_line c80 80 build 2026-03-01T14:00:00Z ok '' >> "$ST/cards.jsonl"
  : > "$STUB/rows"; two=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(snapsum_offset "$ST/cards.jsonl")" = "$(wc -c < "$ST/cards.jsonl")" ] && [ "$(($(wc -c < "$ST/cards.jsonl") - size))" = "$(snapsum_line c80 80 build 2026-03-01T14:00:00Z ok '' | wc -c)" ] \
    || fail "the summary's offset did not move by the new line alone: $size, then $(snapsum_offset "$ST/cards.jsonl")"
  # rows.jq read the four lines of c80 alone, never the 399 of the file.
  [ "$(cat "$STUB/rows")" = "rows.lines 4" ] || fail "the second snapshot did not make the row of the new line's card alone: $(tr '\n' ' ' < "$STUB/rows")"
  # Built, c80 is at its review (it was at its build).
  [ "$(jq -c '.belt | map([.card, .step])' <<<"$two")" = '[["c80","review"]]' ] || fail "the snapshot does not show the new line: $(jq -c '.belt | map([.card, .step])' <<<"$two")"
  # The same snapshot, and the same summary, as made from the whole file.
  mv "$ST/cards.jsonl.rows" "$STUB/kept.rows"
  : > "$STUB/rows"; whole=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(snapsum_ran cards.jsonl)" = 1 ] || fail "with no summary, the rows were not made from the whole file: $(tr '\n' ' ' < "$STUB/rows")"
  [ "$(snapsum_fixed "$two")" = "$(snapsum_fixed "$whole")" ] || fail "the snapshot from the summary differs from the one from the whole file: $(diff <(snapsum_fixed "$two") <(snapsum_fixed "$whole") | head -n 20)"
  cmp -s "$STUB/kept.rows" "$ST/cards.jsonl.rows" || fail "the summary brought up to date differs from one made from the whole file: $(diff "$STUB/kept.rows" "$ST/cards.jsonl.rows" | head -n 5)"
}

# Bug (#531): a summary of a file rewritten since (`retry` moves a card's lines out of the card records) read on from
# its offset: past the end of a shorter file, or, once lines were added past it again, from the middle of a line,
# with the rows of moved cards kept. Either way the summary is made anew from the whole file.
t_snapsumshort() {
  local out was t
  # Today is the day of the history, so landedCount counts its landed cards.
  export TZ=UTC; setup "[$(issue 80 2026-03-01 P2)]"; snapsum_history80
  snapsum_rowsstub; export CONVEYOR_NOW; CONVEYOR_NOW=$(date -u -d 2026-03-01T23:00:00Z +%s)
  loop snapshot > /dev/null || fail "snapshot exited non-zero"
  # Shorter: the lines of c1 are gone.
  grep -v '"card":"c1"' "$ST/cards.jsonl" > "$STUB/short" && mv "$STUB/short" "$ST/cards.jsonl"
  : > "$STUB/rows"; out=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(cat "$STUB/rows")" = "cards.jsonl 393" ] && [ "$(snapsum_offset "$ST/cards.jsonl")" = "$(wc -c < "$ST/cards.jsonl")" ] \
    || fail "the summary of a file rewritten shorter was not made anew from the whole file: $(tr '\n' ' ' < "$STUB/rows"), offset $(snapsum_offset "$ST/cards.jsonl")"
  [ "$(jq -c '.landedCount' <<<"$out")" = 78 ] || fail "the snapshot of the shorter file still counts the moved card: $(jq -c '.landedCount' <<<"$out")"
  # Rewritten again (c2 gone), and grown past the offset since: new lines of c90.
  was=$(snapsum_offset "$ST/cards.jsonl")
  grep -v '"card":"c2"' "$ST/cards.jsonl" > "$STUB/short" && mv "$STUB/short" "$ST/cards.jsonl"
  for t in 0 1 2 3 4 5 6 7 8 9; do snapsum_line c90 90 picked "2026-03-01T15:0${t}:00Z" ok '' >> "$ST/cards.jsonl"; done
  [ "$(wc -c < "$ST/cards.jsonl")" -gt "$was" ] || fail "the fixture is wrong: the rewritten file is not longer than the summary's offset"
  : > "$STUB/rows"; out=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(cat "$STUB/rows")" = "cards.jsonl 398" ] || fail "the summary of a file rewritten and grown past its offset was not made anew: $(tr '\n' ' ' < "$STUB/rows")"
  [ "$(jq -c '[.landedCount, (.belt | map(.card))]' <<<"$out")" = '[77,["c80","c90"]]' ] \
    || fail "the snapshot of the rewritten file shows a moved card or misses a new one: $(jq -c '[.landedCount, (.belt | map(.card))]' <<<"$out")"
}
