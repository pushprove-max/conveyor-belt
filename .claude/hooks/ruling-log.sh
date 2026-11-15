#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PostToolUse (AskUserQuestion) and UserPromptSubmit hook: the decision log. Every picker answer the owner gives, and
# every message they type in the main checkout, becomes one JSONL row of the log lib/rulings.sh names for the
# session's project, with the clock it happened at. A note or rule that cites what the owner decided cites
# ruling:<id>, and ruling-cite-gate.sh refuses an id the log does not hold, so a ruling's time or words are never made
# up later.
#
# A row: {id, utc, time (local, with its zone), session, cwd, source (ask or prompt), header, question, answer,
# annotations, pick}. pick: "recommended" (the option the picker marked "(Recommended)"), "option" (another option, or
# several), "typed" (the owner's own words in a picker) or "prompt" (a typed message). The id is lib/rulings.sh's: two
# answers can land in one second from one session or from two, so the second alone is not an id.
# A picker answer prints one short line with its id(s) and closes the Board's open decision ask-records-decision.sh
# opened for it. A typed message prints nothing once logged. Either says so when it could not be logged.
set -uo pipefail
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
. "${BASH_SOURCE[0]%/*}/lib/rulings.sh"

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
case "$EVENT" in UserPromptSubmit|PostToolUse) ;; *) exit 0 ;; esac
ROOT=${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)}
# A message typed in a card or worker session is the engine's words, not the owner's.
[ "$EVENT" = PostToolUse ] || owner_session "${ROOT:-.}" || exit 0
# Hook feedback and local-command text are machine text, as is a message that is nothing but notification blocks.
# Hook feedback is only the harness's own opening, "<Event>[:<tool>] hook feedback:" or "... hook error:": the
# owner's words about a hook ("Fix hook error handling") are theirs and are logged.
[ "$EVENT" = UserPromptSubmit ] && printf '%s' "$INPUT" | jq -e '(.prompt // "")
    | test("^\\s*(<(local-command-|user-prompt-submit-hook)|(Stop|SubagentStop|PreToolUse|PostToolUse|UserPromptSubmit|SessionStart|SessionEnd|PreCompact|Notification)(:[A-Za-z0-9_-]+)? hook (feedback|error):)")
      or (gsub("<(task-notification|system-notification|system-reminder)>[\\s\\S]*?</\\1>"; "") | test("\\A\\s*\\z"))' \
    >/dev/null 2>&1 && exit 0

notlogged() { # <why>
  HOOK_FIRE_ADVISE=1
  local m="ruling NOT logged: $1. Record the answer by hand; there is no id to cite."
  if [ "$EVENT" = PostToolUse ]; then jq -cn --arg m "$m" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
  else printf '%s\n' "$m"; fi
  exit 0
}
# The session's project comes first: the log is in its state folder, and so is the Board's ledger. Left unset, the
# state folder named is the plugin install's own, which is read-only and no project's.
CONVEYOR_MAIN=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && [[ $CONVEYOR_MAIN == */.git ]] \
  || notlogged "no project checkout at ${ROOT:-.}"
export CONVEYOR_MAIN=${CONVEYOR_MAIN%/.git}
LOG=$(rulings_log) || notlogged "the state folder cannot be named (conveyor.sh state-dir failed)"
PREFIX=$(rulings_prefix) || notlogged "the host file's rulingPrefix is not letters and digits"
# A failed mkdir falls through: the append then fails and says so.
mkdir -p "$(dirname "$LOG")" 2>/dev/null
# A row can be large and an append that size is not one write, so every append holds flock on the log itself; a lock
# not taken in 10 s fails like any failed write.
append_log() { { flock -w 10 9 && printf '%s\n' "$1" >&9; } 9>>"$LOG"; } 2>/dev/null

# The event's arrival time, read before anything that can wait on a lock.
NOW=$(date +%s)
UTC=$(TZ=UTC printf '%(%Y-%m-%dT%H:%M:%SZ)T' "$NOW")
printf -v TIME '%(%Y-%m-%d %H:%M:%S %Z)T' "$NOW"
printf -v STAMP '%(%Y%m%d-%H%M%S)T' "$NOW"
printf -v DAY '%(%Y-%m-%d)T' "$NOW"
RND=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')

