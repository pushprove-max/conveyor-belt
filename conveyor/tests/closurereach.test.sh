#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the closure test fails a shipped file the release set misses in seconds (tools/closure.sh --unreached).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. slotpool is slots.test.sh's.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug (issue 563): a file of conveyor/commands/ the walk does not reach is not in the set, and
# the install case failed on it only after every test had run from the copy, 20 to 30 minutes. A checkout of the set
# with such a file fails the install case in seconds, naming the file. A file on closure.sh's left-out list
# (conveyor/tests/speed/) is not named, and once the unreached file is gone the check names nothing.
t_closurereach() {
  local d=$T/$CASE c=$T/$CASE/co s
  slotpool 2; mkdir -p "$c/conveyor/commands" "$c/conveyor/tests/speed" "$d/tmp"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  ( cd "$SRC/.." && bash conveyor/tools/closure.sh | tar -cf - -T - ) | tar -C "$c" -xf - || fail "cannot copy the release set"
  # No file names hello.sh: a load by a path built at run time with no table or declaration fails closure.sh itself
  # (closuretables.test.sh t_closureloads).
  echo 'hello() { :; }' > "$c/conveyor/commands/hello.sh" && echo notes > "$c/conveyor/tests/speed/extra.md" \
    || fail "cannot make the fixture's files"
  git -C "$c" init -q && git -C "$c" add -A && git -C "$c" commit -qm set || fail "cannot make the checkout a repository"
  s=$SECONDS
  ! ( export TMPDIR=$d/tmp CONVEYOR_SHELL_TEST_CASE=install; timeout 120 bash "$c/conveyor/tools/closure.test.sh" ) > "$d/run.out" 2>&1 \
    || fail "the install case passed with a file the set misses: $(tail -20 "$d/run.out")"
  grep -qxF 'FAIL [install]: conveyor/commands/hello.sh: closure.sh does not reach it: add an anchored source, or a line to the left-out list' "$d/run.out" \
    || fail "the install case did not name the file the set misses: $(tail -20 "$d/run.out")"
  lim=$(loadlimit 60 120) # under the run's 120 s timeout
  [ $((SECONDS - s)) -lt "$lim" ] || fail "the install case took $((SECONDS - s)) s to fail on a file the set misses (limit $lim s: 60 s times the load factor $CASE_LOAD)"
  ! grep -F extra.md "$d/run.out" || fail "a file on the left-out list failed the check"
  git -C "$c" rm -q conveyor/commands/hello.sh || fail "cannot remove the unreached file"
  [ -z "$(bash "$c/conveyor/tools/closure.sh" --unreached "$c")" ] || fail "the check named a file with only left-out files beyond the set"
}
