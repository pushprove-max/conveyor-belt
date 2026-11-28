#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the files the pack's test commands run as the test runner (runnerfiles(), lib/prompts.sh), read in one
# awk pass (#1650), and the test map read with no runner list where it needs none (mapread(), lib/testmap.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# <code> in the engine's shell, its libraries sourced as `run` sources them, in main's checkout.
rfeng() { ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
  && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && eval "$1" ); }
# Main's commit of each <file> holding its <text>.
rffiles() { # <file> <text>...: named for this file alone, as the runner sources every case file into one shell
  while [ $# -ge 2 ]; do mkdir -p "$(dirname "$R/$1")" && printf '%s\n' "$2" > "$R/$1" || fail "main's $1"; shift 2; done
  git -C "$R" add -A && git -C "$R" commit -qm files || fail "main's files could not be committed"
}
# The runner list of main's pack, on one line, with test.command set to <command>.
rflist() { # <command>
  tune --arg c "$1" '.test.command = $c'
  rfeng 'runnerfiles | paste -sd " " -' || fail "runnerfiles() failed on the command $1"
}

# Bug it catches: the awk pass giving this repository's own pack (its commands, the scripts they run, its
# package.json) another list than the bash loop it replaced: a runner left off is run alone as a test, and a test taken
# for a runner never runs alone. The list is the one the loop gave; a change to the runner scripts that changes it on
# purpose changes it here (#1829: conveyor/jq/linkslive.jq, which .conveyor/test-changed.sh reads its links through).
t_rfrepo() {
  setup '[]'
  local out
  out=$(rfeng 'MAIN=$(cd "$SRC/.." && pwd -P) PACK=$MAIN/.conveyor/project.json; runnerfiles | paste -sd " " -') \
    || fail "runnerfiles() failed on this repository's pack: $out"
  [ "$out" = '.claude/scripts/__tests__/dashboard-server.test.sh .conveyor/lint-shell.sh .conveyor/no-browser-tests.sh .conveyor/no-records-split.sh .conveyor/test-changed-map.test.sh .conveyor/test-changed.sh .conveyor/test-full.sh .conveyor/test-lint.sh conveyor/conveyor.sh conveyor/conveyor.test.sh conveyor/foreman/foreman-projects.test.sh conveyor/jq/linkslive.jq conveyor/lib/pick.sh conveyor/unit/unit.sh' ] \
    || fail "this repository's pack (.conveyor/project.json) gave another runner list: $out"
}

# Bug it catches: a command alone losing a word the loop counted: every word that names a tracked file is a runner,
# with a leading ./ and quotes taken off and the value of an --option=<value>; an env setting, an option, a word with a
# $, and a folder (tests) are none.
t_rfcommand() {
  setup '[]'; rffiles scripts/run.mjs x cfg/c.json x tests/a.test.mjs x
  local c='FORCE=1 node --test --config=./cfg/c.json ./scripts/run.mjs tests "$T"' out
  out=$(rflist "$c")
  [ "$out" = 'cfg/c.json scripts/run.mjs' ] || fail "the command $c gave another runner list: $out"
}

# Bug it catches: a script the command runs read another way: of each of its commands only the first word after env
# settings, wrappers and timeout's duration counts (tools/r.mjs; not the test file it is given, nor a word in a
# comment); a file it starts whose first line is no shell (tools/n.mjs) is a runner but is not read, so the
# tools/m.mjs it names is none.
t_rfscript() {
  setup '[]'
  rffiles ci/run.sh '#!/bin/bash
X=1 exec timeout 30s node tools/r.mjs tests/x.test.mjs "$@" # tools/c.mjs
[ -f tools/n.mjs ] && node ./tools/n.mjs' tools/r.mjs x tools/n.mjs 'bash tools/m.mjs' tools/m.mjs x tools/c.mjs x tests/x.test.mjs x
  local out
  out=$(rflist 'bash ci/run.sh')
  [ "$out" = 'ci/run.sh tools/n.mjs tools/r.mjs' ] || fail "the command bash ci/run.sh, which runs ci/run.sh, gave another runner list: $out"
}

# Bug it catches: the depth limit moved: the command, s1.sh, s2.sh and s3.sh are read (three scripts deep), so the
# s4.sh that s3.sh runs is a runner, and the s5.mjs that s4.sh runs is not.
t_rfdeep() {
  setup '[]'
  rffiles s1.sh 'bash s2.sh' s2.sh './s3.sh' s3.sh 'sh s4.sh' s4.sh 'node s5.mjs' s5.mjs x
  local out
  out=$(rflist 'bash s1.sh')
  [ "$out" = 's1.sh s2.sh s3.sh s4.sh' ] || fail "the command bash s1.sh, scripts four deep, gave another runner list: $out"
}

# Bug it catches: quoted words read another way than the loop read them: each quote is taken off a word, and a quoted
# name with a space is two words (q and a.sh, not the file "q a.sh"); so are the quoted words of the package scripts
# npm runs (unit and its postunit).
t_rfquoted() {
  setup '[]'
  rffiles 'q a.sh' x q x a.sh x tools/u.mjs x tools/v.mjs x package.json '{"scripts": {"unit": "node \"./tools/u.mjs\"", "postunit": "'\''tools/v.mjs'\''"}}'
  local c='bash "q a.sh" && npm run unit' out
  out=$(rflist "$c")
  [ "$out" = 'a.sh q tools/u.mjs tools/v.mjs' ] || fail "the command $c gave another runner list: $out"
}

# Bug it catches: the test map read for /units (`conveyor.sh testmap`, every snapshot) paying for the runner list
# (names(), runnerfiles()) when the map names no test by its name alone: Conveyor's made map, or area lines with paths.
# names() here only marks that it ran; each map is read as before.
t_rfmapnames() {
  setup '[]'
  rffiles lib/a.sh x tests/a.test.sh x areas.json '{"area": "a", "test": "tests/a.test.sh"}
{"area": "a", "file": "lib/a.sh"}'
  local out m='{"sources": {"lib/a.sh": ["tests/a.test.sh"]}, "tests": ["tests/a.test.sh"]}' \
    rd='names() { echo named >> "$T/$CASE/named"; return 1; }; mapread "$R"' \
    want='{"by":"map","age":null,"sources":{"lib/a.sh":["tests/a.test.sh"]},"shared":["lib/a.sh"]}'
  tune 'del(.test.map)'
  # The map's text in the code, not read from $m there: the engine's libraries set an m of their own as they load.
  out=$(rfeng "echo '$m' > \"\$(mappath)\"; $rd") && [ "$out" = "$want" ] || fail "the made map $m was read as another map: $out"
  tune '.test.map = "areas.json"'
  out=$(rfeng "$rd") && [ "$out" = "$want" ] || fail "the area lines with paths (areas.json) were read as another map: $out"
  [ ! -e "$T/$CASE/named" ] || fail "mapread ran names() for a map that names no test by its name alone"
}
