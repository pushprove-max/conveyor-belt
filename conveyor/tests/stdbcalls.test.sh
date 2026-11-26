#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the answers of the state store (stdb, lib/records.sh) kept while their files are unchanged.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The loop's look at its cards in flight, each turn (run()): stuckcard with `turn` reads the card records the turn kept.
# Bug it catches (issue 741): that look asking the store again, once a card a turn, for records the turn just read.
t_stuckturn() {
  # shellcheck disable=SC2034 # HERE is read by stdb(), for the folder state.py is in
  # CALLS, not a file under $s: stuckcard has a local s of its own.
  local s=$T/$CASE/st HERE=$SRC STATE CARDS=$T/$CASE/cards CALLS=$T/$CASE/calls out
  STATE=$s/cards.jsonl; mkdir -p "$s" "$CARDS"
  eval "$(sed -n '/^declare -A ASKED_K/p; /^stdb() {/,/^}/p; /^turncards() {/p' "$SRC/lib/records.sh")"
  eval "$(sed -n '/^stuckcard() {/,/^}/p' "$SRC/lib/run.sh")"
  python3() { echo x >> "$CALLS"; command python3 "$@"; } # each state store call, counted
  # Card c1 at its worktree line, its process (pid 1, with a start time it never had) gone.
  printf '%s\n' '{"card":"c1","issue":1,"step":"worktree","pid":1,"started":"Thu Jan  1 00:00:00 1970","time":"2026-01-01T00:00:00Z"}' > "$STATE"
  stdb ask lines cards > /dev/null # kept in this shell, as the loop's turn keeps them
  : > "$CALLS"
  out=$(stuckcard c1 turn) && [ "$out" = '1 worktree gone' ] || fail "the card with no process was not found gone: '$out'"
  [ ! -s "$CALLS" ] || fail "the loop's look at a card in flight asked the state store $(wc -l < "$CALLS") times, not 0"
}

# Bug it catches: a kept answer given after its file changed (a line that ended since it was asked, an append, a
# rewrite in place to the same size and mtime, as `retry` and a hand edit make), or an unchanged file asked again.
t_stdbkept() {
  # shellcheck disable=SC2034 # HERE is read by stdb(), for the folder state.py is in
  local s=$T/$CASE/st HERE=$SRC STATE n
  STATE=$s/cards.jsonl; mkdir -p "$s"
  eval "$(sed -n '/^declare -A ASKED_K/p; /^stdb() {/,/^}/p; /^turncards() {/p' "$SRC/lib/records.sh")"
  python3() { echo x >> "$s/calls"; command python3 "$@"; } # each state store call, counted
  printf '%s\n' '{"card":"c1","issue":1,"step":"picked"}' > "$STATE"; printf '{"card":"c2","issue":2,"step":"pic' >> "$STATE"
  stdb ask lines cards > /dev/null # kept in this shell
  [ "$(stdb ask lines cards | jq -r .card | tr '\n' ' ')" = 'c1 ' ] && [ "$(wc -l < "$s/calls")" = 1 ] \
    || fail "the unchanged file was asked again, or a line being written was read: $(stdb ask lines cards), $(wc -l < "$s/calls") calls"
  printf 'ked"}\n' >> "$STATE"
  [ "$(stdb ask lines cards | jq -r .card | tr '\n' ' ')" = 'c1 c2 ' ] || fail "the line that ended since was not read: $(stdb ask lines cards)"
  stdb ask lines cards > /dev/null; touch -r "$STATE" "$s/was"
  printf x | dd of="$STATE" bs=1 seek=9 conv=notrunc 2>/dev/null; touch -r "$s/was" "$STATE" # c1 is x1, same size and mtime
  [ "$(stdb ask lines cards | jq -r .card | tr '\n' ' ')" = 'x1 c2 ' ] || fail "the file rewritten in place was not read anew: $(stdb ask lines cards)"
  stdb ask lines cards > /dev/null; printf '%s\n' '{"card":"c3","issue":3,"step":"picked"}' | stdb append cards
  [ "$(stdb ask card c3 | jq -r .card) $(stdb ask lines cards | jq -r .card | tr '\n' ' ')" = 'c3 x1 c2 c3 ' ] || fail "the appended line was not read: $(stdb ask lines cards)"
  # A file emptied in place (a retry that moved every line out) holds no line, asked of no database: the loop's turn
  # reader (turncards) gives none either, not the lines kept before.
  stdb ask lines cards > /dev/null; : > "$STATE"; n=$(wc -l < "$s/calls")
  [ -z "$(stdb ask lines cards; stdb ask lines declined; stdb ask issue retried 3; turncards)" ] && [ "$(wc -l < "$s/calls")" = "$n" ] \
    || fail "an empty or missing file's lines were not none, or were asked of the database: $(turncards), $(wc -l < "$s/calls") calls, not $n"
}

# Bug it catches (issue 354): a reader of the card records that stops early (a jq given a bad --argjson stops before
# it reads; head) made the writer's printf say "write error: Broken pipe" in the service's log, where SIGPIPE is
# ignored (systemd's default), many lines a second. Read through both writers: turncards' kept answer and stdb's.
t_stdbpipe() {
  # shellcheck disable=SC2034 # HERE is read by stdb(), for the folder state.py is in
  local s=$T/$CASE/st HERE=$SRC STATE i first
  STATE=$s/cards.jsonl; mkdir -p "$s"
  eval "$(sed -n '/^declare -A ASKED_K/p; /^stdb() {/,/^}/p; /^turncards() {/p' "$SRC/lib/records.sh")"
  # More than a pipe's buffer (64 KiB), so the writer is still writing when the reader stops.
  for i in $(seq 1500); do printf '{"card":"c%s","issue":%s,"step":"picked","reason":"%0100d"}\n' "$i" "$i" 0; done > "$STATE"
  first=$(head -n 1 "$STATE")
  (
    trap '' PIPE
    # A pipe, as the loop's `< <(...)` readers have, but a pipeline: the shell waits for the writer's last word.
    stdb ask lines cards | jq -rs --argjson open '' '.' > "$s/jq" 2>/dev/null
    [ ! -s "$s/jq" ] || echo "jq with a bad --argjson gave: $(cat "$s/jq")"
    [ "$(stdb ask lines cards | head -n 1)" = "$first" ] || echo "stdb through head did not give the first line"
    stdb ask lines cards > /dev/null # kept in this shell: turncards gives its kept answer
    [ -n "${ASKED_K[lines cards ]:-}" ] || echo "the card records were not kept"
    turncards | jq -rs --argjson open '' '.' > "$s/jq" 2>/dev/null
    [ ! -s "$s/jq" ] || echo "jq with a bad --argjson gave: $(cat "$s/jq")"
    [ "$(turncards | head -n 1)" = "$first" ] || echo "turncards through head did not give the first line"
  ) > "$s/out" 2> "$s/err"
  [ ! -s "$s/out" ] || fail "an early-closing reader got another result: $(cat "$s/out")"
  [ ! -s "$s/err" ] || fail "an early-closing reader of the card records left this on stderr: $(head -c 400 "$s/err")"
}