# The Board's open decisions this answer may close: from the owner's session only, so a worker's ask never closes
# one. Empty elsewhere. The ledger is the project's, the one its Board reads, never the plugin install's own checkout.
DECIDE="${BASH_SOURCE[0]%/*}/../scripts/decision.sh"
OPEN_ROWS=$(
  owner_session "${ROOT:-.}" || exit 0
  rows=$(bash "$DECIDE" list 2>/dev/null) || rows='[]'
  jq -c 'map(select(.answeredAt == null))' <<<"$rows" 2>/dev/null || echo '[]'
)
# Close the rows the owner answered. $@ = jq args and a program over $open (OPEN_ROWS) that emits [id, answer,
# matched]; an unmatched one is logged beside the log. The askedAt of the row read is passed on, so a row reopened
# since the read is refused. Never blocks.
answer_decisions() {
  local row id dlog err
  [ -n "$OPEN_ROWS" ] || return 0
  dlog="$(dirname "$LOG")/ask-records-decision.log"
  printf '%s' "$INPUT" | jq -c -L "${BASH_SOURCE[0]%/*}/lib" --argjson open "$OPEN_ROWS" "$@" 2>/dev/null |
  while IFS= read -r row; do
    id=$(jq -r '.[0]' <<<"$row")
    if [ "$(jq -r '.[2]' <<<"$row")" != true ]; then
      printf '%s no open decision %s asking this question\n' "$UTC" "$id" >> "$dlog" 2>/dev/null
    elif ! err=$(bash "$DECIDE" answer "$id" "$(jq -r '.[1]' <<<"$row")" --asked-at "$(jq -r --arg id "$id" '.[] | select(.id == $id) | .askedAt' <<<"$OPEN_ROWS")" 2>&1 >/dev/null); then
      printf '%s %s\n' "$UTC" "$err" >> "$dlog" 2>/dev/null
    fi
  done
}

if [ "$EVENT" = UserPromptSubmit ]; then
  PROW=$(printf '%s' "$INPUT" | jq -c --arg id "$PREFIX-$STAMP-p-$RND" --arg utc "$UTC" --arg time "$TIME" '
    select((.prompt // "") != "")
    | {id:$id, utc:$utc, time:$time, session:.session_id, cwd:.cwd, source:"prompt",
       header:null, question:null, answer:.prompt, annotations:null, pick:"prompt"}' 2>/dev/null) \
    || notlogged "this message could not be read"
  [ -n "$PROW" ] || exit 0
  append_log "$PROW" || notlogged "could not write $LOG"
  exit 0
fi

# The answer is a label, a comma-joined list of labels (multiSelect), or text the owner typed. "(Recommended)" marks
# the suggested option. A whole-label match comes first: a label may itself hold ", ".
ROWS=$(printf '%s' "$INPUT" | jq -c --arg pre "$PREFIX" --arg stamp "$STAMP" --arg rnd "$RND" --arg utc "$UTC" --arg time "$TIME" '
  . as $in | ($in.tool_response // {}) as $r
  | ($r.questions // $in.tool_input.questions // []) | to_entries[]
  | .key as $k | .value as $q
  | ($q.options // [] | map(.label)) as $labels
  | (($r.answers // $in.tool_input.answers // {})[$q.question] // "") as $a
  | ($a | split(", ")) as $parts
  | {id:"\($pre)-\($stamp)-\($k + 1)-\($rnd)", utc:$utc, time:$time, session:$in.session_id, cwd:$in.cwd,
     source:"ask", header:($q.header // null), question:$q.question, answer:$a,
     annotations:(($r.annotations // $in.tool_input.annotations // {})[$q.question]),
     pick:((if $labels | index($a) then [$a] elif $a != "" and ($parts | all(. as $p | $labels | index($p))) then $parts
            else null end) as $chosen
           | if $chosen == null then "typed" elif any($chosen[]; test("\\(Recommended\\)")) then "recommended"
             else "option" end)}' 2>/dev/null)
[ -n "$ROWS" ] || exit 0
# An id is only announced once it is on disk: a note citing an id the log never received would fail the gate.
append_log "$ROWS" || notlogged "could not write $LOG"
# Each answered question closes the row ask-records-decision.sh opened for it (same id rule, on any day: a picker asked
# before midnight is answered after it). A reused header names an older row asking something else: that row is not
# this answer's, so the question must match too; of several, the latest asked. With no such row, the open decision a
# repeat picker asked afresh under its own id (ask-records-decision.sh writes the picker's exact question to it).
answer_decisions --argjson rows "$(printf '%s\n' "$ROWS" | jq -s .)" --arg day "$DAY" '
  include "decision-id";
  . as $in | (($in.tool_response // {}).questions // $in.tool_input.questions // []) | to_entries[]
  | $rows[.key] as $row | select($row.answer != "")
  | (.value | decision_id($day)) as $today | ($today | .[:-11]) as $k | (.value.question // "") as $q
  | ([$open[] | select(.question == $q and (.id | startswith($k + "-") and (.[($k | length) + 1:] | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))))]
      | sort_by(.askedAt) | last
    // ([$open[] | select(.question == $q)] | sort_by(.askedAt) | last)) as $hit
  | [($hit.id // $today), "\($row.answer) (\($row.id))", $hit != null]'
MSG="ruling logged: $(printf '%s\n' "$ROWS" | jq -r '"\(.id) (\(.pick))"' | paste -sd, - | sed 's/,/, /g')"
printf '%s\n' "$ROWS" | jq -e 'select(.answer == "")' >/dev/null 2>&1 && HOOK_FIRE_ADVISE=1 && MSG="$MSG
The owner's answer came back blank; ask again."
jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
