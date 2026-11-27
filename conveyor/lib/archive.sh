# SPDX-License-Identifier: Apache-2.0
# The archive run: at the start of a loop turn, before the pick (run()), the lines of finished cards whose last line is
# over ARCHIVE_DAYS old leave the live records for the archive (ARCHIVE, archrecs(), lib/records.sh), at most
# ARCHIVE_BATCH cards a run, the oldest last line first. The cards are those of the card records: a card given back by
# `retry` has its lines in the retried file alone, where prior() (lib/issues.sh) finds its kept work for the next
# card of its issue, and they stay there. A finished card is one that landed and was pushed (and, with a GitHub issue,
# whose issue the push closed or checked: its issue line), so the push and its batch rule (pushone(), batchdue(),
# lib/push.sh) still find a landing not pushed yet; with Land as pr, also one whose landed commit origin's default
# branch holds (its pull request merged), so Merge PR idle (idleone()) and the run before its merge (pushtests(),
# lib/pushrun.sh) still find the landings the pull request holds; or one whose last end line (landed, closed,
# blocked) is a closed one: closed, shut, or blocked and then shut. Its lines in the card records go to
# cards-YYYY-MM.jsonl.gz and its lines in the retried file to retried-YYYY-MM.jsonl.gz (the month of its last line),
# each run one gzip member more; a landed card goes to the landed list (LANDEDTSV), and the end lines and test lines
# of a card of the card records to the ended list (ENDED), so the pick, the Tests page's pick and its history,
# umbrellas(), the main-red fix cards, the land-branch command and retry still know it ended.
# The run is due when ARCHLAST is over ARCHEVERY seconds old (or missing), or the last run left cards to move: the
# file holds how many it left. A run with nothing to move changes no file's bytes (ARCHLAST's time alone).
ARCHLAST=$ARCHIVE/last
ARCHEVERY=3600
# The selection, of the card records' text (jq -n -R, each line an input; $off: the landed commits Land as pr has not
# merged yet, one a line): {left, cards: {<card>: <month>}, landed: [the landed list's lines]}. A line that is no
# object with a card stays live.
# shellcheck disable=SC2016 # jq's own variables
ARCHPICK='(now - $days * 86400 | todate) as $cut | ($off | split("\n") | map(select(. != "")) | INDEX(.)) as $off
  | [inputs | fromjson? | objects | select((.card | type) == "string" and (.time | type) == "string")] | group_by(.card)
  | map((map(.time) | max) as $t | select($t < $cut and (if any(.step == "landed") then any(.step == "pushed") and (.[0].issue == 0 or any(.step == "issue"))
          and all(.[] | select(.step == "landed"); $off[.sha | tostring] == null)
        else ([.[] | select(.step | IN("landed", "closed", "blocked"))] | last | .step) == "closed" end))
      | {card: .[0].card, t: $t, l: (map(select(.step == "landed")) | last)}) | sort_by(.t)
  | {left: ([length - $batch, 0] | max), cards: (.[:$batch] | map({key: .card, value: .t[:7]}) | from_entries),
     landed: [.[:$batch][] | .l | objects | "\(.card)\t\(.issue)\t\(.sha)\t\(.time)"]}'
