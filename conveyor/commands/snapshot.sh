# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh snapshot [--fresh]`: the snapshot the Board reads (snapshot(), lib/snapshot.sh), sourced by conveyor.sh.
# A reader prints the kept snapshot (KEPT, <state>/snapshot.json) at once and builds nothing. Its first three fields are
# snapshotAt (when the build that made it began, UTC), snapshotAge (its age in seconds as it is printed) and
# recordsNewer (the card records changed after that build began: snapprint). The Board,
# /units and every watcher read the snapshot again and again: each built its own, and on a long history one build took
# a minute, with 12 to 35 of them running at once, so no reader got one before it stopped waiting.
# When an input changed after that build began (a record line, the retried lines, the control record, the files the
# stream watches beside them (watch.py STATE_FILES), a card's live record or a proof run's, a card begun or ended, the
# issues list the stream keeps: snapinputs) or the kept snapshot is SNAPOLD seconds old
# (what counts on the clock alone, and an issues list asked of GitHub), the reader starts the writer in the background.
# The writer is one process a project (it holds KEPT.lock while it builds; a second one finds it held and ends): it
# builds, writes the new snapshot beside KEPT, dates it when its build began and renames it into place, so a reader
# never reads half a file; then it builds again while an input changed meanwhile, at most once every SNAPGAP seconds.
# With no kept snapshot yet, and with --fresh (a caller that needs the view after its own change, as a test does, or
# after a change no input shows: the stream's loop process ending), the snapshot is built here, under the same lock,
# kept and printed. A call that waited for the lock prints
# the build another call began after this one asked, and makes none of its own.
# A build with no `watch` feed (GITHUB unset) reads GitHub's answers, and the Claude usage readings the guard reads,
# from SNAPGH, asked (github(), lib/issues.sh; guardread()) before the lock is taken: a slow GitHub then never holds
# the lock, and with it every other writer (the stream's, which has its own GitHub folder), until it answers. One
# call asks at a time (SNAPGH.lock), and a call asks nothing when another one asked after it began (--fresh) or after
# the kept snapshot's build began (the writer): two calls for one rebuild ask GitHub once.
KEPT=$ST/snapshot.json SNAPOLD=30 SNAPGAP=5 SNAPGH=$ST/snapgh
SNAPLIBS='slots prompts control views snapshot issues pick testrun push flaky fulltest testaction testfiles testrules lane run machine install'
case ${2-} in
  '') fresh='' ;;
  --fresh) fresh=1 ;;
  *) echo "usage: conveyor.sh snapshot [--fresh]" >&2; exit 2 ;;
esac
# Whether an input of the kept snapshot changed after its build began (KEPT's time is when that build began).
snapinputs() {
  local f=("$STATE" "$RETRIED" "$CONTROL" "$ST/pushed" "$ST/limit.jsonl" "$ST/maintest.json" "$ST/loop.json" "$CARDS" "$CARDS/mainrun")
  [ -z "$GITHUB" ] || f+=("$GITHUB/issues")
  [ -n "$(find "${f[@]}" -maxdepth 1 \( ! -path "$CARDS/*" -o -path "$CARDS/mainrun" -o -name '*.live' \) -newer "$KEPT" -print -quit 2>/dev/null)" ]
}
snapdue() { snapinputs || ! p_newer "$KEPT" "$SNAPOLD"; }
# GitHub's answers and the guard's usage readings for the next build, asked outside the build lock into SNAPGH, when
# there is no `watch` feed: the build then reads them as a feed's (GITHUB set), and reading() asks nothing in it.
# SNAPGH/at is dated when the last asking began. <since> is a file: when the last asking began after it was dated,
# those answers serve and nothing is asked. The lock is waited for, or with nowait not: a call that finds another asking returns 3.
snapask() { # <since> [nowait]
  [ -z "$GITHUB" ] || return 0
  [ -d "$SNAPGH" ] || mkdir -p "$SNAPGH" || return 1
  ( if [ -n "${2-}" ]; then flock -n 9 || exit 3; else flock -w 600 9 || { echo "conveyor: another call asked GitHub for 600 s" >&2; exit 1; }; fi
    [ ! "$SNAPGH/at" -nt "$1" ] || exit 0
    # What github() keeps (lib/issues.sh), but the label times (labelled) only when an open issue names the label
    # (BUILT): the snapshot reads them only then, and each question is a program or more a build (t_snapexec).
    local i; : > "$SNAPGH/at" || exit 1
    if i=$(openissues "$FIELDS" 2>/dev/null); then printf '%s\n' "$i" > "$SNAPGH/issues.new" && mv -f "$SNAPGH/issues.new" "$SNAPGH/issues"
    else rm -f "$SNAPGH/issues"; fi
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
snapkeep() {
  local n=$KEPT.$BASHPID rc GITHUB=${GITHUB:-$SNAPGH}
  : > "$KEPT.at" && snapshot > "$n" && [ -s "$n" ] && touch -r "$KEPT.at" "$n" && mv -f "$n" "$KEPT"; rc=$?
  [ "$rc" = 0 ] || rm -f "$n"; return "$rc"
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
snapprint() {
  local k s m now newer=false
  k=$(p_filekey "$KEPT") && k=${k#* } && [[ $k =~ ^([0-9]+)[.,]([0-9]{3}) ]] || { echo "conveyor: cannot read $KEPT" >&2; return 1; }
  s=${BASH_REMATCH[1]} m=$((BASH_REMATCH[1] * 1000 + 10#${BASH_REMATCH[2]}))
  now=${EPOCHREALTIME/[.,]/}; now=$((10#$now / 1000)); m=$((now > m ? now - m : 0))
  # The shell's own test of the times (to the nanosecond, as find -newer): no program on each read.
  { [ "$STATE" -nt "$KEPT" ] || [ "$RETRIED" -nt "$KEPT" ]; } && newer=true
  printf '{"snapshotAt":"%s","snapshotAge":%d.%03d,"recordsNewer":%s,' "$(export TZ=UTC; printf '%(%Y-%m-%dT%H:%M:%SZ)T' "$s")" $((m / 1000)) $((m % 1000)) "$newer"
  tail -c +2 "$KEPT"
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
  { [ -s "$KEPT" ] && [ "$KEPT" -nt "$asked" ]; } || snapkeep ) 9>>"$KEPT.lock"; rc=$?
rm -f "$asked"
[ "$rc" = 0 ] || exit "$rc"
snapprint
