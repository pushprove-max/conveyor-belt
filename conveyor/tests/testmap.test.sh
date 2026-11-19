#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#150): the test map (lib/testmap.sh), which test files cover which source files, made with the
# language's own coverage tool, and a card's list of tests (testsel()) read against it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Runs <command> (engine functions, eval'd) as the loop's commands do, in main's checkout, its output in $T/$CASE/eng.out.
mapeng() { # <command>
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1; eval "$1" ) > "$T/$CASE/eng.out" 2>&1
}
# Main as a Node project: src/a.js and src/b.js, each read by its own test (test/a.test.js, test/b.test.js), and
# src/util.js, a helper every test reads, test/c.test.js too. A file runs alone with node --test (test.fileCommand);
# the pack's test command is $STUB/list-cmd, which writes the arguments it was given to $STUB/got (test.list args).
nodemain() {
  local t
  local -x WHOLESUITE=true # The old fixture: the rule Whole suite in a card on, so a change to a file most tests share runs the whole suite.
  setup '[]'
  mkdir -p "$R/src" "$R/test" && echo '{"name": "fixture"}' > "$R/package.json" || fail "the fixture"
  for t in a b; do echo "module.exports = () => '$t';" > "$R/src/$t.js"; done
  echo 'module.exports = (x) => x;' > "$R/src/util.js"
  for t in a b; do printf "const t = require('node:test'); const f = require('../src/%s.js'); const u = require('../src/util.js');\nt('%s', () => u(f()));\n" "$t" "$t" > "$R/test/$t.test.js"; done
  printf "const t = require('node:test'); const u = require('../src/util.js');\nt('c', () => u(1));\n" > "$R/test/c.test.js"
  git -C "$R" add -A && git -C "$R" commit -qm node || fail "main's files could not be committed"
  echo 'printf "%s\n" "$*" > "$STUB/got"' > "$STUB/list-cmd"
  tune '.test.list = "args" | .test.command = "bash \"$STUB/list-cmd\"" | .test.fileCommand = "node --test"'
}
# Card c7's test step, its own tests() as card() runs it, on <change> (a shell edit staged in its worktree on main);
# its test line's list in $T/$CASE/list.
maprun() { # <change>
  local wt=$T/$CASE/cards/c7
  git -C "$R" worktree add -q --detach "$wt" && (cd "$wt" && eval "$1") && git -C "$wt" add -A || fail "the card's change could not be staged"
  mapeng 'tests "'"$wt"'" && testrec "'"$wt"'" 0 0 | jq -c .list > "'"$T/$CASE/list"'"' || fail "the test step failed: $(cat "$T/$CASE/eng.out")"
}
# The map mapbuild makes of nodemain's files (t_testmapnode proves it), written as it is, on main's commit: the other
# cases start from it and pay for no run of the suite.
nodemap() {
  jq -n --arg c "$(git -C "$R" rev-parse HEAD)" --arg cmd "$(jq -r .test.command "$R/.conveyor/project.json")" '{commit: $c, command: $cmd,
    language: "node", made: "2026-11-16T00:00:00Z", seconds: 1, tests: ["test/a.test.js", "test/b.test.js", "test/c.test.js"],
    sources: {"src/a.js": ["test/a.test.js"], "src/b.js": ["test/b.test.js"], "src/util.js": ["test/a.test.js", "test/b.test.js", "test/c.test.js"]}}' \
    > "$R/.conveyor/test-map.json" || fail "the map could not be written"
}
mapis() { # <jq filter that must hold of the made map> <what>
  jq -e "$1" "$R/.conveyor/test-map.json" >/dev/null 2>&1 || fail "$2: $(cat "$R/.conveyor/test-map.json" 2>&1)"
}

