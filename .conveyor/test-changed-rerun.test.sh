#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh's runs again of a change (the loop's rerun, main, fix and changed lines), the why each run logs,
# the areas a check refuses (an "all" area with no why, a case file no area lists), the function-level selection
# and the test files .conveyor/test-links.json links to a changed file; on a scratch map.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
# The loop's test step sets CONVEYOR_TEST_FILELIST (the file of the card's changed test files) and CONVEYOR_TEST_RERUN: left set,
# every scratch run below would select the card's files as well as its own.
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILELIST CONVEYOR_TEST_RERUN
# The checks are in parts (p_<name>) that run side by side, each in a scratch folder of its own (T, part below): each
# says ok or not ok, and the lines are numbered once every part has ended, in the order the parts started.
ok() { echo "ok - $1"; }
no() { echo "not ok - $1"; }

# A scratch repo: the real script, a map of two areas and a core, case files a and b, and a runner stub that
# records which cases it was asked for (ALL when none was named). Each part starts from its own copy of it, as
# committed ($T/r, its map also in $T/map, read as one object: test-changed.sh --map).
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
# The test lint and the browser check, which every run starts, are empty here: no part checks them, and each run of
# the real ones is time paid ~100 times a file run (test-lint.test.sh checks that a run runs the lint).
cp "$HERE/test-changed.sh" "$HERE/funcs.awk" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$R/.conveyor/"; : > "$R/.conveyor/test-lint.sh"; : > "$R/.conveyor/no-browser-tests.sh"; : > "$R/.conveyor/no-records-split.sh"
cat > "$R/.conveyor/engine-areas.json" <<'EOF'
{"outside": "conveyor/README.md"}
{"area": "core", "file": "conveyor/core.sh"}
{"area": "core", "tests": "all"}
{"area": "a", "file": "conveyor/x.sh"}
{"area": "a", "test": "a.test.sh"}
{"area": "b", "file": "conveyor/y.jq"}
{"area": "b", "test": "b.test.sh"}
EOF
# A map read as one object (test-changed.sh --map), written back one fact a line.
lines() {
  jq -c '(.outside[] | {outside: .}), (.areas | to_entries[] | .key as $a | .value | (.files[] | {area: $a, file: .}),
    (.tests | if . == "all" then {area: $a, tests: "all"} else (. // [])[] | {area: $a, test: .} end), (.why // empty | {area: $a, why: .}))'
}
(cd "$R" && bash .conveyor/test-changed.sh --map) > "$T/scratch.json" || { echo "not ok - the scratch map could not be read"; exit 1; }
printf 't_aone() {\n  :\n}\nt_atwo() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"
printf 't_bone() {\n  :\n}\n' > "$R/conveyor/tests/b.test.sh"
echo 'echo "${CONVEYOR_SHELL_TEST_CASE:-ALL}" >> "${0%/*}/../ran"' > "$R/conveyor/conveyor.test.sh"
echo one > "$R/conveyor/core.sh"; echo one > "$R/conveyor/x.sh"; echo one > "$R/conveyor/y.jq"; echo doc > "$R/conveyor/README.md"
# The runner stub's run of every case file is a meta-runner's (issue 584): a card mode in the pack lets it run whole
# here, so the parts below see which runs are whole.
echo '{"test": {"files": {"conveyor/conveyor.test.sh": {"cardMode": "CONVEYOR_RUNNER_STUB=1"}}}}' > "$R/.conveyor/project.json"
echo ran > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
# ran: the cases the runner stub was asked for, its runs' lines sorted and joined (each engine case file runs on its
# own, side by side, so a selection of two files is two runs, in either order).
ranlines() { LC_ALL=C sort "$1" 2>/dev/null | awk '{ gsub(/ +/, " "); sub(/ $/, ""); printf "%s%s", (NR > 1 ? " " : ""), $0 } END { print "" }'; }
ran() { rm -f "$R/ran"; (cd "$R" && bash .conveyor/test-changed.sh) > "$T/out" 2>&1; echo $? > "$T/rc"; ranlines "$R/ran"; }
mran2() { ran | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//'; }
sorted() { tr ' ' '\n' | grep . | sort | tr '\n' ' '; }
# part <name>: p_<name> in the background, in $T/<name> with its own copy of the scratch repo (R); its output in
# $T/<name>.res, and $T/<name>.end once it ran to its end.
PARTS=()
part() {
  PARTS+=("$1")
  (B=$T; T=$T/$1; mkdir "$T" && cp -a "$B/r" "$T/r" && cp "$B/scratch.json" "$T/map" || exit 1; R=$T/r
    # A name with no p_ function (a typo in the list) fails, rather than skipping its cases with no result.
    declare -F "p_$1" > /dev/null || { echo "not ok - no part p_$1"; exit 1; }
    "p_$1"; : > "$B/$1.end") > "$T/$1.res" 2>&1 &
}

# The loop's run again of the same change (CONVEYOR_TEST_RERUN): a file that passed is not run, and the runner runs only
# its cases that failed (a name that is no case is left out), so one flaky case costs one case, not the selection.
# wchange: the change these parts run again, a test file outside the engine (lib/w.test.sh) and area a's x.sh.
wchange() { mkdir -p "$R/lib"; echo 'echo w >> "$(dirname "$0")/../ran"' > "$R/lib/w.test.sh"; echo two >> "$R/conveyor/x.sh"; }
p_rerun() {
  wchange
  printf 'change\tabc\npass\tlib/w.test.sh\nfail\tconveyor/conveyor.test.sh\tatwo\nfail\tconveyor/conveyor.test.sh\tnosuch\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran)
  [ "$got" = atwo ] && [ "$(cat "$T/rc")" = 0 ] && ok "a run again runs only the runner's failed case and no file that passed" || no "run again: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  got=$(CONVEYOR_TEST_LOG=$T/log ran | tr '\n' ' ')
  [ "$got" = "aone atwo w " ] || [ "$got" = "w aone atwo " ] && ok "without it, the whole selection runs" || no "no run again: ran '$got': $(cat "$T/out")"
}
# Bug it catches: the loop runs a card's failing cases on main (mainred.sh verdicts()), a clean tree where no change
# selects them; the runner ran nothing, so a case broken on main always read as passing there and the card went to a
# fix session that could not repair main. The list's failed cases run: of the runner, those alone; a test file named
# with no failed case of it, or a name that is no case, runs nothing.
p_mainrun() {
  mkdir -p "$R/lib"; echo 'echo w >> "$(dirname "$0")/../ran"' > "$R/lib/w.test.sh"; echo 'echo v >> "$(dirname "$0")/../ran"' > "$R/lib/v.test.sh"
  git -C "$R" add -A && git -C "$R" commit -qm tests
  printf 'pass\tlib/v.test.sh\nfail\tconveyor/conveyor.test.sh\tatwo\nfail\tlib/w.test.sh\tsome case\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun mran2)
  [ "$got" = "atwo w" ] && ok "on a clean tree, the list's failed cases run: the runner's case alone, and the test file" || no "clean tree: ran '$got': $(cat "$T/out")"
  printf 'fail\tconveyor/conveyor.test.sh\tnosuch\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran)
  [ -z "$got" ] && ok "on a clean tree, a failed name that is no case of the runner runs nothing, not the whole engine test" || no "clean tree, no such case: ran '$got': $(cat "$T/out")"
}
# Issue 517: a run of one engine case file by hand (conveyor.sh testaction run: a `fail` line naming the file and no
# case, on main's clean tree) ran the file by itself, not its cases through the runner, which times it as a card's run
# does. It runs that file's cases alone through the runner.
p_handrun() {
  printf 'fail\tconveyor/tests/a.test.sh\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran)
  [ "$got" = "aone atwo" ] && ok "a fail line naming an engine case file runs its cases alone, through the runner" || no "one case file by hand: ran '$got': $(cat "$T/out")"
}
# Bug it catches: a file that failed on a card naming no case (a shell test's `FAIL: ...`, or a timeout) was given to
# the run on main with no line, so on main's clean tree nothing selected it: it never ran there, and a file broken on
# main read as the card's to fix. A `fail` line naming no case runs its file whole, of the runner every case, beside a
# runner's case named by another line.
p_mainwhole() {
  mkdir -p "$R/lib"; echo 'echo w >> "$(dirname "$0")/../ran"' > "$R/lib/w.test.sh"; git -C "$R" add -A && git -C "$R" commit -qm tests
  printf 'fail\tconveyor/conveyor.test.sh\nfail\tconveyor/conveyor.test.sh\tatwo\nfail\tlib/w.test.sh\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun mran2)
  [ "$got" = "ALL w" ] && ok "on a clean tree, a failed file naming no case runs whole: the runner and a test file" || no "clean tree, no case: ran '$got': $(cat "$T/out")"
}
# Bug it catches: a node (Board) test file ran whole whatever the list named of its cases, so a flaky case the loop
# keeps off card runs (an `ok` line: conveyor.sh flakyoff()) still ran on them, and the run on main of a card's failing
# case ran the whole file. A real node test file: its `ok` cases are left out, and on a clean tree its `fail` cases run
# alone; a name with regex characters in it is matched whole.
p_nodecases() {
  local n=board/__tests__/n.test.mjs
  mkdir -p "$R/board/__tests__"
  printf "import test from 'node:test';\nimport { appendFileSync } from 'node:fs';\nconst r = (s) => appendFileSync(new URL('../../ran', import.meta.url), s + '\\\\n');\ntest('one', () => r('one'));\ntest('two (x) [y]', () => r('two'));\ntest('three', () => r('three'));\n" > "$R/$n"
  git -C "$R" add -A && git -C "$R" commit -qm node
  printf 'fail\t%s\ttwo (x) [y]\n' "$n" > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | tr '\n' ' ')
  [ "$got" = "two " ] && [ "$(cat "$T/rc")" = 0 ] && ok "on a clean tree, a node test file runs only the list's failed case" || no "node, clean tree: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  echo 'void 0;' >> "$R/$n"
  printf 'ok\t%s\tone\nok\t%s\ttwo (x) [y]\n' "$n" "$n" > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | tr '\n' ' ')
  [ "$got" = "three " ] && [ "$(cat "$T/rc")" = 0 ] && ok "a node test file a change selects leaves out the cases the list's ok lines name" || no "node, ok cases: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  # Issue 469: a file listed as passed has no `ok` line for its flaky case; its `off` line keeps the case off.
  printf 'pass\t%s\noff\t%s\tone\nchanged\t%s\n' "$n" "$n" "$n" > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "three two " ] && [ "$(cat "$T/rc")" = 0 ] && ok "a node test file a change selects leaves out the cases the list's off lines name" || no "node, off cases: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
# Bug it catches (issue 469): a case the loop keeps off card runs as flaky (conveyor.sh flakyoff()) ran again once a
# fix's `changed` line selected its area: the fresh cases were added back after the `ok` lines were taken out. Its `off`
# line keeps it off whatever selects it: a changed file of its area, or of an "all" area (the whole runner otherwise).
p_flakyoff() {
  wchange
  printf 'change\tabc\npass\tlib/w.test.sh\nok\tconveyor/conveyor.test.sh\taone\noff\tconveyor/conveyor.test.sh\taone\nfail\tconveyor/conveyor.test.sh\tatwo\nchanged\tconveyor/x.sh\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "atwo " ] && ok "a fix that changed a flaky case's area does not run the case kept off" || no "off case, fix of x.sh: ran '$got': $(cat "$T/out")"
  printf 'change\tabc\npass\tlib/w.test.sh\npass\tconveyor/conveyor.test.sh\noff\tconveyor/conveyor.test.sh\taone\nchanged\tconveyor/core.sh\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "atwo bone " ] && ok "a fix that changed an \"all\" area's file runs every case but the one kept off" || no "off case, fix of core.sh: ran '$got': $(cat "$T/out")"
}
# Issue 457: a test file the loop keeps off whole is kept off card runs (conveyor.sh cacheoff():
# a `pass` and an `off` line naming the file, no case). Bug it catches: the file ran on a card's run all the same, as
# a changed file (or, of an engine case file, a change to its area or an "all" area) selected it again.
p_slowoff() {
  wchange
  printf 'pass\tlib/w.test.sh\noff\tlib/w.test.sh\npass\tconveyor/tests/a.test.sh\noff\tconveyor/tests/a.test.sh\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran)
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 0 ] && ok "a first card run keeps a slow test file and a slow engine case file off" || no "slow files off, first run: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  printf 'change\tabc\npass\tlib/w.test.sh\noff\tlib/w.test.sh\npass\tconveyor/tests/a.test.sh\noff\tconveyor/tests/a.test.sh\nchanged\tlib/w.test.sh\nchanged\tconveyor/core.sh\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "bone " ] && ok "a fix that changed a slow file and an \"all\" area's file runs every case but the slow file's" || no "slow files off, fix of core.sh: ran '$got': $(cat "$T/out")"
}
# A runner killed part-way: the cases it printed `ok` for are not run again, and those it never finished are, even
# beside a case that failed.
p_killed() {
  wchange
  printf 'change\tabc\npass\tlib/w.test.sh\nok\tconveyor/conveyor.test.sh\taone\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran)
  [ "$got" = atwo ] && ok "a run again after a killed runner runs only its cases that had not passed" || no "killed runner: ran '$got': $(cat "$T/out")"
  echo two >> "$R/conveyor/core.sh"
  printf 'change\tabc\npass\tlib/w.test.sh\nok\tconveyor/conveyor.test.sh\taone\nfail\tconveyor/conveyor.test.sh\tatwo\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | tr ' ' '\n' | sort | tr '\n' ' ')
  [ "$got" = "atwo bone " ] && ok "a run again of the whole runner, cut after a failed case, runs the failed and the unfinished cases" || no "killed whole runner: ran '$got': $(cat "$T/out")"
}
# The run after a fix session that changed the change (the loop's `changed` lines): what had not passed, and the tests
# of the files the session changed, even those that passed; every other case that passed is kept, not run (#325 had
# one failing case and would have run its whole selection again). Here the change selects aone, atwo and w; atwo
# failed and w passed.
p_fixengine() {
  wchange
  printf 'change\tabc\npass\tlib/w.test.sh\nfail\tconveyor/conveyor.test.sh\tatwo\nchanged\tconveyor/y.jq\n' > "$T/rerun"
  rm -rf "$T/flog"; mkdir "$T/flog"; got=$(CONVEYOR_TEST_LOG=$T/flog CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "atwo bone " ] && ok "after a fix of an engine file, the failed case and that file's area's cases run, and no other" || no "fix of y.jq: ran '$got': $(cat "$T/out")"
  # Its log says how many cases ran and how many passes were kept: aone and w's one.
  [ "$(grep -E '^TESTRUN (files|cases|kept)=' "$T/flog/test-changed.log" | sed 's/ of=.*//' | tr '\n' '|')" = "TESTRUN files=1|TESTRUN cases=2|TESTRUN kept=2|" ] \
    && ok "the run after a fix says the cases it ran and the passes it kept" || no "kept count: $(cat "$T/flog/test-changed.log")"
  # And names each case it runs of the runner: a run whose time runs out loses the kept passes of these cases alone, not
  # of the runner's cases it did not run (testlist.sh rerunlist()).
  [ "$(sed -n 's/^TESTRUN case\t//p' "$T/flog/test-changed.log" | sort | tr '\t\n' ':|')" = "conveyor/conveyor.test.sh:atwo|conveyor/conveyor.test.sh:bone|" ] \
    && ok "the run after a fix names the runner's cases it runs" || no "case lines: $(cat "$T/flog/test-changed.log")"
  printf 'change\tabc\npass\tlib/w.test.sh\nfail\tconveyor/conveyor.test.sh\tatwo\nchanged\tconveyor/core.sh\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran)
  [ "$got" = ALL ] && ok "after a fix that also changed a file of an \"all\" area, the whole engine test runs" || no "fix of core.sh: ran '$got': $(cat "$T/out")"
}
p_fixtest() {
  wchange; printf 't_bone() {\n  true\n}\n' > "$R/conveyor/tests/b.test.sh"
  printf 'change\tabc\npass\tlib/w.test.sh\nfail\tconveyor/conveyor.test.sh\tatwo\nchanged\tconveyor/tests/b.test.sh\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "atwo bone " ] && ok "after a fix of a case file only, the failed case and that file's cases run" || no "fix of b.test.sh: ran '$got': $(cat "$T/out")"
  printf 'change\tabc\npass\tlib/w.test.sh\nfail\tconveyor/conveyor.test.sh\tatwo\nchanged\tlib/w.test.sh\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "atwo w " ] && ok "after a fix of a test file that had passed, it runs again beside the failed case" || no "fix of w.test.sh: ran '$got': $(cat "$T/out")"
}
# The run after the change moved onto a newer main (the loop's `main` lines, issue 460: a card ran its whole selection
# again though main's new commits touched almost nothing its tests use): the tests main's files select run, only where
# the change's own selection holds them; the rest stay kept. Here the change selects aone, atwo and w, all passed.
p_mainmoved() {
  wchange
  printf 'change\tabc\npass\tlib/w.test.sh\npass\tconveyor/conveyor.test.sh\nmain\tconveyor/y.jq\nmain\tlib/w.test.sh\n' > "$T/rerun"
  rm -rf "$T/mlog"; mkdir "$T/mlog"; got=$(CONVEYOR_TEST_LOG=$T/mlog CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "w " ] && ok "after main moved, a test main's file selects runs, and one the change does not select (bone) does not" \
    || no "main changed y.jq and w.test.sh: ran '$got': $(cat "$T/out")"
  [ "$(sed -n 's/^TESTRUN why\t//p' "$T/mlog/test-changed.log" | tr '\t\n' ':|')" = "lib/w.test.sh:main changed lib/w.test.sh|" ] \
    && ok "its log says why the file ran" || no "why lines: $(cat "$T/mlog/test-changed.log")"
  # A file of an "all" area main changed runs the runner's cases the change selects, not the whole engine test; a case
  # that failed runs beside them, and says it did not pass.
  printf 'change\tabc\npass\tlib/w.test.sh\nok\tconveyor/conveyor.test.sh\taone\nfail\tconveyor/conveyor.test.sh\tatwo\nmain\tconveyor/core.sh\n' > "$T/rerun"
  rm -rf "$T/mlog"; mkdir "$T/mlog"; got=$(CONVEYOR_TEST_LOG=$T/mlog CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "aone atwo " ] && ok "after main changed a file of an \"all\" area, only the runner's cases the change selects run" \
    || no "main changed core.sh: ran '$got': $(cat "$T/out")"
  [ "$(sed -n 's/^TESTRUN why\t//p' "$T/mlog/test-changed.log" | sort | tr '\t\n' ':|')" = "conveyor/tests/a.test.sh:did not pass|conveyor/tests/a.test.sh:main changed conveyor/core.sh|" ] \
    && ok "its log gives each reason a file ran, under the case file of those cases" || no "why lines: $(cat "$T/mlog/test-changed.log")"
  # Main changed the map and the list has no `from` line: the map before main's change cannot be read, so which case
  # files it named anew cannot be told, and the runner's cases the change selects run though they passed.
  printf 'change\tabc\npass\tlib/w.test.sh\npass\tconveyor/conveyor.test.sh\nmain\t.conveyor/engine-areas.json\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "aone atwo " ] && ok "after main changed the map, the runner's cases the change selects run again" || no "main changed the map: ran '$got': $(cat "$T/out")"
}
p_fixpassed() {
  wchange
  # The runner had passed whole; the fix changed x.sh: only area a's cases run, not the whole engine test.
  printf 'change\tabc\npass\tlib/w.test.sh\npass\tconveyor/conveyor.test.sh\nchanged\tconveyor/x.sh\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "aone atwo " ] && ok "after a fix, a runner that had passed runs only the changed file's cases" || no "fix of x.sh, runner passed: ran '$got': $(cat "$T/out")"
  # With y.jq changed too (bone in the selection), that run failed aone and passed atwo: the runner is still listed as
  # passed (bone, which did not run, stays kept) beside its failed case. Its run again runs aone alone: were the `pass`
  # line read as before, aone would not run; were atwo's `ok` line read without it, bone would run again.
  echo two >> "$R/conveyor/y.jq"
  printf 'change\tabc\npass\tlib/w.test.sh\npass\tconveyor/conveyor.test.sh\nok\tconveyor/conveyor.test.sh\tatwo\nfail\tconveyor/conveyor.test.sh\taone\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "aone " ] && ok "a runner listed as passed beside a failed case runs that case alone" || no "runner passed and failed: ran '$got': $(cat "$T/out")"
}

