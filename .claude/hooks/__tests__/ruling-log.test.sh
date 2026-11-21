#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Pins the decision log: a picker answer is logged in the state folder with an id of the host file's prefix, the
# choice and whether it was the recommended option, and the id is told back only once it is on disk. Without it a
# ruling's words and time are remembered, not recorded, and a note can cite one that was never given.
set -u
. "$(dirname "$0")/lib/rulings-fixture.sh"
HOOK=$PLUG/.claude/hooks/ruling-log.sh

ask() { # <answer> -> the hook's stdout, run in the main checkout
  jq -cn --arg cwd "$MAIN" --arg a "$1" '{hook_event_name:"PostToolUse", tool_name:"AskUserQuestion", session_id:"s1", cwd:$cwd,
    tool_input:{questions:[{header:"Deploy", question:"Ship it today?", options:[{label:"Yes, ship (Recommended)"},{label:"No, wait"}]}]},
    tool_response:{answers:{"Ship it today?":$a}}}' | bash "$HOOK"
}

out=$(ask "Yes, ship (Recommended)")
row=$(tail -n 1 "$LOG" 2>/dev/null)
check "the recommended option is logged as recommended" "recommended" "$(jq -r .pick <<<"$row")"
check "the choice is logged" "Yes, ship (Recommended)" "$(jq -r .answer <<<"$row")"
check "the question and header are logged" "Deploy|Ship it today?" "$(jq -r '"\(.header)|\(.question)"' <<<"$row")"
id=$(jq -r .id <<<"$row")
check "the id is <prefix>-<date>-<time>-<n>-<hash> with the host file's prefix" yes \
  "$([[ $id =~ ^q-[0-9]{8}-[0-9]{6}-1-[0-9a-f]{6}$ ]] && echo yes || echo "no: $id")"
check "the picker is told the logged id" "ruling logged: $id (recommended)" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")"

ask "No, wait" >/dev/null
check "another option is logged as not the recommended one" "option" "$(tail -n 1 "$LOG" | jq -r .pick)"
jq -cn --arg cwd "$MAIN" '{hook_event_name:"PostToolUse", tool_name:"AskUserQuestion", session_id:"s1", cwd:$cwd,
  tool_input:{questions:[{header:"Mode", question:"Which modes?", multiSelect:true, options:[{label:"Fast (Recommended)"},{label:"Safe"}]}]},
  tool_response:{answers:{"Which modes?":"Fast (Recommended), Safe"}}}' | bash "$HOOK" >/dev/null
check "picking the recommended option beside another keeps the recommended flag" "recommended" "$(tail -n 1 "$LOG" | jq -r .pick)"
ask "only after the tests pass" >/dev/null
check "the owner's own words are logged as typed" "typed" "$(tail -n 1 "$LOG" | jq -r .pick)"

# A message the owner types in the main checkout is logged with a p id; a card session's is the engine's words.
# prompt_rows <cwd> <prompt>: the rows one UserPromptSubmit call added, counted around that call alone, so a wrong
# result is reported by its own call (the hook's last input) and never carried into the next check.
prompt_rows() {
  local b; b=$(wc -l < "$LOG")
  jq -cn --arg cwd "$1" --arg p "$2" '{hook_event_name:"UserPromptSubmit", session_id:"s1", cwd:$cwd, prompt:$p}' | bash "$HOOK"
  echo $(( $(wc -l < "$LOG") - b ))
}
check "a message typed in the main checkout is logged" 1 "$(prompt_rows "$MAIN" "hold the billing work")"
check "a message typed in the main checkout is logged with a p id" yes \
  "$(tail -n 1 "$LOG" | jq -r '.id' | grep -qE '^q-[0-9]{8}-[0-9]{6}-p-[0-9a-f]{6}$' && echo yes || echo no)"
check "a card session's message is not logged" 0 "$(prompt_rows "$CARD" "build the card")"
check "machine text is not logged" 0 "$(prompt_rows "$MAIN" "<system-reminder>x</system-reminder>")"
# Only the harness's own feedback line is machine text: the owner's words about a hook are a ruling like any other,
# and dropping them loses it without a word.
for p in 'Stop hook feedback: Conveyor: blocked' 'PreToolUse:Bash hook error: exit 2'; do
  check "the harness's hook feedback is not logged" 0 "$(prompt_rows "$MAIN" "$p")"
