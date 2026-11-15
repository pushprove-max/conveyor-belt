#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# stop.sh state | reply -- the Foreman's Stop hooks (the Foreman session only; every other session passes).
# state: while the saved state ($FD/state.md) is over its 5000-byte cap, the stop is blocked once with its size; the
#   second stop (stop_hook_active) passes, so it never loops. A warning at startup alone was ignored.
# reply: the turn's last reply (every text block after its last tool call) is refused once per turn (the turn is its opening entry: the newest user entry that is
#   not a tool result, nor meta unless it holds the wake; a refused turn is marked in reply-mark, so its next stop passes) when it
#   - asks the owner a question in text: questions to the owner go only by the picker (AskUserQuestion);
#   - answers a wake (the turn's opening entry holds the first line of last-wake.txt, waiter.sh) with more than what
#     needs the owner: a still-running line, a progress count, a "nothing needs you", a reply that never says you,
#     your or owner, or a sentence reporting a card (landed, merged, done ...) without them; a reply to a wake says only
#     what needs the owner, otherwise one word (Idle);
#   - leaves the Foreman's own work undone ("haven't filed it", "I still need to file", "I'll fix", "want me to ...").
set -uo pipefail
INPUT=$(cat)
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 0
foreman "$(jq -r '.session_id // empty | strings' <<<"$INPUT" 2>/dev/null)" || exit 0
block() { jq -cn --arg r "$1" '{decision: "block", reason: $r}'; exit 0; }

case ${1:-} in
  state)
    [ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" != true ] || exit 0
    n=$(p_stat "$FD/state.md" | cut -d' ' -f1); [ "${n:-0}" -gt 5000 ] || exit 0
    block "state.md is $n bytes, over its 5000-byte cap: mark finished items '- DONE' (they are archived at the next start) and shorten the rest" ;;
  reply) ;;
  *) echo "usage: stop.sh state | reply" >&2; exit 2 ;;
esac

T=$(jq -r '.transcript_path // empty' <<<"$INPUT" 2>/dev/null)
[ -n "$T" ] && [ -f "$T" ] || exit 0
W=$(head -n 1 "$FD/last-wake.txt" 2>/dev/null)
# The whole transcript is read: a long turn's opening entry may be thousands of entries back.
TURN=$(jq -cs --arg w "$W" 'def txt: .message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join("\n")) end;
  (map(.type == "user" and (((.isMeta // false) | not) or ($w != "" and (txt | contains($w))))
       and ((.message.content | type) != "array" or all(.message.content[]?; .type != "tool_result"))) | rindex(true)) as $i
  | if $i == null then empty else {uuid: (.[$i].uuid // ""), opening: (.[$i] | txt),
      reply: ([.[$i + 1:][] | select(.type == "assistant") | .message.content[]?] as $b | ($b | map(.type == "tool_use") | rindex(true)) as $k
        | [$b[(if $k == null then 0 else $k + 1 end):][] | select(.type == "text") | .text] | join("\n"))} end' "$T" 2>/dev/null)
U=$(jq -r '.uuid // empty' <<<"$TURN" 2>/dev/null); REPLY=$(jq -r '.reply // empty' <<<"$TURN" 2>/dev/null)
[ -n "$U" ] && [ -n "$REPLY" ] || exit 0
MARK=$FD/reply-mark
[ "$(cat "$MARK" 2>/dev/null)" != "$U" ] || exit 0
refuse() { { mkdir -p "$FD" && printf '%s\n' "$U" > "$MARK"; } 2>/dev/null || exit 0; block "$1"; }

if grep -qE '\?[[:space:]*_)]*($|[[:space:]])' <<<"$REPLY"; then
  refuse "Your reply asks the owner a question in text. Ask the owner only with the picker (AskUserQuestion), with the options you propose; keep the rest of the reply."
fi
if [ -n "$W" ] && jq -e --arg w "$W" '.opening | contains($w)' <<<"$TURN" >/dev/null 2>&1 && [ "$(wc -w <<<"$REPLY")" -gt 1 ]; then
  # What needs the owner is said to them: a reply that never says you, your or owner reports, and so does a sentence
  # that gives a card's progress without them.
  HIT=$(grep -oiE 'still (running|working|in progress)|not done yet|\b[0-9]+ ?(of|/) ?[0-9]+\b[^.]*\b(done|passed|landed|tests?)\b|nothing (needs|for) you|no action (needed|required)' <<<"$REPLY" | head -3 | paste -sd'|' -)
  [ -n "$HIT" ] || grep -qiwE "you|your|owner('?s)?" <<<"$REPLY" || HIT="a report"
  [ -n "$HIT" ] || HIT=$(tr '\n' ' ' <<<"$REPLY" | grep -oE '[^.!?]+' | grep -viwE "you|your|owner('?s)?" \
    | grep -iwE 'landed|merged|pushed|passed|succeeded|finished|completed|released|deployed|done|running|in progress' | sed 's/^ *//' | head -3 | paste -sd'|' -)
  [ -z "$HIT" ] || refuse "A reply to a wake says only what needs the owner to act or decide ($HIT is not that). Rewrite it without that, or reply with the one word Idle if nothing needs them."
fi
HIT=$(grep -oiE "(haven'?t|have not|did not|didn'?t|not yet) (filed|file it|sent|fixed|checked)|not filed yet|want me to|shall i|should i |if you'?d like|i can (also )?(file|fix|send|check|do|open|run)|let me know if|\b(i|we) (still|yet) (need|have|got) to|\bi (need|have) to (file|fix|send|check|retry|open|run|hold|release)|\bi('ll| will) (file|fix|send|check|retry|open|run|hold|release)|\b(next|later),? i('ll| will)" <<<"$REPLY" | head -3 | paste -sd'|' -)
[ -z "$HIT" ] || refuse "Unfinished work in your reply ($HIT). If it is yours to do (file, check, retry, fix), do it now and say it is done. Keep the line only when it truly needs the owner, and say why in the same sentence."
exit 0