p_core() {
  echo two >> "$R/conveyor/core.sh"
  got=$(ran)
  [ "$got" = ALL ] && ok "a session runs every case for a core change" || no "session, core changed: ran '$got': $(cat "$T/out")"
  # Issue 517: the test step's first run said neither why the runner ran nor that it ran every case file. Its log
  # names the changed file and the "all" area that selected it, and says it ran the whole engine test.
  mkdir "$T/clog"; got=$(CONVEYOR_TEST_LOG=$T/clog ran)
  [ "$got" = ALL ] && [ "$(sed -n 's/^TESTRUN why\t//p' "$T/clog/test-changed.log" | sort | tr '\t\n' ':|')" = "conveyor/conveyor.test.sh:the area core runs all engine tests|conveyor/conveyor.test.sh:the card changed conveyor/core.sh|" ] \
    && grep -qx 'TESTRUN whole-suite' "$T/clog/test-changed.log" && ok "a first run's log says why the runner ran whole, naming the \"all\" area, and that it ran every case file" \
    || no "core changed, first run's log: ran '$got': $(cat "$T/clog/test-changed.log")"
  # A first run whose list holds only a case the loop keeps off as flaky (flakyoff(): `ok` and `off` lines) was read
  # as a run again: its log said "did not pass" alone, with neither the changed file nor the area.
  mkdir "$T/flog"; printf 'ok\tconveyor/conveyor.test.sh\taone\noff\tconveyor/conveyor.test.sh\taone\n' > "$T/frerun"
  got=$(CONVEYOR_TEST_LOG=$T/flog CONVEYOR_TEST_RERUN=$T/frerun ran | sorted)
  # Issue 546: that run still runs every case file (a.test.sh by atwo), but its log did not say so (`TESTRUN whole-suite`).
  [ "$got" = "atwo bone " ] && [ "$(sed -n 's/^TESTRUN why\t//p' "$T/flog/test-changed.log" | sort | tr '\t\n' ':|')" = "conveyor/conveyor.test.sh:the area core runs all engine tests|conveyor/conveyor.test.sh:the card changed conveyor/core.sh|" ] \
    && grep -qx 'TESTRUN whole-suite' "$T/flog/test-changed.log" \
    && ok "a first run with a flaky case kept off says why the runner ran, naming the changed file and the \"all\" area, and that it ran every case file" \
    || no "core changed, flaky case off, first run's log: ran '$got': $(cat "$T/flog/test-changed.log")"
  # A case file kept off whole (cacheoff(): an `off` line with no case) does not run: that log does not say every case file ran.
  mkdir "$T/slog"; printf 'off\tconveyor/tests/b.test.sh\n' > "$T/srerun"
  got=$(CONVEYOR_TEST_LOG=$T/slog CONVEYOR_TEST_RERUN=$T/srerun ran | sorted)
  [ "$got" = "aone atwo " ] && ! grep -q 'TESTRUN whole-suite' "$T/slog/test-changed.log" \
    && ok "a first run with a case file kept off whole does not say it ran every case file" \
    || no "core changed, b.test.sh off, first run's log: ran '$got': $(cat "$T/slog/test-changed.log")"
}
# Issue 517: a first run's log gave no why. A change to one area's file and a new test file: each file it runs has the
# changed file that selected it as its reason, no area's name, and the log does not say every case file ran.
p_firstwhy() {
  wchange; mkdir "$T/wlog"; got=$(CONVEYOR_TEST_LOG=$T/wlog ran | sorted)
  [ "$got" = "aone atwo w " ] && [ "$(sed -n 's/^TESTRUN why\t//p' "$T/wlog/test-changed.log" | sort | tr '\t\n' ':|')" = "conveyor/tests/a.test.sh:the card changed conveyor/x.sh|lib/w.test.sh:the card changed lib/w.test.sh|" ] \
    && ! grep -q 'TESTRUN whole-suite' "$T/wlog/test-changed.log" && ok "a first run's log says why each file ran, and no whole engine test for one area's change" \
    || no "x.sh and w.test.sh changed, first run's log: ran '$got': $(cat "$T/wlog/test-changed.log")"
}

