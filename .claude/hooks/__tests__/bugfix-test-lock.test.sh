#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Self-test for bugfix-test-lock.sh: while a path is listed in
# .claude/bugfix-lock, Edit/Write/MultiEdit on it are blocked whether the tool
# sends a relative or an absolute path; everything else passes, a malformed
# lock entry warns instead of blocking, and an absent lock file is silent.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/bugfix-test-lock.sh"
PASS=0 FAIL=0

. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)$(said)"; fi }
json() { jq -cn --arg tool "$1" --arg fp "$2" '{tool_name:$tool, tool_input:{file_path:$fp}}'; }
json_multi() { jq -cn --arg fp "$1" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[{old_string:"a", new_string:"b"}]}}'; }
json_multi_peredit() { jq -cn --arg fp "$1" '{tool_name:"MultiEdit", tool_input:{edits:[{file_path:$fp, old_string:"a", new_string:"b"}]}}'; }

# A throwaway project dir stands in for the repo root: the hook reads
# CLAUDE_PROJECT_DIR, so the test never depends on the developer's own
# worktree state or on a real .claude/bugfix-lock existing there.
TMP=$(mktemp -d /tmp/bugfix-test-lock-XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude" "$TMP/src/services/__tests__"
LOCKED_REL="src/services/__tests__/coupon.test.ts"
OTHER_REL="src/services/coupon.ts"
: > "$TMP/$LOCKED_REL"
: > "$TMP/$OTHER_REL"

lock() { printf '%s\n' "$@" > "$TMP/.claude/bugfix-lock"; }
run() { CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1 <<<"$1"; echo $?; }
run_err() { CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>&1 >/dev/null <<<"$1"; }
run_all() { CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>&1 <<<"$1"; }

# --- locked path, every tool, both path shapes -------------------------------
lock "$LOCKED_REL"
check "Edit on a locked path blocks"           2 "$(run "$(json Edit "$LOCKED_REL")")"
check "Write on a locked path blocks"          2 "$(run "$(json Write "$LOCKED_REL")")"
check "MultiEdit on a locked path blocks"      2 "$(run "$(json_multi "$LOCKED_REL")")"
check "MultiEdit per-edit file_path blocks"    2 "$(run "$(json_multi_peredit "$TMP/$LOCKED_REL")")"
check "absolute input vs relative entry blocks" 2 "$(run "$(json Edit "$TMP/$LOCKED_REL")")"
check "an unlisted path passes"                0 "$(run "$(json Edit "$OTHER_REL")")"
check "an unlisted absolute path passes"       0 "$(run "$(json Write "$TMP/$OTHER_REL")")"
check "a path outside the repo passes"         0 "$(run "$(json Edit "/tmp/elsewhere/x.ts")")"
check "empty file_path passes"                 0 "$(run '{"tool_name":"Edit","tool_input":{}}')"
check "the block names the hook and the path"  0 \
  "$(run_err "$(json Edit "$LOCKED_REL")" | grep -qF "bugfix-test-lock" && run_err "$(json Edit "$LOCKED_REL")" | grep -qF "$LOCKED_REL is a locked failing test" && echo 0 || echo 1)"
check "the block names the unlock step"        0 \
  "$(run_err "$(json Edit "$LOCKED_REL")" | grep -qF ".claude/bugfix-lock only after the fix is verified" && echo 0 || echo 1)"
# An agent whose brief names a change to the locked test stalled on a question
# without this: the refusal itself carries the recipe.
ERR=$(run_err "$(json Edit "$LOCKED_REL")")
check "the block names the approved recipe"    0 \
  "$(grep -qF "delete the line '$LOCKED_REL'" <<<"$ERR" && grep -qF "Edit the line back" <<<"$ERR" \
     && grep -qF "evidence file" <<<"$ERR" && echo 0 || echo 1)"
# The refusal names the tool, so a Builder does not guess a shell edit of the lock file.
check "the block says to use the Edit tool on the lock file" 0 \
  "$(grep -qF "use the Edit tool on .claude/bugfix-lock" <<<"$ERR" && echo 0 || echo 1)"

# --- comments, blanks, whitespace --------------------------------------------
lock "# the coupon regression, unlock after node --test passes" "" "  $LOCKED_REL  "
check "comments and blank lines are ignored"   2 "$(run "$(json Edit "$LOCKED_REL")")"
check "a commented-out entry does not block"   0 "$(run "$(json Edit "$OTHER_REL")")"
lock "#$OTHER_REL"
check "a commented path is not locked"         0 "$(run "$(json Edit "$OTHER_REL")")"

# --- malformed entries warn, never block -------------------------------------
lock "$TMP/$LOCKED_REL"
check "absolute lock entry does NOT block"     0 "$(run "$(json Edit "$LOCKED_REL")")"
check "absolute lock entry warns on stderr"    0 \
  "$(run_err "$(json Edit "$LOCKED_REL")" | grep -qF "ignoring malformed lock entry" && echo 0 || echo 1)"
lock "src/../src/services/__tests__/coupon.test.ts"
check "'..' traversal entry does NOT block"    0 "$(run "$(json Edit "$LOCKED_REL")")"
check "'..' traversal entry warns"             0 \
  "$(run_err "$(json Edit "$LOCKED_REL")" | grep -qF "ignoring malformed lock entry" && echo 0 || echo 1)"
lock "src/services/__tests__/*.test.ts"
check "glob entry does NOT block"              0 "$(run "$(json Edit "$LOCKED_REL")")"
check "glob entry warns"                       0 \
  "$(run_err "$(json Edit "$LOCKED_REL")" | grep -qF "ignoring malformed lock entry" && echo 0 || echo 1)"
lock "$TMP/$OTHER_REL" "$LOCKED_REL"
check "a valid entry beside a malformed one still blocks" 2 "$(run "$(json Edit "$LOCKED_REL")")"

# --- absent and empty lock files ---------------------------------------------
: > "$TMP/.claude/bugfix-lock"
check "an empty lock file passes"              0 "$(run "$(json Edit "$LOCKED_REL")")"
lock "# only a comment"
check "a comment-only lock file passes"        0 "$(run "$(json Edit "$LOCKED_REL")")"
rm -f "$TMP/.claude/bugfix-lock"
check "an absent lock file passes"             0 "$(run "$(json Edit "$LOCKED_REL")")"
check "an absent lock file is SILENT"          "" "$(run_all "$(json Edit "$LOCKED_REL")")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
