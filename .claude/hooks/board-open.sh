#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SessionStart hook (the plugin's, through shim.sh, which hooks/hooks.json calls only in a repo with a pack): opens the Board in the browser when a session starts fresh in a
# repo with a Conveyor pack, by lib/board-open.sh (board_open: the plugin option boardAutoOpen, the check, the start of a
# Board that is not running, the URL and the opener, shared with `foreman.sh claim`). Only the startup source opens it: a resume, clear or compact would
# stack another tab. Card sessions never get here: they run with --setting-sources "" and the engine's card settings,
# which carry no plugin hook.
#
# Self-test: bash .claude/hooks/__tests__/board-open.test.sh
set -uo pipefail

INPUT=$(cat)
[ "$(jq -r '.source // empty' <<<"$INPUT" 2>/dev/null)" = startup ] || exit 0
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT")}
[ -f "${ROOT:-.}/.conveyor/project.json" ] || exit 0
. "$(dirname "${BASH_SOURCE[0]}")/lib/board-open.sh" || exit 0
board_open "$ROOT"
exit 0
