#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh's one-file mode (`--file <path>`, the pack's test.fileCommand) in a card's run that stops at its
# first failure (CONVEYOR_TEST_FAILFAST=1: the rule Stop a card's tests at the first failure, issue 1616). Bugs it
# catches: only the engine's runner was told, so a Board test file (node), a Python test file, a shell test file
# outside conveyor/tests/ and the plugin test run ran every case after their first failed one; the Board's case pool
# (dashboard-view.helpers.mjs cases()) started its next case before node reported the failed one; a shell test file's
# `FAIL: ` line did not stop it; a test file run in a group of its own (failstop) ran on when the loop ended the run;
# the live count (cases/ok) counted a case the stop skipped as passed; a plain node:test file started its next case
# before failstop read the failed one's `not ok` line; a process a test file started in a group of its own (timeout
# makes one: a Board collect of dashboard-limit.test.sh) ran on after the stop and after the run's end; the live count
# left out the cases that passed before the failure; and the Board's case pool ran a case node keeps off (a flaky
# one), whose failure stopped the file and passed it with the cases it selected not run. Each file here fails a case,
# and a later case leaves a mark as it starts or goes on: no mark is left, and the file fails.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN CONVEYOR_TEST_SLOT CONVEYOR_TEST_SLOTS CONVEYOR_TEST_POOL CONVEYOR_TEST_CASES
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, a map of one area, and the test files.
D=.claude/scripts/__tests__
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests" "$R/conveyor/lib" "$R/$D" "$R/hooks" "$T/bin"
# The Board files below run in the real case pool, whose workers load jsdom as the checkout's own Board tests do (npm
# ci installs it). Bug: in a checkout with no node_modules each case failed on `Cannot find module 'jsdom'`, and this
# test said the file whose flaky case is kept off had not run its later case.
node -e 'require("node:module").createRequire(process.argv[1]).resolve("jsdom")' "$HERE/../$D/dashboard-view.helpers.mjs" 2> /dev/null \
  || { echo "not ok - this checkout has no jsdom for the Board's case pool (dashboard-view.helpers.mjs): run npm ci"; exit 1; }
cp "$HERE/test-changed.sh" "$HERE/funcs.awk" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 't_aone() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"; echo 'echo one' > "$R/conveyor/x.sh"
echo '{}' > "$R/.conveyor/project.json"
# Each later case below waits $L s before it leaves its mark: the stop ends that wait, so only a file the stop missed
# waits it out. A short wait (3 s) let the mark land first on a loaded host, where the stop came late (main red).
L=30
# The Board file runs its cases in the real case pool, at most four at once: `first` fails at once, the three `hold`
# cases hold the other workers, and `later` starts only when a worker is free, the failed case's first.
printf '%s\n' "import { writeFileSync } from 'node:fs';" "import { setTimeout as wait } from 'node:timers/promises';" \
  "import { cases } from '$(cd "$HERE/.." && pwd -P)/$D/dashboard-view.helpers.mjs';" 'const test = cases(import.meta.url);' \
  "test('first', () => { throw new Error('broken'); });" "test('hold1', () => wait(${L}000));" "test('hold2', () => wait(${L}000));" \
  "test('hold3', () => wait(${L}000));" "test('later', () => { writeFileSync('$T/node-later', ''); });" > "$R/$D/w.test.mjs"
# A plain node:test file: node starts `later` at once after `first` fails.
printf '%s\n' "import test from 'node:test';" "import { writeFileSync } from 'node:fs';" "test('pass0', () => {});" \
  "test('first', () => { throw new Error('broken'); });" "test('later', () => { writeFileSync('$T/plain-later', ''); });" > "$R/$D/p.test.mjs"
# A Board file whose case `flaky` the rerun list keeps off (an `off` line, nodecases()): it fails at once if it runs,
# the `hold` cases hold the other workers, and `later` starts only when a worker is free.
printf '%s\n' "import { writeFileSync } from 'node:fs';" "import { setTimeout as wait } from 'node:timers/promises';" \
  "import { cases } from '$(cd "$HERE/.." && pwd -P)/$D/dashboard-view.helpers.mjs';" 'const test = cases(import.meta.url);' \
  "test('flaky', () => { throw new Error('flaky'); });" "test('hold1', () => wait(2000));" "test('hold2', () => wait(2000));" \
  "test('hold3', () => wait(2000));" "test('later', () => { writeFileSync('$T/k-ran', ''); });" > "$R/$D/k.test.mjs"
printf 'off\t%s\tflaky\n' "$D/k.test.mjs" > "$T/k.rerun"
printf '%s\n' 'import pathlib' 'import unittest' '' '' 'class W(unittest.TestCase):' \
  '    def test_a_first(self):' "        self.fail('broken')" '' '    def test_b_later(self):' "        pathlib.Path('$T/py-later').touch()" '' '' \
  "if __name__ == '__main__':" '    unittest.main()' > "$R/$D/w.test.py"
