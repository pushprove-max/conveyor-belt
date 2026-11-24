#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# bash-guardrails.sh in a card's session with the rule Only the Test step runs tests on (CONVEYOR_TESTSTEPONLY=1, set
# by conveyor/lib/session.sh builder()). Bugs it catches: with the rule on, a session still ran its cases, the changed
# tests or a named node test file, time the Test step spends again after the session; or the rule refused a command
# that runs no test, or refused a test command with the rule off or outside a card session.
set -u
HOOK=$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p/.conveyor" "$T/p/conveyor" "$T/state"
# A pack shaped as this project's: the engine's case runner is a whole-suite command, test-changed.sh the changed tests.
printf '%s\n' '{"test": {"command": "bash .conveyor/test-changed.sh", "wholeCommands": ["conveyor/conveyor.test.sh"], "changed": ".conveyor/test-changed.sh"}}' > "$T/p/.conveyor/project.json"
FAIL=0
N=0
# <rule: 1 on, 0 off> <card, or empty for no card session> <expected exit> <command> <why it matters>
check() {
  local rc=0; N=$((N + 1))
  jq -cn --arg c "$4" --arg d "$T/p" --arg s "s$N" '{tool_input: {command: $c}, cwd: $d, session_id: $s}' \
    | (cd "$T/p" && CONVEYOR_TESTSTEPONLY=$1 CONVEYOR_CARD=$2 CLAUDE_PROJECT_DIR=$T/p CONVEYOR_GUARD_STATE=$T/state bash "$HOOK") > /dev/null 2> "$T/err" || rc=$?
  if [ "$rc" = "$3" ] && { [ "$3" = 0 ] || grep -qF 'the Test step runs the tests' "$T/err"; }; then echo "ok   rule=$1 card=${2:-none} $4"
  else echo "FAIL rule=$1 card=${2:-none} $4 (exit $rc, wanted $3): $5"; sed 's/^/     /' "$T/err"; FAIL=1; fi
}
check 1 c1 2 'bash conveyor/conveyor.test.sh rerun' 'a named engine case is still a test run'
check 1 c1 2 'timeout 600 bash .conveyor/test-changed.sh' 'the changed tests are the Test step'"'"'s own run'
check 1 c1 2 'node --max-old-space-size=4096 --test tests/one.test.mjs' 'a named node test file is still a test run'
check 1 c1 0 'git status && ls conveyor' 'a command that runs no test is not this rule'
check 0 c1 0 'bash conveyor/conveyor.test.sh rerun' 'with the rule off a named case runs'
check 0 c1 0 'bash .conveyor/test-changed.sh' 'with the rule off the changed tests run once'
check 0 c1 0 'node --max-old-space-size=4096 --test tests/one.test.mjs' 'with the rule off a named test file runs'
check 1 '' 0 'bash conveyor/conveyor.test.sh rerun' 'outside a card session (the owner, the Foreman) tests are not this rule'
exit $FAIL
