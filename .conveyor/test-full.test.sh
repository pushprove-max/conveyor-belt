#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh, the pack's test.full). Bugs: the pack named no test.full, so
# `conveyor.sh release-prep` stopped before it ran a suite, wrote notes or posted a status; and a full suite that skips
# a test file, runs an untracked one or passes when one fails would let release-prep post a pass on a red commit.
set -u
unset CONVEYOR_TEST_LOG # this file's fixture suite names its files in a folder of its own, never in the run's
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo with the real script and the real pack's test.full: a passing shell test, a failing Python test, and
# an untracked test file that would fail. Each test file notes that it ran.
R=$T/r; mkdir -p "$R/.conveyor" "$R/lib"
cp "$HERE/test-full.sh" "$R/.conveyor/"
full=$(jq -r '.test.full // empty' "$HERE/project.json")
[ -n "$full" ] || no "the pack (.conveyor/project.json) names no test.full"
echo 'echo pass >> "$(dirname "$0")/../ran"' > "$R/lib/fx-pass.test.sh"
printf 'import os, sys\nopen(os.path.join(os.path.dirname(__file__), "..", "ran"), "a").write("py\\n")\nsys.exit(1)\n' > "$R/lib/fx-fail.test.py"
# A runner that names its own case as ended in the engine's test log folder, as the engine's runner does.
echo '[ -z "${CONVEYOR_TEST_LOG:-}" ] || { mkdir -p "$CONVEYOR_TEST_LOG/cases/ok" && : > "$CONVEYOR_TEST_LOG/cases/ok/own"; }' >"$R/lib/fx-own.test.sh"
echo ran > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
echo 'echo untracked >> "$(dirname "$0")/../ran"' > "$R/lib/fx-untracked.test.sh"

mkdir "$T/log"
(cd "$R" && CONVEYOR_TEST_LOG=$T/log bash -c "$full") > "$T/out" 2>&1; rc=$?
# Bug: a whole-suite run's progress (release-prep, release, the Board's full test) counts only the cases the engine's
# runner names, so the Board's test files and their failures were left out of its cases done and failed.
got=$(cd "$T/log/cases" && find ok failed -type f | sort | tr '\n' ' ')
[ "$got" = "failed/lib:fx-fail.test.py ok/lib:fx-pass.test.sh ok/own " ] \
  || no "the full suite does not name each file that named no case of its own as ended, by its result: $got"
[ $rc = 1 ] || no "a failing test file did not fail the full suite (exit $rc): $(cat "$T/out")"
[ "$(sort "$R/ran" 2>/dev/null | tr '\n' ' ')" = "pass py " ] || no "the full suite did not run each tracked test file alone: $(cat "$R/ran" 2>&1)"
grep -qx 'ok lib/fx-pass.test.sh' "$T/out" && grep -qx 'FAIL lib/fx-fail.test.py' "$T/out" \
  || no "the full suite does not name each file's result: $(cat "$T/out")"

# With the failing file gone, the suite passes.
git -C "$R" rm -q lib/fx-fail.test.py && rm -f "$R/lib/fx-untracked.test.sh"
(cd "$R" && bash -c "$full") > "$T/out" 2>&1 || no "the full suite failed with every test file passing: $(cat "$T/out")"

[ $fails = 0 ] && echo "ok - test-full" || exit 1
