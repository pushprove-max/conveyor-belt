#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the closure test's quick mode (tools/closure.test.sh, CONVEYOR_CLOSURE_QUICK), which a card's test
# step runs. closuremiss.test.sh holds its other case, each in a file of its own as each makes an install.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. slotpool is slots.test.sh's.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The closure test's install case in quick mode, of the checkout whose engine folder is <src>, run on the case's pool
# with a temporary folder of the case's own, its output in <d>/run.out. The user's HOME stays: the install's home is
# made under it, as one under the temporary folder is hidden in the install's sandbox.
quickrun() { # <src>
  mkdir -p "$d/tmp"
  ( export CONVEYOR_CLOSURE_QUICK=1 TMPDIR=$d/tmp CONVEYOR_SHELL_TEST_CASE=install; timeout 200 bash "$1/tools/closure.test.sh" ) > "$d/run.out" 2>&1
}

# Bug (issue 583): a card that changed the closure test ran its ~700 units from the copy of the release set, 20 to 30
# minutes, for a check of seconds. In quick mode the install case starts no test file from the copy (no unit line in
# its log), starts its stub unit in the install, on its test slot, and passes.
t_closurequick() {
  local d=$T/$CASE
  slotpool 2; mkdir -p "$d"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  quickrun "$SRC" || fail "the closure test's install case failed in quick mode: $(tail -20 "$d/run.out")"
  grep -qx 'ok install' "$d/run.out" && grep -q '^ok stub unit ' "$d/run.out" \
    && grep -q '^quick: [1-9][0-9]* units from the copy left to the whole test$' "$d/run.out" \
    || fail "the install case did not run its stub unit in quick mode: $(tail -20 "$d/run.out")"
  ! grep -E '^(ok|FAIL) [^ ]*\.test\.(sh|py|mjs)' "$d/run.out" || fail "the install case ran a test file from the copy in quick mode"
}
