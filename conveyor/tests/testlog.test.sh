#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the logs the test runners write, as a failed run's failures are read from them.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug: a runner's log that ends without a newline (the runner was cut off, or writes none after its last line) had the
# mark that begins the next runner's log joined to its last line. The two logs then read as one runner's, in the order
# of the logs' names, so the other runner's `== ` line read as going back and its failing case went to the wrong file:
# the Board named b.test.sh for a failure of a.test.sh. The joined line also gave the file a name ending in the mark.
# Read as a card's test line holds them (logfails(), testfails.test.sh).
t_testlognonewline() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
echo "== b.test.sh"; echo "FAIL [beta]: wrong"
echo "== a.test.sh"; echo "FAIL [alpha]: wrong"
printf '== a.test.sh\n-- FAIL a.test.sh' > "$CONVEYOR_TEST_LOG/a.log"
printf '== b.test.sh\n-- FAIL b.test.sh\n' > "$CONVEYOR_TEST_LOG/b.log"
exit 1
EOF
  f=$(logfails 1) || fail "the failures could not be read"
  [ "$(jq -r '.files | map("\(.file):\(.cases | map(.name) | join(","))") | join(" ")' <<<"$f")" = "a.test.sh:alpha b.test.sh:beta" ] \
    || fail "a log without a final newline put a failing case under the wrong file: $f"
}
