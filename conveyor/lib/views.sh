# SPDX-License-Identifier: Apache-2.0
# Every reader stops at a line, named by its number, that is not one whole record of a known step, exactly as
# line() writes it: nothing is skipped and nothing half-understood is trusted. A push line (result fail) is not a
# step of its card: it is written under the card that landed last, names the commit that did not reach origin, and
# cards() leaves it out of the card's steps. The dashboard's rows need three
# fields a step may add: the issue title (picked), a session's or review's token split (usage), the kept folder (blocked).
# A card that landed on a NO-GO adds two more to its landed line: leftover (true) and followups (the issues filed).
# A follow-up that landed on the yes it inherited adds yesFrom to its landed line: the issue whose yes it was.
# A blocked line whose card's change was kept adds paths: the files it changed, the first 200.
# A closed line ends a card that changed nothing because its issue was already fixed: it has no commit to name. A
# closed line whose reason is SHUT ends a blocked card whose issue was closed, for whatever reason, while it waited
# on the owner (shut()): it fixed and landed nothing, and is counted with neither the landed cards nor the blocked ones.
# A test line (result pass or fail) adds sec, the seconds its run took, and a zero token split, so the dashboard
# prices the step at nothing instead of leaving the card unpriced.
# A review line of a card's change adds visible: the review's USER-VISIBLE answer ("no", or "yes: <what a customer or
# staff member would see>"), or "" when the review gave no single answer. A card blocked right after a review line
# whose visible starts "yes" is waiting on the owner's yes.
# The picked line of a card made by land-branch adds branch: the branch whose change the card lands.
# The picked line of a card of the loop adds created: when its issue was opened (the time it waited is the track's
# first step). A review line adds counts: its findings at each level (counts(), below). A start line adds of.
# A build, fix, rebase or review line adds model and effort: what that session or review ran on.
# Only the lines no check has passed yet are read: a pick and a snapshot each check, and the records only grow.
# $STATE.checked holds what checked whole: its bytes, its lines and the checksum of those bytes. A file whose first
# bytes no longer give that checksum (`retry` rewrote it, or a hand did) is read from its first line again. A check
# and a rewrite (moveout) never overlap: each holds the lock on $STATE.checked.lock, taken after the records' lock
# and never before it.
check() (
  flock 5 || exit 1
  n=0; l=0; sum=''
  { read -r n l sum < "$STATE.checked"; } 2>/dev/null
  size=$(($(wc -c < "$READ"))) || exit 1
  [[ "$n,$l" =~ ^[0-9]+,[0-9]+$ ]] && [ "$n" -le "$size" ] && [ "$(head -c "$n" "$READ" | cksum)" = "$sum" ] || { n=0; l=0; }
  [ "$size" -gt "$n" ] || exit 0
  new() { tail -c +$((n + 1)) "$READ" | head -c $((size - n)); }
  # A last line with no newline is not read, so neither passed nor failed: the check does not hold the records' lock,
  # and a long line can reach the file in more than one write. The next check reads it once it is whole.
  # Its whole lines: as many as it has new lines, counted once (#532).
  lines=$(new | wc -l)
  size=$((n + $(new | head -n "$lines" | wc -c)))
  [ "$size" -gt "$n" ] || exit 0
  bad=$(new | jq -Rrn -f "$HERE/jq/check.jq" | head -n 1)
  [ -z "$bad" ] || { echo "conveyor: $STATE line $((l + bad)) is not a whole record of a known step; stopping" >&2; exit 1; }
  { echo "$size $((l + lines)) $(head -c "$size" "$READ" | cksum)" > "$STATE.checked.new" && mv -f "$STATE.checked.new" "$STATE.checked"; } 2>/dev/null
  exit 0
) 5>>"$STATE.checked.lock"

# A reader that holds no records' lock reads only their whole lines, from a copy (READ, READ_OLD, removed when the
# script exits) the state database gives in one call: a last line with no newline may still be being written, as
# check() says.
# shellcheck disable=SC2064 # d is local: the trap must hold its value now, as it runs after this function returns
whole() {
  local d; d=$(mktemp -d) && trap "rm -rf '$d'" EXIT && stdb ask -o "$d/records" lines cards -- -o "$d/old" lines retried \
    && READ=$d/records && READ_OLD=$d/old
}