# Bug it catches: with no map, a change to src/a.js could only be matched to tests by name, and a change to a file no
# test is named after ran the whole suite. The map, made with V8 coverage a test file at a time, sends src/a.js to
# test/a.test.js alone, and the test line says the list came from the map, made on the commit the card is on.
# Bug it catches too (#176): /units could not show how far the map's run was. Each test file's run sees the run's
# progress file say how many files ran before it, of how many, with the engine's process and the start; a run that
# made the map leaves none (a run still shown as going).
t_testmapnode() {
  nodemain
  printf '%s\n' 'jq -c . "$R/.conveyor/test-map.run.json" >> "$STUB/seen"' 'exec node --test "$@"' > "$STUB/seen.sh"
  tune '.test.fileCommand = "bash \"$STUB/seen.sh\""'
  mapeng 'mapbuild "$R"' || fail "the map was not made: $(cat "$T/$CASE/eng.out")"
  jq -se 'map([.done, .of]) == [[0, 3], [1, 3], [2, 3]] and all(.pid > 1 and .started > 0)' "$STUB/seen" > /dev/null \
    || fail "the run's progress was not written as each file ran: $(cat "$STUB/seen" 2>&1)"
  [ ! -e "$R/.conveyor/test-map.run.json" ] || fail "a run that made the map left its progress: $(cat "$R/.conveyor/test-map.run.json")"
  grep -qE '^conveyor: wrote the test map .* with V8 coverage: 3 source files, 3 test files, in [0-9]+s$' "$T/$CASE/eng.out" \
    || fail "the map's run did not say what it mapped and how long it took: $(cat "$T/$CASE/eng.out")"
  mapis '.sources == {"src/a.js": ["test/a.test.js"], "src/b.js": ["test/b.test.js"], "src/util.js": ["test/a.test.js", "test/b.test.js", "test/c.test.js"]}
    and .tests == ["test/a.test.js", "test/b.test.js", "test/c.test.js"] and .language == "node"' "the map is not what each test read"
  maprun 'echo "// more" >> src/a.js'
  [ "$(cat "$STUB/got")" = test/a.test.js ] || fail "a change to src/a.js did not run test/a.test.js alone: $(cat "$STUB/got")"
  [ "$(cat "$T/$CASE/list")" = '{"mode":"changed","files":1,"by":"map","age":0}' ] || fail "the test line does not say the map chose: $(cat "$T/$CASE/list")"
}

# Bug it catches: a change to a helper that every test reads ran only the tests named after it (none), or a few, so a
# break in most tests landed unseen. The map marks it shared by most tests: the whole suite runs, and says why.
t_testmapshared() {
  nodemain; nodemap
  maprun 'echo "// more" >> src/util.js'
  [ -z "$(cat "$STUB/got")" ] || fail "a change to the shared helper was given a list: $(cat "$STUB/got")"
  [ "$(cat "$T/$CASE/list")" = '{"mode":"whole","why":"src/util.js: shared by most tests (map)"}' ] || fail "the whole suite's why is not the map's: $(cat "$T/$CASE/list")"
}

# Main as nodemain with the map, and .conveyor/test-links.json linking src/util.js and src/a.js to test/c.test.js.
linkmain() {
  nodemain; nodemap
  echo '{"src/util.js": ["test/c.test.js"], "src/a.js": ["test/c.test.js"]}' > "$R/.conveyor/test-links.json" \
    && git -C "$R" add -f .conveyor/test-links.json && git -C "$R" commit -qm links || fail "the links could not be committed"
}
# Bug it catches: a link to the shared helper returned its one linked test before the map's shared check, so a break
# in most tests landed unseen. The map's shared check holds, links or not: the whole suite runs.
t_testmaplinkshared() {
  linkmain
  maprun 'echo "// more" >> src/util.js'
  [ "$(cat "$T/$CASE/list")" = '{"mode":"whole","why":"src/util.js: shared by most tests (map)"}' ] || fail "a link to the shared helper ran only its linked test: $(cat "$T/$CASE/list") $(cat "$STUB/got")"
}
# Bug it catches: a link to src/a.js replaced the tests the map says cover it, so test/a.test.js did not run. Both run.
t_testmaplinkcover() {
  linkmain
  maprun 'echo "// more" >> src/a.js'
  [ "$(cat "$STUB/got")" = 'test/a.test.js test/c.test.js' ] || fail "the linked and the covering tests did not both run: $(cat "$STUB/got")"
  jq -e '.by == "map"' "$T/$CASE/list" >/dev/null || fail "the list does not say the map found its tests: $(cat "$T/$CASE/list")"
}

# Bug it catches: a test file a card adds stayed out of the map, so a later change to what it covers did not run it.
# The card's run that passes maps it (alone, under coverage): src/b.js now lists it beside test/b.test.js.
t_testmapnew() {
  nodemain; nodemap
  maprun "printf \"const t = require('node:test'); const b = require('../src/b.js');\\nt('d', () => b());\\n\" > test/d.test.js"
  [ "$(cat "$STUB/got")" = test/d.test.js ] || fail "the new test was not run: $(cat "$STUB/got")"
  mapis '.sources["src/b.js"] == ["test/b.test.js", "test/d.test.js"] and (.tests | index("test/d.test.js"))' "the new test is not in the map after its first run"
  grep -qF 'conveyor: test map: mapped test/d.test.js on its first run' "$T/$CASE/cards/c7.test" || fail "the run did not say it mapped the new test: $(cat "$T/$CASE/cards/c7.test")"
}

