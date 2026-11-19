#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (the pack's test.full, .conveyor/project.json): every test file git lists but the
# engine's runner (below), each run whole, in the checkout it is started in. release-prep, release and
# the Board's full test suite run it. Exit 1 if any file fails; each file's result is a line `-- ok <file>` or `-- FAIL <file>`.
# With the engine's test log folder (CONVEYOR_TEST_LOG), a file whose runner named none of its cases as ended there
# (cases/ok, cases/failed) is named there itself, its path's slashes as colons, so a whole-suite run's progress (on the
# Board and in /units) counts it and its failure.
# Its first line, `TESTRUN cases=<n>`, is the whole run's total of those names, for that progress's total (fulltest.sh
# suiteprog()): the engine's cases of the case files it runs and one for every other file. It does not run the engine's
# runner, conveyor/conveyor.test.sh, which runs every case of the case files under conveyor/tests/ again: each engine
# case runs once, in its case file (a run of failed cases alone, below, still runs the runner on those cases). Its
# files' own `TESTRUN cases=` lines are left out of its output, as the total names them already.
# Its second line, `TESTRUN files=<n>`, is the number of files it runs, the total of the progress's files (suiteprog()
# reads that line and the `-- ok|FAIL <file>` lines). Its files' own lines of these forms are left out of its output.
# Before each file's `-- ok|FAIL` line it prints the file's `TESTRUN sec<TAB><file><TAB><clock s><TAB><CPU s>` (as
# conveyor/tools/testtime.sh does), which the engine keeps for the Board's Tests page (testrun.sh suiterec()); a file's
# own `TESTRUN sec` lines, of the files it starts, are left out, so each line is of a file this suite ran.
# A file named a case when a name was added, or written again (a case file runs cases the runner named already).
# With CONVEYOR_SUITE_FILES, a file of paths one a line (release-prep's run that reuses the passes of an earlier run,
# conveyor/commands/release-prep.sh), it runs only the test files of its list that git lists: a path in it that is no
# test file of the checkout is left out, and so is conveyor/conveyor.test.sh. Its case total then counts the engine's
# cases of the case files it runs.
# CONVEYOR_SUITE_MODE (release-prep's --serial or --parallel, conveyor/commands/release-prep.sh) is serial, one file
# at a time, when unset; parallel runs several at once through the machine's test slots (conveyor/lib/slots.sh, the
# library CONVEYOR_TEST_SLOTS names, else the checkout's), below. It is this run's: a test file that runs a suite of
# its own runs it in its default mode.
MODE=${CONVEYOR_SUITE_MODE:-serial}; unset CONVEYOR_SUITE_MODE
case $MODE in serial | parallel) ;; *) echo "test-full: CONVEYOR_SUITE_MODE is '$MODE', not serial or parallel; nothing run" >&2; exit 2 ;; esac
rc=0
tmp=$(mktemp -d) || exit 1
# A run stopped before its files end (the test step's timeout, testTimeout: testrun.sh testclock(), stops the whole
# process group) still names in the run's log the cases that ended in each file run in parallel that is still running
# (casecopy, below): its own log folder is gone with $tmp. timeout sends its TERM twice (to the suite, then to its
# process group): the first is caught and the next ignored, so a second one does not stop the copy, nor the copy's own
# commands.
trap 'trap "" TERM; exit 143' TERM
trap 'for p in "${!job[@]}"; do [ ! -d "$LOG" ] || casecopy "$tmp/${job[$p]}.log" "$LOG"; done; rm -rf "$tmp"' EXIT
LOG=${CONVEYOR_TEST_LOG:-} # the run's test log folder; a file run in parallel names its cases in a folder of its own first (runone)
marks() { find "$LOG/cases/ok" "$LOG/cases/failed" -maxdepth 1 -type f "$@" 2>/dev/null | wc -l; }
mapfile -t files < <(git ls-files '*.test.sh' '*.test.mjs' '*.test.py')
if [ -n "${CONVEYOR_SUITE_FILES:-}" ]; then
  mapfile -t files < <(printf '%s\n' "${files[@]}" | grep -xFf <(grep . "$CONVEYOR_SUITE_FILES" 2>/dev/null || echo /))