# The dashboard's one question, asked over ssh from the machine it runs on (dashboard.sh, conveyor): the cards by
# end (a card that closed its issue as already fixed is counted with the landed ones; its row's step is "closed"; so
# is that of a card whose issue was closed while it was blocked, x.blockedAt, which is counted with neither),
# and one row for each open card and each card closed in the last day.
# A row's step is the one in progress, not the last one recorded. It is named from the lines written when a step
# ends, the marks apart (start, filed, pushed, issue: README.md): card() starts the next step straight
# after each such line, so the step in progress is the one that follows the card's last one and it began at that
# line's time (stepAt). stage is its place in the band: 0 picked, 1 build, 2 review 1, 3 fix,
# 4 a later review, 5 landing (after a GO, or after the last review's NO-GO while its follow-ups are filed); a
# closed card keeps the stage it ended in. A card rebuilt after a landing conflict has a `rebase` line, written
# when that session ends: the session itself runs under "landing", the review after it is a later review, and that
# review is the last one, so its NO-GO is followed by the landing, not by a fix. The changed tests run under
# "landing": a `test` line that passed is followed by the landing, one that failed by a fix, and the review after that
# fix is a last one too. A card made by land-branch has no build: its brief line is followed by review 1.
# A card landing from a kept patch (its worktree line says so) has no build and no review: its brief line is
# followed by the changed tests; one whose kept patch is held against the condition of the owner's yes has no build: its
# brief line is followed by review 1. Each finished session, review or test run is in steps with its seconds, fresh tokens and token split.
# The answer also names what only this checkout knows: the models in force for the two seats (its control record's;
# the dashboard labels this record's cards with them, and prices a step with them when its line names no
# model of its own; not with its own machine's), and its GitHub
# address (an issue link opens this repo's issue). An open card whose picked line holds no title (picked before
# titles were recorded) gets it from one gh read; a read that fails leaves the title empty until the next cycle.
# rows() is every card as such a row, whenever it ended; cards() and snapshot() both read it, so they cannot name a
# card's step differently. A row's x holds what only the snapshot shows: at (the step in progress as the snapshot
# names it), review (the number of the review in progress, else null), the card's fresh tokens so far, when it ended
# (endAt, null while open), the follow-ups its landed line names, its last review's USER-VISIBLE answer and the
# branch a land-branch card lands (null for a card of the loop), and log: every line of the card in order, marks
# included, cut to what the reviews list and the track are built from (step, of, result, time, counts, created, n: how
# many follow-ups a filed line names, reason: why an issue line failed, stop: on a blocked line, what its reason says of where the card stopped (worktree,
# deps, brief: the steps with no start line; yes: it waits for the owner's yes and failed nothing), took: the seconds since
# the card's line before it, which for a step with a start line is the time the step ran).
rows() { # [records file: the retried file's lines are card records too]
  jq -cs --argjson max "$MAX_REVIEWS" --arg nodeps "$NODEPS" --arg yes "$YES" --arg shut "$SHUT" -f "$HERE/jq/rows.jq" "${1:-$READ}"
}
cards() {
  local out models url n t titles='{}'
  check && out=$(rows | jq -c '{landed: (map(select((.step | IN("landed", "closed")) and .x.blockedAt == null)) | length), blocked: (map(select(.step == "blocked")) | length),
       open: (map(select(.result == "")) | length), cards: map(select(.result == "" or (.stepAt | fromdate) > now - 86400) | del(.x))}') || return 1
  models=$(inforce)
  url=$(git -C "$MAIN" remote get-url "$REMOTE" 2>/dev/null | sed -nE 's#^(https://([^/@]+@)?github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#https://github.com/\3#p' | sed 's/\.git$//')
  for n in $(jq -r '.cards[] | select(.result == "" and .title == "") | .issue' <<<"$out"); do
    t=$(timeout 5 gh issue view "$n" --json title 2>/dev/null | jq -r '.title // "" | .[0:200]' 2>/dev/null) && [ -n "$t" ] || continue
    titles=$(jq -c --arg n "$n" --arg t "$t" '.[$n] = $t' <<<"$titles")
  done
  jq -c --argjson m "$models" --arg u "$url" --argjson t "$titles" --argjson red "$(redtitles)" '. + {models: $m, repoUrl: (if $u == "" then null else $u end)}
    | .cards |= map(.title = ($red[.card] // (if .title == "" then $t[.issue | tostring] // "" else .title end)))' <<<"$out"
}

# The health record (the cards are watched for when they are stuck). One JSON object, asked
# for over ssh once a minute by the Foreman's watcher, which wakes the Foreman
# on a new problem. It holds: time (now, so the reader needs no clock of its own; CONVEYOR_NOW, epoch seconds, stands
# for now when set: the tests' clock); loop (a `run` or `serve` holds this
# checkout's loop lock; asking takes that lock for an instant); commit (the Conveyor commit that loop started on, as
# its loop.json names it; null with no loop, or one that names none); newest (the time of the last line in the records);
# blocked (card, issue, reason, since) and, apart from those, waiting: the cards blocked for the owner's yes to a visible
# change; stuck (card, issue, step: the last one recorded or begun, since): every open card with neither a new line
# nor, from the step it is running, any output (its live record's `last`, which a card waiting at its claim brings up
# to date each poll, and a session its `progress`: a file or commit of its worktree, watch(); a test run's, its start and
# its cases beginning or ending) for STUCK seconds;
# every open card running a step again after the engine ended the step before it for no progress (since: when its
# progress stopped; did: "ended and retried", on any stuck entry of such a card); and at once every open
# card whose process (the pid and start its worktree line names) is gone, as nothing is left to write its line (but for
# a card in its land step while the loop runs: the loop lands it, and STUCK holds) (step
# waiting and waitsOn for a card waiting on a same-file card, never the landing it waits to begin), and
# every open card that has waited STUCK seconds on a same-file card that is not alive (not on the belt, or its process
# gone: the wait never ends) (step waiting, since: when
# the wait began, waitsOn: that card's {card, issue, state}, as the belt's), every open card whose session (build,
# fix, rebase) has had no output for SESSION_STUCK seconds, every open card that has waited on other cards for more
# than WAIT_LIMIT minutes in all (step waiting, since and waitsOn as above, waitedMin: the whole minutes of all its
# waits, waitedOn: each card it waited on, in order, as waitsOn), and every open card whose test step has a case
# running for CASE_STUCK seconds (step test, cases: their names, since: when the first of them started; testcases()); waitingOnCard (card, issue, since: when the
# wait began, waitsOn as stuck's): every open card waiting at its claim (the live record of the step it is running names
# the card it waits on and was brought up to date within STUCK seconds); unpushed (card, issue, sha, since): the landed commits in main that neither the last push that worked nor
# origin's main as last seen here holds; pushError (time, sha, reason, kind: check or transport, check: the check that
# failed, card and issue: the landing it was pushed for; the last failed push since the oldest of those landed, else null), pushFailingSince (the first such failure, else null) and pushFails (how many such failures); pushing (the push in progress,
# {since, sha}, while the loop's push job runs, else null; a landing during it waits for the next push); gh (signed in); diskFreeKb (free space
# on the cards folder, null when df gives none); refused (card, issue, reason: "refused full run: <why>", since: the
# line's time): each test line of the last 24 hours whose run refused a full run (tests()), for the Foreman's watcher;
# untimed (UNTIMED, below): how many of the last card test runs recorded no test times, 0 when one did; routes: each
# Claude route, subscription and proxy, with its state (routesnow()). Every object of it that names a main-red fix card
# (card) also has name, "Main is red (<commit>)", as rows.jq names it: the card has no issue (issue 0) to be shown by.
# Records that do not check give no record: the reason and exit 1.
# It also says what the control record makes of the loop: state (running, paused, stopped, "paused by guard":
# the weekly limit reading is at or over the guard, or "control record unreadable"; a loop that is not running picks
# nothing, whatever `loop` says of there being one; the running loop's own "control record unreadable" stands over
# this code's reading) and reason (why the record is unreadable, or, paused by a sign-in failure, that failure and what
# to run: the record's signin; null otherwise), guard: at (the guard's percent, null for none), reading and
# readAt (the reading it is held against, null when no guard is set or there is no reading) and missing (true when a
# guard is set and there is no reading: the guard then pauses nothing), start (where new issues start: queue or held;
# null when the record does not read), builderCap (the cap in force), models and
# efforts (the ones in force, {claude, codex}: the next session's and the next review's), and homes (plan section 6).
# homes: each setting the loop reads, by its name in the pack (tunables.poll, models.allowed, rulings.log, checks)
# or the control record (control.cap, control.model, control.reviewer), as {value: the one in force, home: "pack",
# "schema default", "control record", "seed" (the control record leaves it to the seed, CTL0), or "none" for a pack
# field left out that has no default}.
homes() { # <control record>
  local a; packget models.allowed a 2>/dev/null || a=null
  jq -c --slurpfile p "$PACK" --slurpfile s "$HERE/schema/pack.schema.json" --argjson c "$1" --argjson e "$EFFORTS" \
      --argjson d "$CAP0" "$SETTINGS"'
    (first(seatnow("builder"; $c)) // null) as $b | (first(seatnow("reviewer"; $c)) // null) as $r | settings($c; $e; {}) as $m
    | $p[0] as $p | $s[0].properties as $sp
    | def seat($k; $v): {value: $v, home: (if $m[$k].modelFrom == "control" then "control record" else "seed" end)};
      def f($k; $v; $d): {($k): (if $v != null then {value: $v, home: "pack"} elif $d != null then {value: $d, home: "schema default"} else {value: null, home: "none"} end)};
    [($sp.tunables.properties | to_entries[] | f("tunables.\(.key)"; $p.tunables[.key]; .value.default)),
     f("models.allowed"; $p.models.allowed; null), f("rulings.log"; $p.rulings.log; null), f("checks"; $p.checks; $sp.checks.default),
     {"control.cap": (if $c.cap != null then {value: $c.cap, home: "control record"} else {value: $d, home: "seed"} end),
      "control.model": seat("builder"; $b), "control.reviewer": seat("reviewer"; $r)}] | add' <<<"$a"
}
live() { # every live record there is, as one object by card
  local f
  for f in "$CARDS"/*.live; do [ ! -e "$f" ] || jq -c --arg c "$(basename "$f" .live)" '{($c): .}' "$f" 2>/dev/null; done | jq -cs 'add // {}'
}
aways() { # each card that gave way (giveway()): {to: the issue it gave way to, fixing: for the fix of its failed tests}, as one object by card
  local f
  for f in "$CARDS"/*.claim; do [ ! -e "$f" ] || jq -c --arg c "$(basename "$f" .claim)" 'select(.away == true and (.to | type) == "number") | {($c): {to, fixing: (.fixing == true)}}' "$f" 2>/dev/null; done | jq -cs 'add // {}'
}
# cycles: every set of open issues that depend on each other, lowest number first in each; those issues are
# never picked, nor is any issue that waits on one of them. null when gh did not list the open issues.
# before: the open issues waiting for the owner's yes before their build (SEE's before; none while the control
# record's rule "visible changes need the owner's yes" is off) with no card, and that
# nothing else keeps off the belt (awaiting-deploy, a hold of the
# control record, an area label never built): issue, title, section (the whole text of the section, never cut: the owner
# approves all of it, and the build is held to all of it; it goes to jq as a file, never as an argument, so no
# length of it passes the kernel's limit on one argument), since (when the issue was opened), lowest number first.
# null when gh did not list the open issues.
# untimed (on records slurped): the project's last card test runs that recorded no test times, so its test command
# prints no `TESTRUN sec` lines (README.md, The CPU budget of a test file): of the last 5 card test runs that ran tests
# (pass or fail; no batch's reused line, no refused full run, none that selected no file), how many, when none of them
# recorded a file's CPU seconds (times); 0 when one did, or there is none. health and doctor say so.
UNTIMED='def untimed: [.[] | select(.step == "test" and (.result | IN("pass", "fail")) and .reused != true and (.refused | type) != "string"
    and .ended != "nothing selected" and (.selected.files // 1) > 0)] | .[-5:]
  | if length > 0 and all(.[]; .times | type != "object") then length else 0 end;'
health() {
  local loop=true gh=false free a not=() lv c r=null cap cyc=null pu=null bf=null st why='' said gone cm rm mc mn ld
  check && lv=${LIVEJSON:-$(live)} || return 1
  gone=$(jq -rs '[group_by(.card)[] | select(all(.step | IN("landed", "closed", "blocked") | not))
      | map(select(.step == "worktree" and (.pid | type) == "number")) | last | select(.) | "\(.card)\t\(.pid)\t\(.started // "")"] | .[]' "$READ" \
    | while IFS=$'\t' read -r k p t; do p_alive "$p" "$t" || printf '%s\n' "$k"; done | jq -Rcs 'split("\n") | map(select(. != ""))') || return 1
  c=$(ctl 2>/dev/null) || { c=null; why=$(notwhole); }
  if a=${ISSUESJSON:-$(openissues number,title,body,labels,createdAt 2>/dev/null)} && [ "$a" != null ]; then
    cyc=$(jq -c --slurpfile cards "$READ" "$DEPS"' cycles($cards)' <<<"$a" 2>/dev/null) && [ -n "$cyc" ] || cyc=null
    bf=$(jq -c --slurpfile cards "$READ" --argjson c "$c" --arg built "$BUILT" \
        --arg area "$AREA" --argjson np "$NONPRODUCT" "$SEE"'
      ($cards | map(.issue)) as $taken | ($c // {}) as $c
      | [.[] | (.labels // [] | map(.name)) as $l
         | select($c.rules.visible != false and before($area; $np) and (.number | IN($taken[]) | not) and ($l | index($built) | not)
             and (.number | IN(($c.held // [])[]) | not) and ($l | any(IN(($c.rules.never // [])[])) | not))
         | {issue: .number, title: ((.title // "")[0:200]), section: section, since: (.createdAt // null)}] | sort_by(.issue)' <<<"$a" 2>/dev/null) \
      && [ -n "$bf" ] || bf=null
  fi
  cap=$(capnow "$c") || cap=null
  # The guard's reading is that of the accounts the next card will use.
  [ "$(jq -r .guard <<<"$c")" = null ] || r=$(guardread "$c" ask); [ -n "$r" ] || r=null
  ( flock -n 9 ) 9>>"$STATE.run" && loop=false
  st=$(state "$c" "$(jq -r '.pct // empty' <<<"$r")")
  # A loop a sign-in failure paused (signinpause()) says why, and what to run.
  [ "$st" != paused ] || why=$(jq -r '.signin // ""' <<<"$c")
  if [ "$loop" = true ] && said=$(jq -ce 'select(.state == "control record unreadable" and (.pid | type == "number")) | {pid, reason}' "$SAYS" 2>/dev/null) \
    && kill -0 "$(jq -r .pid <<<"$said")" 2>/dev/null; then st='control record unreadable'; why=$(jq -r '.reason // ""' <<<"$said"); fi
  [ "$loop" = true ] && cm=$(jq -ce '.commit | strings' "$SAYS" 2>/dev/null) || cm=null
  if [ "$loop" = true ] && pu=$(jq -ce 'select((.pid | type == "number") and (.since | type == "string")) | {pid, since, sha}' "$PUSHING" 2>/dev/null) \
    && kill -0 "$(jq -r .pid <<<"$pu")" 2>/dev/null; then pu=$(jq -c 'del(.pid)' <<<"$pu"); else pu=null; fi
  ghok && gh=true
  # The card the machine holds back (room()), while the loop runs: {issue, reason, since}.
  rm=null; [ "$loop" != true ] || rm=$(jq -ce 'select((.issue | type == "number") and (.reason | type == "string"))' "$ROOMF" 2>/dev/null) || rm=null
  free=$(df -Pk "$CARDS" 2>/dev/null | awk 'NR == 2 { print $4 }'); [[ $free =~ ^[0-9]+$ ]] || free=null
  mc=$(mhost); mc=${mc:-null}
  # The machine now, for the Board's Load limit: its cores and 1-minute load (roomnow(), as the room reads it); null for one not read.
  read -r ld _ <<<"$(roomnow)"; mn=$(jq -cn --arg c "$(getconf _NPROCESSORS_ONLN 2>/dev/null)" --arg l "${ld:-}" '{cores: ($c | tonumber? // null), load: ($l | tonumber? // null)}')
  for a in "$(pushed)" "refs/remotes/$REMOTE/$BRANCH"; do
    [ -z "$a" ] || ! git rev-parse -q --verify "$a^{commit}" >/dev/null 2>&1 || not+=("$a")
  done
  jq -cs --argjson loop "$loop" --argjson gh "$gh" --argjson free "$free" --argjson stuck "$STUCK" --argjson sstuck "$SESSION_STUCK" --argjson casestuck "$CASE_STUCK" --argjson waitlimit "$WAIT_LIMIT" --argjson gone "$gone" --argjson live "${lv:-{\}}" \
    --arg state "$st" --arg why "$why" --argjson commit "$cm" --argjson ctl "$c" --argjson r "$r" --arg yes "$YES" \
    --argjson cap "$cap" --arg repo "$REPO" --argjson room "$rm" --argjson machine "$mc" --argjson mnow "$mn" --argjson models "$(inforce '' "$c")" --argjson efforts "$(inforce efforts "$c")" --argjson cycles "$cyc" --slurpfile before <(printf '%s\n' "$bf") --argjson pushing "$pu" --argjson homes "$(homes "$c")" --argjson routes "$(routesnow)" \
    --slurpfile old "$READ_OLD" --rawfile ahead <(git rev-list "refs/heads/$BRANCH" --not "${not[@]}" 2>/dev/null) "$UNTIMED"'
    (($ENV.CONVEYOR_NOW // "" | tonumber?) // now) as $now
    | ($ahead | split("\n") | map(select(. != "")) | INDEX(.)) as $ahead
    | ([.[], $old[] | select(.step == "picked" and (.mainRed | type) == "string") | {key: .card, value: "Main is red (\(.mainRed[0:12]))"}] | from_entries) as $names
    | [.[] | select(.step == "landed" and $ahead[.sha]) | {card, issue, sha, since: .time}] as $un
    | [.[] | select(.step == "push" and .result == "fail" and $un[0] and .time >= $un[0].since)] as $fail
    | [map(select(.step != "push")) | group_by(.card)[]
        # Its closing line as rows.jq names it: a blocked line a later landed, pushed or closed line of the record follows does not count.
        | {card: .[0].card, issue: .[0].issue, last: last, end: (map(select(.step | IN("landed", "closed", "blocked", "pushed"))) | . as $e
             | [range(length) as $i | $e[$i] | select(.step != "pushed" and (.step != "blocked" or ($e[$i + 1:] | all(.step == "blocked"))))] | last),
           out: (last as $l | [$live[.[0].card] | select(. != null and $l.step == "start" and $l.of == .step) | [.last, .progress] | map(strings) | max | strings] | first)}] as $c
    | ($c | map(select(.end.step == "blocked") | {card, issue, reason: .end.reason, since: .end.time})) as $b
    # The card a card waits on, its issue and where it is: its step on the belt, blocked, landed, closed, queued (`retry`
    # gave its issue back) or gone (in no record).
    | def holder($h): ([$c[] | select(.card == $h)] | first) as $r | ([$old[] | select(.card == $h)] | first) as $o
        | {card: $h, issue: ($r.issue // $o.issue // ($h | capture("-(?<n>[0-9]+)$").n | tonumber? ) // null),
           state: (if $r != null then (if $r.end then $r.end.step else $r.last | if .step == "start" then .of else .step end end) elif $o then "queued" else "gone" end)};
    [$c[] | select(.end == null) | .card] as $open
    # A card in its land step (its wait for the land turn, and the land; its landed line closes it, so its push is
    # never here), while the loop runs, is not gone for its session process having ended: the loop does that work.
    # It is held to STUCK from its last line, as any step.
    | [$c[] | select((.card | IN($gone[])) and ($loop and .last.step == "start" and .last.of == "land" | not)) | .card] as $gone
    # A card waiting at its claim: the live record of the step it is running names the card it waits on and was brought
    # up to date within STUCK.
    | def atclaim: $live[.card] as $v | .last.step == "start" and .last.of == $v.step
        and ($v.waits.on | type) == "string" and ($v.last | type) == "string" and $now - ($v.last | fromdate) < $stuck;
      # A holder that is alive: on the belt, its process there.
      def alive($h): ($h | IN($open[])) and ($h | IN($gone[]) | not);
      # A stuck list with more entries: one for a card the list holds already adds what it says to the entry of that card.
      def also($more): reduce $more[] as $m (.; (map(.card) | index($m.card)) as $i | if $i == null then . + [$m] else .[$i] += $m end);
    {time: ($now | todate), repo: $repo, loop: $loop, room: $room, machine: $machine, machineNow: $mnow, commit: $commit, state: $state, reason: (if $why == "" then null else $why end),
       guard: {at: $ctl.guard, reading: $r.pct, readAt: $r.time, missing: ($ctl.guard != null and $r == null)}, start: $ctl.start, newest: (last.time // null),
       blocked: ($b | map(select(.reason | startswith($yes) | not))), waiting: ($b | map(select(.reason | startswith($yes)))),
       stuck: ($c | map(select(.end == null) | . + {since: ([.last.time, .out // ""] | max)}
           # A session (build, fix, rebase) that says nothing is listed after SESSION_STUCK, when that is sooner.
           | select((.card | IN($gone[])) or $now - (.since | fromdate) >= (if .last.step == "start" and (.last.of | IN("build", "fix", "rebase")) then [$stuck, $sstuck] | min else $stuck end))
         | ($live[.card].waits.on // null) as $h
         | {card, issue, step: (if $h then "waiting" else .last | if .step == "start" then .of else .step end end), since} + (if $h then {waitsOn: holder($h)} else {} end))
         # A step the engine ended for making no progress, run once more (watch()): stuck since its progress stopped,
         # for as long as the run after it goes on.
         | . + [$c[] | select(.end == null and (.card | IN($gone[]) | not)) | $live[.card] as $v
             | select(($v.stalled | type) == "string" and .last.step == "start" and .last.of == $v.step) | {card, issue, step: $v.step, since: $v.stalled}]
         | group_by(.card) | map(last + (if ($live[.[0].card].stalled | type) == "string" and (.[0].card | IN($gone[]) | not) then {did: "ended and retried"} else {} end))
         | . as $s
         | . + [$c[] | select(.end == null and (.card | IN($s[].card) | not)) | $live[.card] as $v | ($v.waits.on // null) as $h
             | select($h != null and (alive($h) | not) and ($v.at | type) == "string" and $now - ($v.at | fromdate) >= $stuck)
             | {card, issue, step: "waiting", since: $v.at, waitsOn: holder($h)}]
         # A card that has waited on other cards for more than WAIT_LIMIT minutes in all, each holder alive: its waits
         # that ended (waited.before of the live record, seconds) and the one it is in. One stuck already (its holder
         # gone, say) is said to have waited that long too.
         | also([$c[] | select(.end == null) | $live[.card] as $v | ($v.waits.on // null) as $h
             | select($h != null and .last.step == "start" and .last.of == $v.step and ($v.at | type) == "string")
             | ((($v.waited.before | numbers) // 0) + $now - ($v.at | fromdate)) as $w | select($w > $waitlimit * 60)
             | {card, issue, step: "waiting", since: $v.at, waitsOn: holder($h), waitedMin: ($w / 60 | floor),
                waitedOn: [(($v.waited.behind | arrays) // [$h])[] | strings | holder(.)]}])
         # A test step with a case that has run for CASE_STUCK, whatever the other cases print, and when none prints.
         | also([$c[] | select(.end == null and .last.step == "start" and .last.of == "test") | $live[.card] as $v
             | [select($v.step == "test") | $v.cases | arrays | .[] | objects | select((.name | type) == "string" and (.since | type) == "string" and $now - (.since | fromdate) >= $casestuck)] as $k
             | select($k != []) | {card, issue, step: "test", since: ($k | map(.since) | min), cases: ($k | map(.name))}])),
       waitingOnCard: [$c[] | select(.end == null and atclaim) | $live[.card] as $v | {card, issue, since: $v.at, waitsOn: holder($v.waits.on)}],
       unpushed: $un, pushError: ($fail | last | if . then {time, sha, reason, kind: (.kind // null), check: (.check // null), card, issue} else null end), pushFailingSince: ($fail[0].time // null), pushFails: ($fail | length), pushing: $pushing,
       gh: $gh, diskFreeKb: $free, builderCap: $cap, models: $models, efforts: $efforts, cycles: $cycles, before: $before[0], homes: $homes,
       refused: [.[] | select(.step == "test" and (.refused | type) == "string" and $now - (.time | fromdate) < 86400) | {card, issue, reason: .refused, since: .time}],
       untimed: untimed, routes: $routes}
    | walk(if type == "object" and (.card | type) == "string" and $names[.card] then .name = $names[.card] else . end)' "$READ"
}