# Bug it catches (#344): testsel() gave the made test map to jq as one argument, so a map over the system's argument
# limit (about 1 MB on macOS; on Linux 128 KB for one argument) failed with "Argument list too long", and no card made
# its list of tests. Under a lowered limit (ulimit -s 4096: 1 MB for all arguments), a card's list is still made from
# a map over 2 MB: the change to src/a.js runs test/a.test.js, by the map.
t_testmapbig() {
  local wt=$T/$CASE/cards/c7
  nodemain
  jq -n --arg c "$(git -C "$R" rev-parse HEAD)" '{commit: $c, language: "node", tests: ["test/a.test.js", "test/b.test.js", "test/c.test.js"],
    sources: ({"src/a.js": ["test/a.test.js"]} + ([range(40000) | {key: "src/generated/module/folder/file-\(.).js", value: ["test/b.test.js"]}] | from_entries))}' \
    > "$R/.conveyor/test-map.json" && [ "$(wc -c < "$R/.conveyor/test-map.json")" -gt 2097152 ] || fail "the map over 2 MB could not be written"
  git -C "$R" worktree add -q --detach "$wt" && echo '// more' >> "$wt/src/a.js" && git -C "$wt" add -A || fail "the card's change could not be staged"
  mapeng 'ulimit -s 4096 && tests "'"$wt"'" && testrec "'"$wt"'" 0 0 | jq -c .list > "'"$T/$CASE/list"'"' || fail "the test step failed: $(cat "$T/$CASE/eng.out")"
  [ "$(cat "$STUB/got")" = test/a.test.js ] && jq -e '.mode == "changed" and .by == "map"' "$T/$CASE/list" >/dev/null \
    || fail "the card's list was not made from the big map: $(cat "$STUB/got" "$T/$CASE/list" "$T/$CASE/eng.out" 2>&1 | tail -n 5)"
}

# Bug it catches (#155): a Node test file the pack's tests.patterns name but not named *.test.*, *.spec.* or under
# __tests__/ (src/test-a.mjs, checks/one.js) never entered the map, made (mapbuild()) or added (mapnew()), as a fixed
# filename filter dropped it. The map's Node tests are the pack's test files that are JS or TS files.
t_testmapfiles() {
  setup '[]'; tune '.tests.patterns = ["src/test-*.mjs", "checks/"]'
  mkdir -p "$R/src" "$R/checks" && for f in src/test-a.mjs src/a.mjs checks/one.js checks/notes.md; do echo x > "$R/$f"; done
  git -C "$R" add -A && git -C "$R" commit -qm files || fail "main's files could not be committed"
  mapeng 'maptests "$R" node' && [ "$(cat "$T/$CASE/eng.out")" = $'checks/one.js\nsrc/test-a.mjs' ] \
    || fail "the map's Node tests are not the pack's JS test files: $(cat "$T/$CASE/eng.out")"
}

# Bug it catches: a map made under another test command, or long ago, kept sending changes to the tests of code that
# moved. Such a map is due (mapdue()), with why; one of this command and commit is not.
t_testmapdue() {
  nodemain; nodemap
  ! mapeng 'mapdue "$R"' || fail "a map just made is due: $(cat "$T/$CASE/eng.out")"
  tune '.test.mapAge = 1'; echo b >> "$R/a.txt"; git -C "$R" commit -qam b; echo c >> "$R/a.txt"; git -C "$R" commit -qam c
  mapeng 'mapdue "$R"' && [ "$(cat "$T/$CASE/eng.out")" = 'it is 2 commits old (test.mapAge: 1)' ] || fail "a map 2 commits old is not due: $(cat "$T/$CASE/eng.out")"
  tune '.test.mapAge = 5 | .test.command = "npm test"'
  mapeng 'mapdue "$R"' && grep -qF 'it was made under another test command' "$T/$CASE/eng.out" || fail "a map of another command is not due: $(cat "$T/$CASE/eng.out")"
  # What setup says the map's run may cost: the last whole-suite run's seconds, added up over its files.
  mkdir -p "$ST" && echo '{"time": "t", "how": "full", "sha": "s", "files": {"a": {"sec": 40.4}, "b": {"sec": 2}}}' > "$ST/suiteruns.jsonl" || fail "the suite run"
  mapeng mapcost && [ "$(cat "$T/$CASE/eng.out")" = 'It takes about 42s or more: the last whole-suite run took 42s.' ] || fail "the cost is not the last whole run's: $(cat "$T/$CASE/eng.out")"
}

