#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# note.sh <card> [--ask] <what you do about it> -- `foreman.sh note`: the Foreman's note on a blocked card it takes
# (issue 1685): what it does about the card, one line, and since when (now). /units and the Board show the card as the
# Foreman's, with the note and its age, apart from the cards that wait for the owner. --ask: the card waits for the
# owner's answer to a picker; it stays with the cards that need the owner, and says so.
# The note is kept where the card's record is, by ask (lib.sh: over ssh when the host file names a target), as
# `conveyor.sh foreman note` (commands/foreman-note.sh), which says what shows it and what ends it: the snapshot of that
# record carries it. The record is the one of the Foreman's (lib.sh mine) whose tag the card ID names
# (c<time>-<tag>-<issue>, the tag the repo with each character but a letter or digit made "-": CTAG, lib/paths.sh) and
# that has the card. Only the Foreman's own session writes one: the Claude process it runs under (lib.sh cc_pid) must
# hold the marked session. The text is made one line, at most MAX characters.
# NOTED, in the Foreman's folder: line 1 the session that wrote notes, then each repo it wrote one in, which the
# Conveyor watcher renews (watch-conveyor.sh renewnotes) while that session holds the role. The check of the role and
# the write are one step under claim.lock (lib.sh locked), which a claim and an off take too: a note is never kept
# for a session that lost the role while it was written.
set -u
MAX=300
card=${1:-} kind=--does
[ "${2:-}" != --ask ] || { kind=--ask; set -- "$1" "${@:3}"; }
text=$(printf '%s' "${*:2}" | tr -s '[:space:]' ' ' | tr -d '[:cntrl:]') text=${text# } text=${text% } text=${text:0:$MAX}
[[ $card =~ ^c[0-9]{8}T[0-9]{6}-[A-Za-z0-9-]+-[0-9]+$ ]] && [ -n "$text" ] \
  || { echo "usage: foreman.sh note <card> [--ask] <what you do about it>" >&2; exit 2; }
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
NOTED=$FD/noted
pid=$(cc_pid) && sid=$(jq -r '.sessionId // empty | strings' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/$pid.json" 2>/dev/null) \
  && [ -n "$sid" ] && [ "$sid" = "$(marked)" ] || { echo "foreman.sh note: run it in the $NAME's own session: only that session writes a note" >&2; exit 1; }
tag=${card:17} tag=${tag%-*}
mapfile -t recs < <(mine 2>/dev/null | awk -F'\t' -v t="$tag" '{ c = $1; gsub(/[^A-Za-z0-9]/, "-", c) } c == t { print $1 "\t" $2 }')
[ "${#recs[@]}" -gt 0 ] || { echo "foreman.sh note: $card is a card of none of the $NAME's projects" >&2; exit 1; }
# put (under claim.lock): the role checked again, the note kept on the record's host, then its repo in NOTED. Two
# projects can have one tag (so-lo-1 and so_lo.1): each is asked in turn until one has the card (exit 4: it has none).
put() {
  local s='' out='' rc=4 r repo main
  [ "$(marked)" = "$sid" ] || { echo "foreman.sh note: this session no longer holds the $NAME role" >&2; return 1; }
  for r in "${recs[@]}"; do
    IFS=$'\t' read -r repo main <<<"$r"
    out=$(ASK_LIMIT=20 ask "$repo" "$main" foreman note "$sid" "$card" "$kind" "$text" 2>&1); rc=$?
    [ "$rc" = 4 ] || break
  done
  [ "$rc" = 0 ] || { echo "foreman.sh note: no note is kept: ${out:-the host of the record did not answer}" >&2; return 1; }
  { IFS= read -r s < "$NOTED"; } 2>/dev/null
  if [ "$s" != "$sid" ]; then printf '%s\n%s\n' "$sid" "$repo" > "$NOTED.$$"
  else { cat "$NOTED" && grep -qxF -- "$repo" "$NOTED" || printf '%s\n' "$repo"; } > "$NOTED.$$"; fi
  mv -f "$NOTED.$$" "$NOTED" || { rm -f "$NOTED.$$"; echo "foreman.sh note: $NOTED cannot be written" >&2; return 1; }
}
locked put || exit 1
if [ "$kind" = --ask ]; then echo "note: $card waits for the owner's answer; /units and the Board say so while it stays blocked"
else echo "note: $card shows as the $NAME's on /units and the Board while it stays blocked"; fi
