#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#1594): a card's test files run side by side, each on a test slot of its own (lib/fileeach.sh
# fileeach(), the command filecmd() of lib/testrun.sh makes for a card's list), with the result, failures and output
# of a run one at a time, never more at once than the slots the run holds, and all of them stopped with the run.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The worktree $T/$CASE/wt of a fresh main, and a pool of the case's own of <n> slots (the host file's testSlots, in a
# folder no other case shares), so the slots the run can hold are those <n>.
sidewt() { # <n>
  export XDG_CONFIG_HOME=$T/$CASE/config
  setup '[]'; git -C "$R" worktree add -q --detach "$T/$CASE/wt" && mkdir -p "$T/$CASE/wt.testlog" "$XDG_CONFIG_HOME/conveyor" \
    && echo "{\"testSlots\": $1, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the worktree and its pool"
}
# A test file <name> of the worktree that waits, up to 10 s times the load factor, until <n> files of the run have
# begun (each leaves its mark in $T/$CASE/at), prints how many it saw, then passes, or with fail prints a failing case
# `bad` and fails. Run one at a time, the first sees 1 and the run takes 10 s a file.
sidefile() { # <name> <n> [fail]
  local end='echo "ok one"'; [ "${3:-}" != fail ] || end='echo "FAIL [bad]: wrong"; exit 1'
  printf '%s\n' "d=$T/$CASE/at; mkdir -p \"\$d\"; : > \"\$d/\$CONVEYOR_TEST_N\"" \
    "i=0; while [ \"\$(ls \"\$d\" | wc -l)\" -lt $2 ] && [ \$i -lt $(loadlimit 200) ]; do i=\$((i + 1)); sleep 0.05; done" \
    'echo "saw $(ls "$d" | wc -l)"' "$end" > "$T/$CASE/wt/$1"
}
# A card's run of the test files <file>... of the worktree, each alone with bash, as its Test step runs it: the command
# filecmd() makes for a card's list, run by testonce() with the engine as serve.sh loads it. SLOT_HOME is set, so the run
# itself takes no slot (as in loadfactor.test.sh): each file takes one of the case's pool. With SIDEFAST set, the run
# stops at its first failure (filecmd() fast: failfast.test.sh). Exits as the run;
# testfails()'s reading of its output is in $T/$CASE/fails.
siderun() { # <file>...
  local w=$T/$CASE/wt
  # shellcheck disable=SC2034 # LIVE, STUCK, TEST_TIMEOUT, TEST_FILES and TEST_GIVEN (as listcmd() sets them) are read by watch(), testclock() and testonce()
  ( LIVE=0.2 STUCK=1200 TEST_TIMEOUT=${SIDELIMIT:-60} TEST_FILES=$(printf '%s\n' "$@") TEST_GIVEN=$#; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards SLOT_HOME=$T/$CASE/slot
    cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" || exit 99
    testonce "$w" "$(filecmd bash files ${SIDEFAST:+fast})"; rc=$?; testfails "$w.test" "$rc" > "$T/$CASE/fails"; exit $rc )
}

# Bug it catches (#1594): a card's Test step ran its files one at a time, though test slots were free, so its time grew
# with the number of files. Three files on a pool of three each wait for the other two: run side by side, each sees all
# three begun, and the output is each file's whole, in the list's order, with its end line, as a run one at a time
# prints it (testfails() reads a case under the file whose `== ` line is the last before it).
t_fileeachside() {
  local rc f
  sidewt 3; for f in a b c; do sidefile "$f.test.sh" 3; done
  siderun a.test.sh b.test.sh c.test.sh > "$T/$CASE/out" 2>&1; rc=$?
  [ "$rc" = 0 ] || fail "the run of three files that pass exited $rc: $(cat "$T/$CASE/out" "$T/$CASE/wt.test" 2>&1)"
  [ "$(grep -c '^saw 3$' "$T/$CASE/wt.test")" = 3 ] || fail "the three files of a pool of three did not run at the same time: $(cat "$T/$CASE/wt.test")"
  [ "$(tr '\n' '|' < "$T/$CASE/wt.test")" = "== a.test.sh|saw 3|ok one|-- ok a.test.sh|== b.test.sh|saw 3|ok one|-- ok b.test.sh|== c.test.sh|saw 3|ok one|-- ok c.test.sh|" ] \
    || fail "the output is not each file's whole, in the list's order: $(cat "$T/$CASE/wt.test")"
  [ "$(jq -c '[.of, .passed, .files]' "$T/$CASE/fails")" = '[3,["a.test.sh","b.test.sh","c.test.sh"],[]]' ] \
    || fail "the run's result is not three files that passed: $(cat "$T/$CASE/fails")"
}

