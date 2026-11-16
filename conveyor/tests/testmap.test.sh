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
t_testmapnode() {
  nodemain
  mapeng 'mapbuild "$R"' || fail "the map was not made: $(cat "$T/$CASE/eng.out")"
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

# Bug it catches: a test file a card adds stayed out of the map, so a later change to what it covers did not run it.
# The card's run that passes maps it (alone, under coverage): src/b.js now lists it beside test/b.test.js.
t_testmapnew() {
  nodemain; nodemap
  maprun "printf \"const t = require('node:test'); const b = require('../src/b.js');\\nt('d', () => b());\\n\" > test/d.test.js"
  [ "$(cat "$STUB/got")" = test/d.test.js ] || fail "the new test was not run: $(cat "$STUB/got")"
  mapis '.sources["src/b.js"] == ["test/b.test.js", "test/d.test.js"] and (.tests | index("test/d.test.js"))' "the new test is not in the map after its first run"
  grep -qF 'conveyor: test map: mapped test/d.test.js on its first run' "$T/$CASE/cards/c7.test" || fail "the run did not say it mapped the new test: $(cat "$T/$CASE/cards/c7.test")"
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
# without them, and writes the report coverage.py writes.
t_testmappython() {
  setup '[]'
  mkdir -p "$R/src" "$R/tests" && echo x > "$R/pyproject.toml" && for f in src/calc.py src/util.py tests/test_calc.py tests/test_other.py; do echo x > "$R/$f"; done
  git -C "$R" add -A && git -C "$R" commit -qm python || fail "main's files could not be committed"
  cat > "$STUB/coverage" <<'EOF'
#!/usr/bin/env bash
case $1 in
  run) grep -qx 'dynamic_context = test_function' "${2#--rcfile=}" && echo "${*:3}" > "$STUB/cov-run" ;;
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
  [ "$(cat "$STUB/cov-run")" = '-m pytest -q' ] || fail "coverage did not run the test command's pytest: $(cat "$STUB/cov-run")"
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
t_testmaparea() {
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
    case $5 in ./calc) printf "mode: set\nexample.com/m/calc/calc.go:1.1,2.2 1 1\nexample.com/m/util/util.go:1.1,2.2 1 1\nexample.com/m/other/other.go:1.1,2.2 1 0\n" > "$f" ;;
      ./util) printf "mode: set\nexample.com/m/util/util.go:1.1,2.2 1 1\n" > "$f" ;; *) exit 4 ;; esac ;;
  *) exit 2 ;;
esac' '{"calc/calc.go": ["calc/calc_test.go"], "util/util.go": ["calc/calc_test.go", "util/util_test.go"]}' \
    go.mod calc/calc.go calc/calc_test.go util/util.go util/util_test.go other/other.go
  # A Go whole run cannot collect coverage a test file at a time, so a due map was never made again after a whole run
  # (the test on main, the release check): after it passes, the packages' tests run under coverage and remake it.
  tune '.test.command = "go test ./..."'
  mapeng 'mapcovon "$R" && maprefresh "$R"' && grep -qF 'test map: made again' "$T/$CASE/eng.out" || fail "a due Go map was not made again: $(cat "$T/$CASE/eng.out")"
  mapis '.command == "go test ./..." and .sources == {"calc/calc.go": ["calc/calc_test.go"], "util/util.go": ["calc/calc_test.go", "util/util_test.go"]}' \
    "the due Go map was not made again from the coverage run"
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
