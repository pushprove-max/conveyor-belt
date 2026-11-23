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
  # shellcheck disable=SC2034 # HERE is read by the engine's snaprows() and rows(), eval'd below; YES and LINTYES are
  # set by the engine's yesforms(), taken from lib/records.sh
  HERE=$SRC
  mkdir -p "$ST" "$D/d" && : > "$D/rows" && : >> "$ST/cards.jsonl" && : >> "$ST/retried.jsonl" || fail "the case's folders could not be made"
  eval "$(sed -n '/^snaprows() {/,/^}/p; /^ROWKEY=/p; /^ROWLINE=/p' "$SRC/lib/snapshot.sh"; sed -n '/^rows() {/,/^}/p' "$SRC/lib/views.sh" | sed '1s/^rows()/snapsum_realrows()/'
    sed -n '/^yesforms() {/,/^}/p' "$SRC/lib/records.sh"; grep -hE '^(MAX_REVIEWS|NODEPS|SHUT|OWNSHUT)=' "$SRC/lib/"{paths,push,issues}.sh)"
  declare -F yesforms > /dev/null && yesforms "the owner"
  # Bug (#1012): snaprows() reads LINTYES (#259); with it not set, the cases stopped on an unbound variable.
  declare -F snaprows snapsum_realrows > /dev/null && [ -n "${ROWKEY:-}" ] && [ -n "${ROWLINE:-}" ] && [ -n "$MAX_REVIEWS" ] && [ -n "$NODEPS" ] && [ -n "$SHUT" ] && [ -n "${OWNSHUT:-}" ] && [ -n "${LINTYES:-}" ] || fail "snaprows, rows or their settings were not found in the engine"
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
  snapsum_snap cards.jsonl rows 2> "$D/err1"; snapsum_snap retried.jsonl old
  # Bug (#291): the first snapshot, with no summary kept yet, said a retry, a resume or an engine change had rewritten
  # the records, which sends a reader after a cause that never happened.
  grep -qxF 'conveyor: the snapshot is being made from the whole card records (no summary of them is kept yet); this one takes longer' "$D/err1" \
    || fail "the first snapshot did not say that no summary is kept yet: $(cat "$D/err1")"
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
  # rows.jq read the new line alone (#1564: c80's three older lines are the summary's, never searched for in the
  # file), never the 399 of the file.
  [ "$(cat "$D/rows")" = "rows.lines 1" ] || fail "the second snapshot did not make the row of the new line's card from that line alone: $(tr '\n' ' ' < "$D/rows")"
  # Built, c80 is at its review (it was at its build).
  [ "$(jq -c 'map(select(.card == "c80") | .step)' <<<"$two")" = '["review"]' ] || fail "the rows do not show the new line: $(jq -c 'map(select(.card == "c80"))' <<<"$two")"
  # The same rows, and the same summary, as made from the whole file.
  mv "$ST/cards.jsonl.rows" "$D/kept.rows"
  : > "$D/rows"; snapsum_snap cards.jsonl rows
  [ "$(snapsum_ran cards.jsonl)" = 1 ] || fail "with no summary, the rows were not made from the whole file: $(tr '\n' ' ' < "$D/rows")"
  [ "$two" = "$(cat "$D/d/rows")" ] || fail "the rows from the summary differ from the ones from the whole file: $(diff <(jq . <<<"$two") <(jq . "$D/d/rows") | head -n 20)"
  cmp -s "$D/kept.rows" "$ST/cards.jsonl.rows" || fail "the summary brought up to date differs from one made from the whole file: $(diff "$D/kept.rows" "$ST/cards.jsonl.rows" | head -n 5)"
}