# Bug it catches (#1594): with fewer free slots than files, the files ran past the slots, so eight cards testing at
# once overran the machine. A pool of three, slot 1 held by another run (as another card's test step holds one), and
# four files: each names the slot of the pool it holds (a descriptor of its own on that slot's file, whose lock is
# held), then counts the files running beside it (a mark in $T/$CASE/at, holding its slot, from once it has its slot
# until it ends) until it has seen two and for half a second more, and says when two marks there name one slot. Each
# holds slot 2 or 3, none ever sees more than two, no two at once hold one slot (#1594, E8: two files on slot 2 alone
# ran beside each other past the one slot they held), and two did run at the same time (else the cap would prove
# nothing). A run that took no slot, or took the held one, names none or slot 1.
t_fileeachcap() {
  local rc f p=$T/$CASE/slots hp w
  sidewt 3; mkdir -p "$p" && : >> "$p/1" || fail "the pool's slot 1"
  ( exec {h}>> "$p/1"; flock "$h"; exec sleep 300 ) & hp=$! # sleep: the other run, holding slot 1 until the case ends it
  wait_until "! flock -n '$p/1' true" || fail "the other run did not take slot 1"
  w="while [ \$i -lt $(loadlimit 200) ]; do c=\$(ls \"\$d\" | wc -l); [ \"\$c\" -le \$m ] || m=\$c; [ -z \"\$(cat \"\$d\"/* 2>/dev/null | sort | uniq -d)\" ] || : > \"$T/$CASE/same\"; [ \$m -ge 2 ] && [ \$i -ge 10 ] && break; i=\$((i + 1)); sleep 0.05; done" # sleep: each file counts the others beside it for its whole run, in its own shell (no wait_until there)
  for f in a b c d; do
    printf '%s\n' "d=$T/$CASE/at; mkdir -p \"\$d\"; m=0 i=0 s=none" \
      "for x in /dev/fd/*; do for k in 1 2 3; do [ \"\$x\" -ef \"$p/\$k\" ] && ! flock -n \"$p/\$k\" true && s=\$k; done; done" \
      "echo \"\$s\" > \"$T/$CASE/slot.\$CONVEYOR_TEST_N\"; echo \"\$s\" > \"\$d/\$CONVEYOR_TEST_N\"" "$w" \
      "echo \"\$m\" > \"$T/$CASE/max.\$CONVEYOR_TEST_N\"; rm -f \"\$d/\$CONVEYOR_TEST_N\"" > "$T/$CASE/wt/$f.test.sh"
  done
  siderun a.test.sh b.test.sh c.test.sh d.test.sh > "$T/$CASE/out" 2>&1; rc=$?
  kill "$hp" 2>/dev/null; wait "$hp" 2>/dev/null
  [ "$rc" = 0 ] || fail "the run of four files that pass exited $rc: $(cat "$T/$CASE/out" "$T/$CASE/wt.test" 2>&1)"
  f=$(cat "$T/$CASE"/slot.* 2>/dev/null | tr '\n' ' ')
  [[ $f =~ ^([23]\ ){4}$ ]] || fail "not each of the four files held slot 2 or 3 of the pool while slot 1 was another run's: $f"
  f=$(cat "$T/$CASE"/max.* 2>/dev/null | sort -n | tr '\n' ' ')
  [ "$(wc -w <<<"$f")" = 4 ] || fail "not each of the four files said how many ran beside it: $f"
  [ "$(awk '{ print $NF }' <<<"$f")" = 2 ] || fail "with two free slots of a pool of three, the most files that ran at once was not two: $f"
  [ ! -e "$T/$CASE/same" ] || fail "two files ran at the same time on one slot: $(cat "$T/$CASE"/slot.* | tr '\n' ' ')"
}

# Bug it catches (#1594): a file that failed among others running beside it was lost (its exit, or its case put under
# another file's `== ` line as the outputs mixed), so the step passed or named the wrong file. Three files side by side,
# the second failing its case `bad`: the run fails, and its failures name b.test.sh with that case, a and c passed.
t_fileeachfail() {
  local rc f
  sidewt 3; sidefile a.test.sh 3; sidefile b.test.sh 3 fail; sidefile c.test.sh 3
  siderun a.test.sh b.test.sh c.test.sh > "$T/$CASE/out" 2>&1; rc=$?
  [ "$rc" = 1 ] || fail "the run with a failing file exited $rc, not 1: $(cat "$T/$CASE/out" "$T/$CASE/wt.test" 2>&1)"
  [ "$(grep -c '^saw 3$' "$T/$CASE/wt.test")" = 3 ] || fail "the three files did not run at the same time: $(cat "$T/$CASE/wt.test")"
  f=$(jq -c '[(.files | map([.file, (.cases | map(.name))])), .passed]' "$T/$CASE/fails")
  [ "$f" = '[[["b.test.sh",["bad"]]],["a.test.sh","c.test.sh"]]' ] || fail "the failure does not name b.test.sh and its case alone: $f $(cat "$T/$CASE/wt.test")"
}

