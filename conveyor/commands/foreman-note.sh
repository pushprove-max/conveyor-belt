# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh foreman note <session> <card> --does | --ask <text>` and `conveyor.sh foreman note <session> renew`: the
# Foreman's notes on this record's blocked cards (issue 1685), kept in NOTES in the record's state folder, on the
# machine that prints its snapshot (snapprint, commands/snapshot.sh, which names the file and NOTELEASE too), so
# /units and the Board show them wherever the Foreman runs. The Foreman runs both by its ask (foreman/lib.sh), from its
# own machine: `foreman.sh note` (foreman/note.sh) writes one, and its Conveyor watcher (watch-conveyor.sh renewnotes)
# renews them at each poll while the Claude process it runs for holds the session that has the role.
# NOTES: line 1 "<session> <renewed: epoch seconds>", line 2 one JSON object {<card>: {note, ask, since}}. snapprint
# shows them only while renewed is at most NOTELEASE seconds old: once the session is gone, nothing renews them, and a
# renewal or a note after that (the same session resumed) does not bring them back: they are dropped.
# A note is written only for a card the records hold blocked (its last closing line), under the records' lock that a
# retry, a landing and a shut take to write their lines: a card landed or shut before the note is refused (exit 3), and
# so is one blocked for the owner's yes (its reason starts with YES or LINTYES, yesforms(), lib/records.sh), which the
# views list as waiting, not blocked, so no view would show its note; one the records have no line of is refused
# too (exit 4: a card retried, as retry takes its lines out, or a card of another project with the same tag,
# foreman/note.sh), and one retried after it leaves the blocked cards, where snapprint no longer shows its note. Each write keeps only the notes
# of cards the records still hold blocked, so the file does not grow with the cards the Foreman had. A note of another
# session than the one kept, or a renew by another session, ends the kept notes: the role moved. Sourced by
# commands/foreman.sh.
NOTES=$ST/foreman-notes NOTELEASE=300 # NOTELEASE: the same as snapprint's (commands/snapshot.sh)
sid=${1:-} card=${2:-} kind=${3:-}
{ [[ $sid =~ ^[A-Za-z0-9-]+$ ]] && { { [ "$card" = renew ] && [ $# = 2 ]; } \
    || { [[ $card =~ ^c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]+$ ]] && { [ "$kind" = --does ] || [ "$kind" = --ask ]; } && [ -n "${4:-}" ] && [ $# = 4 ]; }; }; } \
  || { echo "usage: conveyor.sh foreman note <session> <card> --does | --ask <text> | conveyor.sh foreman note <session> renew" >&2; exit 2; }
text=${4:-}
# The forms of a block for the owner's yes, from the pack's owner (as recordsnow() reads it); none when it names none.
YES='' LINTYES='' o=$(jq -er '.owner.name | strings' "$MAIN/.conveyor/project.json" 2>/dev/null) && yesforms "$o"
noteput() {
  local s='' t='' kept='' live='' on
  { { read -r s t; IFS= read -r kept; } < "$NOTES"; } 2>/dev/null
  [ -n "$s" ] && [ "$s" = "$sid" ] && [[ $t =~ ^[0-9]+$ ]] && [ $((EPOCHSECONDS - t)) -le "$NOTELEASE" ] && live=1
  if [ "$card" = renew ]; then
    [ -n "$s" ] || return 0
    [ -n "$live" ] || { rm -f "$NOTES"; return 0; }
  else
    [ -n "$live" ] || kept=''
    # The kept cards and this one, each with its last closing line: the notes are passed by file, not as an argument,
    # which a long line would make too long to run.
    on=$(jq -rR --arg c "$card" '[(try fromjson catch null | objects | keys[]), $c] | unique[] | "\"\(.)\""' <<<"$kept") || return 1
    # "none": the records have no line of the card (exit 4): the Foreman asks the next of its projects with the same tag.
    kept=$(grep -F -f <(printf '%s\n' "$on") "$STATE" 2>/dev/null | jq -sc --rawfile k <(printf '%s' "$kept") --arg c "$card" \
      --argjson a "$([ "$kind" = --ask ] && echo true || echo false)" --arg n "$text" --arg t "$(export TZ=UTC; printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1)" \
      --arg yes "$YES" --arg lintyes "$LINTYES" '
      (reduce (.[] | objects | select((.card | type) == "string" and (.step | IN("landed", "closed", "blocked", "pushed")))) as $l
        ({}; .[$l.card] = $l.step)) as $on
      | (([.[] | objects | select(.card == $c and .step == "blocked")] | last | .reason | strings) // "") as $why
      | if any(.[]; objects | .card == $c) | not then "none" elif $on[$c] != "blocked" then "open"
        elif $yes != "" and ($why | startswith($yes) or startswith($lintyes)) then "yes"
        else (($k | try fromjson catch null | objects) // {}) | with_entries(select($on[.key] == "blocked")) | .[$c] = {note: $n, ask: $a, since: $t} end')
    case $kept in
      '{'*) ;;
      '"none"') echo "conveyor: this record has no card $card (retried, or a card of another project): no note is kept" >&2; return 4 ;;
      '"open"') echo "conveyor: $card is not blocked now (landed, shut or not ended): no note is kept" >&2; return 3 ;;
      '"yes"') echo "conveyor: $card waits for the owner's yes, which Needs you shows: no note is kept" >&2; return 3 ;;
      *) echo "conveyor: the records could not be read: no note is kept" >&2; return 1 ;;
    esac
  fi
  printf '%s %s\n%s\n' "$sid" "$EPOCHSECONDS" "$kept" > "$NOTES.$$" && mv -f "$NOTES.$$" "$NOTES" || { rm -f "$NOTES.$$"; return 1; }
}
locked noteput
