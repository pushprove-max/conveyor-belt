#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Self-test for literal-secret-warning.sh. The warning is for a secret
# written as a literal in code that ships. A read from the environment excuses
# the line it is on, not the file: one `process.env` anywhere in the write used
# to silence a literal token beside it.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/literal-secret-warning.sh"
PASS=0 FAIL=0
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)$(said)"; fi }
# warn | quiet | rc=<n>: the hook is advisory, so any non-zero exit is its own failure.
run() { # <file> <content>
  local out rc
  out=$(jq -cn --arg fp "$1" --arg c "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$c}}' | bash "$HOOK" 2>&1 >/dev/null); rc=$?
  [ "$rc" = 0 ] || { echo "rc=$rc"; return; }
  case "$out" in *"Possible hardcoded secret"*) echo warn ;; *) echo quiet ;; esac
}
LITERAL='const cfg = { token: "abcdefgh1234" };'

check "a literal token warns" warn "$(run /repo/src/a.ts "$LITERAL")"
check "a literal token beside an environment read on another line still warns" warn \
  "$(run /repo/src/a.ts "$(printf 'const region = process.env.AWS_REGION;\n%s\n' "$LITERAL")")"
check "and beside a getSetting call on another line" warn \
  "$(run /repo/src/a.ts "$(printf '%s\nconst other = await getSetting("x");\n' "$LITERAL")")"
check "a secret read from the environment is not a literal" quiet \
  "$(run /repo/src/a.ts 'const cfg = { token: process.env.API_TOKEN ?? "" };')"
check "a line that reads the environment is excused, fallback and all" quiet \
  "$(run /repo/src/a.ts 'const password = process.env.DB_PASSWORD || "local-dev-only";')"
check "a short literal is not a secret" quiet "$(run /repo/src/a.ts 'const token = "abc";')"
check "markdown is not code" quiet "$(run /repo/docs/a.md "$LITERAL")"
check "a test file is skipped" quiet "$(run /repo/src/a.test.ts "$LITERAL")"
check "a MultiEdit's second edit is read" warn \
  "$(jq -cn --arg n "$LITERAL" '{tool_name:"MultiEdit", tool_input:{file_path:"/repo/src/a.ts", edits:[{old_string:"a", new_string:"const r = process.env.R;"}, {old_string:"b", new_string:$n}]}}' \
     | bash "$HOOK" 2>&1 >/dev/null | grep -c 'Possible hardcoded secret' | sed 's/^1$/warn/')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