done
for p in 'Fix hook error handling' 'The hook feedback: make it shorter'; do
  check "the owner's words about a hook are logged" "1|$p" "$(prompt_rows "$MAIN" "$p")|$(tail -n 1 "$LOG" | jq -r .answer)"
done

# ruling-id.sh finds the owner's words in the same log.
check "ruling-id.sh finds a logged answer by its words" yes \
  "$(bash "$PLUG/.claude/scripts/ruling-id.sh" "AFTER the tests" | grep -qE '^q-[0-9]{8}-[0-9]{6}-1-' && echo yes || echo no)"
check "ruling-id.sh finds a typed message by its words" yes \
  "$(bash "$PLUG/.claude/scripts/ruling-id.sh" "BILLING work" | grep -qE '^q-[0-9]{8}-[0-9]{6}-p-' && echo yes || echo no)"

# The question goes to the project's Board ledger, never the plugin install's, and the answer closes it there: the
# Board's Needs-you card is read from the project's.
mkdir -p "${LEDGER%/*}"; : > "$LEDGER"
pick=$(jq -cn --arg cwd "$MAIN" '{hook_event_name:"PreToolUse", tool_name:"AskUserQuestion", session_id:"s1", cwd:$cwd,
  tool_input:{questions:[{header:"Billing", question:"Start billing now?", options:[{label:"Yes (Recommended)"},{label:"No"}]}]}}')
bash "$PLUG/.claude/hooks/ask-records-decision.sh" <<<"$pick" >/dev/null 2>&1
check "the picker's question is an open row in the project's ledger" "Start billing now?|null" \
  "$(tail -n 1 "$LEDGER" | jq -r '"\(.question)|\(.answer)"')"
check "the plugin install has no ledger" no "$([ -e "$PLUG/.claude/metrics/decisions.jsonl" ] && echo yes || echo no)"
jq -c '.hook_event_name = "PostToolUse" | .tool_response = {answers: {"Start billing now?": "No"}}' <<<"$pick" \
  | bash "$HOOK" >/dev/null
check "the answer closes the row in the project's ledger" "No (q-" "$(tail -n 1 "$LEDGER" | jq -r '.answer[:6]')"

# A picker asked before midnight and answered after it still closes its row, whose id holds the day it was asked.
CONVEYOR_MAIN=$MAIN bash "$PLUG/.claude/scripts/decision.sh" add late-1999-12-31 "Ship the late fix?" none AskUserQuestion >/dev/null 2>&1
jq -cn --arg cwd "$MAIN" '{hook_event_name:"PostToolUse", tool_name:"AskUserQuestion", session_id:"s1", cwd:$cwd,
  tool_input:{questions:[{header:"Late", question:"Ship the late fix?", options:[{label:"Yes"},{label:"No"}]}]},
  tool_response:{answers:{"Ship the late fix?":"Yes"}}}' | bash "$HOOK" >/dev/null
check "an answer after midnight closes the row asked the day before" "late-1999-12-31|Yes (q-" \
  "$(tail -n 1 "$LEDGER" | jq -r '"\(.id)|\(.answer[:7])"')"

# The owner is asked by picker whenever the session asks: a question that repeats an open decision, or one answered in
# the last 24 hours, is not refused (the hook once exited 2 and the owner never saw it). Each question still gets its
# row, and once the owner answers no open row is left for the question, or Needs you shows it twice or forever.
DAY=$(date +%Y-%m-%d)
picker() { # <questions JSON> -> the PreToolUse input
  jq -cn --arg cwd "$MAIN" --argjson qs "$1" '{hook_event_name:"PreToolUse", tool_name:"AskUserQuestion", session_id:"s1",
    cwd:$cwd, tool_input:{questions:$qs}}'
}
q1() { jq -cn --arg h "$1" --arg q "$2" '[{header:$h, question:$q, options:[{label:"Yes (Recommended)"},{label:"No"}]}]'; }
answered() { # <PreToolUse input> <question> <answer>: the owner's answer reaches ruling-log.sh
  jq -c --arg q "$2" --arg a "$3" '.hook_event_name = "PostToolUse" | .tool_response = {answers: {($q): $a}}' <<<"$1" \
    | bash "$HOOK" >/dev/null
}
ask_pre() { bash "$PLUG/.claude/hooks/ask-records-decision.sh" <<<"$1" >"$T/pre.out" 2>"$T/pre.err"; echo "$?|$(wc -c < "$T/pre.out" | tr -d ' ')"; }
# The ledger reads run bash itself (command bash): a read is not a hook's input, so a FAIL line still names the hook's.
open_for() { CONVEYOR_MAIN=$MAIN command bash "$PLUG/.claude/scripts/decision.sh" list | jq -r --arg q "$1" '[.[] | select(.answeredAt == null and .question == $q)] | length'; }
row_of() { CONVEYOR_MAIN=$MAIN command bash "$PLUG/.claude/scripts/decision.sh" list | jq -r --arg id "$1" '.[] | select(.id == $id) | "\(.question)|\(.answer)"'; }

