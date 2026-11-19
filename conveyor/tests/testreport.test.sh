#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#152): each test file's clock seconds read from the test runner's own report (the pack's test.report,
# tools/testreport.py, testrun.sh reported()), so a project whose test command prints no `TESTRUN sec` lines still
# has test times on the Tests page; how setup finds the runner and its report (setup.sh reportguess()); and what
# health says of it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Main ($R) with the pack's test.report <json> and the files <file>... committed, each holding x, and a card's
# worktree of it ($T/$CASE/wt) with its test log folder: the case then writes the run's report into it.
rp_main() { # <report json> <file>...
  local f r=$1; shift
  setup '[]'; tune --argjson r "$r" '.test.report = $r'
  for f; do mkdir -p "$R/$(dirname "$f")" && echo x > "$R/$f"; done
  git -C "$R" add -- "$@" && git -C "$R" commit -qm tests && git -C "$R" worktree add -q --detach "$T/$CASE/wt" \
    && mkdir -p "$T/$CASE/wt.testlog" || fail "main's test files"
}
# What the Tests page shows of the files the run timed: the run's report read as a run that began a minute ago reads
# it (reported()), its times on the card's test line (slowtests(), slowrec()), that line among the card records, and
# the snapshot's tests part (testspart()): {file: [the last run's clock seconds, its CPU seconds]}, after the test line's
# times and clocks, `{"times": ..., "clocks": ...}`, on a line of its own; keys sorted, and each number as jq prints
# a sum (2, not the 2.0 of the line).
rp_page() {
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && w=$T/$CASE/wt && reported "$w" "$(($(date +%s) - 60))" && slowtests "$w" \
    && s=$(slowrec "$w") && jq -cS '{times, clocks} | walk(if type == "number" then . + 0 else . end)' <<<"$s" \
    && jq -cn --argjson s "$s" '{card: "c0-1", issue: 1, step: "test", time: "2026-11-16T00:00:00Z", tokens: {claude: 0, codex: 0},
      result: "pass", sha: "", reason: ""} + $s' >> "$ST/cards.jsonl" \
    && testspart 2026-11-10 | jq -cS '[.files[] | select(.runs != []) | {key: .file, value: [.lastRun.sec, .lastRun.cpu]}] | from_entries | walk(if type == "number" then . + 0 else . end)' )
}
# The reader alone, in the folder $T/$CASE/d (made, with the files <file>... in it): its lines for the report <path>
# from that folder, of the format <format>, written since a minute ago.
rp_read() { # <format> <path> <file>...
  local d=$T/$CASE/d f fm=$1 p=$2; shift 2
  for f; do mkdir -p "$d/$(dirname "$f")" && echo x > "$d/$f"; done
  python3 -I "$SRC/tools/testreport.py" "$fm" "$d" "$(($(date +%s) - 60))" "$d/$p"
}

