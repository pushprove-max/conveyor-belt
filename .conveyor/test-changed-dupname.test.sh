#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The map check of test-changed.sh (mapcheck, run on every card's test run) and two test files of one name. The map
# names a case file by its file name alone, and the engine's map reader (lib/testmap.sh mapread()) takes that as the
# one test file of the repository with that name. Bug it catches (#332): a second standing.test.sh (under
# conveyor/foreman/) made the reader point to neither file, and the check passed, so every card after it ran without
# the map. The check must fail and name both files. Also two case files that define one function (#871, below).
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILES CONVEYOR_TEST_RERUN
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, one area whose case file is a.test.sh.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests" "$R/conveyor/other"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$R/.conveyor/"
printf '%s\n' '{"outside": "conveyor/other/"}' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' > "$R/.conveyor/engine-areas.json"
echo 'echo one' > "$R/conveyor/x.sh"; echo ': a' > "$R/conveyor/tests/a.test.sh"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
check() { (cd "$R" && bash .conveyor/test-changed.sh --check) > "$T/out" 2>&1; }

# With one a.test.sh the check passes: the failure below is the second file's.
check || no "the check failed with one a.test.sh: $(cat "$T/out")"

# Two case files that define one function (#871: watched() in views.test.sh and stall.test.sh). The runner
# (conveyor/conveyor.test.sh) sources every case file before any case runs, so in every run the later file's
# replaces the other's for the cases of both. The check must fail and name the function and both files. A copy of the
# function in a fixture's heredoc is no second definition, nor is a text after a quoted <<; both must still pass.
printf '%s\n' 'w() { :; }' > "$R/conveyor/tests/a.test.sh"
printf '%s\n' 'b() { echo "cat <<'"'E'"'"; }' 'w() (' '  :' ')' > "$R/conveyor/tests/b.test.sh"
printf '%s\n' '{"area": "a", "test": "b.test.sh"}' >> "$R/.conveyor/engine-areas.json"
git -C "$R" add -A
if check; then no "the check passed with w() in a.test.sh and b.test.sh: $(cat "$T/out")"
else grep -qxF 'w(): defined in 2 case files (conveyor/tests/a.test.sh, conveyor/tests/b.test.sh); the runner sources them all, so one replaces the others in every run: rename it' "$T/out" \
  || no "the check failed, but not naming w() and both files: $(cat "$T/out")"; fi
printf '%s\n' 'b() { echo "cat <<'"'E'"'"; }' 'cat > "$T/x" <<'"'EOF'"'' 'w() { :; }' 'EOF' > "$R/conveyor/tests/b.test.sh"
git -C "$R" add -A
check || no "the check failed with w() only in a.test.sh and in a heredoc of b.test.sh: $(cat "$T/out")"
# A second a.test.sh, outside the engine's case files (as conveyor/foreman/ was), staged as a card's new file is.
echo ': other a' > "$R/conveyor/other/a.test.sh"; git -C "$R" add conveyor/other/a.test.sh
if check; then no "the check passed with two a.test.sh files: $(cat "$T/out")"
else grep -qF 'a.test.sh: named in .conveyor/engine-areas.json, but 2 test files have that name (conveyor/other/a.test.sh, conveyor/tests/a.test.sh)' "$T/out" \
  || no "the check failed, but not naming both a.test.sh files: $(cat "$T/out")"; fi

[ $fails = 0 ] && echo "ok - the map check refuses two test files of a name the map names, and two case files of a function" || exit 1
