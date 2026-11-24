#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# The Conveyor loop and its report against a scratch repo, with gh, claude and codex stubbed on PATH.
# The runner only: the shared setup is tests/lib.sh and each case is in the area file it belongs to, tests/*.test.sh.
# A new case goes in its area's file, or a new one, never here. CONVEYOR_SHELL_TEST_CASE=<case>[,<case>] runs only
# those cases, as do case names given as arguments when it is not set; an unknown name exits 2.
set -uo pipefail
. "$(dirname "$0")/tests/lib.sh"
for f in "$SRC"/tests/*.test.sh; do . "$f"; done
ALL=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$SRC"/tests/*.test.sh | tr '\n' ' ')
# Each case's limit in seconds, its file's `# timeout:` line, the same in a card's run of that file and in a
# whole-suite run (run_case, case_keep): a case past it is stopped and fails as timed out, and the run goes on (but with FAST, below). In one
# process for all cases, no file's limit applied: one hung case stood a release still for 43 minutes with no error.
declare -A CASE_LIMITS=()
# shellcheck disable=SC2034 # CASE_LIMITS is read by run_case (tests/lib.sh)
while read -r LIMIT_CASE LIMIT_SEC; do CASE_LIMITS[$LIMIT_CASE]=$LIMIT_SEC; done < <(awk 'FNR == 1 { n = "" }
  n == "" && /^# timeout: [0-9]+$/ { n = $3 }
  n != "" && /^t_[a-z0-9]+\(\) \{/ { c = $0; sub(/^t_/, "", c); sub(/\(.*/, "", c); print c, n }' "$SRC"/tests/*.test.sh)
unset LIMIT_CASE LIMIT_SEC
SEL=${CONVEYOR_SHELL_TEST_CASE:-${*:-$ALL}}; SEL=${SEL//,/ }
# The selection is this run's, not its cases': a case that starts a runner of its own (t_slotwhole) names its cases, or
# runs them all. The Test step's run again of the failed cases names them here (.conveyor/test-changed.sh).
# CONVEYOR_TEST_TIMES names a file it writes, once its cases end, the time of each case file whose every case it ran
# (case_times()), for the times the Test step records of a test file. The run's own, not its cases'.
TIMES=${CONVEYOR_TEST_TIMES:-}
# CONVEYOR_TEST_FAILFAST=1 (a card's run with the rule Stop a card's tests at the first failure on: lib/fileeach.sh)
# stops the run at its first failed case: no case starts after it, each case still running is ended (case_halt()),
# and the output names the cases not run. The run's own, not its cases': a loop a case runs reads its own rule.
FAST=${CONVEYOR_TEST_FAILFAST:-}
unset CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_TIMES CONVEYOR_TEST_FAILFAST
for CASE in $SEL; do case " $ALL " in *" $CASE "*) ;; *) echo "unknown case $CASE" >&2; exit 2 ;; esac; done
# As many cases at once as it gets of the machine's test slots (lib/slots.sh), never a number of its own: a case
# starts once the runner holds a slot for it (the run's home slot, or one of the pool), and the slot is the case's from
# there (run_case). A run started inside a card's session gets at most the pack's tunables.sessionTestSlots of them
# (slot_session, read by slot_pool in tests/lib.sh before that file unsets the session's mark). The slowest
# (conveyor.slowest) start first. What the runner does before its first case and after its
# last starts no program a case (a grep or cat each): 300 of each held a whole-suite run up for about 1.3 s.
FIRST=$(for CASE in $(sed -n 's/^\([a-z0-9]*\) .*/\1/p' "$SRC/conveyor.slowest"); do case " $SEL " in *" $CASE "*) echo "$CASE" ;; esac; done)
REST=$(for CASE in $SEL; do case $'\n'$FIRST$'\n' in *$'\n'$CASE$'\n'*) ;; *) echo "$CASE" ;; esac; done)
# Told to end (its timeout's TERM, an interrupt), the runner tells each case's worker, which ends its case and all the
# case started (run_case), and is gone only when they are: no loop of a case outlives the run. Killed with its
# workers and no word (KILL to its group), it tells no one: each case's keeper sees its worker gone and ends the case.
trap 'trap "" TERM INT HUP; kill -TERM $(jobs -p) 2>/dev/null; wait; exit 143' TERM INT HUP
# A run of every case is a whole-suite run: it waits for its turn (lib/slots.sh slot_whole), at most two at once, before
# its first case starts. A run of chosen cases takes no turn.
# How many cases it selected, for a loop's live record of the run (conveyor.sh watch()): a case named twice runs once.
N=$(tr ' ' '\n' <<<"$SEL" | grep . | sort -u | wc -l); echo "TESTRUN cases=$((N))"
[ "$N" -ne "$(wc -w <<<"$ALL")" ] || slot_whole || exit 1
# With FAST: RUN is each case started whose end has not been read (its worker), RED the first that failed.
declare -A RUN=(); RED=
# A case that ended failed (its exit in $T/<case>.rc not 0, or its worker gone with none): RED names it. Read with the
# shell's own read, no program a case.
case_red() {
  local c got
  for c in "${!RUN[@]}"; do
    got=; { read -r got < "$T/$c.rc"; } 2>/dev/null || { ! kill -0 "${RUN[$c]}" 2>/dev/null || continue; read -r got < "$T/$c.rc"; } 2>/dev/null
    [ "$got" = 0 ] || { RED=$c; return 0; }
    unset "RUN[$c]"
  done
  return 1
}
# The first failed case's stop: each case still running (no exit written) is ended as at the run's end (run_case),
# and is named, with each case not started, as not run.
case_halt() {
  local c no=()
  for c in "${!RUN[@]}"; do [ -e "$T/$c.rc" ] || { kill -TERM "${RUN[$c]}" 2>/dev/null; [ ! -d "${CONVEYOR_TEST_LOG:-}" ] || rm -f "$CONVEYOR_TEST_LOG/cases/$c"; }; done
  wait
  for c in $SEL; do [ -e "$T/$c.rc" ] || no+=("$c"); done
  [ ${#no[@]} = 0 ] || echo "conveyor: the run stopped at its first failed case, $RED; not run: ${no[*]}"
}
# With FAST, the wait for a slot looks for a failed case too (SLOT_STOP): a push that takes each slot coming free
# would else hold the runner in slot_take while the cases still running go on.
for CASE in $FIRST $REST; do
  SLOT_STOP=${FAST:+case_red} slot_take || break
  [ -z "$FAST" ] || ! case_red || { slot_free; break; }
  run_case &
  [ -z "$FAST" ] || RUN[$CASE]=$!
  slot_free
done
# sleep: with FAST, the run looks for a failed case among those still running, as a case's own end says nothing to it
if [ -n "$FAST" ]; then while [ -z "$RED" ] && [ ${#RUN[@]} -gt 0 ]; do case_red || sleep 0.2; done; fi
[ -z "$RED" ] || case_halt
wait
[ -z "$TIMES" ] || case_times "$SRC"/tests/*.test.sh > "$TIMES"
for CASE in $SEL; do got=; read -r got < "$T/$CASE.rc"; [ "$got" = 0 ] || exit 1; done
