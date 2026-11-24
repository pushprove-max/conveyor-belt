#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#1084): the load factor of a test run (lib/loadfactor.sh loadfactor()): the load average per core, held
# between 1 and 3, which scales a test file's own `# timeout:` limit (filecmd(), LOADSCALE) and which each run gets
# as CONVEYOR_LOAD_FACTOR (testonce(), cleanrun()).
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
  ( . "$SRC/lib/loadfactor.sh"; . "$SRC/lib/fileeach.sh"; eval "$(sed -n '/^FILELIMIT=/p; /^LOADSCALE=/p; /^filecmd() {/,/^}/p' "$SRC/lib/testrun.sh")"
    unset CONVEYOR_LOAD_FACTOR; p_load() { echo "$((per * $(nproc --all)))"; }
    if [ "$2" = factor ]; then loadfactor; exit; fi
    cd "$d" && echo "$3" > "$d/list" && CONVEYOR_LOAD_FACTOR=$(loadfactor) CONVEYOR_TEST_LOG=$d/log CONVEYOR_TEST_FILELIST=$d/list bash -c "$(filecmd bash files)" > "$d/out" 2>&1 )
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
# Issue 1662, the same run: the file's command is given the end of its scaled limit (4 s on) in
# CONVEYOR_TEST_END, so its runner's wait for room in the temp space (.conveyor/test-share.sh share_take) ends before
# that limit stops it as a test that ran out of time.
t_loadslow() {
  local e=()
  printf '%s\n' '# timeout: 2' "echo \"\$CONVEYOR_TEST_END \$EPOCHSECONDS\" > $(printf %q "$T/$CASE/end")" 'sleep 3' > "$T/$CASE/slow.test.sh" # sleep: 1.5 times its 2 s limit
  loadrun 2 run slow.test.sh || fail "a file 1.5 times over its limit, at a load of twice the cores, failed (exit $?): $(cat "$T/$CASE/out")"
  grep -qxF -- '-- ok slow.test.sh' "$T/$CASE/out" || fail "the file is not named as passed: $(cat "$T/$CASE/out")"
  read -r -a e < "$T/$CASE/end" 2>/dev/null
  # 3 to 4 s left as it starts (its start can cross a second): the unscaled 2 s limit leaves 2 at most.
  [ ${#e[@]} = 2 ] && [ $((e[0] - e[1])) -ge 3 ] && [ $((e[0] - e[1])) -le 4 ] \
    || fail "a file with a 4 s scaled limit was not given the epoch second it ends at in CONVEYOR_TEST_END (it saw '${e[*]}': the end, then its own clock)"
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

# testonce <worktree> <command> with LIVE, STUCK and TEST_TIMEOUT=2, at a load of LOADX (default 2) times the cores,
# as a card's Test step runs it: the engine as serve.sh loads it, in a subshell; TEST_FILES, not exported as in the
# engine, the lines of $T/$CASE/files. The command `files` is the run of each listed file alone with bash, as filecmd() makes it for a card.
loadonce() {
  # shellcheck disable=SC2034 # LIVE, STUCK, TEST_TIMEOUT and TEST_FILES are read by watch(), testclock() and testonce()
  ( LIVE=0.2 STUCK=1200 TEST_TIMEOUT=2 TEST_FILES=$(cat "$T/$CASE/files" 2>/dev/null); unset CONVEYOR_LOAD_FACTOR; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards SLOT_HOME=$T/$CASE/slot
    cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && reportask "$1" \
    && p_load() { echo "$((${LOADX:-2} * $(nproc --all)))"; } && c=$2 && { [ "$c" != files ] || c=$(filecmd bash files); } && testonce "$1" "$c" )
}
# Bug it catches (O267): the run's clock stopped the run at testTimeout unscaled, while each file's own limit was scaled
# by the load factor, so at a load of three times the cores a file of `# timeout: 2` that took 3 s, inside its scaled
# 6 s, was cut at 2 s by the run (exit 124). With testTimeout 2 and a factor of 3 the run passes. Factor 3, not 2: the
# clock counts whole seconds, and a scaled 4 s left a 3 s file too little time under a loaded test run.
t_loadclock() {
  local w=$T/$CASE/wt rc
  setup '[]'; git -C "$R" worktree add -q --detach "$w" && mkdir -p "$w.testlog" || fail "the worktree"
  printf '%s\n' '# timeout: 2' 'sleep 3' > "$w/slow.test.sh" # sleep: 1.5 times its 2 s limit and the run's
  echo slow.test.sh > "$T/$CASE/files"; LOADX=3 loadonce "$w" files > "$T/$CASE/out" 2>&1; rc=$?
  [ "$rc" = 0 ] || fail "testTimeout 2 at a load factor of 3: slow.test.sh (# timeout: 2, 3 s) did not pass (exit $rc): $(cat "$w.test" "$T/$CASE/out" 2>/dev/null)"
}
# Bug it catches (E8): the check on main keeps its limit by timeout itself (TEST_HARD, mainred.sh verdicts()), and
# that limit was not scaled: with TEST_HARD 2 at a factor of 3, the same file, inside its scaled 6 s, was cut at 2 s.
t_loadhard() {
  local w=$T/$CASE/wt rc
  setup '[]'; git -C "$R" worktree add -q --detach "$w" && mkdir -p "$w.testlog" || fail "the worktree"
  printf '%s\n' '# timeout: 2' 'sleep 3' > "$w/slow.test.sh" # sleep: 1.5 times its 2 s limit and the run's
  echo slow.test.sh > "$T/$CASE/files"; TEST_HARD=2 LOADX=3 loadonce "$w" files > "$T/$CASE/out" 2>&1; rc=$?
  [ "$rc" = 0 ] || fail "TEST_HARD 2 at a load factor of 3: slow.test.sh (# timeout: 2, 3 s) did not pass (exit $rc): $(cat "$w.test" "$T/$CASE/out" 2>/dev/null)"
}
# Bug it catches (E9): with testTimeout 2 at a factor of 2 the run's clock stops a run at 4 s, but the line that says
# it timed out (testfails(): timeout.sec, which the card's reason prints) said 2 s.
t_loadsaid() {
  local w=$T/$CASE/wt rc out
  setup '[]'; git -C "$R" worktree add -q --detach "$w" && mkdir -p "$w.testlog" || fail "the worktree"
  loadonce "$w" 'sleep 30' > "$T/$CASE/out" 2>&1; rc=$? # sleep: a run the clock ends at its scaled 4 s
  [ "$rc" = 124 ] || fail "the run of 30 s under testTimeout 2 did not time out (exit $rc): $(cat "$w.test" "$T/$CASE/out" 2>/dev/null)"
  out=$( (export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; TEST_TIMEOUT=2; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && testfails "$w.test" 124 | jq -c .timeout) 2>&1)
  [ "$(jq -c .sec <<<"$out" 2>/dev/null)" = 4 ] || fail "the run cut by its clock at 4 s (testTimeout 2, factor 2) says it timed out after: $out"
}
# Bug it catches (O253): the card's test files went to its command as one value of the environment
# (CONVEYOR_TEST_FILES), and 4,000 paths of 42 bytes passed Linux's 128 KiB limit of one: the command did not start.
# They go in a file (CONVEYOR_TEST_FILELIST): the command starts and reads every path.
t_loadlist() {
  local w=$T/$CASE/wt rc
  setup '[]'; git -C "$R" worktree add -q --detach "$w" && mkdir -p "$w.testlog" || fail "the worktree"
  for i in $(seq 4000); do printf 'tests/%033d.sh\n' "$i"; done > "$T/$CASE/files"
  loadonce "$w" 'grep -c . "$CONVEYOR_TEST_FILELIST" > "$PWD.n"' > "$T/$CASE/out" 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(cat "$w.n" 2>/dev/null)" = 4000 ] \
    || fail "with TEST_FILES of 4000 42-byte paths, the test command did not start and read them all (exit $rc, read $(cat "$w.n" 2>&1)): $(cat "$w.test" "$T/$CASE/out" 2>/dev/null | tail -n 5)"
}
# Bug it catches (#1154): the clean run that checks a failure on main and runs its controls (cleanrun(), lib/mainred.sh)
# starts the command with `env -i` and left CONVEYOR_LOAD_FACTOR out, so a file there was held to its unscaled limit.
# And (O267) the clean run ended its command at testTimeout unscaled, while each file's own limit was scaled: with
# testTimeout 2 at a factor of 2, a command of 3 s, inside its scaled 4 s, was cut at 2 s (exit 124).
# And (O253) the repair lane's clean run gets the card's files as testonce() does, in a file (CONVEYOR_TEST_FILELIST):
# 4,000 paths of 42 bytes in one value of the environment pass Linux's 128 KiB limit of one, and the command does not start.
t_loadclean() {
  local w=$T/$CASE/wt out c files
  setup '[]'; git -C "$R" worktree add -q --detach "$w" || fail "the worktree"
  files=$(for i in $(seq 4000); do printf 'tests/%033d.sh\n' "$i"; done)
  c='printf %s "${CONVEYOR_LOAD_FACTOR-unset}" > "$PWD.factor"; grep -c . "$CONVEYOR_TEST_FILELIST" > "$PWD.n"; sleep 3' # sleep: 1.5 times testTimeout 2, inside its scaled 4 s
  # shellcheck disable=SC2034 # LIVE, STUCK and TEST_FILES are read by watch() and cleanrun()
  out=$( ( LIVE=0.2 STUCK=1200 TEST_TIMEOUT=2 TEST_FILES=$files; unset CONVEYOR_LOAD_FACTOR; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards SLOT_HOME=$T/$CASE/slot
    cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" \
    && p_load() { echo "$((2 * $(nproc --all)))"; } && cleanrun "$w" "$c" ) 2>&1 ) \
    || fail "testTimeout 2 at a load factor of 2: the clean run of a 3 s command (inside its scaled 4 s) failed: $out $(cat "$w.test" 2>/dev/null)"
  [ "$(cat "$w.factor")" = 2 ] || fail "the clean run's command was not given the factor 2 in CONVEYOR_LOAD_FACTOR: $(cat "$w.factor")"
  [ "$(cat "$w.n" 2>/dev/null)" = 4000 ] || fail "with TEST_FILES of 4000 42-byte paths, the clean run's command did not read them all from CONVEYOR_TEST_FILELIST (read $(cat "$w.n" 2>&1))"
}
