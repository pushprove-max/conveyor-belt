#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh's list of its selection (CONVEYOR_TEST_LIST), which release-prep reads to rerun only the test files
# the changes since an earlier whole-suite run touch (issue 43). Bugs: the list names an engine case as the runner
# alone, so the whole suite's case files that hold it are not rerun; or the listing runs the tests it lists.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, a map of an "all" area and two areas of one case file each, a shell test named after
# its source, and test files that note in $R/ran that they ran.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests" "$R/lib"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "core", "file": "conveyor/core.sh"}' '{"area": "core", "tests": "all"}' \
  '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' \
  '{"area": "b", "file": "conveyor/y.sh"}' '{"area": "b", "test": "b.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 't_aone() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"
printf 't_bone() {\n  :\n}\n' > "$R/conveyor/tests/b.test.sh"
echo 'echo runner >> "$(dirname "$0")/../ran"' > "$R/conveyor/conveyor.test.sh"
echo 'echo s >> "$(dirname "$0")/../ran"' > "$R/lib/s.test.sh"
for f in conveyor/core.sh conveyor/x.sh conveyor/y.sh lib/s.sh; do echo 'echo one' > "$R/$f"; done
echo '{"test": {"files": {"conveyor/conveyor.test.sh": {"wholeOnly": true}}}}' > "$R/.conveyor/project.json"
printf '%s\n' ran linted > "$R/.gitignore"
# The test lint of the scratch repo only notes that a check ran (the list makes none: below).
echo 'echo linted >> "$(dirname "$0")/../linted"' > "$R/.conveyor/test-lint.sh"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
# listed <changed file>...: each file changed, the list made; prints it on one line. The change is undone after.
listed() {
  local f
  for f; do echo 'echo two' >> "$R/$f"; done
  (cd "$R" && CONVEYOR_TEST_LIST=$T/list bash .conveyor/test-changed.sh) > "$T/out" 2>&1 || no "the listing failed: $(cat "$T/out")"
  git -C "$R" checkout -q -- .
  tr '\n' ' ' < "$T/list" 2>/dev/null
}

got=$(listed conveyor/x.sh lib/s.sh)
[ "$got" = "conveyor/tests/a.test.sh lib/s.test.sh " ] || no "a change to an engine file and a source lists its case file and its named test: '$got'"
[ ! -e "$R/ran" ] || no "the listing ran tests: $(cat "$R/ran")"
# An "all" area's file selects the whole engine: the runner, though whole-only, and every case file.
got=$(listed conveyor/core.sh)
[ "$got" = "conveyor/conveyor.test.sh conveyor/tests/a.test.sh conveyor/tests/b.test.sh " ] || no "a change to an \"all\" area's file does not list the runner and every case file: '$got'"
# #150. Bug it catches: the tests the engine's map reader chose (the list CONVEYOR_TEST_FILELIST names) were
# not run, so this project's cards did not test through the path a user's card takes. An engine case file it names
# runs (through the runner), as does any other file, beside what the script's own selection finds.
printf '%s\n' '#!/usr/bin/env bash' 'echo e >> "$(dirname "$0")/../ran"' > "$R/lib/e.test.sh"
printf '%s\n' conveyor/tests/b.test.sh lib/e.test.sh > "$T/given"
got=$(CONVEYOR_TEST_FILELIST=$T/given listed lib/s.sh)
[ "$got" = "conveyor/tests/b.test.sh lib/e.test.sh lib/s.test.sh " ] || no "the engine's list was not run beside the script's own selection: '$got'"
rm -f "$R/lib/e.test.sh"
# #367. Bug it catches: a document in a test folder (conveyor/tests/speed/<page>.md) that the engine's list named, or
# that a run again's list named as not passed (a `fail` line, "did not pass"), ran as a shell script and failed, and
# main was marked red for it. Neither selects it; the script's own selection still runs.
mkdir -p "$R/conveyor/tests/speed" && echo '# A page' > "$R/conveyor/tests/speed/lib-notes.md"
echo conveyor/tests/speed/lib-notes.md > "$T/given"
got=$(CONVEYOR_TEST_FILELIST=$T/given listed lib/s.sh)
[ "$got" = "lib/s.test.sh " ] || no "a document the engine's list named was selected: '$got'"
printf 'fail\tconveyor/tests/speed/lib-notes.md\t\n' > "$T/rerun"
got=$(CONVEYOR_TEST_RERUN=$T/rerun listed lib/s.sh)
[ "$got" = "lib/s.test.sh " ] || no "a document a run again's list named as not passed was selected: '$got'"
rm -rf "$R/conveyor/tests/speed"
# #1595. The card's list names a passed case file with one case (conveyor/tests/c.test.sh, t_cone: CONVEYOR_TEST_CASES), and
# main's change since the list's `from` commit edits the file's other case, t_ctwo. Bugs it catches: (1) the list named the
# file because t_ctwo is chosen, though the file's own run is limited to t_cone, which passed: the loop started the file and it
# ran no case; (2) the list ran the checks of the tree, which the loop has run for it; (3) the cases kept of a file the list
# leaves out were not logged (`TESTRUN kept=`), so the test record lost them.
printf 't_cone() {\n  :\n}\nt_ctwo() {\n  :\n}\n' > "$R/conveyor/tests/c.test.sh"
git -C "$R" add -A && git -C "$R" commit -qm c
FROM=$(git -C "$R" rev-parse HEAD)
printf 't_cone() {\n  :\n}\nt_ctwo() {\n  : edited\n}\n' > "$R/conveyor/tests/c.test.sh" && git -C "$R" commit -qam main
echo conveyor/tests/c.test.sh > "$T/given"
printf 'pass\tconveyor/tests/c.test.sh\nmain\tconveyor/tests/c.test.sh\nfrom\t%s\n' "$FROM" > "$T/rerun"
# listwith <case of c.test.sh the card names>: the list the loop asks for, with the log folder $T/log; prints it on one line.
listwith() {
  rm -rf "$T/log" "$T/list"; mkdir "$T/log"
  (cd "$R" && CONVEYOR_TEST_LIST=$T/list CONVEYOR_TEST_RERUN=$T/rerun CONVEYOR_TEST_FILELIST=$T/given CONVEYOR_TEST_LOG=$T/log \
    CONVEYOR_TEST_CASES=$(printf 'conveyor/tests/c.test.sh\t%s' "$1") bash .conveyor/test-changed.sh) > "$T/out" 2>&1 || no "the listing failed: $(cat "$T/out")"
  tr '\n' ' ' < "$T/list" 2>/dev/null
}
got=$(listwith cone)
[ -z "$got" ] || no "main's change to t_ctwo listed the file the card runs only t_cone of, which passed: '$got'"
grep -qx 'TESTRUN kept=1' "$T/log/test-changed.log" || no "the one case kept of the file left out was not logged: $(cat "$T/log/test-changed.log" 2>&1)"
[ ! -e "$R/linted" ] || no "the list ran the checks of the tree"
# A list names files, not cases: that the file it names runs its selected cases is test-changed-one.test.sh's (one-file mode) and,
# through a card's run, conveyor/tests/mergetests.test.sh t_mainmovedselected's.
got=$(listwith ctwo)
[ "$got" = "conveyor/tests/c.test.sh " ] || no "main's change to t_ctwo did not list the file the card runs t_ctwo of: '$got'"
! grep -q 'TESTRUN kept' "$T/log/test-changed.log" 2>/dev/null || no "a file the list names was counted as kept: $(cat "$T/log/test-changed.log")"

[ $fails = 0 ] && echo "ok - test-changed list" || exit 1
