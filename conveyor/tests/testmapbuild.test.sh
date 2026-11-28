#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#178): the test map built by hand (lib/testmap.sh mapask(), maprunbuild(), mapquit()): `conveyor.sh
# testmap build` makes it now, on a test slot, and records how it went; `testmap stop` stops it. Their fixtures are
# testmap.test.sh's nodemain and mapeng.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# nodemain's project on a pool of one test slot of the case's own, each test file run by $STUB/file.sh with <its
# first lines> before node --test.
tmbsetup() { # <the file command's first lines>
  export XDG_CONFIG_HOME=$T/$CASE/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the host file was not written"
  nodemain
  printf '%s\n' "$1" 'exec node --test "$@"' > "$STUB/file.sh" && tune '.test.fileCommand = "bash \"$STUB/file.sh\""' || fail "the file command"
}
tmbrec() { jq -r "$1" "$R/.conveyor/test-map.build.json" 2>/dev/null; } # <jq filter>: of the build's record
tmbfree() { flock -n "$T/$CASE/slots/1" true; } # the pool's one slot is free

# Bug it catches: a user who said no at setup, or whose map was old or failed, could not make the map but by setup.
# The build runs mapbuild() on the main checkout, holding the machine's test slot, and /units (`conveyor.sh testmap`)
# shows it running; its record says when it started and ended and that it made the map, and the slot is free after.
t_testmapbuild() {
  local out
  tmbsetup "[ -e \"\$STUB/units\" ] || { if flock -n \"\$STUB/../slots/1\" true; then echo free; else echo held; fi > \"\$STUB/held\"
  CONVEYOR_MAIN=\"\$R\" bash '$SRC/conveyor.sh' testmap > \"\$STUB/units\"; }"
  out=$(loop testmap build 2>&1) && [ "$out" = 'conveyor: the test map is being built with V8 coverage' ] || fail "the build did not start: $out"
  wait_until '[ "$(tmbrec .state)" = made ]' "cat '$R/.conveyor/test-map.build.json'" || fail "the build did not end made"
  [ "$(cat "$STUB/held")" = held ] || fail "the build did not hold the test slot while it ran"
  jq -e '.state == "running" and .of == 3' "$STUB/units" > /dev/null || fail "/units did not show the build running: $(cat "$STUB/units")"
  tmbrec '[(.start | type), (.end | type), .end >= .start, .reason, .tool, has("pid")] | tojson' | grep -qx '\["number","number",true,null,"V8 coverage",false\]' \
    || fail "the record does not say when it ran and that it made the map: $(cat "$R/.conveyor/test-map.build.json")"
  mapis '.sources["src/a.js"] == ["test/a.test.js"]' "the build did not write the map"
  tmbfree || fail "the build kept the test slot after it ended"
  # The Tests page's part: the made map with when and how long, the tool, and the build's record.
  mapeng 'mapboard "$R"' && jq -e '.state == "made" and .sources == 3 and .tests == 3 and .age == 0 and (.made | type) == "string"
    and (.seconds | type) == "number" and .tool == "V8 coverage" and .toolWhy == null and .build.state == "made"' "$T/$CASE/eng.out" > /dev/null \
    || fail "the Test map part does not say the map is made, with the tool and the build: $(cat "$T/$CASE/eng.out")"
  out=$(loop snapshot | jq -c '[.testMap.state, .testMap.build.state]') && [ "$out" = '["made","made"]' ] || fail "the snapshot does not carry the Test map part: $out"
  # A record that says running whose runner is gone (the machine restarted), or whose pid now names another process
  # that holds no lock, would show a build running for ever: it is failed, saying so.
  mapeng 'echo "{\"pid\": $$, \"start\": 1, \"end\": null, \"state\": \"running\"}" > "$(mapbuildpath)"; mapboard "$R"' \
    && jq -e '.build.state == "failed" and .build.reason == "its run stopped before it ended" and (.build | has("pid") | not)' "$T/$CASE/eng.out" > /dev/null \
    || fail "a build whose runner holds no lock is shown as running: $(cat "$T/$CASE/eng.out")"
}

