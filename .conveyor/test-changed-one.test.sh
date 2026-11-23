#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh's one-file mode (`--file <path>`, the pack's test.fileCommand; issue 379): Conveyor runs each test
# file the card lists in its own process through it. Bugs it catches: the mode runs the whole selection of the change
# (every file the change touches, not only the one given), so a card's 50 listed files widen to 129+ and #350's stop
# refuses the run; a path that does not exist runs the checks and the selection, or passes; and under the engine's
# own file loop (filecmd()) each file is counted twice, so the run reads as more files than it was given.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN CONVEYOR_TEST_SLOT CONVEYOR_TEST_SLOTS CONVEYOR_TEST_POOL
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, a map of three areas (a: x.sh and a.test.sh's two cases; b: y.sh and b.test.sh's
# one; c: z.sh and c.test.sh's one, which no change here selects, so a and b are not every case file), a hooks test,
# a Board test and a shell test of conveyor/lib/ that no change selects, and a runner stub; each notes its run in
# $R/ran as `<the file it runs as>:<its cases>`. The change touches x.sh and y.sh: both areas.
B=.claude/scripts/__tests__/w.test.py
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests" "$R/hooks" "$R/${B%/*}"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "a", "file": "conveyor/x.sh"}' '{"area": "a", "test": "a.test.sh"}' \
  '{"area": "b", "file": "conveyor/y.sh"}' '{"area": "b", "test": "b.test.sh"}' \
  '{"area": "c", "file": "conveyor/z.sh"}' '{"area": "c", "test": "c.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 't_aone() {\n  :\n}\nt_atwo() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"
printf 't_bone() {\n  :\n}\n' > "$R/conveyor/tests/b.test.sh"
printf 't_cone() {\n  :\n}\n' > "$R/conveyor/tests/c.test.sh"
cat > "$R/conveyor/conveyor.test.sh" <<'EOF'
echo "$CONVEYOR_TEST_FILE:${CONVEYOR_SHELL_TEST_CASE:-ALL}" >> "$(dirname "$0")/../ran"
for c in $CONVEYOR_SHELL_TEST_CASE; do echo "ok $c"; done
EOF
printf '%s\n' 'echo "hooks/h.test.sh:ALL" >> "$(dirname "$0")/../ran"' "[ ! -r /proc/self/cgroup ] || cat /proc/self/cgroup > '$T/h.cgroup'" > "$R/hooks/h.test.sh"
# A shell test file outside conveyor/tests/ that selects its cases as the runner does; it notes the cases it runs. Its
# two t_ lines make the step count it as two cases when it runs whole.
mkdir -p "$R/conveyor/lib"
printf '%s\n' 'ALL="sone stwo"' 'SEL=${CONVEYOR_SHELL_TEST_CASE:-$ALL}; SEL=${SEL//,/ }' 't_sone() { :; }' 't_stwo() { :; }' \
  'echo "conveyor/lib/s.test.sh:${SEL// /,}" >> "$(dirname "$0")/../../ran"' > "$R/conveyor/lib/s.test.sh"
printf '%s\n' 'with open("ran", "a") as f: f.write("'"$B"':ALL\n")' > "$R/$B"
echo one > "$R/conveyor/x.sh"; echo one > "$R/conveyor/y.sh"; echo one > "$R/conveyor/z.sh"
echo '{"test": {"files": {"conveyor/conveyor.test.sh": {"wholeOnly": true}}}}' > "$R/.conveyor/project.json"
echo ran > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
echo two >> "$R/conveyor/x.sh"; echo two >> "$R/conveyor/y.sh"
# one <log folder> <path> [<cases>]: the one-file mode on that path, given both areas' case files and <path> as the
# engine's list (as filecmd() passes a card's own test files on), and <cases> as the cases the engine names of them
# (CONVEYOR_TEST_CASES); prints the runs' notes, sorted.
one() {
  rm -f "$R/ran"; mkdir -p "$T/$1" && printf '%s\n' conveyor/tests/a.test.sh conveyor/tests/b.test.sh "$2" > "$T/$1.list"
  (cd "$R" && env CONVEYOR_TEST_LOG="$T/$1" CONVEYOR_TEST_FILELIST="$T/$1.list" CONVEYOR_TEST_CASES="${3:-}" \
    bash .conveyor/test-changed.sh --file "$2") > "$T/out" 2>&1; echo $? > "$T/rc"
  LC_ALL=C sort "$R/ran" 2>/dev/null | paste -sd'|' -
}

# An engine case file: only it runs, with its chosen cases, and its log says one file.
got=$(one area conveyor/tests/a.test.sh)
[ "$got" = "conveyor/tests/a.test.sh:aone atwo" ] && [ "$(cat "$T/rc")" = 0 ] \
  && [ "$(grep '^TESTRUN files=' "$T/area/test-changed.log")" = "TESTRUN files=1 of=6" ] \
  || no "the one-file mode given an area file ran more than it: '$got', exit $(cat "$T/rc"): $(cat "$T/out"): $(cat "$T/area/test-changed.log" 2>/dev/null)"

# Issue 414. Bug it catches: a card that changed one case of an area file ran all its cases. The cases the engine
# names of the file (CONVEYOR_TEST_CASES: those the card's change adds or changes) run alone: atwo, not aone; a case
# of another file, or one the file does not have, does not run.
got=$(one cases conveyor/tests/a.test.sh $'conveyor/tests/a.test.sh\tatwo\nconveyor/tests/a.test.sh\tgone\nconveyor/tests/b.test.sh\tbone')
[ "$got" = "conveyor/tests/a.test.sh:atwo" ] && [ "$(cat "$T/rc")" = 0 ] \
  || no "the one-file mode did not run only the cases the engine named: '$got', exit $(cat "$T/rc"): $(cat "$T/out")"

# Issue 414 (E2). Bug it catches: a shell test file outside conveyor/tests/ ran all its cases while the test line
# named only the changed one, also when the engine's list names the file (which marks it whole). The case the engine
# names of it runs alone (stwo, not sone). Issue 423: also when the card's change touches the file itself, so the
# first run's reasons (freshen(), which picks the change again) select it whole.
cp "$R/conveyor/lib/s.test.sh" "$T/s.keep"; echo true >> "$R/conveyor/lib/s.test.sh"
got=$(one shell conveyor/lib/s.test.sh $'conveyor/lib/s.test.sh\tstwo')
cp "$T/s.keep" "$R/conveyor/lib/s.test.sh"
[ "$got" = "conveyor/lib/s.test.sh:stwo" ] && [ "$(cat "$T/rc")" = 0 ] \
  || no "the one-file mode did not run only the case the engine named of a shell test file: '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
# Issue 1439. Bugs: the run of stwo alone was counted as both cases of the file (TESTRUN cases=2, two records in
# cases/ok), and its log named no case it ran, so the step's record left the case out and the test cache kept the
# file as passed whole. One case is counted, one record written, and the case is logged.
grep -q '^TESTRUN cases=1 ' "$T/shell/test-changed.log" \
  && [ "$(find "$T/shell/cases" -type f | wc -l)" = 1 ] && [ "$(find "$T/shell/cases/ok" -type f | wc -l)" = 1 ] \
  && grep -qxF $'TESTRUN case\tconveyor/lib/s.test.sh\tstwo' "$T/shell/test-changed.log" \
  || no "the run of stwo alone of conveyor/lib/s.test.sh was not counted and logged as one case: records $(find "$T/shell/cases" -type f 2>/dev/null | paste -sd' ' -): $(cat "$T/shell/test-changed.log")"

# A test file outside the engine (the hooks'), which the change does not select: it runs whole, and no case file runs.
# Issue 348: with the engine's slots library and a pool, it runs in this script's own cgroup (Linux). Bug it catches:
# each such file was started in a systemd scope of its own with a hard memory cap of the machine's memory over the
# slots (slot_box), so a test that needed more was killed and counted as a failure.
got=$(CONVEYOR_TEST_SLOTS=$ROOT/conveyor/lib/slots.sh CONVEYOR_TEST_POOL=2:$T/pool XDG_CONFIG_HOME=$T/cfg one hooks hooks/h.test.sh)
[ "$got" = "hooks/h.test.sh:ALL" ] && [ "$(cat "$T/rc")" = 0 ] && grep -qxF -- '-- ok hooks/h.test.sh' "$T/hooks/test-changed.log" \
  || no "the one-file mode given a hooks test did not run it alone: '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
[ ! -r /proc/self/cgroup ] || [ "$(cat "$T/h.cgroup")" = "$(cat /proc/self/cgroup)" ] \
  || no "a test file ran in a cgroup of its own (a capped box), not its runner's: $(cat "$T/h.cgroup" 2>/dev/null)"

# A path that does not exist: it fails at once, running no test, check or selection, and writes no log.
got=$(one none conveyor/tests/gone.test.sh)
[ -z "$got" ] && [ "$(cat "$T/rc")" != 0 ] && [ ! -e "$T/none/test-changed.log" ] \
  && [ "$(cat "$T/out")" = "test-changed: --file: no such test file: 'conveyor/tests/gone.test.sh'" ] \
  || no "the one-file mode given a missing path did not fail at once: '$got', exit $(cat "$T/rc"): $(cat "$T/out")"

# Issue 382: the engine's runner given as the file is no test file. It is refused at once, as the last guard after
# the engine's list leaves runners off: nothing runs, not even the checks every run makes, and no log is written.
got=$(one runner ./conveyor/conveyor.test.sh)
[ -z "$got" ] && [ "$(cat "$T/rc")" = 2 ] && [ ! -e "$T/runner/test-changed.log" ] \
  && [ "$(cat "$T/out")" = "test-changed: --file: conveyor/conveyor.test.sh is a runner of the whole suite, not a test file: not run" ] \
  || no "the one-file mode given the engine's runner did not refuse it: '$got', exit $(cat "$T/rc"): $(cat "$T/out")"

# Through the engine's own loop for test.fileCommand (filecmd() of conveyor/lib/testrun.sh, on the pack's own
# test.fileCommand in .conveyor/project.json): each listed file (two area files and a Board test) runs alone, each run reports `TESTRUN files=1` (in its output), and
# the run's count (testprogress(), which watch() holds against the files given) is the three files it was given, not
# each counted twice.
rm -f "$R/ran"; mkdir -p "$T/fc"
fc=$(jq -er '.test.fileCommand' "$HERE/project.json") || no "the pack sets no test.fileCommand"
(
  # shellcheck disable=SC2034 # read by testrun.sh as it is sourced
  HERE=$ROOT/conveyor STATE=$T/state; . "$ROOT/conveyor/lib/testrun.sh"; . "$ROOT/conveyor/lib/session.sh"
  filecmd "$fc" files > "$T/fc.sh"
  printf '%s\n' conveyor/tests/a.test.sh conveyor/tests/b.test.sh "$B" > "$T/fc.list"
  (cd "$R" && env CONVEYOR_TEST_LOG="$T/fc" CONVEYOR_TEST_FILELIST="$T/fc.list" bash "$T/fc.sh") > "$T/fc.out" 2>&1
  echo $? > "$T/rc"; testprogress "$T/fc.out" "$T"/fc/* > "$T/fc.json"
) 2> /dev/null
got=$(LC_ALL=C sort "$R/ran" 2>/dev/null | paste -sd'|' -)
counts=$(sed -n 's/^TESTRUN files=\([0-9]*\) .*/\1/p' "$T/fc.out" | paste -sd' ' -)
[ "$got" = "$B:ALL|conveyor/tests/a.test.sh:aone atwo|conveyor/tests/b.test.sh:bone" ] && [ "$(cat "$T/rc")" = 0 ] \
  && [ "$counts" = "1 1 1" ] && jq -e '.run == 3 and .of == 3 and .over == null' "$T/fc.json" > /dev/null \
  || no "the engine's file loop did not run each listed file once, counted once: '$got', exit $(cat "$T/rc"), progress $(cat "$T/fc.json" 2>/dev/null): $(cat "$T/fc.out")"

# Issue 422: the checks run once a tree in a test step. Bug: each one-file run of a step ran the map check, the test
# lint and shellcheck again on the same tree, so a 50-file card ran them 50 times. A stub shellcheck counts its calls
# and finds a warning on x.sh's changed line 2: three runs of one tree (one log folder) call it once, and each prints
# the warning and fails, the later two from the kept result; a run after the tree changes calls it again.
mkdir -p "$T/bin"
printf '%s\n' '#!/usr/bin/env bash' "echo call >> '$T/sc.calls'" 'echo "conveyor/x.sh:2:1: warning: stub [SC2154]"' > "$T/bin/shellcheck"
chmod +x "$T/bin/shellcheck"; rm -f "$T/sc.calls"
calls() { wc -l < "$T/sc.calls" 2>/dev/null | tr -d ' '; }
for f in hooks/h.test.sh conveyor/tests/a.test.sh "$B"; do
  got=$(PATH=$T/bin:$PATH one tree "$f")
  [ "$(calls)" = 1 ] && [ "$(cat "$T/rc")" = 1 ] && grep -q '^conveyor/x.sh:2:1: warning: stub' "$T/out" && [ "${got%%:*}" = "$f" ] \
    || no "one tree's one-file run of $f did not run its file and report the one shellcheck run's failure: shellcheck ran $(calls) time(s), exit $(cat "$T/rc"), ran '$got': $(cat "$T/out")"
done
echo three >> "$R/conveyor/x.sh"
PATH=$T/bin:$PATH one tree hooks/h.test.sh > /dev/null
[ "$(calls)" = 2 ] && [ "$(cat "$T/rc")" = 1 ] || no "a changed tree's one-file run did not run the checks again: shellcheck ran $(calls) time(s), exit $(cat "$T/rc"): $(cat "$T/out")"

# Issue 436: `--checks` is the pack's test.checkCommand: the loop runs it through its own treecheck()
# (conveyor/lib/donewhen.sh) and puts the result in a test step's log folder (checkskept()). Bugs: `--checks` runs a
# test file too, or passes on a warning; the loop's key of a tree is not this script's, so each one-file run of the
# step ran the checks again. The loop's own functions run it here on a new tree (x.sh changed again): shellcheck runs
# once, the run fails with the warning and runs no test file, and a one-file run given that folder reuses the result.
echo four >> "$R/conveyor/x.sh"; rm -f "$R/ran"
# shellcheck disable=SC2034 # STATE is read by the sourced lib/testrun.sh
got=$( (STATE=$T/cards.jsonl; . "$ROOT/conveyor/lib/testrun.sh" || exit 3
  packget() { printf -v "$2" '%s' 'bash .conveyor/test-changed.sh --checks'; }
  PATH=$T/bin:$PATH treecheck "$R"; echo "exit $?"; mkdir -p "$R.testlog" && checkskept "$R") 2>&1)
[ "$(calls)" = 3 ] && [ "${got##*$'\n'}" = "exit 1" ] && grep -q '^conveyor/x.sh:2:1: warning: stub' <<<"$got" && [ ! -e "$R/ran" ] \
  || no "the loop's run of --checks did not run the checks alone once and fail with the warning: shellcheck ran $(calls) time(s), ran '$(cat "$R/ran" 2>/dev/null)': $got"
rm -rf "$T/kept"; mv "$R.testlog" "$T/kept"
PATH=$T/bin:$PATH one kept hooks/h.test.sh > /dev/null
[ "$(calls)" = 3 ] && [ "$(cat "$T/rc")" = 1 ] && grep -q 'their result is kept' "$T/out" && grep -q '^conveyor/x.sh:2:1: warning: stub' "$T/out" \
  || no "a one-file run of the tree the loop checked ran the checks again, or lost their failure: shellcheck ran $(calls) time(s), exit $(cat "$T/rc"): $(cat "$T/out")"

# Issue 786: treekey() copied the index with a new time, so git trusted the stat of a file staged in the second the
# index was written, and a same-size rewrite in that second kept the old key: the run reused the kept result of the
# tree before a fix. x.sh is written and staged as the kept tree has it and rewritten, same size, in one second (up to
# three tries).
for ((i = 0; i < 3; i++)); do
  until [ "${EPOCHREALTIME: -6}" -lt 300000 ]; do sleep 0.05; done # sleep: the clock must reach the start of a second
  s=${EPOCHREALTIME%%[.,]*}
  if ! { printf 'one\ntwo\nthree\nfour\n' > "$R/conveyor/x.sh" && git -C "$R" add conveyor/x.sh \
    && printf 'one\ntwo\nthree\nfive\n' > "$R/conveyor/x.sh"; }; then no "the rewrite of x.sh"; fi
  [ "${EPOCHREALTIME%%[.,]*}" != "$s" ] || break
done
until [ "${EPOCHREALTIME%%[.,]*}" != "$s" ]; do sleep 0.05; done # sleep: the second the index was written must end
PATH=$T/bin:$PATH one kept hooks/h.test.sh > /dev/null
[ "$(calls)" = 4 ] && [ "$(cat "$T/rc")" = 1 ] \
  || no "a one-file run after a same-second, same-size rewrite reused the kept checks of the tree before it: shellcheck ran $(calls) time(s), exit $(cat "$T/rc"): $(cat "$T/out")"

[ $fails = 0 ] && echo "ok - test-changed runs one given test file alone" || exit 1
