#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#147): the list of tests a card's run gives its test command (tests(): listcmd(), testsel()), in the
# form the pack's test.list names, and the whole suite (no list) when the change cannot be narrowed.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Main holds lib/cartsum.js and its test lib/cartsum.test.js, lib/tax.test.js, a test of the same name in a far folder
# (far/cartsum.test.js) and a shared test helper (test/helpers.js); with a second argument, that map as
# .conveyor/test-links.json. The pack's test.list is <mode>, and its command (by default $STUB/list-cmd) writes the
# arguments it was given and CONVEYOR_TEST_FILES to $STUB/got.
listsetup() { # <test.list> [test-links.json]
  local f
  setup '[]'
  for f in lib/cartsum.js lib/cartsum.test.js lib/tax.test.js far/cartsum.test.js test/helpers.js; do mkdir -p "$R/${f%/*}" && echo x > "$R/$f"; done
  # The fixture's .gitignore leaves .conveyor/ out: a project commits its map (testlinks()), so it is added here.
  [ -z "${2:-}" ] || { printf '%s\n' "$2" > "$R/.conveyor/test-links.json" && git -C "$R" add -f .conveyor/test-links.json; } || fail "the map"
  git -C "$R" add -A && git -C "$R" commit -qm files || fail "main's files could not be committed"
  printf '%s\n' 'printf "args:%s|env:%s\n" "$*" "$(printf %s "${CONVEYOR_TEST_FILES:-}" | tr "\n" " ")" > "$STUB/got"' > "$STUB/list-cmd"
  tune --arg l "$1" '.test.list = $l | .test.command = "bash \"$STUB/list-cmd\""'
}
# Card c7's test step, its own tests() as card() runs it, on a change (a shell edit staged in its worktree on main);
# its test line's fields (testrec()) in c7.rec.
listrun() { # <change>
  local wt=$T/$CASE/cards/c7
  git -C "$R" worktree add -q --detach "$wt" && (cd "$wt" && eval "$1") && git -C "$wt" add -A || fail "the card's change could not be staged"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1; tests "$wt" || exit; testrec "$wt" 0 0 > "$wt.rec" ) > "$T/$CASE/run.out" 2>&1 || fail "the test step failed: $(cat "$T/$CASE/run.out")"
}
listgot() { # <want> <what the list is>
  [ "$(cat "$STUB/got" 2>&1)" = "$1" ] || fail "the command was not given $2: $(cat "$STUB/got" 2>&1)"
}
listrec() { # <the test line's list, as jq -c prints it>
  [ "$(jq -c .list "$T/$CASE/cards/c7.rec" 2>&1)" = "$1" ] || fail "the test line's list is not $1: $(cat "$T/$CASE/cards/c7.rec" 2>&1)"
}

# Bug it catches: a card's run was its plain test command, the whole suite, so six cards at once loaded the machine to
# 94. A change to one source file and a new test file runs only the test of that file by name (the nearest one, not
# far/cartsum.test.js) and the new test, as arguments; a document of the change adds none. The test line says so.
t_testlistargs() {
  listsetup args
  listrun 'echo y >> lib/cartsum.js; echo x > lib/new.test.js; echo d > notes.md'
  listgot 'args:lib/cartsum.test.js lib/new.test.js|env:' 'the test of the changed file and the new test, as arguments'
  listrec '{"mode":"changed","files":2,"by":"name"}'
}

# The same change with test.list env: no argument, and CONVEYOR_TEST_FILES holds the two paths, one a line.
t_testlistenv() {
  listsetup env
  listrun 'echo y >> lib/cartsum.js; echo x > lib/new.test.js'
  listgot 'args:|env:lib/cartsum.test.js lib/new.test.js' 'the two paths in CONVEYOR_TEST_FILES'
}

# test.list placeholder: the path goes where {files} is in the command, and the rest of the command stays.
t_testlistplace() {
  listsetup placeholder
  tune '.test.command = "bash \"$STUB/list-cmd\" --a {files} --b"'
  listrun 'echo y >> lib/cartsum.js'
  listgot 'args:--a lib/cartsum.test.js --b|env:' 'the path in place of {files}'
}

# The project's own map wins over the name: .conveyor/test-links.json links lib/cartsum.js to far/cartsum.test.js.
t_testlistmap() {
  listsetup args '{"lib/cartsum.js": ["far/cartsum.test.js"]}'
  listrun 'echo y >> lib/cartsum.js'
  listgot 'args:far/cartsum.test.js|env:' 'the test the map links'
}

# test.list none: the command takes no list, so it is given none and runs the whole suite, and the test line says why.
t_testlistnone() {
  listsetup none
  listrun 'echo y >> lib/cartsum.js'
  listgot 'args:|env:' 'no list'
  listrec '{"mode":"whole","why":"test.list is none: the test command takes no list"}'
}

# Bug it catches: a change to a shared test helper, which every test may read, ran only the helper. It runs the whole
# suite (no list), and the test line names the file.
t_testlisthelper() {
  listsetup args
  listrun 'echo y >> test/helpers.js; echo y >> lib/cartsum.js'
  listgot 'args:|env:' 'no list for a change to a shared helper'
  listrec '{"mode":"whole","why":"test/helpers.js: shared setup or config"}'
}

# Bug it catches: test.list args added the paths after a command that already names its tests (mocha 'lib/*.test.js',
# here a stub mocha on PATH), so the glob still ran every file it matched while the test line said "changed". It is
# given no path, and the test line says why.
t_testlistnamed() {
  listsetup args
  { echo '#!/usr/bin/env bash'; cat "$STUB/list-cmd"; } > "$STUB/mocha" && chmod +x "$STUB/mocha" || fail "the stub mocha"
  tune '.test.command = "mocha '\''lib/*.test.js'\''"'
  listrun 'echo y >> lib/cartsum.js'
  listgot 'args:lib/*.test.js|env:' 'only its own glob'
  listrec '{"mode":"whole","why":"test.list is args, and test.command already names the tests it runs (lib/*.test.js): use placeholder"}'
}

# A source file with no test found for it by the map or by name runs the whole suite: no test is skipped that may
# cover it.
t_testlistnotest() {
  listsetup args
  listrun 'echo x > lib/other.js'
  listgot 'args:|env:' 'no list for a file with no test found'
  listrec '{"mode":"whole","why":"lib/other.js: no test found for it"}'
}
