#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Pins where the decision log is written: in the state folder of the session's project, never the plugin install's.
# A project runs the hook from its pinned install, which is read-only: a log named there is never written, and what
# the owner decided in that project is lost with nothing said.
set -u
. "$(dirname "$0")/lib/rulings-fixture.sh"
HOOK=$PLUG/.claude/hooks/ruling-log.sh
# This machine is not the project's host: the host file names another checkout, so the project's state folder is its
# own conveyor/state, which no one has made yet.
jq -n --arg m "$T/elsewhere" --arg s "$T/state" '{main: $m, stateDir: $s, rulingPrefix: "q"}' > "$T/config/conveyor/host.json"
PLOG=$MAIN/conveyor/state/foreman/rulings.jsonl
rows() { wc -l 2>/dev/null < "$PLOG" | tr -d ' '; }

# Run as a project runs it: from the install, whose own folder is read-only, with the session's folder in the input.
typed() { jq -cn --arg cwd "$MAIN" '{hook_event_name:"UserPromptSubmit", session_id:"s1", cwd:$cwd, prompt:"hold the billing work"}' | (cd "$PLUG" && bash "$HOOK"); }
picked() {
  jq -cn --arg cwd "$MAIN" '{hook_event_name:"PostToolUse", tool_name:"AskUserQuestion", session_id:"s1", cwd:$cwd,
    tool_input:{questions:[{header:"Deploy", question:"Ship it today?", options:[{label:"Yes"},{label:"No"}]}]},
    tool_response:{answers:{"Ship it today?":"Yes"}}}' | (cd "$PLUG" && bash "$HOOK")
}
listing() { find "$PLUG" -not -path "$PLUG/.git/*" | LC_ALL=C sort; }
chmod -R a-w "$PLUG"; trap 'chmod -R u+w "$PLUG"; rm -rf "$T"' EXIT
before=$(listing)

check "the project's state folder is not there yet" no "$([ -e "$MAIN/conveyor/state" ] && echo yes || echo no)"
typed >/dev/null
check "a typed message makes the missing state folder and adds one row to the project's log" "1|hold the billing work" \
  "$(rows)|$(tail -n 1 "$PLOG" 2>/dev/null | jq -r .answer)"
out=$(picked)
check "a picker answer adds one row to the project's log" "2|Yes" "$(rows)|$(tail -n 1 "$PLOG" 2>/dev/null | jq -r .answer)"
check "the picker is told the id that is in the project's log" "ruling logged: $(tail -n 1 "$PLOG" 2>/dev/null | jq -r .id) (option)" \
  "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")"
check "nothing is written under the install" "$before" "$(listing)"
check "nothing is written in the host's state folder, which is another checkout's" no "$([ -e "$T/state/foreman/rulings.jsonl" ] && echo yes || echo no)"

# A log that cannot be written: the typed message says so, as a picker answer does.
rm -rf "$MAIN/conveyor/state"; : > "$MAIN/conveyor/state"
check "a typed message that cannot be logged says so" yes "$(typed | grep -q '^ruling NOT logged: could not write ' && echo yes || echo no)"
check "a picker answer that cannot be logged says so" yes \
  "$(picked | jq -r .hookSpecificOutput.additionalContext | grep -q '^ruling NOT logged: could not write ' && echo yes || echo no)"
finish
