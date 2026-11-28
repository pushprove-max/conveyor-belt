# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh snapshot [--fresh]`: the snapshot the Board reads (snapshot(), lib/snapshot.sh), sourced by conveyor.sh.
# A reader prints the kept snapshot (KEPT, <state>/snapshot.json) at once and builds nothing. Its first three fields are
# snapshotAt (when the build that made it began, UTC), snapshotAge (its age in seconds as it is printed) and
# recordsNewer (the card records changed after that build began: snapprint). The Board,
# /units and every watcher read the snapshot again and again: each built its own, and on a long history one build took
# a minute, with 12 to 35 of them running at once, so no reader got one before it stopped waiting.
# When an input changed after that build began (a record line, the retried lines, the control record, the files the
# stream watches beside them (watch.py STATE_FILES), a card's live record or a proof run's, a card begun or ended, the
# issues list the stream keeps or the loop's, ISSUES, the test map or its run's progress (watch.py MAP_FILES):
# snapinputs) or the kept snapshot is SNAPOLD seconds old
# (what counts on the clock alone, and an issues list asked of GitHub), the reader starts the writer in the background.
# The writer is one process a project (it holds KEPT.lock while it builds; a second one finds it held and ends): it
# builds, writes the new snapshot beside KEPT, dates it when its build began and renames it into place, so a reader
# never reads half a file; then it builds again while an input changed meanwhile, at most once every SNAPGAP seconds.
# A writer started on the clock alone builds nothing while the kept snapshot is still what a build would make
# (snapsame): it dates KEPT when it looked, so snapshotAt and snapshotAge then count from that look.
# With no kept snapshot yet, and with --fresh (a caller that needs the view after its own change, as a test does, or
# after a change no input shows: the stream's loop process ending), the snapshot is built here, under the same lock,
# kept and printed. A call that waited for the lock prints the build another call began after this one asked (its
# asked marker still there: a build that took its pid for gone removed it), and makes none of its own: the calls that
# came while one build ran make one build between them, after it. One never prints a build that began before it
# asked: that build can have read the records before the change its caller made (#1101).
# A build with no `watch` feed (GITHUB unset) reads GitHub's answers, and the Claude usage readings the guard reads,
# from SNAPGH, asked (github(), lib/issues.sh; guardread()) before the lock is taken: a slow GitHub then never holds
# the lock, and with it every other writer (the stream's, which has its own GitHub folder), until it answers. One
# call asks at a time (SNAPGH.lock), and a call asks nothing when another one asked after it began (--fresh) or after
# the kept snapshot's build began (the writer): two calls for one rebuild ask GitHub once.
KEPT=$ST/snapshot.json SNAPOLD=30 SNAPGAP=5 SNAPIDLE=300 SNAPGH=$ST/snapgh KEPTREAD=$ST/snapshot.json.records
# The Foreman's notes on blocked cards (snapprint); NOTELEASE is the same as commands/foreman-note.sh's.
NOTES=$ST/foreman-notes NOTELEASE=300
SNAPLIBS='slots prompts control views snapshot issues pick testrun push flaky fulltest testaction testfiles testrules lane run machine install setup'
case ${2-} in
  '') fresh='' ;;
  --fresh) fresh=1 ;;
  *) echo "usage: conveyor.sh snapshot [--fresh]" >&2; exit 2 ;;
