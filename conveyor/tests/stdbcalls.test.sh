#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the answers of the state store (stdb, lib/records.sh) kept while their files are unchanged, and how many
# times the loop calls the store, and jq, in one batch run.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Each state store call is a python3 start (about 35 ms). Two cards (#7, #8) land as one batch, with the fixture of
# batchreuse.test.sh (reusesetup); #8 waits at its claim, looking each `live` seconds, for the 3 s #7's product check
# takes once #8 is ready. A stub python3 records each call to state.py, then runs the real one. The engine before
# issue 67 made 125 calls here (116 with no wait): each reader of a loop turn, and each look of a waiting card, asked
# the store again for the card records it had just read, and each card asked again for the lines of tables that hold
# none. Bug it catches: those reads asking the store again.
t_stdbcalls() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'x.txt x.test' 'y.txt y.test'
  echo 'sleep 3' > "$STUB/held-then" # sleep: the time #8 waits, looking each `live` seconds, is what this case counts the calls of
  local py n; py=$(command -v python3)
  printf '#!/usr/bin/env bash\ncase ${2:-} in */state.py) printf "%%s\\n" "${*:4}" >> "$STUB/stdb.calls" ;; esac\nexec %q "$@"\n' "$py" > "$STUB/python3"
  chmod +x "$STUB/python3"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  landedtogether "$(cardof 8) $(cardof 7)" || fail "the two cards did not land as one batch: $(st 'select(.step == "landed")')"
  n=$(wc -l < "$STUB/stdb.calls")
  [ $((n * 2)) -lt 125 ] || fail "the loop called its state store $n times in one batch run of two cards, not fewer than half of 125: $(sort "$STUB/stdb.calls" | cut -c1-60 | uniq -c | sort -rn | head -n 8)"
}

# The loop's look at its cards in flight, each turn (run()): stuckcard with `turn` reads the card records the turn kept.
# Bug it catches (issue 741): that look asking the store again, once a card a turn, for records the turn just read (the
# batch run above made 63 calls).
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

# Each jq and each state store call is a program start. Two cards (#7, #8) land as one batch, with the fixture of
# batchreuse.test.sh (reusesetup). A stub jq counts each of the engine's calls (not those of the fixture's own stub
# scripts, which poll: a jq started by a script under $STUB), a stub python3 each call to state.py; each then runs the
# real one. On main before issue 595 this run made 760 or more of them (700 to 712 jq and 60 or 61 state store calls in
# three runs, without the 3 jq calls of this case's own landing checks): the batch path read a file once a field (the card's claim in claim(), its batch mark in settle(), its
# ready mark in readysince()), and the run's cards one by one, each with its own jq (batchkeep(), batchpass(),
# gather()). Bug it catches: those reads made one by one again.
BATCHCALLS_WAS=760
t_batchcalls() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'x.txt x.test' 'y.txt y.test'
  local py jqp n by; py=$(command -v python3); jqp=$(command -v jq)
  printf '#!/usr/bin/env bash\ncase ${2:-} in */state.py) echo stdb >> "$STUB/calls" ;; esac\nexec %q "$@"\n' "$py" > "$STUB/python3"
  # The parent's command line: /proc on Linux, ps on macOS.
  printf '%s\nexec %q "$@"\n' '#!/usr/bin/env bash
if [ -r "/proc/$PPID/cmdline" ]; then mapfile -d "" a < "/proc/$PPID/cmdline"; a="${a[*]}"; else a=$(ps -o args= -p "$PPID"); fi
case $a in *"$STUB"/*) ;; *) echo jq >> "$STUB/calls" ;; esac' "$jqp" > "$STUB/jq"
  chmod +x "$STUB/python3" "$STUB/jq"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  # Count before the checks below: their jq calls are the test's, not the engine's.
  n=$(wc -l < "$STUB/calls"); by=$(sort "$STUB/calls" | uniq -c | tr -s ' \n' ' ')
  landedtogether "$(cardof 8) $(cardof 7)" || fail "the two cards did not land as one batch: $(st 'select(.step == "landed")')"
  [ "$n" -lt "$BATCHCALLS_WAS" ] || fail "one batch run of two cards made $n jq and state store calls, not fewer than the $BATCHCALLS_WAS before issue 595: $by"
}
