#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: doctor over a main checkout set to bare (#254). Its own file: setup.test.sh is over the 600 lines a case
# file may have. The helpers (doctordone, sample) are setup.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug: a main checkout with core.bare=true fails each git command that needs a work tree, so no card can land, and doctor said nothing
# of it. Doctor names it, with the fix, and fails.
t_doctorbare() {
  local X out rc; doctordone
  git -C "$S" config core.bare true; out=$(cd "$S" && bash "$X" doctor 2>&1); rc=$?; git -C "$S" config core.bare false
  [ $rc != 0 ] && grep -qxF "missing: a working main checkout: $S is not one (core.bare is true), so no card can land; fix: run git -C $S config core.bare false" <<<"$out" \
    || fail "doctor did not name the bare main checkout with its fix (exit $rc): $out"
}
