#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the closure test's quick mode keeps its checks (tools/closure.test.sh, CONVEYOR_CLOSURE_QUICK).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. slotpool is slots.test.sh's, quickrun closurequick.test.sh's.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug (issue 583): a quick mode that left out the checks around the units would pass a copy that misses a shipped
# file. A checkout of the release set whose copy step leaves conveyor/jq/rows.jq out still fails the install case in
# quick mode, on the install's own closure.
t_closuremiss() {
  local d=$T/$CASE c=$T/$CASE/co t
  slotpool 2; mkdir -p "$c"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  ( cd "$SRC/.." && bash conveyor/tools/closure.sh | tar -cf - -T - ) | tar -C "$c" -xf - || fail "cannot copy the release set"
  t=$c/conveyor/tools/closure.test.sh
  sed 's|fail "cannot copy \$f"; done < "\$SET"$|fail "cannot copy $f"; done < <(grep -vxF conveyor/jq/rows.jq "$SET")|' "$t" > "$d/t" \
    && cat "$d/t" > "$t" && grep -qF 'grep -vxF conveyor/jq/rows.jq' "$t" || fail "the checkout's copy step could not be made to leave a file out"
  git -C "$c" init -q && git -C "$c" add -A && git -C "$c" commit -qm set || fail "cannot make the checkout a repository"
  ! quickrun "$c/conveyor" || fail "the install case passed in quick mode with a file missing from the copy: $(tail -20 "$d/run.out")"
  grep -q "^FAIL \[install\]: the install's closure is not the set" "$d/run.out" && grep -qx '> conveyor/jq/rows.jq' "$d/run.out" \
    || fail "the install case did not fail on its closure with a file missing from the copy: $(tail -20 "$d/run.out")"
}
