#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PreToolUse hook on AskUserQuestion: only the owner's session (the main checkout, where the Foreman runs) may ask the
# owner. A card, worker or reviewer session runs in a linked worktree: its picker draws in that session alone, never
# reaches the owner, and the session waits on nobody. Questions to the owner go through the main checkout, where
# ruling-log.sh logs each answer with an id.
#
# Self-test: bash .claude/hooks/__tests__/worker-ask-guard.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
. "${BASH_SOURCE[0]%/*}/lib/rulings.sh"
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT")}
# Outside any git checkout there is no card or worker to stop.
git -C "${ROOT:-.}" rev-parse --git-dir >/dev/null 2>&1 || exit 0
owner_session "${ROOT:-.}" && exit 0

printf '%s\n' \
  "BLOCKED: do not ask. AskUserQuestion in a card or worker session is never seen by the owner: it draws in this session only, so you would wait forever." \
  "Choose a reasonable default, record the choice and why in your closing note, and carry on." >&2
exit 2
