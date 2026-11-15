#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (the pack's test.full, .conveyor/project.json): every test file git lists, each run
# whole, in the checkout it is started in. release-prep, release and
# the Board's full test suite run it. Exit 1 if any file fails; each file's result is a line `ok <file>` or `FAIL <file>`.
# With the engine's test log folder (CONVEYOR_TEST_LOG), a file whose runner named none of its cases as ended there
# (cases/ok, cases/failed) is named there itself, its path's slashes as colons, so a whole-suite run's progress (on the
# Board and in /units) counts it and its failure.
# Its first line, `TESTRUN cases=<n>`, is the whole run's total of those names, for that progress's total (fulltest.sh
# suiteprog()): the engine's cases (conveyor.test.sh runs them, and each case file again under the same names, so each
# counts once) and one for every other file. Its files' own `TESTRUN cases=` lines are left out of its output, as the
# total names them already.
# A file named a case when a name was added, or written again (a case file runs cases the runner named already).
rc=0
stamp=$(mktemp); trap 'rm -f "$stamp"' EXIT
marks() { find "$CONVEYOR_TEST_LOG/cases/ok" "$CONVEYOR_TEST_LOG/cases/failed" -maxdepth 1 -type f "$@" 2>/dev/null | wc -l; }
mapfile -t files < <(git ls-files '*.test.sh' '*.test.mjs' '*.test.py')
engine=0 other=0
for t in "${files[@]}"; do case $t in conveyor/conveyor.test.sh | conveyor/tests/*.test.sh) engine=1 ;; *) other=$((other + 1)) ;; esac; done
[ $engine = 0 ] || engine=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' conveyor/tests/*.test.sh | sort -u | wc -l)
echo "TESTRUN cases=$((engine + other))"
for t in "${files[@]}"; do
  case $t in
    *.mjs) c=(node --max-old-space-size=4096 --test "$t") ;;
    *.py) c=(python3 "$t") ;;
    *) c=(bash "$t") ;;
  esac
  n=$(marks); touch "$stamp"
  "${c[@]}" < /dev/null | awk '!/^TESTRUN cases=/ { print; fflush() }'
  if [ "${PIPESTATUS[0]}" = 0 ]; then echo "ok $t"; r=ok; else echo "FAIL $t"; rc=1; r=failed; fi
  [ ! -d "${CONVEYOR_TEST_LOG:-}" ] || [ "$(marks)" != "$n" ] || [ "$(marks -newer "$stamp")" != 0 ] || { mkdir -p "$CONVEYOR_TEST_LOG/cases/$r" && : > "$CONVEYOR_TEST_LOG/cases/$r/${t//\//:}"; }
done
exit $rc