# Bug it catches: a Python project got no map. coverage.py runs the suite once with dynamic contexts (a test function
# each), and each context's module names its test file: src/calc.py goes to tests/test_calc.py alone, and src/util.py,
# which both tests read, is shared. The stub coverage on PATH refuses a run without test_function contexts or a report
# without them, and writes the report coverage.py writes. While the suite runs, the test files its output names are
# counted (bug, #182: the count stayed at 0 until the whole suite and its report had ended), and a quiet command
# (pytest -q, which prints dots alone) is run at a verbosity that names them (bug: a quiet run's count stayed at 0).
t_testmappython() {
  setup '[]'
  mkdir -p "$R/src" "$R/tests" && echo x > "$R/pyproject.toml" && for f in src/calc.py src/util.py tests/test_calc.py tests/test_other.py; do echo x > "$R/$f"; done
  git -C "$R" add -A && git -C "$R" commit -qm python || fail "main's files could not be committed"
  cat > "$STUB/coverage" <<'EOF'
#!/usr/bin/env bash
case $1 in
  run) grep -qx 'dynamic_context = test_function' "${2#--rcfile=}" && echo "${*:3}" > "$STUB/cov-run" || exit 4
    # As pytest: quiet (-q last) prints only dots; at verbosity 0 each test file's path, then its dots.
    case " ${*:3} " in *' -q --verbosity=0 '*) echo 'tests/test_calc.py ..' ;; *) echo '..' ;; esac
    for i in $(seq 50); do jq -e '.done == 1 and .of == 2' .conveyor/test-map.run.json > /dev/null 2>&1 && break; sleep 0.1; done
    cat .conveyor/test-map.run.json > "$STUB/cov-prog" ;;
  json) [[ " $* " == *" --show-contexts "* ]] || exit 3; o=${!#}
    echo '{"files": {"src/calc.py": {"contexts": {"1": [""], "2": ["tests.test_calc.test_add"]}},
      "src/util.py": {"contexts": {"1": ["tests.test_calc.test_add", "test_other.TestOther.test_x"]}},
      "tests/test_calc.py": {"contexts": {"3": ["tests.test_calc.test_add"]}}}}' > "$o" ;;
  *) exit 2 ;;
esac
EOF
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" > "$STUB/got"' > "$STUB/pytest" && chmod +x "$STUB/coverage" "$STUB/pytest" || fail "the stubs"
  tune '.test.list = "args" | .test.command = "pytest -q"'
  mapeng 'mapbuild "$R"' || fail "the map was not made: $(cat "$T/$CASE/eng.out")"
  [ "$(cat "$STUB/cov-run")" = '-m pytest -q --verbosity=0' ] || fail "coverage did not run the test command's pytest, at a verbosity that names its test files: $(cat "$STUB/cov-run")"
  jq -e '.done == 1 and .of == 2' "$STUB/cov-prog" > /dev/null || fail "the run did not count the test file its output named while it ran: $(cat "$STUB/cov-prog")"
  mapis '.sources == {"src/calc.py": ["tests/test_calc.py"], "src/util.py": ["tests/test_calc.py", "tests/test_other.py"]} and .language == "python"' "the contexts did not map to their test files"
  maprun 'echo y >> src/calc.py'
  [ "$(cat "$STUB/got")" = '-q tests/test_calc.py' ] || fail "a change to src/calc.py did not run tests/test_calc.py alone: $(cat "$STUB/got")"
  [ "$(jq -r .by "$T/$CASE/list")" = map ] || fail "the test line does not say the map chose: $(cat "$T/$CASE/list")"
}

# Bug it catches: a project with no tool, or with a map of its own, got no map or a wrong one. A project with no
# coverage tool the map knows is told so, and keeps finding its tests by name; a map of its own
# (test.map: a path) in area lines, as .conveyor/engine-areas.json holds them, is read: a case file named by its name
# is the tracked test file of that name, and an area whose tests are "all" is shared. One that names a case file
# there is none of fails the read, saying which (the area-map check).
# WHOLESUITE: the per-file fixture's own a.test.sh would be a second tracked a.test.sh, so the name would not resolve.
t_testmaparea() { local -x WHOLESUITE=true
  setup '[]'
  mapeng 'mapbuild "$R"'; grep -qxF "conveyor: no test map: its language has no coverage tool the test map knows (Node, Python, Go, Rust or Ruby); a card's tests are found by name" "$T/$CASE/eng.out" \
    || fail "a project with no known tool was not told: $(cat "$T/$CASE/eng.out")"
  mkdir -p "$R/lib" "$R/tests" && for f in lib/a.sh lib/b.sh lib/core.sh tests/a.test.sh tests/b.test.sh; do echo x > "$R/$f"; done
  printf '%s\n' '{"outside": "lib/README.md"}' '{"area": "a", "test": "a.test.sh"}' '{"area": "a", "file": "lib/a.sh"}' \
    '{"area": "b", "test": "tests/b.test.sh"}' '{"area": "b", "file": "lib/b.sh"}' \
    '{"area": "core", "tests": "all"}' '{"area": "core", "why": "every case runs it"}' '{"area": "core", "file": "lib/core.sh"}' > "$R/areas.json"
  git -C "$R" add -A && git -C "$R" commit -qm areas || fail "main's files could not be committed"
  tune '.test.map = "areas.json"'
  mapeng 'mapread "$R"' && [ "$(jq -c '[.sources, .shared, .age]' "$T/$CASE/eng.out")" = '[{"lib/a.sh":["tests/a.test.sh"],"lib/b.sh":["tests/b.test.sh"]},["lib/core.sh"],null]' ] \
    || fail "the area lines were not read as a map: $(cat "$T/$CASE/eng.out")"
  echo '{"area": "a", "test": "gone.test.sh"}' >> "$R/areas.json"
  ! mapeng 'mapread "$R"' && grep -qF 'areas.json: gone.test.sh is named, but there is no one tracked test file of that name' "$T/$CASE/eng.out" \
    || fail "a map naming a case file there is none of was read: $(cat "$T/$CASE/eng.out")"
}

