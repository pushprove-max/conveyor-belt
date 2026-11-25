#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The engine's unit tests (issue 1620): a case that calls one engine function with its inputs, with no git repository,
# card folder or stub CLI set up (no tests/lib.sh), so it runs in milliseconds where an engine case
# (conveyor/tests/*.test.sh) pays for a scratch repository and a card run. Each unit file here, <name>.unit.sh, names
# the engine file it tests in a `# unit: <path from the repository root>` line, sources that file, and defines its cases
# as `u_<name>() {` functions at the left; a case fails by calling fail <why>, or by a non-zero exit.
# Usage: unit.sh [<changed file>...]: with no file, every unit file; else the unit files that name a changed file and
# each changed unit file, and every unit file when this runner changed. A changed file no unit file names selects none.
# Each case runs in a subshell of its own. Prints `FAIL <unit file> <case>: <why>` for each failed case and one summary
# line when a case ran; exit 1 when a case failed. test-changed.sh's checks run it first, on the change's files.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
SRC=${HERE%/unit}
ROOT=${SRC%/*}
REL=${HERE#"$ROOT"/}
files=()
for u in "$HERE"/*.unit.sh; do
  [ -f "$u" ] || continue
  if [ $# = 0 ]; then files+=("$u"); continue; fi
  of=$(sed -n 's/^# unit: \([^ ]*\)$/\1/p' "$u")
  for f; do
    case $f in "$REL/${u##*/}"|"$of"|"$REL/unit.sh") files+=("$u"); break ;; esac
  done
done
[ ${#files[@]} -gt 0 ] || exit 0
start=${EPOCHREALTIME/[.,]/}
n=0; bad=0
for u in "${files[@]}"; do
  for c in $(sed -n 's/^\(u_[A-Za-z0-9_]*\)() {.*/\1/p' "$u"); do
    n=$((n + 1))
    out=$( (
      fail() { echo "$*"; exit 1; }
      # shellcheck source=/dev/null
      . "$u" && "$c"
    ) 2>&1) && continue
    bad=$((bad + 1))
    echo "FAIL ${u#"$ROOT"/} $c: ${out:-exited non-zero with no output}"
  done
done
echo "unit: $n cases of ${#files[@]} unit files, $bad failed, $(((${EPOCHREALTIME/[.,]/} - start) / 1000)) ms"
[ "$bad" = 0 ]
