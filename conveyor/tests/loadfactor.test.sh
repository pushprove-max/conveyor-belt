#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#1084): the load factor of a test run (lib/loadfactor.sh loadfactor()): the load average per core, held
# between 1 and 3, which scales a test file's own `# timeout:` limit (filecmd(), LOADSCALE) and which each run gets
# as CONVEYOR_LOAD_FACTOR (testonce()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# loadfactor(), FILELIMIT, LOADSCALE and filecmd() of the engine, in a subshell whose load reading (p_load) is <load>
# times the machine's cores and with no factor of an outer run (lib.sh gives the cases 1): the factor (factor), or the
# exit of a run, as a card's run makes it, of the test file <file> in $T/$CASE (run), its output in $T/$CASE/out.
loadrun() { # <load per core> factor | run <file>
  local d=$T/$CASE per=$1
  mkdir -p "$d/log"
  ( . "$SRC/lib/loadfactor.sh"; eval "$(sed -n '/^FILELIMIT=/p; /^LOADSCALE=/p; /^filecmd() {/,/^}/p' "$SRC/lib/testrun.sh")"
    unset CONVEYOR_LOAD_FACTOR; p_load() { echo "$((per * $(nproc --all)))"; }
    if [ "$2" = factor ]; then loadfactor; exit; fi
    cd "$d" && CONVEYOR_LOAD_FACTOR=$(loadfactor) CONVEYOR_TEST_LOG=$d/log CONVEYOR_TEST_FILES=$3 bash -c "$(filecmd bash files)" > "$d/out" 2>&1 )
}

# Bug it catches: a factor that is not the load per core, that falls under 1 on an idle machine (a limit cut short),
# or that has no cap, so a test 10 times slower than it should be still passed on a busy machine.
t_loadfactor() {
  local got
  got="$(loadrun 2 factor) $(loadrun 0 factor) $(loadrun 10 factor)"
  [ "$got" = '2 1 3' ] || fail "the factors at 2, 0 and 10 times the cores' load are not 2, 1 and 3: $got"
  got=$( ( . "$SRC/lib/loadfactor.sh"; p_load() { echo 99; }
    CONVEYOR_LOAD_FACTOR=1.5 loadfactor; CONVEYOR_LOAD_FACTOR=7 loadfactor ) | tr '\n' ' ')
  [ "$got" = '1.5 3 ' ] || fail "a run inside a run does not keep the outer factor, held at 3: $got"
}

# Done when 1. Bug it catches: on a machine loaded to twice its cores, a test file that took 1.5 times its own limit
# (# timeout: 2, 3 s) was stopped and failed the run, though it only ran slower.
t_loadslow() {
  printf '%s\n' '# timeout: 2' 'sleep 3' > "$T/$CASE/slow.test.sh" # sleep: 1.5 times its 2 s limit
  loadrun 2 run slow.test.sh || fail "a file 1.5 times over its limit, at a load of twice the cores, failed (exit $?): $(cat "$T/$CASE/out")"
  grep -qxF -- '-- ok slow.test.sh' "$T/$CASE/out" || fail "the file is not named as passed: $(cat "$T/$CASE/out")"
}

# Done when 1. Bug it catches: the factor let a file 4 times over its limit pass, or its failure did not say the
# limit was scaled, so the 4 s it was stopped at could not be read against the file's own 2 s line.
t_loadhang() {
  local rc
  printf '%s\n' '# timeout: 2' 'sleep 8' > "$T/$CASE/hang.test.sh" # sleep: 4 times its 2 s limit
  loadrun 2 run hang.test.sh; rc=$?
  [ "$rc" = 124 ] || fail "a file 4 times over its limit was not stopped as timed out (exit $rc): $(cat "$T/$CASE/out")"
  grep -qxF "conveyor: hang.test.sh timed out: it ran past its time limit, 4 s, and it was stopped there; the limit is its # timeout: line's 2 s times the load factor 2" "$T/$CASE/out" \
    || fail "the timeout does not give the scaled limit and the factor: $(cat "$T/$CASE/out")"
}

# Done when 2. Bug it catches: a card's run gave its test command no load factor, so a host project's test that
# checks a time budget of its own had nothing to scale it by. The run is made as a card's Test step makes it
# (testonce()), at a load of twice the cores, and the command writes the variable it was given.
t_loadenv() {
  local w=$T/$CASE/wt out
  setup '[]'; git -C "$R" worktree add -q --detach "$w" && mkdir -p "$w.testlog" || fail "the worktree"
  # shellcheck disable=SC2034 # LIVE and STUCK are read by watch(), which testonce() runs
  out=$( ( LIVE=0.2 STUCK=1200; unset CONVEYOR_LOAD_FACTOR; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards SLOT_HOME=$T/$CASE/slot
    cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && reportask "$w" \
    && p_load() { echo "$((2 * $(nproc --all)))"; } && testonce "$w" 'printf %s "${CONVEYOR_LOAD_FACTOR-unset}" > "$PWD.factor"' ) 2>&1 ) \
    || fail "the run failed: $out $(cat "$w.test" 2>/dev/null)"
  [ "$(cat "$w.factor")" = 2 ] || fail "the test command was not given the factor 2 in CONVEYOR_LOAD_FACTOR: $(cat "$w.factor")"
}
