# SPDX-License-Identifier: Apache-2.0
# The self-heals list (SELFHEALS, lib/paths.sh) and the docs list (DOCSDRIFT), fixed in batches, and the sort of the
# work filed before the lists existed. The judge sorts each finding by what its failure does, never by how likely it
# is (HARMRULE, lib/review.sh): a harm finding is built at once, as a follow-up; a self-heals, cleanup or already
# guarded one goes to the self-heals list, and a docs drift one to the docs list (healsadd(), lib/followups.sh).
# Each list is fixed one area at a time: healsbatch() files one card with an area's entries as its scope.

# The locks a card is filed under from a list (healsbatch(), healsharm()), in the subshell that holds the list's lock
# file open as fd 9. A card with no GitHub issue is added to the Tests page's record (tcput()): that lock is taken before
# the list's, the order testpick() and its retry take them in. Taken the other way round, each waits for the other with
# no end, until the pick's time limit (lockedfor(), lib/records.sh) or the Board's call limit stops one.
# The rule is read again under the list's lock, as the owner can turn it off while this ask waits for that lock: an
# issue filed on the old rule cannot be taken back. Turned off while the cards lock is not held, the list's lock is
# let go, the cards lock taken first, and the rule read again. Sets noissue (1: file a card with no GitHub issue) and
# tl (the cards lock's fd, else empty); fails, saying so, when the cards lock cannot be taken.
healslocks() {
  noissue=0 tl=''
  while :; do
    if [ -z "$tl" ] && [ "$(ctl 2>/dev/null | jq -r '.rules.followupissues' 2>/dev/null)" = false ]; then
      mkdir -p "$TESTACTS" 2>/dev/null
      { exec {tl}>>"$TACARDS.lock"; } 2>/dev/null && flock "$tl" || { echo "conveyor: the record of the Tests page's cards could not be locked; nothing filed" >&2; return 1; }
    fi
    flock 9 || return 1
    [ "$(ctl 2>/dev/null | jq -r '.rules.followupissues' 2>/dev/null)" = false ] || break
    [ -z "$tl" ] || { noissue=1; break; }
    flock -u 9
  done
}
# `conveyor.sh heals batch <area | ->` (the Board's Self-heals panel, "File a batch card"): one audit card for the
# entries of the self-heals list in <area> (an area label; - for the entries with none) that no batch card holds yet
# and whose card has ended (below), with them as its scope. With docs (`conveyor.sh heals docs <area | ->`, the
# Board's "File a docs sweep card", and release-prep: healsdocs()), one docs sweep card for the entries of the docs
# list in <area>. With the control record's rules.followupissues false it is a card with no GitHub issue (tcput(),
# lib/testaction.sh, under the cards lock, taken before the list's), as a review follow-up is; else an issue. Either way
# it has the pack's last priority and the area's label, and no follow-up depth: it is a first card, whose own review
# fixes its findings. A batch card with a self-heals entry has the pack's type label (a bug card: its fix has a test
# that fails on main); one of cleanup and already guarded entries alone, and a docs sweep card, has none, as a cleanup
# follow-up has none (followups()): no test can fail on main for them. The card's text tells it to check that the guard
# each already-guarded entry names still holds, and to fix one whose guard no longer does with a test; only a card of
# cleanup entries alone has the Cleanup: line, under which a change to what the code does is a finding. Each entry it
# holds keeps its issue number or card id (batched), so a second ask files none for them.
# The list's lock is held from the reading of the entries to their mark: two asks at once file one card. Exit 2 when
# the area has no open entry whose card has ended.
# The Board's batch sheet (the Self-heals page, parts/heals-page.js) names the entries it keeps (<id>..., of any area: the card still has
# <area>'s label), its title (--title) and level (--prio P2 or P3, a label as healsharm() maps one; else the pack's last
# priority), and files it held (--held: a card with no GitHub issue held as it is made, an issue made with the built
# label, then held, healsholdnow()) or queued (--queue: an issue released at once, healsholdnow(), so a project whose
# new issues start held does not hold it). Named ids that are not open entries of the list file nothing (exit 2); one
# whose card has not ended waits, as above.
healsbatch() { # <area | -> [docs] [--held | --queue] [--prio P2|P3] [--title <text>] [<id>...]
  local use="usage: conveyor.sh heals batch <area | -> [--held | --queue] [--prio P2|P3] [--title <text>] [<id>...] | heals docs <area | -> [the same]"
  [[ $# -ge 1 && -n $1 && $1 != *$'\n'* && ${2:-docs} =~ ^(docs)?$ ]] || { echo "$use" >&2; return 2; }
  local a=$1 lf=$SELFHEALS what='self-heals list' kind='Self-heals batch' tl='' rc held='' queued='' lvl='' name='' x; [ "$a" != - ] || a=''
  [ -z "${2:-}" ] || lf=$DOCSDRIFT what='docs list' kind='Docs sweep'
  shift; [ $# = 0 ] || shift
  while [ $# -gt 0 ]; do case $1 in
    --held) [ -z "$queued" ] || { echo "$use" >&2; return 2; }; held=held; shift ;;
    --queue) [ -z "$held" ] || { echo "$use" >&2; return 2; }; queued=1; shift ;;
    --prio) [[ ${2:-} =~ ^P[23]$ ]] || { echo "$use" >&2; return 2; }; lvl=${2#P}; shift 2 ;;
    --title) [[ -n ${2:-} && ${#2} -le 200 && $2 != *$'\n'* ]] || { echo "$use" >&2; return 2; }; name=$2; shift 2 ;;
    *) break ;; esac; done
  for x; do [[ $x =~ ^[hd][0-9A-Za-z-]{1,40}$ ]] || { echo "$use" >&2; return 2; }; done
  local ids; ids=$(jq -cn '$ARGS.positional' --args "$@")
  ( hold=(); queue=(); heldwhy='it was filed held'; trap 'healsholdnow "${hold[@]}"' EXIT
    healslocks || exit 1
    if [ "$ids" != '[]' ]; then
      miss=$({ cat "$lf" 2>/dev/null || :; } | jq -rn --argjson ids "$ids" '[inputs | objects | select(.batched == null) | .id] as $have | $ids - $have | join(" ")') \
        || { echo "conveyor: the $what could not be read; nothing filed" >&2; exit 1; }
      [ -z "$miss" ] || { echo "conveyor: the $what has no open entry $miss; nothing filed" >&2; exit 2; }
    fi
    # The cards that have not ended (no landed or closed line: in flight or blocked) and their issues. An entry of such a
    # card waits, as does one a review wrote (from: review) on an issue with such a card (a retry's new card): the code
    # its finding names is only in that card's change, so a batch card built on main now finds nothing to fix. It goes
    # to the next batch card of its area once that card ends. A card with no GitHub issue given back by `retry` is
    # known by its new card too (TACARDS was): the entry waits while the card of its own id or its new card is busy.
    # An issue given back by `retry` has no line in the card records until its next card is picked (its lines are in the
    # retried file), so it is busy too, until a card of it has landed or closed. So is a card with no GitHub issue given
    # back so (a main-red fix card or a Tests page card): it is busy while the card of its record (TACARDS, MAINRED) has
    # not landed or closed. That card is the given-back one until the pick, and its next card from the pick on: a
    # Tests page entry names the given-back card in its was, a main-red one by its commit, which the given-back card's
    # picked line (in the retried file) names. The retried file is long and the records grow, so each goes to jq as a
    # file, not an argument (Linux refuses one over 128 KiB). A record file that is not there holds no card.
    # The card records are read before the retried file, and the Tests page's cards once. `retry` (moveout(),
    # lib/issues.sh) writes a card's lines to the retried file before it takes them out of the card records, so a retry
    # that ends between the two reads leaves the card in one of them at least (the other way round, in neither).
    # testpick() sets the new card in TACARDS before its picked line is written, so an entry whose card was given back
    # waits while either the given-back card or its new one is busy (below).
    cl=$(stdb ask lines cards) && rt=$(stdb ask lines retried | jq -c 'objects | {card, issue, red: (.mainRed | if type == "string" then . else null end)}' | sort -u) \
      && tac=$(jq -c '.cards // []' "$TACARDS" 2>/dev/null || echo '[]') \
      || { echo "conveyor: the card records could not be read; nothing filed" >&2; exit 1; }
    busy=$(jq -cs --slurpfile r <(printf '%s\n' "$rt") --slurpfile ta <(printf '%s\n' "$tac") \
      --slurpfile re <(jq -c '.reds // []' "$MAINRED" 2>/dev/null || echo '[]') \
      'def idx: map({key: ., value: true}) | from_entries; def done: any(.step | IN("landed", "closed"));
      map(objects) | group_by(.card) as $g | ($g | map(select(done) | .[0])) as $end | ($g | map(select(done | not) | .[0])) as $open
      | ($end | map(.card) | idx) as $ec | ($g | map(.[0].card) | idx) as $have | ($r | map(.card | strings) | idx) as $rs
      | ($r | map(.issue | select(. != null and . != 0)) | unique) as $ri
      | ([($ta[0][], $re[0][]) | select((.card | type) == "string" and $ec[.card] == null) | .card, (.was // [])[]]
        + [$re[0][] | select((.card | type) == "string" and $ec[.card] == null) | .sha | strings | . as $s | $r[] | select(.red == $s) | .card]
        | map(select($rs[.] != null and $have[.] == null)) | unique) as $rc
      | {cards: (($open | map(.card)) + $rc), issues: (($open | map(.issue | select(. != 0))) + ($ri - ($end | map(.issue))))}' <<<"$cl") \
      || { echo "conveyor: the card records could not be read; nothing filed" >&2; exit 1; }
    es=$(jq -cs --arg a "$a" --argjson ids "$ids" --slurpfile b <(printf '%s\n' "$busy") --slurpfile tc <(printf '%s\n' "$tac") \
      'map(objects | select((if $ids == [] then (.area // "") == $a else .id | IN($ids[]) end) and .batched == null)) | map(.card as $c | . + {wait: (([$c, ((first($tc[0][] | select((.was // []) | index($c))) | .card) // $c)]
        | any(IN($b[0].cards[]))) or (.from == "review" and (.issue | IN($b[0].issues[]))))})' "$lf" 2>/dev/null) || es='[]'
    w=$(jq 'map(select(.wait)) | length' <<<"$es"); es=$(jq -c 'map(select(.wait | not) | del(.wait))' <<<"$es")
    k=$(jq length <<<"$es")
    [ "$k" -gt 0 ] || { echo "conveyor: the $what holds no open entry in ${a:-no area}$([ "$w" = 0 ] || echo " whose card has ended ($w wait for theirs to land or close)"); nothing filed" >&2; exit 2; }
    title=${name:-"$kind: $k finding$([ "$k" = 1 ] || echo s) of ${a:-no area}"}
    # The type label only for a batch with a self-heals entry (above); an entry with no effect was written as self-heals.
    t=''; [ "$lf" = "$DOCSDRIFT" ] || ! jq -e 'any(.[]; (.effect // "self-heals") == "self-heals")' <<<"$es" >/dev/null || t=$TYPE
    if [ "$lf" = "$DOCSDRIFT" ]; then
      body="Conveyor's docs list holds the findings below, of ${a:-no area}. The judge sorted each as docs drift: a guide or README omits or misdescribes what the code does correctly. Make the docs match what users see, in this card. Check each one against main first: fix one that still holds; name in the reply one that is already fixed or no longer true, and why. Change no code."
    else
      body="Conveyor's self-heals list holds the findings below, of ${a:-no area}. The judge sorted each by what its failure does, its kind under it: self-heals (its failure heals itself: a card waits longer, a step runs again, text the next poll corrects, extra work with no wrong result), cleanup (its fix changes no behaviour) or already guarded (another check, which its reason names as file:line, already stops the bad outcome). Fix them together in this card. Check each one against main first: fix one that still holds, a self-heals one with a test that fails without the fix; name in the reply one that is already fixed or no longer true, and why. For an already-guarded one, check first that the check its reason names still stops the outcome: when it no longer does, the finding is harm, so fix it here with a test that fails without the fix."
      # The Cleanup: line (a change to what the code does is a finding: REVIEWER, lib/prompts.sh) only when every entry is
      # cleanup: an already-guarded entry whose guard no longer holds asks for such a change.
      ! jq -e 'all(.[]; .effect == "cleanup")' <<<"$es" >/dev/null \
        || body+=$'\nCleanup: each finding here is cleanup, so no test has to fail on main for it. The change must keep what the code does: the review judges that it does.'
    fi
    body+=$'\n\n## Findings\n'$(jq -r 'map("- \(.finding)\n  - Kind: \(.effect // "self-heals"). From: card \(.card), issue #\(.issue). The judge: \(.why) (list entry \(.id))") | join("\n")' <<<"$es")
    if [ -z "$lvl" ]; then prio=$(jq -r '.[-1] // empty' <<<"$PRIOS")
    else prio=$(jq -r --argjson i "$lvl" 'if $i == 3 and length < 4 then "" else .[[$i, length - 1] | min] // "" end' <<<"$PRIOS"); fi
    # Its area label: the area's, else (a batch of no area) that of the file its first finding names, else the map's other (lib/areas.sh).
    la=$(filearea "$a" "$(jq -r '.[0].finding' <<<"$es")") || la=$a
    if [ "$noissue" = 1 ]; then
      num=$(tcput "" "$title" "$body" "$held" "$kind: ${a:-no area}" "$(jq -cn '$ARGS.positional' --args ${t:+"$t"} ${prio:+"$prio"} ${la:+"$la"})") || exit 1
    else
      pm=''; packget privacy.mode pm || { echo "conveyor: the pack's privacy mode could not be read; nothing filed" >&2; exit 1; }
      [ "$pm" != public ] || body=$(privmask "$body") || { echo "conveyor: the privacy check could not be made; nothing filed" >&2; exit 1; }
      out=$(gh_write issue create --title "$title" ${t:+--label "$t"} ${prio:+--label "$prio"} ${la:+--label "$la"} ${held:+--label "$BUILT"} --body "$body" 2>&1) \
        && num=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1) && num=${num##*/} && [ -n "$num" ] || { echo "conveyor: the $kind card was not filed: ${out:0:400}" >&2; exit 1; }
      [ -z "$held" ] || hold+=("$num"); [ -z "$queued" ] || queue+=("$num")
    fi
    jq -c --argjson ids "$(jq -c 'map(.id)' <<<"$es")" --arg b "$num" 'if type == "object" and (.id | IN($ids[])) then .batched = ($b | tonumber? // $b) else . end' "$lf" > "$lf.new" \
      && mv -f "$lf.new" "$lf" || { rm -f "$lf.new"; echo "conveyor: the $kind card $num is filed, but the list could not mark its entries" >&2; exit 1; }
    echo "conveyor: filed $num with $k finding$([ "$k" = 1 ] || echo s) of ${a:-no area}$([ "$w" = 0 ] || echo "; $w wait for their card to land or close and stay on the list")" ) 9>>"$lf.lock"
  rc=$?; [ -z "$tl" ] || exec {tl}>&-
  return $rc
}
# The ids given that are not open entries of the self-heals list (none such, or one a batch card holds), one line;
# empty when each is. Fails when the list cannot be read. The caller holds the list's lock.
healsmissing() { # <id>...
  { cat "$SELFHEALS" 2>/dev/null || :; } | jq -rn '[inputs | objects | select(.batched == null) | .id] as $have | $ARGS.positional - $have | join(" ")' --args "$@"
}
# Entries <ids> (a JSON list) of the self-heals list leave it for the dropped record (HEALSDROPPED), each with dropped
# {time, why: <why>} and, for one moved up to harm, filed (its card's issue number or id). Its freed goes, so a retry of
# the batch card that gave it back (healstake(), lib/followups.sh) does not take it back to the list. The dropped lines
# are written before the list is, as healsexpiry() writes them: a failure between the two leaves an entry in both, never
# in neither. The caller holds the list's lock.
healsgone() { # <ids json> <why> [<filed>]
  local f=$SELFHEALS t
  t=$(clock) || return 1
  jq -c --argjson ids "$1" --arg t "$t" --arg why "$2" --arg n "${3:-}" 'select(type == "object" and (.id | IN($ids[])) and .batched == null)
    | del(.freed, .expired) + {dropped: ({time: $t, why: $why} + if $n == "" then {} else {filed: ($n | tonumber? // $n)} end)}' "$f" >> "$HEALSDROPPED" \
    && jq -c --argjson ids "$1" 'select(type != "object" or (.id | IN($ids[]) | not) or .batched != null)' "$f" > "$f.new" && mv -f "$f.new" "$f" \
    || { rm -f "$f.new"; return 1; }
}
# `conveyor.sh heals drop <id>...` (the Board's Self-heals page, "Drop now"): the owner takes entries off the self-heals
# list before their days run out. Each leaves for the dropped record with dropped {time, why: dropped}, kept there as an
# expired one is: the same finding listed again takes its line back (healsadd(), lib/followups.sh). When an id is not an
# open entry of the list (none such, or one a batch card holds), nothing is dropped (exit 2).
healsdiscard() { # <id>...
  [ $# -ge 1 ] && ! printf '%s\n' "$@" | grep -qvE '^h[0-9A-Za-z-]{1,40}$' || { echo "usage: conveyor.sh heals drop <id>..." >&2; return 2; }
  ( flock 9 || exit 1
    miss=$(healsmissing "$@") || { echo "conveyor: the self-heals list could not be read; nothing dropped" >&2; exit 1; }
    [ -z "$miss" ] || { echo "conveyor: the self-heals list has no open entry $miss; nothing dropped" >&2; exit 2; }
    healsgone "$(jq -cn '$ARGS.positional' --args "$@")" dropped || { echo "conveyor: the self-heals list could not be written; nothing dropped" >&2; exit 1; }
    echo "conveyor: dropped $# entr$([ $# = 1 ] && echo y || echo ies) from the self-heals list" ) 9>>"$SELFHEALS.lock"
}
# What stands in for the issue of main-red fix card <card> (redissue(), lib/redfix.sh). $MAINRED no longer names a card
# given back by `retry` and picked again, nor one that blocked or closed and that pushred() replaces. Its entry, which
# may name a new card or none yet, is found by main's commit: the card's picked line names it, in the card records or, once
# given back, in the retried file (read in that order, as `retry` writes it there first). Fails for any other card.
healsred() { # <card>
  local s
  redissue "$1" && return 0
  # jq reads to the end: one that stops at its match fails the pipe (pipefail) when more lines follow than it holds.
  s=$({ stdb ask card "$1" && stdb ask lines retried; } | jq -rn --arg c "$1" '[inputs | objects | select(.card == $c) | .mainRed | strings] | first // empty') && [ -n "$s" ] || return 1
  redissue "$s"
}
# `conveyor.sh heals harm <id>...` (the Board's Self-heals page, "Move up to harm"): the owner saw the finding of each
# entry <id> of the self-heals list in real logs or records, so it is harm and gets its own follow-up card at once, as
# followups() files a harm finding: the pack's follow-up label, its type label (none for a cleanup entry), the priority
# of the finding's [P<n>] (P1 when it names none) and an area label: its parent's (the entry's issue, else the card with
# no GitHub issue that listed it), else that of the file the finding names, else the map's other (filearea(),
# lib/areas.sh), else the entry's; an entry whose issue's labels cannot be read is not filed. With rules.followupissues
# false a card with no GitHub issue (the locks of healslocks()). Each entry then leaves the list for the dropped record (healsgone(),
# why: harm, filed: the card), so it is neither on the list nor lost; it is marked right after its own card is filed, so
# a failure on a later entry leaves none filed twice. When an id is not an open entry of the list, nothing is filed (exit 2).
# A finding that names one of the pack's pipelineFiles (onpipeline(), lib/followups.sh) is filed held, as followups()
# files one, with its "Cost to every card:" line: a card with no GitHub issue held as it is made; an issue made with the
# built label, which the pick skips, then held in the control record and the label taken off (healsholdnow()).
healsharm() { # <id>...
  [ $# -ge 1 ] && ! printf '%s\n' "$@" | grep -qvE '^h[0-9A-Za-z-]{1,40}$' || { echo "usage: conveyor.sh heals harm <id>..." >&2; return 2; }
  local tl='' rc
  ( hold=(); trap 'healsholdnow "${hold[@]}"' EXIT
    healslocks || exit 1
    miss=$(healsmissing "$@") || { echo "conveyor: the self-heals list could not be read; nothing filed" >&2; exit 1; }
    [ -z "$miss" ] || { echo "conveyor: the self-heals list has no open entry $miss; nothing filed" >&2; exit 2; }
    pm=''; [ "$noissue" = 1 ] || packget privacy.mode pm || { echo "conveyor: the pack's privacy mode could not be read; nothing filed" >&2; exit 1; }
    pipe=''; packget pipelineFiles pipe || { echo "conveyor: the pack's pipeline files could not be read; nothing filed" >&2; exit 1; }
    for id; do
      e=$(jq -c --arg id "$id" 'select(type == "object" and .id == $id)' "$SELFHEALS" | head -n 1) && f=$(jq -r .finding <<<"$e") && g=$f \
        || { echo "conveyor: entry $id could not be read; it is not filed" >&2; exit 1; }
      [ "$pm" != public ] || g=$(privmask "$f") || { echo "conveyor: the privacy check could not be made; entry $id is not filed" >&2; exit 1; }
      mark=$(grep -oE '\[P[0-3]\]' <<<"$f" | head -n 1 | tr -d '[]P'); where=$(grep -oE '[^[:space:]]+:[0-9]+' <<<"$g" | head -n 1)
      mark=$(jq -r --argjson i "${mark:-1}" 'if $i == 3 and length < 4 then "" else .[[$i, length - 1] | min] end' <<<"$PRIOS")
      t=$TYPE; [ "$(jq -r .effect <<<"$e")" != cleanup ] || t=''
      n=$(jq -r .issue <<<"$e")
      if [ "$n" != 0 ]; then
        par=$(timeout 20 gh issue view "$n" --json labels 2>/dev/null) || { echo "conveyor: the labels of #$n, the issue of entry $id, could not be read; it is not filed" >&2; exit 1; }
      else # a card with no GitHub issue: a main-red fix card (healsred()), else one of the record, under the id it has now or had before it was given back (was)
        c=$(jq -r .card <<<"$e")
        par=$(healsred "$c") || par=$(jq -c --arg c "$c" 'first(.cards[]? | select(.card == $c or any(.was[]?; . == $c))) | {labels: [.labels[]? | {name: .}]}' "$TACARDS" 2>/dev/null) || par=''
      fi
      pa=$(jq -r --arg p "$AREA" 'first(.labels[]?.name | select(startswith($p)))' <<<"$par") || pa=''
      a=$(filearea "$pa" "$f") || a=$pa
      [ -n "$a" ] || a=$(jq -r '.area // empty' <<<"$e")
      cost=$(onpipeline "$f" <<<"$pipe") || { echo "conveyor: whether entry $id names a pipeline file could not be told; it is not filed" >&2; exit 1; }
      body=$(jq -r --arg w "${where:-the finding names no file:line}" '"Conveyor'"'"'s self-heals list held the finding below. The owner moved it up to harm on the Board: it shows up in real logs or records, so it is fixed in a card of its own.\n\nFinding: \(.finding)\nWhere: \($w)\nKind: harm (moved up from the self-heals list, where the judge had sorted it as \(.effect // "self-heals"): \(.why))\nFrom: card \(.card), issue #\(.issue) (list entry \(.id))"' <<<"$e") \
        || { echo "conveyor: entry $id could not be read; it is not filed" >&2; exit 1; }
      [ "$pm" != public ] || body=$(privmask "$body") || { echo "conveyor: the privacy check could not be made; entry $id is not filed" >&2; exit 1; }
      [ -z "$cost" ] || body+=$'\nCost to every card: not assessed'
      if [ "$noissue" = 1 ]; then
        num=$(tcput "" "$(futitle "$g")" "$body" "${cost:+held}" "Self-heals moved up to harm" "$(jq -cn '$ARGS.positional' --args "$FOLLOWUP" ${t:+"$t"} ${mark:+"$mark"} ${a:+"$a"})") || exit 1
      else
        out=$(gh_write issue create --title "$(futitle "$g")" --label "$FOLLOWUP" ${t:+--label "$t"} ${mark:+--label "$mark"} ${a:+--label "$a"} ${cost:+--label "$BUILT"} --body "$body" 2>&1) \
          && num=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1) && num=${num##*/} && [ -n "$num" ] || { echo "conveyor: entry $id was not filed: ${out:0:400}" >&2; exit 1; }
        [ -z "$cost" ] || hold+=("$num")
      fi
      healsgone "$(jq -cn '[$ARGS.positional[0]]' --args "$id")" harm "$num" || { echo "conveyor: entry $id is filed as $num, but it could not leave the self-heals list" >&2; exit 1; }
      echo "conveyor: entry $id moved up to harm: filed $num"
    done ) 9>>"$SELFHEALS.lock"
  rc=$?; [ -z "$tl" ] || exec {tl}>&-
  return $rc
}
# On the exit of healsharm()'s or healsbatch()'s subshell, whatever ended it (heldwhy: why it is held, a pipeline file
# when unset): each issue <n> it filed with the built label is held in the
# control record (`control hold`), then the label taken off; each issue of queue (healsbatch()'s --queue) is released
# (`control release`): the owner's File and queue, so adopted() (lib/control.sh) never holds it, whatever where new
# issues start. The list's lock and the cards lock are let go first: `retry`
# takes the records' lock before the list's (healstake(), lib/followups.sh), so a hold asked under the list's lock could
# wait for that retry while it waits for this list. Keeps the subshell's exit status, else 1 when an issue is left
# unheld or unreleased.
healsholdnow() { # <n>...
  local rc=$? n
  flock -u 9 2>/dev/null; [ -z "${tl:-}" ] || flock -u "$tl" 2>/dev/null
  for n in ${queue[@]+"${queue[@]}"}; do
    locked control release "$n" > /dev/null 2>&1 \
      || { rc=1; echo "conveyor: #$n is filed, but could not be queued: release it (conveyor.sh control release $n), as a project whose new issues start held holds it" >&2; }
  done
  for n; do
    if ! locked control hold "$n" > /dev/null 2>&1; then rc=1; echo "conveyor: #$n is filed, but could not be held (${heldwhy:-its finding names a pipeline file}): hold it (conveyor.sh control hold $n) unless the owner has said yes to it, and take the $BUILT label off it, which the belt skips" >&2
    elif gh_write issue edit "$n" --remove-label "$BUILT" > /dev/null 2>&1; then echo "conveyor: #$n is held, as ${heldwhy:-its finding names a pipeline file}: release it (conveyor.sh control release $n) once the owner says yes"
    else rc=1; echo "conveyor: #$n is held, as ${heldwhy:-its finding names a pipeline file}, but the $BUILT label could not be taken off it: take it off before you release it (conveyor.sh control release $n), as the belt skips an issue with it" >&2; fi
  done
  exit "$rc"
}
# release-prep (commands/release-prep.sh), before the suite: one docs sweep card (healsbatch() docs) for each area of
# the docs list with an open entry, so the docs match what users see in the release. An area whose entries all wait
# for their card (exit 2) files none. Prints what it filed; fails when a card could not be filed, the others filed.
healsdocs() {
  local a rc=0
  while IFS= read -r a; do
    healsbatch "${a:--}" docs 2>&1; case $? in 0|2) ;; *) rc=1 ;; esac
  done < <(jq -r 'objects | select(.batched == null) | .area // ""' "$DOCSDRIFT" 2>/dev/null | sort -u)
  return $rc
}

# What the sort's judge is told (healssort()), then the findings, numbered.
healsprompt() {
  printf '%s\n' 'You sort open review findings of this project. Each finding at the end of this message was filed for a fix,
as a follow-up card or an issue, before the rule below existed. Read the code each one names, as it stands in this
worktree (main), when you need it to tell what its failure does. Do not run tests or builds, and change nothing.' "$HARMRULE" \
    'Answer with exactly one line for each finding, in order, and no other line:
`F<n> HARM: <one-line reason>`
`F<n> SELF-HEALS: <one-line reason>`
`F<n> CLEANUP: <one-line reason>`
`F<n> ALREADY GUARDED: <one-line reason that names the check as file:line>`
`F<n> DOCS DRIFT: <one-line reason>`'
}
# jq: a finding of an issue of many is a body line `- **<id> [P<n>] ...` (ispart) and the indented lines under it,
# its line $s of the body's lines $l; partend is the line after them, partof its text as the judge is given it.
# healsitems() reads it, and healsmove() reads it again from the body as it is now, so it moves only the text the
# judge read.
HEALSPART='def ispart: test("^- \\*\\*[A-Za-z]+[0-9]+ \\[P[0-3]\\]");
  def partend($l; $s): first(range($s + 1; $l | length) | select($l[.] | test("^\\s") | not)) // ($l | length);
  def partof($l; $s): $l[$s:partend($l; $s)] | map(gsub("^\\s+|\\s+$"; "")) | .[0] |= ltrimstr("- ") | join(" ") | gsub("\\*\\*"; "");'
# The items the sort reads, one JSON line each, numbered n from 1: {kind: card, id, issue (the issue it follows up),
# area, from (the card it came from), finding} for each queued review follow-up card (TACARDS: not picked, with the
# pack's follow-up label, held or not: one held when the sort runs is built once it is released, so it is sorted now
# like the others); {kind: issue, issue, area, from, finding} for each open issue that is one finding
# (a [P0] to [P3] title, and a Proof in its title or body: its body's "Finding:" line, else its title); {kind: part,
# issue, area, from, head (its first line), fid (its id), finding} for each finding of an open issue that holds many
# (a body line `- **<id> [P<n>] ...`, with the indented lines under it), but one an earlier sort moved to the list
# (the sort never edits a body, so it stays there). An issue the owner ordered that is no finding has neither shape and is not sorted; nor is a held issue
# (healsheld(): it stays held, whatever its kind), one with the pack's built label, or one with a card that has not
# landed or closed. A card or issue whose body has a "Kind:" line was filed by followups() under this rule, with
# the judge's kind: it is sorted already, and never sent to the judge again. Fails when the holds cannot be read.
healsitems() { # <the open issues json>
  local h busy
  h=$(healsheld "$1") || return 1
  busy=$(stdb ask lines cards 2>/dev/null | jq -cs 'group_by(.card) | map(select(any(.step | IN("landed", "closed")) | not) | .[0].issue)' 2>/dev/null) || busy='[]'
  { jq -c --arg fu "$FOLLOWUP" --arg p "$AREA" '.cards[]? | select(.card == null and ((.labels // []) | index($fu) != null))
      | select(.body // "" | test("(?:^|\n)Kind: ") | not)
      | {kind: "card", id, issue: (.parent // 0), area: ((.labels // []) | map(select(startswith($p))) | .[0] // null),
         from: ([.body // "" | match("Conveyor card (c[^)[:space:]]+)") | .captures[0].string][0] // .id),
         finding: ([.body // "" | match("(?:^|\n)Finding: ([^\n]*)") | .captures[0].string][0] // null)}' "$TACARDS" 2>/dev/null
    jq -c --argjson h "$h" --arg built "$BUILT" --arg p "$AREA" --argjson busy "${busy:-[]}" --slurpfile ls <(healslisted) "$HEALSPART$HEALSONE"'
      .[]? | select((.number | IN($h[]) or IN($busy[])) | not) | select(any(.labels[]?; .name == $built) | not) | select(.body // "" | test("(?:^|\n)Kind: ") | not)
      | (.labels // [] | map(.name | select(startswith($p))) | .[0] // null) as $a
      | ([.body // "" | match("Conveyor card (c[^)[:space:]]+)") | .captures[0].string][0] // "#\(.number)") as $from
      | if (.title | test("^\\s*\\[P[0-3]\\]")) and ((.title + "\n" + (.body // "")) | test("Proof:")) then
          {kind: "issue", issue: .number, area: $a, from: $from, finding: ([.body // "" | match("(?:^|\n)Finding: ([^\n]*)") | .captures[0].string][0] // .title)}
        else .number as $n | (.body // "" | split("\n")) as $l
          | range(0; $l | length) as $s | select($l[$s] | ispart) | select({issue: $n, finding: (partof($l; $s) | one)} | IN($ls[]) | not)
          | {kind: "part", issue: $n, area: $a, from: "#\($n)", head: $l[$s], fid: ($l[$s] | capture("^- \\*\\*(?<i>[A-Za-z]+[0-9]+) ").i),
             finding: partof($l; $s)}
        end' <<<"$1"
  } | jq -c -s 'to_entries | map(.value + {n: (.key + 1)}) | .[]'
}
# The findings of issues that a sort moved to the self-heals list or the docs list, {issue, finding} a line, those that
# expired off the self-heals list too (HEALSDROPPED): the issue's body still holds them, and they are not sorted again.
healslisted() { cat "$SELFHEALS" "$HEALSDROPPED" "$DOCSDRIFT" 2>/dev/null | jq -c 'objects | select(.from == "sort") | {issue, finding}' 2>/dev/null || :; }
# The open issues held now, as a JSON list: the control record's held with the holds adopted() adds to it for these
# issues (a span of startHeld, the filing mark, an author outside the project), as pick reads them. Fails when the
# control record cannot be read: then no issue may be sorted.
healsheld() { # <the open issues json>
  local c; c=$(ctl 2>/dev/null) && adopted "$c" "$1" 2>/dev/null | jq -ce '.held // [] | arrays' 2>/dev/null
}
# The judge's kind of each item with a finding (healsitems() in <folder>/items): its answer read into <folder>/rulings, {n, effect,
# why} a line, one for each item it gave exactly one readable line; an item it gave none is harm (healsapply()). A
# finding whose Proof says it was seen in real logs or records is harm whatever it said (SEENRX, lib/followups.sh), as
# is an already-guarded one whose reason names no check found at a file:line of main (guardless(), lib/followups.sh).
# Prints the judge's fields (judgecall(), lib/review.sh); fails, printing them with failed, when it gave no answer.
healsjudge() { # <folder>
  local j x rc ACCT RACCT bad
  mapfile -t x < <(SEATCARD='' cardaccts "$(ctl 2>/dev/null)")
  # shellcheck disable=SC2034 # ACCT and RACCT are read by judgecall() in lib/review.sh: the accounts a card started now would use
  ACCT=${x[0]-} RACCT=${x[1]-}
  git -C "$MAIN" worktree add -q --detach "$1/wt" >/dev/null 2>&1 || { jq -cn '{failed: "no worktree of main could be made for the judge"}'; return 1; }
  j=$(CALLSTEP=sort CALLACT='the judge sorts the queued follow-ups and open finding issues' judgecall "$1/wt" "$(healsprompt)" \
    "# The findings"$'\n'"$(jq -r 'select((.finding // "") | test("[^[:space:]]")) | "F\(.n) [\(if .kind == "card" then "card " + .id else "issue #\(.issue)" end)] \(.finding)"' "$1/items")"); rc=$?
  [ $rc != 0 ] || jq -cRn --slurpfile i <(jq -c . "$1/items") --arg seen "$SEENRX" '[inputs | gsub("^([[:space:]`*-]|[0-9]+[.)])+|[[:space:]`*]+$"; "")
      | capture("^F(?<n>[0-9]+) (?<e>HARM|SELF-HEALS|CLEANUP|ALREADY[ -]GUARDED|DOCS[ -]DRIFT):[[:space:]]*(?<r>.*[^[:space:]].*)$"; "i") | .n |= tonumber
      | .e |= (ascii_downcase | sub("-"; " ") | sub("^self heals$"; "self-heals"))] | group_by(.n) | map(select(length == 1) | .[0])[]
    | .n as $n | (first($i[] | select(.n == $n)) // null) as $x | select($x != null)
    | (.e != "harm" and ($x.finding | test($seen; "i"))) as $seenit
    | {n: $n, effect: (if $seenit then "harm" else .e end), why: (.r + if $seenit then " (its Proof says it was seen in real logs or records, so it is harm)" else "" end)}' \
    "$1/wt.judge" > "$1/rulings" 2>/dev/null || : > "$1/rulings"
  # An already-guarded ruling whose guard is not found in main's worktree, read before it goes, is harm; a check that
  # cannot be made keeps no ruling, so each item stays, as harm.
  bad=$(jq -r 'select(.effect == "already guarded") | [.n, .why] | map(tostring | gsub("[[:space:]]+"; " ")) | join("\t")' "$1/rulings" 2>/dev/null | guardless "$1/wt") \
    || { bad='[]'; : > "$1/rulings"; }
  [ "$bad" = '[]' ] || { jq -c --argjson b "$bad" --arg w "$GUARDLESS" 'if .n | IN($b[]) then .effect = "harm" | .why += $w else . end' "$1/rulings" > "$1/rulings.new" \
    && mv -f "$1/rulings.new" "$1/rulings" || : > "$1/rulings"; }
  git -C "$MAIN" worktree remove --force "$1/wt" >/dev/null 2>&1
  printf '%s\n' "$j"; return $rc
}
# Each item of <folder>/items given its kind (<folder>/rulings; with none, or with no finding text, it is harm). A harm
# item stays as it is. One of a kind kept off the belt (self-heals, cleanup, already guarded or docs drift) goes to the
# list of its kind first (healsadd(), from: sort), so it is never lost, then: a
# card leaves the queue (tcdrop(); one a card picked meanwhile is built, and its line says so); a one-finding issue is
# read again once its entry is written, just before its close (healssame()): one changed, closed or held since the
# judge read it stays open and its entry leaves the list (healsdrop()); else it is closed as not planned, with a
# comment that names its list entry (healsclose(): one changed as it closed is opened again, and its entry leaves the
# list too). Such findings of an issue of many go to their lists with one comment on the issue (healsmove()).
# The sort never edits an issue's body. An issue held now (healsheld(), read again after the judge: a hold added while it
# read stays) is left as it is. Writes the log's items to <folder>/log, one JSON line each (healslog()), and for each
# issue of many, {issue, moved, closed, done, note}.
healsapply() { # <folder>
  local it k n e why id f a from iss entry note ok h parts=()
  : > "$1/log"
  h=$(healsheld "$(cat "$1/issues")") || h=null
  while IFS= read -r it; do
    k=$(jq -r .kind <<<"$it") n=$(jq -r .n <<<"$it") f=$(jq -r '.finding // ""' <<<"$it") a=$(jq -r '.area // ""' <<<"$it")
    from=$(jq -r .from <<<"$it") iss=$(jq -r .issue <<<"$it") id=$(jq -r '.id // ""' <<<"$it")
    e=$(jq -r --argjson n "$n" 'select(.n == $n) | .effect' "$1/rulings" 2>/dev/null | head -n 1)
    why=$(jq -r --argjson n "$n" 'select(.n == $n) | .why' "$1/rulings" 2>/dev/null | head -n 1)
    if [[ $f != *[![:space:]]* ]]; then e=harm why='it holds no finding text, so it stays, as harm'
    elif [ -z "$e" ]; then e=harm why='the judge gave no line for it that could be read, so it stays, as harm'
    elif [ "$e" = harm ]; then healsseen "$from" "$iss" "$f" || echo "conveyor: the self-heals list could not be told that issue $iss's finding was seen again" >&2; fi
    entry='' note='' ok=true
    if [ "$e" != harm ] && [ "$k" != card ] && ! jq -e --argjson i "$iss" 'arrays | index($i) == null' <<<"$h" >/dev/null 2>&1; then
      ok=false note='it is held now, or its holds could not be read, so it stays as it is'
    elif [ "$e" != harm ] && [ "$k" = part ]; then
      parts+=("$(jq -c --arg why "$why" --arg e "$e" '. + {why: $why, effect: $e}' <<<"$it")"); continue
    elif [ "$e" != harm ]; then
      if ! entry=$(healsadd "$from" "$iss" "$a" "$why" "$f" sort "$e"); then entry='' ok=false note='its list could not be written, so it stays'
      elif [ "$k" = card ]; then
        tcdrop "$id"; ! jq -e --arg c "$id" 'any(.cards[]?; .id == $c)' "$TACARDS" >/dev/null 2>&1 || { ok=false note='a card picked it before it could leave the queue, so it is built'; }
      elif ! healssame "$1" "$iss"; then
        ok=false note='it was changed, closed or held on GitHub after the judge read it, or could not be read again, so it stays as it is'
        healsdrop "$entry" || note+=', and its entry could not leave its list'
        entry=''
      elif ! healsclose "$iss" "$(jq -c --argjson n "$iss" 'first(.[] | select(.number == $n))' "$1/issues")" \
          "Conveyor sorted this finding by what its failure does: the judge sorted it as $e. It is now entry $entry of the $(healswhat "$e"), which a $(healscard "$e") of its area fixes with the others, so this issue is closed."; then
        ok=false note='it could not be closed, or it changed as it was closed and was opened again, so it stays'
        healsdrop "$entry" || note+=', and its entry could not leave its list'
        entry=''
      fi
    fi
    healslog "$k" "$id" "$iss" "$f" "$e" "$why" "$entry" "$ok" "$note" >> "$1/log"
  done < "$1/items"
  [ ${#parts[@]} = 0 ] || healsmove "${parts[@]}" >> "$1/log"
}
# Issue <n> closed as not planned with <comment>, then read again: when its title or body is no longer that of <the
# issue json> (an edit made after the last read, as it closed) or it cannot be read, it is opened again with a comment
# that says why, and healsclose fails: an issue is never left closed on a ruling of text the judge did not read.
healsclose() { # <issue> <the issue json> <comment>
  local now
  gh_write issue close "$1" --reason "not planned" --comment "$3" >/dev/null 2>&1 || return 1
  now=$(timeout 60 gh issue view "$1" --json title,body 2>/dev/null) \
    && jq -e --argjson o "$2" '.title == $o.title and (.body // "") == ($o.body // "")' <<<"$now" >/dev/null 2>&1 && return 0
  gh_write issue reopen "$1" --comment "Conveyor opened this issue again: it changed as the sort closed it, or could not be read again, so the ruling of its earlier text does not hold. Its findings are not on the self-heals list; the next sort reads it again." >/dev/null 2>&1 \
    || echo "conveyor: #$1 changed as the sort closed it, and could not be opened again: open it by hand" >&2
  return 1
}
# A log line of the sort for one item: {card or issue, finding (its first 300 characters), effect, why, entry (a
# self-heals one's list id), done (false when its action failed), note (what failed)}.
healslog() { # <kind> <card id> <issue> <finding> <effect> <why> <entry> <done> <note>
  jq -cn --arg k "$1" --arg id "$2" --argjson i "$3" --arg f "$4" --arg e "$5" --arg why "$6" --arg en "$7" --argjson d "$8" --arg note "$9" \
    '(if $k == "card" then {card: $id} else {issue: $i} end) + {finding: $f[0:300], effect: $e, why: $why, done: $d}
     + (if $en == "" then {} else {entry: $en} end) + (if $note == "" then {} else {note: $note} end)'
}
# Issue <n> as GitHub holds it now ({number, state, title, body, labels}), when it is open and not held
# (healsheld()); fails otherwise. healssame() and healsmove() read an issue with it just before they close or comment
# on it, so an edit made before that read is never closed on.
healsnow() { # <issue>
  local cur
  cur=$(timeout 60 gh issue view "$1" --json number,state,title,body,labels 2>/dev/null) \
    && jq -e '.state == "OPEN"' <<<"$cur" >/dev/null 2>&1 \
    && jq -e --argjson i "$1" 'index($i) == null' <<<"$(healsheld "[$cur]")" >/dev/null 2>&1 && printf '%s\n' "$cur"
}
# Whether issue <n>, read again from GitHub now (healsnow()), is open, not held, and has the title and body the judge
# read (<folder>/issues): a one-finding issue whose Proof was edited since the judge read it is not closed on a ruling
# of the old text.
healssame() { # <folder> <issue>
  local cur
  cur=$(healsnow "$2") && jq -e --argjson n "$2" --slurpfile w "$1/issues" 'first($w[0][] | select(.number == $n)) as $o
      | .title == $o.title and (.body // "") == ($o.body // "")' <<<"$cur" >/dev/null 2>&1
}
# The entry <id> a sort wrote to the self-heals list or the docs list (healsadd(), from: sort; a d id is the docs
# list's) for a finding it then left where it was (healsapply(), healsmove()): taken off the list, so the finding is
# not both in its issue and on the list. An entry a batch card holds already stays; one that was taken back from the
# dropped record goes back to it. Fails when the list cannot be written again.
healsdrop() { # <entry id>
  local f=$SELFHEALS; [[ $1 != d* ]] || f=$DOCSDRIFT
  ( flock 9 || exit 1
    # An entry that came back from the dropped record (healsagain(), lib/followups.sh) goes back to it as it expired, written
    # before the list is, so a failure between the two leaves it in both, never in neither.
    [ "$f" != "$SELFHEALS" ] || jq -c --arg id "$1" 'select(type == "object" and .id == $id and .from == "sort" and .batched == null and .expired != null) | .dropped = .expired | del(.expired)' "$f" >> "$HEALSDROPPED" || exit 1
    jq -c --arg id "$1" 'select(type != "object" or .id != $id or .from != "sort" or .batched != null)' "$f" > "$f.new" \
      && mv -f "$f.new" "$f" || { rm -f "$f.new"; exit 1; } ) 9>>"$f.lock"
}
# <kind>: the name of its list, and of the card that fixes an area's entries of that list (healsbatch()).
healswhat() { if [ "$1" = 'docs drift' ]; then echo 'docs list'; else echo 'self-heals list'; fi; }
healscard() { if [ "$1" = 'docs drift' ]; then echo 'docs sweep card'; else echo 'batch card'; fi; }
# The findings of each issue of many that the judge sorted as a kind kept off the belt (healsapply(): each its item, a
# JSON line with the judge's why and kind, effect; each goes to the list of its kind). The
# issue is read again first (healsnow()): one closed or held meanwhile is left as it is. A finding moves only when the
# body still holds it as the judge read it (its first line, head, with the lines under it: partof()); one changed or no
# longer there stays in the issue and off the list. Each one that moves goes to the list (healsadd()). The body is
# never edited: a read, change and write of it would lose an edit made between the read and the write. ONE comment
# names the findings that moved and their entries; when every finding of the body is on the list, the issue is closed
# as not planned with it instead (healsclose()). When the comment or the close fails, the entries this sort wrote
# leave the list (healsdrop()), so a finding is on the list only when its issue says so. Prints a log line for each
# finding (healslog()) and {issue, moved (the entries), closed, done, note} for each issue.
healsmove() { # <part item>...
  local iss cur p entry f why e msg note ok closed hit left logs
  for iss in $(printf '%s\n' "$@" | jq -r .issue | sort -un); do
    note='' ok=true closed=false hit='' logs=''
    cur=$(healsnow "$iss") || cur=''
    while IFS= read -r p; do
      f=$(jq -r .finding <<<"$p") why=$(jq -r .why <<<"$p") e=$(jq -r '.effect // "self-heals"' <<<"$p") entry=''
      if [ -z "$cur" ]; then logs+=$(healslog part '' "$iss" "$f" "$e" "$why" '' false 'its issue could not be read again, is closed or is held now, so it stays in the issue')$'\n'
      elif ! jq -e --argjson c "$cur" "$HEALSPART"'.head as $h | .finding as $f | ($c.body // "" | split("\n")) as $l
          | any(range($l | length); $l[.] == $h and partof($l; .) == $f)' <<<"$p" >/dev/null 2>&1; then
        logs+=$(healslog part '' "$iss" "$f" "$e" "$why" '' false 'it was changed or removed in the issue while the judge read it, so it stays')$'\n'
      elif ! entry=$(healsadd "$(jq -r .from <<<"$p")" "$iss" "$(jq -r '.area // ""' <<<"$p")" "$why" "$f" sort "$e"); then
        logs+=$(healslog part '' "$iss" "$f" "$e" "$why" '' false 'its list could not be written, so it stays in the issue')$'\n'
      else
        logs+=$(healslog part '' "$iss" "$f" "$e" "$why" "$entry" true '')$'\n'; hit+=$(jq -c --arg e "$entry" '{fid, entry: $e}' <<<"$p")$'\n'
      fi
    done < <(printf '%s\n' "$@" | jq -c --argjson i "$iss" 'select(.issue == $i)')
    hit=$(printf '%s' "$hit" | jq -cs .)
    if [ "$hit" = '[]' ]; then ok=false note='no finding of it went to the list, so it was left as it is'
    else
      # How many findings of the body are not on the list: this sort's or an earlier one's.
      left=$(jq -n --argjson c "$cur" --argjson i "$iss" --slurpfile ls <(healslisted) "$HEALSPART$HEALSONE"'($c.body // "" | split("\n")) as $l
        | [range($l | length) | select($l[.] | ispart) | {issue: $i, finding: (partof($l; .) | one)} | select(IN($ls[]) | not)] | length') || left=''
      msg="Conveyor sorted the findings of this issue by what their failure does. The judge sorted these as no harm, so they moved to the self-heals list (self-heals, cleanup and already guarded), which a batch card of their area fixes, or to the docs list (docs drift, an entry that starts with d), which a docs sweep card of their area fixes: $(jq -r 'map("\(.fid) as \(.entry)") | join(", ")' <<<"$hit")."
      if [ "$left" = 0 ]; then
        if healsclose "$iss" "$cur" "$msg Every finding of this issue is on the list or has expired from it now, so it is closed. Its body is left as it was."; then closed=true
        else ok=false note='every finding of it is on the list, but it could not be closed, or it changed as it was closed and was opened again, so its findings stay in it'; fi
      elif ! gh_write issue comment "$iss" --body "$msg Its other findings stay in this issue. Its body is left as it was." >/dev/null 2>&1; then
        ok=false note='the comment that names the entries could not be posted, so its findings stay in it'
      fi
      [ "$ok" = true ] || while IFS= read -r entry; do healsdrop "$entry" || note+=", and entry $entry could not leave its list"; done < <(jq -r '.[].entry' <<<"$hit")
    fi
    # The findings' lines, each that moved given as left in the issue when its issue's comment or close failed.
    printf '%s' "$logs" | jq -c --argjson d "$ok" 'if $d or .entry == null then . else del(.entry) + {done: false, note: "its issue could not be told, so it stays in the issue"} end'
    jq -cn --argjson i "$iss" --argjson h "$hit" --argjson c "$closed" --argjson d "$ok" --arg note "$note" \
      '{issue: $i, moved: (if $d then $h | map(.entry) else [] end), closed: $c, done: $d} + (if $note == "" then {} else {note: $note} end)'
  done
}
# The loop's own sort, in run()'s own variables (turnask(), lib/run.sh, at each turn that would pick, in a `run` and
# a `serve` alike): 0 once HEALSSORT logs a sort. Until then it is 1 and the turn picks nothing, so no follow-up
# queued before the rule is built before the sort has read it. It starts healssort() as a job beside the cards
# (sorter), never counted as one, with no run lock (fd 8), when none runs and none started in the last minute
# (HEALSTRIED, this process's): a sort that could log nothing (the open issues or the holds could not be read) is tried
# again. The owner runs it again by hand.
HEALSTRIED=-1000000
# An entry of the self-heals list that no batch card holds and that was not seen again (healsadd() and healsseen(),
# lib/followups.sh) for rules.healsdays days leaves the list for HEALSDROPPED, with dropped: {time, why: expired}. Its days
# count from its seen, else its time; one with neither (written before the list was dated) is dated now (seen), so it stays
# this run. One a shut batch card gave back (freed, healsfree()) counts its days from the give-back, and expires as the rest
# do; a retry of that card (healstake()) after that takes it back from HEALSDROPPED. The docs list never expires. Both files change under the list's lock, as healsadd()
# takes it: an entry seen again in the meantime stays. A turn that finds the lock held checks nothing and tries at the next. The dropped lines are written before the list is, so a failure
# between the two leaves an entry in both, never in neither. turnask() (lib/run.sh) calls it at each turn, so it says
# on stderr when it could not check the list.
healsexpire() { healsexpiry || { echo "conveyor: the self-heals list could not be checked for expired entries" >&2; return 1; }; }
healsexpiry() {
  local f=$SELFHEALS
  [ -s "$f" ] || return 0
  # Neither the age nor the time is read before the lock is held, so an age saved while this waited is the one used. A
  # list locked by another writer (healsbatch() holds it across its GitHub calls) is left to the next turn: the loop never waits on it.
  ( flock -n 9 || exit 0
    days=$(ctl 2>/dev/null | jq -r '.rules.healsdays // empty') && [ -n "$days" ] && t=$(clock) || exit 1
    q='def lastat: try ((.seen // .time) | fromdateiso8601) catch null; def open: type == "object" and .batched == null;'
    jq -c --arg t "$t" --argjson days "$days" "$q"'select(open and lastat != null and lastat + $days * 86400 <= ($t | fromdateiso8601))
      | . + {dropped: {time: $t, why: "expired"}} | del(.expired)' "$f" > "$f.drop" \
      && jq -c --arg t "$t" --argjson days "$days" "$q"'if open and lastat == null then .seen = $t
        elif open and lastat + $days * 86400 <= ($t | fromdateiso8601) then empty else . end' "$f" > "$f.new" \
      && { [ ! -s "$f.drop" ] || cat "$f.drop" >> "$HEALSDROPPED"; } && { cmp -s "$f" "$f.new" || mv -f "$f.new" "$f"; }
    rc=$?; rm -f "$f.new" "$f.drop"; exit $rc ) 9>>"$f.lock"
}
healsonce() {
  [ ! -s "$HEALSSORT" ] || return 0
  { [ -n "${sorter:-}" ] && jobs -rp | grep -qx "$sorter"; } || [ $((SECONDS - HEALSTRIED)) -lt 60 ] \
    || { HEALSTRIED=$SECONDS; ( healssort ) 8>&- < /dev/null & sorter=$!; }
  return 1
}
# `conveyor.sh heals sort`: the sort of the work filed before the self-heals list existed, by the same rule. The loop
# runs it by itself before its first pick, until HEALSSORT logs one (healsonce()); the command runs it again by hand.
# The queued follow-up cards and the open finding issues (healsitems()) go to the judge in one call (healsjudge()), and
# each is kept or moved by its kind (healsapply()). A judge that fails moves nothing: every item stays, as harm. The
# run's line goes to HEALSSORT, which the Board and the Foreman's status read for when it ran. When the open issues or
# the holds cannot be read, it sorts nothing and logs nothing, so the loop tries again. One sort at a time (a lock of
# its own).
healssort() {
  local fd w t iss j out rc
  { exec {fd}>>"$HEALSSORT.lock"; } 2>/dev/null && flock -n "$fd" || { echo "conveyor: a sort runs already; none started" >&2; return 1; }
  w=$(mktemp -d) || { exec {fd}>&-; return 1; }
  t=$(clock)
  if ! { iss=$(openissues number,title,body,labels,authorAssociation) && jq -e 'type == "array"' <<<"$iss" >/dev/null 2>&1; }; then
    rm -r -f -- "$w"; exec {fd}>&-; echo "conveyor: the open issues could not be read, so nothing was sorted" >&2; return 1
  fi
  printf '%s\n' "$iss" > "$w/issues"; : > "$w/rulings"
  healsitems "$iss" > "$w/items" || { rm -r -f -- "$w"; exec {fd}>&-; echo "conveyor: the held issues could not be read, so nothing was sorted" >&2; return 1; }
  j=null; [ ! -s "$w/items" ] || j=$(healsjudge "$w") || :
  jq -e objects <<<"$j" >/dev/null 2>&1 || j=null
  healsapply "$w"
  out=$(jq -cn --arg t "$t" --arg e "$(clock)" --argjson j "$j" --slurpfile i "$w/log" \
    '{time: $t, ended: $e, judge: ($j | if . == null then null else {model, failed} | del(.[] | nulls) end), items: $i}') \
    && printf '%s\n' "$out" >> "$HEALSSORT"; rc=$?
  rm -r -f -- "$w"; exec {fd}>&-
  [ $rc = 0 ] || { echo "conveyor: the sort ran, but its line could not be written to $HEALSSORT" >&2; return 1; }
  jq -r '"conveyor: sorted \(.items | map(select(.moved == null)) | length) item(s): \(.items | map(select((.effect | IN("self-heals", "cleanup", "already guarded")) and .done)) | length) moved to the self-heals list, \(.items | map(select(.effect == "docs drift" and .done)) | length) to the docs list"
    + (if .judge.failed then "; the judge failed (\(.judge.failed)), so each stays, as harm" else "" end)' <<<"$out"
}
