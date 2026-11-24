#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the free disk floor (tunables.minFreeDiskGb) pauses picks.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: a host short of disk starts new cards, which then fail their steps and record writes; the state does not say
# why the loop picks nothing; a card already in flight is stopped by the pause; a df that cannot be read pauses the
# loop; free space back over the floor does not start picks again.
# The free space df reports for the card folder: $STUB/free, in KB, or "fail" for a df that gives nothing (exit 1). A
# file of several lines gives one a call, the last for good: a check that reads df twice sees two readings.
# Bug: df asked of another folder than the card folder ($T/$CASE/cards, in $STUB/dir) gives nothing, so a floor read
# of the wrong folder pauses nothing and the cases fail.
dfsetup() { # <issues json>
  setup "$1"
  echo "$GO" > "$STUB/review.1" # each case lands one card: its one review passes
  echo "$T/$CASE/cards" > "$STUB/dir"
  # df as an exported bash function, not a program on PATH: on macOS p_path puts Homebrew's df first on PATH, and the
  # engine's bash runs a function of that name before any program. The case sets the free space; the host's is not read.
  df() { [ "$*" = "-Pk $(cat "$STUB/dir")" ] || return 1
    local f; f=$(head -n 1 "$STUB/free"); [ "$f" != fail ] || return 1
    [ "$(wc -l < "$STUB/free")" -le 1 ] || { tail -n +2 "$STUB/free" > "$STUB/free.n" && mv "$STUB/free.n" "$STUB/free"; }
    echo "Filesystem 1024-blocks Used Available Capacity Mounted on"; echo "/dev/x 99999999 1 $f 1% /"; }
  export -f df
}
GB=1048576 # KB in a GB, as the floor counts one

t_diskfloor() {
  dfsetup "$(jq -cs . <(issue 5 2026-01-01 P2))"
  # Under the 3 GB default floor: a real loop run picks nothing and says why. Health names the reason.
  echo $((GB * 5 / 2)) > "$STUB/free"
  # loop: only a run shows the loop's own turn reads the floor before its pick and says why it picked nothing (no card is built)
  out=$(loop run 2>&1); [ -z "$(st 'select(.step == "picked") | .issue')" ] && grep -qF 'the loop is paused: free disk 2.5 GB under the 3 GB floor;' <<<"$out" \
    || fail "free disk 2.5 GB under the floor: a card was picked, or the run did not say why: $out"
  # A loop that keeps running: a whole turn under the floor picks nothing and health names the reason; free space back
  # over the floor between two of its turns, and the same loop picks #5 and lands it, with no step by anyone.
  tune '.tunables.idle = 1 | .tunables.poll = 1'; watchturns
  loop serve > "$STUB/serve.out" 2>&1 & lp=$! # loop: only the running loop's own turns show picks stop under the floor and start again once space is back
  trap 'kill $lp 2>/dev/null' EXIT
  turns 1
  [ -z "$(st 'select(.step == "picked") | .issue')" ] && [ "$(loop health | jq -r .state)" = 'paused: free disk 2.5 GB under the 3 GB floor' ] \
    || fail "the running loop with 2.5 GB free picked a card, or health did not say why: $(loop health | jq -c .state) $(cat "$STUB/serve.out")"
  atturn "echo $((GB * 4)) > '$STUB/free'"
  wait_until "[ -n \"\$(st 'select(.issue == 5 and .step == \"landed\") | .sha' 2>/dev/null)\" ]" "cat '$STUB/serve.out'" \
    || fail "the running loop did not land #5 once free space was back over the floor at 4 GB: $(loop health | jq -c .state)"
  [ "$(loop health | jq -r .state)" = running ] || fail "health with 4 GB free: $(loop health | jq -c .state)"
  kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
  # Bug: health reads df once for its state and again for its Disk row, so one report shows two free spaces. df gives
  # 2.5 GB, then 4 GB: both parts of the one report show the first.
  printf '%s\n' $((GB * 5 / 2)) $((GB * 4)) > "$STUB/free"
  h=$(loop health | jq -c '[.state, .diskFreeKb]')
  [ "$h" = "[\"paused: free disk 2.5 GB under the 3 GB floor\",$((GB * 5 / 2))]" ] || fail "health with df giving 2.5 GB then 4 GB: $h"
  # Bug: a floor written as 1e1 (packget gives 1E+1) is read as no number and the 3 GB default holds: 4 GB free picks.
  # The pack's floor of 10 GB puts 4 GB free under it.
  tune --argjson x 1e1 '.tunables.minFreeDiskGb = $x'
  [ "$(loop health | jq -r .state)" = 'paused: free disk 4 GB under the 10 GB floor' ] || fail "health with the pack's floor 1e1 (10 GB) and 4 GB free: $(loop health | jq -c .state)"
}

# A df that gives nothing: no pause on missing data, and health shows free disk as unknown.
t_diskunread() {
  dfsetup "$(jq -cs . <(issue 5 2026-01-01 P2))"
  echo fail > "$STUB/free"
  # loop: only a run shows the loop's own turn picks when the free space does not read
  out=$(loop run 2>&1); [ -n "$(st 'select(.issue == 5 and .step == "landed") | .sha')" ] && [ "$(loop health | jq -c '[.state, .diskFreeKb]')" = '["running",null]' ] \
    || fail "with df unreadable the run did not land #5: $(loop health | jq -c '[.state, .diskFreeKb]') $out"
}

t_diskflight() {
  dfsetup "$(jq -cs . <(issue 5 2026-01-01 P1) <(issue 6 2026-02-01 P2))"
  loop control cap 1 >/dev/null
  echo $((GB * 10)) > "$STUB/free"
  echo "$GO" > "$STUB/review.2" # the stub counts every review call: a retried review of #5 passes too
  tune '.tunables.idle = 1 | .tunables.poll = 1'; watchturns
  # #5's build drops the free space under the floor while its card is in flight, then waits for the loop to begin two
  # more turn waits (one whole turn under the floor) before it ends: that turn must leave the card to land, and #6 is
  # never picked. A build that sees no such turn fails, and #5 does not land.
  echo "echo $((GB * 2)) > \"\$STUB/free\"; n=\$((\$(wc -l < \"\$TURNS\") + 2)); for i in \$(seq 600); do [ \"\$(wc -l < \"\$TURNS\")\" -lt \$n ] || break; sleep 0.1; done
[ \"\$(wc -l < \"\$TURNS\")\" -ge \$n ] || { echo 'no loop turn while in flight' > \"\$STUB/noturn\"; exit 1; }; echo two >> a.txt" > "$STUB/build"
  # loop: only a run shows the loop's later turns leave the card in flight to land and start no new card
  out=$(loop run 2>&1)
  [ ! -e "$STUB/noturn" ] || fail "the loop took no whole turn while #5 was in flight under the floor: $out"
  [ "$(st 'select(.step == "picked") | .issue' | tr '\n' ' ')" = '5 ' ] || fail "the loop picked under the floor: $(st 'select(.step == "picked") | .issue' | tr '\n' ' ') $out"
  [ -n "$(st 'select(.issue == 5 and .step == "landed") | .sha')" ] || fail "the card in flight when space fell under the floor did not land: $(st 'select(.issue == 5) | [.step, .result, .reason] | tostring')"
}
