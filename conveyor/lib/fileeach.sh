#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The run of test files, each alone, through the pack's test.fileCommand (filecmd(), lib/testrun.sh): side by side
# on test slots for a card's list, else one at a time. Sourced, never
# run: filecmd() puts this function's text in the command it makes, so the command needs no file of the engine's where
# it runs.

# fileeach <side|one> <test.fileCommand> <FILELIMIT> <LOADSCALE> <log> [file...]: runs each file alone with the
# command, the file's path added as its last argument and in CONVEYOR_TEST_FILE, its place in the run (1, 2 and so on)
# in CONVEYOR_TEST_N. It logs each to <log> (the run's log `files`) as a runner does: `TESTRUN files=<n>` before the
# first begins (#433: a file's own run prints its own count), `== <file>` as it begins, `-- ok <file>` or
# `-- FAIL <file>` as it ends; and before each file after the first begins, a `=@ <bytes> <log>` line for each other
# log in its folder then: watch() (wideeach(), lib/testlist.sh) reads what the files begun before it reported from
# those, and k - 1 files begun can report no more than k - 1 files, side by side or not; side by side, a file the
# other logs together name more times than its `== <file>` lines was run by another file's run too (wideeach() reads
# that as well). A file's end line is logged by the file's own process as its command ends, as a run one at a time
# logs it, never later by the run (which can be waiting for a slot then): a run stopped after a file passed keeps that
# pass in the log. Exits 1 when a file failed.
# side (a card's list, filecmd() files): the files run side by side, each in its own process on a test slot of its own
# (lib/slots.sh, the library CONVEYOR_TEST_SLOTS names): the run's home slot when no other file of the run is on it
# (slot_take), else a slot of the pool, waited for, so a card never runs more files at once than it holds slots and
# never waits on the pool for its first. Each file is pinned to its slot's core (slot_mine), and a file that cannot be
# pinned fails. Each file's output goes to a file of its own (<log>.out/<n>), printed whole, `== <file>` first and its
# end line last, once it and every file before it have ended: the output has the files in the list's order, as a run
# one at a time has it, so a case's line is read under its own file (testfails()). Its end line goes to <log> as it
# ends. one (a run of a list's `fail` lines), or a run that cannot read the slots (no CONVEYOR_TEST_SLOTS, or
# slot_pool fails): each file runs once the one before it has ended, its output straight to the run's.
# Each file runs in a process group of its own (timeout's), with the file's own time limit, its `# timeout: <seconds>`
# line (FILELIMIT), times the run's load factor (CONVEYOR_LOAD_FACTOR: loadfactor(), LOADSCALE, rounded up): past it,
# timeout ends the file and everything it started, and the output says it timed out, and with a factor over 1, the
# line's own seconds and the factor. Its log keeps it begun with no `-- ok|FAIL` line, and a `-- timeout <file>` line
# in the log alone (no reader of results reads it: testclock() does, so the run's limit is never said to have stopped
# it), and the run, once its other files ran, exits 124, as a run that ran out of time does: testfails() names it as
# the run's timeout, not as a failed file (which the check on main, mainred.sh verdicts(), would count as main's), and
# the mutation check and the Board's Run action read the exit as timed out. A file with no such line has the run's
# limit (testTimeout: testlist.sh testclock()). When the run itself is ended (TERM, as at that limit), each file still
# running is ended with it, its process group too, and every file begun is printed with no end line, then the run
# exits 143. A process a file's run leaves running, in that group, is out of the test command's group, which the
# runner watches to give the home slot back (slot_left(), lib/slots.sh): a process of the run's own, in the command's
# group, that holds no descriptor it inherited but the file's slot, stays while the file's group has one, so the
# file's slot, and the home slot, stay taken until it has ended.
fileeach() { # <side|one> <test.fileCommand> <FILELIMIT> <LOADSCALE> <log> [file...]
  local fc=$2 fl=$3 ls=$4 l=$5 o=$5.out f g n s i=0 nx=1 r=0 to='' sl=''
  local -A job=()
  local -a fs=("${@:6}") ex=() fn=() fsec=()
  echo "TESTRUN files=${#fs[@]}" >> "$l"
  # shellcheck source=/dev/null
  if [ "$1" = side ] && [ -n "${CONVEYOR_TEST_SLOTS:-}" ] && . "$CONVEYOR_TEST_SLOTS" && slot_pool; then sl=1; mkdir -p "$o" || exit 1; fi
  # The end of file <pid>'s run, its exit <x> (K: it was ended with the run), for fe_shown: its process logged it.
  fe_ended() { # <pid> <x>
    local k=${job[$1]}; ex[k]=$2; unset "job[$1]"
  }
  # Each file that ended and every file before it: printed, in order.
  fe_shown() {
    local f x w
    while [ -n "${ex[nx]+x}" ]; do
      f=${fs[nx - 1]}; x=${ex[nx]}
      [ -z "$sl" ] || { echo "== $f"; cat "$o/$nx" 2>/dev/null; rm -f "$o/$nx"; }
      if [ "$x" = K ]; then :; elif [ "$x" = 0 ]; then echo "-- ok $f"
      elif [ "$x" = 124 ] && [ "${fn[nx]}" != 0 ]; then w=; [ "${fsec[nx]}" = "${fn[nx]}" ] || w="; the limit is its # timeout: line's ${fn[nx]} s times the load factor $CONVEYOR_LOAD_FACTOR"
        echo "conveyor: $f timed out: it ran past its time limit, ${fsec[nx]} s, and it was stopped there$w"; to=124
      else echo "-- FAIL $f"; r=1; fi
      nx=$((nx + 1))
    done
  }
  # Each file that has ended, logged, then printed as fe_shown prints it.
  fe_reap() {
    local q
    for q in "${!job[@]}"; do kill -0 "$q" 2>/dev/null || { wait "$q"; fe_ended "$q" $?; }; done
    fe_shown
  }
  # The run is ended: each file still running is ended (its own trap ends its group), and every file begun is printed.
  fe_stop() {
    local q x
    for q in "${!job[@]}"; do kill -TERM "$q" 2>/dev/null; done
    for q in "${!job[@]}"; do wait "$q"; x=$?; [ "$x" != 143 ] || x=K; fe_ended "$q" "$x"; done
    fe_shown; rmdir "$o" 2>/dev/null; exit 143
  }
  trap fe_stop TERM INT
  for f in "${fs[@]}"; do
    i=$((i + 1))
    # The waits' own processes (slot_take's, the sleep below) are the run's: one the run's end kills is not reported
    # in its output (a "Terminated" line of bash's), so their errors go nowhere.
    if [ -n "$sl" ]; then { slot_take; } 2> /dev/null; else for g in "${!job[@]}"; do wait "$g"; fe_ended "$g" $?; done; fi
    fe_reap
    [ $i = 1 ] || for g in "${l%/*}"/*; do [ ! -f "$g" ] || [ "$g" = "$l" ] || echo "=@ $(($(wc -c < "$g"))) ${g##*/}"; done >> "$l"
    echo "== $f" >> "$l"; [ -n "$sl" ] || echo "== $f"
    n=$(awk "$fl" "$f" 2>/dev/null); [ "${n:-0}" -gt 0 ] 2>/dev/null || n=0
    s=$n; [ "$n" = 0 ] || s=$(awk -v n="$n" -v f="${CONVEYOR_LOAD_FACTOR:-1}" "$ls")
    fn[i]=$n; fsec[i]=$s
    # The file's own process: its trap ends the file's group when the run is ended, before the file's run has begun too.
    # shellcheck disable=SC2030,SC2031 # p is the subshell's own
    ( p=''; trap '[ -z "$p" ] || { kill -TERM "$p" 2>/dev/null; wait "$p" 2>/dev/null; }; exit 143' TERM
      [ -z "$sl" ] || { exec > "$o/$i" 2>&1; slot_mine; }
      CONVEYOR_TEST_FILE=$f CONVEYOR_TEST_N=$i timeout --kill-after=10 "$s" bash -c "$fc"' "$CONVEYOR_TEST_FILE"' < /dev/null & p=$!
      wait "$p"; x=$?
      if pgrep -g "$p" > /dev/null 2>&1; then
        ( for ((d = 3; d < 256; d++)); do [ "$d" = "${SLOT_FD:-}" ] || [ "$d" = "${SLOT_CAPFD:-}" ] || eval "exec $d>&-"; done
          while pgrep -g "$p" > /dev/null 2>&1; do sleep 0.5; done ) < /dev/null > /dev/null 2>&1 &
      fi
      # Its end line, logged here at once: the run reads its exit only once it is free (fe_reap). Ended with the run
      # from now on, it exits with its own exit, so the output and the log both have the end line.
      trap '' TERM
      if [ "$x" = 0 ]; then echo "-- ok $f"; elif [ "$x" = 124 ] && [ "$n" != 0 ]; then echo "-- timeout $f"; else echo "-- FAIL $f"; fi >> "$l"
      exit "$x" ) < /dev/null &
    job[$!]=$i
    [ -z "$sl" ] || slot_free
  done
  # sleep: a file that ended is asked for by itself (fe_reap), as `wait -n` before bash 5.3 misses one that ended first
  while [ ${#job[@]} -gt 0 ]; do fe_reap; [ ${#job[@]} = 0 ] || { sleep 0.2; } 2> /dev/null; done
  fe_shown; [ -z "$sl" ] || rmdir "$o" 2>/dev/null
  exit "${to:-$r}"
}
