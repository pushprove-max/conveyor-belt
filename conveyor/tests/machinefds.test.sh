#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the fds the machine's Conveyor (`conveyor.sh machine`) and the loops it starts hold.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: the machine kept its copy of stderr (LOGFD) when it ran itself again as the reaper of what it starts, and gave
# it to each loop it started; with the copy each conveyor.sh makes of its own, these added up to hundreds of fds in
# every loop and card, so a card's test runner got fd 255, bash's own, and its slot and lock cases failed. Linux alone
# has /proc and the reaper's run again. The machine runs from a code repo's checkout (coderepo), so its loop follows
# that checkout's HEAD and restarts on each move.
t_machinefds() {
  [ -d /proc/$$/fd ] || return 0
  setup '[]'; tune '.tunables.idle = 1 | .tunables.poll = 1'
  local H=$XDG_CONFIG_HOME/conveyor/host.json out=$T/$CASE/machine.out lp fds c n
  coderepo; git -C "$D" reset -q --hard "$A" || fail "the checkout was not put back on $A"
  mkdir -p "${H%/*}"; jq -n --arg r "$R" '{records: [{repo: "solo", main: $r}]}' > "$H"
  ( cd "$R" && CONVEYOR_MAIN=$R exec bash "$D/conveyor/conveyor.sh" machine > "$out" 2>&1 ) & mp=$!
  trap 'kill -TERM $mp 2>/dev/null; wait $mp 2>/dev/null' EXIT
  # The fds of <pid> open on the machine's output, fewest of 5 looks (a builtin's redirection holds one more for a moment).
  copies() { local f n m=''; for _ in 1 2 3 4 5; do n=0; for f in /proc/$1/fd/*; do [ ! "$f" -ef "$out" ] || n=$((n + 1)); done; [ -n "$m" ] && [ "$m" -le $n ] || m=$n; sleep 0.1; done; echo "$m"; } # sleep: samples the fd count over half a second, as a re-exec settles; nothing to wait for
  copies() { local f n m=''; for _ in 1 2 3 4 5; do n=0; for f in /proc/$1/fd/*; do [ ! "$f" -ef "$out" ] || n=$((n + 1)); done; [ -n "$m" ] && [ "$m" -le $n ] || m=$n; sleep 0.1; done; echo "$m"; } # sleep: the looks are spread over 0.5 s
  wait_until 'lp=$(jq -r .pid "$ST/loop.json" 2>/dev/null) && [ "$lp" != "$mp" ] && kill -0 "$lp" 2>/dev/null' \
    || fail "the machine did not start the project's loop: $(cat "$out")"
  lp=$(jq -r .pid "$ST/loop.json")
  # The machine: its stdout and its own LOGFD (its stderr is the pipe to its reader, machineerr); a copy kept is a third.
  [ "$(copies "$mp")" = 2 ] || fail "the machine holds $(copies "$mp") fds on its output, not 2: it kept a copy of stderr when it ran itself again"
  # The loop writes to its reader, never to the machine's output.
  [ "$(copies "$lp")" = 0 ] || fail "the project's loop holds $(copies "$lp") fds on the machine's output, not 0: the machine gave it its copy of stderr"
  # Bug (#213, asked for by #216): each restart of serve kept fds (a copy of stderr, LOGFD), so after hundreds the lock and slot fds of
  # its cards were above 255. Its count of open fds that a restart's exec keeps, fewest of 20 looks over 2 s (a turn
  # holds some for a moment), is no higher after three restarts. Only fds with no close-on-exec flag (O_CLOEXEC, 02000000
  # in /proc's fdinfo flags) are counted, as only those can be kept: bash's own copy of stderr while a command's stderr
  # is redirected has the flag and is closed again between commands, so a look that fell between them counted one less
  # before the restarts than after (#1266).
  count() { local n m=''; for _ in {1..20}; do n=$(cat "/proc/$lp/fdinfo/"* 2>/dev/null | awk '$1 == "flags:" && substr($2, length($2) - 6, 1) !~ /[2367]/ { n++ } END { print n + 0 }'); [ -n "$m" ] && [ "$m" -le "$n" ] || m=$n; sleep 0.1; done; echo "$m"; } # sleep: the looks are spread over 2 s
  # At least its stdin, stdout and stderr, which have no close-on-exec flag: fewer, and the flags were not read.
  fds=$(count); [ "$fds" -ge 3 ] || fail "serve's fds with no close-on-exec flag could not be counted from /proc/$lp/fdinfo: $fds"
  for c in "$B" "$A" "$B"; do
    git -C "$D" reset -q --hard "$c" || fail "the checkout did not move to $c"
    wait_until '[ "$(jq -r .commit "$ST/loop.json" 2>/dev/null)" = "$c" ] && [ "$(jq -r .pid "$ST/loop.json")" = "$lp" ]' \
      || fail "the loop did not restart in its own process on $c: $(cat "$out")"
  done
  n=$(count); [ "$n" -le "$fds" ] || fail "serve holds $n fds after three restarts, $fds before: each restart kept some"
}
