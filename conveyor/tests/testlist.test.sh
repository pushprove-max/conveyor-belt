#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#147, #351): the list of tests a card's run gives test.fileCommand, one file at a time (tests():
# listcmd(), testsel()): the test files the links and the names give the change's files.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Main holds lib/cartsum.js and its test lib/cartsum.test.js, lib/tax.test.js, a test of the same name in a far folder
# (far/cartsum.test.js) and a shared test helper (test/helpers.js); with an argument, that map as
# .conveyor/test-links.json. The pack's test.fileCommand ($STUB/one) adds `one:<the file it was given>` to $STUB/got,
# a line a run.
listsetup() { # [test-links.json]
  local f
  setup '[]'
  for f in lib/cartsum.js lib/cartsum.test.js lib/tax.test.js far/cartsum.test.js test/helpers.js; do mkdir -p "$R/${f%/*}" && echo x > "$R/$f"; done
  # The fixture's .gitignore leaves .conveyor/ out: a project commits its map (testlinks()), so it is added here.
  [ -z "${1:-}" ] || { printf '%s\n' "$1" > "$R/.conveyor/test-links.json" && git -C "$R" add -f .conveyor/test-links.json; } || fail "the map"
  git -C "$R" add -A && git -C "$R" commit -qm files || fail "main's files could not be committed"
  printf '%s\n' 'echo "one:$1" >> "$STUB/got"' > "$STUB/one"
  tune '.test.fileCommand = "bash \"$STUB/one\""'
}
# Card c7's test step, its own tests() as card() runs it, on a change (a shell edit staged in its worktree on main).
listrun() { # <change>
  local wt=$T/$CASE/cards/c7
  git -C "$R" worktree add -q --detach "$wt" && (cd "$wt" && eval "$1") && git -C "$wt" add -A || fail "the card's change could not be staged"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1; tests "$wt" ) > "$T/$CASE/run.out" 2>&1 || fail "the test step failed: $(cat "$T/$CASE/run.out")"
}
listgot() { # <want> <what the list is>
  [ "$(cat "$STUB/got" 2>&1)" = "$1" ] || fail "test.fileCommand was not given $2: $(cat "$STUB/got" 2>&1)"
}

# #367. Bug it catches: a page in a test folder (lib/tests/speed/cartsum-notes.md, a test file by the default tests/
# pattern, as conveyor/tests/speed/<page>.md is) was taken by name for a test of lib/cartsum.js, run as a script and
# failed, and main was marked red for it. The change edits the page beside the source: only lib/cartsum.test.js runs.
t_testlistdoc() {
  listsetup
  mkdir -p "$R/lib/tests/speed" && echo '# Notes' > "$R/lib/tests/speed/cartsum-notes.md" && git -C "$R" add -A && git -C "$R" commit -qm notes \
    || fail "the page could not be committed"
  listrun 'echo y >> lib/cartsum.js; echo more >> lib/tests/speed/cartsum-notes.md'
  listgot 'one:lib/cartsum.test.js' 'the test of the changed file alone, not the page'
}

# The project's own map wins over the name: .conveyor/test-links.json links lib/cartsum.js to far/cartsum.test.js.
t_testlistmap() {
  listsetup '{"lib/cartsum.js": ["far/cartsum.test.js"]}'
  listrun 'echo y >> lib/cartsum.js'
  listgot 'one:far/cartsum.test.js' 'the test the map links alone'
}
