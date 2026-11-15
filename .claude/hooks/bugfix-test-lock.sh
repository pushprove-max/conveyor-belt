#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PreToolUse hook (Edit|Write|MultiEdit): a failing test, once written, IS the
# spec for the fix. While its path is listed in .claude/bugfix-lock the file
# tools refuse to touch it -- fix the code, then rerun the test unmodified.
#
# CHARTER: a TRIPWIRE against the common path, not a security boundary. It
# deliberately does not parse Bash, so `sed -i` on a locked test sails through.
# That is the repo's standing ruling (.claude/rules/orchestration.md, "Role ->
# model"): inferring intent from arbitrary shell strings is not a winnable
# parse, and a guard with known bypasses that poses as complete is worse than
# no guard, because the operator stops checking.
#
# Lock file (repo root, gitignored): one repo-relative path per line; blank
# lines and `#` comments ignored. An absolute path, a `..` traversal or a glob
# is MALFORMED -- warned about on stderr and ignored, never honoured as a
# match. A lock entry nobody can read is an entry that blocks the wrong edit.
#
# Unlock is PROCESS, not mechanism: the path comes out of the lock file after
# the fix is verified. Nothing here enforces the timing; briefs and review do.

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] || exit 0
ROOT=$(realpath -m "$ROOT" 2>/dev/null || printf '%s' "$ROOT")

LOCK="$ROOT/.claude/bugfix-lock"
# No lock file is the normal state: silent pass-through, zero output.
[ -f "$LOCK" ] || exit 0

# MultiEdit carries edits[]; in this repo's payload the path stays on
# tool_input.file_path (dependency-addition-guard.sh folds edits[] the same
# way). A per-edit file_path costs one jq alternative to cover, and a
# payload-shape miss is the known bypass class for a path-matching hook.
TARGETS=$(echo "$INPUT" | jq -r '[
  .tool_input.file_path // empty,
  (.tool_input.edits // [] | .[] | .file_path // empty)
] | .[]' 2>/dev/null)
[ -z "$TARGETS" ] && exit 0

# Both sides go through the SAME canonicalizer: the tool may send an absolute
# path while the lock file holds a relative one, and a relative lock entry must
# still block the absolute input. -m keeps this working for a Write to a file
# that does not exist yet.
canon() {
  local _p
  case "$1" in
    /*) _p="$1" ;;
    *) _p="$ROOT/$1" ;;
  esac
  realpath -m "$_p" 2>/dev/null || printf '%s\n' "$_p"
}

LOCKED=()
while IFS= read -r RAW || [ -n "$RAW" ]; do
  LINE=$(printf '%s' "$RAW" | tr -d '\r')
  LINE="${LINE#"${LINE%%[![:space:]]*}"}"
  LINE="${LINE%"${LINE##*[![:space:]]}"}"
  [ -z "$LINE" ] && continue
  case "$LINE" in \#*) continue ;; esac
  case "$LINE" in
    /*|*..*|*\**|*\?*|*\[*|*\]*)
      echo "bugfix-test-lock: ignoring malformed lock entry '$LINE' -- entries are repo-relative paths, no '..' and no globs." >&2
      continue
      ;;
  esac
  LOCKED+=("$(canon "$LINE")")
done < "$LOCK"

[ ${#LOCKED[@]} -eq 0 ] && exit 0

while IFS= read -r TARGET; do
  [ -z "$TARGET" ] && continue
  ABS=$(canon "$TARGET")
  for L in "${LOCKED[@]}"; do
    [ "$ABS" = "$L" ] || continue
    REL="${ABS#"$ROOT"/}"
    cat >&2 <<EOF
BLOCKED (bugfix-test-lock): $REL is a locked failing test. Fix the code, not the test.
If your brief or a review finding names this change to the test, no question is needed:
use the Edit tool on .claude/bugfix-lock: delete the line '$REL', make only the named change, then Edit the line back,
and show the test's before and after in your evidence file. Anything wider is a question for main.
Otherwise leave the test as it is; the path comes out of .claude/bugfix-lock only after the fix is verified.
EOF
    exit 2
  done
done <<< "$TARGETS"

exit 0
