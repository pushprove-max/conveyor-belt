#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh runs each engine case file it selects as a test file of its own (issue 214): its own process, test
# slot and result, with only its chosen cases. Bugs it catches: the chosen cases of two areas run as one runner's,
# named conveyor/conveyor.test.sh, so a failure, a red main, a flaky entry and a time name the runner, and a broken
# run fails the cases of every area at once; a case is lost in the split; the case files run one after another, not
# side by side on the pool's slots as the runner's cases did; a failed case is not run again by name in its own case
# file; a list written before (naming the runner) or a flaky case kept off under its case file is no longer read.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN CONVEYOR_TEST_SLOT CONVEYOR_TEST_SLOTS CONVEYOR_TEST_POOL
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, a map of three areas (a: x.sh and a.test.sh's two cases; b: y.sh and b.test.sh's
# one; c: z.sh and c.test.sh's one, which no change here selects), and a runner stub that notes each run in $R/ran as `<the file it runs as>:<its cases>:<slot or none>` and, as
# the runner does, the time of a case file whose every case it ran (CONVEYOR_TEST_TIMES). A run as the file named in
# $R/failing fails. With $R/meet, each run waits for the other file's to start: they meet only when side by side.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-changed.sh" "$HERE/funcs.awk" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' \
  '{"area": "b", "file": "conveyor/y.sh"}' '{"area": "b", "test": "b.test.sh"}' \
  '{"area": "c", "file": "conveyor/z.sh"}' '{"area": "c", "test": "c.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 't_aone() {\n  :\n}\nt_atwo() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"
printf 't_bone() {\n  :\n}\n' > "$R/conveyor/tests/b.test.sh"
printf 't_cone() {\n  :\n}\n' > "$R/conveyor/tests/c.test.sh"
cat > "$R/conveyor/conveyor.test.sh" <<'EOF'
d=$(dirname "$0")/..; f=${CONVEYOR_TEST_FILE##*/}
echo "$CONVEYOR_TEST_FILE:${CONVEYOR_SHELL_TEST_CASE:-ALL}:${CONVEYOR_TEST_SLOT:+slot}" >> "$d/ran"
if [ -e "$d/meet" ]; then
  : > "$d/started-$f"; o=a.test.sh; [ "$f" != a.test.sh ] || o=b.test.sh
  timeout 20 bash -c 'until [ -e "$1" ]; do sleep 0.05; done' _ "$d/started-$o" || { echo "FAIL [$f]: ran alone"; exit 1; }
fi
for c in $CONVEYOR_SHELL_TEST_CASE; do echo "ok $c"; done
[ ! -e "$d/hang" ] || { echo "$TMPDIR" > "$d/hung"; exec sleep 30; } # sleep: a stand-in run, which the step is told to end in
[ "$f:$CONVEYOR_SHELL_TEST_CASE" != "a.test.sh:aone atwo" ] || printf '%s\t1.0\t0.5\n' "$f" > "$CONVEYOR_TEST_TIMES"
[ "$CONVEYOR_TEST_FILE" != "$(cat "$d/failing" 2>/dev/null)" ]
EOF
echo one > "$R/conveyor/x.sh"; echo one > "$R/conveyor/y.sh"; echo one > "$R/conveyor/z.sh"
echo '{"test": {"files": {"conveyor/conveyor.test.sh": {"wholeOnly": true}}}}' > "$R/.conveyor/project.json"
printf '%s\n' ran meet 'started-*' failing hang hung > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
echo two >> "$R/conveyor/x.sh"; echo two >> "$R/conveyor/y.sh"
# run <log folder> [<list>]: the step on the change to x.sh and y.sh (both areas); prints the runs' notes, sorted.
run() {
  rm -f "$R/ran"; mkdir -p "$T/$1"
  (cd "$R" && env CONVEYOR_TEST_LOG="$T/$1" ${2:+CONVEYOR_TEST_RERUN="$2"} bash .conveyor/test-changed.sh) > "$T/out" 2>&1; echo $? > "$T/rc"
  LC_ALL=C sort "$R/ran" 2>/dev/null | paste -sd'|' -
}

# Both areas: a.test.sh with its two cases and b.test.sh with its one, each a run of its own on a slot of the pool (a
# pool of the test's own, of 2), side by side; b's run fails, and only b.test.sh fails. Every case the runner was
# given (the cases of the two areas' case files) runs in some case file, and no other.
echo conveyor/tests/b.test.sh > "$R/failing"; : > "$R/meet"
got=$(CONVEYOR_TEST_SLOTS=$ROOT/conveyor/lib/slots.sh CONVEYOR_TEST_POOL=2:$T/pool XDG_CONFIG_HOME=$T/cfg run both)
L=$T/both/test-changed.log
[ "$got" = "conveyor/tests/a.test.sh:aone atwo:slot|conveyor/tests/b.test.sh:bone:slot" ] && [ "$(cat "$T/rc")" = 1 ] \
  || no "two areas: each case file did not run its own cases alone, side by side on a slot: '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
all=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$R"/conveyor/tests/[ab].test.sh | sort | paste -sd' ' -)
[ "$(cut -d: -f2 <<<"${got//|/$'\n'}" | tr ' ' '\n' | sort | paste -sd' ' -)" = "$all" ] || no "a case of the runner ran in no case file: '$got', want '$all'"
grep -qxF -- '-- ok conveyor/tests/a.test.sh' "$L" && grep -qxF -- '-- FAIL conveyor/tests/b.test.sh' "$L" && ! grep -q 'conveyor/conveyor.test.sh' "$L" \
  && grep -qxF '== conveyor/tests/b.test.sh (cases: bone)' "$T/out" \
  || no "the results do not name each case file, or one file's failure failed the other: $(cat "$L")"
[ "$(sed -n 's/^TESTRUN case\t//p' "$L" | sort | tr '\t\n' ':|')" = "conveyor/tests/a.test.sh:aone|conveyor/tests/a.test.sh:atwo|conveyor/tests/b.test.sh:bone|" ] \
  && [ "$(sed -n 's/^TESTRUN why\t//p' "$L" | sort | tr '\t\n' ':|')" = "conveyor/tests/a.test.sh:the card changed conveyor/x.sh|conveyor/tests/b.test.sh:the card changed conveyor/y.sh|" ] \
  && grep -qxF "$(printf 'TESTRUN sec\tconveyor/tests/a.test.sh\t1.0\t0.5')" "$L" && [ "$(head -n 1 "$L")" = "TESTRUN files=2 of=3" ] \
  || no "the log does not name the case file of each case, reason and time: $(cat "$L")"
rm -f "$R/failing" "$R/meet" "$R"/started-*

# A run again: a.test.sh passed, b.test.sh's case failed: bone runs again by name in b.test.sh, and a.test.sh does not run.
printf 'change\tabc\npass\tconveyor/tests/a.test.sh\nfail\tconveyor/tests/b.test.sh\tbone\n' > "$T/list"
got=$(run again "$T/list")
[ "$got" = "conveyor/tests/b.test.sh:bone:" ] && [ "$(cat "$T/rc")" = 0 ] || no "a failed case did not run again alone in its case file: '$got': $(cat "$T/out")"
# A list written before, naming the cases under the runner, reads the same.
printf 'change\tabc\nok\tconveyor/conveyor.test.sh\taone\nok\tconveyor/conveyor.test.sh\tatwo\nfail\tconveyor/conveyor.test.sh\tbone\n' > "$T/list"
got=$(run old "$T/list")
[ "$got" = "conveyor/tests/b.test.sh:bone:" ] || no "a list naming the runner's case did not run it in its case file: '$got': $(cat "$T/out")"
# A flaky case kept off under its case file (the loop's ok and off lines: conveyor.sh flakyoff()) is left out.
printf 'ok\tconveyor/tests/a.test.sh\taone\noff\tconveyor/tests/a.test.sh\taone\n' > "$T/list"
got=$(run off "$T/list")
[ "$got" = "conveyor/tests/a.test.sh:atwo:|conveyor/tests/b.test.sh:bone:" ] || no "a case kept off under its case file still ran: '$got': $(cat "$T/out")"

# Told to end (its timeout) while a case file's run goes on, the step prints what each run printed, under its case
# file's `== ` line, begun and not ended in the log: a case that passed (its `ok` line) stays passed, and the timeout
# names a case file. Bug it catches: their output, kept until all ended, was lost, and every case ran again.
# The case file's own temp folder (its TMPDIR, noted in $R/hung) is gone once the step has ended (#1238: test runs
# left 2,097 temp folders in /tmp), and was no folder of the step's caller.
rm -f "$R/ran" "$R/hung"; : > "$R/hang"; mkdir -p "$T/term"
(cd "$R" && exec env CONVEYOR_TEST_LOG="$T/term" TMPDIR="$T" bash .conveyor/test-changed.sh) > "$T/out" 2>&1 & p=$!
i=0; until [ -s "$R/hung" ] || [ $((i += 1)) -gt 400 ]; do sleep 0.05; done
read -r ft < "$R/hung"
[ -d "$ft" ] && [ "${ft#"$T"/}" != "$ft" ] || no "a case file run by the step had no temp folder of its own in the step's TMPDIR $T while it ran: '$ft'"
kill -TERM "$p"; wait "$p"; rc=$?; rm -f "$R/hang"
grep -qxF '== conveyor/tests/a.test.sh (cases: aone atwo)' "$T/out" && grep -qxF 'ok aone' "$T/out" && [ "$rc" = 143 ] \
  && grep -qxF '== conveyor/tests/a.test.sh' "$T/term/test-changed.log" && ! grep -q '^-- ' "$T/term/test-changed.log" \
  || no "a step told to end lost what its case files printed: exit $rc: $(cat "$T/out"): $(cat "$T/term/test-changed.log")"
[ ! -e "$ft" ] || no "a case file's temp folder $ft is left once the step was told to end: $(ls -A "$T")"

[ $fails = 0 ] && echo "ok - test-changed runs each engine case file on its own" || exit 1
