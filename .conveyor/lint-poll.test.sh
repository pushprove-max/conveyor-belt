#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The pack's lint command for a test's wait with no ceiling (lint-poll.sh): a card that brings back
# `until [ -e <file> ]; do sleep 0.1; done` in a test, or in a script a test writes (issue 1840: a fixture whose file
# never came held a proof run for 35 minutes, until it was stopped by hand), must be a finding the engine reads; a wait
# that ends (wait_until, wait_poll, a second condition, a count, a timeout around it) and a comment must not; and the
# test files the pack gives the command must pass.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; bad=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); bad=1; echo "not ok $n - $1"; }
run() { rc=0; out=$(cd "$T" && bash "$HERE/lint-poll.sh" "$@" 2>&1) || rc=$?; }
printf '%s\n' 'until [ -e "$T/up" ]; do sleep 0.1; done' '( flock 9 && while [ ! -s "$T/pid" ]; do sleep 0.05; done ) 9>> "$T/lock" &' \
  "printf '%s\\n' 'until [ -e \"\$1\" ]; do sleep 0.1; done' > \"\$T/session\"" "hook='#!/usr/bin/env bash\\nuntil [ -e %q/end ]; do sleep 0.05; done\\n'" \
  'until [[ -f $T/x ]]; do' '  sleep 1 # sleep: the pause' 'done' 'while ! test -e "$T/y"; do sleep 1; done' > "$T/bad.sh"
printf '%s\n' "wait_until '[ -e \"\$T/up\" ]' || fail \"not up\"" '# until [ -e "$T/up" ]; do sleep 0.1; done' \
  'until [ -e "$T/up" ] || ! kill -0 "$pid"; do sleep 0.1; done' 'i=0; until [ -e "$T/up" ]; do [ $((i += 1)) -le 100 ] || exit 1; sleep 0.1; done' \
  'until [ -e "$T/up" ]; do sleep 0.1; kill -0 "$pid" || exit 1; done' "timeout 20 bash -c 'until [ -e \"\$1\" ]; do sleep 0.05; done' _ \"\$T/up\" || exit 1" \
  "printf '%s\\n' \"\$(wait_fn)\" 'wait_poll [ -e \"\$1\" ]' > \"\$T/session\"" > "$T/good.sh"

# Bug: a wait for a file with no ceiling passed the lint, in a test's own code and in the text of a script it writes.
run bad.sh
printf '%s\n' "$out" > "$T/out"; printf 'bad.sh\0' > "$T/paths"
# shellcheck source=/dev/null
. "$HERE/../conveyor/lib/lint.sh"
found=$(lintfindings "$T/out" "$T/paths" | jq -sc 'map([.file, .line])')
[ "$rc" = 1 ] && [[ $out == *"a wait for a file with no ceiling"* ]] \
  && [ "$found" = '[["bad.sh",1],["bad.sh",2],["bad.sh",3],["bad.sh",4],["bad.sh",5],["bad.sh",8]]' ] \
  && ok "a wait for a file with no ceiling is a finding the engine reads, on one line or on several, exit 1" \
  || no "bad.sh: exit $rc, engine read $found: $out"

# Bug: a wait that ends (wait_until, wait_poll, a second condition, a count, a check in the loop, a timeout around it)
# or a comment was a finding.
run good.sh
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a wait that ends and a comment pass" || no "good.sh: exit $rc: $out"

# What must stay true: the test files the pack gives the command have no such wait.
mapfile -t ps < <(jq -r '.lint.commands[] | select(.run == "bash .conveyor/lint-poll.sh {files}") | .files[]' "$HERE/project.json")
mapfile -t fs < <(cd "$HERE/.." && [ ${#ps[@]} != 0 ] && git ls-files -co --exclude-standard -- "${ps[@]}")
rc=0; out=$(cd "$HERE/.." && [ ${#fs[@]} != 0 ] && bash .conveyor/lint-poll.sh "${fs[@]}" 2>&1) || rc=$?
[ "$rc" = 0 ] && ok "the pack's test files pass" || no "the pack's ${#fs[@]} test files (${ps[*]}): exit $rc: $out"

# Bug: a file that cannot be read looked like a pass.
run gone.sh
[ "$rc" = 2 ] && ok "a file that cannot be read exits 2" || no "gone.sh: exit $rc: $out"

echo "1..$n"; exit $bad
