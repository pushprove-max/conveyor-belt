#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh and the engine area map: a build or fix session runs only the engine cases of the areas a change
# touches (the full engine test is about 9 minutes, run several times a card), and so does the loop's test step
# (CONVEYOR_TEST_LOG set); and an engine source file in no area fails the
# map check, so a new file is never left out of the session runs unseen.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
# The loop's test step sets CONVEYOR_TEST_FILES (the card's changed test files) and CONVEYOR_TEST_RERUN: left set,
# every scratch run below would select the card's files as well as its own.
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILES CONVEYOR_TEST_RERUN
# The checks are in parts (p_<name>) that run side by side, each in a scratch folder of its own (T, part below): each
# says ok or not ok, and the lines are numbered once every part has ended, in the order the parts started.
ok() { echo "ok - $1"; }
no() { echo "not ok - $1"; }

# A scratch repo: the real script, a map of two areas and a core, case files a and b, and a runner stub that
# records which cases it was asked for (ALL when none was named). Each part starts from its own copy of it, as
# committed ($T/r, its map also in $T/map, read as one object: test-changed.sh --map).
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
cp "$HERE/test-changed.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$R/.conveyor/"
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
echo 'echo "${CONVEYOR_SHELL_TEST_CASE:-ALL}" >> "$(dirname "$0")/../ran"' > "$R/conveyor/conveyor.test.sh"
echo one > "$R/conveyor/core.sh"; echo one > "$R/conveyor/x.sh"; echo one > "$R/conveyor/y.jq"; echo doc > "$R/conveyor/README.md"
# The runner stub's run of every case file is a meta-runner's (issue 584): a card mode in the pack lets it run whole
# here, so the parts below see which runs are whole.
echo '{"test": {"files": {"conveyor/conveyor.test.sh": {"cardMode": "CONVEYOR_RUNNER_STUB=1"}}}}' > "$R/.conveyor/project.json"
echo ran > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
# ran: the cases the runner stub was asked for, its runs' lines sorted and joined (each engine case file runs on its
# own, side by side, so a selection of two files is two runs, in either order).
ran() { rm -f "$R/ran"; (cd "$R" && bash .conveyor/test-changed.sh "$@") > "$T/out" 2>&1; echo $? > "$T/rc"; LC_ALL=C sort "$R/ran" 2>/dev/null | tr -s ' ' | sed 's/ $//' | paste -sd' ' -; }
mran2() { ran "$@" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//'; }
sorted() { tr ' ' '\n' | grep . | sort | tr '\n' ' '; }
# part <name> [m]: p_<name> in the background, in $T/<name> with its own copy of the scratch repo (R), and with m of
# this checkout's map copy below (M); its output in $T/<name>.res, and $T/<name>.end once it ran to its end.
PARTS=()
part() {
  PARTS+=("$1")
  (B=$T; T=$T/$1; mkdir "$T" && cp -a "$B/r" "$T/r" && cp "$B/scratch.json" "$T/map" || exit 1; R=$T/r
    [ -z "${2:-}" ] || { cp -a "$B/m" "$T/m" && M=$T/m; } || exit 1
    # A name with no p_ function (a typo in the list) fails, rather than skipping its cases with no result.
    declare -F "p_$1" > /dev/null || { echo "not ok - no part p_$1"; exit 1; }
    "p_$1"; : > "$B/$1.end") > "$T/$1.res" 2>&1 &
}

# This checkout's own map: every engine source file is in exactly one area.
p_checkout() {
  out=$(cd "$ROOT" && bash .conveyor/test-changed.sh --check 2>&1) && ok "this checkout's engine area map passes" || no "this checkout's map: $out"
}

p_area() {
  echo two >> "$R/conveyor/x.sh"
  got=$(ran)
  [ "$got" = "aone atwo" ] && [ "$(cat "$T/rc")" = 0 ] && ok "a session runs only the changed area's cases" || no "session, area a changed: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  got=$(CONVEYOR_TEST_LOG=$T/log ran)
  [ "$got" = "aone atwo" ] && ok "the test step, like a session, runs only the changed area's cases" || no "test step, area a changed: ran '$got': $(cat "$T/out")"
  # The test step's record of a failed run names the files that failed from this log, not from the output.
  mkdir "$T/steplog"; echo 'exit 1' > "$R/conveyor/conveyor.test.sh"
  CONVEYOR_TEST_LOG=$T/steplog ran > /dev/null
  # It says too what it selected out of how many: the runner, which changed, so all 3 cases, out of the 2 case files,
  # each a test file of its own (issue 214); why it ran (each changed file that selected it), and that it ran every
  # case file (issue 517), each as a file it started (issue 584).
  [ "$(cat "$T/rc")" = 1 ] && [ "$(tr '\n' '|' < "$T/steplog/test-changed.log")" = "TESTRUN files=1 of=2|TESTRUN cases=3 of=3|== conveyor/conveyor.test.sh|TESTRUN why	conveyor/conveyor.test.sh	the card changed conveyor/conveyor.test.sh|TESTRUN why	conveyor/conveyor.test.sh	the card changed conveyor/x.sh|TESTRUN whole-suite|TESTRUN nested	conveyor/conveyor.test.sh	conveyor/tests/a.test.sh|TESTRUN nested	conveyor/conveyor.test.sh	conveyor/tests/b.test.sh|-- FAIL conveyor/conveyor.test.sh|" ] \
    && ok "the test step's log says what it selected, names each file as it begins and how it ended" || no "test step log: exit $(cat "$T/rc"): $(cat "$T/steplog/test-changed.log" 2>&1)"
}

p_selected() {
  # A change no test touches selects nothing, and its log says so (the step records "nothing selected").
  mkdir "$T/nolog"; CONVEYOR_TEST_LOG=$T/nolog ran > /dev/null
  [ "$(cat "$T/rc")" = 0 ] && [ "$(tr '\n' '|' < "$T/nolog/test-changed.log")" = "TESTRUN files=0 of=2|TESTRUN cases=0 of=3|" ] \
    && ok "the test step's log of a change no test touches says nothing was selected" || no "nothing selected: exit $(cat "$T/rc"): $(cat "$T/nolog/test-changed.log" 2>&1)"
  echo two >> "$R/conveyor/x.sh"
  mkdir "$T/alog"; CONVEYOR_TEST_LOG=$T/alog ran > /dev/null
  [ "$(head -n 2 "$T/alog/test-changed.log" | tr '\n' '|')" = "TESTRUN files=1 of=2|TESTRUN cases=2 of=3|" ] \
    && ok "the test step's log says it selected area a's 2 of the 3 cases, in its 1 of the 2 case files" || no "area a's cases: $(cat "$T/alog/test-changed.log" 2>&1)"
}

# A Board test file's cases count too, selected and in all: its 2 node tests beside area a's 2 engine cases, of 5.
p_boardcount() {
  echo two >> "$R/conveyor/x.sh"
  mkdir -p "$R/board/__tests__"; printf "import test from 'node:test';\ntest('one', () => {});\ntest('two', () => {});\n" > "$R/board/__tests__/v.test.mjs"
  mkdir "$T/blog"; CONVEYOR_TEST_LOG=$T/blog ran > /dev/null
  [ "$(head -n 2 "$T/blog/test-changed.log" | tr '\n' '|')" = "TESTRUN files=2 of=3|TESTRUN cases=4 of=5|" ] \
    && ok "the test step's log counts a Board test file's cases among those selected" || no "board cases: $(cat "$T/blog/test-changed.log" 2>&1)"
}

# A shell test file's cases count too: its 2 checks beside area a's 2 engine cases, of 5.
shellfile() { mkdir -p "$R/tool"; printf 'check() { :; }\ncheck "one" 1 1\ncheck "two" 1 1\n' > "$R/tool/s.test.sh"; }
p_shellcount() {
  echo two >> "$R/conveyor/x.sh"; shellfile
  mkdir "$T/slog"; CONVEYOR_TEST_LOG=$T/slog ran > /dev/null
  [ "$(head -n 2 "$T/slog/test-changed.log" | tr '\n' '|')" = "TESTRUN files=2 of=3|TESTRUN cases=4 of=5|" ] \
    && ok "the test step's log counts a shell test file's cases among those selected" || no "shell cases: $(cat "$T/slog/test-changed.log" 2>&1)"
  # Bug: with no time line, the loop recorded no time of a test file the card adds.
  # The engine's runner is no test file of its own: it times its case files (p_enginetime), never itself.
  [ "$(grep '^TESTRUN sec' "$T/slog/test-changed.log" | grep -cE '^TESTRUN sec	tool/s\.test\.sh	[0-9]+\.[0-9]	[0-9]+\.[0-9]$')" = 1 ] \
    && ! grep -q '^TESTRUN sec	conveyor/conveyor.test.sh' "$T/slog/test-changed.log" \
    && ok "the test step's log times the shell test file it ran, once, and not the engine's runner" || no "time line: $(cat "$T/slog/test-changed.log" 2>&1)"
}

# Bug: the cases counted above for a Board or shell test file were never recorded as ended, so the loop's live record
# showed them as not done, and their failures were not counted. Each one is now recorded when its file ends. A Board
# file of 3 tests with 2 failing (node's summary says `fail 2`) gives 2 in failed and 1 in ok. A shell file that passes
# gives both of its checks in ok.
p_ended() {
  echo two >> "$R/conveyor/x.sh"; shellfile
  mkdir -p "$R/board/__tests__"; printf "import test from 'node:test';\ntest('one', () => {});\ntest('two', () => { throw new Error('x'); });\ntest('three', () => { throw new Error('y'); });\n" > "$R/board/__tests__/v.test.mjs"
  mkdir "$T/clog"; CONVEYOR_TEST_LOG=$T/clog ran > /dev/null
  got=$(cd "$T/clog/cases" && find . -type f | sort | tr '\n' ' ')
  [ "$(cat "$T/rc")" = 1 ] && [ "$got" = "./failed/board:__tests__:v.test.mjs#1 ./failed/board:__tests__:v.test.mjs#2 ./ok/board:__tests__:v.test.mjs#3 ./ok/tool:s.test.sh#1 ./ok/tool:s.test.sh#2 " ] \
    && ok "the test step records a Board and a shell test file's cases as ended, the failed ones apart" || no "case records: exit $(cat "$T/rc"), '$got': $(cat "$T/out")"
}

# Bug (issue 452): a test run wrote a fake Foreman claim into the real main checkout's conveyor/state/foreman, and the
# run passed. A test file that writes the Foreman's mark there fails the run and is named; one beside it that does not
# is not (the mark is compared again from what the last file left).
p_realstate() {
  echo two >> "$R/conveyor/x.sh"; shellfile
  echo 'd=$(dirname "$0")/../conveyor/state/foreman; mkdir -p "$d" && echo "a3a3a3a3-0000 x" > "$d/session"' > "$R/tool/claim.test.sh"
  ran > /dev/null
  [ "$(cat "$T/rc")" = 1 ] && grep -qF "tool/claim.test.sh changed the Foreman's mark in the main checkout's state" "$T/out" \
    && [ "$(grep -c "changed the Foreman's mark" "$T/out")" = 1 ] \
    && ok "a test file that writes the Foreman's mark in the main checkout's state fails the run, and it alone is named" \
    || no "Foreman's mark written: exit $(cat "$T/rc"): $(cat "$T/out")"
}

p_filter() {
  echo two >> "$R/conveyor/x.sh"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_SHELL_TEST_CASE=aone ran)
  [ "$got" = "aone atwo" ] && ok "the test step runs the area's cases even with a case filter in its environment" || no "test step, inherited filter aone: ran '$got': $(cat "$T/out")"
}

# Bug (issue 446): Rules' Undo is tested in dashboard-view.needs.test.mjs, a file named after no panel, so a change to
# .claude/dashboard/panels/rules.js did not select it and landed with it failing. It is selected; a test file that
# only mentions rules.js (as a fixture's text may) is not.
p_named() {
  local n=.claude/scripts/__tests__/dashboard-view.needs.test.mjs o=.claude/scripts/__tests__/other.test.mjs
  mkdir -p "$R/.claude/scripts/__tests__" "$R/.claude/dashboard/panels"
  echo "test('x', () => {});" > "$R/$n"; echo "// .claude/dashboard/panels/rules.js" > "$R/$o"
  echo one > "$R/.claude/dashboard/panels/rules.js"
  git -C "$R" add -A && git -C "$R" commit -qm board
  echo two >> "$R/.claude/dashboard/panels/rules.js"
  mkdir "$T/nlog"; CONVEYOR_TEST_LOG=$T/nlog ran > /dev/null
  got=$(sed -n 's/^== //p' "$T/nlog/test-changed.log" | tr '\n' ' ')
  [ "$got" = "$n " ] && ok "a change to panels/rules.js selects dashboard-view.needs, and not a test file that only mentions it" \
    || no "rules.js changed: ran '$got': $(cat "$T/out")"
}

# Bug (issue 463): a test is selected by its name, <stem>-*, so a change to dashboard.sh alone selected every
# dashboard-* test: the page's dashboard-view.* and those of dashboard_server.py (43 of 90 files). A test named
# <stem>-<rest> is the longest source name's it starts with (`_` read as `-`); the page's dashboard-view names no
# file (test-changed.sh NAMED). A Board of each kind: dashboard.sh with its own test, a test of it named after
# nothing else (collector) and two it runs named after dashboard_limit.py and dashboard_server.py (TESTS_OF); one of
# dashboard_server.py's it does not run; two of the page's.
board463() {
  local s=$R/.claude/scripts f
  mkdir -p "$s/__tests__"
  for f in dashboard.sh dashboard_server.py dashboard_limit.py; do echo one > "$s/$f"; done
  for f in dashboard dashboard-limit dashboard-server dashboard-server-local; do echo 'exit 0' > "$s/__tests__/$f.test.sh"; done
  for f in dashboard-collector-incremental dashboard-view.needs dashboard-view.page-tabs; do echo '// none' > "$s/__tests__/$f.test.mjs"; done
  git -C "$R" add -A && git -C "$R" commit -qm board
  echo two >> "$s/$1"
  mkdir "$T/olog"; CONVEYOR_TEST_LOG=$T/olog ran > /dev/null
  sed -n 's/^== .claude\/scripts\/__tests__\///p' "$T/olog/test-changed.log" | sorted
}
p_owned() {
  got=$(board463 dashboard.sh)
  [ "$got" = "dashboard-collector-incremental.test.mjs dashboard-limit.test.sh dashboard-server.test.sh dashboard.test.sh " ] \
    && ok "a change to dashboard.sh selects its own tests and those that run it, not the page's or another source file's" \
    || no "dashboard.sh changed: ran '$got': $(cat "$T/out")"
}
p_ownedpy() {
  got=$(board463 dashboard_server.py)
  [ "$got" = "dashboard-server-local.test.sh dashboard-server.test.sh " ] \
    && ok "a change to dashboard_server.py selects the dashboard-server tests, its by name" \
    || no "dashboard_server.py changed: ran '$got': $(cat "$T/out")"
}

# A deleted engine file's area is gone from the map with it (its case file listed by another area, as the check
# asks), so its change runs every case, in a session and the step.
p_deleted() {
  rm "$R/conveyor/x.sh"; jq 'del(.areas.a) | .areas.b.tests += ["a.test.sh"]' "$T/map" | lines > "$R/.conveyor/engine-areas.json"
  got=$(ran)
  [ "$got" = ALL ] && [ "$(cat "$T/rc")" = 0 ] && ok "a session runs every case for a deleted engine file" || no "session, x.sh deleted: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  got=$(CONVEYOR_TEST_LOG=$T/log ran)
  [ "$got" = ALL ] && ok "the test step runs every case for a deleted engine file" || no "test step, x.sh deleted: ran '$got': $(cat "$T/out")"
}

# Bug: a map change ran the whole engine test (a card that added four names to the map ran all 241 cases). It now runs
# the map's own test (a committed stub here, that records MAPTEST) and the case files whose naming changed, in a
# session and the step: a case file newly listed by an area runs, as it never ran on that area's files.
maptest() {
  echo 'echo MAPTEST >> "$(dirname "$0")/../ran"' > "$R/.conveyor/test-changed.test.sh"
  git -C "$R" add -A && git -C "$R" commit -qm maptest
}
p_mapadd() {
  maptest
  jq '.areas.b.tests = ["b.test.sh", "a.test.sh"]' "$T/map" | lines > "$R/.conveyor/engine-areas.json"
  got=$(mran2)
  [ "$got" = "MAPTEST aone atwo" ] && [ "$(cat "$T/rc")" = 0 ] && ok "a session runs the map's test and the newly listed case file for a map change, not every case" \
    || no "session, a.test.sh added to b: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  got=$(CONVEYOR_TEST_LOG=$T/log mran2)
  [ "$got" = "MAPTEST aone atwo" ] && ok "the test step runs the map's test and the newly listed case file for a map change" || no "test step, a.test.sh added to b: ran '$got': $(cat "$T/out")"
}
p_mapmove() {
  maptest
  # An engine file moved from one area to another runs both areas' case files: the cases it leaves and the ones it joins.
  jq '.areas.a.files = [] | .areas.b.files += ["conveyor/x.sh"]' "$T/map" | lines > "$R/.conveyor/engine-areas.json"
  got=$(mran2)
  [ "$got" = "MAPTEST aone atwo bone" ] && ok "a map change that moves an engine file runs both areas' case files" || no "x.sh moved from a to b: ran '$got': $(cat "$T/out")"
  # A file added to an "all" area runs every case.
  jq '.areas.core.files += ["conveyor/x.sh"] | .areas.a.files = []' "$T/map" | lines > "$R/.conveyor/engine-areas.json"
  got=$(mran2)
  [ "$got" = "ALL MAPTEST" ] && ok "a map change to an \"all\" area's files runs every case" || no "x.sh moved to core: ran '$got': $(cat "$T/out")"
}
p_mapcore() {
  maptest
  # A map change beside a change to what every case runs through still runs every case.
  jq '.areas.b.tests = ["b.test.sh", "a.test.sh"]' "$T/map" | lines > "$R/.conveyor/engine-areas.json"; echo two >> "$R/conveyor/core.sh"
  got=$(mran2)
  [ "$got" = "ALL MAPTEST" ] && ok "a map change with a core change runs every case" || no "map and core changed: ran '$got': $(cat "$T/out")"
  echo one > "$R/conveyor/core.sh"
  # A map that cannot be read at HEAD gives nothing to compare with: every case runs.
  echo '{not json' > "$R/.conveyor/engine-areas.json"; git -C "$R" commit -qam badmap
  jq '.areas.b.tests = ["b.test.sh", "a.test.sh"]' "$T/map" | lines > "$R/.conveyor/engine-areas.json"
  got=$(mran2)
  [ "$got" = "ALL MAPTEST" ] && ok "a map that is not JSON at HEAD runs every case" || no "map not JSON at HEAD: ran '$got': $(cat "$T/out")"
}

# An area with no case files would let its source change run no test at all.
p_emptyarea() {
  jq '.areas.a.tests = []' "$T/map" | lines > "$R/.conveyor/engine-areas.json"
  echo two >> "$R/conveyor/x.sh"
  ran > /dev/null
  [ "$(cat "$T/rc")" = 1 ] && grep -q '^a: an area of .* with no case files' "$T/out" \
    && ok "an area with no case files fails the map check" || no "area a with no test line: exit $(cat "$T/rc"): $(cat "$T/out")"
}

# A line of the map that is not one of its shapes is not passed over: an area's files written as a list (the map's
# old shape, one long line per area) would leave x.sh in no area's files unseen, and an area with both "all" and a case
# file says two things. Either makes the map unreadable, and the check fails.
p_badline() {
  for l in '{"area": "a", "files": ["conveyor/x.sh"]}' '{"area": "a", "tests": "all"}'; do
    { lines < "$T/map" | grep -v '"file":"conveyor/x.sh"'; echo "$l"; } > "$R/.conveyor/engine-areas.json"
    (cd "$R" && bash .conveyor/test-changed.sh --check) > "$T/out" 2>&1
    [ $? = 1 ] && grep -q 'engine-areas.json could not be read' "$T/out" && ok "a map line $l fails the map check" || no "map line $l: $(cat "$T/out")"
  done
}

# Bug (#436: the map was shared in 5 of a day's 11 landing clashes): each area's lists were one long line, so two cards
# that each added a file to one area always clashed. The map is one fact a line, merged keeping both sides (this
# checkout's .gitattributes): a card that adds a file to the claim area, after the same line as main did, merges onto
# main three-way as the landing merges it (git apply --3way, claim.sh settle()), with no conflict, and the map reads both.
p_union() {
  local u=$T/u f
  mkdir -p "$u/.conveyor" && cp "$HERE/test-changed.sh" "$HERE/engine-areas.json" "$u/.conveyor/" && cp "$ROOT/.gitattributes" "$u/" \
    && git -C "$u" init -q && git -C "$u" add -A && git -C "$u" commit -qm init || { no "the map's merge: no scratch repo"; return; }
  f=$u/.conveyor/engine-areas.json
  for n in one two; do
    awk -v l="{\"area\": \"claim\", \"file\": \"conveyor/lib/$n.sh\"}" '{ print } $0 == "{\"area\": \"claim\", \"file\": \"conveyor/lib/claim.sh\"}" { print l }' \
      "$HERE/engine-areas.json" > "$f"
    [ $n = two ] || { git -C "$u" diff > "$T/one.patch"; continue; }
    git -C "$u" commit -qam "main adds two.sh"
  done
  if (cd "$u" && git apply --3way --index "$T/one.patch") > "$T/out" 2>&1 \
    && (cd "$u" && bash .conveyor/test-changed.sh --map) | jq -e '.areas.claim.files as $f | all("conveyor/lib/claim.sh", "conveyor/lib/one.sh", "conveyor/lib/two.sh"; . as $x | $f | index($x))' >/dev/null; then
    ok "two changes that each add a file to one area of the map merge with no conflict, both files in it"
  else no "the map's merge of two added files: $(cat "$T/out") $(cat "$f")"; fi
}

# Issue 513 (D3). Bug: a changed case file ran whole, every case of it, when a card only edited or added one. A case
# file whose shared part (lines outside its t_<case> functions) is the same but for comments runs only the cases it
# changed (atwo's body, under a new comment) and added (btwo), not aone or bone.
p_casefile() {
  printf 't_aone() {\n  :\n}\n# A comment on atwo.\nt_atwo() {\n  true\n}\n' > "$R/conveyor/tests/a.test.sh"
  echo 't_btwo() { :; }' >> "$R/conveyor/tests/b.test.sh"
  got=$(mran2)
  [ "$got" = "atwo btwo" ] && ok "a session runs only the changed and added cases of a case file whose shared part is the same" \
    || no "session, atwo changed and btwo added: ran '$got': $(cat "$T/out")"
}
# A change to a case file's shared part runs the file whole: a.test.sh's new helper, beside its changed atwo, runs aone
# too. So does a case of no shape it can read: b.test.sh's btwo with a line at the left (were it read as btwo's, a
# change to a helper after a case read as not ended would run that case alone).
p_caseshared() {
  printf 't_btwo() {\n  :\n}\n' >> "$R/conveyor/tests/b.test.sh"; git -C "$R" commit -qam btwo
  printf 'helper() {\n  :\n}\nt_aone() {\n  :\n}\nt_atwo() {\n  true\n}\n' > "$R/conveyor/tests/a.test.sh"
  printf 't_bone() {\n  :\n}\nt_btwo() {\nx=1\n}\n' > "$R/conveyor/tests/b.test.sh"
  got=$(mran2)
  [ "$got" = "aone atwo bone btwo" ] && ok "a change to a case file's setup, or a case it cannot read, runs the file whole" \
    || no "session, a.test.sh setup and b.test.sh shape changed: ran '$got': $(cat "$T/out")"
}

# The shellcheck of changed lines (issue 525). Bug: a card's unquoted variable (#461's P1) passed tests that only parsed.
p_scnew() {
  echo 'rm -f $@' >> "$R/conveyor/x.sh"; ran > /dev/null
  [ "$(cat "$T/rc")" = 1 ] && grep -q '^conveyor/x.sh:2:.*SC2068' "$T/out" && ok "a new shellcheck warning on a changed line fails the run" || no "unquoted \$@ added: exit $(cat "$T/rc"): $(cat "$T/out")"
}
# Bug: the engine's old warnings would fail every card that touched their file.
p_scold() {
  printf 'rm -f $@\none\n' > "$R/conveyor/x.sh"; git -C "$R" commit -qam old; echo two >> "$R/conveyor/x.sh"; ran > /dev/null
  [ "$(cat "$T/rc")" = 0 ] && ! grep -q SC2068 "$T/out" && ok "an old warning on a line the change did not touch passes" || no "old warning: exit $(cat "$T/rc"): $(cat "$T/out")"
  # With no shellcheck on the PATH, the run says so once and goes on.
  mkdir "$T/bin"; for d in ${PATH//:/ }; do ln -s "$d"/* "$T/bin/" 2>/dev/null; done; rm -f "$T/bin/shellcheck"; PATH=$T/bin ran > /dev/null
  [ "$(cat "$T/rc")" = 0 ] && [ "$(grep -c 'shellcheck is not installed' "$T/out")" = 1 ] && ok "a missing shellcheck says so and passes" || no "no shellcheck: exit $(cat "$T/rc"): $(cat "$T/out")"
}

# Bug: an engine case file had no time line, so the time of one a card added or slowed was never recorded.
# The runner writes each case file's time and CPU seconds to the file CONVEYOR_TEST_TIMES names; the log has them
# under its path.
p_enginetime() {
  echo 't_btwo() { :; }' >> "$R/conveyor/tests/b.test.sh"
  echo 'printf "b.test.sh\t7.5\t3.2\n" > "$CONVEYOR_TEST_TIMES"' > "$R/conveyor/conveyor.test.sh"
  mkdir "$T/elog"; CONVEYOR_TEST_LOG=$T/elog ran > /dev/null
  [ "$(cat "$T/rc")" = 0 ] && [ "$(grep '^TESTRUN sec' "$T/elog/test-changed.log")" = "TESTRUN sec	conveyor/tests/b.test.sh	7.5	3.2" ] \
    && ok "the test step's log times an engine case file by the runner's time and CPU seconds of it" || no "engine time line: exit $(cat "$T/rc"): $(cat "$T/elog/test-changed.log" 2>&1)"
}

# Bug: a file's recorded time was its clock time, which on a busy machine is the load's. The log gives each file's CPU
# seconds too, of its own process tree: a file that sleeps 0.6 s uses next to none, one that burns CPU uses it,
# however long either took.
p_cputime() {
  mkdir -p "$R/tool"; echo 'sleep 0.6' > "$R/tool/idle.test.sh"
  echo 'i=0; while [ $i -lt 100000 ]; do i=$((i + 1)); done' > "$R/tool/busy.test.sh"
  mkdir "$T/clog"; CONVEYOR_TEST_LOG=$T/clog ran > /dev/null
  got=$(awk -F'\t' '$1 == "TESTRUN sec" { printf "%s %s %s|", $2, $3, $4 }' "$T/clog/test-changed.log")
  awk -F'\t' '$1 == "TESTRUN sec" && $2 == "tool/idle.test.sh" { i = $3 >= 0.6 && $4 <= 0.1 }
    $1 == "TESTRUN sec" && $2 == "tool/busy.test.sh" { b = $4 >= 0.05 && $4 <= $3 + 0.1 } END { exit !(i && b) }' "$T/clog/test-changed.log" \
    && ok "the test step's log gives each file's CPU seconds, next to none for one that sleeps" || no "CPU seconds, file clock CPU: '$got': $(cat "$T/out")"
}

# Bug (issue 583): a card that changed the closure test ran its ~700 units from the copy, 20 to 30 minutes, for a
# check of seconds. The test step runs it in quick mode (CONVEYOR_CLOSURE_QUICK=1, its card mode in this checkout's
# pack: issue 584); another test file, not.
p_closurequick() {
  mkdir -p "$R/conveyor/tools" "$R/lib"; cp "$HERE/project.json" "$R/.conveyor/"
  echo 'echo "closure:${CONVEYOR_CLOSURE_QUICK:-full}" >> "$(dirname "$0")/../../ran"' > "$R/conveyor/tools/closure.test.sh"
  echo 'echo "w:${CONVEYOR_CLOSURE_QUICK:-full}" >> "$(dirname "$0")/../ran"' > "$R/lib/w.test.sh"
  got=$(ran | sort | paste -sd ' ' -)
  [ "$got" = "closure:1 w:full" ] && ok "the test step runs the closure test in quick mode, and no other test file" || no "closure test: ran '$got': $(cat "$T/out")"
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
# Bug it catches: the loop runs a card's failing cases on main (conveyor.sh verdicts()), a clean tree where no change
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
# Issue 457: a test file the slow-test record names is kept off card runs (conveyor.sh slowoff():
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
  # of the runner's cases it did not run (conveyor.sh rerunlist()).
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
  # Main changed the map: the map at HEAD is main's, so the case files it named anew (one now covering the change's
  # x.sh) cannot be told from it, and the runner's cases the change selects run though they passed.
  printf 'change\tabc\npass\tlib/w.test.sh\npass\tconveyor/conveyor.test.sh\nmain\t.conveyor/engine-areas.json\n' > "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "aone atwo " ] && ok "after main changed the map, the runner's cases the change selects run again" || no "main changed the map: ran '$got': $(cat "$T/out")"
}
# Bug (#345): a file that passed, run again because the cards landed since touch what it tests (conveyor's unshare():
# a `fail` line and a `shared` line), was logged as "did not pass". Its log now says main changed what it tests, of an
# engine case file run through the runner too. (A file that failed still says it did not pass: p_mainmoved.)
p_sharedwhy() {
  wchange
  printf 'change\tabc\nfail\tlib/w.test.sh\nshared\tlib/w.test.sh\nfail\tconveyor/tests/b.test.sh\nshared\tconveyor/tests/b.test.sh\nok\tconveyor/conveyor.test.sh\taone\nok\tconveyor/conveyor.test.sh\tatwo\n' > "$T/rerun"
  mkdir "$T/slog"; got=$(CONVEYOR_TEST_LOG=$T/slog CONVEYOR_TEST_RERUN=$T/rerun ran | sorted)
  [ "$got" = "bone w " ] && [ "$(sed -n 's/^TESTRUN why\t//p' "$T/slog/test-changed.log" | sort | tr '\t\n' ':|')" = "conveyor/tests/b.test.sh:main changed what it tests since it passed|lib/w.test.sh:main changed what it tests since it passed|" ] \
    && ok "a file run again on main's change says main changed what it tests, not that it did not pass" \
    || no "shared files: ran '$got': $(cat "$T/slog/test-changed.log" "$T/out")"
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
  # A case file kept off whole (slowoff(): an `off` line with no case) does not run: that log does not say every case file ran.
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
      bash .conveyor/test-changed.sh --funcs "$f" | jq -cR --arg f "$f" 'split("\t") | {file: $f, fn: .[0], sum: .[1]}'; done
    jq -cn --arg d "$d" '{file: "conveyor/x.sh", fn: "xone", test: "conveyor/conveyor.test.sh", case: "aone"},
      {file: ".claude/scripts/dashboard.sh", fn: "dfa", test: $d, case: "history"}'; } > .conveyor/coverage.jsonl)
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
  (cd "$R" && bash .conveyor/test-changed.sh --funcs .claude/hooks/hk.sh | jq -cR 'split("\t") | {file: ".claude/hooks/hk.sh", fn: .[0], sum: .[1]}'
    jq -cn --arg hk "$hk" --arg bg "$bg" '{file: ".claude/hooks/hk.sh", fn: "hka", test: $hk, case: "hc"}, {file: ".claude/hooks/hk.sh", fn: "hka", test: $hk, case: "ha"},
      {file: ".claude/hooks/hk.sh", fn: "hkb", test: $bg, case: "the hkb check"}') >> "$R/.conveyor/coverage.jsonl"
  git -C "$R" add -A && git -C "$R" commit -qm hooks
  sed 's/echo a/echo A/; s/echo b/echo B/' "$R/.claude/hooks/hk.sh" > "$T/e" && cat "$T/e" > "$R/.claude/hooks/hk.sh"; got=$(ran)
  [ "$got" = "bg:the hkb check hk:ha,hc" ] && ok "changed hook functions run only the case_on cases and check texts the map lists" || no "hka and hkb changed: ran '$got': $(cat "$T/out")"
  git -C "$R" checkout -q -- .claude/hooks/hk.sh
  printf 'xthree() {\n  echo three\n}\n' >> "$R/conveyor/x.sh"; got=$(ran)
  [ "$got" = "aone atwo" ] && ok "D3: a function the coverage map does not hold runs its file's area, as before" || no "xthree added: ran '$got': $(cat "$T/out")"
  git -C "$R" checkout -q -- conveyor/x.sh; echo 'echo top' >> "$R/conveyor/x.sh"; got=$(ran)
  [ "$got" = "aone atwo" ] && ok "a changed line outside the functions runs the area" || no "top-level line: ran '$got': $(cat "$T/out")"
  git -C "$R" checkout -q -- conveyor/x.sh
  sed 's/echo one/echo uno/' "$R/conveyor/x.sh" > "$T/e" && cat "$T/e" > "$R/conveyor/x.sh"; git -C "$R" commit -qam since
  sed 's/echo uno/echo eins/' "$R/conveyor/x.sh" > "$T/e" && cat "$T/e" > "$R/conveyor/x.sh"; got=$(ran)
  [ "$got" = "aone atwo" ] && ok "a function changed since the coverage map was traced runs the area" || no "xone changed since the trace: ran '$got': $(cat "$T/out")"
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

for p in checkout area selected boardcount shellcount ended realstate filter named owned ownedpy deleted mapadd mapmove mapcore emptyarea casefile caseshared scnew scold enginetime cputime \
  rerun closurequick mainrun mainwhole nodecases flakyoff slowoff killed fixengine fixtest mainmoved sharedwhy fixpassed core firstwhy handrun noarea why unlisted badline union cover linked; do part "$p"; done

# This checkout's own map, on a scratch copy of every file it names, each case file holding one case named after it
# (t_<file>): a change to one engine file runs the case files its area names, not the whole engine test; a change to
# what every case runs through (the dispatcher, the shared setup) still runs the whole. Each part below has its own
# copy of it (M).
M=$T/m; mkdir -p "$M/.conveyor" "$M/conveyor/tests"
cp "$HERE/test-changed.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/engine-areas.json" "$M/.conveyor/"
HMAP=$T/here.json; (cd "$ROOT" && bash .conveyor/test-changed.sh --map) > "$HMAP" || echo "not ok - this checkout's map could not be read"
jq -r '.areas[].files[]' "$HMAP" | while read -r f; do mkdir -p "$M/${f%/*}"; echo one > "$M/$f"; done
for c in "$ROOT"/conveyor/tests/*.test.sh; do s=$(basename "$c" .test.sh); printf 't_%s() {\n  :\n}\n' "$s" > "$M/conveyor/tests/$s.test.sh"; done
echo 'echo "${CONVEYOR_SHELL_TEST_CASE:-ALL}" >> "$(dirname "$0")/../ran"' > "$M/conveyor/conveyor.test.sh"
cp "$R/.conveyor/project.json" "$M/.conveyor/"
echo ran > "$M/.gitignore"
git -C "$M" init -q && git -C "$M" add -A && git -C "$M" commit -qm init
mran() { rm -f "$M/ran"; (cd "$M" && bash .conveyor/test-changed.sh) > "$T/out" 2>&1; echo $? > "$T/rc"; LC_ALL=C sort "$M/ran" 2>/dev/null | tr -s ' ' | sed 's/ $//' | paste -sd' ' -; }
cases=$(ls "$M"/conveyor/tests/*.test.sh | wc -l)
marea() { # <engine file>
  local f=$1 want got
  want=$(jq -r --arg f "$f" '.areas[] | select(.files | index($f)) | .tests[]' "$HMAP" | sed 's/[.]test[.]sh$//' | sort | tr '\n' ' ')
  echo two >> "$M/$f"; got=$(mran); echo one > "$M/$f"
  [ -n "$want" ] && [ "$got" = "${want% }" ] && [ "$(wc -w <<<"$got")" -lt "$cases" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a change to $f alone runs its area's case files ($got), not the whole engine test" \
    || no "$f changed: ran '$got', want '$want' of $cases case files, exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_mtestrun() { marea conveyor/lib/testrun.sh; }
p_mreview() { marea conveyor/lib/review.sh; }
p_mclaim() { marea conveyor/lib/claim.sh; }
p_mall() {
  echo two >> "$M/conveyor/tests/lib.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a change to conveyor/tests/lib.sh runs the whole engine test" || no "conveyor/tests/lib.sh changed: ran '$got': $(cat "$T/out")"
}
# Issue 513. Bug: any change to the dispatcher, conveyor.sh (core, an "all" area), ran the whole engine test, 74 case
# files, though it only reworded a message. D1: a reworded echo message runs the case file that holds it (wait's), not
# the whole engine test. D2: a changed code line still runs the whole.
p_mdisp() {
  printf '#!/usr/bin/env bash\nset -u\necho "the dispatcher could not start its loop"\n' > "$M/conveyor/conveyor.sh"
  printf 't_wait() {\n  grep -q "could not start its loop" out\n}\n' > "$M/conveyor/tests/wait.test.sh"
  git -C "$M" commit -qam dispatcher
  sed 's/could not/cannot/' "$M/conveyor/conveyor.sh" > "$T/e" && cat "$T/e" > "$M/conveyor/conveyor.sh"; got=$(mran)
  [ "$got" = wait ] && [ "$(cat "$T/rc")" = 0 ] && ok "a reworded echo message in conveyor/conveyor.sh runs the case file that holds it, not the whole engine test" \
    || no "conveyor.sh echo reworded: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  git -C "$M" show HEAD:conveyor/conveyor.sh | sed 's/^set -u$/set -e/' > "$T/e" && cat "$T/e" > "$M/conveyor/conveyor.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed code line in conveyor/conveyor.sh runs the whole engine test" || no "conveyor.sh code changed: ran '$got': $(cat "$T/out")"
}
# Issue 513. Bug: the base area's test pack fixtures (test-pack.json, test-hooks.json, test-card-rules.md) were no
# file a text-only change could be, so a blank line or a reworded card rule there ran the whole engine test. Blanks in
# the JSON run no engine case; a reworded rule runs the case file that holds it; a changed JSON value still runs all.
p_mbase() {
  printf '{\n  "owner": {"name": "Sample"}\n}\n' > "$M/conveyor/lib/test-pack.json"
  printf '{"hooks": {}}\n' > "$M/conveyor/lib/test-hooks.json"
  printf '# Test pack card rules\n\n- PACK-CARD-RULE: the test pack rule given to every card.\n' > "$M/conveyor/lib/test-card-rules.md"
  printf 't_wait() {\n  grep -q "rule given to every card" out\n}\n' > "$M/conveyor/tests/wait.test.sh"
  git -C "$M" commit -qam fixtures
  printf '\n' >> "$M/conveyor/lib/test-pack.json"; printf '{ "hooks": { } }\n' > "$M/conveyor/lib/test-hooks.json"; got=$(mran)
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 0 ] && ok "blanks added to the test pack's JSON fixtures run no engine case, not the whole engine test" \
    || no "test pack JSON blanks: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  git -C "$M" checkout -q -- conveyor/lib
  sed 's/given to/given to each and/' "$M/conveyor/lib/test-card-rules.md" > "$T/e" && cat "$T/e" > "$M/conveyor/lib/test-card-rules.md"; got=$(mran)
  [ "$got" = wait ] && [ "$(cat "$T/rc")" = 0 ] && ok "a reworded rule in test-card-rules.md runs the case file that holds it, not the whole engine test" \
    || no "test-card-rules.md reworded: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  git -C "$M" checkout -q -- conveyor/lib
  sed 's/Sample/Other/' "$M/conveyor/lib/test-pack.json" > "$T/e" && cat "$T/e" > "$M/conveyor/lib/test-pack.json"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed value in test-pack.json runs the whole engine test" || no "test-pack.json value changed: ran '$got': $(cat "$T/out")"
}
# Issue 514. Bug: any code change to paths.sh (base, an "all" area) ran the whole engine test, 74 case files, though
# it changed one function that only some areas call. D1: a changed function body runs the case files of its callers'
# areas (review.sh calls it; claim.sh through cardaccts, a function of paths.sh that calls it) and the case file that
# calls it, not pick.sh's whose comment names it. D2: a changed top-level line, or a function a top-level line calls
# at start-up, still runs the whole.
p_mfuncs() {
  printf 'HOST=x\nnohost() {\n  :\n}\nnohost\nguardread() { # <control record>\n  echo one\n}\ncardaccts() { guardread; } 2>/dev/null\n' \
    > "$M/conveyor/lib/paths.sh"
  printf 'rv() { guardread; }\n' > "$M/conveyor/lib/review.sh"; printf 'cl() { cardaccts; }\n' > "$M/conveyor/lib/claim.sh"
  printf '# guardread() reads the guard\n' > "$M/conveyor/lib/pick.sh"; printf 't_wait() {\n  guardread\n}\n' > "$M/conveyor/tests/wait.test.sh"
  git -C "$M" commit -qam functions
  want=$({ jq -r '.areas[] | select(.files | index("conveyor/lib/review.sh") or index("conveyor/lib/claim.sh")) | .tests[]' "$HMAP"
    echo wait.test.sh; } | sed 's/[.]test[.]sh$//' | sort -u | tr '\n' ' ')
  sed 's/echo one/echo two/' "$M/conveyor/lib/paths.sh" > "$T/e" && cat "$T/e" > "$M/conveyor/lib/paths.sh"; got=$(mran)
  [ "$got" = "${want% }" ] && [ "$(wc -w <<<"$got")" -lt "$cases" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed function body in paths.sh runs the case files of its callers' areas ($got), not the whole engine test" \
    || no "paths.sh guardread() changed: ran '$got', want '$want', exit $(cat "$T/rc"): $(cat "$T/out")"
  git -C "$M" show HEAD:conveyor/lib/paths.sh | sed 's/^HOST=x$/HOST=y/' > "$M/conveyor/lib/paths.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed top-level line of paths.sh runs the whole engine test" || no "paths.sh top-level line changed: ran '$got': $(cat "$T/out")"
  git -C "$M" show HEAD:conveyor/lib/paths.sh | sed 's/^  :$/  true/' > "$M/conveyor/lib/paths.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed function of paths.sh that runs at start-up runs the whole engine test" || no "paths.sh nohost() changed: ran '$got': $(cat "$T/out")"
}
# Issue 514. Bug: any code change to conveyor.sh ran the whole engine test, though it changed one command's line of
# its command table (issue 530: the table replaced the dispatch case). D3: a changed command line runs the case files
# that run that command (`loop retry`, and `loop <main> retry` through a case file's own loop, `bash "$X" retry` with
# X set to conveyor.sh's path), not machine's that runs shut; with its usage text reworded too, also the case file
# that holds the text. A command the shared setup runs (state-dir), or a change to setup() itself (D4), runs the
# whole. Issue 530 D1: a command line added to the table runs only the case file that runs that command (pick's).
p_mcmds() {
  printf '#!/usr/bin/env bash\nset -u\n# The command table.\ncmd() { :; }\ncmd retry retry.sh %s\n# Shut a card.\ncmd shut shut.sh %s\ncmd state-dir state-dir.sh %s\necho "usage: conveyor.sh" >&2\n' \
    "'retry <issue>'" "'shut <issue>'" "'state-dir'" > "$M/conveyor/conveyor.sh"
  printf 'loop() { bash "$SRC/conveyor.sh" "$@"; }\nsetup() {\n  ST=$(loop state-dir)\n}\n' > "$M/conveyor/tests/lib.sh"
  printf 't_control() {\n  loop retry 5\n}\n' > "$M/conveyor/tests/control.test.sh"
  printf 'loop() { bash "$SRC/conveyor.sh" "${@:2}"; }\nt_batch() {\n  loop "$S" retry 5\n}\n' > "$M/conveyor/tests/batch.test.sh"
  printf 't_machine() {\n  loop shut 5\n}\n' > "$M/conveyor/tests/machine.test.sh"
  printf 'go() { X=$D/conveyor/conveyor.sh; }\nt_setup() {\n  go; bash "$X" retry 5\n}\n' > "$M/conveyor/tests/setup.test.sh"
  printf 't_wait() {\n  grep -q "the usage of retry <issue>" out\n}\n' > "$M/conveyor/tests/wait.test.sh"
  printf 't_pick() {\n  loop again 5\n}\n' > "$M/conveyor/tests/pick.test.sh"
  git -C "$M" commit -qam dispatch
  sed 's/^cmd retry retry.sh /cmd retry again.sh /' "$M/conveyor/conveyor.sh" > "$T/e" && cat "$T/e" > "$M/conveyor/conveyor.sh"; got=$(mran)
  [ "$got" = "batch control setup" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed command line in conveyor.sh runs the case files that run that command, not the whole engine test" \
    || no "conveyor.sh retry line changed: ran '$got', want 'batch control setup', exit $(cat "$T/rc"): $(cat "$T/out")"
  sed "s/'retry <issue>'/'retry <issue> [--now]'/" "$M/conveyor/conveyor.sh" > "$T/e" && cat "$T/e" > "$M/conveyor/conveyor.sh"; got=$(mran)
  [ "$got" = "batch control setup wait" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed command line with a reworded usage text runs that command's case files and the one that holds the text" \
    || no "conveyor.sh retry line and usage changed: ran '$got', want 'batch control setup wait', exit $(cat "$T/rc"): $(cat "$T/out")"
  git -C "$M" show HEAD:conveyor/conveyor.sh | awk '/^cmd shut / { print "cmd again again.sh \047again <issue>\047" } 1' > "$M/conveyor/conveyor.sh"; got=$(mran)
  [ "$got" = pick ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a command line added to the table runs only the case file that runs that command, not the whole engine test" \
    || no "conveyor.sh again line added: ran '$got', want 'pick', exit $(cat "$T/rc"): $(cat "$T/out")"
  git -C "$M" show HEAD:conveyor/conveyor.sh | sed 's/state-dir.sh/dir.sh/' > "$M/conveyor/conveyor.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed command that the shared test setup runs runs the whole engine test" || no "conveyor.sh state-dir line changed: ran '$got': $(cat "$T/out")"
  git -C "$M" checkout -q -- conveyor/conveyor.sh
  sed 's/ST=/export ST=/' "$M/conveyor/tests/lib.sh" > "$T/e" && cat "$T/e" > "$M/conveyor/tests/lib.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed setup() in conveyor/tests/lib.sh runs the whole engine test" || no "tests/lib.sh setup() changed: ran '$got': $(cat "$T/out")"
}
# Issue 530. Bug: the control record's defaults were a line of paths.sh (base, an "all" area), so a key added to them
# ran the whole engine test. D2: a key added to control-defaults.json runs only the case file that reads the file
# (control's), not the whole engine test nor control.sh's area; a changed default runs also the case files of the code
# that reads that key (pick.sh reads .mode), not those of code that reads another (push.sh, .rules.push).
p_mdefaults() {
  printf '{\n  "mode": "run",\n  "rules": {\n    "push": true\n  }\n}\n' > "$M/conveyor/lib/control-defaults.json"
  printf 'CTL0=$(jq -c . "$HERE/lib/control-defaults.json")\nctl() { jq -c --argjson d "$CTL0" %s "$CONTROL"; }\n' "'\$d * .'" > "$M/conveyor/lib/control.sh"
  printf 'paused() { jq -e %s <<<"$1"; }\n' "'.mode == \"pause\"'" > "$M/conveyor/lib/pick.sh"
  printf 'pushes() { jq -e %s <<<"$1"; }\n' "'.rules.push'" > "$M/conveyor/lib/push.sh"
  printf 't_control() {\n  jq -c . "$SRC/lib/control-defaults.json"\n}\n' > "$M/conveyor/tests/control.test.sh"
  git -C "$M" commit -qam defaults
  jq '.later = true' "$M/conveyor/lib/control-defaults.json" > "$T/e" && cat "$T/e" > "$M/conveyor/lib/control-defaults.json"; got=$(mran)
  [ "$got" = control ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a key added to the control record's defaults runs the case file that reads them, not the whole engine test" \
    || no "control-defaults.json key added: ran '$got', want 'control', exit $(cat "$T/rc"): $(cat "$T/out")"
  want=$({ jq -r '.areas[] | select(.files | index("conveyor/lib/pick.sh")) | .tests[]' "$HMAP"; echo control.test.sh; } \
    | sed 's/[.]test[.]sh$//' | sort -u | tr '\n' ' ')
  git -C "$M" show HEAD:conveyor/lib/control-defaults.json | jq '.mode = "pause"' > "$M/conveyor/lib/control-defaults.json"; got=$(mran)
  [ "$got" = "${want% }" ] && [ "$(wc -w <<<"$got")" -lt "$cases" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed default runs the case files of the code that reads that key ($got), not the whole engine test" \
    || no "control-defaults.json mode changed: ran '$got', want '${want% }', exit $(cat "$T/rc"): $(cat "$T/out")"
}
# A map change runs only the case files it renamed, but beside a change to the shared test setup it still runs the whole.
p_mmap() {
  jq '.areas.slots.tests += ["wait.test.sh"]' "$HMAP" | lines > "$M/.conveyor/engine-areas.json"
  got=$(mran)
  [ "$got" = wait ] && ok "a map change that adds wait.test.sh to an area runs that case file alone" || no "map, wait.test.sh added: ran '$got': $(cat "$T/out")"
  echo two >> "$M/conveyor/tests/lib.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a map change with a change to conveyor/tests/lib.sh runs the whole engine test" || no "map and tests/lib.sh changed: ran '$got': $(cat "$T/out")"
}

# Bug: an engine file's area left out a case file written to test that file (fail.test.sh's landing checks of
# claim.sh, reuse.test.sh's reuse branch of card.sh, metrics.test.sh's session and review statistics,
# reviewacct.test.sh's and reviewacctown.test.sh's review account of review.sh's claudereview, port.test.sh's landing
# conflict of claim.sh's land, control.test.sh's close through issues.sh's shut), so a change to it passed its card
# with that case unrun. Each pair is an engine file and a case file that tests it.
p_mapnames() {
  missing=$(for p in claim:fail card:reuse card:batch card:rules session:metrics review:metrics snapshot:metrics snapshot:visible \
    prompts:review prompts:port push:branch setup:machine install:serve control:serve run:records views:samefile views:giveway \
    views:fail pick:fail review:reviewacct review:reviewacctown claim:port issues:control; do
    jq -e --arg f "conveyor/lib/${p%%:*}.sh" --arg c "${p#*:}.test.sh" \
      '[.areas[] | select(.files | index($f)) | .tests | arrays | index($c)] | any(. != null)' "$HMAP" >/dev/null || echo "$p"
  done)
  [ -z "$missing" ] && ok "each engine file's area names the case files written to test it" || no "areas missing their case files: $missing"

  # An area that lists more than half the case files is near the whole test on every change to it: it says why.
  big=$(jq -r --argjson n "$cases" '.areas | to_entries[] | select((.value.tests | arrays | length) * 2 > $n and (.value.why // "") == "") | .key' \
    "$HMAP")
  [ -z "$big" ] && ok "no area of this checkout's map lists more than half the case files without a why" || no "areas over half the $cases case files with no why: $big"
}

for p in mtestrun mreview mclaim mall mdisp mbase mmap mfuncs mcmds mdefaults; do part "$p" m; done
part mapnames
wait
for p in "${PARTS[@]}"; do
  cat "$T/$p.res"
  [ -e "$T/$p.end" ] || echo "not ok - part $p did not run to its end"
done | awk '/^(not )?ok - / { n++; sub(/ - /, " " n " - ") } { print } /^not ok / { bad = 1 } END { exit bad }'