fi
unset CONVEYOR_SUITE_FILES # the list is this run's: a test file that runs a suite of its own runs it whole
# The engine's run of one failed case alone (conveyor/lib/fulltest.sh fullalone()) names it in the CONVEYOR_TEST_RERUN
# list as `fail<TAB><file>[<TAB><case>]`: it runs only the files of its `fail` lines, so a run alone is not the whole
# suite again. Of the engine's runner (a case of it or of an engine case file, which the runner runs) only those cases,
# and of a node test file those cases alone; a Python or other shell test file has no case filter and runs whole. A
# list with no `fail` line (files kept off as passed before) is not read: the suite runs whole. Nor is a list with a
# `fail` line that names no test file of the run (a run with no per-file logs names its failure by the command, as
# testrun.sh testfails() does): selecting by it would run nothing and pass, so the suite runs whole.
RERUN=${CONVEYOR_TEST_RERUN:-}; unset CONVEYOR_TEST_RERUN
again=()
if [ -s "$RERUN" ] && grep -q $'^fail\t' "$RERUN" \
  && ! awk -F'\t' '$1 == "fail" { print $2 }' "$RERUN" | grep -vxFf <(printf '%s\n' "${files[@]}") | grep -q .; then
  mapfile -t again < <(awk -F'\t' '$1 == "fail" && $3 != "" && ($2 == "conveyor/conveyor.test.sh" || $2 ~ /^conveyor\/tests\/[^\/]+[.]test[.]sh$/) { print $3 }' "$RERUN" | sort -u)
  # A `fail` line naming the runner with no case runs it whole.
  ! grep -qxF $'fail\tconveyor/conveyor.test.sh' "$RERUN" || again=()
  mapfile -t files < <(printf '%s\n' "${files[@]}" | grep -xFf <({ awk -F'\t' '$1 == "fail" && !($3 != "" && $2 ~ /^conveyor\/tests\//) { print $2 }' "$RERUN"
    [ ${#again[@]} = 0 ] || echo conveyor/conveyor.test.sh; } | grep .))
else
  mapfile -t files < <(printf '%s\n' "${files[@]}" | grep -vxF -e conveyor/conveyor.test.sh -e '') # '': no file
fi
engine=0 other=0 cf=()
for t in "${files[@]}"; do case $t in conveyor/conveyor.test.sh) engine=1 ;; conveyor/tests/*.test.sh) cf+=("$t") ;; *) other=$((other + 1)) ;; esac; done
[ $engine = 0 ] || cf=(conveyor/tests/*.test.sh)
engine=0; [ ${#cf[@]} = 0 ] || engine=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "${cf[@]}" | sort -u | wc -l)
[ ${#again[@]} = 0 ] || engine=${#again[@]}
# The cases of a node test file's `fail` lines, each matched whole by name (as the test step's runner does).
nodecases() { # <node test file>
  local k f c
  [ -s "$RERUN" ] || return 0
  while IFS=$'\t' read -r k f c; do
    [ "$k" = fail ] && [ "$f" = "$1" ] && [ -n "$c" ] || continue
    echo "--test-name-pattern=^$(sed 's/[][\\.*+?^${}()|/]/\\&/g' <<<"$c")\$"
  done < "$RERUN"
}
echo "TESTRUN cases=$((engine + other))"
echo "TESTRUN files=${#files[@]}"
# One test file run: its output, then its `TESTRUN sec` and `-- ok|FAIL` lines; exit 1 when it failed. <n> names its
# scratch files in $tmp.
runone() { # <test file> <n>
  local t=$1 stamp=$tmp/$2.stamp tt=$tmp/$2.times c n st s e r
  case $t in
    *.mjs) mapfile -t c < <(nodecases "$t"); c=(node --max-old-space-size=4096 --test "${c[@]}" "$t") ;;
    *.py) c=(python3 "$t") ;;
    conveyor/conveyor.test.sh) c=(bash "$t"); [ ${#again[@]} = 0 ] || c=(env "CONVEYOR_SHELL_TEST_CASE=$(IFS=,; echo "${again[*]}")" bash "$t") ;;
    *) c=(bash "$t") ;;
  esac
  n=$(marks); touch "$stamp"
  times > "$tt"; s=${EPOCHREALTIME/,/.}
  "${c[@]}" < /dev/null | awk '!/^(TESTRUN (cases|files)=|TESTRUN sec\t|-- (ok|FAIL) )/ { print; fflush() }'
  st=${PIPESTATUS[0]}; e=${EPOCHREALTIME/,/.}; times >> "$tt"
  awk -v f="$t" -v a="$s" -v b="$e" 'function c(x, a) { sub(/s$/, "", x); split(x, a, "m"); return a[1] * 60 + a[2] } { gsub(/,/, ".") }
    NR == 2 || NR == 4 { n[NR] = c($1) + c($2) } END { printf "TESTRUN sec\t%s\t%.1f\t%.1f\n", f, b - a, n[4] - n[2] }' "$tt"
  if [ "$st" = 0 ]; then echo "-- ok $t"; r=ok; else echo "-- FAIL $t"; r=failed; fi
  [ ! -d "$LOG" ] || [ "$(marks)" != "$n" ] || [ "$(marks -newer "$stamp")" != 0 ] || { mkdir -p "$LOG/cases/$r" && : > "$LOG/cases/$r/${t//\//:}"; }
  [ "$st" = 0 ]
}
if [ "$MODE" = serial ]; then
  i=0; for t in "${files[@]}"; do i=$((i + 1)); runone "$t" "$i" || rc=1; done
  exit $rc
fi
# Parallel: at most as many files at once as the pool has slots. A file that is no engine runner holds a slot while it
# runs (the run's home slot or one of the pool, slot_take) and is pinned to its core (slot_mine); the engine's runner,
# its case files and any other bash file that reads the pool itself (a line of its own that sources the slots and calls
# slot_pool, as conveyor/tools/closure.test.sh does) hold none, as each of their cases takes a slot of its own: a file
# holding one would keep it from its own cases. Each file's output goes to a file of its own, printed whole once the file has ended, so no two files'
# lines are mixed. Its case names go to a log folder of its own, copied into the run's once it has ended: a case
# another file names meanwhile is then never taken for one of this file's (runone's marks check).
SLOTS=${CONVEYOR_TEST_SLOTS:-conveyor/lib/slots.sh}
# shellcheck source=/dev/null
. "$SLOTS" && slot_pool || { echo "test-full: the test slots ($SLOTS) could not be read; nothing run" >&2; exit 1; }
declare -A job=()
# The case names <file log> (a file's own log folder) holds, copied into <run log>: each name alone, as another file's
# copy may make the same folder of the run's log at the same time. Fails when one could not be copied.
casecopy() { # <file log> <run log>
  local f d st=0
  for f in "$1"/cases/*/*; do
    [ -f "$f" ] || continue; d=${f%/*}; d=$2/cases/${d##*/}
    mkdir -p "$d" && cp "$f" "$d/" || { echo "test-full: $f could not be copied into the run's test log" >&2; st=1; }
  done
  return $st
}
reap() { # one file that ended: its output printed, its result counted
  local p='' q st t
  # A worker that ended before this wait began (while slot_take waited for a slot) is not among the jobs a bash before
  # 5.3 waits for with `wait -n`: its exit is asked for by itself, as lib/session.sh watch() does, before and after.
  for q in "${!job[@]}"; do kill -0 "$q" 2>/dev/null || { p=$q; break; }; done
  if [ -n "$p" ]; then wait "$p"; st=$?; else wait -n -p p "${!job[@]}"; st=$?; fi
  if [ -z "$p" ]; then
    for q in "${!job[@]}"; do kill -0 "$q" 2>/dev/null || { p=$q; break; }; done
    [ -n "$p" ] || { echo "test-full: no file it started could be waited for (exit $st); the run ends failed" >&2; exit 1; }
    wait "$p"; st=$?
  fi
  t=${files[${job[$p]} - 1]}
  cat "$tmp/${job[$p]}.out"; [ "$st" = 0 ] || rc=1
  # A worker that ended before its file ran (no core to pin it to: slot_mine) printed no result line of it.
  [ "$st" = 0 ] || grep -qxF -e "-- FAIL $t" -e "-- ok $t" "$tmp/${job[$p]}.out" || echo "-- FAIL $t"
  unset "job[$p]"
}
i=0
for t in "${files[@]}"; do
  while [ ${#job[@]} -ge "$SLOT_N" ]; do reap; done
  i=$((i + 1)); own=''
  case $t in conveyor/conveyor.test.sh | conveyor/tests/*.test.sh) own=1 ;; *.sh) ! grep -q '^\. .*slot_pool' "$t" || own=1 ;; esac
  [ -n "$own" ] || slot_take
  ( [ -n "$own" ] || slot_mine
    all=$LOG; LOG=''
    [ ! -d "$all" ] || { LOG=$tmp/$i.log; mkdir "$LOG" && export CONVEYOR_TEST_LOG=$LOG; } || exit 1
    runone "$t" "$i"; st=$?
    [ -z "$LOG" ] || casecopy "$LOG" "$all" || st=1
    exit $st )> "$tmp/$i.out" 2>&1 < /dev/null &
  job[$!]=$i
  [ -n "$own" ] || slot_free
done
while [ ${#job[@]} -gt 0 ]; do reap; done
exit $rc
