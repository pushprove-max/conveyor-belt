#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a case that fails in a card, passes on main and is in a file the card does not change is one sighting
# on the flaky-test record (mainred.sh verdicts(), flaky.sh flakycard(): issue 1829).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. mrshared() and mrv() are mainredproof.test.sh's; eng() is mainred.test.sh's.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

MRFL='{"files":[{"file":"a.test","cases":[{"name":"one","line":1}]}]}' # the card's last run: a.test: one failed
mrflc() { printf 'c20260101T000000-repo-%s' "$1"; } # the id of the card of issue <n>
# Card <n>'s worktree on main's commit, with <file> staged as its change (<file> gets one line more).
mrflcard() { # <n> <file>
  local w; w=$T/$CASE/cards/$(mrflc "$1")
  git -C "$R" worktree add -q --detach "$w" && echo '# changed' >> "$w/$2" && git -C "$w" add "$2" || fail "card $1's worktree could not be made"
}
mrflentries() { jq -c '[.entries[]? | [.case, .source, .card, .issue]]' "$ST/flaky.json" 2>/dev/null || echo '[]'; }

# Bug it catches (issue 1829): a.test: one failed in every run of a card and passed on main, so its verdict was card,
# and nothing counted it: it failed in three cards that did not change a.test and was never kept off. Card 7, whose
# change is to another file, adds one entry with the card as its source, its issue and a note that names main's
# commit. Its second fix round fails the case again and adds no entry: one card is one source.
t_mainredflakycard() {
  local c s; c=$(mrflc 7) # s: main's commit, set by mrshared()
  mrshared one; mrflcard 7 b.txt
  mrv "$c" "$MRFL"
  [ "$(jq -c .verdicts "$STUB/v.$c")" = '[{"case":"a.test: one","verdict":"card"}]' ] || fail "card $c given $MRFL, a.test: one passing on main: not the card's: $(cat "$STUB/v.$c" "$STUB/v.$c.err")"
  [ "$(mrflentries)" = "[[\"a.test: one\",\"$c\",\"$c\",7]]" ] \
    || fail "card $c given $MRFL, a.test: one passing on main and the change in b.txt alone: not one entry from the card: $(cat "$ST/flaky.json" 2>&1) $(cat "$STUB/v.$c.err")"
  [ "$(jq -r '.entries[0].note' "$ST/flaky.json")" = "failed in the card, passed on main at ${s:0:12}; the card does not change its file" ] \
    || fail "card $c given $MRFL: the entry's note does not name main's commit ${s:0:12}: $(cat "$ST/flaky.json")"
  mrv "$c" "$MRFL"
  [ "$(mrflentries)" = "[[\"a.test: one\",\"$c\",\"$c\",7]]" ] || fail "card $c given $MRFL a second time: a second entry was added: $(cat "$ST/flaky.json")"
}

# Bug it catches: the card's own test counted as flaky. Card 7's change edits a.test: its failure there is the card's
# to fix, and adds no entry, though main's a.test passes.
t_mainredflakyown() {
  local c; c=$(mrflc 7)
  mrshared one; mrflcard 7 a.test
  mrv "$c" "$MRFL"
  [ "$(jq -c .verdicts "$STUB/v.$c")" = '[{"case":"a.test: one","verdict":"card"}]' ] || fail "card $c given $MRFL, its change editing a.test: not the card's: $(cat "$STUB/v.$c" "$STUB/v.$c.err")"
  [ "$(mrflentries)" = '[]' ] || fail "card $c given $MRFL, its change editing a.test: an entry was added: $(cat "$ST/flaky.json")"
}

# Bug it catches (review E2): a case main's run did not run counted as passing there. Main's a.test still passes,
# but no longer holds case one (the runner prints no `ok one`): card 7's failure of a.test: one is the card's, and adds
# no entry.
t_mainredflakygone() {
  local c; c=$(mrflc 7)
  mrshared gone:one; mrflcard 7 b.txt
  mrv "$c" "$MRFL"
  [ "$(jq -c .verdicts "$STUB/v.$c")" = '[{"case":"a.test: one","verdict":"card"}]' ] || fail "card $c given $MRFL, main's a.test passing without case one: not the card's: $(cat "$STUB/v.$c" "$STUB/v.$c.err")"
  [ "$(mrflentries)" = '[]' ] || fail "card $c given $MRFL, main's a.test passing without running case one: an entry was added: $(cat "$ST/flaky.json")"
}