CONVEYOR_MAIN=$MAIN bash "$PLUG/.claude/scripts/decision.sh" add chat-rollback "Roll back the billing release?" none main >/dev/null 2>&1
p=$(picker "$(q1 Rollback "Should we roll back the billing release?")")
check "a picker repeating an open decision reaches the owner: exit 0, no refusal printed" "0|0" "$(ask_pre "$p")"
# The repeat is that open decision asked again, not a second row: a second row (or the old one closed with a made-up
# answer) leaves the decision without the owner's own answer.
check "the open decision it repeats is its row, open, with the picker's question" "Should we roll back the billing release?|null" \
  "$(row_of chat-rollback)"
check "no second row under the picker's id" "" "$(row_of "rollback-$DAY")"
answered "$p" "Should we roll back the billing release?" "No"
check "after the owner answers, no open row is left for the question" "0|0" \
  "$(open_for "Roll back the billing release?")|$(open_for "Should we roll back the billing release?")"
check "the owner's answer closes that same decision" "No (q-" "$(row_of chat-rollback | cut -d'|' -f2 | cut -c1-6)"

# Asked again after that answer: a repeat of a decision answered minutes ago gets its own row under the picker's id;
# the same picker again asks that id afresh, never a second open row.
p=$(picker "$(q1 Rollback "Roll back the billing release now?")")
check "a picker repeating a decision answered minutes ago reaches the owner" "0|0" "$(ask_pre "$p")"
check "its row is open under the picker's id, with the picker's question" "Roll back the billing release now?|null" \
  "$(row_of "rollback-$DAY")"
ask_pre "$p" >/dev/null
check "the same picker asked twice leaves one open row" 1 "$(open_for "Roll back the billing release now?")"
answered "$p" "Roll back the billing release now?" "Yes (Recommended)"
check "the answer closes it" 0 "$(open_for "Roll back the billing release now?")"

# A picker of several questions, one repeating an open decision: every question gets its row.
CONVEYOR_MAIN=$MAIN bash "$PLUG/.claude/scripts/decision.sh" add chat-vendor "Switch the mail vendor this month?" none main >/dev/null 2>&1
p=$(picker "$(jq -cn '[{header:"Vendor", question:"Switch the mail vendor this month?", options:[{label:"Yes"},{label:"No"}]},
  {header:"Region", question:"Move the queue to the second region?", options:[{label:"Yes"},{label:"No"}]}]')")
check "a picker of several questions with one repeat reaches the owner" "0|0" "$(ask_pre "$p")"
check "every question in it has an open row: the repeat's is the decision it repeats" \
  "Switch the mail vendor this month?|null Move the queue to the second region?|null" \
  "$(row_of chat-vendor) $(row_of "region-$DAY")"
jq -c '.hook_event_name = "PostToolUse" | .tool_response = {answers: {"Switch the mail vendor this month?": "No",
  "Move the queue to the second region?": "Yes"}}' <<<"$p" | bash "$HOOK" >/dev/null
check "after the answers no open row is left for either question" "0 0" \
  "$(open_for "Switch the mail vendor this month?") $(open_for "Move the queue to the second region?")"
check "each answer closes its own row" "No (q-|Yes (q-" \
  "$(row_of chat-vendor | cut -d'|' -f2 | cut -c1-6)|$(row_of "region-$DAY" | cut -d'|' -f2 | cut -c1-7)"

# A log that cannot be written gives no id: the picker is told so.
rm -rf "$T/state"; : > "$T/state"
out=$(ask "No, wait")
check "an unwritable log announces no id" yes \
  "$(jq -r .hookSpecificOutput.additionalContext <<<"$out" | grep -q '^ruling NOT logged' && echo yes || echo no)"
finish
