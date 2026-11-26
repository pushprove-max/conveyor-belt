#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# A card's Test step runs at most test.cardFiles (.conveyor/project.json) of the test files the area map and
# .conveyor/test-links.json give its change: with no failure history, the first that many of a test-changed.sh listing
# (CONVEYOR_TEST_LIST, which runs no test), as conveyor/lib/testlist.sh selfirst() keeps its order and testrun.sh
# testcap() keeps its first ones. The testfails and testtimeout cases of conveyor/tests/testruns.test.sh read the fails
# records through recok and loop snapshot, and both pass them through conveyor/jq/check.jq. Bug it catches: the link
# from check.jq to testruns.test.sh was listed by name among the record area's case files, so those that sort before it
# filled the card's few, and a card that changed check.jq alone ran neither case. This test asks the listing itself, as
# selfirst() does: a whole card run would pay for the loop to prove the same order.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
# The loop's test step sets these: left set, the listing would name the card's own files as well.
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST CONVEYOR_TEST_RERUN CONVEYOR_TEST_CASES BASH_ENV
n=$(jq -er '.test.cardFiles' "$HERE/project.json") || { echo "not ok - test.cardFiles could not be read from .conveyor/project.json"; exit 1; }

# A scratch repo: the real script and this checkout's real links, and an area map that gives check.jq one more case
# file than a card runs (a0.test.sh ...), each sorting before testruns.test.sh, so testruns.test.sh comes only from the
# links. Each case file is a stub of one empty case.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests" "$R/conveyor/jq"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-links.json" "$R/.conveyor/"
: > "$R/.conveyor/test-lint.sh"; : > "$R/.conveyor/no-browser-tests.sh"; : > "$R/.conveyor/no-records-split.sh"
echo '{"area": "a", "file": "conveyor/jq/check.jq"}' > "$R/.conveyor/engine-areas.json"
for i in $(seq 0 "$n"); do
  echo "{\"area\": \"a\", \"test\": \"a$i.test.sh\"}" >> "$R/.conveyor/engine-areas.json"; printf 't_a%s() {\n  :\n}\n' "$i" > "$R/conveyor/tests/a$i.test.sh"
done
printf 't_testruns() {\n  :\n}\n' > "$R/conveyor/tests/testruns.test.sh"
echo one > "$R/conveyor/jq/check.jq"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init || { echo "not ok - the scratch repo could not be made"; exit 1; }

# The change, and the linked files the engine gives the listing (CONVEYOR_TEST_FILELIST), by name as testsel() gives them.
echo two >> "$R/conveyor/jq/check.jq"
(cd "$R" && ls conveyor/tests/*.test.sh) > "$T/files"
(cd "$R" && CONVEYOR_TEST_LIST=$T/list CONVEYOR_TEST_FILELIST=$T/files bash .conveyor/test-changed.sh) > "$T/out" 2>&1 \
  || { echo "not ok - the listing of a change to conveyor/jq/check.jq, given '$(paste -sd' ' "$T/files")', failed: $(cat "$T/out")"; exit 1; }
head -n "$n" "$T/list" | grep -qxF conveyor/tests/testruns.test.sh \
  || { echo "not ok - a change to conveyor/jq/check.jq, given '$(paste -sd' ' "$T/files")', does not list conveyor/tests/testruns.test.sh in its first $n: '$(paste -sd' ' "$T/list" 2>&1)'"; exit 1; }
echo "ok - a change to conveyor/jq/check.jq lists conveyor/tests/testruns.test.sh in the first $n (test.cardFiles) a card runs"
