#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh's selection on a scratch map: which cases a change to an area's file, a case file, a Board or
# shell test file or the map itself runs, what a map line must be, the shellcheck of changed lines and the time
# lines; and this checkout's own map check (every engine source file in exactly one area).
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
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
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$R/.conveyor/"; : > "$R/.conveyor/test-lint.sh"; : > "$R/.conveyor/no-browser-tests.sh"; : > "$R/.conveyor/no-records-split.sh"
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
# nothing else (collector) and three it runs named after dashboard_limit.py and dashboard_server.py (TESTS_OF); one of
# dashboard_server.py's it does not run; two of the page's. And a part of dashboard.sh and one of dashboard_server.py,
# named after no test (test-changed.sh PART_OF).
board463() {
  local s=$R/.claude/scripts f
  mkdir -p "$s/__tests__"
  for f in dashboard.sh dashboard_server.py dashboard_limit.py dashboard_panels.sh dashboard_server_auth.py; do echo one > "$s/$f"; done
  for f in dashboard dashboard-limit dashboard-limit-wait dashboard-server dashboard-server-local; do echo 'exit 0' > "$s/__tests__/$f.test.sh"; done
  for f in dashboard-collector-incremental dashboard-view.needs dashboard-view.page-tabs; do echo '// none' > "$s/__tests__/$f.test.mjs"; done
  git -C "$R" add -A && git -C "$R" commit -qm board
  echo two >> "$s/$1"
  mkdir "$T/olog"; CONVEYOR_TEST_LOG=$T/olog ran > /dev/null
  sed -n 's/^== .claude\/scripts\/__tests__\///p' "$T/olog/test-changed.log" | sorted
}
p_owned() {
  got=$(board463 dashboard.sh)
  [ "$got" = "dashboard-collector-incremental.test.mjs dashboard-limit-wait.test.sh dashboard-limit.test.sh dashboard-server.test.sh dashboard.test.sh " ] \
    && ok "a change to dashboard.sh selects its own tests and those that run it, not the page's or another source file's" \
    || no "dashboard.sh changed: ran '$got': $(cat "$T/out")"
}
p_ownedpy() {
  got=$(board463 dashboard_server.py)
  [ "$got" = "dashboard-server-local.test.sh dashboard-server.test.sh " ] \
    && ok "a change to dashboard_server.py selects the dashboard-server tests, its by name" \
    || no "dashboard_server.py changed: ran '$got': $(cat "$T/out")"
}
# Bug caught: a part of a Board script is named after no test, so a change to it alone selected no test of its script.
p_partsh() {
  got=$(board463 dashboard_panels.sh)
  [ "$got" = "dashboard-collector-incremental.test.mjs dashboard-limit-wait.test.sh dashboard-limit.test.sh dashboard-server.test.sh dashboard.test.sh " ] \
    && ok "a change to a part of dashboard.sh selects dashboard.sh's tests" \
    || no "dashboard_panels.sh changed: ran '$got': $(cat "$T/out")"
}
# And a test .conveyor/test-links.json links to dashboard_server.py (page-tabs here) was skipped for a change to its part.
p_partpy() {
  echo '{".claude/scripts/dashboard_server.py": [".claude/scripts/__tests__/dashboard-view.page-tabs.test.mjs"]}' > "$R/.conveyor/test-links.json"
  got=$(board463 dashboard_server_auth.py)
  [ "$got" = "dashboard-server-local.test.sh dashboard-server.test.sh dashboard-view.page-tabs.test.mjs " ] \
    && ok "a change to a part of dashboard_server.py selects dashboard_server.py's tests and linked tests" \
    || no "dashboard_server_auth.py changed: ran '$got': $(cat "$T/out")"
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
# Bug it catches: the map's own test was split in three files (issue 959) and a map change ran only the one named
# test-changed.test.sh, so this file's checks of this checkout's map (p_checkout, p_union) never ran on a map change.
# A map change, made by the card or by main (a `main` line), runs both files that read the map, not the rerun file.
p_mapareas() {
  local t
  for t in areas rerun; do echo "echo MAP$t >> \"\$(dirname \"\$0\")/../ran\"" > "$R/.conveyor/test-changed-$t.test.sh"; done
  maptest
  jq '.areas.b.tests = ["b.test.sh", "a.test.sh"]' "$T/map" | lines > "$R/.conveyor/engine-areas.json"
  got=$(mran2)
  [ "$got" = "MAPTEST MAPareas aone atwo" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a map change runs test-changed.test.sh and test-changed-areas.test.sh, not test-changed-rerun.test.sh" \
    || no "map change, three map test files: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
  # The run again: the card's change (each of the three files edited) selects all three, and all three passed; main's
  # map change runs again only the two that read the map.
  git -C "$R" checkout -q -- .conveyor/engine-areas.json
  for t in "" -areas -rerun; do echo ': two' >> "$R/.conveyor/test-changed$t.test.sh"; done
  printf 'change\tabc\n' > "$T/rerun"
  for t in "" -areas -rerun; do printf 'pass\t.conveyor/test-changed%s.test.sh\n' "$t" >> "$T/rerun"; done
  printf 'main\t.conveyor/engine-areas.json\n' >> "$T/rerun"
  got=$(CONVEYOR_TEST_LOG=$T/log CONVEYOR_TEST_RERUN=$T/rerun mran2)
  [ "$got" = "MAPTEST MAPareas" ] && ok "after main changed the map, both map test files run again, not the rerun file" \
    || no "main changed the map, three map test files: ran '$got': $(cat "$T/out")"
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
  mkdir -p "$u/.conveyor" && cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/engine-areas.json" "$u/.conveyor/" && cp "$ROOT/.gitattributes" "$u/" \
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
  # Bug: a shellcheck that could not check the files (lint-shell.sh exit 2 or more) passed, its error lines dropped
  # as no finding on a changed line. A shellcheck that exits 3 (bad options) stands in for it.
  printf '%s\n' '#!/usr/bin/env bash' 'echo "shellcheck: bad option" >&2; exit 3' > "$T/bin/shellcheck"; chmod +x "$T/bin/shellcheck"
  PATH=$T/bin ran > /dev/null
  [ "$(cat "$T/rc")" = 1 ] && grep -q 'shellcheck could not check the changed shell files (exit 3)' "$T/out" && grep -q 'bad option' "$T/out" \
    && ok "a shellcheck that cannot check the files fails the run" || no "shellcheck exit 3: exit $(cat "$T/rc"): $(cat "$T/out")"
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

for p in checkout area selected boardcount shellcount ended realstate filter named owned ownedpy partsh partpy deleted mapadd \
  mapareas mapmove mapcore emptyarea casefile caseshared scnew scold enginetime cputime badline union; do part "$p"; done
wait
for p in "${PARTS[@]}"; do
  cat "$T/$p.res"
  [ -e "$T/$p.end" ] || echo "not ok - part $p did not run to its end"
done | awk '/^(not )?ok - / { n++; sub(/ - /, " " n " - ") } { print } /^not ok / { bad = 1 } END { exit bad }'
