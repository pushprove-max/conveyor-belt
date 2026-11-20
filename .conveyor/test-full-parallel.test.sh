#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh) in parallel mode (CONVEYOR_SUITE_MODE=parallel), on a pool
# of two test slots of its own. Bugs: an engine case file that held a slot its cases cannot use while they wait for
# slots of their own (two such files on a two-slot pool) would wait for ever; a file that reads the pool itself (as
# conveyor/tools/closure.test.sh does) held a slot, though its cases take their own; files run at once mixed their
# output lines; a file's own name in the progress log was left out when another file named its cases meanwhile; and a
# red run's failed cases were not under their own files.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo with the real script: two engine case files that each spread two cases over the pool's slots, as the
# engine's runner does (each case takes a slot, runs on it, and names itself in the test log), and one other file.
# Each prints two lines; each case notes that it ran.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests" "$R/lib"
cp "$HERE/test-full.sh" "$R/.conveyor/"
for f in fx-a fx-b; do
  printf '%s\n' '. "$CONVEYOR_TEST_SLOTS" && slot_pool || exit 1' "n=$f" \
    'for c in 1 2; do slot_take; ( slot_mine; echo "$n-$c" >> "$(dirname "$0")/../../ran"; mkdir -p "$CONVEYOR_TEST_LOG/cases/ok" && : > "$CONVEYOR_TEST_LOG/cases/ok/$n-$c" ) & slot_free; done; wait' \
    'echo "$n line 1"; echo "$n line 2"' > "$R/conveyor/tests/$f.test.sh"
done
printf '%s\n' 'echo "fx-x line 1"; echo "fx-x line 2"' > "$R/lib/fx-x.test.sh"
# A file outside the engine's case files that reads the pool itself, as conveyor/tools/closure.test.sh does, so its
# cases take slots of their own: it notes the slot it was started on (CONVEYOR_TEST_SLOT, which a file that holds a
# slot passes on, slot_mine), "none" when it holds none. Its path ends in no tracked test file's, so the test step does
# not take this test for a meta-runner.
mkdir -p "$R/tools" && printf '%s\n' 'echo "spread-${CONVEYOR_TEST_SLOT:-none}" >> "$(dirname "$0")/../ran"' \
  '. "$CONVEYOR_TEST_SLOTS" && slot_pool || exit 1' > "$R/tools/fx-spread.test.sh"
echo ran > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init

mkdir "$T/log" "$T/config"
# This runs the whole suite script, not one of its functions: the code under test is its top-level parallel loop, which
# is no function. That loop picks the files that hold no slot, takes and frees the slots, starts each file as a worker
# and gives each one its own output file and log folder; reap only collects a worker the loop started, and runone runs
# one file with none of this. Three of the bugs also need two files running at once on the shared pool (the wait for
# ever, mixed lines, a lost progress name).
(cd "$R" && unset CONVEYOR_TEST_SLOT CONVEYOR_CARD CONVEYOR_TEST_WHOLE && XDG_CONFIG_HOME=$T/config CONVEYOR_TEST_POOL=2:$T/pool \
  CONVEYOR_TEST_SLOTS=$HERE/../conveyor/lib/slots.sh CONVEYOR_TEST_LOG=$T/log CONVEYOR_SUITE_MODE=parallel timeout 60 bash .conveyor/test-full.sh) > "$T/out" 2>&1; rc=$?
[ $rc = 0 ] || no "the parallel suite on a pool of two slots did not end passed (exit $rc; 124: it hung): $(cat "$T/out")"
# spread-none: the file that reads the pool held no slot of its own, as its cases take theirs (the rule for a file that
# spreads its cases over slots); a file that held one would pass it on as CONVEYOR_TEST_SLOT.
[ "$(sort "$R/ran" 2>/dev/null | tr '\n' ' ')" = "fx-a-1 fx-a-2 fx-b-1 fx-b-2 spread-none " ] || no "not every case of the two case files ran once, or the file that reads the pool held a slot: $(cat "$R/ran" 2>&1)"
# Each file's lines, its time and its result, one block with no other file's line inside.
for f in conveyor/tests/fx-a.test.sh conveyor/tests/fx-b.test.sh lib/fx-x.test.sh; do
  n=${f##*/}; n=${n%.test.sh}
  awk -v n="$n" -v f="$f" '$0 == n " line 1" { getline a; getline b; getline c; if (a == n " line 2" && b ~ "^TESTRUN sec\t" f "\t" && c == "-- ok " f) ok = 1 } END { exit !ok }' "$T/out" \
    || no "the output of $f is not whole and in one piece with its result line: $(cat "$T/out")"
done
# The progress log names each case of the case files and the other files, which named none of their own, by path.
got=$(cd "$T/log/cases" && find ok failed -type f 2>/dev/null | sort | tr '\n' ' ')
[ "$got" = "ok/fx-a-1 ok/fx-a-2 ok/fx-b-1 ok/fx-b-2 ok/lib:fx-x.test.sh ok/tools:fx-spread.test.sh " ] || no "the progress log does not name each case and the files that named none: $got"

# The parallel suite again, as above, into the log folder <dir>.testlog and the output <dir>.test.
suite() { # <dir>
  mkdir "$1.testlog" && (cd "$R" && unset CONVEYOR_TEST_SLOT CONVEYOR_CARD CONVEYOR_TEST_WHOLE && XDG_CONFIG_HOME=$T/config CONVEYOR_TEST_POOL=2:$T/pool \
    CONVEYOR_TEST_SLOTS=$HERE/../conveyor/lib/slots.sh CONVEYOR_TEST_LOG=$1.testlog CONVEYOR_SUITE_MODE=parallel timeout 60 bash .conveyor/test-full.sh) > "$1.test" 2>&1
}
full=$(jq -r '.test.full' "$HERE/project.json")
failsof() { ( eval "$(sed -n '/^testfails() {/,/^}/p' "$HERE/../conveyor/lib/testrun.sh"; sed -n '/^testlogs() {/,/^}/p' "$HERE/../conveyor/lib/session.sh")"
  packget() { printf -v "$2" '%s' "$full"; } # the pack's test.full
  TEST_TIMEOUT=600 testfails "$1" "$2" test.full ); } # <output file> <exit>: the engine's failures of a run of the suite
# Bug (#1007): the engine put each failed case of a red suite under the suite's command, so its run alone ran the
# suite whole. In parallel, each file's output is printed once it ends: each failed case is still under its own file.
printf '%s\n' 'echo "FAIL [three]: wrong"; echo "FAIL [four]: wrong"; exit 1' > "$R/conveyor/tests/fx-c.test.sh"
git -C "$R" add -A && git -C "$R" commit -qm red
suite "$T/red"
got=$(failsof "$T/red.test" 1 | jq -c '[.files[] | .file as $f | .cases[] | "\($f) \(.name)"]')
[ "$got" = '["conveyor/tests/fx-c.test.sh three","conveyor/tests/fx-c.test.sh four"]' ] \
  || no "a red parallel suite's failed cases are not each under their case file: $got $(cat "$T/red.test")"
exit $fails
