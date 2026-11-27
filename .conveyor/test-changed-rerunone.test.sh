#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh's one-file mode (`--file <path>`) in a run again whose list has a whole-file `fail` line of another
# engine case file: a card's run that stops at its first failure, where that file failed before any case passed
# (conveyor/lib/testrun.sh adds a `fail` line naming no case for each failed file). Bug it catches (#1630): the other
# file's cases took the place of this file's selection, were then left out as another file's, and the run exited 0
# with none of this file's cases run. The run must run this file's cases.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN CONVEYOR_TEST_SLOTS CONVEYOR_TEST_CASES CONVEYOR_TEST_FAILFAST
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, two engine case files, and a runner that writes each case it runs to a file.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-changed.sh" "$HERE/funcs.awk" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' '{"area": "a", "test": "b.test.sh"}' > "$R/.conveyor/engine-areas.json"
echo 'echo one' > "$R/conveyor/x.sh"
# The script runs an engine case file's cases through the runner, so the case files need only their cases.
for f in a b; do printf '%s\n' "t_${f}one() {" '  :' '}' > "$R/conveyor/tests/$f.test.sh"; done
printf '%s\n' "for c in \${CONVEYOR_SHELL_TEST_CASE:-}; do echo \"\$c\" >> '$T/ran'; echo \"ok \$c\"; done" > "$R/conveyor/conveyor.test.sh"
echo '{}' > "$R/.conveyor/project.json"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init

mkdir "$T/log"; printf 'fail\tconveyor/tests/a.test.sh\n' > "$T/rerun"; echo conveyor/tests/b.test.sh > "$T/list"
(cd "$R" && CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_FILELIST=$T/list CONVEYOR_TEST_RERUN=$T/rerun \
  bash .conveyor/test-changed.sh --file conveyor/tests/b.test.sh) > "$T/out" 2>&1; rc=$?
grep -qx bone "$T/ran" 2>/dev/null && [ "$rc" = 0 ] \
  || no "test-changed.sh --file conveyor/tests/b.test.sh with the rerun list '$(cat "$T/rerun")' did not run its case bone (exit $rc; cases run: $(cat "$T/ran" 2>/dev/null)): $(tail -n 20 "$T/out")"
! grep -qx aone "$T/ran" 2>/dev/null || no "test-changed.sh --file conveyor/tests/b.test.sh with the rerun list '$(cat "$T/rerun")' ran another file's case aone"

[ $fails = 0 ] && echo "ok - test-changed one-file run again with another file's whole-file fail line" || exit 1
