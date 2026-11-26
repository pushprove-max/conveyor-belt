# SPDX-License-Identifier: Apache-2.0
# The tests' one way to wait: for a condition, never for a set time and a check after it (on a busy machine the set
# time is over before the thing has happened). Sourced by the engine cases' setup (lib.sh) and by each test file that
# waits on its own; the test lint (.conveyor/test-lint.sh) fails a sleep that stands in for one of these.
# wait_until <condition> [<state>]: runs the condition (shell text, as it would stand after `until`) every 0.1 s until
# it holds. The ceiling, WAIT_CEILING seconds (120), guards against a hang; it is no claim about how long the thing
# takes. A run of the condition that is still going at the ceiling is ended there, with all it started, so a condition
# that blocks does not pass the ceiling. When it is reached: prints the condition and the last state (what <state>,
# shell text too, prints then; with none, what the condition's last run printed, or its exit status, or that it was
# still running) and returns 1. <state> has the ceiling's time of its own, and is ended the same way when it blocks.
wait_until() {
  local cond=$1 state=${2:-} out rc crc end=$((SECONDS + ${WAIT_CEILING:-120}))
  while :; do
    wait_run "$cond" $((end - SECONDS))
    [ "$rc" != 0 ] || return 0
    [ "$rc" != running ] && [ "$SECONDS" -lt "$end" ] || break
    sleep 0.1 # sleep: the pause between two checks of the condition
  done
  crc=$rc; [ "$rc" != running ] || out="${out:+$out; }the condition was still running"
  [ -z "$state" ] || { wait_run "$state" "${WAIT_CEILING:-120}"; [ "$rc" != running ] || out="${out:+$out; }the state was still running"; }
  echo "wait_until: not true after ${WAIT_CEILING:-120} s: $cond" >&2
  echo "wait_until: last state: ${out:-exit $crc, nothing printed}" >&2
  return 1
}
# wait_run <shell text> <seconds>: runs the text for that long at most, and sets the caller's out (what it printed) and
# rc (its exit status, or `running` when it was still going and was ended, with all it started).
wait_run() {
  local fd p part s left first end=$((SECONDS + ($2 > 0 ? $2 : 1)))
  # The run's output, then its exit status on a last line of its own, read until the run ends or its time is over.
  exec {fd}< <( (eval "$1") 2>&1; printf '\n%s' "$?"); p=$!
  # A read ends at a NUL byte the run prints: the byte is dropped and the read goes on, in the time that is left, so
  # what stood before it does not pass for the whole output, and its last line for the exit status, while the run goes on.
  # The time that is left is taken from the clock once a read, and the read is given what was checked: taken again after
  # the check, it is 0 when the clock has moved on between the two, and a read with no time fails at once on a run that
  # has printed nothing more, which would pass for the run's end. The first read is always made, with 1 s at least: the
  # clock counts whole seconds, and when it moves on between setting the end and the first check, a run that has
  # already ended would otherwise pass for one still running.
  out=; rc=running; first=1
  while left=$((end - SECONDS)); [ "$left" -gt 0 ] || [ -n "$first" ]; do
    first=; IFS= read -r -d '' -t "$((left > 0 ? left : 1))" -u "$fd" part; s=$?; out+=$part
    [ "$s" = 0 ] || { [ "$s" -gt 128 ] || { rc=${out##*$'\n'}; out=${out%$'\n'*}; }; break; }
  done
  exec {fd}<&-
  [ "$rc" != running ] || wait_end "$p"
  wait "$p" 2>/dev/null || :
  while [[ $out == *$'\n' ]]; do out=${out%$'\n'}; done
}
# wait_end <pid>: ends that process and every process under it, whatever signal they ignore. Each is stopped before
# its children are listed, so it starts none after, and then killed.
wait_end() {
  local k kids; kill -STOP "$1" 2>/dev/null; kids=$(pgrep -P "$1") || :
  kill -KILL "$1" 2>/dev/null
  for k in $kids; do wait_end "$k"; done
}
# under <pid> <name>: whether a process named <name> runs under <pid> (a child, a child's child, and so on). A command
# that waits at a lock is seen by this, not by a pause: its flock runs under it for as long as it waits.
under() {
  local k
  pgrep -P "$1" -x "$2" > /dev/null && return 0
  for k in $(pgrep -P "$1"); do under "$k" "$2" && return 0; done
  return 1
}
# cases_side <prefix> <case>...: runs <prefix><case> for each case in a background shell, at most 8 at a time,
# starting the next when one ends, then waits for the rest. Returns 1 when a case failed. Only its own shells are
# counted and waited for: a background job the caller started before is left alone.
cases_side() {
  local prefix=$1 c p ended rc=0; local -a pids=() left; shift
  for c; do
    if [ "${#pids[@]}" -ge 8 ]; then
      wait -n -p ended "${pids[@]}" || rc=1
      left=(); for p in "${pids[@]}"; do [ "$p" = "$ended" ] || left+=("$p"); done; pids=("${left[@]}")
    fi
    "$prefix$c" & pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p" || rc=1; done
  return "$rc"
}
