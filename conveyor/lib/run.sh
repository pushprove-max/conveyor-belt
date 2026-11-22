# SPDX-License-Identifier: Apache-2.0
# Up to the cap in force of cards at once, each launched and waited on here: no panes, no relay, no watcher.
# Nothing to pick does not end the run while a card is in flight: that card may land on a NO-GO and so make its
# follow-ups pickable. The loop asks again each time a card ends, and stops only when a pick finds nothing and no
# card was running when that pick began. The running cards are counted before the pick, not after it: a card that
# lands while the pick is asking, or just after, is then still followed by one more pick, which sees its follow-ups.
# While a builder slot is free it also asks at least every POLL seconds, so an issue given back by `retry` is
# taken without a restart and without waiting for a card to end. A retried card does not count toward max-cards:
# once the run has used them up it still picks, but retried issues only. A pick that fails while cards are in
# flight does not end the run under them (gh is asked far more often now): it is asked again at the next turn.
# A run limited by --only builds every issue of its list, however many cards that
# takes: max-cards is then how many build at once in it (never more than the cap in force), not how many it starts.
# It goes on while an issue of the list waits on a dependency or is held (pick says `wait`) and ends once nothing of the list is
# left to pick or waiting: each one has landed, closed or blocked, or will not be picked (it is said at the start).
# At its start it says which of its issues depend on an open issue outside the list (they wait until that closes),
# are in a dependency cycle, are held (it waits for their release), or will not be picked at all (excluded by a rule,
# kept off by a label, not open).
# `serve` is the same loop with no end and no max-cards: when nothing is in flight and no issue qualifies, or
# the pick fails, it looks again after IDLE seconds.
# At the top of each turn the loop, `run` or `serve`, also sees to the push: when the last landed commit is in main
# and origin does not have it, and no push is running, it starts one (push, above) beside the cards, at once for a
# landing it has not tried yet and otherwise once PUSH_RETRY seconds have passed since the last try; but not while the
# last push failed its check on the commit main is at (checkheld(): it would fail the same way). The push is not
# a card: it is not counted against the builder cap, and its end only turns the loop. A `run` waits for a push under
# way before it ends (a failed pick does not end it under one either), then exits 1 if a push is still owed. With the
# control record's push rule off (land only, owed()), no push is owed: cards land on main one after another and the
# loop pushes none of them; the Board's Push landed (fulltest()) or Push now (pushnow()) does.
# stop, under the lock: which of the loop's cards in progress end, given as "<pid> <card>" lines. A card that
# has begun filing its follow-ups or landing is left to finish: stopped there, it could leave filed issues with no
# landing. So is a card that has begun filing the slices of a split (splitcheck(), growcheck(): lib/slices.sh) or has
# filed them: stopped, its issue would go back to the queue with its slices open. Under the lock, none of them can
# begin either while this asks. A card that waits at its land step for a release run (releasewait(), lib/push.sh)
# or for another card's landing turn (landwait(), lib/claim.sh) has begun neither (a follow-up it filed before the hold refused its landing was withdrawn), and ends (bug #1076:
# left, it landed after the stop once the run ended). Each card that ends has its processes killed here, all of them (the card, its session
# or review, the timeout around it), and prints its card id.
halt() { # <pid> <card> lines
  local p c
  while read -r p c; do
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null || continue
    stdb ask card "$c" 2>/dev/null | jq -es --arg c "$c" 'map(select(.card == $c)) | (last | .step == "start" and (.waitFor | IN("release", "turn"))) as $w
      | ($w | not) and (any(.step | IN("filed", "landed", "closed", "blocked")) or (last | .step == "start" and (.of | IN("file", "land"))))
      or any(.[]; (.split, .grown) | objects | (.filed, .cards) | type == "array" and length > 0)' >/dev/null 2>&1 && continue
    kill -TERM $(tree "$p") 2>/dev/null; echo "$p $c"
  done
}
onlyreport() { # what a run limited by --only will not build by itself, said at its start
  local issues q
  issues=$(openissues "$FIELDS") && q=$(upnext "$issues" '' all) \
    || { echo "conveyor: the open issues could not be read: the dependencies of the listed issues are not checked" >&2; return 0; }
  jq -r --argjson only "$ONLY" --argjson q "$q" --slurpfile cards <(recs) "$DEPS"'
    map(.number) as $open | (cycles($cards) | add // []) as $cyc | ($q | INDEX(.number)) as $in | ($cards | map(.issue)) as $taken
    | ($only[] | select(IN($open[]) | not) | "conveyor: #\(.) is not open: nothing to build"),
      (.[] | select(.number | IN($only[])) | .number as $n | $in[$n | tostring] as $e
        | ([needs[] | select(IN($open[]) and (IN($only[]) | not)) | "#\(.)"] + [farneeds[] as $r | select(.far[$r].open != false) | $r]) as $out
        | (select($out != []) | "conveyor: #\($n) depends on \($out | join(", ")), outside this run: it waits until \(if ($out | length) == 1 then "that issue closes" else "those close" end)"),
          (select($n | IN($cyc[])) | "conveyor: #\($n) is in a dependency cycle: it will not be picked"),
          (select($n | IN($taken[]) | not) | if (.parts // []) != [] then "conveyor: #\($n) is a parent: it is not built, " + ([.parts[] | select(.open) | .ref]
              | if . == [] then "and its parts are all closed: the loop closes it at its next turn" else "its open parts \(join(", ")) are built in its place, and it closes when each is closed or landed" end)
            elif $e == null then "conveyor: #\($n) is kept off the belt by a label: it will not be picked"
            elif $e.hold then "conveyor: #\($n) is held: the run waits until it is released"
            elif $e.rule != null then "conveyor: #\($n) is excluded by the rule \($e.rule): it will not be picked" else empty end))' <<<"$issues"
}
tree() { local k; echo "$1"; for k in $(pgrep -P "$1"); do tree "$k"; done; } # <pid>: it and every process under it
# <pid>: it and every process under it, each stopped before the processes under it are looked for, so none can start
# another unseen; KILL then ends them all, and none of them runs a handler that starts one more.
freeze() { local k; kill -STOP "$1" 2>/dev/null; echo "$1"; for k in $(pgrep -P "$1"); do freeze "$k"; done; }
# True when this process runs from an install and the pack pins another commit (or, following the plugin's main, the
# project's current engine is another commit, or none is taken yet: enginepin()), or is a `serve` run from a checkout
# whose HEAD (the commit its conveyor/ came from) is no longer the one it started on. A loop run from a checkout has
# no version folder, and never restarts on the pin; a `run` from one is not restarted, and its own landings move HEAD.
# A pack that does not read is not said here: the loop asks at every turn, and says why once (packturn()).
stale() {
  local p f
  if [ -n "$OWN" ]; then enginepin p f 2>/dev/null && if [ -n "$p" ]; then [ "$p" != "$OWN" ]; else [ -n "$f" ]; fi
  else [ -n "$FOLLOW" ] && p=$(git -C "$HERE" rev-parse -q --verify HEAD) && [ "$p" != "$RAN" ]; fi
}
# <command...>, run under the card records' lock unless this process is stale: then "stale". A landing takes the same
# lock, so no pick follows one that changed the pin.
fresh() { if stale; then echo stale; else "$@"; fi; }
# The pack's names, at every turn of the loop (run()), in run()'s own variables: one that does not read sets nopack to
# why, which holds the turn's push and pick. Why is said when it changes (told), never at every turn: a loop held for
# hours has said it once.
packturn() {
  nopack=''; names 2>/dev/null || { nopack=$(names 2>&1) || :; nopack=${nopack:-conveyor pack: $PACK could not be read}; }
  [ "$nopack" = "$told" ] || { told=$nopack; [ -z "$nopack" ] || printf '%s\n' "$nopack" >&2; }
}
# <conveyor.sh>: true when that script has the machine's Conveyor (its machine command, and room() under it). A pin older
# than that would start cards past the machine's cap, pause and room: no loop restarts on it, and install-service
# refuses it. The command is its line of the command table (`cmd machine `), or in a commit from before the table, its
# arm of the dispatch case (`  machine) `).
machined() { grep -qE '^(cmd machine |  machine\) )' "$1" 2>/dev/null; }
# The issues, as a JSON list, of the cards a card on the belt waits on now (its live record's waits, at settle()) that
# `retry` gave back: their lines are out of the card records. Nothing when there are none. The loop picks one of them
# first, even with every slot taken: a card that waits on it past the waiting cards left out of the count (idle())
# holds a slot, and with the belt full of such cards it would never be picked. A card that waited once and went on
# holds its slot for work, and starts nothing past the cap.
# A run with --only takes only the listed ones.
# How many of the loop's cards in progress only wait now: alive, with <worktree>.idle standing. A card stands it while
# it sleeps out a wait on a same-file card or on the batch card that took it (settle()), or for main to change on a
# red main (mainred.sh mainwait()), or for the machine hold to go (mainred.sh holdwait()), or for its seat's CLI to come back (seatwait()); never while it runs its checks or tests. run() leaves at most the cap of them out of its count
# against the cap: the rest count, so the loop does not start card after card while the old ones pile up waiting.
# A card in a step that runs no builder session never counts, waiting or not (offcap()), so this limit holds the others.
idle() { # <the loop's own cards in progress, "<pid> <card>" one a line>
  local p c n=0
  while read -r p c; do [ -n "$c" ] && [ -e "$CARDS/$c.idle" ] && kill -0 "$p" 2>/dev/null && n=$((n + 1)); done <<<"$1"
  echo "$n"
}
# The mark of a card that runs no builder session now: <worktree>.nocap, holding the step, from the start of its
# review (with the judge), test, land or file step (began(), lib/card.sh) to the start of its next build, fix or
# rebase step, the only steps that run a builder session. The loop leaves such a card out of its count against the
# builder cap, whether it waits or not (offcap()): its tests take slots of the machine's test pool (lib/slots.sh),
# which limits them apart.
capmark() { # <card> <the step it begins>
  case $2 in review|test|land|file) printf '%s\n' "$2" > "$CARDS/$1.nocap" ;; *) rm -f "$CARDS/$1.nocap" ;; esac
}
# How many of the loop's cards in progress hold no builder slot: alive, with <worktree>.nocap standing (capmark()).
# Prints "<all of them> <those that wait (<worktree>.idle)> <in their review step, not waiting> <in their test step,
# not waiting>".
offcap() { # <the loop's own cards in progress, "<pid> <card>" one a line>
  local p c s n=0 w=0 r=0 t=0
  while read -r p c; do
    [ -n "$c" ] && read -r s 2>/dev/null < "$CARDS/$c.nocap" && kill -0 "$p" 2>/dev/null || continue
    n=$((n + 1)); if [ -e "$CARDS/$c.idle" ]; then w=$((w + 1)); elif [ "$s" = review ]; then r=$((r + 1)); elif [ "$s" = test ]; then t=$((t + 1)); fi
  done <<<"$1"
  echo "$n $w $r $t"
}
# The loop's cards that wait for their seat's CLI (seatwait(), lib/control.sh: alive, <worktree>.idle standing, their
# live record's cli naming it) whose step starts again in this turn: at most <free> of them, each once the CLI is on
# PATH and the host's report, read fresh, lists it. Each has its idle mark taken away here, so it counts against the
# cap from this turn on, and the card starts its step. Prints how many.
cliwake() { # <the loop's own cards in progress, "<pid> <card>" one a line> <free slots>
  local p c a n=0 h=''
  while read -r p c; do
    [ "$n" -lt "$2" ] || break
    [ -n "$c" ] && [ -e "$CARDS/$c.idle" ] && kill -0 "$p" 2>/dev/null && a=$(jq -r '.cli | strings' "$CARDS/$c.live" 2>/dev/null) \
      && [ -n "$a" ] && command -v "$a" >/dev/null || continue
    [ -n "$h" ] || h=$(hostclis fresh) || h=''
    jq -e --arg a "$a" 'has($a)' <<<"${h:-null}" >/dev/null 2>&1 || continue
    rm -f "$CARDS/$c.idle"; n=$((n + 1))
  done <<<"$1"
  echo "$n"
}
urgent() {
  live | jq -c --slurpfile s <(turncards) --argjson only "${ONLY:-null}" '[$s[] | select(.step == "picked") | .card] as $on
    | [$s[] | select(.step | IN("landed", "closed", "blocked")) | .card] as $ended
    | [to_entries[] | select((.key | IN($on[])) and (.key | IN($ended[]) | not)) | .value.waits.on // empty
      | select(IN($on[]) | not) | capture("-(?<n>[0-9]+)$").n | tonumber | select($only == null or IN($only[]))] | unique | select(. != [])' 2>/dev/null
}
# A red main commit whose fix card is not picked yet, or was given back by `retry` (mainred.sh redpick()): prints its commit;
# nothing when there is none, when one of the loop's own cards in progress is a main-red fix card, or in a run with
# --only (whose pick takes no fix card). With the cap reached, the loop picks that fix card in one slot beyond it
# (issue 612): the cards on the belt that fail only what is red on main wait for that fix, and with every slot theirs
# nothing would move. One such card at a time; once it ends its slot ends with it, as the loop counts its cards
# again. The machine's cap and room apply as to any card (mainred.sh redpick(): room()).
redfix() { # <the loop's own cards in progress, card ids one a line>
  [ -z "${ONLY:-}" ] && [ -s "$MAINRED" ] || return 0
  jq -r --slurpfile s <(turncards) --argjson own "$(jq -Rsc '[splits("\n") | select(. != "")]' <<<"$1")" \
    '[.reds[]?.card | strings] as $fix | select(any($own[]; IN($fix[])) | not) | [$s[].card] as $taken
    | first(.reds[]? | select(.card == null or (.card | IN($taken[]) | not)) | .sha)' "$MAINRED" 2>/dev/null
}
# The cards an older speed check blocked, at the loop's start: each is retried as `retry <issue> --fresh` retries it
# (its kept work moved to kept-dropped), with no one asked, and says why (SPEEDWHY) in the log and on its retried line.
# A card counts when its blocked line is the last end of its issue (no card picked, landed or closed since) and the
# version of the speed check that blocked it is lower than this engine's (SPEEDCHECK, lib/speedproof.sh): its speedcheck,
# or, on a line that carries none (written before the lines carried it), 1 for the first check's two reasons and 2 for
# the second's three ("the file is not faster: ...; its budget is ...", "the split does not fit: ..." and "the file is
# over the budget of its own ..."). Not a card whose issue the owner holds, nor one retried
# so before: SPEEDRETRIED keeps {card, issue, speedcheck, time} of each. No control record read, nothing is retried.
SPEEDWHY='retried: the speed check that blocked it has changed'
speedretry() {
  local held c n v
  held=$(ctl 2>/dev/null | jq -ce '.held // [] | arrays') || return 0
  while read -r c n v; do
    [ -n "$c" ] || continue
    RETRYWHY=$SPEEDWHY locked retry "$n" fresh >/dev/null || continue
    echo "conveyor: card $c of issue #$n: $SPEEDWHY"
    jq -cn --arg c "$c" --argjson n "$n" --argjson v "$v" --arg t "$(date -u +%FT%TZ)" '{card: $c, issue: $n, speedcheck: $v, time: $t}' >> "$SPEEDRETRIED" \
      || echo "conveyor: card $c could not be noted in $SPEEDRETRIED as retried" >&2
  done < <(turncards | jq -rs --argjson now "$SPEEDCHECK" --argjson held "$held" --slurpfile was <(cat "$SPEEDRETRIED" 2>/dev/null) '
      ($was | map(.card)) as $d | map(objects | select((.issue | type) == "number" and .issue != 0)) | group_by(.issue)[]
      | map(select(.step | IN("picked", "blocked", "landed", "closed", "pushed"))) | last | select(.step == "blocked")
      | (.speedcheck // (.reason // "" | if startswith("build: the files of the split are not faster: ")
          or (startswith("build: the file is not faster: ") and (contains("; its budget is ") | not)) then 1
          elif startswith("build: the file is not faster: ") or startswith("build: the split does not fit: ")
          or startswith("build: the file is over the budget of its own that the build proposes: ") then 2 else null end)) as $v
      | select($v != null and $v < $now and (.issue | IN($held[]) | not) and (.card | IN($d[]) | not))
      | "\(.card) \(.issue) \($v)"' 2>/dev/null)
}
# The cards with an open record whose process is gone, at the loop's start and at each look: the machine or the loop
# stopped under them (a power cut, a reboot, a loop killed with its cards), and nothing would ever close them. Only a
# card whose worktree line names its process (pid and start) counts, and none of the loop's own (given, card ids one a
# line): a card that has not written that line yet is still starting. A card whose process runs is never touched.
# Each is blocked as a card that stops is (block()): its worktree's change, staged, unstaged and untracked, kept as a
# patch. One stopped in its test run keeps what that run had passed, as a run cut short does (testlist.sh rerunlist()), beside the
# patch: its next card's run goes on from there (card()); so does a list an earlier run of it left. Then its issue is
# given back as `retry` gives it, with no one asked, so it is picked again from its kept work, or from the start when
# its worktree was gone too. One whose change could not be kept stays blocked, its worktree where it is, and so does a
# card of issue 0 (a branch, land-branch: no issue to pick again).
GONE='its process was gone: the machine or the loop stopped'
# The worktree of a card whose process is gone, made ready for block() to keep (revive(), and run() for a card of its
# own). Stopped in its batch's tests (batch(), rebatch()): its worktree holds the batch's changes, not its own; its
# own goes back first, on the commit it was on, and no list of passes goes with it: the batch's run, of the batch's
# change, writes <worktree>.rerun (batchlist()). It fails, saying so, when its change cannot be put back: the card is
# left open, as block() would keep the batch's changes as its work and remove its own .bpatch.
gonewt() { # <card> <worktree> <its last step>
  local c=$1 wt=$2 f
  if [ -s "$wt.lent" ] && [ -d "$wt" ]; then
    git -C "$wt" reset -q --hard "$(<"$wt.lent")" 2>/dev/null && git -C "$wt" apply --index "$wt.bpatch" 2>/dev/null || {
      echo "conveyor: card $c had an open record and its process was gone mid-batch, and its change could not be put back in its worktree; it is left open: its change is the patch $wt.bpatch on commit $(<"$wt.lent")"
      return 1; }
    rm -f "$wt.lent" "$wt.rerun"
  elif [ "$3" = test ] && [ -d "$wt" ] && [ -d "$wt.testlog" ] && f=$(testfails "$wt.test" 137); then
    rerunlist "$wt" "$(git -C "$wt" diff --cached --binary --no-renames HEAD 2>/dev/null | git hash-object --stdin)" "$f" \
      "$(git -C "$wt" rev-parse -q --verify HEAD 2>/dev/null)" "$(git -C "$wt" write-tree 2>/dev/null)"
  fi
}
revive() { # <the loop's own cards, one a line>
  local c n p t step wt
  while IFS=$'\t' read -r c n p t step; do
    [ -n "$c" ] && ! grep -qxF "$c" <<<"$1" && ! p_alive "$p" "$t" || continue
    # Read again now its process is gone: a card writes its closing line before its process ends, so one that closed
    # since the read above (another process's: a land-branch) is closed, not gone.
    [ "$(stdb ask ended "$c" 2>/dev/null)" != true ] || continue
    wt=$CARDS/$c
    gonewt "$c" "$wt" "$step" || continue
    ( block "$c" "$n" "$wt" "$GONE" )
    if [ -d "$wt" ] || [ "$n" = 0 ]; then
      echo "conveyor: card $c had an open record and its process was gone; it is blocked$([ "$n" = 0 ] || echo ", its change left in its worktree: \`retry $n\` takes issue #$n again")"
    else
      echo "conveyor: card $c had an open record and its process was gone; it is blocked, its work kept, and issue #$n is given back"
      locked retry "$n"
    fi
    stdbkeeps
  done < <(jq -rs '[group_by(.card)[] | select(all(.step | IN("landed", "closed", "blocked") | not))
      | (last | if .step == "start" then .of else .step end) as $s
      | map(select(.step == "worktree" and (.pid | type) == "number" and (.started | type) == "string")) | last | select(.)
      | [.card, .issue, .pid, .started, $s] | @tsv] | .[]' < <(turncards) 2>/dev/null)
}
# A card of the loop: card() in a process of its own, under this one, which writes that process's exit status to
# <cards>/<card>.exit when it ends (128 + N when signal N killed it), so the loop can say why a card that wrote no
# closing line ended (cardgone()). LOOPCARD marks it as the loop's: a step whose seat's CLI stays gone waits for the
# loop to start it again (seatwait(), cliwake()).
cardrun() { # <card> <issue>
  # shellcheck disable=SC2034 # LOOPCARD is read by seatwait() in lib/control.sh
  ( LOOPCARD=1; card "$1" "$2" ); echo $? > "$CARDS/$1.exit"
}
# The Conveyor commit a card of the loop runs now: the one its last switch to new code named on its start line
# (began(), lib/card.sh), else the one it started on.
cardcode() { # <card> <the commit it started on>
  local t
  t=$(stdb ask card "$1" 2>/dev/null | jq -rs --arg c "$1" 'map(select(.card == $c and .step == "start" and .engine)) | last | .engine // empty' 2>/dev/null) \
    && [ -n "$t" ] && echo "$t" || echo "$2"
}
# A card's last step: its last record line's (the step a start line opens).
cardstep() { # <card>
  stdb ask card "$1" 2>/dev/null | jq -rs --arg c "$1" 'map(select(.card == $c)) | last | if .step == "start" then .of else .step end | strings' 2>/dev/null
}
# Why a card of the loop ended with no closing line, for its blocked line and its error output: its last step
# (cardstep()), its last action in that step (<worktree>.live, when it is of that step) and its exit status or the
# signal that killed it (<cards>/<card>.exit, cardrun()). A card that an older loop started has no exit status.
cardgone() { # <card> <its last step>
  local s=$2 a='' rc why
  [ -z "$s" ] || a=$(jq -r --arg s "$s" 'select(.step == $s) | .action | strings' "$CARDS/$1.live" 2>/dev/null)
  why="its process ended without a result${s:+ in its $s step}${a:+ (last action: ${a:0:300})}"
  read -r rc 2>/dev/null < "$CARDS/$1.exit" || rc=''
  if [[ ! $rc =~ ^[0-9]{1,3}$ ]]; then echo "$why; its exit status is not known"
  elif [ "$rc" -gt 128 ] && a=$(kill -l $((rc - 128)) 2>/dev/null); then echo "$why; signal $a killed it (exit status $rc)"
  else echo "$why; it exited with status $rc"; fi
}
# A card stuck in flight (#466): open, its worktree line (or, before it, its split check's start line, lib/slices.sh)
# naming its process (pid and start), and either that process
# gone, or alive with no process of its step for a stall's time (below). Its step is the one the Board shows it in: the step
# its last start line begins, else the one after its last line. A step's process (a session, a review, a test run, a
# wait at the claim or for the machine or the model API, a bug card's run on main's code) keeps a live record while it
# runs, and watch() ends one that makes no progress for STUCK seconds; the step then waits REVIEW_PAUSE and runs once
# more, writing nothing meanwhile. So a card in its build, review, fix or test step with no live record, and with no
# new line and no write to any of its files for STUCK and REVIEW_PAUSE together, has no process of that step. Prints
# "<pid> <step> gone" or "<pid> <step> stuck"; fails for any other card. With `turn`, the loop's look at its cards, it
# reads the card records its turn kept (turncards()), asking the store nothing: a card is stuck only after minutes with
# no new line, so that reading, of this turn, holds its last line then. Outside the loop's turn (`retry` and `shut`),
# a process that a signal stopped (ps state T: `kill -STOP`, a Ctrl-Z) does no work until someone starts it again, so
# it prints "<pid> <step> stopped"; the loop never leaves a card's process stopped (freeze() kills it at once). With
# `any` (`shut`), a card whose process runs prints "<pid> <step> running" too.
stuckcard() { # <card> [turn | any]
  local c=$1 p t s at m f
  IFS=$'\t' read -r p t s at < <(if [ "${2:-}" = turn ]; then turncards; else stdb ask card "$c"; fi 2>/dev/null | jq -rs --arg c "$c" 'map(select(.card == $c and .step != "push")) as $l
    | ($l | map(select((.step == "worktree" or (.step == "start" and .of == "split")) and (.pid | type) == "number" and (.started | type) == "string")) | last) as $w | ($l | last) as $z
    | select($w != null and all($l[]; .step | IN("landed", "closed", "blocked", "pushed") | not))
    | [$w.pid, $w.started, (if $z.step == "start" then $z.of elif $z.step | IN("build", "fix", "rebase") then "review" elif $z.step == "brief" then "build"
        elif $z.step == "review" then (if $z.result == "GO" then "test" else "fix" end) elif $z.step == "test" then (if $z.result == "fail" then "fix" else "land" end)
        else $z.step end), ($z.time | fromdate? // 0)] | @tsv' 2>/dev/null) && [ -n "$p" ] || return 1
  p_alive "$p" "$t" || { echo "$p $s gone"; return 0; }
  [ "${2:-}" = turn ] || [[ $(ps -o stat= -p "$p" 2>/dev/null) != *T* ]] || { echo "$p $s stopped"; return 0; }
  [ "${2:-}" != any ] || { echo "$p $s running"; return 0; }
  [[ $s =~ ^(build|review|fix|test)$ ]] && [ ! -e "$CARDS/$c.live" ] && [ ! -e "$CARDS/mainrun/$c.unfixed.live" ] || return 1
  m=$at
  while read -r f _; do [[ ! $f =~ ^[0-9]+$ ]] || [ "$f" -le "$m" ] || m=$f; done < <(p_mtimes "$CARDS/$c" "$CARDS/$c".* "$CARDS/mainrun/$c".* 2>/dev/null)
  [ $((EPOCHSECONDS - m)) -ge $((STUCK + REVIEW_PAUSE)) ] || return 1
  echo "$p $s stuck"
}
# The reason a card stuck in flight is blocked with: <step> <gone | stopped | stuck>, as stuckcard() prints them.
stuckwhy() { # <step> <gone | stopped | stuck>
  if [ "$2" = gone ]; then echo "$GONE"; elif [ "$2" = stopped ]; then echo "$1: its process was stopped by a signal, so the engine ended the card"; else echo "$1: no process of this step ran for $((STUCK + REVIEW_PAUSE))s (the pack's stuck and reviewPause), so the engine stopped the card"; fi
}
# Ends a card stuck in flight (stuckcard()) as a block ends a card: a process that is still alive is stopped with
# every process under it, then all are killed, so none writes a line after; then the card is blocked with <reason>,
# its work kept (gonewt(), block()). Fails, leaving the card open, when its change cannot be put back (gonewt()).
endcard() { # <card> <issue> <pid, or "" when its process is gone> <its step> <reason>
  local k=''
  [ -z "$3" ] || { k=$(freeze "$3"); kill -KILL $k 2>/dev/null; }
  for k in $k; do while ps -o stat= -p "$k" 2>/dev/null | grep -qv Z; do sleep 0.1; done; done
  # Closed meanwhile (a card writes its closing line before its process ends): closed, not stuck.
  [ "$(stdb ask ended "$1" 2>/dev/null)" != true ] || return 0
  gonewt "$1" "$CARDS/$1" "$4" || return 1
  ( block "$1" "$2" "$CARDS/$1" "$5" )
}
# `retry <issue>` (#466): each open card of the issue stuck in flight, or whose process a signal stopped
# (stuckcard()), is ended first, as the loop ends one (endcard()), outside the records' lock, which block() takes.
# retry then takes the issue as it takes a blocked card's; a card with a step running, or not yet started, is left,
# and retry refuses it, naming `shut`.
unstick() { # <issue>
  local c p s how w
  [ -n "${NAMED:-}" ] || names || return 1
  for c in $(stdb ask issue cards "$1" 2>/dev/null | jq -r '.card' 2>/dev/null | sort -u); do
    read -r p s how < <(stuckcard "$c") || continue
    [ "$how" != gone ] || p=''
    case $how in gone) w="its process gone" ;; stopped) w="its process stopped" ;; *) w="no process of its $s step for $((STUCK + REVIEW_PAUSE))s" ;; esac
    endcard "$c" "$1" "$p" "$s" "$(stuckwhy "$s" "$how")" && echo "conveyor: card $c was open with $w; it is blocked, its work kept"
  done
}
# `shut <issue | card id>` (#1030): each open card named, every one of the issue's or the one card, is ended as
# endcard() ends a card stuck in flight, whatever its step and whether its process runs, outside the records' lock,
# and blocked with OWNSHUT, its work kept; shut() then closes it. A card in its land step is left as it is: its change
# may be going onto main. So is one that has begun filing issues (its last start line is of file: its follow-ups, or the
# slices of a split, lib/slices.sh), as halt() leaves it: ended there, it would leave some of them open on GitHub, or a
# split's umbrella not held. A card that has filed them and begun its next step (a grown split's fix, growcheck()) is
# ended as any other. Bug: shut ended a card while it filed the
# slices of a split, before splitwithdraw() could close the slices it had filed. The card's processes are stopped
# (freeze()) before its step is read, so a card that runs writes no line between that read and its end; one left is
# started again (unless a signal had stopped it before). A database call of the card's (state.py) is let finish: it
# starts no other, and stopped, it would hold the database's write transaction, so the reads here would wait for it
# until they time out. Bug (issue 1385): shut read the step, the card then began filing, and shut ended it with a slice
# filed. Prints a line for each card it ended; a card left is said on stderr, as is one whose records cannot be read.
shutopen() { # <issue | card id>
  local c n p q s t how k
  [ -n "${NAMED:-}" ] || names || return 1
  if [[ $1 =~ ^[0-9]+$ ]]; then c=$(stdb ask issue cards "$1" 2>/dev/null | jq -r '.card' 2>/dev/null | sort -u)
  else c=$1; fi
  for c in $c; do
    read -r p s how < <(stuckcard "$c" any) || continue
    k=''; [ "$how" = gone ] || k=$(freeze "$p")
    for q in $k; do [[ $(ps -o args= -p "$q" 2>/dev/null) != *state.py* ]] || kill -CONT "$q" 2>/dev/null; done
    # A card the loop blocked meanwhile has no step now: it is ended as before (endcard() reads it closed), shut's own.
    ! read -r _ t _ < <(stuckcard "$c" any) || s=$t
    n=''; read -r n q < <(stdb ask card "$c" 2>/dev/null | jq -rs --arg c "$c" 'map(select(.card == $c)) | "\(first | .issue) \(map(select(.step == "start")) | last | .of // "none")"' 2>/dev/null)
    if [[ ! $n =~ ^[0-9]+$ ]]; then echo "conveyor: card $c: its records could not be read; it is left as it is" >&2; s=''
    elif [ "$s" = land ]; then echo "conveyor: card $c is in its land step; it is left to land" >&2; s=''
    elif [ "$q" = file ]; then echo "conveyor: card $c has begun filing its follow-ups or the slices of its issue; it is left to finish" >&2; s=''; fi
    [ -n "$s" ] || { [ "$how" != running ] || [ -z "$k" ] || kill -CONT $k 2>/dev/null; continue; }
    [ "$how" != gone ] || p=''
    endcard "$c" "$n" "$p" "$s" "$OWNSHUT" && echo "conveyor: card $c was open in its $s step ($([ "$how" = gone ] && echo "its process gone" || echo "its process $how, now ended")); it is blocked, its work kept"
  done
}
# run()'s cards in progress (running), set in run()'s own variables: its jobs less the push (pusher) and the other
# jobs beside the cards, and the cards it took over (took). A push so leaves its builder slot free.
cardsrun() {
  running=$(($(jobs -rp | grep -cvx -e "${pusher:-0}" -e "${tester:-0}" -e "${taker:-0}" -e "${muter:-0}" -e "${prober:-0}" -e "${merger:-0}" -e "${fixer:-0}" -e "${asker:-0}") + ${#took[@]}))
}
# The wait that ends a turn, in run()'s own variables: until the turn's timer, one of the loop's cards (mine), the
# push (pusher) or the machine hold's look (prober, which runends() waits for) ends, at once when one of them has
# ended already. The other jobs beside the cards (take, relfixes, needsask, maintest, mutnext, idlemerge) never end it:
# relfixes, started every IDLE seconds, ended during each turn, so a bare `wait -n` returned at once and the loop ran
# turn after turn with no wait (issue 881). A job named that ended before is waited no more: bash keeps its status,
# and a wait on it returns at once at every turn. The prober is named only while it runs, as nothing clears it (the
# push is cleared at the turn's start, pushended(); a card leaves mine). An adopted card is no job of this shell's;
# wait passes over it. A job that has gone from the shell's job table already (a `jobs` or `wait` took it) is no longer
# found by `wait -n` in bash 5.2: the wait would go on to the timer. So the wait first looks that each of them is alive
# (kill -0), and returns at once when one is not.
# A wake (wakeloop(), lib/control.sh) ends it too: the URG trap run() sets kills the timer and sets nudged, so a wake
# that came after the turn read the control record, and before its timer started, ends the wait at once as well.
turnwait() {
  local j=() p
  [ -z "${nudged:-}" ] || { nudged=''; return 0; }
  [ -z "$pusher" ] || j+=("$pusher")
  [ -z "$prober" ] || ! jobs -rp | grep -qx "$prober" || j+=("$prober")
  for p in "${j[@]}" "${!mine[@]}"; do kill -0 "$p" 2>/dev/null || return 0; done
  wait -n "$timer" "${j[@]}" "${!mine[@]}" 2>/dev/null; nudged=''
}
# A `run` (not a serve) may end at this turn, read in run()'s own variables: no card of its own runs, no push
# (pusher) or machine-hold look (prober) is under way, and no pick waits.
runends() {
  [ "$running" = 0 ] && [ -z "$serve" ] && [ -z "$pusher" ] && [ -z "$waits" ] && { [ -z "$prober" ] || ! jobs -rp | grep -qx "$prober"; }
}
# The parts of a turn of the loop, called in order by run(), in run()'s own variables (the only locals of their own
# are turnended()'s frozen and turnrestart()'s on): turnopen(), turnended(), turnside(), turncount(), turnrestart(),
# turnask() and turnpick().
# The turn's start, in run()'s own variables: the push that ended, the script a `serve` restarts on (new), the pack
# (packturn()), the machine hold, the jobs that take a commit and see to a red release run's fix cards, the seats'
# CLIs, the push, and the control record (cap, guard, pct, now and why).
turnopen() {
  stdbkeeps # the turn's readers, and the cards it starts, find the records kept until they change (lib/records.sh)
  pushended
  # The script a `serve` restarts on, once no push runs: the pinned commit's install, or the checkout's own (its
  # new code); no push starts then, as the restart would wait for it (the new loop makes the push).
  new=''; if [ -z "$pusher" ] && [ -n "$serve" ] && stale; then
    if [ -n "$FOLLOW" ]; then new=$HERE/conveyor.sh
    elif enginepin p 2>/dev/null && installed "$p" ro && machined "$VERSIONS/$p/conveyor/conveyor.sh"; then new=$VERSIONS/$p/conveyor/conveyor.sh; fi
  fi
  packturn
  [ -n "$nopack" ] || fullreap || : # a full test run's marker whose process is gone (fullreap(), lib/fulltest.sh)
  # The machine hold (mainred.sh machinehold(), issue 221), at every turn: while it stands, this turn picks no card. Said when it
  # changes, as above.
  mhold=''; [ -n "$nopack" ] || mhold=$(machineheld)
  [ "$mhold" = "$htold" ] || { htold=$mhold; [ -z "$mhold" ] || echo "conveyor: $mhold" >&2; }
  # A pack that follows the plugin's main or its releases: its pushed main, or newest release, is looked at once every IDLE seconds (take(),
  # lib/install.sh), a job beside the cards, never counted as one and given no run lock; a commit it takes is
  # restarted on at a later turn (stale()).
  if [ -n "$serve" ] && [ -z "$nopack" ] && [ $((SECONDS - ttook)) -ge "$IDLE" ] && { [ -z "$taker" ] || ! jobs -rp | grep -qx "$taker"; } \
    && packget plugin.follow f && [ -n "$f" ]; then
    ttook=$SECONDS; ( take ) 8>&- < /dev/null & taker=$!
  fi
  # A red release run's fix cards (relfixes(), lib/fulltest.sh): looked at once every IDLE seconds, a job beside the
  # cards as take() is; once each has landed and is in the commit release-prep tests (relhead(), lib/push.sh) and no card is open, it starts release-prep again.
  if [ -n "$serve" ] && [ -z "$nopack" ] && [ $((SECONDS - rtried)) -ge "$IDLE" ] && { [ -z "$fixer" ] || ! jobs -rp | grep -qx "$fixer"; }; then
    rtried=$SECONDS; ( relfixes ) 8>&- < /dev/null & fixer=$!
  fi
  # The blocked cards with kept work, and the held issues the nightly whole test filed, put to the owner as decisions,
  # the auto pass over a new one while auto is on, and the step each answer names (needsjob(), lib/needsask.sh): looked
  # at once every IDLE seconds, a job beside the cards as relfixes() is.
  if [ -n "$serve" ] && [ -z "$nopack" ] && [ $((SECONDS - atried)) -ge "$IDLE" ] && { [ -z "$asker" ] || ! jobs -rp | grep -qx "$asker"; }; then
    atried=$SECONDS; ( needsjob ) 8>&- < /dev/null & asker=$!
  fi
  # The seats and the host's CLIs are worked out once in this shell (clis, its words dropped), so the check below,
  # the pick and the cards this turn starts find them kept (seat, hostclis, seatready).
  [ -n "$nopack" ] || clis >/dev/null 2>&1 || :
  nocli=''; [ -n "$nopack" ] || nocli=$(clis && codexready) || : # a seat whose CLI is gone, or a reviewer model family that resolves to no model id, holds this turn's pick
  pushturn # the push, when one is owed and due (lib/push.sh)
  # The control record, at every turn: the cap in force, the guard's reading (taken here, outside the lock:
  # it may go over the network), and a stop, which ends the loop's own cards in progress.
  # Read in this shell (ctlread), so the turn's subshells and the cards it starts find it kept while it stands.
  why=''; if ctlread 2>/dev/null; then ctl=$CTL_V; else ctl=''; why=$(notwhole); fi
  # A record that does not read keeps the last cap read; with none read, nothing is picked. One that names no cap
  # has the seed's.
  IFS=, read -r cap guard <<<"$(jq -r --argjson d "$CAP0" '"\(if . == null then "" else .cap // $d end),\(.guard // "")"' <<<"${ctl:-null}" 2>/dev/null)"
  if [ -n "$cap" ]; then base=$cap; else cap=${base:-0}; fi
  [ -z "$lim" ] || [ "$cap" -le "$lim" ] || cap=$lim
  # The guard reads the account the next card will use (a record that does not read keeps the last one read).
  pct=''; [ -z "$guard" ] || pct=$(guardread "$ctl" ask | jq -r '.pct // empty')
  now=$(state "$ctl" "$pct")
}
# The loop's own cards that ended, or stuck, since the last turn, in run()'s own variables (mine, took, kids), then
# the other open cards whose process is gone (revive()), and with the control record at stop, the loop's own cards.
# A card of the loop whose process ended with no closing line (it was killed, or its shell stopped on an error) is
# recorded blocked, so it is not left open for good and `retry` takes it. Its line and its error output
# (<worktree>.err, kept with it) say why (cardgone()): its last step and action, and its exit status or signal.
# One stopped mid-batch has its own change put back first (gonewt()), or is left open when it cannot be.
# Its session, review or tests outlive it (no longer under it, they are found from the last turn's list) and
# still use its worktree: they are ended, and gone, before block() takes the worktree away. They are stopped, all
# under them with them, then killed: one that ignores TERM never holds the loop, and none starts another on TERM
# that would outlive it unseen.
turnended() {
  local frozen=() # the processes of an ended card, stopped and then killed
  for p in "${!mine[@]}"; do
    # One alive with no process of its step for STUCK and REVIEW_PAUSE seconds (stuckcard(), #466) is ended and blocked, naming that
    # step, so `retry` can take it.
    if kill -0 "$p" 2>/dev/null && [ ! -e "$CARDS/${mine[$p]% *}.live" ] && read -r _ gs gone < <(stuckcard "${mine[$p]% *}" turn) && [ "$gone" = stuck ]; then
      read -r c n <<<"${mine[$p]}"; unset 'mine[$p]' 'took[$p]' 'kids[$p]'
      gone=$(stuckwhy "$gs" stuck)
      endcard "$c" "$n" "$p" "$gs" "$gone" && echo "conveyor: card $c: $gone; it is blocked, and \`retry $n\` takes issue #$n again"
      wait "$p" 2>/dev/null; rm -f "$CARDS/$c.exit"; stdbkeeps; continue
    fi
    if kill -0 "$p" 2>/dev/null; then
      # Those of the last list still alive are kept: one killed during this look has none under it to be found.
      kids[$p]=$( { while read -r k t; do [ -n "$k" ] && p_alive "$k" "$t" && echo "$k $t"; done <<<"${kids[$p]:-}"
        for k in $(tree "$p"); do t=$(p_started "$k") && echo "$k $t"; done; } | sort -u)
      continue
    fi
    read -r c n <<<"${mine[$p]}"; unset 'mine[$p]' 'took[$p]'
    k=${kids[$p]:-}; unset 'kids[$p]'
    # Its closing line is looked for in the whole lines only: a last line still being written (check() says why)
    # made the whole read fail, and a card that had landed was blocked; its push is the loop's, as for any landing.
    [ "$(stdb ask ended "$c" 2>/dev/null)" = true ] && { rm -f "$CARDS/$c.exit"; continue; }
    gs=$(cardstep "$c"); gone=$(cardgone "$c" "$gs"); rm -f "$CARDS/$c.exit"
    # No line left: `retry` ended it (unstick()) and moved its lines out; a blocked line now would stand alone.
    [ -n "$gs" ] || { stdb ask card "$c" 2>/dev/null | grep -q . || continue; }
    k=$(while read -r p t; do [ -n "$p" ] && p_alive "$p" "$t" && echo "$p $t"; done <<<"$k")
    mapfile -t frozen < <(while read -r p t; do [ -z "$p" ] || freeze "$p"; done <<<"$k")
    kill -KILL "${frozen[@]}" 2>/dev/null
    while read -r p t; do while [ -n "$p" ] && p_alive "$p" "$t"; do sleep 0.1; done; done <<<"$k"
    printf 'conveyor: card %s: %s\n' "$c" "$gone" >> "$CARDS/$c.err"
    gonewt "$c" "$CARDS/$c" "$gs" || continue
    ( block "$c" "$n" "$CARDS/$c" "$gone" ); stdbkeeps; echo "conveyor: card $c ended without a result: $gone; it is blocked, and \`retry $n\` takes issue #$n again"
  done
  # Any other open card whose process is gone (revive()): blocked, its work kept, and picked again.
  revive "$(for p in "${!mine[@]}"; do echo "${mine[$p]% *}"; done)"
  if [ "$now" = stopped ] && [ ${#mine[@]} != 0 ]; then
    while read -r p k; do
      [ -n "$p" ] || continue
      # An adopted card is no job of this shell's: wait cannot wait on it, so it is watched until it is gone.
      wait "$p" 2>/dev/null; while kill -0 "$p" 2>/dev/null; do sleep 0.1; done
      read -r c n <<<"${mine[$p]}"; unset 'mine[$p]' 'took[$p]' 'kids[$p]'
      stopped "$c" "$n"; clean "$CARDS/$c"; rm -f "$CARDS/$c.exit"
      locked moveout '.card == $c' --arg c "$c" && echo "conveyor: stopped card $c; issue #$n is back in the queue" \
        || echo "conveyor: stopped card $c, but its lines could not be moved out of the card records: retry #$n by hand" >&2
    done < <(for p in "${!mine[@]}"; do echo "$p ${mine[$p]% *}"; done | locked halt)
    stdbkeeps
  fi
}
# The jobs a `serve` starts beside the cards once a minute, in run()'s own variables: the whole test on main, the idle
# mutation checks and the monthly test-speed survey.
turnside() {
  # The whole test on main (maintest()), looked at once a minute: a job beside the cards, never counted as one, and
  # given no run lock (fd 8), so a loop that ends while it runs leaves the checkout free for the next loop.
  if [ -n "$serve" ] && [ -z "$new" ] && [ -z "$nopack" ] && [ $((SECONDS - mtried)) -ge 60 ] && { [ -z "$tester" ] || ! jobs -rp | grep -qx "$tester"; }; then
    mtried=$SECONDS; ( maintest ) 8>&- < /dev/null & tester=$!
  fi
  # The idle mutation checks (mutnext(), lib/mutate.sh), looked at once a minute: a job beside the cards, never
  # counted as one, and given no run lock. No card's step runs one.
  if [ -n "$serve" ] && [ -z "$new" ] && [ -z "$nopack" ] && [ $((SECONDS - utried)) -ge 60 ] && { [ -z "$muter" ] || ! jobs -rp | grep -qx "$muter"; }; then
    utried=$SECONDS; ( mutnext ) 8>&- < /dev/null & muter=$!
  fi
  # The monthly test-speed survey's issue (survey(), lib/survey.sh), looked at once a minute, in the loop itself: a
  # look is a date and a pack read, and files at most one issue a month. With it, the models with no price (noprice(),
  # lib/control.sh), in this shell, which keeps what it last looked at: the list Needs you counts, and no issue.
  if [ -n "$serve" ] && [ -z "$new" ] && [ -z "$nopack" ] && [ $((SECONDS - stried)) -ge 60 ]; then
    stried=$SECONDS; survey 8>&- < /dev/null; noprice 8>&- < /dev/null || :
  fi
}
# The turn's count of the cards, in run()'s own variables (running, idles, building, inuse), the machine hold's look, the
# loop's notice that its code is stale (old), and what it says of itself (SAYS, loop.json).
turncount() {
  local p c on='' off='' past pidle rev tst
  cardsrun; waits=''
  # The cards counted against the builder cap (building): those running, less those in a step that runs no builder
  # session (offcap(): review and judge, test, land), waiting or not, and less those of the rest that only wait
  # (idle()), at most as many of them as the cap. running still counts every card: the loop ends only once none is left.
  # A card that waits for its seat's CLI starts its step again once the host lists the CLI (cliwake()): one in a step
  # with no builder session at once, any other in a free slot. The free slots are the cap less the cards that build:
  # counted after the cap on idle cards, waits past the cap (the cap lowered while they waited) would fill every slot
  # and none would start again.
  for p in "${!mine[@]}"; do c=${mine[$p]% *}; if [ -e "$CARDS/$c.nocap" ]; then off+="$p $c"$'\n'; else on+="$p $c"$'\n'; fi; done
  cliwake "$off" "${#mine[@]}" >/dev/null || :
  read -r past pidle rev tst <<<"$(offcap "$off")"
  idles=$(idle "$on")
  [ $((running - past - idles)) -ge "$cap" ] || { woke=$(cliwake "$on" $((cap - running + past + idles))) && idles=$((idles - woke)); } || :
  [ "$idles" -le "$cap" ] || idles=$cap; [ "$idles" -ge 0 ] || idles=0
  building=$((running - past - idles)); [ "$building" -ge 0 ] || building=0
  idles=$((idles + pidle)) # every waiting card left out of the count, for loop.json
  # The machine's count (inuse, room()): every card that builds, reviews, tests or lands, the waiting ones left out.
  inuse=$((running - idles)); [ "$inuse" -ge 0 ] || inuse=0
  # The machine hold's look (mainred.sh machineprobe()), at most once every POLL seconds (as often as a free loop would pick)
  # while the hold stands: a job beside the cards, never counted as one, and given no run lock; a `run` does not end
  # while it runs (runends()). Once its files pass on main the hold goes, so the next turn picks again and the cards on
  # hold test again.
  if [ -n "$mhold" ] && [ $((SECONDS - htried)) -ge "$POLL" ] && { [ -z "$prober" ] || ! jobs -rp | grep -qx "$prober"; }; then
    htried=$SECONDS; ( machineprobe ) 8>&- < /dev/null & prober=$!
  fi
  if [ -z "$old" ] && stale; then
    old=1; enginepin p f 2>/dev/null || f=''
    if [ -n "$FOLLOW" ]; then echo "conveyor: the checkout has moved on from this loop's $RAN; nothing new is picked, and the loop restarts on the checkout's new code once its push is done"
    elif [ -n "$f" ]; then echo "conveyor: $([ -n "$p" ] && echo "the project's engine is now Conveyor commit $p, not this loop's $OWN" || echo "the project follows the plugin's $f and has taken no commit of it on this machine yet"); nothing new is picked, and the loop $([ -n "$serve" ] && echo "restarts on the project's engine once its push is done" || echo "ends once its cards and push are done")"
    else echo "conveyor: the pack pins another Conveyor commit than this loop's $OWN; nothing new is picked, and the loop $([ -n "$serve" ] && echo "restarts on the pinned commit once its push is done" || echo "ends once its cards and push are done")"; fi
  fi
  [ -z "$why" ] || [ -z "$old" ] || why+="; the loop $([ -n "$serve" ] && echo "restarts on the $([ -n "$FOLLOW" ] && echo "checkout's new code" || echo "project's Conveyor commit") once its push is done" || echo "ends once its cards and push are done")"
  # building and waiting: the cards counted against the cap, and those left out as they only wait (health());
  # reviewing and testing: those left out as they are in their review (with the judge) or test step (offcap());
  # running: every card of the loop in progress, waiting or not, in whatever step (the Foreman's count on the belt).
  say=$(jq -cn --argjson p "$$" --arg t "$self" --arg s "$now" --arg r "$why" --arg c "$RAN" --arg h "$([ -n "$OWN" ] || echo "$HERE")" --argjson b "$building" --argjson w "$idles" \
    --argjson rv "$rev" --argjson ts "$tst" --argjson n "$running" \
    '{pid: $p, started: $t, state: $s, reason: (if $r == "" then null else $r end), commit: (if $c == "" then null else $c end), checkout: (if $h == "" then null else $h end), building: $b, waiting: $w, reviewing: $rv, testing: $ts, running: $n}')
  [ "$say" = "$said" ] || { printf '%s\n' "$say" > "$SAYS.new" && mv -f "$SAYS.new" "$SAYS" && said=$say; }
}
# The restart on the new code (new), at a turn where the loop's code is stale (old), in run()'s own variables; it does
# not return.
# Restarted as soon as the push job (if any) has ended, without waiting for the cards in flight: the new loop
# would start a second push beside one still running, and nothing is picked meanwhile; no other push starts once
# the restart is due (new, turnopen()), so it never waits for a push of a card that landed meanwhile. The cards carry on in
# this same process on the code they started with (its install stays as it is) until their next step, which begins
# on the new code where the card can switch (switchcode(), lib/card.sh), and the new loop adopts them
# (CONVEYOR_ADOPT, with the run lock on fd 8): it counts them against the cap, keeps their claims (their process
# lives), sees to their ends and the push as for its own, and records one whose process ends without a result as
# blocked. A pin that is not installed ends the loop only once nothing of its own runs. A `run` ends then too.
# They carry on only while this process does: a stop of the loop, or of the machine's Conveyor over it (its service's
# restart too), ends them with all under it (machinestop, lib/machine.sh), and the restart's line says so (#1332).
turnrestart() {
  # The list of the last turn is kept with what runs under each card now: a card killed since then has none under it.
  held=$(for k in "${!mine[@]}"; do
    while read -r p t; do [ -z "$p" ] || echo "$k $p $t"; done <<<"${kids[$k]:-}"
    for p in $(tree "$k"); do t=$(p_started "$p") && echo "$k $p $t"; done
  done | sort -u)
  local -A on=() # the commit each card runs now (cardcode())
  for k in "${!mine[@]}"; do read -r c _ <<<"${mine[$k]}"; on[$k]=$(cardcode "$c" "${took[$k]:-$RAN}"); done
  echo "conveyor: restarting on the new code; ${#mine[@]} cards in flight carry on on $( (for k in "${!mine[@]}"; do echo "${on[$k]}"; done; [ ${#mine[@]} != 0 ] || echo "$RAN") | sort -u | paste -sd' ' - | sed 's/ /, /g')$([ ${#mine[@]} = 0 ] || echo "; a stop of this loop or of the machine's Conveyor, or a restart of its service, ends them")"
  # Without its copy of stderr (LOGFD): the new code makes its own, so each restart kept one more, and after some
  # hundreds every card's test runner got fd 255, bash's own.
  CONVEYOR_KIDS=$held CONVEYOR_ADOPT=$(for k in "${!mine[@]}"; do echo "$k ${mine[$k]} ${on[$k]}"; done) exec "$BASH" "$new" serve {LOGFD}>&-
}
# What the turn's pick reads, in run()'s own variables: the urgent and main-red cards, whether it asks (asking) and
# the open issues (issues), the seats' accounts, the machine's count (slotturn()), the blocked cards whose issue was
# closed (shuts), the cards given back, and the sample of the minute.
turnask() {
  # The open issues a pick reads, asked before the sample starts, so the sample reads them from ISSUES and never
  # asks GitHub itself while the pick holds the records' lock.
  urgent=''; [ "$cap" -le 0 ] || urgent=$(urgent) || urgent=''
  red=''; [ "$cap" -le 0 ] || [ "$building" -lt "$cap" ] || red=$(redfix "$(for p in "${!mine[@]}"; do echo "${mine[$p]% *}"; done)") || red=''
  # While a session's API-side error is fresh (session()), no card is picked: its session would meet the same outage.
  asking=''; if { [ "$building" -lt "$cap" ] || [ -n "$urgent" ] || [ -n "$red" ]; } && [ -z "$old" ] && [ -z "$nopack" ] && [ -z "$nocli" ] && [ -z "$mhold" ]; then
    if apifresh; then waits=1; else asking=1; [ "$now" != running ] || issues=$(asked) || asking=failed; fi
  fi
  # The accounts of the seats the record keeps for an open issue (`control card`) are asked for too, outside the lock:
  # pick holds that issue's card alone while one is at the guard (cardheld(), lib/pick.sh); the queue goes on.
  [ "$asking" != 1 ] || [ "$now" != running ] || [ -z "$guard" ] || [ -z "$issues" ] \
    || for n in $(jq -r --argjson i "$issues" '.cards // {} | keys[] | select(tonumber | IN($i[].number))' <<<"$ctl" 2>/dev/null); do
      SEATCARD=$n guardread "$ctl" ask >/dev/null
    done
  # The machine's count of this project's cards (room()): those in review or in their Test step count, as the
  # machine's cap is over every card that builds, reviews or tests; the waiting ones are left out as here, and no card
  # of it waits for a slot when it asks for none.
  # shellcheck disable=SC2034 # RUNNING is read by room() and slotput, from lib/pick.sh
  RUNNING=$inuse; slotturn "$inuse" "$([ "$asking" = 1 ] && [ "$now" = running ] && echo 1)"
  # A blocked card whose issue was closed leaves the blocked lists (shut), and the issue leaves the open list this
  # turn's pick reads. Closed is decided from the issue's own state on GitHub, never from its absence in the open
  # list (a filter or --only narrows that): each blocked card's issue is asked at every turn until it is seen
  # closed, so it leaves within one turn of closing; a closed answer is kept (shuts) until its card is shut. No
  # answer is no answer: nothing moves. The shut card ends closed in the card records, so pick does not take its
  # issue from an open list asked before it closed; once it is opened again, a later turn gives it back (reopened(),
  # below). The issue leaves ISSUES too, so the sample does not count it queued.
  while read -r n; do
    [ "${n:-0}" != 0 ] && [ -z "${shuts[$n]:-}" ] || continue
    t=$(timeout 20 gh issue view "$n" --json closed 2>/dev/null | jq -r '.closed' 2>/dev/null) || t=''
    [ "$t" != true ] || shuts[$n]=1
  done < <(jq -rs 'map(select(.step != "push")) | group_by(.card)[]
    | select((map(select(.step | IN("landed", "closed", "blocked", "pushed"))) | . as $e
        | [range(length) as $i | $e[$i] | select(.step != "pushed" and (.step != "blocked" or ($e[$i + 1:] | all(.step == "blocked"))))] | last | .step) == "blocked")
    | .[0].issue' < <(turncards) 2>/dev/null | sort -un)
  if [ ${#shuts[@]} != 0 ]; then
    t=$(printf '%s\n' "${!shuts[@]}" | jq -cs .)
    [ -z "$issues" ] || issues=$(jq -c --argjson s "$t" 'map(select(.number | IN($s[]) | not))' <<<"$issues")
    [ ! -s "$ISSUES" ] || { jq -c --argjson s "$t" 'map(select(.number | IN($s[]) | not))' "$ISSUES" > "$ISSUES.new" && mv -f "$ISSUES.new" "$ISSUES"; } 2>/dev/null
    ! locked shut "$t" || shuts=(); stdbkeeps
  fi
  # A shut card's issue opened again is given back as `retry` gives it, before this turn's pick reads the open list.
  [ "$asking" != 1 ] || [ -z "$issues" ] || reopened "$issues"
  # So is a card stopped for the owner's yes whose issue has an approval line added since (approved()).
  [ "$asking" != 1 ] || [ -z "$issues" ] || approved "$issues"
  # So is a card blocked by a session that never began its work, once a check session starts (startagain()).
  [ "$asking" != 1 ] || [ -z "$issues" ] || startagain "$issues"
  # A parent whose GitHub sub-issues are each closed or landed, and an umbrella of a split issue whose slices have all landed or
  # are already done on main, is closed (umbrellas(), lib/slices.sh).
  [ "$asking" != 1 ] || [ -z "$issues" ] || umbrellas "$issues"
  # The sample of the minute, and while a card is in progress a weekly limit reading (reading() asks at
  # most every LIMIT_TTL seconds). Both are taken out of the loop's job list (they may take seconds: the sample asks
  # GitHub for the queue, and a job of the loop's would count as a card).
  if [ $((SECONDS - sampled)) -ge "$SAMPLE" ]; then
    sampled=$SECONDS; ( sample "$building" "$cap" "$now" "$mhold" >/dev/null 2>&1 8>&- & )
    [ "$running" = 0 ] || ( reading >/dev/null 2>&1 8>&- & )
  fi
}
# The pick of a turn where the loop asks (asking), in run()'s own variables; a card it picks is started (mine).
# Its status is 1 when the turn ends here and the next one begins: a card was started, or the pick found the loop's
# code stale (the next turn says so and stops picking). It is 0 when nothing was picked.
turnpick() {
  # A queued card a card on the belt waits on (urgent) goes first, past the cap; the rest only below the cap. Each pick
  # holds the records' lock for LOCKLIMIT seconds at most (lockedfor): one stopped there fails as any failed pick.
  picked=''; [ "$asking" != 1 ] || [ -z "$urgent" ] || { picked=$(ONLY=$urgent lockedfor pick fresh pick retried "$pct" "${issues:-}" "$(acctkey "$ctl")") && [ "$picked" != wait ]; } || picked=''
  # With the cap reached, a main-red fix card (red) takes the one slot beyond it; no queued issue does.
  [ -n "$picked" ] || [ "$asking" != 1 ] || [ -z "$red" ] \
    || { picked=$(BEYOND='main is red' lockedfor pick fresh pick "$([ "$left" != 0 ] || echo retried)" "$pct" "${issues:-}" "$(acctkey "$ctl")") && [ "$picked" != wait ]; } || picked=''
  # Below the cap, the issue it would take is first read beside the cards on the belt (overlap(), outside the lock).
  [ -n "$picked" ] || [ "$building" -ge "$cap" ] || [ "$asking" != 1 ] || { overlap "${issues:-}" "$([ "$left" != 0 ] || echo retried)" "$ctl"; issues=$OVL; }
  [ -n "$picked" ] || [ "$building" -ge "$cap" ] \
    || picked=$([ "$asking" = 1 ] && lockedfor pick fresh pick "$([ "$left" != 0 ] || echo retried)" "$pct" "${issues:-}" "$(acctkey "$ctl")") || { [ "$running" != 0 ] || [ -n "$serve" ] || [ -n "$pusher" ] || exit 1; picked=''; }
  [ "$picked" != stale ] || return 1 # the next turn says so and stops picking
  [ "$picked" != wait ] || { waits=1; picked=''; }
  [ -n "$picked" ] || return 0
  read -r c n again <<<"$picked"
  CARDCTL=$ctl cardrun "$c" "$n" & mine[$!]="$c $n"
  [ "$again" = true ] || left=$((left - 1)); started=$((started + 1))
  return 1
}
run() { # [max-cards] [serve]
  local left=${1:--1} serve=${2:-} cap base='' picked running building idles started=0 c n again timer pusher='' owed tried='' triedat=0 ctl pct now='' p k lim='' waits sampled=-1000000 guard issues='' asking urgent red
  local why say said='' old='' nopack told='' nocli self adopt='' held='' new t tester='' mtried=-1000000 stried=-1000000 taker='' ttook=-1000000 f muter='' utried=-1000000 woke nudged=''
  local mhold htold='' prober='' htried=-1000000 gone gs merger='' gtried=-1000000 fixer='' rtried=-1000000 asker='' atried=-1000000
  local inuse # the machine's count of the turn (turncount())
  # The loop's own cards in progress: pid -> "card issue"; took: those it adopted at its start -> the commit they run;
  # kids: a card's processes at the last turn, as "<pid> <started>" lines; at a restart, the list the loop
  # before it took just before it restarted (CONVEYOR_KIDS), so a card that ends before this loop's first turn still
  # has its review and tests ended before its worktree goes.
  local -A mine=() took=() kids=() shuts=()
  # One loop per checkout: the cap counts this loop's own cards, so a second loop beside it would double it.
  # A loop restarted on new code with cards in flight (CONVEYOR_ADOPT, below) keeps the lock it was given on fd 8:
  # those cards hold it too, so a lock taken anew would be refused. Only an fd 8 open on this run file is kept, and
  # flock still refuses one opened anew beside a running loop: the variable alone never passes the lock. No hook,
  # session, review or test under the loop is given fd 8 (git(), above, and the 8>&- where each starts), so one that
  # sets the variable opens the file anew and is refused.
  if [ -n "${CONVEYOR_ADOPT:-}" ] && [ /dev/fd/8 -ef "$STATE.run" ]; then adopt=$CONVEYOR_ADOPT; held=${CONVEYOR_KIDS:-}; else exec 8>>"$STATE.run"; fi; unset CONVEYOR_ADOPT CONVEYOR_KIDS
  flock -n 8 || { echo "conveyor: a loop is already running here; a second one would pass the builder cap" >&2; exit 1; }
  # The cards in flight of the loop this one restarted from, as "<pid> <card> <issue> <commit>" lines: still this
  # process's children, running the code they started on. They are this loop's own cards from here on.
  while read -r p c n k; do [ -z "$p" ] || { mine[$p]="$c $n"; took[$p]=$k; }; done <<<"$adopt"
  while read -r p k t; do [ -z "$p" ] || [ -z "${took[$p]:-}" ] || kids[$p]+="$k $t"$'\n'; done <<<"$held"
  # A loop killed during its push left them; this loop has said nothing yet. A push record whose process lives is a push
  # that runs (the Board's Push now, under the push lock): it stays.
  rm -f "$SAYS"; p=$(jq -r '.pid | numbers' "$PUSHING" 2>/dev/null) && [ -n "$p" ] && kill -0 "$p" 2>/dev/null || rm -f "$PUSHING"
  self=$(p_started $$)
  # A wake (wakeloop(), lib/control.sh, on a hold, a release or a filing) is URG: it kills the turn's timer, as the
  # turn's own end does, and sets nudged, which turnwait() reads. A trapped signal also cuts short a `wait` this shell
  # runs, so no wait of this shell's own may read its status as a job's (the cards' and other jobs' are subshells,
  # where the trap is not set).
  trap 'nudged=1; [ -z "${timer:-}" ] || kill "$timer" 2>/dev/null' URG
  speedretry
  [ -n "$OWN" ] || [ -z "$RAN" ] || FOLLOW=$serve
  if [ -n "$ONLY" ] && [ -z "$serve" ]; then [ "$left" -le 0 ] || lim=$left; left=-1; onlyreport; fi
  while :; do
    turnopen
    turnended
    turnside
    turncount
    [ -z "$old" ] || [ -z "$new" ] || turnrestart
    if [ -n "$old" ] && [ "$running" = 0 ] && [ -z "$pusher" ]; then
      # A `run` ends here; a card that landed after this turn's push check is owed a push first, as below.
      [ -n "$serve" ] || { [ -n "$nopack" ] || ! owed=$(owed) || [ "$owed" = "$tried" ] || continue; break; }
      # A pin, or a checkout's HEAD, first seen to move after this turn began (new is read at its start) is restarted
      # on at the next turn.
      [ -z "$FOLLOW" ] || continue
      enginepin p f || { p=''; f=''; }
      if installed "$p" ro && [ -f "$VERSIONS/$p/conveyor/conveyor.sh" ]; then
        machined "$VERSIONS/$p/conveyor/conveyor.sh" && continue
        echo "conveyor: the pack pins Conveyor commit $p, which has no machine's Conveyor: its cards would pass the machine's cap, pause and room; pin a newer commit" >&2; exit 1
      fi
      # Following the plugin's main with no commit taken yet: the loop waits, picking nothing, for take() to take one.
      if [ -n "$p" ] || [ -z "$f" ]; then
        echo "conveyor: the pack pins Conveyor commit ${p:-(none readable)}, which is not installed and verified: run conveyor install <commit>" >&2; exit 1
      fi
    fi
    turnask
    if [ -n "$asking" ]; then turnpick || continue; fi
    # Nothing was picked. With none of the loop's cards running and no push under way, the rule Merge PR idle
    # (idlemerge(), lib/push.sh, which checks the rule and the card records) is looked at once every IDLE seconds: a job
    # beside the cards, never counted as one, and given no run lock.
    if [ -n "$serve" ] && [ -z "$nopack" ] && [ -z "$new" ] && [ "$running" = 0 ] && [ -z "$pusher" ] && [ $((SECONDS - gtried)) -ge "$IDLE" ] \
      && { [ -z "$merger" ] || ! jobs -rp | grep -qx "$merger"; }; then
      gtried=$SECONDS; ( idlemerge ) 8>&- < /dev/null & merger=$!
    fi
    # A card that landed after this turn's push check is owed a push no turn has tried: one more turn makes it.
    if runends; then
      [ -n "$nopack" ] || ! owed=$(owed) || [ "$owed" = "$tried" ] || continue
      break
    fi
    # The wait (turnwait()) returns at once when a card has already ended; the next turn then counts it as gone.
    # A timer ends the wait too, even with every slot taken, so a push that is owed is tried on time; it is gone
    # again before the cards are next counted. Its length is worked out here, not in the timer: one ended while it
    # still worked that out wrote an error (a broken pipe) into the loop's output, at any turn.
    { [ "$running" != 0 ] || [ -n "$pusher" ] || [ -n "$waits" ]; } && t=$POLL || t=$IDLE
    sleep "$t" 8>&- & timer=$!
    # The timer is cleared once it is waited for: a wake then kills no other process given its pid.
    turnwait; kill "$timer" 2>/dev/null; wait "$timer" 2>/dev/null; timer=''
  done
  if [ -n "$old" ]; then echo "conveyor: this run ends: the pack pins another Conveyor commit; start it again from that commit's install"
  elif [ "$started" = 0 ] && [ -z "$tried" ]; then
    if [ "$cap" = 0 ]; then echo "conveyor: $why; nothing recorded" >&2; exit 1
    elif [ -n "$nocli" ]; then echo "conveyor: $nocli; nothing recorded" >&2; exit 1
    elif [ -n "$mhold" ]; then echo "conveyor: the machine hold stands; nothing recorded" >&2; exit 1
    elif [ "$now" = running ]; then echo "conveyor: no issue qualifies; nothing recorded"
    else echo "conveyor: the loop is $now (the control record); nothing recorded"; fi
  fi
  ! owed=$(owed) || { echo "conveyor: main (${owed##* }) is not pushed; the push line in the card records has the reason" >&2; exit 1; }
}
