#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the withdrawal of the slices of a split that could not be filed whole (splitfile(), splitwithdraw(),
# lib/slices.sh), when the close of some fails. Each case calls the engine function with gh_write replaced; no card runs.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# fx_in reads its worktree's .unfixed (FXWT): these cases have no worktree.
# shellcheck disable=SC2034 # read by fx_in (lib.sh)
FXWT=$T/none
# gh_write as GitHub unreachable for each close: the close is logged in $STUB/tried, and fails.
NOCLOSE='gh_write() { [ "$1 $2" != "issue close" ] || { echo "$3" >> "$STUB/tried"; return 1; }; '

# splitfile() files slice 1 as #100101, slice 2 cannot be filed, and the close of #100101 fails. Bug caught: the
# reason said only that slice 2 was not filed, and #100101 stayed open as a slice of a split that never was.
t_slicewithdrawfile() {
  setup '[]'
  local i='{"number":7,"title":"t","body":"Done when:\n- a\n- b","labels":[],"milestone":null}'
  local sl='[{"title":"s1","doneWhen":["a"],"covers":[1],"dependsOn":[]},{"title":"s2","doneWhen":["b"],"covers":[2],"dependsOn":[]}]'
  fx_in "$NOCLOSE"' [ ! -e "$STUB/one" ] || { echo "HTTP 502"; return 1; }; touch "$STUB/one"; echo https://github.com/o/r/issues/100101; }; '"splitfile c1-7 '$i' '$sl' 0"
  [ "$RC" = 1 ] && [ "$(cat "$STUB/tried" 2>/dev/null)" = 100101 ] \
    && [ "$(cat "$T/$CASE/run.out")" = 'slice 2 was not filed: HTTP 502; Conveyor could not confirm that GitHub closed the slices filed before it (#100101): they may still be open' ] \
    || fail "splitfile c1-7 #7 '$sl', slice 2's create and every close failed: the reason does not say #100101 may still be open (exit $RC, closes tried $(cat "$STUB/tried" 2>/dev/null)): $(cat "$T/$CASE/run.out")"
}
# splitfile() files three slices #100101 to #100103, then splitplace() fails; the closes of #100101 and #100103 fail
# while #100102 closes. Bug caught (review E2): a reason that names only the last failed close, names the closed
# #100102, or drops the failed numbers when the slices could not be placed leaves an open slice the record does not name.
t_slicewithdrawplace() {
  setup '[]'
  local i='{"number":7,"title":"t","body":"Done when:\n- a\n- b\n- c","labels":[],"milestone":null}'
  local sl='[{"title":"s1","doneWhen":["a"],"covers":[1],"dependsOn":[]},{"title":"s2","doneWhen":["b"],"covers":[2],"dependsOn":[]},{"title":"s3","doneWhen":["c"],"covers":[3],"dependsOn":[]}]'
  fx_in 'gh_write() { [ "$1 $2" != "issue close" ] || { echo "$3" >> "$STUB/tried"; [ "$3" = 100102 ]; return; }
      echo x >> "$STUB/made"; echo "https://github.com/o/r/issues/10010$(wc -l < "$STUB/made" | tr -d " ")"; }
    splitplace() { return 1; }; '"splitfile c1-7 '$i' '$sl' 0"
  [ "$RC" = 1 ] && [ "$(tr '\n' ' ' < "$STUB/tried")" = '100101 100102 100103 ' ] \
    && [ "$(cat "$T/$CASE/run.out")" = 'the control record could not be read or written, so the slices could not be held or queued as their issue is; Conveyor could not confirm that GitHub closed the slices filed (#100101, #100103): they may still be open' ] \
    || fail "splitfile c1-7 #7 '$sl', splitplace failed and the closes of 100101 and 100103 failed: the reason does not name both (exit $RC, closes tried $(cat "$STUB/tried" 2>/dev/null)): $(cat "$T/$CASE/run.out")"
}
