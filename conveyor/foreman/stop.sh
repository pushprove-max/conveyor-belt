#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# stop.sh state | reply -- the Foreman's Stop hooks (the Foreman session only; every other session passes).
# state: while the open lines of the saved state ($FD/state.md: all but the '- DONE' items, with their indented lines,
#   which the next start archives, archive.py) are over the cap (CAP in foreman.sh), the stop is blocked once with their size; the
#   second stop (stop_hook_active) passes, so it never loops. A warning at startup alone was ignored. First, each stop
#   sends the owner's profile items to the build hosts when they changed since last sent (`conveyor.sh auto send`); when
#   that fails (a host not reached), the stop is blocked once with its error, so the owner is told.
# reply: the turn's last reply (every text block after its last tool call or user entry, such as a refused stop's
#   feedback) is refused once per turn (the turn is its opening entry: the newest user entry that is
#   not a tool result, nor meta unless it holds the wake; a refused turn is marked in reply-mark, so its next stop passes) when it
#   - answers a wake (the turn's opening entry holds the first line of last-wake.txt, waiter.sh) with more than what
#     needs the owner: a still-running line, a progress count, a "nothing needs you", a reply that never says you,
#     your or owner, or a sentence reporting a card (landed, merged, done ...) without them; a reply to a wake says only
#     what needs the owner (and a "Done without asking (<kind>): ...; logged as <id>" line, the standing-yes receipt), otherwise one word (Idle); a turn in which the owner typed a message (a queued_command
#     entry of human origin after the opening) answers the owner, so its reply is not judged as a wake reply;
#   - leaves the Foreman's own work undone ("haven't filed it", "I still need to file", "I'll fix", "want me to ..."); an "I'll <verb>" in a
#     sentence that ties it to a later event or a standing rule (when, once, after, until, every, if ...) is not that.
#   A line in the plugin-problem form (PLUG: "Plugin problem (for the conveyor-belt repo): <the command or step>, <what it did>, <what was expected>") reports a
#   suspected defect in Conveyor itself, which the owner fixes (the owner files it too, except in the plugin's own
#   repository, where the Foreman files it): it needs the owner, so the wake and
#   unfinished-work checks read the reply without it, and each such line is noted once in $FD/plugin-bugs.md (time,
#   card, what was seen, evidence path) before any check, so the finding outlives a refused or short reply. In the
#   plugin's own repository (lib.sh plugin_home) the Foreman files it there itself, so a line that does not end
#   "filed as #<n>" is refused too, at every stop of the turn (not only once, as the checks above are).
#   A plugin-problem line may carry a part "cause not checked: <text>" before its card and evidence: a guess at the cause.
#   No line is refused for [likely]: a clause that holds it outside that part is noted moved into the part (plug_cause),
#   with the clauses before it that it goes on (one with no subject, "is stale", or a hedge word, "maybe", takes the
#   clause before it),
#   so the marker is never lost and the report shows the text as a cause that was not checked.
#   A turn that opens with a wake naming a card of this Foreman's projects "not yet reported: blocked" (watch-conveyor.sh
#   unreported) is refused at every stop until, for each such card, an act naming it was logged since it blocked (`auto act`, read back from the ruling
#   log), the turn asked the owner about it (AskUserQuestion), or its record no longer holds it blocked (retried, shut,
#   landed): a reply ("Idle", or a plan to act later) alone is not that.
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
    # An item the turn added to the owner's profile goes to the build hosts now (commands/auto.sh send), not at the next
    # `auto decide`: the engine there decides while this session is closed. A host it did not reach decides by the items
    # it last got, so the stop is refused once with why, for the owner; each later stop sends them again. Only exit 1 is
    # that failure (a host not reached, the profile not read): another code (no conveyor.sh beside it) is not.
    sent=$(bash "$(dirname "${BASH_SOURCE[0]}")/../conveyor.sh" auto send 2>&1 < /dev/null > /dev/null); rc=$?
    [ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" != true ] || exit 0
    [ "$rc" != 1 ] || block "The owner's profile items (owner-way.md) did not reach a build host, so the engine there can still decide what a new item holds, until a later stop sends them: ${sent//$'\n'/ } Tell the owner."
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
  | if $i == null then empty else
    # ok: the tool calls of the turn whose result is no error: a picker a hook denied (auto on in full, hooks/auto.tsx)
    # never reached the owner.
    [.[$i + 1:][] | select(.type == "user") | .message.content | arrays | .[] | objects | select(.type == "tool_result" and .is_error != true) | .tool_use_id] as $ok
    | {uuid: (.[$i].uuid // ""), opening: (.[$i] | txt), meta: (.[$i].isMeta // false),
      owner: any(.[$i + 1:][]; .type == "attachment" and .attachment.type? == "queued_command" and .attachment.origin.kind? == "human"),
      # asks: each question of each AskUserQuestion of the turn that the owner was asked (its result is no error), as
      # JSON (its text and options), one apiece, so a card and a project are matched within one question.
      asks: [.[$i + 1:][] | select(.type == "assistant") | .message.content[]? | objects
        | select(.type == "tool_use" and .name == "AskUserQuestion" and (.id | IN($ok[])))
        | .input | if (.questions? | type) == "array" then .questions[] | tojson else tojson end],
      # reply: the text after the last tool call or user entry (a refused stop adds its feedback as a user
      # entry), so a refused reply is never checked or noted again at the next stop.
      reply: ([.[$i + 1:][] | if .type == "user" then {cut: true} elif .type == "assistant" then (.message.content[]? | if .type == "tool_use" then {cut: true} else . end) else empty end] as $c
        | ($c | map(.cut == true) | rindex(true)) as $k | [$c[(if $k == null then 0 else $k + 1 end):][] | select(.type == "text") | .text] | join("\n"))} end' "$T" 2>/dev/null)
U=$(jq -r '.uuid // empty' <<<"$TURN" 2>/dev/null); REPLY=$(jq -r '.reply // empty' <<<"$TURN" 2>/dev/null)
[ -n "$U" ] && [ -n "$REPLY" ] || exit 0
PLUG='^[[:space:]*_>-]*plugin problem \(for the conveyor-belt repo\):[[:space:]*_]*'
FORM="'Plugin problem (for the conveyor-belt repo): <the command or step>, <what it did>, <what you expected>[, cause not checked: <what you think the cause is>], card <card>, evidence <path>'"
# Each plugin-problem line is noted once: a reply that says it again (after a refusal) adds no second note. A line
# that ends "filed as #<n>" names the issue it was filed as; in the plugin's own repository, said after the same line
# without it (or as the line context gives a listed note), it takes that note's place, so the note names the issue
# (context lists those with none).
# An issue number is 1 or more: "filed as #0" names no issue, so that line is refused and noted without it, as unfiled.
NOTES=$FD/plugin-bugs.md
FILED='[,;]?[[:space:]]*filed as #([1-9][0-9]*)[[:space:]]*\.?$'
NOISSUE='[,;]?[[:space:]]*filed as #[0-9]+[[:space:]]*\.?$'
UNFILED=()
# plug_cause <text>: sets BODY, the text with each clause that holds [likely] moved into its "cause not checked: <text>"
# part (put before the card, evidence and filed clauses), and BASE, the text without that part (where the card and the
# evidence path are read). A text with neither [likely] nor that part is both, as it is. Clauses end at ", " or "; ".
plug_cause() {
  BODY=$1 BASE=$1
  [[ ${1,,} == *'[likely]'* || ${1,,} == *'cause not checked:'* ]] || return 0
  # A card, evidence or filed clause is only one that has the field's own shape (a card id or "-", one path with a "/"
  # or "-"), so a cause that says ", card lookups use old data" stays in the cause, and an empty field ends it.
  local TAILRE='^(card[[:space:]]+(c[0-9]{8}T[0-9]{6}-[^[:space:]]+|-)|evidence[[:space:]]+([^[:space:]]*/[^[:space:]]*|-)|filed as #.*)$'
  local s=${1//; /, } c p before after first cause='' moved=0 incause=0 intail=0 tailtag=0
  local -a cl=() head=() tail=()
  while [[ $s == *', '* ]]; do cl+=("${s%%, *}"); s=${s#*, }; done; cl+=("$s")
  for c in "${cl[@]}"; do
    p=${c,,}; p=${p%%\[likely\]*}; before=$(plug_join "${c:0:${#p}}")
    if [[ ${c,,} == 'cause not checked:'* ]]; then incause=1; cause=$(plug_join "$cause" "${c#*:}"); continue; fi
    if ((incause)) && ! [[ $before =~ $TAILRE ]]; then cause=$(plug_join "$cause" "$(plug_untag "$c")"); continue; fi
    incause=0
    if [[ ${c,,} == *'[likely]'* ]]; then
      moved=1; after=$(plug_untag "${c:${#p}+8}")
      if [[ $before =~ $TAILRE ]]; then   # a card, evidence or filed clause keeps its text before the tag
        c=$before
        # A tag that ends a field has no claim of its own to mark: it marks the line's text before the fields.
        if [ -n "$after" ]; then cause=$(plug_join "$cause" "$after"); else tailtag=1; fi
      else
        # A tagged clause with no subject of its own ("is stale") or a hedge word ("maybe") goes on the clause before
        # it, so that clause is part of the same guess and goes into the cause too ("the cache, maybe, is stale"). A
        # one-word guess that is no hedge ("timeout") has its own subject: the clause before it stays outside the cause.
        c=$(plug_untag "$c"); first=$c
        while ((${#head[@]} && !intail)) && [[ ${first,,} =~ ^((is|are|was|were|has|have|had|seems?|may|might|can|could|will|would|does|do|did)([[:space:]]|$)|(maybe|perhaps|probably|possibly|likely|apparently)$) ]]; do
          first=${head[-1]}; c=$(plug_join "$first" "$c"); unset 'head[-1]'
        done
        cause=$(plug_join "$cause" "$c"); continue
      fi
    fi
    [[ $c =~ $TAILRE ]] && intail=1
    if ((intail)); then tail+=("$c"); else head+=("$c"); fi
  done
  BASE=$(plug_join "${head[@]}" "${tail[@]}")
  ((moved)) || return 0
  if ((tailtag)); then cause=$(plug_join "${head[@]}" "$cause"); head=(); fi
  BODY=$(plug_join "${head[@]}" "cause not checked: ${cause:-not stated}" "${tail[@]}")
}
# plug_join <part>...: the non-empty parts, each trimmed, joined with ", ".
plug_join() { local o='' x; for x; do x=${x#"${x%%[![:space:]]*}"}; x=${x%"${x##*[![:space:]]}"}; [ -z "$x" ] || o=${o:+$o, }$x; done; printf '%s' "$o"; }
# plug_untag <text>: the text without any [likely] tag, trimmed.
plug_untag() { local s=$1 p; while [[ ${s,,} == *'[likely]'* ]]; do p=${s,,}; p=${p%%\[likely\]*}; s=${s:0:${#p}}${s:${#p}+8}; done; plug_join "$s"; }
# The notes file is read and rewritten by the Board's Dismiss and appended to by serve's price notes, all under
# noprice.lock beside it (noprice(), lib/control.sh): the loop holds that lock, so a note it writes is not lost under
# the Board's older copy. Only a reply with a plugin-problem line takes it (plug_lock, at its first such line). A lock
# that cannot be taken in 30 s is dropped and the loop runs without it: the hook never blocks.
plug_lock() {
  [ -z "${NLTRIED:-}" ] || return 0
  NLTRIED=1
  mkdir -p "$FD" 2>/dev/null && exec {NL}>>"$FD/noprice.lock" 2>/dev/null && { flock -w 30 "$NL" || { exec {NL}>&-; unset NL; }; } 2>/dev/null
  return 0
}
shopt -s nocasematch
while IFS= read -r l; do
  [[ $l =~ $PLUG ]] || continue
  seen=${l:${#BASH_REMATCH[0]}}; seen=${seen%"${seen##*[![:space:]]}"}; [ -n "$seen" ] || continue
  plug_lock
  # The "filed as #<n>" end is set aside, so a cause part never swallows it. A number that names no issue is left out
  # of the note, so the line with a valid number later takes its place.
  sfx=; [[ $seen =~ $NOISSUE ]] && { sfx=${BASH_REMATCH[0]}; seen=${seen:0:${#seen}-${#sfx}}; }
  plug_cause "$seen"; seen=$BODY
  if [[ $sfx =~ $FILED ]]; then seen=$seen$sfx; what=$BODY
  else
    [ -n "$seen" ] || continue
    what=$seen; UNFILED+=("$what")
  fi
  ! grep -qF -- " · $seen · evidence: " "$NOTES" 2>/dev/null || continue
  # The card of the "card <card>" field, a part of its own between commas (the last such part: the fields end the
  # line), none when that field is "card -"; with no such field, the first card id that is no file's name (after a /
  # or ending in an extension): the text before the fields may name another card ("compare card <card>") or a card's
  # evidence file, ~/cards/<card>.err.
  card='' field=''; IFS=, read -ra parts <<<"$BASE"
  for x in "${parts[@]}"; do [[ $x =~ ^[[:space:]]*card[[:space:]]+(-|c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]*[A-Za-z0-9])[[:space:]]*$ ]] && field=1 card=${BASH_REMATCH[1]#-}; done
  [ -n "$field" ] || card=$(grep -oE '(^|[^/])\bc[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]*[A-Za-z0-9]' <<<"$BASE" | grep -oE 'c[0-9]{8}T[0-9]{6}-.*' | grep -vE '\.[A-Za-z]+$' | head -n 1)
  ev=$(grep -oE "(~|\.{1,2})?/[^[:space:],;()'\"\`]+|[A-Za-z0-9._-]+/[^[:space:],;()'\"\`]+" <<<"$BASE" | head -n 1); ev=${ev%.}
  # In the plugin's own repository (plugin_home) a filed line takes the place of the first note that names no issue
  # and says the same thing: its own text (the line the start-up list gives for it), or that text with its own card
  # and evidence fields after it. Never a note that only shares a card or path: that may be a different problem. In
  # any other project the owner files it, and a filed line is noted as its own row, as before.
  if [ "$what" != "$seen" ] && [ -s "$NOTES" ] && plugin_home \
    && W="$what" S="$seen" LC_ALL=C awk '
      BEGIN { D = " · "; C = " · card "; E = " · evidence: " }
      !done && /^- / && tolower($0) !~ /[ ,;]filed as #[1-9][0-9]*[[:space:]]*\.? · evidence: / && (i = index($0, C)) {
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
[ -z "${NL:-}" ] || exec {NL}>&-
# The wake and unfinished-work checks below read the reply without its plugin-problem lines.
# A "Done without asking" line (the standing-yes rule's one line to the owner) is read out of it too: it is how the
# owner hears of an act taken for them, so a wake reply may carry it. It must have the whole form, kind and id.
DONE='^[[:space:]*_>-]*done without asking \([^)]+\):.*; logged as [^[:space:]]+[[:space:]*_]*$'
REST=$(grep -viE "$PLUG" <<<"$REPLY" | grep -viE "$DONE")
# In the plugin's own repository (plugin_home) a plugin problem is the Foreman's to file there: a line naming no
# issue is refused at every stop, not once per turn (reply-mark is not read or set here), so a reply never ends with it
# unfiled; filing it, or leaving the line out (its note stays listed at start-up), lets the stop pass. In any other
# project the owner files it, and the line passes as it is.
if [ ${#UNFILED[@]} != 0 ] && plugin_home; then
  block "This project is the plugin's own repository, so a plugin problem is a defect you file here yourself, as any issue you file (it starts held until the owner says yes). File it now, then name the issue at the end of the line: 'Plugin problem (for the conveyor-belt repo): <the command or step>, <what it did>, <what you expected>[, cause not checked: <what you think the cause is>], card <card>, evidence <path>, filed as #<n>'. Not filed: ${UNFILED[0]}"
fi
# A card the wake names "<repo>: not yet reported: blocked <ref>" (watch-conveyor.sh unreported), or names in its own
# first wake as "<repo>: <ref> is blocked since <time>: <why>" (watch-conveyor.sh record, read here as the same
# "not yet reported" line: the ref before the first " is blocked since "), needs, since it
# blocked, a change of its state (health no longer holds it blocked as the line says: lib.sh blocked_now and FRESH),
# an act logged under a standing kind (a row of a ruling log written at or after the block time health gives, and not
# marked void) or an AskUserQuestion of this turn whose one question names it and whose result is no error (one a hook
# denied never reached the owner). The lines are read from last-wake.txt (the text the waiter relayed) only in a turn
# that the wake opens: a meta entry (the waiter's hook feedback, which no owner types) that holds W, and only for a
# project this Foreman watches (mine): wake text the owner pastes or quotes in a prompt is no wake, and another
# Foreman's project is not this one's. A card whose record's health does not read
# (the build host not reached) is still held, as it may still be blocked: its block time is then read from the
# snapshot the watcher kept of that record ($FD/conveyor-snapshot-<repo>.json, watch-conveyor.sh keepsnap) for the
# card id its line names ("(card <id>)", watch-conveyor.sh unreported), and only when that snapshot does not list that
# card (one kept before the card was retried lists the card before it) does its act count from the wake's time
# (last-wake.txt's), as the card blocked before its wake was put.
# The ruling logs read are this Foreman's own ($FD/rulings.jsonl, .claude/hooks/lib/rulings.sh rulings_log) and the
# one of the record's host (lib.sh hostacts, read as it is, so an act logged there by an engine of any pin counts).
# Only a ruling log counts as an act, not a receipt line, which any command can print. A text names the card only by
# its id (the line's, or else health's), or, for a card the line names by its issue ("#<n>"), by its project with that
# issue written together ("<project> #<n>", "<project> issue #<n>", not after a "/"), or by the GitHub repository of
# the record's main checkout where its belt runs (lib.sh host_slug on the host file's ssh target, else repo_slug here;
# never a checkout of this machine's that only shares the project's name, which can be the owner's fork), owner and
# name, with the issue: "<owner>/<name>#<n>" or the issue's link, ".../<owner>/<name>/issues/<n>". Not by a card's name: the follow-ups of
# one issue share one, and so can cards of two projects. Not by "#<n>" alone, nor by a project and an issue named
# apart, nor by a fork's link: two projects can each have an issue #7, and the Foreman's records share one ruling log
# on a machine. A plan in prose is none of these. Refused at every stop, as an unfiled plugin problem is: retrying or
# shutting the card is always open (asking the owner too, unless auto is on in full), so the turn can always end.
LEFT=''
if [ -n "$W" ] && jq -e --arg w "$W" '.meta == true and (.opening | contains($w))' <<<"$TURN" > /dev/null 2>&1; then
  LEFT=$(awk '/^[A-Za-z0-9._-]+: not yet reported: blocked .+$/ { l = $0 }
      match($0, /^[A-Za-z0-9._-]+: /) && (i = index($0, " is blocked since ")) > RLENGTH + 1 && substr($0, i + 18) ~ /^[0-9T:-]+Z: / {
        l = substr($0, 1, RLENGTH) "not yet reported: blocked " substr($0, RLENGTH + 1, i - RLENGTH - 1) }
      l != "" && !s[l]++ { print l } { l = "" }' "$FD/last-wake.txt" 2>/dev/null \
    | awk -F': ' 'NR == FNR { w[$1]; next } $1 in w' <(mine 2>/dev/null | cut -f1) -)
fi
if [ -n "$LEFT" ]; then
  now=$(cut -d: -f1 <<<"$LEFT" | sort -u | blocked_now)
  t=$(printf 'x\n%s\n' "$LEFT" | jq -Rrs --argjson now "$now" "$FRESH" 2>/dev/null) && LEFT=$(tail -n +2 <<<"$t")
  ASKS=$(jq -c '.asks // []' <<<"$TURN" 2>/dev/null) || ASKS='[]'
  # The blocked cards of the watcher's kept snapshot of each record whose health did not read, as blocked_now gives
  # them: {<repo>: [{ref, card, since}]}. A record with no snapshot kept gives nothing, and the loop goes on: its
  # failed read is not the loop's status, which pipefail would make the pipeline's and so drop every record's.
  KEPT=$(cut -d: -f1 <<<"$LEFT" | sort -u | while IFS= read -r r; do
    jq -e --arg r "$r" 'has($r)' <<<"$now" > /dev/null 2>&1 \
      || jq -c --arg r "$r" '{($r): [.health.blocked | arrays | .[] | objects | {ref: ((.name | strings) // "#\(.issue)"), card, since}]}' "$FD/conveyor-snapshot-$r.json" 2>/dev/null \
      || :
  done | jq -cs 'add // {}' 2>/dev/null) || KEPT='{}'
  # NAMES: true when a text of its input (a JSON list) names the card id $c, or the issue $n with the project $r, or
  # with the repository $g ("owner/name", lower case), written together; a word is matched whole, as #7 is not #70, c7
  # is not c70 and alpha is not alpha-2, and a project's name not after a "/", as fork/alpha is another repository.
  NAMES='def esc: gsub("(?<c>[.*+?()\\[\\]{}|^$\\\\])"; "\\\(.c)");
    def word($w): test("(?<![A-Za-z0-9._-])" + $w + "(?![A-Za-z0-9_-]|\\.[A-Za-z0-9_-])");
    any(.[] | strings; ($c != "" and word($c | esc))
      or ($n != "" and (word("(?<!/)" + ($r | esc) + "(?:'\''s)?(?:\\s+issue)?\\s*#" + $n)
        or ($g != "" and test("(?:^|[^A-Za-z0-9._/-]|://[A-Za-z0-9.-]+/)" + ($g | esc) + "(?:#|/issues/)" + $n + "(?![0-9])"; "i")))))'
  # This Foreman's own ruling log, read once: rows of an act not marked void, {utc, answer}.
  MINE=$(jq -cRs '[split("\n")[] | fromjson? | objects | select(.source == "standing" and .void != true) | {utc, answer}]' "$FD/rulings.jsonl" 2>/dev/null) || MINE='[]'
  declare -A ACTS=() SLUG=()
  # The wake's time, as a ruling row's utc: the time an act counts from when health gives no block time.
  WT=$(p_mtimes "$FD/last-wake.txt" | jq -Rr 'split(" ")[0] | tonumber | todate' 2>/dev/null) || WT=''
  KEEP=''
  while IFS= read -r l; do
    [[ $l =~ ^([A-Za-z0-9._-]+):\ not\ yet\ reported:\ blocked\ (.+)$ ]] || continue
    r=${BASH_REMATCH[1]} ref=${BASH_REMATCH[2]} c='' n='' since='' hc=''
    [[ $ref =~ ^(.+)\ \(card\ ([A-Za-z0-9._-]+)\)$ ]] && ref=${BASH_REMATCH[1]} c=${BASH_REMATCH[2]}
    # Only a line that names the card by its issue gives one: a named card's issue (a follow-up's) is its parent's.
    [[ $ref =~ ^#([0-9]+)$ ]] && n=${BASH_REMATCH[1]}
    # The repository of the record where its belt runs, read once: empty when it does not read, and then only the
    # project's name counts.
    if [ -n "$n" ] && [ -z "${SLUG[$r]+x}" ]; then
      SLUG[$r]=''; m=$(recmain "$r") && SLUG[$r]=$(if [ -n "$(host_ssh)" ]; then host_slug "$m"; else repo_slug "$m"; fi)
    fi
    # The block time and the id health gives for the card, or else the kept snapshot's for the card of the line's id
    # alone: a snapshot kept before the card was retried names the card before it (each retry is a new card), whose
    # block time is older and whose act is no step on this one. The fields are split on a unit separator, as a tab is
    # white space to read.
    IFS=$'\x1f' read -r since hc < <(jq -r --arg r "$r" --arg ref "$ref" --arg c "$c" --argjson k "$KEPT" 'first((.[$r] // (if $c == "" then null else $k[$r] end))[]?
      | select(.ref == $ref and ($c == "" or .card == $c)))
      | [(.since | strings) // "", (.card | strings) // ""] | join("\u001f")' <<<"$now" 2>/dev/null)
    since=${since:-$WT}
    # A line that names no card id takes health's.
    c=${c:-${hc:-}}
    a=(--arg c "$c" --arg r "$r" --arg n "$n" --arg g "${SLUG[$r]:-}")
    jq -e "${a[@]}" "$NAMES" <<<"$ASKS" > /dev/null 2>&1 && continue
    if [ -n "${since:-}" ]; then
      [ -n "${ACTS[$r]+x}" ] || { m=$(recmain "$r") && ACTS[$r]=$(hostacts "$m" 2>/dev/null | jq -cs .); } || ACTS[$r]='[]'
      jq -e "${a[@]}" --arg s "$since" -s "[add[] | select((.utc | strings) >= \$s) | .answer] | $NAMES" <<<"$MINE${ACTS[$r]}" > /dev/null 2>&1 && continue
    fi
    KEEP+=$l$'\n'
  done <<<"$LEFT"
  KEEP=${KEEP%$'\n'}
  [ -z "$KEEP" ] || block "A blocked card is not yet reported: ${KEEP//$'\n'/; }. Before the turn ends, take a step on each one: retry or shut it, or take a standing kind and log it with \`auto act <kind> \"<what you did>\"\`, or ask the owner with AskUserQuestion. Name the card in the act or the question by its card id, or, for a card named here by its issue, by its project with its issue written together, as \`<project> #<n>\`. A plan to do it later is not a step."
fi
MARK=$FD/reply-mark
[ "$(cat "$MARK" 2>/dev/null)" != "$U" ] || exit 0
refuse() { { mkdir -p "$FD" && printf '%s\n' "$U" > "$MARK"; } 2>/dev/null || exit 0; block "$1"; }

if [ -n "$W" ] && jq -e --arg w "$W" '(.opening | contains($w)) and (.owner | not)' <<<"$TURN" >/dev/null 2>&1 && [ "$(wc -w <<<"$REST")" -gt 1 ]; then
  # What needs the owner is said to them: a reply that never says you, your or owner reports, and so does a sentence
  # that gives a card's progress without them.
  HIT=$(grep -oiE 'still (running|working|in progress)|not done yet|\b[0-9]+ ?(of|/) ?[0-9]+\b[^.]*\b(done|passed|landed|tests?)\b|nothing (needs|for) you|no action (needed|required)' <<<"$REST" | head -3 | paste -sd'|' -)
  [ -n "$HIT" ] || grep -qiwE "you|your|owner('?s)?" <<<"$REST" || HIT="a report"
  [ -n "$HIT" ] || HIT=$(tr '\n' ' ' <<<"$REST" | grep -oE '[^.!?]+' | grep -viwE "you|your|owner('?s)?" \
    | grep -iwE 'landed|merged|pushed|passed|succeeded|finished|completed|released|deployed|done|running|in progress' | sed 's/^ *//' | head -3 | paste -sd'|' -)
  [ -z "$HIT" ] || refuse "A reply to a wake says only what needs the owner to act or decide ($HIT is not that). Rewrite it without that, or reply with the one word Idle if nothing needs them and no act is left to tell them of (that line, \"Done without asking (<kind>): <what>; logged as <id>.\", is kept). A suspected defect in Conveyor itself needs the owner: keep it, as its own line in the form $(plugin_home && echo "${FORM%\'}, filed as #<n>' (this is the plugin's own repository: file it here first)" || echo "$FORM")."
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
