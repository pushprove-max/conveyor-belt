#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (the pack's test.full, .conveyor/project.json): every test file git lists, each run
# whole, in the checkout it is started in. release-prep, release and
# the Board's full test suite run it. Exit 1 if any file fails; each file's result is a line `-- ok <file>` or `-- FAIL <file>`.
# With the engine's test log folder (CONVEYOR_TEST_LOG), a file whose runner named none of its cases as ended there
# (cases/ok, cases/failed) is named there itself, its path's slashes as colons, so a whole-suite run's progress (on the
# Board and in /units) counts it and its failure.
# Its first line, `TESTRUN cases=<n>`, is the whole run's total of those names, for that progress's total (fulltest.sh
# suiteprog()): the engine's cases (conveyor.test.sh runs them, and each case file again under the same names, so each
# counts once) and one for every other file. Its files' own `TESTRUN cases=` lines are left out of its output, as the
# total names them already.
# Its second line, `TESTRUN files=<n>`, is the number of files it runs, the total of the progress's files (suiteprog()
# reads that line and the `-- ok|FAIL <file>` lines). Its files' own lines of these forms are left out of its output.
# Before each file's `-- ok|FAIL` line it prints the file's `TESTRUN sec<TAB><file><TAB><clock s><TAB><CPU s>` (as
# conveyor/tools/testtime.sh does), which the engine keeps for the Board's Tests page (testrun.sh suiterec()); a file's
# own `TESTRUN sec` lines, of the files it starts, are left out, so each line is of a file this suite ran.
# A file named a case when a name was added, or written again (a case file runs cases the runner named already).
# With CONVEYOR_SUITE_FILES, a file of paths one a line (release-prep's run that reuses the passes of an earlier run,
# conveyor/commands/release-prep.sh), it runs only the test files of its list that git lists: a path in it that is no
# test file of the checkout is left out. Its case total then counts the engine's cases of the case files it runs (all of
# them when it runs conveyor/conveyor.test.sh).
rc=0
stamp=$(mktemp); tt=$(mktemp); trap 'rm -f "$stamp" "$tt"' EXIT
marks() { find "$CONVEYOR_TEST_LOG/cases/ok" "$CONVEYOR_TEST_LOG/cases/failed" -maxdepth 1 -type f "$@" 2>/dev/null | wc -l; }
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
for t in "${files[@]}"; do
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
  if [ "$st" = 0 ]; then echo "-- ok $t"; r=ok; else echo "-- FAIL $t"; rc=1; r=failed; fi
  [ ! -d "${CONVEYOR_TEST_LOG:-}" ] || [ "$(marks)" != "$n" ] || [ "$(marks -newer "$stamp")" != 0 ] || { mkdir -p "$CONVEYOR_TEST_LOG/cases/$r" && : > "$CONVEYOR_TEST_LOG/cases/$r/${t//\//:}"; }
done
exit $rc
