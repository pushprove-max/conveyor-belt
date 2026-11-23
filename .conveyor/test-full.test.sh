#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh, the pack's test.full). Bugs: the pack named no test.full, so
# `conveyor.sh release-prep` stopped before it ran a suite, wrote notes or posted a status; and a full suite that skips
# a test file, runs an untracked one or passes when one fails would let release-prep post a pass on a red commit.
set -u
unset CONVEYOR_TEST_LOG # this file's fixture suite names its files in a folder of its own, never in the run's
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo with the real script and the real pack's test.full: a passing shell test, a failing Python test, and
# an untracked test file that would fail. Each test file notes that it ran, so a check of what ran sees every file.
R=$T/r; mkdir -p "$R/.conveyor" "$R/lib"
cp "$HERE/test-full.sh" "$HERE/test-share.sh" "$R/.conveyor/"
full=$(jq -r '.test.full // empty' "$HERE/project.json")
[ -n "$full" ] || no "the pack (.conveyor/project.json) names no test.full"
echo 'echo pass >> "$(dirname "$0")/../ran"' > "$R/lib/fx-pass.test.sh"
printf 'import os, sys\nopen(os.path.join(os.path.dirname(__file__), "..", "ran"), "a").write("py\\n")\nsys.exit(1)\n' > "$R/lib/fx-fail.test.py"
# A runner that names its own case as ended in the engine's test log folder, as the engine's runner does.
echo '[ -z "${CONVEYOR_TEST_LOG:-}" ] || { mkdir -p "$CONVEYOR_TEST_LOG/cases/ok" && : > "$CONVEYOR_TEST_LOG/cases/ok/own"; }' >"$R/lib/fx-own.test.sh"
# It also times a file it starts, as a meta-runner does: that line is not the suite's.
printf 'printf "TESTRUN sec\\tlib/inner.test.sh\\t1.0\\t1.0\\n"\n' >> "$R/lib/fx-own.test.sh"
echo 'echo own >> "$(dirname "$0")/../ran"' >> "$R/lib/fx-own.test.sh"
# Two engine case files that run the same two cases under the same names, as the engine's runner and each case file
# do. Their names end in no tracked test file's path, so the test step does not take this test for a meta-runner.
mkdir -p "$R/conveyor/tests"
for f in conveyor/tests/fx-a.test.sh conveyor/tests/fx-b.test.sh; do
  n=${f#*fx-}; printf '%s\n' 't_one() { :; }' 't_two() { :; }' 'echo "TESTRUN cases=2"' "echo ${n%%.*} >> \"\$(dirname \"\$0\")/../../ran\"" \
    '[ -z "${CONVEYOR_TEST_LOG:-}" ] || { mkdir -p "$CONVEYOR_TEST_LOG/cases/ok" && : > "$CONVEYOR_TEST_LOG/cases/ok/one" && : > "$CONVEYOR_TEST_LOG/cases/ok/two"; }' > "$R/$f"
done
# The engine's runner, which runs the cases of those case files again; it notes that it ran.
echo 'echo "runner ${CONVEYOR_SHELL_TEST_CASE:-all}" >> "$(dirname "$0")/../ran"' > "$R/conveyor/conveyor.test.sh"
echo ran > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
echo 'echo untracked >> "$(dirname "$0")/../ran"' > "$R/lib/fx-untracked.test.sh"

mkdir "$T/log"
(cd "$R" && CONVEYOR_TEST_LOG=$T/log bash -c "$full") > "$T/out" 2>&1; rc=$?
# Bug: a whole-suite run's progress (release-prep, release, the Board's full test) counts only the cases the engine's
# runner names, so the Board's test files and their failures were left out of its cases done and failed.
# Bug: a case file that ran cases the runner had named already was named again as a file, a name the total has not.
got=$(cd "$T/log/cases" && find ok failed -type f | sort | tr '\n' ' ')
[ "$got" = "failed/lib:fx-fail.test.py ok/lib:fx-pass.test.sh ok/one ok/own ok/two " ] \
  || no "the full suite does not name each file that named no case of its own as ended, by its result: $got"
# Bug: the progress's total (fulltest.sh suiteprog(), the sum of the run's `TESTRUN cases=` lines) left out each file
# the suite names itself, and counted the engine's cases twice, so the Foreman's status showed a false total.
of=$(awk -F= '/^TESTRUN cases=/ { n += $2 } END { print n + 0 }' "$T/out")
[ "$of" = 5 ] || no "the full suite's case total is $of, not the 5 names it marks as ended: $(grep TESTRUN "$T/out")"
[ $rc = 1 ] || no "a failing test file did not fail the full suite (exit $rc): $(cat "$T/out")"
[ "$(sort "$R/ran" 2>/dev/null | tr '\n' ' ')" = "a b own pass py " ] || no "the full suite did not run each tracked test file alone, and not the runner: $(cat "$R/ran" 2>&1)"
# Bug (#720): the suite ran the engine's runner and then each case file, so each engine case ran twice (the runner
# alone took 950 s of a release's 3600 s), and the totals counted the runner. Its first two lines count what it runs.
[ "$(head -2 "$T/out" | tr '\n' ' ')" = "TESTRUN cases=5 TESTRUN files=5 " ] \
  || no "the full suite's first two lines do not count only the files it runs: $(head -2 "$T/out")"
grep -qx -- '-- ok lib/fx-pass.test.sh' "$T/out" && grep -qx -- '-- FAIL lib/fx-fail.test.py' "$T/out" \
  || no "the full suite does not name each file's result: $(cat "$T/out")"
# Bug: a whole-suite run timed no file, so the Tests page had no time for a file that only whole-suite runs run. Each
# file it ran has its own `TESTRUN sec` line, and a nested file and the runner, which it does not run, have none.
got=$(awk -F'\t' '$1 == "TESTRUN sec" && $3 ~ /^[0-9]+\.[0-9]$/ && $4 ~ /^[0-9]+\.[0-9]$/ { print $2 }' "$T/out" | sort | tr '\n' ' ')
[ "$got" = "conveyor/tests/fx-a.test.sh conveyor/tests/fx-b.test.sh lib/fx-fail.test.py lib/fx-own.test.sh lib/fx-pass.test.sh " ] \
  || no "the full suite does not time each file it runs, and only those: $got"
# Bug: the suite printed `ok <file>` and no file total, so the Release panel's progress (fulltest.sh suiteprog(), which
# reads `TESTRUN files=` and `-- ok|FAIL <file>`) had no files done of total and no failed file names.
cp "$T/out" "$T/wt.test"
# shellcheck source=/dev/null
source <(sed -n '/^suiteprog() {/,/^}/p' "$HERE/../conveyor/lib/fulltest.sh")
got=$(suiteprog "$T/wt" | jq -c .files)
[ "$got" = '{"done":5,"of":5,"failed":["lib/fx-fail.test.py"]}' ] \
  || no "the suite's progress does not count its files and failed file names: $got"

# With the failing file gone, the suite passes.
git -C "$R" rm -q lib/fx-fail.test.py && rm -f "$R/lib/fx-untracked.test.sh"
(cd "$R" && bash -c "$full") > "$T/out" 2>&1 || no "the full suite failed with every test file passing: $(cat "$T/out")"

# Bug (#43): release-prep reran every file though it names the few that failed or changed since the last suite run.
# With CONVEYOR_SUITE_FILES it runs only the test files of its list, and its totals count only those; a listed path
# that is no tracked test file (a source file, a deleted one) is not run.
# Bug: the list reached the files it runs, so a test file that runs a suite of its own (this one) ran a part of it:
# lib/fx-env fails when it sees the list.
printf '%s\n' 'echo env >> "$(dirname "$0")/../ran"' '[ -z "${CONVEYOR_SUITE_FILES:-}" ]' > "$R/lib/fx-env.test.sh" && git -C "$R" add lib/fx-env.test.sh && git -C "$R" commit -qm env
# Bug (#720): a list that names the engine's runner ran it, so its case files' cases ran twice.
printf '%s\n' lib/fx-pass.test.sh lib/fx-env.test.sh conveyor/tests/fx-a.test.sh lib/source.sh lib/gone.test.sh \
  conveyor/conveyor.test.sh > "$T/list"
rm -f "$R/ran"
(cd "$R" && CONVEYOR_SUITE_FILES=$T/list bash -c "$full") > "$T/out" 2>&1 || no "the listed files' run failed: $(cat "$T/out")"
got=$(sed -n 's/^-- ok //p' "$T/out" | sort | tr '\n' ' ')
[ "$got" = "conveyor/tests/fx-a.test.sh lib/fx-env.test.sh lib/fx-pass.test.sh " ] || no "the suite with a list did not run only its tracked test files: $got"
grep -qx 'TESTRUN files=3' "$T/out" && grep -qx 'TESTRUN cases=4' "$T/out" || no "the totals of a listed run are not of its files: $(grep TESTRUN "$T/out")"
[ "$(sort "$R/ran" 2>&1 | tr '\n' ' ')" = "a env pass " ] || no "the suite with a list naming the engine's runner ran it: $(cat "$R/ran" 2>&1)"

# Bug: the whole test on main runs each failed case alone 3 times through this suite (fulltest.sh fullalone()), which
# read no CONVEYOR_TEST_RERUN list, so each run alone was the whole suite again. With `fail` lines it runs only those
# files: of the engine's runner the cases named (of it or of an engine case file), of a node file the case named.
# Every fixture file notes that it ran, so a run that also starts a passed file or a case file is seen.
printf '%s\n' "import { test } from 'node:test'; import { appendFileSync } from 'node:fs';" "const ran = new URL('../ran', import.meta.url);" \
  "test('a (b)', () => appendFileSync(ran, 'node a\\n'));" "test('c', () => appendFileSync(ran, 'node c\\n'));" > "$R/lib/fx-node.test.mjs"
# A Python file has no case filter: its `fail` line runs the whole file (the notes of test-full.sh say so). The file notes
# its arguments, so a case name passed to it as a filter shows as `py a case`, not `py`.
printf '%s\n' 'import os, sys' 'open(os.path.join(os.path.dirname(__file__), "..", "ran"), "a").write(" ".join(["py"] + sys.argv[1:]) + "\n")' > "$R/lib/fx-py.test.py"
git -C "$R" add -A && git -C "$R" commit -qm runner && rm -f "$R/ran"
printf '%s\t%s\t%s\n' pass lib/fx-env.test.sh '' fail lib/fx-pass.test.sh '' fail conveyor/conveyor.test.sh one \
  fail conveyor/tests/fx-b.test.sh two fail lib/fx-node.test.mjs 'a (b)' fail lib/fx-py.test.py 'a case' | sed 's/\t$//' > "$T/rerun"
(cd "$R" && CONVEYOR_TEST_RERUN=$T/rerun bash -c "$full") > "$T/out" 2>&1 || no "the run of failed cases alone failed: $(cat "$T/out")"
got=$(sort "$R/ran" 2>/dev/null | tr '\n' ' ')
[ "$got" = "node a pass py runner one,two " ] || no "a list's failed cases were not run alone, or a Python file named with a case did not run whole: $got"
grep -qx 'TESTRUN files=4' "$T/out" && grep -qx 'TESTRUN cases=5' "$T/out" || no "the totals of a run alone are not of its cases: $(grep TESTRUN "$T/out")"
git -C "$R" rm -q -f lib/fx-py.test.py && git -C "$R" commit -qm nopy && rm -f "$R/ran" # the later cases run the suite whole
# Bug (#1007): the suite wrote no log of its files, so the engine (testrun.sh testfails()) put every failed case of a
# red suite under the suite's command, and each run of one alone (fulltest.sh fullalone()) named the command in its
# `fail` line: the suite ran whole again for each, and a release with 3 failed cases took an hour. Each failed case of
# an engine case file is now under that file, and its run alone runs that case only. This runs the real suite twice
# over (a red whole run, then each case alone) with the engine's own readers: what the engine reads from a real run's
# log and output is what this proves, which a hand-written log cannot show.
printf '%s\n' 't_three() { :; }' 't_four() { :; }' 'echo fx-c >> "$(dirname "$0")/../../ran"' \
  'echo "FAIL [three]: wrong"; echo "FAIL [four]: wrong"; exit 1' > "$R/conveyor/tests/fx-c.test.sh"
git -C "$R" add -A && git -C "$R" commit -qm red
W=$T/red; mkdir "$W.testlog"
(cd "$R" && CONVEYOR_TEST_LOG=$W.testlog bash -c "$full") > "$W.test" 2>&1
failsof() { ( eval "$(sed -n '/^testfails() {/,/^}/p' "$HERE/../conveyor/lib/testrun.sh"; sed -n '/^testlogs() {/,/^}/p' "$HERE/../conveyor/lib/session.sh")"
  packget() { printf -v "$2" '%s' "$full"; } # the pack's test.full
  TEST_TIMEOUT=600 testfails "$1" "$2" test.full ); } # <output file> <exit>: the engine's failures of a run of the suite
units=$(failsof "$W.test" 1 | jq -c '.files[] | .file as $f | .cases[] | {file: $f, case: .name}')
[ "$(jq -sc 'map("\(.file) \(.case)")' <<<"$units")" = '["conveyor/tests/fx-c.test.sh three","conveyor/tests/fx-c.test.sh four"]' ] \
  || no "a red suite's failed cases are not each under their engine case file: $units $(cat "$W.test")"
while IFS= read -r u; do
  rm -f "$R/ran"
  got=$( eval "$(sed -n '/^fullalone() {/,/^}/p' "$HERE/../conveyor/lib/fulltest.sh")"
    tests() { (cd "$R" && CONVEYOR_TEST_RERUN=$1.rerun bash -c "$full") > "$1.test" 2>&1; }
    fullalone "$W" '{"files":[]}' "$u" > /dev/null; grep $'^fail\t' "$W.rerun" )
  c=$(jq -r .case <<<"$u")
  [ "$got" = "fail"$'\t'"conveyor/tests/fx-c.test.sh"$'\t'"$c" ] || no "the run alone of $c does not name its case file and case: $got"
  [ "$(cat "$R/ran" 2>&1)" = "runner $c" ] || no "the run alone of $c ran more than that case: $(cat "$R/ran" 2>&1)"
done <<<"$units"
git -C "$R" rm -q conveyor/tests/fx-c.test.sh && git -C "$R" commit -qm green
# Bug (#1007 review): a suite stopped at its timeout left a log naming the file it was in as the one still running, so
# the engine took that file for the run's timeout, and its run alone (all the others listed as passed) could pass the
# release though the suite never reached the files after it. A stopped run leaves no log: the timeout is the suite's.
# This stops the real suite, as the test step's timeout does: what it leaves is what a stop of no function shows.
echo 'sleep 60' > "$R/lib/fx-slow.test.sh" && git -C "$R" add -A && git -C "$R" commit -qm slow
W=$T/stop; mkdir "$W.testlog"
(cd "$R" && CONVEYOR_TEST_LOG=$W.testlog timeout 5 bash -c "$full") > "$W.test" 2>&1
got=$(failsof "$W.test" 124 | jq -r '.timeout.file')
[ "$got" = "$full" ] || no "a stopped serial suite's timeout is not the suite's but $got: $(cat "$W.test")"
git -C "$R" rm -q lib/fx-slow.test.sh && git -C "$R" commit -qm fast
# A list with no `fail` line (files kept off as passed before) leaves the suite whole. The fixture runner goes first:
# started whole, the test step's hook would take it for a test file this one runs.
git -C "$R" rm -q conveyor/conveyor.test.sh && git -C "$R" commit -qm 'no runner'
rm -f "$R/ran"; printf 'pass\tlib/fx-pass.test.sh\noff\tlib/fx-pass.test.sh\n' > "$T/rerun"
(cd "$R" && CONVEYOR_TEST_RERUN=$T/rerun bash -c "$full") > "$T/out" 2>&1
got=$(sort "$R/ran" 2>/dev/null | tr '\n' ' ')
[ "$got" = "a b env node a node c own pass " ] || no "a list with no failed case did not run the whole suite: $got"
# Bug (#88): a run with no per-file logs names its failed case's file by the pack's command (testrun.sh testfails()).
# Its `fail` line selected no file, so each run alone ran nothing and passed, and the failure was taken as flaky.
rm -f "$R/ran"; printf 'pass\tlib/fx-pass.test.sh\nfail\t%s\tc\n' "$full" > "$T/rerun"
(cd "$R" && CONVEYOR_TEST_RERUN=$T/rerun bash -c "$full") > "$T/out" 2>&1
got=$(sort "$R/ran" 2>/dev/null | tr '\n' ' ')
[ "$got" = "a b env node a node c own pass " ] || no "a failed case named by the command, not a test file, ran no test file: $got"

# Bug (#720): the suite runs each engine case in its case file alone, not in the runner, so a case file that does not
# start the runner with its cases (swebenchshow.test.sh only defined them) exits 0 having run none of them, while the
# suite's total still counts them. Each of this checkout's case files, run alone, starts the runner with its own cases.
E=$T/engine; mkdir -p "$E/tests"; cp "$HERE"/../conveyor/tests/*.test.sh "$E/tests/"
# A stub runner that notes the cases it is given, by CONVEYOR_SHELL_TEST_CASE or as arguments.
echo 'echo "${CONVEYOR_SHELL_TEST_CASE:-} $*" > "$(dirname "$0")/cases"' > "$E/conveyor.test.sh"
for f in "$E"/tests/*.test.sh; do
  want=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$f" | sort | tr '\n' ' ')
  [ -n "$want" ] || continue
  rm -f "$E/cases"; (cd "$T" && bash "$f" < /dev/null > /dev/null 2>&1)
  got=$(tr ' ' '\n' < "$E/cases" 2>/dev/null | grep . | sort | tr '\n' ' ')
  [ "$got" = "$want" ] || no "conveyor/tests/${f##*/}, run alone, did not run its cases ($want) but: $got"
done

[ $fails = 0 ] && echo "ok - test-full" || exit 1