# Bug it catches: a second build beside the first wrote the map twice, each holding a test slot; and a build that
# could not be stopped held the slot until the whole suite had run. A second start is refused while one runs; a stop
# ends the build's processes, frees the slot, leaves the map there as it was and records stopped.
t_testmapbuildstop() {
  local out
  tmbsetup "$(wait_fn)"'; echo $$ > "$STUB/pid"; wait_poll [ -e "$STUB/go" ]'
  out=$(loop testmap build 2>&1) || fail "the build did not start: $out"
  wait_until '[ -s "$STUB/pid" ]' || fail "the build's first test file did not start"
  out=$(loop testmap build 2>&1); [ $? = 2 ] && [ "$out" = 'conveyor: a build of the test map is running; nothing started' ] \
    || fail "a second start was not refused: $out"
  # A whole run on main with the map due (made under another test command) collects no coverage beside the build,
  # which would write the map too.
  nodemap; tune '.test.command = "npm test"'
  mapeng 'mapcovon "$R"' && grep -q 'but a build of it by hand runs' "$T/$CASE/eng.out" && [ ! -e "$R.mapcov" ] \
    || fail "a whole run on main collected coverage while the build ran: $(cat "$T/$CASE/eng.out")"
  out=$(loop testmap stop 2>&1) && [ "$out" = 'conveyor: the build of the test map is stopped' ] || fail "the stop failed: $out"
  [ "$(tmbrec '[.state, .reason, (.end | type)] | tojson')" = '["stopped","stopped by hand","number"]' ] \
    || fail "the record does not say stopped: $(cat "$R/.conveyor/test-map.build.json")"
  ! kill -0 "$(cat "$STUB/pid")" 2>/dev/null || fail "the test file still runs after the stop"
  tmbfree || fail "the stopped build kept the test slot"
  loop testmap | jq -e '.state == "made" and .sources == 3' > /dev/null || fail "the stopped build did not leave the map there as it was: $(loop testmap 2>&1)"
  out=$(loop testmap stop 2>&1); [ $? = 2 ] || fail "a stop with no build running was not refused: $out"
}

# Bug it catches: with test.map off the build asked a question, or ran anyway. It says the map is off and how to turn
# it on, and starts nothing.
t_testmapbuildoff() {
  local out
  nodemain; tune '.test.map = "off"'
  out=$(loop testmap build 2>&1); [ $? = 2 ] || fail "a build with the map off was not refused: $out"
  [[ $out == 'conveyor: the test map is off (the pack'"'"'s test.map is "off")'*'remove test.map from '*'setup with --test-map yes'* ]] \
    || fail "the refusal does not say the map is off and how to turn it on: $out"
  [ ! -e "$R/.conveyor/test-map.build.json" ] || fail "a refused build left a record"
}

# Bug it catches: with test.map naming a map the project keeps itself, the Tests page offered Build (its language has
# a coverage tool), and the command refused every click. The part gives no tool, saying why, and the command refuses.
t_testmapbuildkept() {
  local out
  nodemain; tune '.test.map = "test/map.json"'
  mapeng 'mapboard "$R"' && jq -e '.tool == null and (.toolWhy | test("keeps itself \\(test/map.json\\)"))' "$T/$CASE/eng.out" > /dev/null \
    || fail "the Test map part offers a build of a map the project keeps: $(cat "$T/$CASE/eng.out")"
  out=$(loop testmap build 2>&1); [ $? = 2 ] && [[ $out == *'keeps itself (test/map.json)'* ]] || fail "a build of a map the project keeps was not refused: $out"
}