printf '%s\n' 'echo "not ok - first"' "sleep $L; : > '$T/sh-later'; echo 'ok - later'; exit 1 # sleep: the later case, past the stop" > "$R/conveyor/lib/s.test.sh"
printf '%s\n' 'echo "FAIL: broken" >&2' "sleep $L; : > '$T/fail-later'; exit 1 # sleep: the later part, past the stop" > "$R/conveyor/lib/f.test.sh"
# poll <file>: the text of a fixture's wait for a file a process it started writes. Its ceiling is that of the tests'
# wait (WAIT_CEILING, 120 s: conveyor/tests/wait.sh) times the run's load factor: a fixture whose file never comes
# fails then, and says what it waited for (issue 1840: with no ceiling, one held a proof run for 35 minutes).
WS=$(awk -v c="${WAIT_CEILING:-120}" -v f="${CONVEYOR_LOAD_FACTOR:-1}" 'BEGIN { x = c * f; print (x == int(x)) ? x : int(x) + 1 }')
poll() { echo "i=0; until [ -s '$1' ]; do [ \$((i += 1)) -le $((WS * 10)) ] || { echo 'no $1 after $WS s' >&2; exit 1; }; sleep 0.1; done"; }
# A shell test file whose later part runs in a group of its own (timeout's), started before its failed case.
printf '%s\n' "timeout 60 bash -c \"echo \\\$\\\$ > '$T/grp-pid'; sleep $L; : > '$T/grp-later'\" & # sleep: the later part, past the stop" \
  "$(poll "$T/grp-pid") # poll: the later part's start is seen only in the file it writes" \
  "echo 'not ok - first'; wait; exit 1" > "$R/conveyor/lib/g.test.sh"
printf '%s\n' "timeout 600 bash -c \"echo \\\$\\\$ > '$T/long-pid2'; exec sleep 300\" & # sleep: runs until the run's end ends it" \
  "$(poll "$T/long-pid2") # poll: the nested group's start is seen only in the file it writes" \
  "echo \$\$ > '$T/long-pid'; wait" > "$R/conveyor/lib/long.test.sh"
printf '%s\n' "test('one', () => {});" "test('first', () => {});" > "$R/hooks/w.test.ts"; printf '%s\n' "test('other', () => {});" > "$R/hooks/other.test.ts"
# The plugin test run (claude plugin test): another file's failed case, then this file's passed and failed ones, and
# the run going on past them.
st=$(printf '%s\n' '#!/usr/bin/env bash' "echo 'hooks/other.test.ts:'; echo '(fail) other'; sleep 1 # sleep: a stop at the other file's failure lands first" \
  "echo 'hooks/w.test.ts:'; echo '(pass) one'; echo '(fail) first'" \
  "sleep $L; : > '$T/ts-later'; echo '(pass) later' # sleep: the run past the stop")
# stub: the output of the plugin test run, in the order and with the waits above, is all test-changed.sh reads of it
printf '%s\n' "$st" > "$T/bin/claude"
chmod +x "$T/bin/claude"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init

