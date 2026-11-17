#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the fds the machine's Conveyor (`conveyor.sh machine`) and the loops it starts hold.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: the machine kept its copy of stderr (LOGFD) when it ran itself again as the reaper of what it starts, and gave
# it to each loop it started; with the copy each conveyor.sh makes of its own, these added up to hundreds of fds in
# every loop and card, so a card's test runner got fd 255, bash's own, and its slot and lock cases failed. Linux alone
# has /proc and the reaper's run again.
t_machinefds() {
  [ -d /proc/$$/fd ] || return 0
  setup '[]'; tune '.tunables.idle = 1 | .tunables.poll = 1'
  local H=$XDG_CONFIG_HOME/conveyor/host.json out=$T/$CASE/machine.out lp
  mkdir -p "${H%/*}"; jq -n --arg r "$R" '{records: [{repo: "solo", main: $r}]}' > "$H"
  ( cd "$R" && CONVEYOR_MAIN=$R exec bash "$SRC/conveyor.sh" machine > "$out" 2>&1 ) & mp=$!
  trap 'kill -TERM $mp 2>/dev/null; wait $mp 2>/dev/null' EXIT
  # The fds of <pid> open on the machine's output, fewest of 5 looks (a builtin's redirection holds one more for a moment).
  copies() { local i f n m=''; for i in 1 2 3 4 5; do n=0; for f in /proc/$1/fd/*; do [ ! "$f" -ef "$out" ] || n=$((n + 1)); done; [ -n "$m" ] && [ "$m" -le $n ] || m=$n; sleep 0.1; done; echo "$m"; } # sleep: samples the fd count over half a second, as a re-exec settles; nothing to wait for
  wait_until 'lp=$(jq -r .pid "$ST/loop.json" 2>/dev/null) && [ "$lp" != "$mp" ] && kill -0 "$lp" 2>/dev/null' \
    || fail "the machine did not start the project's loop: $(cat "$out")"
  lp=$(jq -r .pid "$ST/loop.json")
  # The machine: its stdout, its stderr and its own LOGFD.
  [ "$(copies "$mp")" = 3 ] || fail "the machine holds $(copies "$mp") fds on its output, not 3: it kept a copy of stderr when it ran itself again"
  # The loop writes to its reader, never to the machine's output.
  [ "$(copies "$lp")" = 0 ] || fail "the project's loop holds $(copies "$lp") fds on the machine's output, not 0: the machine gave it its copy of stderr"
}