p_noarea() {
  echo new > "$R/conveyor/z.sh"
  got=$(ran)
  [ "$(cat "$T/rc")" = 1 ] && grep -q '^conveyor/z.sh: an engine source file in no area' "$T/out" \
    && ok "an engine file in no area fails the map check" || no "z.sh in no area: exit $(cat "$T/rc"): $(cat "$T/out")"
  (cd "$R" && bash .conveyor/test-changed.sh --check > /dev/null) && no "--check passed with z.sh in no area" || ok "--check fails with z.sh in no area"
  rm "$R/conveyor/z.sh"
  (cd "$R" && bash .conveyor/test-changed.sh --check > /dev/null) && ok "--check passes once every file is in an area" || no "--check failed on a complete map"
}

# An engine file left in an "all" area with no why runs every case on each change to it (a 12-line change to one
# engine file ran all 205 cases): the check refuses it, so a new engine file names its case files when it is added.
p_why() {
  echo one > "$R/conveyor/lib.sh"
  jq '.areas.core.files += ["conveyor/lib.sh"]' "$T/map" | lines > "$R/.conveyor/engine-areas.json"
  (cd "$R" && bash .conveyor/test-changed.sh --check) > "$T/out" 2>&1 && ok "a conveyor/ file outside lib/ in an \"all\" area with no why passes the check" || no "conveyor/lib.sh in core, no why: $(cat "$T/out")"
  rm "$R/conveyor/lib.sh"; mkdir -p "$R/conveyor/lib"; echo one > "$R/conveyor/lib/w.sh"
  jq '.areas.core.files += ["conveyor/lib/w.sh"]' "$T/map" | lines > "$R/.conveyor/engine-areas.json"
  (cd "$R" && bash .conveyor/test-changed.sh --check) > "$T/out" 2>&1
  [ $? = 1 ] && grep -q '^conveyor/lib/w.sh: in core, an area of .* whose tests are "all" with no why' "$T/out" \
    && ok "the check fails for a conveyor/lib/ file in an \"all\" area with no why" || no "lib/w.sh in core, no why: $(cat "$T/out")"
  jq '.areas.core.files += ["conveyor/lib/w.sh"] | .areas.core.why = "every case runs through it"' "$T/map" | lines > "$R/.conveyor/engine-areas.json"
  (cd "$R" && bash .conveyor/test-changed.sh --check) > "$T/out" 2>&1 && ok "a conveyor/lib/ file in an \"all\" area that says why passes the check" || no "lib/w.sh in core with a why: $(cat "$T/out")"
}

