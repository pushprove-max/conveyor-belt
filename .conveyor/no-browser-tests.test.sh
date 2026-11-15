#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The ban on browser tests holds (no-browser-tests.sh). Bug it catches: a card adds a test that starts a headless
# browser again, and the check lets it through.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d); trap "rm -rf $T" EXIT
git -C "$T" init -q; mkdir -p "$T/.conveyor" "$T/.claude/scripts/__tests__"
cp "$ROOT/.conveyor/no-browser-tests.sh" "$T/.conveyor/"
echo "assert.ok(true);" > "$T/.claude/scripts/__tests__/a.test.mjs"
bash "$T/.conveyor/no-browser-tests.sh" 2>/dev/null || { echo "not ok - a plain test was refused"; exit 1; }
echo "const b = process.env.CONVEYOR_BROWSER;" > "$T/.claude/scripts/__tests__/b.test.mjs"
out=$(bash "$T/.conveyor/no-browser-tests.sh" 2>&1) && { echo "not ok - a browser test was let through"; exit 1; }
grep -q "b.test.mjs" <<<"$out" || { echo "not ok - the refusal does not name the file: $out"; exit 1; }
bash "$ROOT/.conveyor/no-browser-tests.sh" || { echo "not ok - the project itself has a browser test"; exit 1; }
echo "ok - no browser tests"
