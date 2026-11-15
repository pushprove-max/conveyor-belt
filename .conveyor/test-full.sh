#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (the pack's test.full, .conveyor/project.json): every test file git lists, each run
# whole, in the checkout it is started in. release-prep, release and
# the Board's full test suite run it. Exit 1 if any file fails; each file's result is a line `ok <file>` or `FAIL <file>`.
rc=0
while IFS= read -r t; do
  case $t in
    *.mjs) c=(node --max-old-space-size=4096 --test "$t") ;;
    *.py) c=(python3 "$t") ;;
    *) c=(bash "$t") ;;
  esac
  if "${c[@]}" < /dev/null; then echo "ok $t"; else echo "FAIL $t"; rc=1; fi
done < <(git ls-files '*.test.sh' '*.test.mjs' '*.test.py')
exit $rc