# Bug it catches: a project whose language has no coverage tool the map knows got a build that could only fail. It
# is told so, and why, and nothing starts.
t_testmapbuildnotool() {
  local out
  setup '[]'
  out=$(loop testmap build 2>&1); [ $? = 2 ] || fail "a build with no coverage tool was not refused: $out"
  [ "$out" = "conveyor: no test map can be made: its language has no coverage tool the test map knows (Node, Python, Go, Rust or Ruby); a card's tests are found by name; nothing started" ] \
    || fail "the refusal does not say why: $out"
  [ ! -e "$R/.conveyor/test-map.build.json" ] || fail "a refused build left a record"
}

# mapbuild of a Python project of three test files under <test command>, whose stub coverage runs the suite, prints
# <the run's output> (one line a file) with tests/test_bad.py failing, exits 1 as the runner does, and reports
# contexts of all three: the map holds the two that passed, and test_bad.py is not mapped, with why.
pyfailmap() { # <test command> <the run's output>
  setup '[]'
  mkdir -p "$R/src" "$R/tests" && echo x > "$R/pyproject.toml" && for f in src/a.py src/b.py tests/test_a.py tests/test_b.py tests/test_bad.py; do echo x > "$R/$f"; done
  git -C "$R" add -A && git -C "$R" commit -qm python && printf '%s\n' "$2" > "$STUB/py-says" || fail "main's files could not be committed"
  # stub: coverage.py, which runs the suite (one failed test) and reports the contexts each test touched
  cat > "$STUB/coverage" <<'EOF'
#!/usr/bin/env bash
case $1 in
  run) cat "$STUB/py-says"; exit 1 ;;
  json) echo '{"files": {"src/a.py": {"contexts": {"1": ["tests.test_a.test_a", "tests.test_bad.test_x"]}}, "src/b.py": {"contexts": {"1": ["tests.test_b.test_b"]}}}}' > "${!#}" ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$STUB/coverage" && tune --arg c "$1" '.test.list = "args" | .test.command = $c' || fail "the stub"
  mapeng 'mapbuild "$R"' || fail "mapbuild under '$1' with one failing Python test file failed (its output: $2): $(cat "$T/$CASE/eng.out")"
  mapis '.sources == {"src/a.py": ["tests/test_a.py"], "src/b.py": ["tests/test_b.py"]} and .tests == ["tests/test_a.py", "tests/test_b.py"]
    and ([.notMapped[] | [.file, .why]] == [["tests/test_bad.py", "a test of it failed under coverage"]])' \
    "the map of a suite under '$1' whose tests/test_bad.py fails (its output: $2) does not map the other two and name it not mapped"
}
# Bug it catches (O244): one failing Python test file failed the whole map build, as the suite runs once under
# coverage and pytest exits 1 when any test fails. pytest names the file in its FAILED line. Bug it catches too (E7):
# the whole FAILED line was searched for test files, so a message that names a passing file left that file out too.
t_testmappyfail() {
  pyfailmap 'pytest -q' $'tests/test_a.py .\ntests/test_b.py .\ntests/test_bad.py F\nFAILED tests/test_bad.py::test_x - Failed: tests/test_a.py'
}
# Bug it catches: unittest discover -s tests names a failed test's module from that folder, test_bad, not the file's
# path, so its failure was not matched to tests/test_bad.py and the whole build failed.
t_testmapunitfail() {
  pyfailmap 'python -m unittest discover -s tests' $'..F\nFAIL: test_x (test_bad.BadTests.test_x)\nFAILED (failures=1)'
}
# Bug it catches: a failed subtest's line ends with its message and parameters in brackets of their own,
# `(test_bad.BadTests.test_x) [m] (x=1)`; the last brackets were read as the module, x=1 named no file, and the whole
# build failed.
t_testmapsubfail() {
  pyfailmap 'python -m unittest discover -s tests' $'..F\nFAIL: test_x (test_bad.BadTests.test_x) [m (1)] (x=1)\nFAILED (failures=1)'
}