# The lines of a moved card that the ended list keeps (ENDED, lib/records.sh): what its readers ask of an ended card,
# whole; and its test, bugproof and review lines as the Tests page reads them (TESTLINE, lib/testfiles.sh), so its
# test runs stay in the page's history (testlines()).
ENDSEL='(.step | IN("picked", "landed", "pushed", "closed", "blocked", "split")) or .followups != null or .grown != null'
ENDTEST='select(.step | IN("test", "bugproof", "review"))'
# Each line of a records file as `<month>\t<line>` when its card moves ($m: the selection's cards), else `-\t<line>`.
# shellcheck disable=SC2016 # jq's own variables
ARCHTAG='. as $l | ((fromjson? | objects | .card | strings) as $c | $m[0][$c]) // "-" | "\(.)\t\($l)"'
# The tagged lines of <file> into <folder>/<tag>: one file a month moved, and `-` for those kept.
archsplit() { # <file> <map> <folder>
  mkdir -p "$3" && : > "$3/-" && jq -rR --slurpfile m "$2" "$ARCHTAG" "$1" | LC_ALL=C awk -F'\t' -v d="$3" '{ t = $1; sub(/^[^\t]*\t/, ""); print > (d "/" t) }'
}
# The whole lines of <file> (none when it is missing) into <to>.
archwhole() { # <file> <to>
  if [ -e "$1" ]; then head -n "$(wc -l < "$1")" "$1" > "$2"; else : > "$2"; fi
}
archiverun() {
  [ ! -e "$ARCHLAST" ] || ! p_newer "$ARCHLAST" "$ARCHEVERY" || [ "$(cat "$ARCHLAST" 2>/dev/null)" != 0 ] || return 0
  local d k size ino off sum left b=''
  mkdir -p "$ARCHIVE" && d=$(mktemp -d) || return 0
  # The records' whole lines as they are now, read outside the lock: what the run moves is chosen from them. With Land
  # as pr (or Land as unread), the landed commits origin's default branch does not hold, as the last fetch of it
  # (prfetch(), lib/push.sh) has it; every landed commit when no fetch is kept.
  k=$(p_filekey "$STATE") && read -r size _ _ ino _ <<<"$k" && head -c "$size" "$STATE" > "$d/part" \
    && head -n "$(wc -l < "$d/part")" "$d/part" > "$d/read" && off=$(($(wc -c < "$d/read"))) \
    && sum=$(tail -c 4096 "$d/read" | cksum) && : > "$d/off" \
    && if [ "$(landas 2>/dev/null || echo pr)" = pr ]; then
      b=$(git rev-parse -q --verify "refs/remotes/${REMOTE-}/${BRANCH-}^{commit}") || b=''
      jq -rR 'fromjson? | objects | select(.step == "landed") | .sha | strings' "$d/read" | if [ -n "$b" ]; then offmain "$b"; else cat; fi > "$d/off"
    fi \
    && jq -cnR --argjson days "$ARCHIVE_DAYS" --argjson batch "$ARCHIVE_BATCH" --rawfile off "$d/off" "$ARCHPICK" < "$d/read" > "$d/pick" \
    && left=$(jq -r '.left' "$d/pick") || { echo "conveyor: the archive run could not read the card records; nothing moved" >&2; rm -rf "$d"; return 0; }
  if jq -e '.cards == {}' "$d/pick" > /dev/null; then
    if [ "$(cat "$ARCHLAST" 2>/dev/null)" = 0 ]; then touch "$ARCHLAST"; else echo 0 > "$ARCHLAST"; fi
    rm -rf "$d"; return 0
  fi
  lockedfor "the archive run" archwrite "$d" "$ino" "$off" "$sum"
  case $? in
    0) echo "$left" > "$ARCHLAST" ;;
    # Rewritten since the read (a retry, a line set aside): nothing moved, and the next turn runs again.
    3) echo "conveyor: the card records were rewritten while the archive run read them; nothing moved, and the next turn runs it again" >&2; echo 1 > "$ARCHLAST" ;;
    *) echo "conveyor: the archive run failed; the next turn runs it again" >&2; echo 1 > "$ARCHLAST" ;;
  esac
  rm -rf "$d"; return 0
}
# Under the records' lock. 3 when the records were rewritten since the read: another inode, shorter than the part
# read, or the last 4 KB before its end changed. The lines appended since stay live, after the kept ones. The archive
# is written first: a run stopped before the rewrite leaves the lines in both, never in neither. The archive, the
# landed and ended lists and both files change under the lock a snapshot's copy takes (snapcopy(), lib/snapshot.sh),
# as moveout() changes them: the copy, and the archive files' sizes it notes, are of one time, before the move or
# after it, so the snapshot never counts a card in both or in neither.
archwrite() { # <scratch folder> <inode read> <bytes read> <cksum of the last 4 KB of them>
  local d=$1 k size ino from=1 n=$3 m f
  k=$(p_filekey "$STATE") && read -r size _ _ ino _ <<<"$k" || return 1
  [ "$3" -le 4096 ] || { from=$(($3 - 4095)); n=4096; }
  [ "$ino" = "$2" ] && [ "$size" -ge "$3" ] && [ "$(tail -c +"$from" "$STATE" | head -c "$n" | cksum)" = "$4" ] || return 3
  jq -c '.cards' "$d/pick" > "$d/map" && archsplit "$d/read" "$d/map" "$d/c" && tail -c +$(($3 + 1)) "$STATE" >> "$d/c/-" \
    && archwhole "$RETRIED" "$d/old" && archsplit "$d/old" "$d/map" "$d/r" || return 1
  : > "$d/ended" || return 1
  for f in "$d"/c/[0-9]*; do [ ! -e "$f" ] || jq -cR "(fromjson? | objects | select($ENDSEL)) // ($TESTLINE | $ENDTEST)" "$f" >> "$d/ended" || return 1; done
  ( flock 5 || exit 1
    for f in "$d"/c/[0-9]* "$d"/r/[0-9]*; do
      [ -e "$f" ] || continue; m=${f##*/}
      gzip -c < "$f" >> "$ARCHIVE/$([ "${f%/*}" = "$d/c" ] && echo cards || echo retried)-$m.jsonl.gz" || exit 1
    done
    jq -r '.landed[]' "$d/pick" >> "$LANDEDTSV" && { [ ! -s "$d/ended" ] || cat -- "$d/ended" >> "$ENDED"; } || exit 1
    stdb rewrite retried < "$d/r/-" && stdb rewrite cards < "$d/c/-" || exit 1
    # The summaries kept of the records are made anew from them by their next reader, and the links of snapshots
    # that ended are removed (the copy of one still running is its own).
    rm -f -- "$STATE".{rows,cardruns,priced,health,tests,driftlines,driftin,drift,judged}* "$RETRIED".{rows,health,tests,judged}* \
      "$STATE.copy" "$STATE.copy".{at,counts,checked} "$STATE.rest"
    for f in "$STATE.copy".r*; do
      m=${f##*.r}; m=${m%.kept}; [[ $m =~ ^[0-9]+$ ]] && ! kill -0 "$m" 2>/dev/null && rm -f -- "$f"
    done; exit 0 ) 5>>"$STATE.checked.lock" || return 1
  stdb vacuum || echo "conveyor: the archive run could not vacuum state.db" >&2
  echo "conveyor: the archive run moved $(jq '.cards | length' "$d/pick") finished cards' lines to $ARCHIVE"
}
