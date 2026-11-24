#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#1651): mapread() (lib/testmap.sh) on a project's own map of many test files named by their names
# alone. Their fixtures are testmap.test.sh's mapeng.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug it catches (#1651): mapread() looked each test a line of areas names by its name alone up by a scan of every
# tracked file, so a map of n such lines over n test files took n * n steps: 3000 of each took seconds of CPU in one
# jq, and every card's Test step reads the map. Looked up in an index of base names built once, it reads in a small
# part of that. The CPU limit (ulimit -t, CPU seconds, not wall time, so a busy machine does not fail it) is the check:
# the map's output alone is the same either way (t_testmaparea proves it), so only its cost shows the scan.
t_testmapreadmany() {
  local n=3000
  setup '[]'
  # The test files go into the index only (the empty blob, no file written): mapread() reads them from git ls-files.
  seq "$n" | awk -v b="$(git -C "$R" hash-object -w --stdin < /dev/null)" '{ printf "100644 %s\tt/d%d/t%d.test.sh\n", b, $1, $1 }' \
    | git -C "$R" update-index --index-info || fail "the test files could not be added to the index"
  { echo '{"area": "a", "file": "lib/a.sh"}'; seq "$n" | awk '{ printf "{\"area\": \"a\", \"test\": \"t%d.test.sh\"}\n", $1 }'; } > "$R/areas.json"
  tune '.test.map = "areas.json"'
  mapeng '(ulimit -t 2 && mapread "$R")' && jq -e --argjson n "$n" '.sources["lib/a.sh"] | length == $n and (.[0] | test("^t/d[0-9]+/t[0-9]+[.]test[.]sh$"))' "$T/$CASE/eng.out" > /dev/null \
    || fail "mapread of $n test files named by their names alone did not end in 2 s of CPU with each one found: $(tail -c 400 "$T/$CASE/eng.out")"
}
