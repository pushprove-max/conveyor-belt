#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PreToolUse hook on AskUserQuestion, in the owner's session (the main checkout) only: every question put to the owner
# becomes a row in the Board's decisions ledger (decision.sh), the source of the Board's Needs-you card.
#
# Row: id = the header slug plus today's date (lib/decision-id.jq), proposed default = the option marked
# "(Recommended)" without the marker, else "none"; options = the labels without the marker when there are 2 to 4 valid
# ones (the card's buttons). The hook refuses no picker: there is no check for a repeat. A question that repeats one
# still open, or answered in the last 24 hours (decision.sh exit 3), goes to the owner like any other. A repeat of an
# open decision asks that same decision afresh (--reask under its own id, with the picker's question), so the owner's
# answer closes it and no second open row is made; a repeat of an answered one gets its row under the picker's id with
# --reask. Any other refused add (a same-day header reused for another question) is logged beside the decision log and
# the question still goes out. ruling-log.sh closes the row.
#
# Self-test: bash .claude/hooks/__tests__/ruling-log.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
. "${BASH_SOURCE[0]%/*}/lib/rulings.sh"
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT")}
# A linked worktree has no ledger to write (worker-ask-guard.sh refuses its picker).
owner_session "${ROOT:-.}" || exit 0
# The project's ledger, the one its Board reads, never the plugin install's own checkout (read-only, and no Board's).
CONVEYOR_MAIN=$(git -C "${ROOT:-.}" rev-parse --show-toplevel) || exit 0
export CONVEYOR_MAIN
LOG=$(rulings_log) && LOG="$(dirname "$LOG")/ask-records-decision.log" || LOG=/dev/null

DECIDE="${BASH_SOURCE[0]%/*}/../scripts/decision.sh"
ROWS=$(jq -c -L "${BASH_SOURCE[0]%/*}/lib" --arg day "$(date +%Y-%m-%d)" 'include "decision-id"; .tool_input.questions[]? | [
  decision_id($day),
  (.question // ""),
  ([.options[]?.label // "" | select(test("\\(Recommended\\)\\s*$"))] | first
    | if . == null then "none" else sub("\\s*\\(Recommended\\)\\s*$"; "") end),
  ([.options[]?.label // ""] | map(sub("\\s*\\(Recommended\\)\\s*$"; ""))
    | if length >= 2 and length <= 4 and all(.[]; length >= 1 and length <= 500 and test("^(?:[^\\p{C}\\p{Z}]| )+$")) then . else null end)]' <<<"$INPUT" 2>/dev/null)

# note <decision.sh's refusal>: logged beside the decision log; the picker still goes out.
note() {
  HOOK_FIRE_ADVISE=1
  mkdir -p "${LOG%/*}" 2>/dev/null
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" | tee -a "$LOG" >&2
}
while IFS= read -r row; do
  [ -n "$row" ] || continue
  id=$(jq -r '.[0]' <<<"$row") q=$(jq -r '.[1]' <<<"$row") d=$(jq -r '.[2]' <<<"$row")
  opts=(); jq -e '.[3] != null' <<<"$row" >/dev/null && opts=(--options "$(jq -c '.[3]' <<<"$row")")
  # On exit 3, the line that is JSON is the earlier decision's snapshot; the rest is decision.sh's reason.
  res=$(bash "$DECIDE" add "$id" "$q" "$d" AskUserQuestion ${opts[@]+"${opts[@]}"} 2>&1) && continue
  rc=$? prev=$(grep '^{' <<<"$res" | tail -n 1) err=$(grep -v '^{' <<<"$res")
  [ "$rc" -eq 3 ] && pid=$(jq -er '.id' <<<"$prev" 2>/dev/null) || { note "$err"; continue; }
  if [ "$pid" != "$id" ] && jq -e '.answeredAt == null' <<<"$prev" >/dev/null; then
    # The open decision it repeats is this question's row: asked afresh under its own id, unit kept, with the picker's
    # exact question, which ruling-log.sh matches to close that decision with the owner's answer.
    u=$(jq -r '.unit // empty' <<<"$prev")
    e=$(bash "$DECIDE" add "$pid" "$q" "$d" AskUserQuestion ${opts[@]+"${opts[@]}"} ${u:+--unit "$u"} \
      --reask "picker $id repeats it" 2>&1 >/dev/null) || note "$e"
    continue
  fi
  # --reask writes over the id it is given: an id already holding another question keeps it.
  [ "$pid" = "$id" ] || ! bash "$DECIDE" list 2>/dev/null | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null \
    || { note "decision: decision $id already exists; \"$q\" repeats $pid and has no row of its own"; continue; }
  # The same id (same header, same day) is asked afresh in place: one open snapshot, the picker's question.
  e=$(bash "$DECIDE" add "$id" "$q" "$d" AskUserQuestion ${opts[@]+"${opts[@]}"} --reask "picker repeats $pid" 2>&1 >/dev/null) \
    || note "$e"
done <<<"$ROWS"
exit 0