# A case file no area lists runs on no engine file's change, only when it is itself changed: the check refuses it.
p_unlisted() {
  printf 't_cone() {\n  :\n}\n' > "$R/conveyor/tests/c.test.sh"
  (cd "$R" && bash .conveyor/test-changed.sh --check) > "$T/out" 2>&1
  [ $? = 1 ] && grep -q '^conveyor/tests/c.test.sh: a case file no area of .* names' "$T/out" \
    && ok "the check fails for a case file no area lists" || no "c.test.sh in no area: $(cat "$T/out")"
}

# Issue 527. Bug: a change to one engine function ran its whole area, and one to one function of dashboard.sh all of
# dashboard.test.sh (55 CPU s). D2: a change to a function the coverage map holds runs only the cases it lists for it;
# D4: of dashboard.sh, only the parts of dashboard.test.sh it lists. D3: a function the map does not hold, or lists no
# case for, one changed since the trace, or a line outside the functions, runs by the area rule, as before. The map
# check says how old the map is.
p_cover() {
  local d=.claude/scripts/__tests__/dashboard.test.sh
  (cd "$R" && bash .conveyor/test-changed.sh --check) | grep -q '^coverage map: none' && ok "the map check says there is no coverage map" || no "no coverage map: $(cd "$R" && bash .conveyor/test-changed.sh --check)"
  printf 'xone() {\n  echo one\n}\nxtwo() {\n  echo two\n}\n' > "$R/conveyor/x.sh"
  mkdir -p "$R/.claude/scripts/__tests__"; printf 'dfa() {\n  echo a\n}\ndfb() {\n  echo b\n}\n' > "$R/.claude/scripts/dashboard.sh"
  printf '%s\n' 'echo "dash:${CONVEYOR_SHELL_TEST_CASE:-ALL}" >> "$(dirname "$0")/../../../ran"' 'started() { :; }' \
    '( :' ') & started contract' '( :' ') & started history' > "$R/$d"
  (cd "$R" && { echo '{"traced": "2026-11-01T00:00:00Z"}'
    for f in conveyor/x.sh .claude/scripts/dashboard.sh; do
      bash .conveyor/test-changed.sh --funcs "$f" | jq -cR --arg f "$f" 'split("\t") | {file: $f, fn: .[0], sum: .[1], units: ({xone: [1], dfa: [2]}[.[0]] // [])}'; done
    jq -cn --arg d "$d" '{testfile: 1, path: "conveyor/conveyor.test.sh"}, {testfile: 2, path: $d},
      {unit: 1, testfile: 1, case: "aone"}, {unit: 2, testfile: 2, case: "history"}'; } > .conveyor/coverage.jsonl)
  git -C "$R" add -A && git -C "$R" commit -qm cover
  (cd "$R" && bash .conveyor/test-changed.sh --check) | grep -qE '^coverage map .conveyor/coverage.jsonl: traced 2026-11-01T00:00:00Z, [0-9]+ days ago$' \
    && ok "the map check says when the coverage map was traced and how many days ago" || no "map age: $(cd "$R" && bash .conveyor/test-changed.sh --check)"
  sed 's/echo one/echo uno/' "$R/conveyor/x.sh" > "$T/e" && cat "$T/e" > "$R/conveyor/x.sh"; got=$(ran)
  [ "$got" = aone ] && [ "$(cat "$T/rc")" = 0 ] && ok "D2: a changed function the coverage map holds runs only the case it lists (aone), not its area" \
    || no "xone changed: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  git -C "$R" checkout -q -- conveyor/x.sh
  sed 's/echo a/echo A/' "$R/.claude/scripts/dashboard.sh" > "$T/e" && cat "$T/e" > "$R/.claude/scripts/dashboard.sh"; got=$(ran)
  [ "$got" = dash:history ] && ok "D4: a changed dashboard.sh function runs only the dashboard.test.sh part the map lists" || no "dfa changed: ran '$got': $(cat "$T/out")"
  echo ': changed' >> "$R/$d"; got=$(ran)
  [ "$got" = dash:ALL ] && ok "a dashboard.test.sh the change also selects whole runs whole, not the part" || no "dfa and dashboard.test.sh changed: ran '$got': $(cat "$T/out")"
  git -C "$R" checkout -q -- .claude/scripts/dashboard.sh "$d"
  sed 's/echo b/echo B/' "$R/.claude/scripts/dashboard.sh" > "$T/e" && cat "$T/e" > "$R/.claude/scripts/dashboard.sh"; got=$(ran)
  [ "$got" = dash:ALL ] && ok "a changed dashboard.sh function the map lists no case for runs dashboard.test.sh whole" || no "dfb changed: ran '$got': $(cat "$T/out")"
  git -C "$R" checkout -q -- .claude/scripts/dashboard.sh
  # Bug: the parts of the hooks' tests (a case_on CASES line; the text of a check, lib/case-filter.sh) were not parts,
  # so a change to a hook function ran its tests whole. They run only the parts the map lists, comma-separated.
  local hk=.claude/hooks/__tests__/hk.test.sh bg=.claude/hooks/__tests__/bg.test.sh
  mkdir -p "$R/.claude/hooks/__tests__/lib"; : > "$R/.claude/hooks/__tests__/lib/case-filter.sh"
  printf 'hka() {\n  echo a\n}\nhkb() {\n  echo b\n}\n' > "$R/.claude/hooks/hk.sh"
  printf '%s\n' '# CONVEYOR_SHELL_TEST_CASE' 'CASES=" ha hb hc "' 'echo "hk:${CONVEYOR_SHELL_TEST_CASE:-ALL}" >> "$(dirname "$0")/../../../ran"' > "$R/$hk"
  printf '%s\n' '# CONVEYOR_SHELL_TEST_CASE' '. "$(dirname "${BASH_SOURCE[0]}")/lib/case-filter.sh"' 'echo "bg:${CONVEYOR_SHELL_TEST_CASE:-ALL}" >> "$(dirname "$0")/../../../ran"' \
    'check() { :; }' 'check "the hkb check" x' > "$R/$bg"
  (cd "$R" && bash .conveyor/test-changed.sh --funcs .claude/hooks/hk.sh | jq -cR 'split("\t") | {file: ".claude/hooks/hk.sh", fn: .[0], sum: .[1], units: {hka: [3, 4], hkb: [5]}[.[0]]}'
    jq -cn --arg hk "$hk" --arg bg "$bg" '{testfile: 3, path: $hk}, {testfile: 4, path: $bg}, {unit: 3, testfile: 3, case: "hc"}, {unit: 4, testfile: 3, case: "ha"},
      {unit: 5, testfile: 4, case: "the hkb check"}') >> "$R/.conveyor/coverage.jsonl"
  git -C "$R" add -A && git -C "$R" commit -qm hooks
  sed 's/echo a/echo A/; s/echo b/echo B/' "$R/.claude/hooks/hk.sh" > "$T/e" && cat "$T/e" > "$R/.claude/hooks/hk.sh"; got=$(ran)
  [ "$got" = "bg:the hkb check hk:ha,hc" ] && ok "changed hook functions run only the case_on cases and check texts the map lists" || no "hka and hkb changed: ran '$got': $(cat "$T/out")"
  git -C "$R" checkout -q -- .claude/hooks/hk.sh
  printf 'xthree() {\n  echo three\n}\n' >> "$R/conveyor/x.sh"; got=$(ran)
  [ "$got" = "aone atwo" ] && ok "D3: an added function that no mapped function calls runs its file's area, as before" || no "xthree added: ran '$got': $(cat "$T/out")"
  git -C "$R" checkout -q -- conveyor/x.sh; echo 'echo top' >> "$R/conveyor/x.sh"; got=$(ran)
  [ "$got" = "aone atwo" ] && ok "a changed line outside the functions runs the area" || no "top-level line: ran '$got': $(cat "$T/out")"
  git -C "$R" checkout -q -- conveyor/x.sh
  sed 's/echo one/echo uno/' "$R/conveyor/x.sh" > "$T/e" && cat "$T/e" > "$R/conveyor/x.sh"; git -C "$R" commit -qam since
  sed 's/echo uno/echo eins/' "$R/conveyor/x.sh" > "$T/e" && cat "$T/e" > "$R/conveyor/x.sh"; got=$(ran)
  [ "$got" = aone ] && ok "a function changed since the coverage map was traced runs the cases the map lists for it as traced, not the area" || no "xone changed since the trace: ran '$got': $(cat "$T/out")"
}

# Issue 598. Bug it catches: a change to lib/a.sh broke tests/l.test.sh, which no card changing lib/a.sh selects, so it
# landed and main went red. The link .conveyor/test-links.json keeps (from the landing that broke it) makes a later
# card changing lib/a.sh run tests/l.test.sh, and an engine case file linked so, its cases through the runner; its log
# names each one; a card changing only lib/c.sh runs neither. A link to a deleted test file is dropped without error.
# (Not tests/b.test.sh: the map names b.test.sh, and two files of that name fail the map check, issue 332.)
p_linked() {
  mkdir -p "$R/lib" "$R/tests" "$T/log"
  printf '#!/usr/bin/env bash\n:\n' > "$R/lib/a.sh"; printf '#!/usr/bin/env bash\n:\n' > "$R/lib/c.sh"
  echo 'echo b >> "$(dirname "$0")/../ran"' > "$R/tests/l.test.sh"
  echo '{"lib/a.sh": ["tests/l.test.sh", "tests/gone.test.sh", "conveyor/tests/b.test.sh"]}' > "$R/.conveyor/test-links.json"
  git -C "$R" add -A && git -C "$R" commit -qm links
  echo ': two' >> "$R/lib/a.sh"; got=$(CONVEYOR_TEST_LOG=$T/log ran | sorted)
  [ "$got" = "b bone " ] && [ "$(cat "$T/rc")" = 0 ] && ok "D2, D3: a card changing lib/a.sh runs its linked tests/l.test.sh and engine case file, and a link to a deleted file is dropped" \
    || no "lib/a.sh changed: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  [ "$(grep '^TESTRUN linked' "$T/log/test-changed.log" | sort | tr '\n' '|')" = "TESTRUN linked	conveyor/tests/b.test.sh	lib/a.sh|TESTRUN linked	tests/l.test.sh	lib/a.sh|" ] \
    && ok "D2: the log names each test file a link added and the changed file that linked it" || no "linked log: $(cat "$T/log/test-changed.log" 2>&1)"
  git -C "$R" checkout -q -- lib/a.sh; rm -f "$T/log/test-changed.log"; echo ': two' >> "$R/lib/c.sh"; got=$(CONVEYOR_TEST_LOG=$T/log ran)
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 0 ] && ! grep -q '^TESTRUN linked' "$T/log/test-changed.log" && ok "D2: a card changing only lib/c.sh does not run tests/l.test.sh" \
    || no "lib/c.sh changed: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}

# Bug (#1597): main changed the map, and the run after it ran every case of the runner the change selects, the map's
# own tests and all, though main changed one entry. mainmap: main's commit changes the map (the jq program $2 on
# the scratch map, naming the new file $1) and adds a map test stub; the card's change (wchange) is not committed; the list names main's
# commit as `from` (the HEAD before it) and says the change's runner cases and test files passed. The card's list
# (CONVEYOR_TEST_FILELIST, as the loop gives it) holds only the card's own test file, not the map test stub: bug, the
# stub ran only when the list named it, so a card that changed one other test file never ran the map's own tests.
mainmap() {
  local from; from=$(git -C "$R" rev-parse HEAD)
  echo one > "$R/$1"
  jq "$2" "$T/map" | lines > "$R/.conveyor/engine-areas.json"
  echo 'echo MAPTEST >> "$(dirname "$0")/../ran"' > "$R/.conveyor/test-changed.test.sh"
  git -C "$R" add .conveyor "$1" && git -C "$R" commit -qm "main moves the map"
  wchange
  printf 'change\tabc\nfrom\t%s\npass\tlib/w.test.sh\npass\t.conveyor/test-changed.test.sh\npass\tconveyor/conveyor.test.sh\nmain\t.conveyor/engine-areas.json\n' "$from" > "$T/rerun"
  printf 'lib/w.test.sh\n' > "$T/files"
  CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun CONVEYOR_TEST_FILELIST=$T/files ran | sorted
}
# fileran <file>: the one-file run (--file) the loop gives each file of its list, on mainmap's change and `from`. The
# list is the one the loop keeps of a one-file run of an engine case file that passed (conveyor/lib/testlist.sh,
# rerunlist()): only `pass <case file>`, with no `ok` line of its cases and no runner-wide `pass`. Bug: a `--file` mode
# that skipped the reading of that `pass` as its cases' `ok` lines (test-changed.sh) ran the passed cases again.
fileran() {
  local from; from=$(awk -F'\t' '$1 == "from" {print $2}' "$T/rerun")
  printf 'change\tabc\nfrom\t%s\npass\t%s\nmain\t.conveyor/engine-areas.json\n' "$from" "$1" > "$T/rerun"
  printf '%s\n' "$1" > "$T/files"
  rm -f "$R/ran"
  (cd "$R" && CONVEYOR_TEST_N=1 CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun CONVEYOR_TEST_FILELIST=$T/files \
    bash .conveyor/test-changed.sh --file "$1") > "$T/out" 2>&1
  ranlines "$R/ran" | sorted
}
# Main adds a line for y2.jq (area b) to the map; the card changes x.sh (area a). Only the map's own tests run: the
# cases of area b are not in the card's selection, and area a's entry did not change.
p_mapmainother() {
  got=$(mainmap conveyor/y2.jq '.areas.b.files += ["conveyor/y2.jq"]')
  [ "$got" = "MAPTEST " ] && ok "main added a map line for a file the card does not change: the map's own tests run, no other engine file" \
    || no "main added y2.jq to area b: ran '$got': $(cat "$T/out")"
  # Catches a one-file run (the loop's call: test.fileCommand, once for each file of the card's list) that starts the map's
  # own tests beside its file: the loop stops a run that starts a file beyond its list (conveyor/lib/session.sh, wide).
  grep -v $'^pass\tlib/w.test.sh' "$T/rerun" > "$T/rerun1"; rm -f "$R/ran"
  (cd "$R" && CONVEYOR_TEST_N=1 CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun1 bash .conveyor/test-changed.sh --file lib/w.test.sh) > "$T/out" 2>&1
  got=$(ranlines "$R/ran" | sorted)
  [ "$got" = "w " ] && ok "a one-file run, after main changed the map, runs only the file it was given" \
    || no "--file lib/w.test.sh after main changed the map: ran '$got': $(cat "$T/out")"
  # Catches a one-file run of the map's own test, which the loop gives once main changed the map (listcmd(): the link
  # "main:<map>"), that left it out as a test the card's selection does not hold: the test's own run did nothing.
  printf 'lib/w.test.sh\n.conveyor/test-changed.test.sh\n' > "$T/files2"; rm -f "$R/ran"
  (cd "$R" && CONVEYOR_TEST_N=2 CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun1 CONVEYOR_TEST_FILELIST=$T/files2 \
    bash .conveyor/test-changed.sh --file .conveyor/test-changed.test.sh) > "$T/out" 2>&1
  got=$(ranlines "$R/ran" | sorted)
  [ "$got" = "MAPTEST " ] && ok "a one-file run of the map's own test, after main changed the map, runs it" \
    || no "--file .conveyor/test-changed.test.sh after main changed the map: ran '$got': $(cat "$T/out")"
  # Catches a one-file run of an engine case file (the loop's own mode) that runs its cases again though main's map
  # change left their area's entry as it was: the map comparison picks them, as in a whole run.
  got=$(fileran conveyor/tests/a.test.sh)
  [ -z "$got" ] && ok "a one-file run of an engine case file whose area's map entry main left as it was runs none of its cases" \
    || no "--file conveyor/tests/a.test.sh after main added y2.jq to area b: ran '$got': $(cat "$T/out")"
}
# Main adds a file to area a's entry, the area of the file the card changes: that entry's cases run (a is a's case file).
p_mapmainentry() {
  got=$(mainmap conveyor/x2.sh '.areas.a.files += ["conveyor/x2.sh"]')
  [ "$got" = "MAPTEST aone atwo " ] && ok "main changed the map entry of the area of a file the card changes: that entry's cases run" \
    || no "main added x2.sh to area a: ran '$got': $(cat "$T/out")"
  # Catches a one-file run of an engine case file (the loop's own mode: the selection holds only the runner with that
  # file's cases) that skips the map comparison: main changed its area's entry, so its cases run again.
  got=$(fileran conveyor/tests/a.test.sh)
  [ "$got" = "aone atwo " ] && ok "a one-file run of an engine case file whose area's map entry main changed runs its cases" \
    || no "--file conveyor/tests/a.test.sh after main added x2.sh to area a: ran '$got': $(cat "$T/out")"
}

for p in rerun mainrun mainwhole nodecases flakyoff slowoff killed fixengine fixtest mainmoved fixpassed \
  core firstwhy handrun noarea why unlisted cover linked mapmainother mapmainentry; do part "$p"; done
wait
for p in "${PARTS[@]}"; do
  cat "$T/$p.res"
  [ -e "$T/$p.end" ] || echo "not ok - part $p did not run to its end"
done | awk '/^(not )?ok - / { n++; sub(/ - /, " " n " - ") } { print } /^not ok / { bad = 1 } END { exit bad }'
