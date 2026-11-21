#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (the pack's test.full, .conveyor/project.json): every test file git lists but the
# engine's runner (below), each run whole, in the checkout it is started in. release-prep, release and
# the Board's full test suite run it. Exit 1 if any file fails; each file's output begins with a line `== <file>`, and
# its result is a line `-- ok <file>` or `-- FAIL <file>`.
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
# CONVEYOR_SUITE_AT_ONCE (release-prep's: the control record's suiteAtOnce) is the most files parallel mode runs at
# once, 2 when unset, and at most the pool's slots. Serial mode runs one at a time whatever it is.
# In parallel mode it starts its files longest first, by CONVEYOR_SUITE_RECORD (release-prep's suite record,
# suiteruns.jsonl: suiterec() of conveyor/lib/testrun.sh): each file's `sec` in the newest run of the record (its
# last line that is a run), not in older runs. Files that run did not time start before every timed file, as their time is not known;
# ties keep the suite's order, and so does every file when the record cannot be read. Serial mode keeps the suite's order.
MODE=${CONVEYOR_SUITE_MODE:-serial}; unset CONVEYOR_SUITE_MODE
RECORD=${CONVEYOR_SUITE_RECORD:-}; unset CONVEYOR_SUITE_RECORD
case $MODE in serial | parallel) ;; *) echo "test-full: CONVEYOR_SUITE_MODE is '$MODE', not serial or parallel; nothing run" >&2; exit 2 ;; esac
AT=${CONVEYOR_SUITE_AT_ONCE:-2}; unset CONVEYOR_SUITE_AT_ONCE
[[ $AT =~ ^[1-9][0-9]{0,5}$ ]] || { echo "test-full: CONVEYOR_SUITE_AT_ONCE is '$AT', not a whole number from 1; nothing run" >&2; exit 2; }
# The host file's testTmpMB (docs/setup.md) is each test file's share, in MB, of the space its temp files go in (the
# file system of TMPDIR, else /tmp), 2048 when unset: a file that writes past it fails alone, and the others and the
# belt keep their space (runone; .conveyor/test-share.sh, which the card's test step uses too).
# shellcheck source=.conveyor/test-share.sh
. "${BASH_SOURCE[0]%/*}/test-share.sh" || { echo "test-full: ${BASH_SOURCE[0]%/*}/test-share.sh could not be read; nothing run" >&2; exit 2; }
rc=0
tmp=$(mktemp -d) || exit 1
share_init "$tmp" > "$tmp/share.why" || { echo "test-full: $(cat "$tmp/share.why"); nothing run" >&2; rm -rf "$tmp"; exit 2; }
# A run stopped before its files end (the test step's timeout, testTimeout: testrun.sh testclock(), stops the whole
# process group) still names in the run's log the cases that ended in each file run in parallel that is still running
# (casecopy, below): its own log folder is gone with $tmp. timeout sends its TERM twice (to the suite, then to its
# process group): the first is caught and the next ignored, so a second one does not stop the copy, nor the copy's own
# commands.
trap 'trap "" TERM; exit 143' TERM
# u+w: a file's temp folder may hold read-only folders (an install), which rm cannot empty.
trap 'for p in "${!job[@]}"; do [ ! -d "$LOG" ] || casecopy "$tmp/${job[$p]}.log" "$LOG"; done; chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
LOG=${CONVEYOR_TEST_LOG:-} # the run's test log folder; a file run in parallel names its cases in a folder of its own first (runone)
# The run's own log in that folder, test-full.log: its `TESTRUN cases=|files=` lines and each file's `== <file>` and
# `-- ok|FAIL <file>` lines, in the order the output prints the files (each file's output begins with its `== <file>`
# line). The engine reads which file each failed case is of from it (testrun.sh testfails()), so a run of the failed
# cases alone (fullalone()) names each under its own file: with no such log, every case is under the suite's command,
# and its run alone runs the suite whole (below). No test's own output can pass for these lines. It is written in $tmp
# and put in that folder only when every file has ended (ended): a run stopped before then (a timeout) has none, so
# its failure is the suite's, and its run alone runs the suite whole, never only the file it was in.
RUNLOG=$tmp/test-full.log
runlog() { printf '%s\n' "$@" >> "$RUNLOG"; }
ended() { [ ! -d "$LOG" ] || cp "$RUNLOG" "$LOG/test-full.log" || rc=1; exit $rc; }
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
runlog "TESTRUN cases=$((engine + other))" "TESTRUN files=${#files[@]}"
# One test file run: its output, then its `TESTRUN sec` and `-- ok|FAIL` lines; exit 1 when it failed. <n> names its
# scratch files in $tmp. Its TMPDIR is a folder of its own there, removed when it ends (share_run); a run stopped first
# (its timeout) removes it with $tmp. It does not start while share_noroom says why (the reason is its output), and a
# file whose temp folder reaches its share fails with the reason.
runone() { # <test file> <n>
  local t=$1 stamp=$tmp/$2.stamp tt=$tmp/$2.times c n st s e r why
  case $t in
    *.mjs) mapfile -t c < <(nodecases "$t"); c=(node --max-old-space-size=4096 --test "${c[@]}" "$t") ;;
    *.py) c=(python3 "$t") ;;
    conveyor/conveyor.test.sh) c=(bash "$t"); [ ${#again[@]} = 0 ] || c=(env "CONVEYOR_SHELL_TEST_CASE=$(IFS=,; echo "${again[*]}")" bash "$t") ;;
    *) c=(bash "$t") ;;
  esac
  n=$(marks); touch "$stamp"; echo "== $t"
  if why=$(share_noroom "$tmp" 0); then
    echo "test-full: $t did not start: $why"; st=1
  else
    times > "$tt"; s=${EPOCHREALTIME/,/.}
    share_run "test-full: $t" "$tmp/$2.tmp" "${c[@]}" < /dev/null \
      | awk '!/^(TESTRUN (cases|files)=|TESTRUN sec\t|-- (ok|FAIL) )/ { print; fflush() }'
    st=${PIPESTATUS[0]}; e=${EPOCHREALTIME/,/.}; times >> "$tt"
    awk -v f="$t" -v a="$s" -v b="$e" 'function c(x, a) { sub(/s$/, "", x); split(x, a, "m"); return a[1] * 60 + a[2] } { gsub(/,/, ".") }
      NR == 2 || NR == 4 { n[NR] = c($1) + c($2) } END { printf "TESTRUN sec\t%s\t%.1f\t%.1f\n", f, b - a, n[4] - n[2] }' "$tt"
  fi
  if [ "$st" = 0 ]; then echo "-- ok $t"; r=ok; else echo "-- FAIL $t"; r=failed; fi
  [ ! -d "$LOG" ] || [ "$(marks)" != "$n" ] || [ "$(marks -newer "$stamp")" != 0 ] || { mkdir -p "$LOG/cases/$r" && : > "$LOG/cases/$r/${t//\//:}"; }
  [ "$st" = 0 ]
}
if [ "$MODE" = serial ]; then
  i=0; for t in "${files[@]}"; do i=$((i + 1)); runlog "== $t"; if runone "$t" "$i"; then runlog "-- ok $t"; else rc=1; runlog "-- FAIL $t"; fi; done
  ended