# Bug caught: a Node project (node --test, JUnit reporter) recorded no test times, so Health said "Not recorded" and
# no file was on the Tests page. Each file's clock seconds are the sum of its cases' (by each case's file attribute,
# an absolute path), with no CPU seconds; a `TESTRUN sec` line of the runner's log for a file wins over the report.
t_reportnode() {
  rp_main '{"runner": "node --test", "format": "junit", "path": "out/node.xml"}' t/a.test.js t/b.test.js t/c.test.js
  local w=$T/$CASE/wt; mkdir -p "$w/out"
  cat > "$w/out/node.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<testsuites>
	<testcase name="a" time="0.250000" classname="test" file="$w/t/a.test.js"/>
	<testcase name="b" time="0.500000" classname="test" file="$w/t/a.test.js"/>
	<testsuite name="s" time="1.300000" tests="1">
		<testcase name="c" time="1.250000" classname="s" file="$w/t/b.test.js"/>
	</testsuite>
	<testcase name="d" time="0.100000" classname="test" file="$w/t/c.test.js"/>
</testsuites>
EOF
  printf 'TESTRUN sec\tt/c.test.js\t2.0\t1.5\n' > "$w.testlog/run.log"
  local out; out=$(rp_page) || fail "the run's times could not be read: $out"
  [ "$out" = $'{"clocks":{"t/a.test.js":0.75,"t/b.test.js":1.25,"t/c.test.js":2},"times":{"t/c.test.js":1.5}}\n{"t/a.test.js":[0.75,null],"t/b.test.js":[1.25,null],"t/c.test.js":[2,1.5]}' ] \
    || fail "the Tests page does not show the report's clock seconds of each file, the runner's own line winning: $out"
}
# Bug caught: a vitest project (its JSON reporter) recorded no test times. Each test result's end less its start. A
# run timed by the report alone has times {} on its test line (no CPU seconds), so it counts as a run that recorded
# times (health's untimed): with no times there, Health said "Not recorded" still.
t_reportvitest() {
  rp_main '{"runner": "vitest", "format": "jest-json", "path": "vitest.json"}' src/a.test.ts
  local w=$T/$CASE/wt
  printf '{"numTotalTests": 1, "testResults": [{"name": "%s/src/a.test.ts", "startTime": 1000, "endTime": 3500, "assertionResults": [{"duration": 3}]}]}\n' "$w" > "$w/vitest.json"
  local out; out=$(rp_page) || fail "the run's times could not be read: $out"
  [ "$out" = $'{"clocks":{"src/a.test.ts":2.5},"times":{}}\n{"src/a.test.ts":[2.5,null]}' ] \
    || fail "the test line does not hold the clock-only times, or the Tests page does not show vitest's time of the file: $out"
}
# Bug caught: a pytest project (--junitxml) recorded no test times. pytest's JUnit XML names no file: each case's
# classname is read as a module path, a class in it too, and a classname that is no file of the worktree is left out.
t_reportpytest() {
  rp_main '{"runner": "pytest", "format": "junit", "path": "reports/pytest.xml"}' tests/test_cart.py tests/sub/test_x.py
  local w=$T/$CASE/wt; mkdir -p "$w/reports"
  cat > "$w/reports/pytest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?><testsuites><testsuite name="pytest" errors="0" failures="0" tests="4" time="1.2">
<testcase classname="tests.test_cart" name="test_add" time="0.4"/><testcase classname="tests.test_cart.TestBox" name="test_box" time="0.1"/>
<testcase classname="tests.sub.test_x" name="test_x" time="0.3"/><testcase classname="tests.test_gone" name="test_g" time="9"/>
</testsuite></testsuites>
EOF
  local out; out=$(rp_page) || fail "the run's times could not be read: $out"
  [ "$(tail -n 1 <<<"$out")" = '{"tests/sub/test_x.py":[0.3,null],"tests/test_cart.py":[0.5,null]}' ] \
    || fail "the Tests page does not show pytest's time of each module: $out"
}
# Bug caught: a Go project (go test -json, in the command's output) recorded no test times, and then recorded them for
# each package's folder, which is no test file: the files stayed untimed. Each top-level test's end gives its seconds,
# by the _test.go file of its package's folder (from go.mod's module) that declares it; a subtest's line, a package's
# own line, a package outside the module and a line that is no JSON are not.
t_reportgo() {
  rp_main '{"runner": "go test", "format": "go-json"}' go.mod calc_test.go mul_test.go add/add_test.go
  local w=$T/$CASE/wt; echo 'module example.com/calc' > "$w/go.mod"
  printf 'package calc\nfunc TestCalc(t *testing.T) {}\nfunc TestSub(t *testing.T) {}\n' > "$w/calc_test.go"
  printf 'package calc\nfunc TestMul(t *testing.T) {}\n' > "$w/mul_test.go"
  printf 'package add\nfunc TestAdd(t *testing.T) {}\n' > "$w/add/add_test.go"
  cat > "$w.test" <<'EOF'
go: downloading example.com/dep v1.0.0
{"Action":"run","Package":"example.com/calc/add","Test":"TestAdd"}
{"Action":"pass","Package":"example.com/calc/add","Test":"TestAdd/one","Elapsed":0.05}
{"Action":"pass","Package":"example.com/calc/add","Test":"TestAdd","Elapsed":0.1}
{"Action":"pass","Package":"example.com/calc/add","Elapsed":0.42}
{"Action":"pass","Package":"example.com/calc","Test":"TestCalc","Elapsed":0.5}
{"Action":"fail","Package":"example.com/calc","Test":"TestSub","Elapsed":0.25}
{"Action":"pass","Package":"example.com/calc","Test":"TestMul","Elapsed":2}
{"Action":"fail","Package":"example.com/calc","Elapsed":3}
{"Action":"pass","Package":"example.com/other","Test":"TestAdd","Elapsed":3}
EOF
  local out; out=$(rp_page) || fail "the run's times could not be read: $out"
  [ "$(tail -n 1 <<<"$out")" = '{"add/add_test.go":[0.1,null],"calc_test.go":[0.75,null],"mul_test.go":[2,null]}' ] \
    || fail "the Tests page does not show go's time of each test file: $out"
}
# Bug caught: a Node project's `npm test` (node --test, its default reporter) still recorded no test times: the owner
# had to add reporter options to the test command. Setup's test.report has Conveyor ask node for a JUnit report through
# NODE_OPTIONS at each run (reportask(), testonce()); the command, unchanged, writes it, and the Tests page shows
# each file's seconds. A NODE_OPTIONS of the owner's own is kept.
t_reportask() {
  rp_main '{"runner": "node --test", "format": "junit", "env": {"NODE_OPTIONS": "--test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit --test-reporter-destination=<file>"}}' t/a.test.js
  local w=$T/$CASE/wt out
  printf '%s\n' "require('node:test').test('a', () => {});" > "$w/t/a.test.js"
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards NODE_OPTIONS=--max-old-space-size=4096; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && reportask "$w" && [ -z "$REPORT_ARGS" ] \
    && [ "${REPORT_ENV[*]}" = "NODE_OPTIONS=--max-old-space-size=4096 --test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit --test-reporter-destination=\"$w.report\"" ] \
    && (cd "$w" && export "${REPORT_ENV[@]}" && node --test t/a.test.js) > "$w.test" 2>&1 ) ) \
    || fail "the run with Conveyor's NODE_OPTIONS failed, or the owner's NODE_OPTIONS was not kept: $out $(cat "$w.test")"
  grep -q '✔ a' "$w.test" || fail "node's own output was replaced by the report: $(cat "$w.test")"
  out=$(rp_page) || fail "the run's times could not be read: $out"
  [[ $(tail -n 1 <<<"$out") =~ ^\{\"t/a\.test\.js\":\[[0-9.]+,null\]\}$ ]] || fail "the Tests page does not show the time node's report gave: $out"
}
# Bug caught: a jest project's `npm test` recorded no test times unless the owner added --json to it. The pack's
# test.report args are what a card's run adds after its command (tests()): the report file Conveyor names, quoted
# for the shell, in place of <file>, and the run's JSON report there gives each file's seconds.
t_reportargs() {
  rp_main '{"runner": "jest", "format": "jest-json", "args": "-- --json --outputFile=<file>"}' src/a.test.js
  local w=$T/$CASE/wt out
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && reportask "$w" && printf '%s|%s' "${#REPORT_ENV[@]}" "$REPORT_ARGS" ) ) \
    || fail "reportask failed: $out"
  [ "$out" = "0|-- --json --outputFile=$(printf '%q' "$w.report")" ] || fail "the run does not add jest's report option with Conveyor's file: $out"
  printf '{"testResults": [{"name": "%s/src/a.test.js", "perfStats": {"runtime": 1500}}]}\n' "$w" > "$w.report"
  out=$(rp_page) || fail "the run's times could not be read: $out"
  [ "$(tail -n 1 <<<"$out")" = '{"src/a.test.js":[1.5,null]}' ] || fail "the Tests page does not show the time of Conveyor's report file: $out"
}
# E1 of #374's review. Bug caught: a card's run, each test file alone through test.fileCommand, added the report's args
# after the run's own last word, `exit $r`, and a run that passed failed with "exit: too many arguments"; and one
# report file for all the files' runs kept the last file's times alone. Each file's run is given the args before its
# path, with a report file of its own (<worktree>.report.<n>): the run passes, and both files' seconds are read.
t_reportfiles() {
  rp_main '{"runner": "jest", "format": "jest-json", "args": "--report <file>"}' src/a.test.js src/b.test.js
  printf '%s\n' '[ "$1" = --report ] || exit 4' \
    'printf "{\"testResults\": [{\"name\": \"%s/%s\", \"perfStats\": {\"runtime\": 1500}}]}\n" "$PWD" "$3" > "$2"' > "$STUB/rep"
  tune '.test.fileCommand = "bash \"$STUB/rep\""'
  local w=$T/$CASE/wt out
  echo y >> "$w/src/a.test.js"; echo y >> "$w/src/b.test.js"; git -C "$w" add src || fail "the card's change could not be staged"
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && names && tests "$w" && cat "$w.reported" ) 2>&1 ) \
    || fail "the card's run with the report's args failed: $out $(cat "$w.test" 2>/dev/null)"
  [ "$(grep -cE $'^TESTRUN sec\tsrc/[ab]\\.test\\.js\t1\\.5' <<<"$out")" = 2 ] || fail "the report of each file's run was not read: $out"
}
# Bug caught (#164): the full test suite (test.full, which setup gives the card's command; release-prep's suite too)
# was not asked for the runner's report, so its run, an `npm test` of node --test for one, recorded no file times. The
# run of test.full (tests()) adds test.report's args with Conveyor's file, and the suite's record (suiterec()) has the
# report's seconds of the file.
t_reportfull() {
  rp_main '{"runner": "jest", "format": "junit", "args": "<file>"}' t/a.test.js
  tune '.test.full = "f() { printf %s \"<testsuites><testsuite name=\\\"a\\\" file=\\\"t/a.test.js\\\"><testcase name=\\\"x\\\" time=\\\"0.5\\\"/></testsuite></testsuites>\" > \"$1\"; }; f"'
  local w=$T/$CASE/wt out
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && names && tests "$w" test.full && suiterec "$w" full abc \
    && jq -c 'select(.sha == "abc") | .files | walk(if type == "number" then . + 0 else . end)' "$SUITERUNS" ) 2>&1 ) || fail "the full suite's run failed: $out $(cat "$w.test" 2>/dev/null)"
  [ "$out" = '{"t/a.test.js":{"result":null,"sec":0.5,"cpu":null}}' ] || fail "the full suite's run did not ask for the runner's report, or its record lacks the report's time: $out"
}
# Bug caught: a runner Conveyor does not know that writes JUnit XML files to a folder recorded no test times. Each
# file of the folder written in the run is read, its suites' file attribute naming the file; one an earlier run left
# (written before the run began) is not, so its times are never taken for this run's.
t_reportjunit() {
  rp_main '{"runner": "make test", "format": "junit", "path": "reports"}' spec/a_spec.lua spec/b_spec.lua
  local w=$T/$CASE/wt; mkdir -p "$w/reports/unit"
  printf '<testsuites><testsuite name="a" file="spec/a_spec.lua"><testcase name="x" time="0.3"/><testcase name="y" time="0.2"/></testsuite></testsuites>\n' > "$w/reports/unit/a.xml"
  printf '<testsuites><testsuite name="b" file="spec/b_spec.lua"><testcase name="z" time="4"/></testsuite></testsuites>\n' > "$w/reports/old.xml"
  touch -d '-2 hours' "$w/reports/old.xml"
  local out; out=$(rp_page) || fail "the run's times could not be read: $out"
  [ "$(tail -n 1 <<<"$out")" = '{"spec/a_spec.lua":[0.5,null]}' ] || fail "the Tests page does not show the folder's report of this run alone: $out"
}
# Bug caught: a jest project (--json --outputFile) recorded no test times. Jest gives each file's perfStats.
t_reportjest() {
  local d=$T/$CASE/d; mkdir -p "$d"
  printf '{"testResults": [{"name": "%s/a.test.js", "perfStats": {"start": 10, "end": 900, "runtime": 1200}}, {"testFilePath": "%s/b.test.js", "perfStats": {"start": 100, "end": 400}}]}\n' "$d" "$d" > "$d/j.json"
  [ "$(rp_read jest-json j.json a.test.js b.test.js)" = $'TESTRUN sec\ta.test.js\t1.200\nTESTRUN sec\tb.test.js\t0.300' ] \
    || fail "jest's report does not give each file's seconds: $(rp_read jest-json j.json)"
}
# Bug caught: a Rust project recorded no test times unless its command asked for libtest's JSON format. Each test
# target's `test result` line (its suite's exec_time in the JSON format) goes to the source its `Running` line names;
# the doctests' line, after `Doc-tests`, went to the last target's file and is left out now.
t_reportcargo() {
  local d=$T/$CASE/d; mkdir -p "$d"
  printf '%s\n' '     Running unittests src/lib.rs (target/debug/deps/calc-1)' 'running 1 test' 'test adds ... ok' '' \
    'test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.25s' \
    '     Running tests/add.rs (target/debug/deps/add-2)' 'test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 1.50s' \
    '   Doc-tests calc' 'test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 9.00s' > "$d/out"
  printf '%s\n' '     Running unittests src/lib.rs (target/debug/deps/calc-1)' '{ "type": "suite", "event": "started", "test_count": 1 }' \
    '{ "type": "suite", "event": "ok", "passed": 1, "failed": 0, "exec_time": 0.25 }' '     Running tests/add.rs (target/debug/deps/add-2)' \
    '{ "type": "test", "event": "ok", "name": "adds", "exec_time": 0.1 }' '{ "type": "suite", "event": "failed", "passed": 0, "failed": 1, "exec_time": 1.5 }' \
    '   Doc-tests calc' '{ "type": "suite", "event": "ok", "passed": 3, "failed": 0, "exec_time": 9 }' > "$d/json"
  local want=$'TESTRUN sec\tsrc/lib.rs\t0.250\nTESTRUN sec\ttests/add.rs\t1.500'
  [ "$(rp_read cargo out src/lib.rs tests/add.rs)" = "$want" ] || fail "cargo's own output does not give each test target's seconds: $(rp_read cargo out)"
  [ "$(rp_read cargo json)" = "$want" ] || fail "cargo's JSON output does not give each test target's seconds: $(rp_read cargo json)"
}
# Bug caught: a Go project whose command has no -json recorded no test times. go test -v's output (GOFLAGS=-v, which
# a card's run sets) gives each top-level test's `--- PASS|FAIL|SKIP` line, of the package the `ok|FAIL` line after
# it names, by the _test.go file that declares it; a subtest's indented line is in its parent's seconds.
t_reportgotext() {
  local d=$T/$CASE/d; mkdir -p "$d/add"
  echo 'module example.com/calc' > "$d/go.mod"
  printf 'package calc\nfunc TestCalc(t *testing.T) {}\nfunc TestSub(t *testing.T) {}\n' > "$d/calc_test.go"
  printf 'package add\nfunc TestAdd(t *testing.T) {}\n' > "$d/add/add_test.go"
  printf '%s\n' '=== RUN   TestAdd' '=== RUN   TestAdd/one' '    --- PASS: TestAdd/one (0.05s)' '--- PASS: TestAdd (0.10s)' 'PASS' \
    $'ok  \texample.com/calc/add\t0.42s' '=== RUN   TestCalc' '--- PASS: TestCalc (0.50s)' '=== RUN   TestSub' '    calc_test.go:9: wrong' \
    '--- FAIL: TestSub (0.25s)' 'FAIL' $'FAIL\texample.com/calc\t3.00s' 'FAIL' > "$d/out"
  [ "$(rp_read go-text out)" = $'TESTRUN sec\tadd/add_test.go\t0.100\nTESTRUN sec\tcalc_test.go\t0.750' ] \
    || fail "go test -v's output does not give each test file's seconds: $(rp_read go-text out)"
}
# Bug caught: a mocha project recorded no test times unless the owner changed its reporter. A card's run loads
# Conveyor's timer through NODE_OPTIONS (reportask(): <mochatimes> and <file> in it): when mocha's runner runs, each
# test's end gives its file's seconds, and the Tests page shows them. Here a stand-in for mocha's lib/runner.js.
t_reportmocha() {
  rp_main '{"runner": "mocha", "format": "mocha-times", "env": {"NODE_OPTIONS": "--require <mochatimes>", "CONVEYOR_MOCHA_REPORT": "<file>"}}' test/a.test.js test/b.test.js
  local w=$T/$CASE/wt out; mkdir -p "$w/node_modules/mocha/lib"
  printf '%s\n' "module.exports = class Runner extends require('events') { run(files) {" \
    "  for (const [file, duration] of files) this.emit('test end', { file, duration }); this.emit('test end', { file: files[0][0] }); } };" \
    > "$w/node_modules/mocha/lib/runner.js"
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && reportask "$w" \
    && (cd "$w" && export "${REPORT_ENV[@]}" && node -e "new (require('mocha/lib/runner'))().run([['$w/test/a.test.js', 250], ['$w/test/b.test.js', 1500], ['$w/test/a.test.js', 500]])") ) 2>&1 ) \
    || fail "the run with Conveyor's timer failed: $out"
  out=$(rp_page) || fail "the run's times could not be read: $out"
  [ "$(tail -n 1 <<<"$out")" = '{"test/a.test.js":[0.75,null],"test/b.test.js":[1.5,null]}' ] || fail "the Tests page does not show mocha's time of each file: $out"
}
# Bug caught (#165): a card's run that failed ran again (tests(): testonce() twice after one reportask()), and mocha's
# timer adds to Conveyor's report file, so the run again's times held the first run's too (0.25 + 0.5 s here). Each
# run reads only the report it wrote.
t_reportagain() {
  rp_main '{"runner": "mocha", "format": "mocha-times", "env": {"CONVEYOR_MOCHA_REPORT": "<file>"}}' test/a.test.js
  local w=$T/$CASE/wt out
  # shellcheck disable=SC2034 # LIVE and STUCK are read by watch(), which testonce() runs; names() is not run here
  out=$( ( LIVE=0.2 STUCK=1200; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards SLOT_HOME=$T/$CASE/slot; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && reportask "$w" \
    && { testonce "$w" "echo '{\"file\": \"$w/test/a.test.js\", \"sec\": 0.25}' >> \"\${CONVEYOR_MOCHA_REPORT//\\\"/}\"; exit 1"; [ $? = 1 ]; } \
    && testonce "$w" "echo '{\"file\": \"$w/test/a.test.js\", \"sec\": 0.5}' >> \"\${CONVEYOR_MOCHA_REPORT//\\\"/}\"" && cat "$w.reported" ) 2>&1 ) \
    || fail "the two runs failed: $out $(cat "$w.test" 2>/dev/null)"
  [ "$out" = $'TESTRUN sec\ttest/a.test.js\t0.500' ] || fail "the run again's times hold the first run's: $out"
}
# Bug caught: a Ruby project (rspec's JSON formatter) recorded no test times. Each example's run_time, by its file.
t_reportrspec() {
  local d=$T/$CASE/d; mkdir -p "$d"
  echo '{"examples": [{"file_path": "./spec/a_spec.rb", "run_time": 0.5}, {"file_path": "./spec/a_spec.rb", "run_time": 0.25}, {"file_path": "./spec/b_spec.rb", "run_time": 1}]}' > "$d/r.json"
  [ "$(rp_read rspec-json r.json spec/a_spec.rb spec/b_spec.rb)" = $'TESTRUN sec\tspec/a_spec.rb\t0.750\nTESTRUN sec\tspec/b_spec.rb\t1.000' ] \
    || fail "rspec's report does not give each file's seconds: $(rp_read rspec-json r.json)"
}
# Bug caught: a pytest project that prints --durations=0 recorded no test times. Each case's setup, call and teardown
# seconds, by its file.
t_reportdurations() {
  local d=$T/$CASE/d; mkdir -p "$d"
  printf '%s\n' '============ slowest durations ============' '0.50s call     tests/test_a.py::test_one' '0.10s setup    tests/test_a.py::test_one' \
    '0.20s call     tests/test_b.py::TestB::test_two' '(3 durations < 0.005s hidden.  Use -vv to show these durations.)' > "$d/out"
  [ "$(rp_read pytest-durations out tests/test_a.py tests/test_b.py)" = $'TESTRUN sec\ttests/test_a.py\t0.600\nTESTRUN sec\ttests/test_b.py\t0.200' ] \
    || fail "pytest's durations do not give each file's seconds: $(rp_read pytest-durations out)"
}

