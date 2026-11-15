#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (the pack's test.full, .conveyor/project.json): every test file git lists, each run
# whole, in the checkout it is started in. release-prep, release and
# the Board's full test suite run it. Exit 1 if any file fails; each file's result is a line `ok <file>` or `FAIL <file>`.
# With the engine's test log folder (CONVEYOR_TEST_LOG), a file whose runner named none of its cases as ended there
# (cases/ok, cases/failed) is named there itself, its path's slashes as colons, so a whole-suite run's progress (on the
# Board and in /units) counts it and its failure.
rc=0
marks() { find "$CONVEYOR_TEST_LOG/cases/ok" "$CONVEYOR_TEST_LOG/cases/failed" -maxdepth 1 -type f 2>/dev/null | wc -l; }
while IFS= read -r t; do
  case $t in
    *.mjs) c=(node --max-old-space-size=4096 --test "$t") ;;
    *.py) c=(python3 "$t") ;;
    *) c=(bash "$t") ;;
  esac
  n=$(marks)
  if "${c[@]}" < /dev/null; then echo "ok $t"; r=ok; else echo "FAIL $t"; rc=1; r=failed; fi
  [ ! -d "${CONVEYOR_TEST_LOG:-}" ] || [ "$(marks)" != "$n" ] || { mkdir -p "$CONVEYOR_TEST_LOG/cases/$r" && : > "$CONVEYOR_TEST_LOG/cases/$r/${t//\//:}"; }
done < <(git ls-files '*.test.sh' '*.test.mjs' '*.test.py')
exit $rc
