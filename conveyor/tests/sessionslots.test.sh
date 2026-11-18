#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a test run started inside a card's build, fix or rebase session (its mark, CONVEYOR_CARD) holds at
# most the pack's tunables.sessionTestSlots of the machine's test slots at once (lib/slots.sh slot_session,
# slot_permit, slot_take). One session's run of 342 cases held about 12 slots while five other cards built, and the
# machine's load went from about 10 to 46. A run with no mark (the loop's test step) keeps its share.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Six workers of a run, taken as the runner takes them (../conveyor.test.sh: slot_take, slot_mine in the worker,
# slot_free), from a free pool of 10 slots of the case's own (fewer on a machine with fewer cores), each holding its
# slot for 1 s, in the session of card <card> (none: no session's mark). Prints the most slots of the pool held at
# once, sampled every 0.05 s while the workers run; each worker that ran writes a line in $T/$CASE/ran. A machine of
# fewer than 4 cores cannot show a run above a cap of 2 or 3: it prints "few".
sixrun() { # [<card>] [whole]
  local d=$T/$CASE n p=0 i=0
  export XDG_CONFIG_HOME=$d/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 10, \"testSlotsDir\": \"$d/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the case's host file could not be written"
  CONVEYOR_CARD=${1:-} slot_pool || fail "the pool could not be read"
  [ "$SLOT_N" -ge 4 ] || { echo few; return 0; }
  # whole: the run is a whole suite's, which takes its turn, and a home slot of the pool, before its first worker.
  [ "${2:-}" != whole ] || slot_whole 2>/dev/null || fail "the whole-suite run could not take its turn"
  ( for _ in 1 2 3 4 5 6; do
      slot_take
      ( slot_mine; sleep 1; echo x >> "$d/ran" ) & # sleep: the worker holds its slot long enough to be counted
      slot_free
    done; wait; : > "$d/done" ) &
  while [ ! -e "$d/done" ] && [ $i -lt 600 ]; do n=$(slot_used); [ "$n" -le "$p" ] || p=$n; i=$((i + 1)); sleep 0.05; done
  [ -e "$d/done" ] || fail "the run's six workers did not end in 30 s"
  echo "$p"
}

# The issue's run: with the session's mark and the cap's default (no pack in the case's folder), never more than 2 slots at
# once, and all six workers still run. Without the cap this run held all six.
t_sessionslots() {
  local p
  p=$(sixrun c20261118T000000-test-1) || exit 1
  [ "$p" != few ] || return 0
  [ "$p" -le 2 ] || fail "a run in a card's session held $p test slots at once, not at most 2"
  [ "$p" -ge 1 ] || fail "a run in a card's session held no slot"
  [ "$(wc -l < "$T/$CASE/ran")" = 6 ] || fail "not every worker of the session's run ran: $(wc -l < "$T/$CASE/ran") of 6"
}

# A whole-suite run in a session (the issue's run: bash conveyor/conveyor.test.sh with no case named) holds at most 2
# slots too. Without a permit for the home slot slot_whole takes, its home turns and two permitted pool slots held 3.
t_sessionslotswhole() {
  local p
  p=$(sixrun c20261118T000000-test-1 whole) || exit 1
  [ "$p" != few ] || return 0
  [ "$p" -le 2 ] || fail "a whole-suite run in a card's session held $p test slots at once, not at most 2"
  [ "$(wc -l < "$T/$CASE/ran")" = 6 ] || fail "not every worker of the session's whole-suite run ran: $(wc -l < "$T/$CASE/ran") of 6"
}

# A run with no session's mark (the loop's own test step, the check on main, a release) keeps its share: the same run
# holds more than 2 slots at once. Without this, a cap on every run would pass t_sessionslots.
t_sessionslotsoff() {
  local p
  p=$(sixrun) || exit 1
  [ "$p" != few ] || return 0
  [ "$p" -gt 2 ] || fail "a run with no session's mark held at most $p test slots at once: it lost its share"
}

# The cap is the pack's tunables.sessionTestSlots, read from the checkout the run starts in: set to 3 there, the run
# holds 3 at once, not the default 2.
t_sessionslotspack() {
  local p d=$T/$CASE/p
  git init -q "$d" && mkdir -p "$d/.conveyor" && jq '.tunables.sessionTestSlots = 3' "$SRC/lib/test-pack.json" > "$d/.conveyor/project.json" \
    || fail "the case's checkout could not be made"
  cd "$d" || fail "no checkout"
  p=$(sixrun c20261118T000000-test-1) || exit 1
  [ "$p" != few ] || return 0
  [ "$p" = 3 ] || fail "a run in a session whose pack sets sessionTestSlots to 3 held $p test slots at once, not 3"
}

# A whole-suite run in a session that waits for a permit of its session's (both held by other runs of the session)
# makes no other run wait: a whole-suite run with no mark that asks after it (the check on main) takes its turn at once.
# When the session's run asked for its turn before it had a permit, its empty ticket held the check on main back
# until the session's other runs ended, while turns and slots were free.
t_sessionslotsqueue() {
  local d=$T/$CASE c=$T/$CASE/slots/session/c20261118T000000-test-1 i=0
  export XDG_CONFIG_HOME=$d/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$c" && echo "{\"testSlots\": 10, \"testSlotsDir\": \"$d/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" \
    && : > "$c/1" && : > "$c/2" || fail "the case's host file or permits could not be made"
  # The session's other runs: a process of its own holds both permits, so the runs below do not inherit their locks.
  ( exec 7>>"$c/1" 8>>"$c/2"; flock 7 && flock 8 && : > "$d/held"; while [ ! -e "$d/release" ]; do sleep 0.1; done ) &
  while [ ! -e "$d/held" ] && [ $i -lt 100 ]; do i=$((i + 1)); sleep 0.05; done
  [ -e "$d/held" ] || fail "the session's permits could not be held"
  ( CONVEYOR_CARD=c20261118T000000-test-1 slot_pool && slot_whole 2>/dev/null && : > "$d/session" ) &
  sleep 1 # sleep: the session's run asks first; it waits on a permit and leaves nothing to see while it waits
  ( slot_pool && slot_whole 2>/dev/null && : > "$d/main" ) &
  i=0; while [ ! -e "$d/main" ] && [ $i -lt 200 ]; do i=$((i + 1)); sleep 0.05; done
  : > "$d/release"
  [ -e "$d/main" ] || fail "a whole-suite run with no mark waited for its turn behind a session's run that waited for a permit"
  i=0; while [ ! -e "$d/session" ] && [ $i -lt 200 ]; do i=$((i + 1)); sleep 0.05; done
  [ -e "$d/session" ] || fail "the session's whole-suite run did not take its turn once a permit was free"
}