# ff <file> <mark>: the one-file mode on <file>, as a card's run with the rule on gives it (CONVEYOR_TEST_FAILFAST=1);
# returns 1, saying why, when the file passed or its later case left <mark>. The script waits for the file's command
# and all it started, so a later case that was not ended has left its mark when it returns. The files run side by side.
ff() {
  local l=$T/log-${2%-later} rc
  mkdir -p "$l" && printf '%s\n' "$1" > "$l.list"
  (cd "$R" && env PATH="$T/bin:$PATH" CONVEYOR_TEST_LOG="$l" CONVEYOR_TEST_FILELIST="$l.list" CONVEYOR_TEST_FAILFAST=1 \
    bash .conveyor/test-changed.sh --file "$1") > "$l.out" 2>&1; rc=$?
  [ "$rc" != 0 ] || { no "test-changed.sh --file $1 with CONVEYOR_TEST_FAILFAST=1 and a failing first case passed: $(cat "$l.out")"; return 1; }
  [ ! -e "$T/$2" ] || { no "test-changed.sh --file $1 with CONVEYOR_TEST_FAILFAST=1 ran the case after its first failed one: $(cat "$l.out")"; return 1; }
}
# The loop ends a file of a run that stopped (lib/fileeach.sh) with a TERM to the file's timeout, which passes it to
# its process group: long.test.sh, which failstop runs in a group of its own, and the process it started in a group
# of its own (timeout's) must end with the run.
runend() {
  local l=$T/log-long i=0 tp pid q
  mkdir -p "$l" && printf '%s\n' conveyor/lib/long.test.sh > "$l.list"
  ( cd "$R" && exec env CONVEYOR_TEST_LOG="$l" CONVEYOR_TEST_FILELIST="$l.list" CONVEYOR_TEST_FAILFAST=1 \
    timeout 60 bash .conveyor/test-changed.sh --file conveyor/lib/long.test.sh ) > "$l.out" 2>&1 & tp=$!
  # poll: the test file's start is seen only in the file it writes
  while [ ! -s "$T/long-pid" ] && [ $i -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
  pid=$(cat "$T/long-pid" 2>/dev/null) || { no "test-changed.sh --file conveyor/lib/long.test.sh did not start the file: $(cat "$l.out")"; return 1; }
  kill -TERM "$tp"; wait "$tp"
  for q in "$pid" "$(cat "$T/long-pid2")"; do
    # poll: a process of another group ends on its own signal, a moment after the run's end (on a loaded host, more
    # than 5 s after); one that does not end runs its `sleep 300` on, past this poll
    i=0; while kill -0 "$q" 2>/dev/null && [ $i -lt 250 ]; do sleep 0.1; i=$((i + 1)); done
    ! kill -0 "$q" 2>/dev/null || { no "test-changed.sh --file conveyor/lib/long.test.sh, ended with TERM to its timeout, left this process of the test file running: $(ps -o pid=,stat=,args= -p "$q"); its output: $(cat "$l.out")"; kill -CONT "$q"; kill "$q"; return 1; }
  done
}
# The Board file k.test.mjs with its flaky case kept off: it passes, and its later case ran.
keptoff() {
  local l=$T/log-k rc
  mkdir -p "$l" && printf '%s\n' "$D/k.test.mjs" > "$l.list"
  (cd "$R" && env CONVEYOR_TEST_LOG="$l" CONVEYOR_TEST_FILELIST="$l.list" CONVEYOR_TEST_FAILFAST=1 CONVEYOR_TEST_RERUN="$T/k.rerun" \
    bash .conveyor/test-changed.sh --file "$D/k.test.mjs") > "$l.out" 2>&1; rc=$?
  [ "$rc" = 0 ] && [ -e "$T/k-ran" ] \
    || { no "test-changed.sh --file $D/k.test.mjs with CONVEYOR_TEST_FAILFAST=1 and the rerun list $(cat "$T/k.rerun") did not run its later case (exit $rc): $(cat "$l.out")"; return 1; }
}
ff "$D/w.test.mjs" node-later & a=$!
ff "$D/p.test.mjs" plain-later & m=$!
ff conveyor/lib/g.test.sh grp-later & n=$!
keptoff & k=$!
ff "$D/w.test.py" py-later & b=$!
ff conveyor/lib/s.test.sh sh-later & c=$!
ff conveyor/lib/f.test.sh fail-later & e=$!
ff hooks/w.test.ts ts-later & g=$!
runend & h=$!
for p in $a $b $c $e $g $h $m $n $k; do wait "$p" || fails=1; done
# Python's -f skipped test_b_later: the live count has its failed case and no passed one.
[ "$(ls -A "$T/log-py/cases/ok" 2>/dev/null | wc -l)" = 0 ] && [ "$(ls -A "$T/log-py/cases/failed" 2>/dev/null | wc -l)" = 1 ] \
  || no "test-changed.sh --file $D/w.test.py with CONVEYOR_TEST_FAILFAST=1 counted a case not run as passed or failed: ok: $(ls -A "$T/log-py/cases/ok" 2>&1), failed: $(ls -A "$T/log-py/cases/failed" 2>&1)"
# The cases that passed before the failed one are counted as passed: pass0 of the node file, `one` of the plugin's.
for x in plain:"$D/p.test.mjs" ts:hooks/w.test.ts; do
  [ "$(ls -A "$T/log-${x%%:*}/cases/ok" 2>/dev/null | wc -l)" = 1 ] && [ "$(ls -A "$T/log-${x%%:*}/cases/failed" 2>/dev/null | wc -l)" = 1 ] \
    || no "test-changed.sh --file ${x#*:} with CONVEYOR_TEST_FAILFAST=1, a passed case then a failed one, did not count one of each: ok: $(ls -A "$T/log-${x%%:*}/cases/ok" 2>&1), failed: $(ls -A "$T/log-${x%%:*}/cases/failed" 2>&1)"
done
# The plugin test run stopped at this file's failed case, not at another file's: this file's section was printed.
grep -qx '(pass) one' "$T/log-ts.out" || no "test-changed.sh --file hooks/w.test.ts with CONVEYOR_TEST_FAILFAST=1 stopped at another file's failed case: $(cat "$T/log-ts.out")"
[ "$fails" = 0 ] && echo "ok - test-changed.sh stops each test file at its first failed case"
exit "$fails"