# Bug it catches (review E2): a file main's run could not start (no temp file: the runner logs `TESTRUN host`, as
# .conveyor/test-changed.sh nostart() does) counted as passing there. Card 7's failure of a.test: one adds no entry.
t_mainredflakyhost() {
  local c; c=$(mrflc 7)
  mrshared one; mrflcard 7 b.txt
  printf '%s\n' '{ echo "== a.test"; printf "TESTRUN host\ta.test\tno temp file\n"; echo "-- notrun a.test"; } >> "$CONVEYOR_TEST_LOG/r"; exit 1' > "$STUB/mainrun-cmd"
  mrv "$c" "$MRFL"
  [ "$(jq -c .verdicts "$STUB/v.$c")" = '[{"case":"a.test: one","verdict":"card"}]' ] || fail "card $c given $MRFL, main's a.test not started: not the card's: $(cat "$STUB/v.$c" "$STUB/v.$c.err")"
  [ "$(mrflentries)" = '[]' ] || fail "card $c given $MRFL, main's run not starting a.test: an entry was added: $(cat "$ST/flaky.json")"
}

# Bug it catches: a record that cannot be written changed the verdicts, said nothing, or said it twice (review E3:
# flaky()'s own line and the card's). With flaky.json.new a folder (so flakyput() cannot write), card 7's verdict stays
# card and its log has one line on the record: that it could not be written.
t_mainredflakyunwritten() {
  local c; c=$(mrflc 7)
  mrshared one; mrflcard 7 b.txt; mkdir -p "$ST/flaky.json.new"
  mrv "$c" "$MRFL"
  [ "$(jq -c .verdicts "$STUB/v.$c")" = '[{"case":"a.test: one","verdict":"card"}]' ] || fail "card $c given $MRFL, the record not writable: the verdicts changed: $(cat "$STUB/v.$c" "$STUB/v.$c.err")"
  [ "$(grep -F 'flaky-test record' "$STUB/v.$c.err")" = "conveyor: card $c: the flaky-test record could not be written" ] \
    || fail "card $c given $MRFL, the record not writable: its log does not say so in one line: $(cat "$STUB/v.$c.err")"
}

# The owner, 2026-11-27: a case that failed in three cards and passed on main each time was kept off by hand. Cards 7,
# 8 and 9 fail a.test: one, each in a change to b.txt alone, in that order, each test step first given flakyoff()'s
# list, as tests() gives it: a sighting alone keeps the case off no card (review E1: card 7's would have kept it off
# cards 8 and 9, so the third source never came), the third files the flaky issue, and while it is open flakyoff()
# keeps the case off card 10's test step (an `ok` and an `off` line in its list). Cards 8 and 9 read main's run of
# card 7 at the same commit (mainprobe.json): its proof that a.test: one passed is kept with it.
t_mainredflakythree() {
  local c n w
  mrshared one
  for c in 7 8 9; do
    mrflcard "$c" b.txt; w=$T/$CASE/cards/$(mrflc "$c"); : > "$w.rerun"
    eng 'flakyoff "$CONVEYOR_CARDS/'"$(mrflc "$c")"'"' || fail "flakyoff on card $c failed"
    [ ! -s "$w.rerun" ] || fail "flakyoff on card $c with $(jq -c '[.entries[].source]' "$ST/flaky.json" 2>&1) and no issue filed: a.test: one kept off: $(cat "$w.rerun")"
    mrv "$(mrflc "$c")" "$MRFL"
  done
  [ "$(wc -l < "$STUB/mainruns")" = 1 ] || fail "cards 7, 8 and 9 at one commit of main ran a.test there $(wc -l < "$STUB/mainruns") times, not once"
  [ "$(jq -c '[.entries[].source] | unique' "$ST/flaky.json" 2>/dev/null)" = "[\"$(mrflc 7)\",\"$(mrflc 8)\",\"$(mrflc 9)\"]" ] \
    || fail "cards 7, 8 and 9 given $MRFL, a.test: one passing on main: not one source each: $(cat "$ST/flaky.json" 2>&1)"
  [ "$(jq -s '[.[] | select(.title == "Flaky test: a.test: one fails at random")] | length' "$STUB/filed" 2>/dev/null)" = 1 ] \
    || fail "cards 7, 8 and 9 given $MRFL: the third source did not file one flaky issue for a.test: one: $(cat "$STUB/filed" 2>&1)"
  n=$(jq -r '.filed[] | select(.case == "a.test: one") | .issue' "$ST/flaky.json") && [ -n "$n" ] || fail "the record holds no filed issue: $(cat "$ST/flaky.json")"
  echo OPEN > "$STUB/state.$n"
  w=$T/$CASE/cards/$(mrflc 10); mkdir -p "$w"; : > "$w.rerun"
  eng 'flakyoff "$CONVEYOR_CARDS/'"$(mrflc 10)"'"' || fail "flakyoff failed"
  [ "$(tr '\t\n' ':|' < "$w.rerun")" = 'ok:a.test:one|off:a.test:one|' ] || fail "flakyoff on card 10 with #$n open: a.test: one not kept off: $(cat "$w.rerun")"
}
