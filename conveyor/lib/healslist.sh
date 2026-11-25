# SPDX-License-Identifier: Apache-2.0
# How a sighting of a finding finds its entry on the self-heals list (SELFHEALS, lib/paths.sh) or in the record of the
# entries that expired from it (HEALSDROPPED), and what it does there. Sourced by lib/followups.sh, which holds healsadd()
# (a listing) and calls these; healsseen() (a finding seen again that goes to no list) is called by judged() (lib/review.sh).

# jq: the finding of an entry without its Proof or its audit How, which move with the code and are worded again when the logs
# show the finding (exk: what two sightings of one finding at one place have in common), without its audit number (R1; two
# findings of an audit with different numbers are two findings, whatever their wording: rno), level, kind and id marks,
# which a later review gives it another way, without the backticks an audit puts round a place, without the line numbers of its file:line places, which move when a line is added
# above them, and without the stops that end it (key); the entries of <list> that a sighting $l ({card, issue, repo, finding,
# effect, why, from}; $id, the id its entry would have) names (same): its own id, or on the self-heals list one no batch card
# holds with the same finding of this repository (a listing of a card matches a live entry that card holds by its exact finding
# alone: two findings of one card that differ in their line numbers only are two findings; an entry another card saw is that
# card's now; in the record of expired entries (same(true)) one card's finding may have moved, so its line numbers need not
# match), and for a sort of the same issue, an entry of a sort alone; and what a sighting at time $t does to such an entry
# (again): it is seen now, one more time (sightings, which the Board's Self-heals page shows as "seen N×"), and, as no batch card holds it, it is of the card that saw it (and, from a review, of its issue: heals
# batch waits for that card to end), takes the area $l gives when it has none (an entry listed before the pack had its
# path-to-area map, lib/areas.sh; one with an area keeps it), and, when $l gives them, takes its kind, reason and finding (the text the listing has now: a
# sort counts the findings its issue still holds against the entries' text; an entry of a sort that a review sees again keeps the
# finding the sort stored, as healsitems() (lib/heals.sh) reads that text). A sighting names the entries that are as close to its
# finding as any are (tier): with its own text (exk) first, then with its text but for the level marks, backticks and the colon
# after a place (its line numbers kept: lkey), then with its text but for the line numbers (key); the entries of a nearer tier hide those of a farther one.
HEALSSAME="$HEALSONE"'def exk: one | sub("(?i)[.:;]* (- how|proof):.*$"; "");
  def rno: first(exk | capture("^(?<r>R[0-9]+) ") | .r) // null;
  def lkey: exk | sub("^R[0-9]+ "; "") | sub("^(\\[[^\\]]*\\] ?)+"; "") | gsub("`"; "")
    | gsub("(?<p>[A-Za-z0-9_./-]+:[0-9]+(-[0-9]+)?)(?![0-9A-Za-z]):"; "\(.p)") | sub("[.:;]+$"; "");
  def key: exk | sub("^R[0-9]+ "; "") | sub("^(\\[[^\\]]*\\] ?)+"; "") | gsub("`"; "")
    | gsub("(?<f>[A-Za-z0-9_./-]+):[0-9]+(-[0-9]+)?(?![0-9A-Za-z]):?"; "\(.f)") | sub("[.:;]+$"; "");
  def same($d): type == "object" and (.id == $id or ($l.effect != "docs drift" and .batched == null and ($l.effect == null or $d or .card != $l.card or (.finding | exk) == ($l.finding | exk)) and (.finding | key) == ($l.finding | key)
    and ((.finding | rno) as $a | ($l.finding | rno) as $b | $a == null or $b == null or $a == $b)
    and (.repo // $l.repo) == $l.repo and ($l.from != "sort" or (.from == "sort" and .issue == $l.issue))));
  def same: same(false);
  def tier($x): if $x == 2 then (.finding | exk) == ($l.finding | exk) elif $x == 1 then (.finding | lkey) == ($l.finding | lkey) else true end;
  def again: .seen = $t | .sightings = (.sightings // 0) + 1 | if .batched == null then .card = $l.card | (if .from == "review" then .issue = $l.issue else . end)
    | (if (.area // "") == "" and ($l.area // "") != "" then .area = $l.area else . end)
    | (if $l.effect then .effect = $l.effect | .why = $l.why | (if .from == "sort" and $l.from != "sort" then . else .finding = $l.finding end) else . end) else . end;'
# The id of the first entry of <list> that a sighting names (HEALSSAME; <dropped> true for the record of expired entries)
# and that is of <tier> or nearer: 2, its finding text as the sighting has it (its Proof and How aside, its line numbers
# kept: exk), 1, the same but for the level marks (lkey), 0, the same but for the line numbers too (key). Fails when none.
healspick() { # <list> <id | ""> <the sighting: JSON> <dropped: true | false> <tier: 0 | 1 | 2>
  jq -sre --arg id "$2" --argjson l "$3" --argjson d "$4" --argjson x "$5" "$HEALSSAME"'first(.[] | select(same($d) and tier($x)) | .id)' "$1" 2>/dev/null
}
# A sighting at time <time> of the finding of an entry of <list>, with the caller holding the list's lock. It names the
# entries of the nearest tier (healspick()) that has one, in the list and in HEALSDROPPED. A listing (<restore> 1) names
# one entry, the first of: one of the list of that tier, one of HEALSDROPPED of it (a finding that is listed live and in
# the record with only its line numbers apart is two findings; the entry it names starts its days to expire over, and no
# other entry changes). A sighting that is no listing (<restore> 0, the logs showed the finding) starts the days over of
# every entry of the list that it names in that tier, and so does not touch an entry of the same finding at another line
# while one at its own line is named. On the self-heals list, an entry of HEALSDROPPED that a listing names takes its line
# back to the list and leaves the record; it keeps when it expired (expired), so healsdrop() can put it back. A sighting
# that is no listing leaves an expired entry in the record, with its seen set to the sighting (the record shows the
# finding came back), whether or not a live entry of the list is named too: its finding is filed another way. Prints the
# id of the entry. Returns 3 when no entry is named, and fails when a file cannot be written.
healsagain() { # <list> <id | ""> <the sighting: JSON> <time> <restore: 1 | 0>
  local f=$1 rid='' drid='' sd=false x=3
  [ "$f" != "$SELFHEALS" ] || sd=true
  while [ $x -gt 0 ] && [ -z "$rid$drid" ]; do
    x=$((x - 1))
    rid=$(healspick "$f" "$2" "$3" false $x) || rid=''
    if [ "$sd" = true ] && { [ "$5" = 0 ] || [ -z "$rid" ]; }; then drid=$(healspick "$HEALSDROPPED" "$2" "$3" true $x) || drid=''; fi
  done
  if [ -n "$rid" ]; then
    jq -c --arg id "$2" --arg rid "$rid" --argjson l "$3" --arg t "$4" --argjson all "$([ "$5" = 0 ] && echo true || echo false)" --argjson x "$x" "$HEALSSAME"'if (if $all then same and tier($x) else .id == $rid end) then again else . end' "$f" > "$f.new" \
      && mv -f "$f.new" "$f" || { rm -f "$f.new"; return 1; }
  fi
  if [ -n "$drid" ]; then
    if [ "$5" = 0 ]; then
      jq -c --arg id "$2" --argjson l "$3" --arg t "$4" --argjson x "$x" "$HEALSSAME"'if same(true) and tier($x) then .seen = $t | .sightings = (.sightings // 0) + 1 else . end' "$HEALSDROPPED" > "$HEALSDROPPED.new" \
        && mv -f "$HEALSDROPPED.new" "$HEALSDROPPED" || { rm -f "$HEALSDROPPED.new"; return 1; }
    else
      jq -ce --arg id "$2" --arg rid "$drid" --argjson l "$3" --arg t "$4" "$HEALSSAME"'first(select(type == "object" and .id == $rid) | .expired = .dropped | del(.dropped) | again)' "$HEALSDROPPED" >> "$f" \
        && jq -c --arg rid "$drid" 'select(type != "object" or .id != $rid)' "$HEALSDROPPED" > "$HEALSDROPPED.new" && mv -f "$HEALSDROPPED.new" "$HEALSDROPPED" || { rm -f "$HEALSDROPPED.new"; return 1; }
    fi
    [ -n "$rid" ] || rid=$drid
  fi
  [ -n "$rid" ] || return 3
  printf '%s\n' "$rid"
}
# A finding the judge ruled harm (one whose Proof says it was seen in real logs is harm: SEENRX) or accepted, that an
# entry of the self-heals list names too, was seen again on <card> of <issue>: that entry starts its days to expire over
# (healsagain(), healsexpire(), lib/heals.sh), as when healsadd() finds it again. An entry that expired stays expired, and its record notes the sighting:
# such a finding is filed as a follow-up or fixed in the card, so it is not listed a second time. judged() (lib/review.sh)
# and healsapply() (lib/heals.sh) call it, as such a finding goes to no list. Fails when the list cannot be written.
healsseen() { # <card> <issue> <finding>...
  local l t f rc
  [[ $2 =~ ^[0-9]+$ && $1 == *[![:space:]]* ]] || return 2
  [ -s "$SELFHEALS" ] || [ -s "$HEALSDROPPED" ] || return 0
  t=$(clock) || return 1
  ( flock 9 || exit 1
    for f in "${@:3}"; do
      l=$(jq -cn --arg c "$1" --argjson n "$2" --arg f "$f" --arg repo "$REPO" '{card: $c, issue: $n, repo: $repo, finding: $f, effect: null, from: null}') || exit 1
      healsagain "$SELFHEALS" '' "$l" "$t" 0 >/dev/null; rc=$?
      [ $rc = 0 ] || [ $rc = 3 ] || exit 1
    done ) 9>>"$SELFHEALS.lock"
}