esac
# Whether an input of the kept snapshot changed after its build began (KEPT's time is when that build began). The map's
# folder (M) counts by its own time as well as by its map files': a run's progress file that is removed (mapend(), as
# `testmap stop` ends a build) is newer than nothing, but its removal dates the folder.
snapinputs() {
  local M=$MAIN/.conveyor
  local f=("$STATE" "$RETRIED" "$CONTROL" "$ST/pushed" "$ST/limit.jsonl" "$ST/maintest.json" "$ST/loop.json" "$ISSUES" "$CARDS" "$CARDS/mainrun" "$M")
  [ -z "$GITHUB" ] || f+=("$GITHUB/issues")
  [ -n "$(find "${f[@]}" -maxdepth 1 \( ! -path "$CARDS/*" ! -path "$M/*" -o -path "$CARDS/mainrun" -o -name '*.live' \
    -o -path "$M/test-map.json" -o -path "$M/test-map.run.json" \) -newer "$KEPT" -print -quit 2>/dev/null)" ]
}
snapdue() { snapinputs || ! p_newer "$KEPT" "$SNAPOLD"; }
# GitHub's answers the next build reads (the feed's, or SNAPGH as snapask() asked them), as one sum. KEPT.gh holds the
# kept snapshot's (snapkeep takes it before the build reads them) and is dated when that build ended.
snapghsum() { cat "${GITHUB:-$SNAPGH}"/* 2>/dev/null | cksum; }
# Whether the kept snapshot, due on the clock alone, is still what a build would make: GitHub answered the same as for
# its build, no card runs (loop.json's cards; no loop.json: none runs here) and its build ended under SNAPIDLE seconds
# ago. Every other input is a file (snapinputs), and only a running card's times move much with the clock. A paused
# belt was built again every 30 s, up to 10 s of a core each on a long history (148 CPU s in 10 minutes, 2026-11-27).
# Not when a --fresh call waits (its asked marker): it gets a build. Not when the plugin-bugs.md the build read
# (KEPT.notes) changed after it: snapprint then leaves its notes out, and a newer KEPT would put them back.
snapsame() {
  local pf
  p_newer "$KEPT.gh" "$SNAPIDLE" && [ "$(snapghsum)" = "$(cat "$KEPT.gh" 2>/dev/null)" ] && ! compgen -G "$KEPT.*.asked" > /dev/null \
    && { ! { read -r pf < "$KEPT.notes"; } 2>/dev/null || [ -z "$pf" ] || [ ! "$pf" -nt "$KEPT" ]; } \
    && { [ ! -e "$ST/loop.json" ] || [ "$(jq -r '(.cards // []) | length' "$ST/loop.json" 2>/dev/null)" = 0 ]; }
}
# GitHub's answers and the guard's usage readings for the next build, asked outside the build lock into SNAPGH, when
# there is no `watch` feed: the build then reads them as a feed's (GITHUB set), and reading() asks nothing in it.
# SNAPGH/at is dated when the last asking began. <since> is a file: when the last asking began after it was dated,
# those answers serve and nothing is asked. The lock is waited for, or with nowait not: a call that finds another asking returns 3.
snapask() { # <since> [nowait]
  [ -z "$GITHUB" ] || return 0
  [ -d "$SNAPGH" ] || mkdir -p "$SNAPGH" || return 1
  # The control record read in this shell, not only in the subshell below: the build after it finds it kept
  # (ctlread's CTL_K), and does not check it again with a jq of its own (t_snapexec).
  local CTL_V; ctlread 2>/dev/null || :
  ( if [ -n "${2-}" ]; then flock -n 9 || exit 3; else flock -w 600 9 || { echo "conveyor: another call asked GitHub for 600 s" >&2; exit 1; }; fi
    [ ! "$SNAPGH/at" -nt "$1" ] || exit 0
    # What github() keeps (lib/issues.sh), but the label times (labelled) only when an open issue names the label
    # (BUILT): the snapshot reads them only then, and each question is a program or more a build (t_snapexec).
    local i; : > "$SNAPGH/at" || exit 1
    if i=$(openissues "$FIELDS" 2>/dev/null); then printf '%s\n' "$i" > "$SNAPGH/issues.new" && mv -f "$SNAPGH/issues.new" "$SNAPGH/issues"
    else rm -f "$SNAPGH/issues"; fi
    queuedfarkeep "$SNAPGH" # the other repositories' issues the waiting cards with no GitHub issue name
    [[ $i != *"\"$BUILT\""* ]] || { labelled > "$SNAPGH/labelled.new" && mv -f "$SNAPGH/labelled.new" "$SNAPGH/labelled"; }
    local g=false r=false; ! ghok || g=true
    # Whether GitHub answers too (health's ghReached): the build reads SNAPGH as a feed, and a feed with no ghreach
    # reads as GitHub not reached. Health reads it only when signed in, so it is asked only then.
    [ "$g" = false ] || ! ghreach || r=true
    printf '%s\n' "$GHWHY" > "$SNAPGH/ghwhy.new" && mv -f "$SNAPGH/ghwhy.new" "$SNAPGH/ghwhy"
    echo "$g" > "$SNAPGH/gh.new" && mv -f "$SNAPGH/gh.new" "$SNAPGH/gh"
    echo "$r" > "$SNAPGH/ghreach.new" && mv -f "$SNAPGH/ghreach.new" "$SNAPGH/ghreach"
    hostclis due >/dev/null 2>&1 || :
    local c CTL_V; if ctlread 2>/dev/null; then c=$CTL_V; else c=null; fi
    [ "$(jq -r .guard <<<"$c" 2>/dev/null)" = null ] || guardread "$c" ask > /dev/null 2>&1 || :
  ) 9>>"$SNAPGH.lock"
}
# One build (under the lock), put in place by a rename and dated when it began (KEPT.at, kept: one build at a time
# dates it, and a file removed is one program more each build, t_snapexec); GitHub as snapask() asked it.
# The asked marker of a --fresh call whose process is gone is removed first: a call killed at its caller's time limit
# (watch.py SNAPSHOT_LIMIT) left its marker, and nothing else removes it. kill -0 is a builtin, so a build with no
# such marker runs no program more. It also fails for a pid it may not signal (another user's): that call, with its
# marker gone, builds its own after this one.
# KEPT.notes names the Foreman's plugin-bugs.md the build read its priceNotes from (SNAPNOTES, snapshot()), written in
# place as the build reads it (no program more): snapprint leaves those notes out once that file is newer than KEPT.
# KEPTREAD holds how many lines each card had in the copy of the card records the kept snapshot's build took
# (`<count>\t<card>`, one card a line: snapcopy keeps them with its copy, so a build never reads the whole records to
# count them), put in place after the rename and dated then, so it is newer than the snapshot it goes with
# (recordsnow reads it): a card's line past its count came after that build's copy, whatever time it was stamped with.
# A line that waited for the records' lock was stamped before the build began and appended after the build copied the
# records, so its time alone left it out of both. Counts, not the records' size: a rewrite (retry or stop, moveout();
# quarantine(), lib/views.sh) takes lines out before a line appended late, which a size then put before it, and
# retry and stop take out every line of a card, so each other card's lines keep their count. quarantine() sets one
# line of a card aside and keeps its others: when it was counted (the build's own check sets aside a bad line the count
# took), that card's count is over its lines, and as many of its next lines are read only by their time.
snapkeep() {
  local n=$KEPT.$BASHPID rc GITHUB=${GITHUB:-$SNAPGH} a p c=$KEPTREAD.$BASHPID g
  for a in "$KEPT".*.asked; do
    p=${a#"$KEPT".}; p=${p%.asked}
    [[ $p =~ ^[0-9]+$ ]] && ! kill -0 "$p" 2>/dev/null && rm -f -- "$a"
  done
  g=$(snapghsum)
  : > "$KEPT.at" && SNAPCOUNTS=$c SNAPNOTES=$KEPT.notes snapshot > "$n" && [ -s "$n" ] && touch -r "$KEPT.at" "$n" && mv -f "$n" "$KEPT"; rc=$?
  # A count that could not be taken leaves the last one, now older than the kept snapshot: recordsnow takes none.
  [ "$rc" != 0 ] || printf '%s\n' "$g" > "$KEPT.gh" || :
  if [ "$rc" = 0 ]; then [ ! -e "$c" ] || { mv -f "$c" "$KEPTREAD" && touch "$KEPTREAD"; } 2>/dev/null || :; else rm -f "$n" "$c"; fi
  return "$rc"
}
# The background writer (libraries sourced): it builds while the kept snapshot is due, then while an input changed,
# asking GitHub before it takes the lock for each build, unless a call asked after the kept snapshot's build began
# (that call's build is still to come) or one is asking now (it builds next: this writer ends). A build begins SNAPGAP
# seconds after the last one began at the soonest (KEPT is dated when that began), whichever writer made it.
snapwriter() {
  local due=snapdue rc
  while $due; do
    snapask "$KEPT" nowait || break
    ( flock -n 9 || exit 3
      $due || exit 0
      # Still current (snapsame): KEPT and KEPT.at are dated when the look began (KEPT.checked), not built, so an input
      # that changes after the look is newer than KEPT. KEPTREAD, when it was the kept build's, is dated after them.
      # Exit 4: the writer ends.
      if [ "$due" = snapdue ]; then
        r=; [ ! "$KEPTREAD" -nt "$KEPT" ] || r=1; : > "$KEPT.checked" || exit 1
        ! snapinputs && snapsame && touch -r "$KEPT.checked" "$KEPT.at" "$KEPT" && { [ -z "$r" ] || touch "$KEPTREAD"; exit 4; }
      fi
      s=$(($(p_mtimes "$KEPT" | cut -d' ' -f1) + SNAPGAP - $(date +%s))); [ "$s" -le 0 ] || sleep "$s"
      snapkeep ) 9>>"$KEPT.lock"; rc=$?
    # Another writer holds the lock (it builds again for a change after its own build began), or the build failed.
    [ "$rc" = 0 ] || break
    due=snapinputs
  done
}
# The kept snapshot as a reader gets it: snapshotAt and snapshotAge (to the millisecond: the stream dates what a
# snapshot read by it, watch.py) first, then recordsNewer, then the snapshot's own fields. recordsNewer is true when
# the card records or the retried file changed after its build began: its belt can leave out a card begun since. A
# retry rewrites the records, so the next build reads them whole and can take minutes (#1032: the Foreman's watcher
# read the snapshot from before the retry, with the belt empty, and woke the Foreman with "Conveyor is idle").
# While recordsNewer is true, or loop.json changed after that build began (its counts are newer than the snapshot's),
# recordsNow (recordsnow) follows it, and each card of its started is added to the belt (its issue taken out of
# queue.next, queue.order and queue.waiting).
# KEPTREAD (snapkeep) is taken only when it is newer than the kept snapshot: an older one is an older build's. A newer
# build that replaces both after this test puts its snapshot in place first, and the snapshot is read here last: its
# counts go with the snapshot printed, and an older snapshotAt only reads lines again (recordsnow lists a card once).
# A card's count can fall from one build to the next (quarantine(), lib/views.sh, sets one line of a card aside and
# keeps its others), so the older counts with the newer snapshotAt can leave out a line of that card that only its
# count would read.
snapprint() {
  local k s m now newer=false at rn='' r='' off=''
  [ "$KEPTREAD" -nt "$KEPT" ] && off=$KEPTREAD
  k=$(p_filekey "$KEPT") && k=${k#* } && [[ $k =~ ^([0-9]+)[.,]([0-9]{3}) ]] || { echo "conveyor: cannot read $KEPT" >&2; return 1; }
  s=${BASH_REMATCH[1]} m=$((BASH_REMATCH[1] * 1000 + 10#${BASH_REMATCH[2]}))
  at=$(export TZ=UTC; printf '%(%Y-%m-%dT%H:%M:%SZ)T' "$s")
  # The shell's own test of the times (to the nanosecond, as find -newer): no program on each read.
  { [ "$STATE" -nt "$KEPT" ] || [ "$RETRIED" -nt "$KEPT" ]; } && newer=true
  # The Foreman's notes on blocked cards (NOTES, commands/foreman-note.sh) are read at each print, not by the build:
  # they end when the Foreman's watcher stops renewing them (its session gone), which changes no input of the build.
  # While renewed at most NOTELEASE seconds ago, a blocked card with a note gets it as foreman {note, ask, since}: one
  # of recordsNow's blocked (a card blocked after the build began, which then joins needsYou.blocked too) and one of
  # the kept needsYou.blocked (below), but
  # not the push item, and only when the card was blocked before the note was written (a card blocked again since has
  # a note of an earlier block). One program more, only while there are notes. The notes go to jq as a file: as an
  # argument, a long line is more than the system lets one argument be.
  local ns='' nt='' nj='' nf='' rr
  { { read -r ns nt; IFS= read -r nj; } < "$NOTES"; } 2>/dev/null && [ -n "$ns" ] && [[ $nt =~ ^[0-9]+$ ]] && [ $((EPOCHSECONDS - nt)) -le "$NOTELEASE" ] \
    && nf='(($fn | try fromjson catch null | objects) // {}) as $fn
      | def noted($held): map(if .push != true and (.card | type) == "string" and ($fn[.card] | type) == "object"
          and ($held == null or (.card | IN($held[]))) and (($fn[.card].since | strings) // "") >= ((.since | strings) // "")
        then . + {foreman: ($fn[.card] | {note: ((.note | strings) // ""), ask: (.ask == true), since: ((.since | strings) // null)})} else . end);'
  if [ "$newer" = true ] || [ "$SAYS" -nt "$KEPT" ]; then
    r=$(recordsnow "$at" "$off" 2>/dev/null) && [ -n "$r" ] || r=null
    [ -z "$nf" ] || [[ $r != '{'* ]] || ! rr=$(jq -c --rawfile fn <(printf '%s' "$nj") "$nf"' if (.blocked | type) == "array" then .blocked |= noted(null) else . end' <<<"$r") || r=$rr
    rn="\"recordsNow\":$r,"
  fi
  now=${EPOCHREALTIME/[.,]/}; now=$((10#$now / 1000)); m=$((now > m ? now - m : 0))
  printf '{"snapshotAt":"%s","snapshotAge":%d.%03d,"recordsNewer":%s,%s' "$at" $((m / 1000)) $((m % 1000)) "$newer" "$rn"
  # A card started since joins the belt (recordsNow's started) and its issue leaves the queue's lists, so it is not
  # shown in Queue and on the belt at once. Its issue leaves the held issues (open.held), and the count of the split it
  # was held in goes to the belt's (open.split, the Board's held total), as a build lists no issue on the belt as held.
  # A card of its issue in Needs you (needsYou waiting and blocked, but for the push item, which names a landing not
  # pushed) leaves it when the records now hold it neither blocked nor waiting (recordsNow): retry took its lines out.
  # One the records still hold stays: a land-branch card can start beside a blocked card of its issue (pickbranch(),
  # lib/lane.sh). #1633: a retried issue building read "card blocked: retry" in the Foreman's status and stayed in
  # Needs you until the next build. The kept priceNotes are left out
  # ([]) when the plugin-bugs.md they were read from (KEPT.notes) changed after the build began: stop.sh can have
  # marked one filed, or the Board's File or Dismiss taken it out, and a Board on another machine would add it to its own notes again. The next build gives
  # them as the file holds them then. With no KEPT.notes (a kept snapshot an older engine built, or one whose file
  # could not be written), what they were read from is not known, so they are left out as for a changed file. One
  # program more, only while there is one of the two.
  local jf='.' pf=''
  if { read -r pf < "$KEPT.notes"; } 2>/dev/null; then [ -z "$pf" ] || [ ! "$pf" -nt "$KEPT" ] || jf='.priceNotes = []'
  else jf='.priceNotes = []'; fi
  # The Foreman's notes on blocked cards (NOTES, commands/foreman-note.sh), from nf above: a card of the kept
  # needsYou.blocked gets its note while the records still hold it blocked (recordsNow's blocked, when the records are
  # newer than the build: a retry took its lines out). A card of recordsNow's blocked with a note (blocked after the
  # build began) joins needsYou.blocked, fromRecords true as on the Board: /units and the Board's Needs you column read
  # only needsYou, so its note would else show nowhere but in Overview until the next build.
  [ -z "$nf" ] || jf+=" | $nf"' (if ($r | type) == "object" and ($r.blocked | type) == "array" then [$r.blocked[].card] else null end) as $held
      | (.needsYou | objects | .blocked | arrays) |= noted($held)
      | if $held != null and (.needsYou | type) == "object" and (.needsYou.blocked | type) == "array"
        then [.needsYou.blocked[].card] as $kb | .needsYou.blocked += [$r.blocked[] | select(.foreman != null and (.card | IN($kb[]) | not)) | . + {fromRecords: true}]
        else . end'
  [[ $r != *'"started":[{'* ]] || jf+=' | [$r.started[].issue | numbers | select(. > 0)] as $n
      | .belt = (.belt // []) + $r.started
      | (.queue | objects | (.next, .order, .waiting) | arrays) |= map(select((.issue | IN($n[])) | not))
      | (.open | objects | select(.held | type == "array")) |= ([.held[] | select(.issue | IN($n[]))] as $g
          | .held -= $g
          | ($g | map(select((.reasons | map(.kind) | unique) == ["you"])) | length) as $you
          | ($g | map(select(any(.reasons[]; .notPushed == true))) | length) as $np
          | if (.split | type) == "object" then .split |= (.you -= $you | .landed -= $np | .labelOrRule -= (($g | length) - $you - $np) | .belt += ($g | length)) else . end)
      | ([$r.blocked, $r.waiting | arrays | .[].card | strings]) as $now
      | (.needsYou | objects | (.waiting, .blocked) | arrays) |= map(select(.push == true or (.issue | IN($n[]) | not) or (.card | IN($now[]))))'
  # recordsNow goes by file too: with the notes on its blocked cards, it can be more than one argument may be.
  if [ "$jf" != . ]; then jq -c --slurpfile rs <(printf '%s' "${r:-null}") --rawfile fn <(printf '%s' "$nj") '$rs[0] as $r | '"$jf" "$KEPT" | tail -c +2
  else tail -c +2 "$KEPT"; fi
}
# What the card records and loop.json say now, which stay current while a new build takes minutes: the kept snapshot
# can show nothing blocked and nothing building while cards block and build (#1101). One object: blocked, each card
# the records hold blocked now, as {card, issue, name, title, reason, since} (title: the belt's, else its picked line's): the kept snapshot's health blocked and waiting,
# but for a card with a closing line since <snapshotAt> or with no line left (retried), and each card whose last
# closing line (landed, closed, blocked or pushed) since then is blocked; of those, a card stopped for the owner's yes
# (its reason starts with YES or LINTYES, yesforms() with the pack's owner.name: block(), lib/card.sh) is in waiting
# instead, as views.sh splits health's, with its sentence: the reason after that start; building, waitingCount and
# running, the running loop's count at its last turn (loop.json, run(): running is every card of it in progress, in
# review and in its Test step too), and each card in progress (on the kept belt and not landed, or in started) that
# loop.json's cards do not name, picked at or after loop.json's last write (turncount() writes it before the turn's
# pick, and again only when it changes), null when no process of that loop lives, and left out when there is no
# loop.json (the loop does not run on this machine, so there is no count of it here to read); landed, the
# count of landed cards on the belt for their push, which no loop count holds: those the kept snapshot's belt has
# landed with no closing line since, and, unless the rule "Push when a card lands" is off, each card whose last
# closing line since is landed (a card pushed since leaves it, though the belt keeps it until its issue closes), but
# for one loop.json's cards still name, in either list: running counts it until the loop's next turn; started,
# each card picked since that the kept belt does not hold, with no closing line since and still in the records, as a
# belt card {card, issue, name, title, step (from its last step line, as rows.jq names it, roughly), stepAt, landed
# false, fromRecords true: it is in no full build yet, so it has no track, model or cost}; lines, each card with a line
# since (one the kept snapshot names stuck has moved on: the Foreman's watcher, recheck()). Nothing is
# printed when the pack names no owner. A line since is one stamped at <snapshotAt> or later, or a card's line past
# that card's count in <counts> (KEPTREAD, snapkeep): a line stamped before the build began that waited for the
# records' lock is appended after the build copied them. A line the snapshot may hold (of the second the build began,
# or appended before its copy) is read again: a card is listed once. Counts that cannot be read are taken as none
# given: only the times count. The rule "Push when a card lands" is the control record's now (as ctlread() reads it,
# lib/control.sh: its defaults under it, null when it does not read), not the kept snapshot's: a card that lands after
# the owner turned the rule on is counted.
# Only the lines since are read whole: a line's first "time" field is its own (line(), lib/records.sh).
recordsnow() { # <snapshotAt> [<counts>]
  local p at b=null YES LINTYES o c=/dev/null here=true
  [ ! -s "$CONTROL" ] || c=$CONTROL
  [ -e "$SAYS" ] || here=false
  o=$(jq -er '.owner.name | strings' "$MAIN/.conveyor/project.json" 2>/dev/null) || return 1
  yesforms "$o"
  p=$(jq -r '.pid | numbers' "$SAYS" 2>/dev/null) && [ -n "$p" ] && kill -0 "$p" 2>/dev/null && at=$(p_stat "$SAYS") \
    && b=$(jq -c --argjson at "${at#* }" '{building: (.building | numbers), waiting: (.waiting | numbers), running: (.running | numbers), cards: [.cards | arrays | .[] | strings], at: $at}' "$SAYS" 2>/dev/null) \
    && [ -n "$b" ] || b=null
  LC_ALL=C awk -v t="\"time\":\"$1\"" -v f="${2:-}" 'BEGIN { if (f != "") { while ((r = (getline l < f)) > 0) { j = index(l, "\t"); k[substr(l, j + 1)] = substr(l, 1, j - 1) + 0 }; if (r < 0) f = "" } }
    { c = ""; if (f != "" && match($0, /^\{"card":"[^"]*"/)) { c = substr($0, 10, RLENGTH - 10); s[c]++ }
      i = index($0, "\"time\":\""); if ((c != "" && s[c] > k[c]) || (i && substr($0, i, length(t)) >= t)) print }' "$STATE" \
    | jq -cnR --slurpfile k "$KEPT" --argjson loop "$b" --argjson here "$here" --arg yes "$YES" --arg lintyes "$LINTYES" --rawfile ids <(LC_ALL=C grep -o '^{"card":"[^"]*"' "$STATE") \
      --rawfile ctl "$c" --slurpfile d "$HERE/lib/control-defaults.json" '
      ($ids | split("\n") | map(select(. != "") | .[9:-1]) | INDEX(.)) as $have
      | [inputs | fromjson? | objects | select((.card | type) == "string" and (.time | type) == "string")] as $new
      | $k[0] as $s
      | ([if $ctl == "" then $d[0] else ($ctl | fromjson? | objects | $d[0] * .) end | .rules | objects | .push] | first) as $push
      # A main-red fix card or a Tests page card has no issue: its name, as the belt has it, or as its picked line gives it (views.sh).
      | ([$s.belt | arrays | .[] | objects | select((.card | type) == "string" and (.name | type) == "string") | {key: .card, value: .name}]
         + [$new[] | select(.step == "picked" and (.mainRed | type) == "string") | {key: .card, value: "Main is red (\(.mainRed[0:12]))"}]
         + [$new[] | select(.step == "picked" and ((.testFile | type) == "string" or (.noIssue | type) == "string")) | {key: .card, value: (if (.testFile | type) == "string" then "Tests page: \(.testFile)" else .noIssue end)}] | from_entries) as $names
      # Its title, as the belt has it, or as its picked line gives it: a card picked since has no line on the belt.
      | ([$s.belt | arrays | .[] | objects | select((.card | type) == "string" and (.title | type) == "string") | {key: .card, value: .title}]
         + [$new[] | select(.step == "picked" and (.title | type) == "string") | {key: .card, value: .title}] | from_entries) as $titles
      | ($new | map(select(.step | IN("landed", "closed", "blocked", "pushed"))) | group_by(.card) | map(last)) as $ends
      | ($ends | INDEX(.card)) as $ended
      | ([$s.health | objects | (.blocked, .waiting) | arrays | .[] | objects | select((.card | type) == "string")
            | select($have[.card] != null and $ended[.card] == null) | {card, issue, name: (.name // $names[.card]), title: $titles[.card], reason, since}]
          + [$ends[] | select(.step == "blocked") | {card, issue, name: $names[.card], title: $titles[.card], reason, since: .time}]) as $all
      | def yes: (.reason | type) == "string" and (.reason | startswith($yes) or startswith($lintyes));
        {blocked: [$all[] | select(yes | not)], waiting: [$all[] | select(yes) | . + {sentence: (.reason | if startswith($lintyes) then ltrimstr($lintyes) else ltrimstr($yes) end)}],
         building: $loop.building, waitingCount: $loop.waiting, running: $loop.running,
         landed: ([$s.belt | arrays | .[] | objects | select(.landed == true and (.card | type) == "string" and $have[.card] != null and $ended[.card] == null) | .card]
           + (if $push == false then [] else [$ends[] | select(.step == "landed") | .card] end)
           | map(select(IN($loop.cards // [] | .[]) | not)) | unique | length),
         started: (([$s.belt | arrays | .[] | objects | .card | strings] | INDEX(.)) as $onbelt
           | [$new | group_by(.card)[] | select(any(.step == "picked") and $have[.[0].card] != null and $onbelt[.[0].card] == null and $ended[.[0].card] == null)
             | (map(select(.step | IN("brief", "build", "fix", "rebase", "review", "test"))) | last) as $l
             | {card: .[0].card, issue: (map(select(.step == "picked")) | last | .issue), name: $names[.[0].card], title: $titles[.[0].card],
                step: (if $l == null then "brief" elif $l.step == "brief" then "build" elif $l.step | IN("build", "fix", "rebase") then "review"
                  elif $l.step == "test" then (if $l.result == "fail" then "fix" else "landing" end)
                  elif $l.result == "GO" then "tests" elif $l.result == "NO-GO" then "fix" else "review" end),
                stepAt: last.time, landed: false, fromRecords: true}]),
         lines: ([$new[].card] | unique)}
      # loop.json is written before its turn picks, and again only when it changes: a card in progress that its cards
      # do not name, picked at or after its last write (its mtime, at), is in progress too, on the kept belt or started.
      | if (.running | type) == "number" then .running += ([
          ([$s.belt | arrays | .[] | objects | select(.landed != true and (.card | type) == "string" and $have[.card] != null and $ended[.card] == null) | {card, t: .pickedAt}]
            + [.started[] | .card as $c | {card: $c, t: ([$new[] | select(.card == $c and .step == "picked") | .time] | last)}])
          | unique_by(.card)[] | select((.card | IN($loop.cards[]) | not) and ((.t | fromdate?) // 0) >= $loop.at)] | length) else . end
      # With no loop.json the loop does not run on this machine: its counts are not here to read, so none is given.
      | if $here then . else del(.building, .waitingCount, .running) end'
}
if [ -z "$fresh" ] && [ -s "$KEPT" ]; then
  if snapdue; then
    # None of the reader's descriptors stays open in the writer (the engine's own stderr, LOGFD, too): a reader that
    # reads this one's output to its end (watch.py) would wait for the writer's build.
    ( exec {LOGFD}>&-; exec {LOGFD}>/dev/null
      # shellcheck source=/dev/null # the engine's lib files, as below
      for l in $SNAPLIBS; do . "$HERE/lib/$l.sh" || exit 1; done; names && snapwriter ) < /dev/null > /dev/null 2>&1 8>&- &
  fi
  snapprint; exit
fi
# shellcheck source=/dev/null # the engine's lib files SNAPLIBS names, in that order
for l in $SNAPLIBS; do . "$HERE/lib/$l.sh" || exit 1; done
names || exit 1
asked=$KEPT.$$.asked
: > "$asked" && snapask "$asked" || { rm -f "$asked"; exit 1; }
( flock -w 600 9 || { echo "conveyor: another snapshot build held $KEPT.lock for 600 s" >&2; exit 1; }
  { [ -s "$KEPT" ] && [ -e "$asked" ] && [ "$KEPT" -nt "$asked" ]; } || snapkeep ) 9>>"$KEPT.lock"; rc=$?
rm -f "$asked"
[ "$rc" = 0 ] || exit "$rc"
snapprint