# Bug it catches (#1594, the scope check of #350 and R135): run side by side, a file whose run ran another file of the
# list was never stopped, as both had begun before it reported the other: two files begun, two files reported. Two
# files on a pool of two wait until both have begun; a.test.sh's run then reports both in a log of its own, as a
# runner that runs files it is not given does, and b.test.sh's reports b.test.sh in another log; then each runs on.
# Each log names b.test.sh once, so a check of each log alone passes it. The run is stopped well before their 30 s,
# and <worktree>.wide names b.test.sh, reported twice though begun once.
t_fileeachwide() {
  local rc f s=$SECONDS lim w
  sidewt 2
  w="while [ \"\$(ls \"\$d\" | wc -l)\" -lt 2 ] && [ \$i -lt $(loadlimit 200) ]; do i=\$((i + 1)); sleep 0.05; done" # sleep: each file waits for the other to begin, in its own shell (no wait_until there)
  for f in a b; do
    printf '%s\n' "d=$T/$CASE/at; mkdir -p \"\$d\"; : > \"\$d/\$CONVEYOR_TEST_N\"; i=0" "$w" \
      "for g in $([ $f = a ] && echo 'a b' || echo b); do echo \"-- ok \$g.test.sh\" >> \"\$CONVEYOR_TEST_LOG/inner.$f\"; done" \
      'exec sleep 30' > "$T/$CASE/wt/$f.test.sh" # sleep: a long run, which the stop cuts
  done
  siderun a.test.sh b.test.sh > "$T/$CASE/out" 2>&1; rc=$?
  lim=$(loadlimit 20 30) # under the files' 30 s
  [ "$rc" != 0 ] && [ $((SECONDS - s)) -lt "$lim" ] || fail "the run whose a.test.sh reported b.test.sh too was not stopped (exit $rc, $((SECONDS - s))s; limit $lim s): $(cat "$T/$CASE/wt.testlog"/inner.* 2>&1)"
  [ "$(cat "$T/$CASE/wt.wide" 2>&1)" = $'2\nb.test.sh\nbegun 1' ] || fail "the stop does not name b.test.sh, reported twice and begun once: $(cat "$T/$CASE/wt.wide" 2>&1)"
}

# Bug it catches (#1594): a file's end line was logged by the run only once it was free to read the file's exit, as
# when it waited for a slot for the next file, so a machine that stopped then lost the file's pass, and the card ran it
# again. A pool of two and three files: a.test.sh passes and leaves a process that holds its slot until $T/$CASE/go,
# and b.test.sh waits for go, so the run waits for a slot for c.test.sh. Once a.test.sh's command has ended, its pass
# is in the log, and the log as a stopped machine leaves it then (copied) reads a.test.sh passed (testfails()). Then
# go: the run ends with all three passed.
t_fileeachkeep() {
  local rc sp
  sidewt 2; sidefile c.test.sh 1
  printf '%s\n' "( until [ -e $T/$CASE/go ]; do sleep 0.1; done ) < /dev/null > /dev/null 2>&1 &" "echo ok > $T/$CASE/a.done" > "$T/$CASE/wt/a.test.sh" # sleep: a process a.test.sh leaves, in its own shell (no wait_until there)
  printf '%s\n' "until [ -e $T/$CASE/go ]; do sleep 0.1; done" > "$T/$CASE/wt/b.test.sh" # sleep: b.test.sh holds its slot until go, in its own shell (no wait_until there)
  siderun a.test.sh b.test.sh c.test.sh > "$T/$CASE/out" 2>&1 & sp=$!
  wait_until "[ -s '$T/$CASE/a.done' ]" || { touch "$T/$CASE/go"; wait "$sp"; fail "a.test.sh did not run: $(cat "$T/$CASE/out" "$T/$CASE/wt.test" 2>&1)"; }
  WAIT_CEILING=$(loadlimit 10) wait_until "grep -qxF -- '-- ok a.test.sh' '$T/$CASE/wt.testlog/files'" \
    || { touch "$T/$CASE/go"; wait "$sp"; fail "a.test.sh's pass was not logged while the run waited for a slot: $(cat "$T/$CASE/wt.testlog/files")"; }
  cp -R "$T/$CASE/wt.testlog" "$T/$CASE/cut.testlog" && : > "$T/$CASE/cut.test" || fail "the copy of the log"
  rc=$( (cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && testfails "$T/$CASE/cut.test" 137 | jq -c .passed) 2>&1)
  touch "$T/$CASE/go"; wait "$sp"; [ $? = 0 ] || fail "the run of three files that pass failed: $(cat "$T/$CASE/out" "$T/$CASE/wt.test" 2>&1)"
  [ "$rc" = '["a.test.sh"]' ] || fail "the log of the run stopped after a.test.sh passed does not read a.test.sh passed: $rc $(cat "$T/$CASE/cut.testlog/files")"
  [ "$(jq -c .passed "$T/$CASE/fails")" = '["a.test.sh","b.test.sh","c.test.sh"]' ] || fail "the run's result is not three files that passed: $(cat "$T/$CASE/fails")"
}