# Go, Rust and Ruby, each with its tool stubbed on PATH as it reports coverage: <files> in main, committed, the stub
# <tools> (space-separated) each written from <script>, the map made (mapbuild()), and its sources must be <want>.
stubmap() { # <tools> <script> <want> <files>...
  local f t s=$2 w=$3 ts; read -ra ts <<<"$1"; shift 3
  # The old fixture, for the Ruby case: mapone() runs a spec file through test.fileCommand when the pack has one, so the
  # per-file fixture's would run in place of the rspec stub. Go and Rust run go test and cargo llvm-cov directly.
  local -x WHOLESUITE=true
  setup '[]'
  for f in "$@"; do mkdir -p "$R/$(dirname "$f")" && echo x > "$R/$f"; done
  git -C "$R" add -A && git -C "$R" commit -qm files || fail "main's files could not be committed"
  for t in "${ts[@]}"; do printf '#!/usr/bin/env bash\n%s\n' "$s" > "$STUB/$t" && chmod +x "$STUB/$t" || fail "the stub $t"; done
  mapeng 'mapbuild "$R"' || fail "the map was not made: $(cat "$T/$CASE/eng.out")"
  mapis ".sources == $w" "the map is not what the tool reported"
}

# Bug it catches: a Go project got no map. Each package's tests run with a coverage profile of the whole module
# (-coverpkg=./...): a file with a count above 0 is a source of that package's test files; one at 0 is not.
t_testmapgo() {
  stubmap go 'case "$1 $2" in
  "list -m") echo example.com/m ;;
  "test -count=1") f=${4#-coverprofile=}; [ "$3" = -coverpkg=./... ] || exit 3
    jq -c "[.done, .of]" "$R/.conveyor/test-map.run.json" >> "$STUB/seen"
    case $5 in ./calc) printf "mode: set\nexample.com/m/calc/calc.go:1.1,2.2 1 1\nexample.com/m/util/util.go:1.1,2.2 1 1\nexample.com/m/other/other.go:1.1,2.2 1 0\n" > "$f" ;;
      ./util) printf "mode: set\nexample.com/m/util/util.go:1.1,2.2 1 1\n" > "$f" ;; *) exit 4 ;; esac ;;
  *) exit 2 ;;
esac' '{"calc/calc.go": ["calc/calc_test.go"], "util/util.go": ["calc/calc_test.go", "util/util_test.go"]}' \
    go.mod calc/calc.go calc/calc_test.go util/util.go util/util_test.go other/other.go
  # The run's progress (#176) counts a package's test files once its package has run.
  [ "$(cat "$STUB/seen")" = $'[0,2]\n[1,2]' ] || fail "the Go run's progress was not a package at a time: $(cat "$STUB/seen")"
  # A Go whole run cannot collect coverage a test file at a time, so a due map was never made again after a whole run
  # (the test on main, the release check): after it passes, the packages' tests run under coverage and remake it.
  tune '.test.command = "go test ./..."'
  mapeng 'mapcovon "$R" && maprefresh "$R"' && grep -qF 'test map: made again' "$T/$CASE/eng.out" || fail "a due Go map was not made again: $(cat "$T/$CASE/eng.out")"
  mapis '.command == "go test ./..." and .sources == {"calc/calc.go": ["calc/calc_test.go"], "util/util.go": ["calc/calc_test.go", "util/util_test.go"]}' \
    "the due Go map was not made again from the coverage run"
  [ ! -e "$R/.conveyor/test-map.run.json" ] || fail "a refresh that made the map left its progress: $(cat "$R/.conveyor/test-map.run.json")"
}

