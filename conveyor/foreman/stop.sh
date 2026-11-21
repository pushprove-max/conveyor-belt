#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# stop.sh state | reply -- the Foreman's Stop hooks (the Foreman session only; every other session passes).
# state: while the open lines of the saved state ($FD/state.md: all but the '- DONE' items, with their indented lines,
#   which the next start archives, archive.py) are over the cap (CAP in foreman.sh), the stop is blocked once with their size; the
#   second stop (stop_hook_active) passes, so it never loops. A warning at startup alone was ignored.
# reply: the turn's last reply (every text block after its last tool call or user entry, such as a refused stop's
#   feedback) is refused once per turn (the turn is its opening entry: the newest user entry that is
#   not a tool result, nor meta unless it holds the wake; a refused turn is marked in reply-mark, so its next stop passes) when it
#   - asks the owner a question in text: questions to the owner go only by the picker (AskUserQuestion);
#   - answers a wake (the turn's opening entry holds the first line of last-wake.txt, waiter.sh) with more than what
#     needs the owner: a still-running line, a progress count, a "nothing needs you", a reply that never says you,
#     your or owner, or a sentence reporting a card (landed, merged, done ...) without them; a reply to a wake says only
#     what needs the owner, otherwise one word (Idle); a turn in which the owner typed a message (a queued_command
#     entry of human origin after the opening) answers the owner, so its reply is not judged as a wake reply;
#   - leaves the Foreman's own work undone ("haven't filed it", "I still need to file", "I'll fix", "want me to ..."); an "I'll <verb>" in a
#     sentence that ties it to a later event or a standing rule (when, once, after, until, every, if ...) is not that.
#   A line in the plugin-problem form (PLUG: "Plugin problem (for the conveyor-belt repo): <what was seen>") reports a
#   suspected defect in Conveyor itself, which the owner fixes (the owner files it too, except in the plugin's own
#   repository, where the Foreman files it): it needs the owner, so the wake and
#   unfinished-work checks read the reply without it, and each such line is noted once in $FD/plugin-bugs.md (time,
#   card, what was seen, evidence path) before any check, so the finding outlives a refused or short reply. In the
#   plugin's own repository (lib.sh plugin_home) the Foreman files it there itself, so a line that does not end
#   "filed as #<n>" is refused too, at every stop of the turn (not only once, as the checks above are).
# Each refused stop is noted in $FD/refused-stops (lib.sh refused_put), which waiter.sh reads.
set -uo pipefail
INPUT=$(cat)
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 0
foreman "$(jq -r '.session_id // empty | strings' <<<"$INPUT" 2>/dev/null)" || exit 0
# block <reason>: refuses the stop, noted by its stop_key (lib.sh), so the waiter relays again a wake it relayed at it.
block() {
  refused_put "$(stop_key "$(jq -r '.transcript_path // empty | strings' <<<"$INPUT" 2>/dev/null)")"
  jq -cn --arg r "$1" '{decision: "block", reason: $r}'; exit 0
}

case ${1:-} in
  state)
    [ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" != true ] || exit 0
    cap=$(sed -n 's/^CAP=\([0-9][0-9]*\)[ ;].*/\1/p' "$(dirname "${BASH_SOURCE[0]}")/foreman.sh" 2>/dev/null)
    [ -n "$cap" ] || { echo "stop.sh: no CAP=<bytes> line in foreman.sh" >&2; exit 2; }
    # The same split archive.py makes: an item starts at a line beginning '- DONE', or beginning '- ' and ending ' - DONE', and runs over the indented lines after it.
    n=$(LC_ALL=C awk '/^- DONE/ || /^- .* - DONE[ \t]*$/ { skip = 1; next } /^[ \t]/ { if (!skip) print; next } { skip = 0; print }' "$FD/state.md" 2>/dev/null | wc -c | tr -d ' ')
    [ "${n:-0}" -gt "$cap" ] || exit 0
    block "state.md has $n bytes of open lines, over its $cap-byte cap: begin the line of a finished item with '- DONE', as '- DONE 2026-11-21 08:20 ET: ...' (they are archived at the next start) and shorten the rest" ;;
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
      owner: any(.[$i + 1:][]; .type == "attachment" and .attachment.type? == "queued_command" and .attachment.origin.kind? == "human"),
      # reply: the text after the last tool call or user entry (a refused stop adds its feedback as a user
      # entry), so a refused reply is never checked or noted again at the next stop.
      reply: ([.[$i + 1:][] | if .type == "user" then {cut: true} elif .type == "assistant" then (.message.content[]? | if .type == "tool_use" then {cut: true} else . end) else empty end] as $c
        | ($c | map(.cut == true) | rindex(true)) as $k | [$c[(if $k == null then 0 else $k + 1 end):][] | select(.type == "text") | .text] | join("\n"))} end' "$T" 2>/dev/null)