# Bug caught: setup did not find how to read the test runner's own report, so the pack had no test.report and no card
# recorded test times. Each runner whose report the command already writes gives its format and path (a package.json
# script read for `npm test`). Bug caught too: a runner whose report the command does not ask for (node --test, pytest,
# rspec, and vitest or jest ending the command) needed the owner to add its report option: Conveyor asks for it at
# each run, by an environment variable or words added after the command (`--` before them for an npm script). Bug
# caught too: go test, cargo test and mocha still needed the owner to add a report option: go test -v (by GOFLAGS, or
# the command's own -v) and cargo's own output are read, and mocha gets Conveyor's timer. A command it does not know,
# and a report path with a variable in it, give nothing it would read; jest not ending the command gives its option.
t_reportguess() {
  setup '[]'
  echo '{"scripts": {"test": "vitest run --reporter=default --reporter=json --outputFile.json=reports/vt.json", "unit": "jest --ci"}}' > "$R/package.json"
  local out
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && . "$SRC/lib/setup.sh" \
    && for c in "npm test" "node --test --test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit --test-reporter-destination=out/n.xml" \
      "node --max-old-space-size=4096 --test" "pytest -q --junitxml=./reports/p.xml" "python3 -m pytest --durations=0" "go test -json ./..." \
      "cargo test -- -Z unstable-options --format json" "jest --json --outputFile=j.json" "bundle exec rspec --format json --out r.json" \
      "go test ./..." "go test -v ./..." "cargo test" "mocha 'lib/*.test.js'" "make check" 'pytest --junitxml=$OUT/p.xml' "npm run unit" "npx vitest run" "jest && eslint ." "bundle exec rspec"; do
      echo "$(reportguess "$c")"; done ) ) || fail "the guess failed: $out"
  [ "$out" = '{"runner":"vitest","format":"jest-json","path":"reports/vt.json"}
{"runner":"node --test","format":"junit","path":"out/n.xml"}
{"runner":"node --test","format":"junit","env":{"NODE_OPTIONS":"--test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit --test-reporter-destination=<file>"}}
{"runner":"pytest","format":"junit","path":"reports/p.xml"}
{"runner":"pytest","format":"pytest-durations"}
{"runner":"go test","format":"go-json"}
{"runner":"cargo test","format":"cargo"}
{"runner":"jest","format":"jest-json","path":"j.json"}
{"runner":"rspec","format":"rspec-json","path":"r.json"}
{"runner":"go test","format":"go-text","env":{"GOFLAGS":"-v"}}
{"runner":"go test","format":"go-text"}
{"runner":"cargo test","format":"cargo"}
{"runner":"mocha","format":"mocha-times","env":{"NODE_OPTIONS":"--require <mochatimes>","CONVEYOR_MOCHA_REPORT":"<file>"}}

{"runner":"pytest","option":"--junitxml=<file>"}
{"runner":"jest","format":"jest-json","args":"-- --json --outputFile=<file>"}
{"runner":"vitest","format":"jest-json","args":"--reporter=default --reporter=json --outputFile.json=<file>"}
{"runner":"jest","option":"--json --outputFile=<file>"}
{"runner":"rspec","format":"rspec-json","env":{"SPEC_OPTS":"--format progress --format json --out <file>"}}' ] || fail "setup did not find each runner and how to read its report: $out"
}
# Bug caught: Health said only "Not recorded" for a project whose runner setup found but whose output Conveyor cannot
# read: health gives the pack's test.report beside untimed, for the Board to name the runner and its report option.
t_reportuntimed() {
  setup '[]'; tune '.test.report = {runner: "jest", option: "--json --outputFile=<file>"}'
  jq -cn '{card: "c0-1", issue: 1, step: "test", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: ""}' >> "$ST/cards.jsonl"
  local out; out=$(loop health | jq -c '{untimed, report}')
  [ "$out" = '{"untimed":1,"report":{"runner":"jest","option":"--json --outputFile=<file>"}}' ] \
    || fail "health does not give the pack's test.report with the runs that recorded no times: $out"
}