# Bug it catches: a file's runner that logged its pass (`-- ok <file>` in a log of its own, as .conveyor/test-changed.sh
# does) and then cleaned up had no end line in the run's log `files` yet, so a machine that stopped in that cleanup
# left the file open there, testfails() dropped its pass, and recovery ran it again. a.test.sh logs its pass in a log
# of its own, then waits for $T/$CASE/go; the log as a stopped machine leaves it then (copied) reads a.test.sh passed.
t_fileeachrunnerok() {
  local rc sp l=$T/$CASE/wt.testlog/a
  sidewt 1
  printf '%s\n' "printf '== a.test.sh\nok one\n-- ok a.test.sh\n' > $l" "until [ -e $T/$CASE/go ]; do sleep 0.1; done" > "$T/$CASE/wt/a.test.sh" # sleep: the runner's cleanup, in its own shell (no wait_until there)
  siderun a.test.sh > "$T/$CASE/out" 2>&1 & sp=$!
  wait_until "grep -qxF -- '-- ok a.test.sh' '$l'" || { touch "$T/$CASE/go"; wait "$sp"; fail "a.test.sh did not log its pass: $(cat "$T/$CASE/out" "$T/$CASE/wt.test" 2>&1)"; }
  cp -R "$T/$CASE/wt.testlog" "$T/$CASE/cut.testlog" && : > "$T/$CASE/cut.test" || fail "the copy of the log"
  rc=$( (cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && testfails "$T/$CASE/cut.test" 137 | jq -c .passed) 2>&1)
  touch "$T/$CASE/go"; wait "$sp"; [ $? = 0 ] || fail "the run of a file that passes failed: $(cat "$T/$CASE/out" "$T/$CASE/wt.test" 2>&1)"
  grep -qxF '== a.test.sh' "$T/$CASE/cut.testlog/files" && ! grep -qF -- '-- ok' "$T/$CASE/cut.testlog/files" || fail "the copy is not of a.test.sh begun and not ended in files: $(cat "$T/$CASE/cut.testlog/files")"
  [ "$rc" = '["a.test.sh"]' ] || fail "the log of a run stopped as a.test.sh's runner cleaned up after its pass does not read a.test.sh passed: $rc $(cat "$T/$CASE/cut.testlog"/*)"
}

# Bug it catches (#1594): the run's limit stopped the runner but not the files beside the one it waited for, which ran
# on, holding their slots. Three files that never end, side by side, and the run's limit (testTimeout 2): the run times
# out, each file is printed begun with no end line, and none of their processes is left.
t_fileeachstop() {
  local rc f pids=()
  sidewt 3
  for f in a b c; do
    printf '%s\n' "d=$T/$CASE/at; mkdir -p \"\$d\"; echo \$\$ > \"\$d/\$CONVEYOR_TEST_N\"; echo begun; exec sleep 300" > "$T/$CASE/wt/$f.test.sh" # sleep: a file that runs until the run's limit stops it
  done
  SIDELIMIT=2 siderun a.test.sh b.test.sh c.test.sh > "$T/$CASE/out" 2>&1; rc=$?
  [ "$rc" = 124 ] || fail "the run of files that never end did not time out (exit $rc): $(cat "$T/$CASE/out" "$T/$CASE/wt.test" 2>&1)"
  mapfile -t pids < <(cat "$T/$CASE/at"/* 2>/dev/null)
  [ ${#pids[@]} = 3 ] || fail "not each of the three files began before the run's limit: ${pids[*]} $(cat "$T/$CASE/wt.test")"
  for f in "${pids[@]}"; do wait_until "! kill -0 $f 2>/dev/null" || fail "a file's process ran on after the run's limit stopped the run: $f"; done
  [ "$(grep -v '^conveyor: ' "$T/$CASE/wt.test" | tr '\n' '|')" = "== a.test.sh|begun|== b.test.sh|begun|== c.test.sh|begun|" ] \
    || fail "the stopped files are not each printed begun with no end line: $(cat "$T/$CASE/wt.test")"
}
