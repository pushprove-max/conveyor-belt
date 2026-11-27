#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The pack's lint command for engine settings set in front of a test call (lint-prefix.sh): a card that brings back
# `TEST_STILL=pretestok tests` (bash then gives it to every test file the call starts; 2026-11-27, a test's own engine
# refused its runs in every pre-review run) must be a finding the engine reads; a CONVEYOR_ setting for the test command,
# a scoped() call and a comment must not; and the engine's own files must pass.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; bad=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); bad=1; echo "not ok $n - $1"; }
run() { rc=0; out=$(cd "$T" && bash "$HERE/lint-prefix.sh" "$@" 2>&1) || rc=$?; }
printf '%s\n' 'f() {' '  TEST_STILL=pretestok tests "$wt"; rc=$?' '  x=1; TEST_GIVEN=${#fs[@]} bugrun "$mwt" "${fs[@]}"' '}' > "$T/bad.sh"
printf '%s\n' 'f() {' '  CONVEYOR_TEST_ONESLOT=1 scoped TEST_HARD "$lim" tests "$mwt" alone' '  CONVEYOR_SUITE_FILES=$wt.files hosttests "$wt" test.full' \
  '  # TEST_STILL=pretestok tests "$wt"' '  REPLY=x; tests "$wt"' '}' > "$T/good.sh"

# Bug: a setting of the engine set in front of tests() or bugrun() passed the lint, so its test files inherited it.
run bad.sh
printf '%s\n' "$out" > "$T/out"; printf 'bad.sh\0' > "$T/paths"
# shellcheck source=/dev/null
. "$HERE/../conveyor/lib/lint.sh"
found=$(lintfindings "$T/out" "$T/paths" | jq -sc 'map([.file, .line])')
[ "$rc" = 1 ] && [[ $out == *"TEST_STILL set in front of tests"* ]] && [[ $out == *"TEST_GIVEN set in front of bugrun"* ]] \
  && [ "$found" = '[["bad.sh",2],["bad.sh",3]]' ] && ok "an engine setting in front of a test call is a finding the engine reads, exit 1" \
  || no "bad.sh: exit $rc, engine read $found: $out"

# Bug: a CONVEYOR_ setting meant for the test command, a scoped() call, a comment or a plain assignment was a finding.
run good.sh
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a CONVEYOR_ setting, scoped(), a comment and a plain assignment pass" || no "good.sh: exit $rc: $out"

# What must stay true: the engine's own files have no such call.
rc=0; out=$(cd "$HERE/.." && bash .conveyor/lint-prefix.sh conveyor/lib/*.sh conveyor/commands/*.sh 2>&1) || rc=$?
[ "$rc" = 0 ] && ok "the engine's files pass" || no "the engine's files: exit $rc: $out"

# Bug: a file that cannot be read looked like a pass.
run gone.sh
[ "$rc" = 2 ] && ok "a file that cannot be read exits 2" || no "gone.sh: exit $rc: $out"

echo "1..$n"; exit $bad
