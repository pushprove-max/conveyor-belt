#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# test-changed.sh's checks (the Test step's test.checkCommand, run after each session) run the engine's unit cases of
# the changed engine files first (issue 1620: conveyor/unit/unit.sh). The checks read the change from git, so
# this runs the real script with --checks in a scratch repository: a call of the unit runner alone cannot show that.
# Bug: with no unit layer in the checks, a broken function was found only by the engine cases of the Test step; or
# the unit cases ran after the slower checks, so their failure was not the first thing the checks printed.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=${HERE%/*}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/lib" "$R/conveyor/tests" "$R/conveyor/unit"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
cp "$ROOT/conveyor/lib/portable.sh" "$R/conveyor/lib/"
cp "$ROOT/conveyor/unit/unit.sh" "$ROOT/conveyor/unit/portable.unit.sh" "$R/conveyor/unit/"
printf '%s\n' '{"outside": "conveyor/unit/"}' '{"area": "a", "file": "conveyor/lib/portable.sh"}' '{"area": "a", "test": "a.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 't_aone() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init || { echo "not ok - could not make the scratch repository"; exit 1; }
fails=0
no() { echo "not ok - $1"; fails=1; }
runchecks() { (cd "$R" && bash .conveyor/test-changed.sh --checks) > "$T/out" 2>&1; rc=$?; }
# First a change to portable.sh that breaks nothing (a comment): the checks pass on this tree, so in the next run
# only the unit case can make them fail. Bug: when another check also failed here, dropping `|| rc=1` from the unit
# runner's call in checks() kept the exit at 1 and this test passed with a unit failure that failed nothing.
printf '# a comment\n' >> "$R/conveyor/lib/portable.sh"
runchecks
[ "$rc" = 0 ] || no "test-changed.sh --checks with only a comment added to conveyor/lib/portable.sh must pass, so the unit case is the one failure below: exit $rc: $(cat "$T/out")"
# A change to portable.sh that breaks diffid: it hashes the line-number headers too.
sed -i.bak "s/grep -aEv '^(@@|index )'/grep -aEv '^(index )'/" "$R/conveyor/lib/portable.sh"
cmp -s "$R/conveyor/lib/portable.sh" "$R/conveyor/lib/portable.sh.bak" && { echo "not ok - could not break diffid: its filter is not the one this test changes"; exit 1; }
rm "$R/conveyor/lib/portable.sh.bak"
runchecks
if [ "$rc" = 1 ] && grep -q '^FAIL conveyor/unit/portable.unit.sh u_diffid: ' "$T/out" && grep -q '^unit: 2 cases of 1 unit files, 1 failed' "$T/out"; then
  echo "ok - a change that breaks diffid fails the checks on its unit case alone"
else
  no "test-changed.sh --checks with a broken diffid in conveyor/lib/portable.sh (no other check failing) must exit 1 on its unit case: exit $rc: $(cat "$T/out")"
fi
# And an engine file in no area, so the map check fails too: the unit case's failure must be printed before it.
printf '#!/usr/bin/env bash\n' > "$R/conveyor/lib/stray.sh"
runchecks
if [ "$rc" = 1 ] && u=$(grep -n -m1 '^FAIL conveyor/unit/' "$T/out" | cut -d: -f1) && m=$(grep -n -m1 'stray.sh: an engine source file in no area' "$T/out" | cut -d: -f1) \
  && [ "$u" -lt "$m" ]; then
  echo "ok - the unit case's failure is printed before the map check's"
else
  no "test-changed.sh --checks with a broken diffid in conveyor/lib/portable.sh and conveyor/lib/stray.sh in no area (the unit failure must come first): exit $rc: $(cat "$T/out")"
fi
exit "$fails"
