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
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILES BASH_ENV CONVEYOR_TEST_RERUN CONVEYOR_TEST_SLOT CONVEYOR_TEST_SLOTS CONVEYOR_TEST_POOL
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, a map of three areas (a: x.sh and a.test.sh's two cases; b: y.sh and b.test.sh's
# one; c: z.sh and c.test.sh's one, which no change here selects, so a and b are not every case file), a hooks test,
# a Board test and a shell test of conveyor/lib/ that no change selects, and a runner stub; each notes its run in
# $R/ran as `<the file it runs as>:<its cases>`. The change touches x.sh and y.sh: both areas.
B=.claude/scripts/__tests__/w.test.py
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests" "$R/hooks" "$R/${B%/*}"
cp "$HERE/test-changed.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$R/.conveyor/"
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
printf '%s\n' 'echo "hooks/h.test.sh:ALL" >> "$(dirname "$0")/../ran"' > "$R/hooks/h.test.sh"
# A shell test file outside conveyor/tests/ that selects its cases as the runner does; it notes the cases it runs.
mkdir -p "$R/conveyor/lib"
printf '%s\n' 'ALL="sone stwo"' 'SEL=${CONVEYOR_SHELL_TEST_CASE:-$ALL}; SEL=${SEL//,/ }' \
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
  rm -f "$R/ran"; mkdir -p "$T/$1"
  (cd "$R" && env CONVEYOR_TEST_LOG="$T/$1" CONVEYOR_TEST_FILES=$'conveyor/tests/a.test.sh\nconveyor/tests/b.test.sh\n'"$2" CONVEYOR_TEST_CASES="${3:-}" \
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
# names of it runs alone (stwo, not sone).
got=$(one shell conveyor/lib/s.test.sh $'conveyor/lib/s.test.sh\tstwo')
[ "$got" = "conveyor/lib/s.test.sh:stwo" ] && [ "$(cat "$T/rc")" = 0 ] \
  || no "the one-file mode did not run only the case the engine named of a shell test file: '$got', exit $(cat "$T/rc"): $(cat "$T/out")"

# A test file outside the engine (the hooks'), which the change does not select: it runs whole, and no case file runs.
got=$(one hooks hooks/h.test.sh)
[ "$got" = "hooks/h.test.sh:ALL" ] && [ "$(cat "$T/rc")" = 0 ] && grep -qxF -- '-- ok hooks/h.test.sh' "$T/hooks/test-changed.log" \
  || no "the one-file mode given a hooks test did not run it alone: '$got', exit $(cat "$T/rc"): $(cat "$T/out")"

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
  (cd "$R" && env CONVEYOR_TEST_LOG="$T/fc" CONVEYOR_TEST_FILES=$'conveyor/tests/a.test.sh\nconveyor/tests/b.test.sh\n'"$B" bash "$T/fc.sh") > "$T/fc.out" 2>&1
  echo $? > "$T/rc"; testprogress "$T/fc.out" "$T"/fc/* > "$T/fc.json"
) 2> /dev/null
got=$(LC_ALL=C sort "$R/ran" 2>/dev/null | paste -sd'|' -)
counts=$(sed -n 's/^TESTRUN files=\([0-9]*\) .*/\1/p' "$T/fc.out" | paste -sd' ' -)
[ "$got" = "$B:ALL|conveyor/tests/a.test.sh:aone atwo|conveyor/tests/b.test.sh:bone" ] && [ "$(cat "$T/rc")" = 0 ] \
  && [ "$counts" = "1 1 1" ] && jq -e '.run == 3 and .of == 3 and .over == null' "$T/fc.json" > /dev/null \
  || no "the engine's file loop did not run each listed file once, counted once: '$got', exit $(cat "$T/rc"), progress $(cat "$T/fc.json" 2>/dev/null): $(cat "$T/fc.out")"

[ $fails = 0 ] && echo "ok - test-changed runs one given test file alone" || exit 1
