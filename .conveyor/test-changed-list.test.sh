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
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILES BASH_ENV CONVEYOR_TEST_RERUN
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, a map of an "all" area and two areas of one case file each, a shell test named after
# its source, and test files that note in $R/ran that they ran.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests" "$R/lib"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "core", "file": "conveyor/core.sh"}' '{"area": "core", "tests": "all"}' \
  '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' \
  '{"area": "b", "file": "conveyor/y.sh"}' '{"area": "b", "test": "b.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 't_aone() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"
printf 't_bone() {\n  :\n}\n' > "$R/conveyor/tests/b.test.sh"
echo 'echo runner >> "$(dirname "$0")/../ran"' > "$R/conveyor/conveyor.test.sh"
echo 'echo s >> "$(dirname "$0")/../ran"' > "$R/lib/s.test.sh"
for f in conveyor/core.sh conveyor/x.sh conveyor/y.sh lib/s.sh; do echo 'echo one' > "$R/$f"; done
echo '{"test": {"files": {"conveyor/conveyor.test.sh": {"wholeOnly": true}}}}' > "$R/.conveyor/project.json"
echo ran > "$R/.gitignore"
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
# #150. Bug it catches: the tests the engine's map reader chose (the pack's test.list env: CONVEYOR_TEST_FILES) were
# not run, so this project's cards did not test through the path a user's card takes. An engine case file it names
# runs (through the runner), as does any other file, beside what the script's own selection finds.
printf '%s\n' '#!/usr/bin/env bash' 'echo e >> "$(dirname "$0")/../ran"' > "$R/lib/e.test.sh"
got=$(CONVEYOR_TEST_FILES=$'conveyor/tests/b.test.sh\nlib/e.test.sh' listed lib/s.sh)
[ "$got" = "conveyor/tests/b.test.sh lib/e.test.sh lib/s.test.sh " ] || no "the engine's list was not run beside the script's own selection: '$got'"
rm -f "$R/lib/e.test.sh"
# #367. Bug it catches: a document in a test folder (conveyor/tests/speed/<page>.md) that the engine's list named, or
# that a run again's list named as not passed (a `fail` line, "did not pass"), ran as a shell script and failed, and
# main was marked red for it. Neither selects it; the script's own selection still runs.
mkdir -p "$R/conveyor/tests/speed" && echo '# A page' > "$R/conveyor/tests/speed/lib-notes.md"
got=$(CONVEYOR_TEST_FILES=conveyor/tests/speed/lib-notes.md listed lib/s.sh)
[ "$got" = "lib/s.test.sh " ] || no "a document the engine's list named was selected: '$got'"
printf 'fail\tconveyor/tests/speed/lib-notes.md\t\n' > "$T/rerun"
got=$(CONVEYOR_TEST_RERUN=$T/rerun listed lib/s.sh)
[ "$got" = "lib/s.test.sh " ] || no "a document a run again's list named as not passed was selected: '$got'"
rm -rf "$R/conveyor/tests/speed"

[ $fails = 0 ] && echo "ok - test-changed list" || exit 1