# Bug (#1564 review): a failed push appends a push line alone (pushone(), lib/push.sh), which names no row's card. The
# file of the cards the new lines name was then empty, and the summary's split of its kept rows took every row as a
# name: each was dropped, and the Board showed an empty belt. The rows after a push line are the ones before it.
t_snappushonly() {
  local one
  snapsum_engine; snapsum_history80
  snapsum_snap cards.jsonl rows; one=$(cat "$D/d/rows")
  [ "$(jq length <<<"$one")" = 80 ] || fail "the fixture's rows are not its 80 cards: $(jq -c 'map(.card)' <<<"$one")"
  printf '{"card":"c79","issue":79,"step":"push","time":"2026-03-01T14:00:00Z","result":"fail","sha":"abc79","kind":"transport","reason":"no network","repo":"r"}\n' >> "$ST/cards.jsonl"
  snapsum_snap cards.jsonl rows
  [ "$(snapsum_offset "$ST/cards.jsonl")" = "$(wc -c < "$ST/cards.jsonl")" ] || fail "the summary did not read the push line: offset $(snapsum_offset "$ST/cards.jsonl")"
  [ "$(cat "$D/d/rows")" = "$one" ] || fail "the rows after a push line alone differ from the ones before it: $(jq -c 'map(.card)' "$D/d/rows")"
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

# The whole-build cases run `loop snapshot`: what a direct call to snaprows(), as t_snapsum makes, cannot show is
# what snapshot() keeps between two builds (its copy of the card records, $STATE.copy, the rows' summary, $STATE.rows,
# and the check's and other summaries of the copy) and what each program it starts reads. Stubs of the programs that
# read files note each call given the card records or the kept copy (an argument or stdin that is one of them) in
# $D/<name>.reads; the jq one also notes each rows.jq run as `<lines of the file it reads>:<states it is given>` (`-`
# with none) in $D/<name>.rows, and the first such run after the case makes $STUB/hold waits there (it renames hold to
# held, then waits for $STUB/go) with no lock held and the build's link to the kept copy made; a python3 notes the
# first line of each `since` answer the state database gives (state.py: from, end, mark and the bytes of the lines it
# gave) in $D/<name>.since. Each runs the real program.
# snapsum_build <log name>: one build. snapsum_kept: the summary's lines now; snapsum_rows: the rows in them.
snapsum_builds() {
  local p real
  setup "[$(issue 1 2026-01-01)]"; mkdir -p "$ST"; D=$T/$CASE; snapsum_history80
  for p in awk cat cksum cp cut grep head sed sort tail jq; do
    real=$(command -v "$p") || fail "no $p to wrap"
    # stub: a reader that notes a call given the records or the kept copy, then runs the real program (jq also notes rows.jq's input)
    { printf '#!/usr/bin/env bash\nfor a in "$@" /dev/stdin; do if [ "$a" -ef %q ] || [ "$a" -ef %q ]; then echo "%s $*" >> %q; break; fi; done\n' \
        "$ST/cards.jsonl" "$ST/cards.jsonl.copy" "$p" "$STUB/reads"
      [ "$p" != jq ] || printf 'case "$*" in *jq/rows.jq*) if [ -e %q ] && mv %q %q 2>/dev/null; then i=0; while [ ! -e %q ] && [ $i -lt 1200 ]; do i=$((i + 1)); sleep 0.1; done; fi ;; esac\n' \
        "$STUB/hold" "$STUB/hold" "$STUB/held" "$STUB/go"
      [ "$p" != jq ] || printf 'case "$*" in *jq/rows.jq*) s=-; for ((i = 1; i < $#; i++)); do [ "${!i}" != states ] || { j=$((i + 1)); s=$(wc -l < "${!j}"); }; done; echo "$(wc -l < "${@: -1}"):$s" >> %q ;; esac\n' "$STUB/rowsruns"
      printf 'exec %q "$@"\n' "$real"; } > "$STUB/$p" && chmod +x "$STUB/$p" || fail "the $p stub could not be made"
  done
  # stub: a python3 that runs the real one, then logs the first line of the answer it wrote for a `since` question
  printf '#!/usr/bin/env bash\n%q "$@"; rc=$?; o=\nfor a in "$@"; do case $a in --) o= ;; since) [ -z "$o" ] || head -n 1 "$o" >> "$STUB/since" ;; esac; [ "$p" != -o ] || o=$a; p=$a; done\nexit $rc\n' \
    "$(command -v python3)" > "$STUB/python3" && chmod +x "$STUB/python3" || fail "the python3 stub could not be made"
}
# Bug (#1564 review): on macOS p_path puts Homebrew's programs (python3, jq, the GNU tools) ahead of $STUB on PATH, so
# the stubs never ran there and the cases saw no `since` answer. Each stub is also an exported function of its name,
# which the engine's bash runs before any program on PATH.
snapsum_route() {
  local p
  for p in awk cat cksum cp cut grep head sed sort tail jq python3; do eval "$p() { $(printf %q "$STUB/$p") \"\$@\"; }; export -f $p" || return 1; done
}
snapsum_build() {
  : > "$STUB/rowsruns"; : > "$STUB/since"; : > "$STUB/reads"; ( snapsum_route && loop snapshot --fresh > /dev/null ) || fail "the $1 build exited non-zero"
  paste -sd' ' "$STUB/rowsruns" > "$D/$1.rows"; cp "$STUB/since" "$D/$1.since"; cp "$STUB/reads" "$D/$1.reads"
}
snapsum_kept() { tail -n +2 "$ST/cards.jsonl.rows"; }
snapsum_rows() { cut -f2 <<<"$1"; }

# Bug (#1335, #1564): a snapshot build copied the whole card records from the state database each time, checksummed
# the copy, counted each card's lines in the records, searched the copy for the older lines of each card a new line
# names, and rows.jq read all of them: its time grew with every card ever run (31,612 lines, 34 MB, and the Board
# minutes behind). The first build reads the 398 lines of the 80 cards; the second, after one more line of c80 (three
# lines before it), reads that line alone: the database gives its bytes alone, no program reads the records or the
# kept copy but from past the bytes read before, and rows.jq is given that line and c80's state alone. Its rows, and
# the line counts of the cards (snapshot.json.records), are the ones a whole build makes.
# Bugs (#1564 review): the new line is a landed one, as a card's end is: the drift watch, made again when a card starts
# or ends, was given the whole copy. And `conveyor.sh history test` and `health` run between the builds, as the Board
# and the owner run them: each wrote its summary of the records over the snapshot's, which then read the whole copy.
t_snapbuilds() {
  local size one two bad nl dk
  snapsum_builds; snapsum_build first; size=$(wc -c < "$ST/cards.jsonl")
  dk=$(head -n 1 "$ST/cards.jsonl.drift") || fail "the first build kept no drift watch: $(ls "$ST" | tr '\n' ' ')"
  rm -f "$ST/cards.jsonl.tests" "$ST/cards.jsonl.health"
  loop history test a.test.sh > /dev/null && loop health > /dev/null && [ -s "$ST/cards.jsonl.tests" ] && [ -s "$ST/cards.jsonl.health" ] \
    || fail "\`history test a.test.sh\` and \`health\` did not run or kept no summary of the records: $(ls "$ST" | tr '\n' ' ')"
  # A landed line names its commit and whether it changed the product (jq/check.jq).
  nl=$(snapsum_line c80 80 landed 2026-03-01T14:00:00Z ok '' | jq -c '.sha = "abc80" | .product = false') && printf '%s\n' "$nl" >> "$ST/cards.jsonl" \
    || fail "the landed line could not be written"
  snapsum_build second; two=$(snapsum_kept)
  # Bug (#1564 review): with a retried file that holds no worktree or end line, the drift watch's key failed
  # (pipefail) and the watch was never made. The landed line makes it again, on a new key.
  [ "$(head -n 1 "$ST/cards.jsonl.drift")" != "$dk" ] || fail "the second build did not make the drift watch again after the landed line (key $dk)"
  [ "$(grep -cxF $'4\tc80' "$ST/snapshot.json.records")" = 1 ] && [ "$(grep -cxF $'5\tc1' "$ST/snapshot.json.records")" = 1 ] && [ "$(wc -l < "$ST/snapshot.json.records")" = 80 ] \
    || fail "the second build's line counts are not the records' (4 of c80, 5 of c1, 80 cards): $(sort -k2 "$ST/snapshot.json.records" | tail -n 3 | tr '\t\n' ': ')"
  # A whole build of the same records: no summary kept.
  rm -f "$ST/cards.jsonl.rows"; snapsum_build whole
  [[ " $(cat "$D/first.rows") " == *" 398:0 "* ]] || fail "the first build did not read the whole records (each rows.jq run's lines:states: $(cat "$D/first.rows"))"
  # The stubs see a whole read: the first build checks the whole copy (a tail from its first byte).
  grep -q '^tail -c +1 ' "$D/first.reads" || fail "the stubs did not see the first build read the whole copy: $(head -n 5 "$D/first.reads")"
  [ "$(cat "$D/second.rows")" = 1:1 ] || fail "the second build gave rows.jq other than the one new line and its card's state (each rows.jq run's lines:states: $(cat "$D/second.rows"))"
  one=$(printf '%s\n' "$nl" | wc -c)
  [ "$(cut -d' ' -f1,4 "$D/second.since")" = "$size $one" ] \
    || fail "the second build read other than the new line's $one bytes past byte $size of the records (the database's answer: $(cat "$D/second.since"))"
  bad=$(grep -vE "^tail -c \+$((size + 1)) " "$D/second.reads")
  [ -z "$bad" ] && [ -s "$D/second.reads" ] || fail "the second build read the records or the kept copy other than past byte $size: ${bad:-nothing read}"
  [[ " $(cat "$D/whole.rows") " == *" 399:0 "* ]] || fail "the reference build was not a whole one (each rows.jq run's lines:states: $(cat "$D/whole.rows"))"
  [ "$(snapsum_rows "$two" | jq -r 'select(.card == "c80") | .step')" = landed ] || fail "the second build's rows do not show c80's new line: $(grep '"c80"' <<<"$two" | cut -f2)"
  [ "$two" = "$(snapsum_kept)" ] || fail "the rows of the second build differ from a whole build's: $(diff <(echo "$two") <(snapsum_kept) | head -n 6)"
}

# Bug (#1564): a copy and a summary kept from before a rewrite of the card records (`retry` moves a card's lines
# out, a bad line is set aside) are not the records' first bytes any more, and reading on past their end would keep
# the moved card and lose or garble lines. In place, as the state database rewrites the file, with lines added past
# the old end since: the next build reads the whole records, and its rows are a whole build's.
t_snaprewrite() {
  local size two t
  snapsum_builds; snapsum_build first; size=$(wc -c < "$ST/cards.jsonl")
  grep -v '"card":"c1"' "$ST/cards.jsonl" > "$D/rest" && cat "$D/rest" > "$ST/cards.jsonl" || fail "the fixture's rewrite failed"
  for t in 0 1 2 3 4 5 6 7 8 9; do snapsum_line c90 90 picked "2026-03-01T15:0${t}:00Z" ok '' >> "$ST/cards.jsonl"; done
  [ "$(wc -c < "$ST/cards.jsonl")" -gt "$size" ] || fail "the fixture is wrong: the rewritten records are not longer than the first build's"
  snapsum_build second; two=$(snapsum_kept)
  cmp -s "$ST/cards.jsonl.copy" "$ST/cards.jsonl" || fail "the kept copy is not the rewritten records: $(diff "$ST/cards.jsonl.copy" "$ST/cards.jsonl" | head -n 4)"
  rm -f "$ST/cards.jsonl.rows"; snapsum_build whole
  [ "$(cut -d' ' -f1,4 "$D/second.since")" = "0 $(wc -c < "$ST/cards.jsonl")" ] \
    || fail "the second build did not read the whole rewritten records (the database's answer: $(cat "$D/second.since"))"
  [[ " $(cat "$D/second.rows") " == *" $(wc -l < "$ST/cards.jsonl"):0 "* ]] || fail "rows.jq was not given the whole rewritten records (each rows.jq run's lines:states: $(cat "$D/second.rows"))"
  [ "$(snapsum_rows "$two" | jq -sc '[any(.card == "c1"), any(.card == "c90")]')" = '[false,true]' ] || fail "the second build's rows keep the moved card or miss the new one: $(snapsum_rows "$two" | jq -sc 'map(.card)')"
  [ "$two" = "$(snapsum_kept)" ] || fail "the rows after the rewrite differ from a whole build's: $(diff <(echo "$two") <(snapsum_kept) | head -n 6)"
}

# Bug (#1564 review): a build reads the kept copy through its link ($STATE.copy.r<pid>), the same file. A second
# build that adds a new line while the first still runs must write the copy anew (snapcopy()), never append in place:
# else the running build's copy changes under it. `history` builds with no kept-snapshot lock, so it runs beside a
# `snapshot` build, as on a host; it is held at its rows.jq run (the stub), past its copy and its check, and the
# second build runs then. A direct call cannot show it: what is checked is the link the real snapshot() keeps.
t_snapcopyheld() {
  local pa l rc
  snapsum_builds; snapsum_build first
  snapsum_line c80 80 build 2026-03-01T14:00:00Z ok '' >> "$ST/cards.jsonl" && cp "$ST/cards.jsonl" "$D/a.records" && rm -f "$ST/history.json" \
    && : > "$STUB/hold" || fail "the fixture's first new line could not be written"
  ( snapsum_route && loop history > /dev/null ) & pa=$!
  wait_until "[ -e '$STUB/held' ]" "ls '$ST'" || { touch "$STUB/go"; fail "the history build did not reach its rows.jq run"; }
  l=$(printf '%s\n' "$ST"/cards.jsonl.copy.r*)
  [ -f "$l" ] && [ "$l" -ef "$ST/cards.jsonl.copy" ] && cmp -s "$l" "$D/a.records" \
    || { touch "$STUB/go"; fail "the fixture is wrong: the held build's link is not the kept copy of the records then: $l"; }
  snapsum_line c80 80 review 2026-03-01T14:10:00Z GO '' >> "$ST/cards.jsonl"
  ( snapsum_route && loop snapshot --fresh > /dev/null ) || { touch "$STUB/go"; fail "the second build exited non-zero"; }
  cmp -s "$l" "$D/a.records" || { touch "$STUB/go"; fail "the held build's copy changed under it: $(diff "$D/a.records" "$l" | head -n 4)"; }
  cmp -s "$ST/cards.jsonl.copy" "$ST/cards.jsonl" || { touch "$STUB/go"; fail "the kept copy is not the records after the second build: $(diff "$ST/cards.jsonl.copy" "$ST/cards.jsonl" | head -n 4)"; }
  touch "$STUB/go"; wait "$pa"; rc=$?
  [ "$rc" = 0 ] && [ ! -e "$l" ] || fail "the held build exited $rc, or left its link $l"
}

# Bug (#1564 review): the drift watch (driftof(), lib/snapshot.sh) gave bench/drift.sh the whole copy of the card
# records each time a card started or ended. It gives what drift.sh reads of each line (DRIFTIN) instead, and the
# answer must be the one the whole lines give: four cards on two engine commits, with tokens, reviews, fixes, waits, a
# blocked card, a card still running and fields drift.sh does not read.
t_snapdriftin() {
  local f whole cut
  eval "$(sed -n "/^DRIFTIN='/,/'\$/p" "$SRC/lib/snapshot.sh")"; [ -n "${DRIFTIN:-}" ] || fail "DRIFTIN was not found in lib/snapshot.sh"
  f=$T/$CASE.jsonl
  jq -cn 'range(1; 6) as $i | ("2026-03-01T00:00:00Z" | fromdate) + $i * 3600 as $t
    | [["picked", {}], ["worktree", {engine: (if $i < 3 then "aaaa1111" else "bbbb2222" end), pid: 9}], ["review", {reason: "P1 x"}], ["fix", {}],
       ["review", {}], (if $i == 5 then empty elif $i == 4 then ["blocked", {waitSec: 120}] else ["landed", {waitSec: ($i * 60), sha: "abc"}] end)]
    | to_entries[] | {card: "c\($i)", issue: $i, step: .value[0], time: ($t + .key * 300 | todate), tokens: {claude: ($i * 10 + .key), codex: .key}, result: "ok"} + .value[1]' > "$f" \
    || fail "the fixture could not be made"
  whole=$("$SRC/bench/drift.sh" --json "$f") && cut=$(jq -cR "$DRIFTIN" "$f" | "$SRC/bench/drift.sh" --json /dev/stdin) \
    || fail "drift.sh failed on the fixture or on what DRIFTIN keeps of it: ${cut:-$whole}"
  jq -e '.before.cards == 2 and .after.cards == 2 and .after.blocked == 1 and .before.waits > 0 and .before.fixes == 1' <<<"$whole" > /dev/null \
    || fail "the fixture does not give two groups with tokens, fixes and waits: $whole"
  [ "$cut" = "$whole" ] || fail "drift.sh's answer from DRIFTIN's lines differs from the one from the whole lines: $cut against $whole"
}
