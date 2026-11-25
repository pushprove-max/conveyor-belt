#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The unit runner, unit.sh (issue 1620): it runs the unit cases of a changed engine file with none of the engine
# cases' setup, from a folder that is no git repository, in under a second. That a broken function fails its case,
# named, is .conveyor/test-changed-unit.test.sh's check, through the checks that run this runner.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
rc=0
no() { echo "not ok - $*"; rc=1; }
# unit <arg>...: the runner's run from a folder that is no git repository (it needs none), its output in $T/out, its
# exit in $T/rc and its time in ms in $T/ms.
unit() {
  local s=${EPOCHREALTIME/[.,]/}
  (cd "$T/none" && bash "$HERE/unit.sh" "$@") > "$T/out" 2>&1; echo $? > "$T/rc"
  echo $(((${EPOCHREALTIME/[.,]/} - s) / 1000)) > "$T/ms"
}
mkdir "$T/none"

# Bug: no unit layer: a check of one function's logic paid for a scratch repository and a card run. A change to
# portable.sh runs its unit cases, all pass, and the whole run takes under a second.
unit conveyor/lib/portable.sh
grep -q '^unit: 2 cases of 1 unit files, 0 failed' "$T/out" && [ "$(cat "$T/rc")" = 0 ] && [ "$(cat "$T/ms")" -lt 1000 ] \
  && echo "ok - a change to portable.sh runs its unit cases in $(cat "$T/ms") ms" \
  || no "unit.sh conveyor/lib/portable.sh: exit $(cat "$T/rc"), $(cat "$T/ms") ms: $(cat "$T/out")"

# Bug: a changed file no unit file names runs unit cases all the same (or fails the checks).
unit conveyor/lib/pack.sh
[ "$(cat "$T/rc")" = 0 ] && [ ! -s "$T/out" ] && echo "ok - a change to pack.sh runs no unit case" \
  || no "unit.sh conveyor/lib/pack.sh: exit $(cat "$T/rc"): $(cat "$T/out")"
exit $rc
