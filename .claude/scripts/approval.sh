#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Usage: approval.sh <header>
# The approval a gate asks for, read from the decision log: exit 0 when the owner's latest answer today to a picker
# with exactly this header, asked in this project's main checkout, starts "Yes"; exit 1 otherwise. The header is
# compared whole, so one header never approves another. The latest answer decides, so a later "No" withdraws an
# earlier "Yes". A picker asked in another project, or in a worktree (never the owner's), approves nothing here. An
# approval is good for the day it was given only. A gate that refuses an action until the owner approves it calls
# this, and its refusal says to ask the owner by picker with that header.
# The project is CLAUDE_PROJECT_DIR, else the current folder.
. "${BASH_SOURCE[0]%/*}/../hooks/lib/rulings.sh"
[ -n "${1:-}" ] || { echo "usage: approval.sh <header>" >&2; exit 2; }
LOG=$(rulings_log) && PREFIX=$(rulings_prefix) || exit 1
HERE=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 1
printf -v DAY '%(%Y%m%d)T' -1
# Today's rows for this header, newest last: the folder each was asked in, then whether its answer is a Yes.
ROWS=$(jq -nrR --arg h "$1" --arg day "$PREFIX-$DAY-" '
  inputs | fromjson? | objects
  | select(.source == "ask" and (.void | not) and ((.id // "") | startswith($day)) and (.header // "") == $h)
  | [(.cwd // ""), ((.answer // "") | test("^\\s*yes\\b"; "i"))] | @tsv' "$LOG" 2>/dev/null)
LAST=
while IFS=$'\t' read -r cwd yes; do
  [ -n "$cwd" ] && owner_session "$cwd" \
    && [ "$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" = "$HERE" ] && LAST=$yes
done <<<"$ROWS"
[ "$LAST" = true ]
