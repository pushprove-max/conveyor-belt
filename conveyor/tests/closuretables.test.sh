#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the release set takes the files the run-time tables name (tools/closure.sh TABLES: the command table
# of conveyor.sh, SNAPLIBS of commands/snapshot.sh, FETCH of hooks/units.tsx), and fails on a missing one.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug (issue 776): the command-table reader dropped a script that was missing or untracked, so the set shipped a
# command whose script was not in it, and SNAPLIBS and FETCH were not read at all. In a checkout of the set, a new
# entry of each table, with its file, is in the set with no other change; an unused sibling of a library the snapshot
# loads is not (only --unreached names it); and each entry whose file is untracked or missing fails the set, naming the
# file that holds the table and the path it expects, as does a table the reader no longer finds.
t_closuretables() {
  local c=$T/$CASE/co o=$T/$CASE/out
  mkdir -p "$c"
  ( cd "$SRC/.." && bash conveyor/tools/closure.sh | tar -cf - -T - ) | tar -C "$c" -xf - || fail "cannot copy the release set"
  echo 'hello() { :; }' > "$c/conveyor/commands/hello.sh" && echo 'extra() { :; }' > "$c/conveyor/lib/extra.sh" \
    && echo 'unused() { :; }' > "$c/conveyor/lib/zzunused.sh" && echo 'echo fetch' > "$c/hooks/units-fetch2.sh" \
    && sed -i '/^cmd watch /a cmd hello hello.sh -' "$c/conveyor/conveyor.sh" \
    && sed -i "s/^SNAPLIBS='/SNAPLIBS='extra /" "$c/conveyor/commands/snapshot.sh" \
    && sed -i "s|^const FETCH = 'hooks/units-fetch.sh'|const FETCH = 'hooks/units-fetch2.sh'|" "$c/hooks/units.tsx" \
    && grep -qx 'cmd hello hello.sh -' "$c/conveyor/conveyor.sh" && grep -q "^SNAPLIBS='extra " "$c/conveyor/commands/snapshot.sh" \
    && grep -q "^const FETCH = 'hooks/units-fetch2.sh'" "$c/hooks/units.tsx" || fail "cannot make the fixture's table entries"
  git -C "$c" init -q && git -C "$c" add -A && git -C "$c" commit -qm set || fail "cannot make the checkout a repository"
  bash "$c/conveyor/tools/closure.sh" "$c" > "$o" || fail "closure.sh failed with every table entry's file in place"
  for f in conveyor/commands/hello.sh conveyor/lib/extra.sh hooks/units-fetch2.sh; do
    grep -qxF "$f" "$o" || fail "the set misses $f, which a table names"
  done
  ! grep -qxF conveyor/lib/zzunused.sh "$o" || fail "the set holds an unused sibling of the snapshot's libraries"
  [ "$(bash "$c/conveyor/tools/closure.sh" --unreached "$c")" = conveyor/lib/zzunused.sh ] \
    || fail "--unreached did not name only the unused library"
  # Each missing target in turn: untracked (the file is still on disk), then gone from the checkout.
  git -C "$c" rm -q --cached conveyor/commands/hello.sh || fail "cannot untrack the command's script"
  ! bash "$c/conveyor/tools/closure.sh" "$c" > /dev/null 2> "$o" || fail "closure.sh passed with a command's script untracked"
  grep -qxF 'closure: conveyor/conveyor.sh: cmd names hello.sh, but conveyor/commands/hello.sh is missing or untracked' "$o" \
    || fail "closure.sh did not name conveyor/conveyor.sh and the missing script: $(cat "$o")"
  git -C "$c" add conveyor/commands/hello.sh && git -C "$c" rm -q conveyor/lib/extra.sh || fail "cannot remove the library"
  ! bash "$c/conveyor/tools/closure.sh" "$c" > /dev/null 2> "$o" || fail "closure.sh passed with a SNAPLIBS library missing"
  grep -qxF 'closure: conveyor/commands/snapshot.sh: SNAPLIBS names extra, but conveyor/lib/extra.sh is missing or untracked' "$o" \
    || fail "closure.sh did not name snapshot.sh and the missing library: $(cat "$o")"
  echo 'extra() { :; }' > "$c/conveyor/lib/extra.sh" && git -C "$c" add conveyor/lib/extra.sh && git -C "$c" rm -q hooks/units-fetch2.sh \
    || fail "cannot remove the fetch"
  ! bash "$c/conveyor/tools/closure.sh" "$c" > /dev/null 2> "$o" || fail "closure.sh passed with the FETCH file missing"
  grep -qxF 'closure: hooks/units.tsx: FETCH names hooks/units-fetch2.sh, but hooks/units-fetch2.sh is missing or untracked' "$o" \
    || fail "closure.sh did not name units.tsx and the missing fetch: $(cat "$o")"
  # A table the reader no longer finds (renamed) fails too, not read as one with no entries.
  echo 'echo fetch' > "$c/hooks/units-fetch2.sh" && git -C "$c" add hooks/units-fetch2.sh \
    && sed -i 's/^SNAPLIBS=/LIBS=/' "$c/conveyor/commands/snapshot.sh" && git -C "$c" add conveyor/commands/snapshot.sh || fail "cannot rename SNAPLIBS"
  ! bash "$c/conveyor/tools/closure.sh" "$c" > /dev/null 2> "$o" || fail "closure.sh passed with no SNAPLIBS table"
  grep -qxF 'closure: conveyor/commands/snapshot.sh: its SNAPLIBS table names no file' "$o" \
    || fail "closure.sh did not name snapshot.sh and its missing table: $(cat "$o")"
}