fi
# Parallel: at most AT files at once, and never more than the pool has slots. A file that is no engine runner holds a slot while it
# runs (the run's home slot or one of the pool, slot_take) and is pinned to its core (slot_mine); the engine's runner,
# its case files and any other bash file that reads the pool itself (a line of its own that sources the slots and calls
# slot_pool, as conveyor/tools/closure.test.sh does) hold none, as each of their cases takes a slot of its own: a file
# holding one would keep it from its own cases. Each file's output goes to a file of its own, printed whole once the file has ended, so no two files'
# lines are mixed. Its case names go to a log folder of its own, copied into the run's once it has ended: a case
# another file names meanwhile is then never taken for one of this file's (runone's marks check).
SLOTS=${CONVEYOR_TEST_SLOTS:-conveyor/lib/slots.sh}
# shellcheck source=/dev/null
. "$SLOTS" && slot_pool || { echo "test-full: the test slots ($SLOTS) could not be read; nothing run" >&2; exit 1; }
[ "$AT" -le "$SLOT_N" ] || AT=$SLOT_N
declare -A job=()
# Longest first (above): an order the record cannot give (no jq, or a count that is not the files') keeps the suite's.
# jq's sort is stable, so ties keep the suite's order.
if [ ${#files[@]} -gt 0 ] && o=$(printf '%s\n' "${files[@]}" | jq -rRn --slurpfile r <(jq -cR 'fromjson? | objects | .files | objects' "$RECORD" 2>/dev/null) '
    ($r[-1] // {} | with_entries(select(.value | objects | .sec | numbers) | .value |= .sec)) as $t
    | [inputs] | sort_by(if $t[.] == null then [0, 0] else [1, -$t[.]] end) | .[]') \
  && [ "$(grep -c '' <<<"$o")" = ${#files[@]} ]; then
  mapfile -t files <<<"$o"
fi
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
  # Its lines in the run's log once it ended, as its output is printed only then.
  if [ "$st" = 0 ]; then runlog "== $t" "-- ok $t"; else runlog "== $t" "-- FAIL $t"; fi
  unset "job[$p]"
}
i=0
for t in "${files[@]}"; do
  # A file waits for one that runs to end while the space cannot hold its share (share_noroom); with none running, it
  # starts, and runone fails it with the reason when there is still no room.
  while [ ${#job[@]} -ge "$AT" ] || { [ ${#job[@]} -gt 0 ] && share_noroom "$tmp" ${#job[@]} > /dev/null; }; do reap; done
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
ended
