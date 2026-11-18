#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Each shell test file outside conveyor/tests/ that defines cases (the case scan, CASESCAN of conveyor/lib/testfiles.sh)
# runs only the cases CONVEYOR_SHELL_TEST_CASE names: test-changed.sh's one-file mode gives a file the cases a card
# changed in it so (issue 414). Bug it catches (issue 424): the foreman and research tests ran their own loop over all
# their cases, so a change to one case of foreman-standing.test.sh ran all seven while the step named one.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$ROOT" || exit 1
. conveyor/lib/testfiles.sh
fails=0
no() { echo "not ok - $1"; fails=1; }

scan=$(git ls-files -z -- '*.test.sh' ':!conveyor/tests/*.test.sh' ':!conveyor/conveyor.test.sh' \
  | xargs -0 awk -v q="'" "$CASESCAN")
files=$(cut -f1 <<<"$scan" | LC_ALL=C sort -u)
[ -n "$files" ] || no "the case scan found no shell test file with cases outside conveyor/tests/"
for f in $files; do
  # The line test-changed.sh looks for before it gives the file its changed cases (else the file runs whole).
  grep -q '^SEL=\${CONVEYOR_SHELL_TEST_CASE' "$f" || no "$f: no SEL=\${CONVEYOR_SHELL_TEST_CASE...} line, so test-changed.sh runs it whole"
  # A blank selection names no case: the file runs none and passes. A file that runs all its cases shows their calls.
  out=$(CONVEYOR_SHELL_TEST_CASE=' ' timeout 60 bash -x "$f" 2>&1); rc=$?
  [ "$rc" = 0 ] && ! grep -qE '^\++ "?t_[a-z0-9]+' <<<"$out" \
    || no "$f: a selection of no case ran a case, or failed (exit $rc): $(grep -E '^\++ "?t_[a-z0-9]+' <<<"$out" | head -3)"
  # A case it does not have is refused, not taken as none or as all; each case the scan finds in it is taken, as the
  # check stops at the first unknown name. Bug it catches: status.test.sh set its case list twice, and the second
  # dropped slowlive and slowdown, so a change to either was refused.
  want=$(awk -F'\t' -v f="$f" '$1 == f { printf "%s,", $2 }' <<<"$scan")
  out=$(CONVEYOR_SHELL_TEST_CASE="${want}nosuch" timeout 60 bash "$f" 2>&1); rc=$?
  [ "$rc" = 2 ] && grep -qF 'unknown case nosuch' <<<"$out" || no "$f: an unknown case was not refused (exit $rc): $(tail -3 <<<"$out")"
done
[ "$fails" = 0 ] && echo "ok - each shell test file with cases runs only the ones CONVEYOR_SHELL_TEST_CASE names"
exit "$fails"