U=$(jq -r '.uuid // empty' <<<"$TURN" 2>/dev/null); REPLY=$(jq -r '.reply // empty' <<<"$TURN" 2>/dev/null)
[ -n "$U" ] && [ -n "$REPLY" ] || exit 0
PLUG='^[[:space:]*_>-]*plugin problem \(for the conveyor-belt repo\):[[:space:]*_]*'
FORM="'Plugin problem (for the conveyor-belt repo): <what you saw>, card <card>, evidence <path>'"
# Each plugin-problem line is noted once: a reply that says it again (after a refusal) adds no second note. A line
# that ends "filed as #<n>" names the issue it was filed as; in the plugin's own repository, said after the same line
# without it (or as the line context gives a listed note), it takes that note's place, so the note names the issue
# (context lists those with none).
# An issue number is 1 or more: "filed as #0" names no issue, so that line is refused and noted without it, as unfiled.
NOTES=$FD/plugin-bugs.md
FILED='[,;]?[[:space:]]*filed as #([1-9][0-9]*)[[:space:]]*\.?$'
NOISSUE='[,;]?[[:space:]]*filed as #[0-9]+[[:space:]]*\.?$'
UNFILED=()
shopt -s nocasematch
while IFS= read -r l; do
  [[ $l =~ $PLUG ]] || continue
  seen=${l:${#BASH_REMATCH[0]}}; seen=${seen%"${seen##*[![:space:]]}"}; [ -n "$seen" ] || continue
  what=$seen
  if [[ $seen =~ $FILED ]]; then what=${seen:0:${#seen}-${#BASH_REMATCH[0]}}
  else
    # A number that names no issue is left out of the note, so the line with a valid number later takes its place.
    [[ $seen =~ $NOISSUE ]] && { seen=${seen:0:${#seen}-${#BASH_REMATCH[0]}}; what=$seen; }
    [ -n "$seen" ] || continue
    UNFILED+=("$what")
  fi
  ! grep -qF -- " · $seen · evidence: " "$NOTES" 2>/dev/null || continue
  card=$(grep -oE '\bc[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]*[A-Za-z0-9]|#[0-9]+' <<<"$what" | head -n 1)
  ev=$(grep -oE "(~|\.{1,2})?/[^[:space:],;()'\"\`]+|[A-Za-z0-9._-]+/[^[:space:],;()'\"\`]+" <<<"$what" | head -n 1); ev=${ev%.}
  # In the plugin's own repository (plugin_home) a filed line takes the place of the first note that names no issue
  # and says the same thing: its own text (the line the start-up list gives for it), or that text with its own card
  # and evidence fields after it. Never a note that only shares a card or path: that may be a different problem. In
  # any other project the owner files it, and a filed line is noted as its own row, as before.
  if [ "$what" != "$seen" ] && [ -s "$NOTES" ] && plugin_home \
    && W="$what" S="$seen" LC_ALL=C awk '
      BEGIN { D = " · "; C = " · card "; E = " · evidence: " }
      !done && /^- / && tolower($0) !~ / filed as #[1-9][0-9]*[[:space:]]*\.? · evidence: / && (i = index($0, C)) {
        r = substr($0, i + length(C)); j = index(r, D); card = substr(r, 1, j - 1); t = substr(r, j + length(D))
        k = 0; while ((m = index(substr(t, k + 1), E))) k += m
        if (j && k) { ev = substr(t, k + length(E)); t = substr(t, 1, k - 1)
          if (t == ENVIRON["W"] || t ", card " card ", evidence " ev == ENVIRON["W"]) {
            $0 = substr($0, 1, i - 1) C card D ENVIRON["S"] E ev; done = 1 } } }
      { print } END { exit !done }' "$NOTES" > "$NOTES.new" 2>/dev/null; then
    mv -f "$NOTES.new" "$NOTES" 2>/dev/null
    continue
  fi
  rm -f "$NOTES.new" 2>/dev/null
  { mkdir -p "$FD" && { [ -s "$NOTES" ] || printf '# Plugin problems the Foreman noted (for the conveyor-belt repo)\n\n'
    printf -- '- %s · card %s · %s · evidence: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${card:--}" "$seen" "${ev:--}"; } >> "$NOTES"; } 2>/dev/null
done < <(grep -iE "${PLUG}[^[:space:]]" <<<"$REPLY")
shopt -u nocasematch
# The wake and unfinished-work checks below read the reply without its plugin-problem lines.
REST=$(grep -viE "$PLUG" <<<"$REPLY")
# In the plugin's own repository (plugin_home) a plugin problem is the Foreman's to file there: a line naming no
# issue is refused at every stop, not once per turn (reply-mark is not read or set here), so a reply never ends with it
# unfiled; filing it, or leaving the line out (its note stays listed at start-up), lets the stop pass. In any other
# project the owner files it, and the line passes as it is.
if [ ${#UNFILED[@]} != 0 ] && plugin_home; then
  block "This project is the plugin's own repository, so a plugin problem is a defect you file here yourself, as any issue you file (it starts held until the owner says yes). File it now, then name the issue at the end of the line: 'Plugin problem (for the conveyor-belt repo): <what you saw>, card <card>, evidence <path>, filed as #<n>'. Not filed: ${UNFILED[0]}"
fi
MARK=$FD/reply-mark
[ "$(cat "$MARK" 2>/dev/null)" != "$U" ] || exit 0
refuse() { { mkdir -p "$FD" && printf '%s\n' "$U" > "$MARK"; } 2>/dev/null || exit 0; block "$1"; }

if grep -qE '\?[[:space:]*_)]*($|[[:space:]])' <<<"$REPLY"; then
  refuse "Your reply asks the owner a question in text. Ask the owner only with the picker (AskUserQuestion), with the options you propose; keep the rest of the reply."
fi
if [ -n "$W" ] && jq -e --arg w "$W" '(.opening | contains($w)) and (.owner | not)' <<<"$TURN" >/dev/null 2>&1 && [ "$(wc -w <<<"$REST")" -gt 1 ]; then
  # What needs the owner is said to them: a reply that never says you, your or owner reports, and so does a sentence
  # that gives a card's progress without them.
  HIT=$(grep -oiE 'still (running|working|in progress)|not done yet|\b[0-9]+ ?(of|/) ?[0-9]+\b[^.]*\b(done|passed|landed|tests?)\b|nothing (needs|for) you|no action (needed|required)' <<<"$REST" | head -3 | paste -sd'|' -)
  [ -n "$HIT" ] || grep -qiwE "you|your|owner('?s)?" <<<"$REST" || HIT="a report"
  [ -n "$HIT" ] || HIT=$(tr '\n' ' ' <<<"$REST" | grep -oE '[^.!?]+' | grep -viwE "you|your|owner('?s)?" \
    | grep -iwE 'landed|merged|pushed|passed|succeeded|finished|completed|released|deployed|done|running|in progress' | sed 's/^ *//' | head -3 | paste -sd'|' -)
  [ -z "$HIT" ] || refuse "A reply to a wake says only what needs the owner to act or decide ($HIT is not that). Rewrite it without that, or reply with the one word Idle if nothing needs them. A suspected defect in Conveyor itself needs the owner: keep it, as its own line in the form $(plugin_home && echo "${FORM%\'}, filed as #<n>' (this is the plugin's own repository: file it here first)" || echo "$FORM")."
fi
HIT=$({ grep -oiE "(haven'?t|have not|did not|didn'?t|not yet) (filed|file it|sent|fixed|checked)|not filed yet|want me to|shall i|should i |if you'?d like|i can (also )?(file|fix|send|check|do|open|run)|let me know if|\b(i|we) (still|yet) (need|have|got) to|\bi (need|have) to (file|fix|send|check|retry|open|run|hold|release)|\b(next|later),? i('ll| will)" <<<"$REST"
  # An "I'll <verb>" is undone work only in a sentence that ties it to no later event or standing rule ("When the
  # queue empties, I'll release", "Until #361 lands, I'll check ... on every wake" leave nothing undone now). Each line
  # (a list item) and each sentence in it is judged alone, so a later event in one never hides a deferral in another.
  sed -E 's/([.!?])[[:space:]]+/\1\
/g' <<<"$REST" \
    | grep -viE '\b(when|whenever|once|after|until|as soon as|each|every|at the next|if)\b' \
    | grep -oiE "\bi('ll| will) (file|fix|send|check|retry|open|run|hold|release)"; } | head -3 | paste -sd'|' -)
[ -z "$HIT" ] || refuse "Unfinished work in your reply ($HIT). If it is yours to do (file, check, retry, fix), do it now and say it is done. Keep the line only when it truly needs the owner, and say why in the same sentence."
exit 0
