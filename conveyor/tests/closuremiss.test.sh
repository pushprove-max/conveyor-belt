#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the closure test's staged copy holds exactly the release set's paths (tools/closure.test.sh install).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. slotpool is slots.test.sh's.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A checkout of the release set in <d>/co whose closure test's copy step takes its list of paths from <list> (a
# command that reads "$SET"; no # and no &), made a repository; its install case run, its output in <d>/run.out. The
# user's HOME stays: the install's home is made under it, as one under the temporary folder is hidden in the install's
# sandbox.
stagerun() { # <list>
  local c=$d/co t
  slotpool 2; mkdir -p "$c" "$d/tmp"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  ( cd "$SRC/.." && bash conveyor/tools/closure.sh | tar -cf - -T - ) | tar -C "$c" -xf - || fail "cannot copy the release set"
  t=$c/conveyor/tools/closure.test.sh
  sed "s#tar -C \"\$TOP\" -cf - -T \"\$SET\"#$1 | tar -C \"\$TOP\" -cf - -T -#" "$t" > "$d/t" \
    && cat "$d/t" > "$t" && grep -qF "$1 | tar" "$t" || fail "the checkout's copy step could not be made to change its list"
  git -C "$c" init -q && git -C "$c" add -A && git -C "$c" commit -qm set || fail "cannot make the checkout a repository"
  ( export TMPDIR=$d/tmp CONVEYOR_SHELL_TEST_CASE=install; timeout 200 bash "$t" ) > "$d/run.out" 2>&1
}

# Bug (issue 775): the copy's paths are checked against the set, not only what closure.sh walks from the copy, so a
# shipped file missing from the copy fails, named. A copy step that leaves conveyor/jq/rows.jq out fails the install
# case, naming it.
t_closuremiss() {
  local d=$T/$CASE
  ! stagerun 'grep -vxF conveyor/jq/rows.jq "$SET"' || fail "the install case passed with a file missing from the copy: $(tail -20 "$d/run.out")"
  grep -qxF 'FAIL [install]: the staged copy misses conveyor/jq/rows.jq' "$d/run.out" \
    || fail "the install case did not name the file missing from the copy: $(tail -20 "$d/run.out")"
}

# Bug (issue 775): a path the copy holds beyond the set (a folder the set named, which tar copies whole) would ship
# unchecked. A copy step that adds a file of the checkout outside the set fails the install case, naming it.
t_closureextra() {
  local d=$T/$CASE
  mkdir -p "$d/co/zz" && echo notes > "$d/co/zz/extra.md" || fail "cannot make the file outside the set"
  ! stagerun '{ cat "$SET"; echo zz/extra.md; }' || fail "the install case passed with a file beyond the set in the copy: $(tail -20 "$d/run.out")"
  grep -qxF 'FAIL [install]: the staged copy holds zz/extra.md, which is not in the set' "$d/run.out" \
    || fail "the install case did not name the file beyond the set: $(tail -20 "$d/run.out")"
}
