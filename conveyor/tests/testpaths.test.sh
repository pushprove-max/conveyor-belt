#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: which paths are a project's test files (testpaths(), the pack's tests.patterns), and how setup and
# doctor find the project's convention (#137); which product files a change's inline tests are in (the pack's
# tests.inline, #140).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The engine's own functions, sourced as `run` sources them, and setup's and doctor's (lib/setup.sh), in main's
# checkout: what a card's checks and setup call, with no card run.
tpeng() { ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
  && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && . "$SRC/lib/setup.sh" && names && eval "$1" ); }
# Main's commit of the files given, each holding `x`.
tpfiles() { # <file>...: named for this file alone, as the runner sources every case file into one shell
  local f; for f; do { [[ $f != */* ]] || mkdir -p "$R/${f%/*}"; } && echo x > "$R/$f"; done
  git -C "$R" add -- "$@" && git -C "$R" commit -qm files || fail "main's files"
}

# Bug it catches: the engine knew only __tests__, .test. and .spec., so a project with any other convention had every
# test file taken for product code, and its bug cards found no test file. With no setting, the default finds the
# common conventions of the main languages, and no source file.
t_testpathsdefault() {
  setup '[]'
  local tests='test_x.py pkg/x_test.go spec/x_spec.rb src/FooTest.java a/__tests__/b.js x.test.ts y.spec.js py/a_test.py tests/x.sh test/y.sh src/test-a.mjs t/a.sh lib/a.t A/BarTests.cs' out
  out=$(tpeng "printf '%s\n' $tests src/x.py latest.go contest.py src/spec.rb Test.javax src/t.sh retest/a.sh | testpaths") || fail "testpaths failed: $out"
  [ "$(tr '\n' ' ' <<<"$out")" = "$tests " ] || fail "the default patterns did not find exactly the test files: $out"
}

# Bug it catches: a pack could not name its project's test files, and productpaths() (a change's product code) and a
# card's test files read a pattern fixed in the engine. The pack's tests.patterns replace the default: src/test-a.mjs
# is a test file and no product code, a.test.js is neither a test file now nor product code (not under productPaths).
t_testpathsset() {
  setup '[]'; tune '.tests.patterns = ["src/test-*.mjs"]'
  local out
  out=$(tpeng 'printf "%s\n" src/test-a.mjs a.test.js src/a.mjs | testpaths; printf "%s\n" src/test-a.mjs | productpaths && echo product-test
    printf "%s\n" src/a.mjs | productpaths && echo product-src; echo "$TESTGLOBS"') || fail "the engine failed: $out"
  [ "$out" = $'src/test-a.mjs\nproduct-src\nsrc/test-*.mjs' ] || fail "the pack's tests.patterns were not what decides test files and product code: $out"
}

# Bug it catches (#137): each of productpaths(), a card's test files at landing (claim.sh) and the bug-card check had a
# pattern of its own, so a fix to one left the others wrong. The issue asks that they read one helper. Which helper a
# line calls is no behaviour a run shows, so this reads the engine's source: TESTRX is read only in testpaths(), and
# no engine file outside it tests a path for .test. or .spec. to decide a change's test files.
t_testpathsone() {
  local l b
  b=$(sed -n '/^testpaths() {/,/^}/p' "$SRC/lib/issues.sh" | grep 'TESTRX')
  grep -qF 'grep -E "$@" -e "$TESTRX"' <<<"$b" || fail "testpaths() no longer matches paths with TESTRX: $b"
  l=$(grep -n 'TESTRX' "$SRC/conveyor.sh" "$SRC"/lib/*.sh "$SRC"/commands/*.sh | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' | grep -v 'TESTRX=\${x\[2\]}' | grep -vF -- "$b")
  [ -z "$l" ] || fail "TESTRX is read outside testpaths(): $l"
  grep -q 'testpaths -v | grep -Ec "\$PRODUCT"' "$SRC/lib/issues.sh" && grep -q 'diff --cached --name-only --no-renames 2>/dev/null | testpaths |' "$SRC/lib/claim.sh" \
    || fail "productpaths() or claim.sh does not read testpaths()"
  ! grep -n '(test|spec)' "$SRC/lib/issues.sh" "$SRC/lib/claim.sh" "$SRC/lib/testrun.sh" | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' \
    || fail "an engine file that finds a change's test files still has a pattern of its own"
}

# Bug it catches: setup wrote no pattern for a project whose tests the default misses. Its guess, from the names of
# the tracked files, is each convention's glob: test-*.mjs from src/test-a.mjs and src/test-b.mjs (here against the old
# fixed patterns, which miss them), never a document's (docs/test-plan.md); a file the test command names by a glob
# with no test word in its name gives its folder's glob. With the default, which covers test-*.mjs, it offers nothing.
t_testguess() {
  setup '[]'; tpfiles src/test-a.mjs src/test-b.mjs src/a.mjs docs/test-plan.md checks/one.js
  local out
  out=$(tpeng 'testguess "npm test" "[\"__tests__/\", \"*.test.*\", \"*.spec.*\"]"; echo --; testguess "node --test '\''checks/*.js'\''" "[\"test-*.mjs\"]"
    echo --; testoffer "npm test"') || fail "the guess failed: $out"
  [ "$out" = $'test-*.mjs\n--\n/checks/*.js\n--' ] || fail "setup's guess is not each convention's glob: $out"
}

# Bug it catches: doctor said nothing of patterns that find no test file, or miss the files the test command runs, so
# every bug card of the project was blocked with no word of why. Each is a missing: line naming the fix; patterns
# that match say how many tracked files.
t_testcheck() {
  setup '[]'; tpfiles checks/one.js a.test.sh
  local out
  out=$(tuned '.tests.patterns = ["nothing/"]' tpeng testcheck) && fail "doctor passed patterns that match no file: $out"
  [[ $out == "missing: test files the pack's tests.patterns match (they match no tracked file: nothing/); fix: set tests.patterns in .conveyor/project.json"* ]] || fail "the no-match line: $out"
  out=$(tuned '.test.command = "node --test checks/*.js"' tpeng testcheck) && fail "doctor passed patterns that miss the command's files: $out"
  [[ $out == "missing: tests.patterns that match the 1 file the test command names, such as checks/one.js; fix: "* ]] || fail "the command's files line: $out"
  out=$(tuned '.test.command = "node --test checks/*.js" | .tests.patterns = ["checks/", "*.test.*"]' tpeng testcheck) && [ "$out" = 'ok: the pack'"'"'s tests.patterns match 2 tracked files' ] \
    || fail "patterns that match the project's tests were not ok: $out"
}

# #140. Bug it catches: the kinds of inline tests were fixed in the engine, so a project with another kind could not
# add it. The pack's tests.inline adds a kind (go) and replaces a default one (python, here for *.pyx files alone); the
# defaults it does not name (rust) are kept, and a test file (a_test.go) is never taken for a file with inline tests.
t_inlinekinds() {
  setup '[]'; tune '.tests.inline = {go: {files: ["*.go"], start: "^func Example", end: "braces"}, python: {files: ["*.pyx"], start: "\"\"\"", end: "\"\"\""}}'
  local f out; for f in a.go a_test.go b.py c.rs d.pyx; do echo x > "$R/$f"; done
  git -C "$R" add -- a.go a_test.go b.py c.rs d.pyx || fail "the change"
  out=$(tpeng 'inlinekinds "$R" | tr "\0" "\n" | paste - - | while IFS=$'"'\t'"' read -r p k; do echo "$p $(jq -r ".files | join(\",\")" <<<"$k")"; done') \
    || fail "inlinekinds failed: $out"
  [ "$out" = $'a.go *.go\nc.rs *.rs\nd.pyx *.pyx' ] || fail "the pack's tests.inline did not add to and replace the default kinds: $out"
}

# #147. Bug it catches: setup could not tell which runner a test command starts, so it could not offer test.list. Each
# common runner is found, in the command or in the package.json script `npm test` / `npm run <name>` runs: args for
# those that take test files, none for go test and cargo test, nothing for a command it does not know. Nor for one
# that already names the files its runner runs (a glob, a path, a folder of main; not an option's value), as paths
# added at its end would not narrow it.
t_listguess() {
  setup '[]'
  printf '{"scripts": {"test": "eslint . && vitest run", "unit": "mocha", "glob": "node --test checks/*.js"}}\n' > "$R/package.json"
  mkdir -p "$R/tests"
  local out
  out=$(tpeng 'for c in "node --max-old-space-size=4096 --test" "npx jest --ci" "python3 -m pytest -q" "bundle exec rspec" "npm test" "npm run unit" \
      "go test ./..." "cargo test" "make check" "node --test-only x.js" "node --test checks/*.js" "npm run glob" "pytest -q tests" "pytest -k cart" \
      "node --test --test-reporter dot"; do printf "%s|" "$(listguess "$c")"; done') || fail "the guess failed: $out"
  [ "$out" = 'args node --test|args jest|args pytest|args rspec|args vitest|args mocha|none go test|none cargo test||||||args pytest|args node --test|' ] \
    || fail "setup did not find each runner, and what test.list it takes: $out"
}