# Bug it catches (#176): a map's run that failed showed in /units as no map, or as still running. It leaves why it
# failed, which the map's state (mapstate(), what /units reads) gives.
t_testmapfail() {
  setup '[]'
  mkdir -p "$R/calc" && for f in go.mod calc/calc.go calc/calc_test.go; do echo x > "$R/$f"; done
  git -C "$R" add -A && git -C "$R" commit -qm files || fail "main's files could not be committed"
  printf '%s\n' '#!/usr/bin/env bash' '[ "$1 $2" != "list -m" ] || { echo example.com/m; exit 0; }' 'exit 1' > "$STUB/go" && chmod +x "$STUB/go" || fail "the stub go"
  ! mapeng 'mapbuild "$R"' || fail "a run that failed made a map: $(cat "$T/$CASE/eng.out")"
  mapeng 'mapstate "$R"' && jq -e '.state == "failed" and (.why | test("^the run with go test -coverprofile failed after [0-9]+s: no test file could be mapped .*; the first, calc/calc_test\\.go: failed under coverage$"))' \
    "$T/$CASE/eng.out" > /dev/null || fail "the failed run's state does not say why: $(cat "$T/$CASE/eng.out")"
}

# Bug it catches (#327): one test file that failed under the map's run stopped the build, and the project had no map
# at all. The two files that pass are mapped; the one that fails is listed as not mapped with the end of its output,
# which the Board's part (mapboard()) gives; the build says how many it could not map.
t_testmapskip() {
  nodemain
  printf '%s\n' 'process.exit(1);' > "$R/test/c.test.js"
  git -C "$R" commit -qam c || fail "the failing test could not be committed"
  mapeng 'mapbuild "$R" && mapboard "$R" > "'"$T/$CASE/board"'"' || fail "one failing file stopped the build: $(cat "$T/$CASE/eng.out")"
  grep -qE '^conveyor: wrote the test map .*: 3 source files, 2 test files, 1 not mapped .*, in [0-9]+s$' "$T/$CASE/eng.out" \
    || fail "the build did not say it left a file not mapped: $(cat "$T/$CASE/eng.out")"
  mapis '.tests == ["test/a.test.js", "test/b.test.js"] and .sources["src/a.js"] == ["test/a.test.js"]
    and (.notMapped | length == 1 and .[0].file == "test/c.test.js" and (.[0].why | startswith("failed under coverage; the end of its output:\n") and contains("✖ test/c.test.js") and endswith("test failed'"'"'")))' \
    "the two files that pass are not mapped, or the failing one is not listed with its output"
  jq -e '.state == "made" and .notMapped[0].file == "test/c.test.js" and (.notMapped[0].why | endswith("test failed'"'"'"))' "$T/$CASE/board" > /dev/null \
    || fail "the Board's part does not list the file not mapped with why: $(cat "$T/$CASE/board")"
}

# Bug it catches (#327): with every test file failing, the build must still fail, saying so, not write an empty map.
t_testmapallfail() {
  nodemain
  printf '%s\n' 'echo "cannot run $1"; exit 1' > "$STUB/fails.sh"
  tune '.test.fileCommand = "bash \"$STUB/fails.sh\""'
  ! mapeng 'mapbuild "$R"' || fail "a run where every file failed made a map: $(cat "$T/$CASE/eng.out")"
  [ ! -e "$R/.conveyor/test-map.json" ] || fail "a run where every file failed wrote a map: $(cat "$R/.conveyor/test-map.json")"
  mapeng 'mapstate "$R"' && jq -e '.state == "failed" and (.why | test("^the run with V8 coverage failed after [0-9]+s: no test file could be mapped .*; the first, test/a\\.test\\.js: failed under coverage$"))' \
    "$T/$CASE/eng.out" > /dev/null || fail "the failed run's state does not say why: $(cat "$T/$CASE/eng.out")"
}

# Bug it catches (#327): a Claude Code mod test (it imports claude-code/testing) was run under node --test, failed,
# and stopped the build. It is left out before it runs, and listed as not mapped with why.
t_testmapother() {
  nodemain
  printf '%s\n' "import { test } from 'claude-code/testing';" "test('mod', () => {});" > "$R/test/mod.test.tsx"
  printf '%s\n' 'echo "$1" >> "$STUB/ran"' 'exec node --test "$@"' > "$STUB/ran.sh"
  tune '.test.fileCommand = "bash \"$STUB/ran.sh\""'
  mapeng 'd=$(mktemp -d) && mapcollect "$R" node "$d" test/mod.test.tsx test/a.test.js > /dev/null && cat "$d/skipped"' \
    || fail "the run failed: $(cat "$T/$CASE/eng.out")"
  [ "$(cat "$STUB/ran")" = test/a.test.js ] || fail "the mod test was run, or the other was not: $(cat "$STUB/ran")"
  jq -e '.file == "test/mod.test.tsx" and (.why | test("claude-code/testing"))' "$T/$CASE/eng.out" > /dev/null \
    || fail "the mod test is not listed as not mapped with why: $(cat "$T/$CASE/eng.out")"
}

# Bug it catches (#176): /units could not tell a map not made yet from one made (and how far behind main), one turned
# off, one being made, or one whose run was killed (its process gone) and so will never end.
t_testmapstate() {
  local dead
  setup '[]'
  echo x > "$R/a.js" && git -C "$R" add -A && git -C "$R" commit -qm a || fail "main's files could not be committed"
  sleep 0 & dead=$!; wait "$dead" # sleep: no time passes; it only gives the pid of a process that has ended
  mapeng 'mapstate "$R"
    jq -n --arg c "$(git -C "$R" rev-parse HEAD)" "{commit: \$c, sources: {\"a.js\": [\"t/a.test.js\", \"t/b.test.js\"], \"b.js\": [\"t/b.test.js\"]}}" > "$(mappath)"
    echo y >> "$R/a.js" && git -C "$R" commit -qam y && mapstate "$R"
    mapend "an earlier run failed" && tune ".test.map = \"off\"" && mapstate "$R"
    echo "{\"pid\": $$, \"started\": 100, \"done\": 2, \"of\": 5}" > "$(mapprogpath)" && mapstate "$R"
    tune "del(.test.map)" && echo "{\"pid\": '"$dead"', \"started\": 100, \"done\": 2, \"of\": 5}" > "$(mapprogpath)" && mapstate "$R"' \
    || fail "the states could not be read: $(cat "$T/$CASE/eng.out")"
  # Turned off, a failed run before is no matter; a run going is shown whatever the setting.
  [ "$(cat "$T/$CASE/eng.out")" = '{"state":"none"}
{"state":"made","sources":2,"tests":2,"age":1}
{"state":"off"}
{"state":"running","done":2,"of":5,"started":100}
{"state":"failed","why":"its run stopped before it ended"}' ] || fail "the map's states are not these: $(cat "$T/$CASE/eng.out")"
}

# Bug it catches (#176): a refresh of a Node or Python map is the whole run on main itself, which said nothing of how
# far it was; and a whole run that failed left the map shown as being made. While it runs, the test files run so far
# are counted; mapcovoff() stops the count, and a run that makes no map says why. node --test marks no file as ended in
# its output: a file is counted once the V8 coverage file of its process is written whole (bug: the count read only
# the engine runner's `-- ok` marks, so it stayed at 0 for node --test).
t_testmaprefresh() {
  nodemain; nodemap; tune '.test.command = "npm test"'
  # test/a.test.js's process has ended; test/b.test.js's file is still being written. The count is looked at for up to 5 s.
  mapeng 'mapcovon "$R" > /dev/null
    echo "{\"result\": [{\"url\": \"file://$(pwd -P)/test/a.test.js\"}, {\"url\": \"file://$(pwd -P)/src/a.js\"}]}" > "$R.mapcov/v8/coverage-1.json"
    echo "{\"result\": [{\"url\": \"file://$(pwd -P)/test/b.test.js\"" > "$R.mapcov/v8/coverage-2.json"
    for i in $(seq 50); do s=$(mapstate "$R"); [[ $s != *"\"done\":1"* ]] || break; sleep 0.1; done; echo "$s"; mapcovoff
    mapstop "$R" "the whole test on main failed"; mapstate "$R"; jobs -p | wc -l' || fail "the refresh could not run: $(cat "$T/$CASE/eng.out")"
  sed -n 1p "$T/$CASE/eng.out" | jq -e '.state == "running" and .done == 1 and .of == 3' > /dev/null \
    || fail "the whole run's progress was not counted from its coverage files: $(cat "$T/$CASE/eng.out")"
  [ "$(sed -n '2,$p' "$T/$CASE/eng.out")" = $'{"state":"failed","why":"the whole test on main failed"}\n0' ] \
    || fail "a failed whole run did not say so, or its count kept running: $(cat "$T/$CASE/eng.out")"
}

# Bug it catches (#327): a Node map made again from the whole run's coverage dropped the files the build could not
# map, though the run mapped them no more than before; the Board then said nothing of them. A file the run does map
# (test/b.test.js) leaves the list, or the Board keeps a reason that is no longer true.
t_testmaprefreshkeep() {
  nodemain; nodemap; tune '.test.command = "npm test"'
  jq '.tests -= ["test/b.test.js", "test/c.test.js"]
    | .notMapped = [{file: "test/b.test.js", why: "it failed once"}, {file: "test/c.test.js", why: "it failed"}, {file: "test/gone.test.js", why: "gone"}]' \
    "$R/.conveyor/test-map.json" > "$T/$CASE/m" && mv "$T/$CASE/m" "$R/.conveyor/test-map.json" || fail "the map could not be written"
  mapeng 'mapcovon "$R" > /dev/null && mapcovoff
    for t in a b; do echo "{\"result\": [{\"url\": \"file://$(pwd -P)/test/$t.test.js\"}, {\"url\": \"file://$(pwd -P)/src/$t.js\"}]}" > "$R.mapcov/v8/coverage-$t.json"; done
    maprefresh "$R"' && grep -qF 'test map: made again' "$T/$CASE/eng.out" || fail "the refresh made no map: $(cat "$T/$CASE/eng.out")"
  mapis '.tests == ["test/a.test.js", "test/b.test.js"] and .notMapped == [{file: "test/c.test.js", why: "it failed"}]' \
    "the refresh dropped the file not mapped, or kept one that is no test file now or that it mapped"
}

# Bug it catches (#176): a Python map's refresh counted only the engine runner's `-- ok` marks, so pytest's run stayed
# at 0. The files the run's output names so far are counted: pytest's file path, unittest -v's module (tests.test_b).
t_testmaprefreshpy() {
  setup '[]'
  mkdir -p "$R/tests" && for f in pyproject.toml tests/test_a.py tests/test_b.py tests/test_c.py; do echo x > "$R/$f"; done
  git -C "$R" add -A && git -C "$R" commit -qm python || fail "main's files could not be committed"
  jq -n --arg c "$(git -C "$R" rev-parse HEAD)" '{commit: $c, command: "an older command", language: "python", tests: [], sources: {}}' \
    > "$R/.conveyor/test-map.json" && tune '.test.command = "pytest"' || fail "the map could not be written"
  printf '%s\n' 'tests/test_a.py ..F.                    [ 40%]' 'test_x (tests.test_b.TestB.test_x) ... ok' > "$R.test"
  mapeng 'mapcovon "$R" > /dev/null
    for i in $(seq 50); do s=$(mapstate "$R"); [[ $s != *"\"done\":2"* ]] || break; sleep 0.1; done; echo "$s"; mapcovoff' \
    || fail "the refresh could not run: $(cat "$T/$CASE/eng.out")"
  jq -e '.state == "running" and .done == 2 and .of == 3' "$T/$CASE/eng.out" > /dev/null \
    || fail "the Python run's progress was not counted from its output: $(cat "$T/$CASE/eng.out")"
}

# Bug it catches: a Rust project got no map. Each test binary (tests/<name>.rs) runs under cargo llvm-cov: a file
# with lines covered is its source; one with none is not.
t_testmaprust() {
  stubmap cargo '[ "$1" = llvm-cov ] || exit 2; [ "$2" != --version ] || exit 0
[ "$*" = "llvm-cov --json --summary-only --test a" ] || exit 3
p=$(pwd -P); echo "{\"data\": [{\"files\": [{\"filename\": \"$p/src/lib.rs\", \"summary\": {\"lines\": {\"covered\": 3}}},
  {\"filename\": \"$p/src/b.rs\", \"summary\": {\"lines\": {\"covered\": 0}}}]}]}"' '{"src/lib.rs": ["tests/a.rs"]}' \
    Cargo.toml src/lib.rs src/b.rs tests/a.rs
}

# Bug it catches: a Ruby project got no map. Each spec file runs with SimpleCov started first (RUBYOPT -r a file that
# starts it, writing to CONVEYOR_MAP_COV): a file with a line run is its source.
t_testmapruby() {
  # One stub is both: ruby -e (the check that SimpleCov is there) and rspec <spec file>.
  stubmap 'rspec ruby' '[ "$1" != -e ] || exit 0
h=${RUBYOPT%% *}; [ "$1" = spec/a_spec.rb ] && grep -q "SimpleCov.start" "${h#-r}" || exit 3
p=$(pwd -P); echo "{\"RSpec\": {\"coverage\": {\"$p/lib/a.rb\": {\"lines\": [null, 1, 0]}, \"$p/lib/b.rb\": {\"lines\": [null, 0]}}}}" > "$CONVEYOR_MAP_COV/.resultset.json"' \
    '{"lib/a.rb": ["spec/a_spec.rb"]}' .rspec lib/a.rb lib/b.rb spec/a_spec.rb
}
