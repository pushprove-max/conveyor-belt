#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: mainred.sh linkput(), the write (and delete) of a main-red fix card's .conveyor/test-links.json, when a session
# process makes .conveyor, or test-links.json itself, a symlink to a folder outside the worktree. Its cases call
# mainred.test.sh's linkfix() and linkfns(). The runner, ../conveyor.test.sh, sources this file after the shared setup
# (lib.sh) and runs its cases; run alone, this file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue 1488. Bug it catches: linkput() checked .conveyor, then renamed its new file into place through the path
# "<worktree>/.conveyor/test-links.json", so a session process that swapped .conveyor for a symlink between the check
# and the rename made the engine replace test-links.json in the folder the symlink names, outside the worktree. Here
# mv swaps the folder just before the rename runs: the outside file keeps its text, and the links go to the folder
# that was checked.
t_mainredlinkputswap() {
  local w=$T/$CASE got
  linkfix '{}'; mkdir -p "$w/out/.conveyor" && echo keep > "$w/out/.conveyor/test-links.json" || fail "the fixture could not be made"
  got=$( eval "$(linkfns)"; export MAINRED=$w/mainred.json
    sw=$w # linkput() sets its own w in its subshell, where this mv runs
    mv() { command mv -- "$sw/fix/.conveyor" "$sw/moved" && ln -s "$sw/out/.conveyor" "$sw/fix/.conveyor" && command mv "$@"; }
    testlinks cfix "$w/fix" && echo staged; : ) || fail "the fixture failed: $got"
  [ "$(cat "$w/out/.conveyor/test-links.json")" = keep ] \
    || fail "linkput() with .conveyor swapped for a symlink before its rename replaced the file outside the worktree: $got: $(cat "$w/out/.conveyor/test-links.json")"
  [ "$(jq -c . "$w/moved/test-links.json" 2>&1)" = '{"lib/a.sh":["tests/b.test.sh"]}' ] \
    || fail "linkput() did not write the links in the .conveyor it checked: $(cat "$w/moved/test-links.json" 2>&1)"
}
# Bug it catches: when main has no test-links.json, linksonly() deleted the worktree's copy with rm -f through the path
# "<worktree>/.conveyor/test-links.json" after its check of .conveyor, so a session process that swapped .conveyor for
# a symlink in between made the engine delete test-links.json in the folder the symlink names, outside the worktree.
# Here rm swaps the folder just before it runs: the outside file stays, and the file goes from the folder checked.
t_mainredlinkputrmswap() {
  local w=$T/$CASE got
  linkfix '{}'; git -C "$w/fix" rm -q .conveyor/test-links.json && git -C "$w/fix" commit -qm 'no links' \
    && mkdir -p "$w/out/.conveyor" && echo keep > "$w/out/.conveyor/test-links.json" || fail "the fixture could not be made"
  got=$( eval "$(linkfns)"; export MAINRED=$w/mainred.json
    testlinks cfix "$w/fix" || exit 1
    sw=$w # linkput() sets its own w in its subshell, where this rm runs
    rm() { [ -e "$sw/moved" ] || { command mv -- "$sw/fix/.conveyor" "$sw/moved" && ln -s "$sw/out/.conveyor" "$sw/fix/.conveyor"; }; command rm "$@"; }
    linksonly cfix "$w/fix" && echo only; : ) || fail "the fixture failed: $got"
  [ "$(cat "$w/out/.conveyor/test-links.json" 2>&1)" = keep ] \
    || fail "linksonly() with .conveyor swapped for a symlink before its delete deleted the file outside the worktree: $got"
  [ -d "$w/moved" ] && [ ! -e "$w/moved/test-links.json" ] \
    || fail "linksonly() did not delete test-links.json in the .conveyor it checked: $got: $(ls -A "$w/moved" 2>&1)"
}
# Issue 1488. Bug it catches: testlinks() wrote through linkput() with no check of .conveyor (only linksonly() checked
# it), so a session that left .conveyor as a symlink to a folder outside the worktree made the engine replace
# test-links.json there. testlinks() now fails and the outside file keeps its text.
t_mainredlinkputdirlink() {
  local w=$T/$CASE got
  linkfix '{}'; mkdir -p "$w/out/.conveyor" && echo keep > "$w/out/.conveyor/test-links.json" \
    && rm -rf "$w/fix/.conveyor" && ln -s "$w/out/.conveyor" "$w/fix/.conveyor" || fail "the fixture could not be made"
  got=$( eval "$(linkfns)"; export MAINRED=$w/mainred.json
    testlinks cfix "$w/fix" && echo staged; : ) || fail "the fixture failed: $got"
  [ -z "$got" ] && [ "$(cat "$w/out/.conveyor/test-links.json")" = keep ] \
    || fail "testlinks() with .conveyor a symlink to an outside folder wrote through it, or did not fail: $got: $(cat "$w/out/.conveyor/test-links.json")"
}
# Issue 1488. Bug it catches: linkput() renamed its new file with a plain mv -f, so a session that left
# test-links.json as a symlink to a folder outside the worktree made mv move the engine's file into that folder. The
# outside folder stays empty, and test-links.json becomes the worktree's own file with the links.
t_mainredlinkputfilelink() {
  local w=$T/$CASE got
  linkfix '{}'; mkdir -p "$w/out/links" && ln -sfn "$w/out/links" "$w/fix/.conveyor/test-links.json" || fail "the fixture could not be made"
  got=$( eval "$(linkfns)"; export MAINRED=$w/mainred.json
    testlinks cfix "$w/fix" && echo staged; : ) || fail "the fixture failed: $got"
  [ -z "$(ls -A "$w/out/links")" ] \
    || fail "testlinks() with test-links.json a symlink to an outside folder moved its file into it: $got: $(ls -A "$w/out/links")"
  [ ! -L "$w/fix/.conveyor/test-links.json" ] && [ "$(jq -c . "$w/fix/.conveyor/test-links.json" 2>&1)" = '{"lib/a.sh":["tests/b.test.sh"]}' ] \
    || fail "testlinks() with test-links.json a symlink to an outside folder did not write the links in its place: $got"
}
