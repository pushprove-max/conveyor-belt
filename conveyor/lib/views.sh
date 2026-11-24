# SPDX-License-Identifier: Apache-2.0
# Every reader reads only whole records of a known step, exactly as line() writes them: nothing half-understood is
# trusted. A line that is not one is set aside before anything reads it (check(), quarantine()), so one bad line
# never stops the loop or the snapshot. A push line (result fail) is not a
# step of its card: it is written under the card that landed last, names the commit that did not reach origin, and
# cards() leaves it out of the card's steps. The dashboard's rows need three
# fields a step may add: the issue title (picked), a session's or review's token split (usage), the kept folder (blocked).
# A card that landed on a NO-GO adds two more to its landed line: leftover (true) and followups (the issues filed).
# A follow-up that landed on the yes it inherited adds yesFrom to its landed line: the issue whose yes it was.
# A blocked line whose card's change was kept adds paths: the files it changed, the first 200.
# A closed line ends a card that changed nothing because its issue was already fixed: it has no commit to name. A
# closed line whose reason is SHUT ends a blocked card whose issue was closed, for whatever reason, while it waited
# on the owner (shut()), and one whose reason is OWNSHUT a card the owner shut: it fixed and landed nothing, and is counted with neither the landed cards nor the blocked ones.
# A test line (result pass or fail) adds sec, the seconds its run took, and a zero token split, so the dashboard
# prices the step at nothing instead of leaving the card unpriced.
# A review line of a card's change adds visible: the review's USER-VISIBLE answer ("no", or "yes: <what a customer or
# staff member would see>"), or "" when the review gave no single answer. A card blocked right after a review line
# whose visible starts "yes" is waiting on the owner's yes. A review line whose review named rollout actions (ROLLOUT
# lines, lib/prompts.sh) adds rollout: [{action, fails, place}], as does a GO of the whole change, [] when it named
# none (card()); a landed line adds the card's own (card()).
# The picked line of a card made by land-branch adds branch: the branch whose change the card lands.
# The picked line of a card of the loop adds created: when its issue was opened (the time it waited is the track's
# first step). A review line adds counts: its findings at each level (donewhen.sh counts()). A start line adds of.
# A build, fix, rebase or review line adds model and effort: what that session or review ran on.
# Only the lines no check has passed yet are read: a pick and a snapshot each check, and the records only grow.
# $STATE.checked holds what checked whole: its bytes, its lines and the checksum of those bytes. A file whose first
# bytes no longer give that checksum (`retry` rewrote it, or a hand did) is read from its first line again. A check
# and a rewrite (moveout) never overlap: each holds the lock on $STATE.checked.lock, taken after the records' lock
# and never before it.
# A line the check refuses (jq/check.jq names the field it refused) is set aside, not read: quarantine() moves it out
# of the card records to $QUARANTINE, under the records' lock (taken here, for LOCKLIMIT seconds at most, unless the
# caller holds it: LOCKHELD), and health names it until the owner deals with it. A copy a reader holds (READ, not STATE: whole(), the snapshot)
# drops the same lines, and the copy's lineage (READG: the snapshot's copy is then no longer the one it keeps,
# snapcopy()). The check then reads the rest again; a line still refused after three tries
# stops the reader.
check() {
  local rc
  for _ in 1 2 3; do
    checkpart; rc=$?
    [ $rc = 3 ] || return $rc
    if [ -n "${LOCKHELD:-}" ]; then quarantine; else lockedfor "the set-aside of a bad line" quarantine; fi || return 1
    [ "$READ" = "$STATE" ] || { dropbad "$READ" && READG=''; } || return 1
  done
  echo "conveyor: $READ still holds a line that is not a whole record of a known step after it was set aside; stopping" >&2
  return 1
}
# The lines of a copy of the card records that the check refuses, dropped from it.
dropbad() { # <copy>
  local bad
  bad=$(jq -Rrn -f "$HERE/jq/check.jq" < "$1") || return 1
  [ -z "$bad" ] || { awk -F'\t' 'NR == FNR { b[$1]; next } !(FNR in b)' <(printf '%s\n' "$bad") "$1" > "$1.kept" && mv -f "$1.kept" "$1"; }
}
# Under the records' lock: every line of the card records the check refuses moves to $QUARANTINE as {line (its number
# in the records), field (the one the check refused), time, record (the line as it was)}, and the records are rewritten
# without it (as moveout() rewrites them, under the lock on $STATE.checked.lock). Each is named on stderr.
quarantine() {
  local bad
  stdb ask -o "$STATE.qall" lines cards && bad=$(jq -Rrn -f "$HERE/jq/check.jq" < "$STATE.qall") \
    || { rm -f "$STATE.qall"; echo "conveyor: cannot read the card records to set a bad line aside; nothing changed" >&2; return 1; }
  [ -n "$bad" ] || { rm -f "$STATE.qall"; return 0; }
  awk -F'\t' 'NR == FNR { b[$1] = $2; next } FNR in b { print FNR "\t" b[FNR] "\t" $0 }' <(printf '%s\n' "$bad") "$STATE.qall" \
    | jq -cR --arg at "$(date -u +%FT%TZ)" 'split("\t") | {line: (.[0] | tonumber), field: .[1], time: $at, record: (.[2:] | join("\t"))}' >> "$QUARANTINE" \
    && awk -F'\t' 'NR == FNR { b[$1]; next } !(FNR in b)' <(printf '%s\n' "$bad") "$STATE.qall" > "$STATE.qrest" \
    || { rm -f "$STATE.qall" "$STATE.qrest"; echo "conveyor: cannot write $QUARANTINE; the card records are unchanged" >&2; return 1; }
  ( flock 5 || exit 1; stdb rewrite cards < "$STATE.qrest" ) 5>>"$STATE.checked.lock" \
    || { echo "conveyor: the card records were not rewritten whole; what they held is in $STATE.qall" >&2; return 1; }
  rm -f "$STATE.qall" "$STATE.qrest"
  while IFS=$'\t' read -r l f; do echo "conveyor: $STATE line $l is not a whole record of a known step (the check refused $f); it is set aside in $QUARANTINE" >&2; done <<<"$bad"
}
# 3: a whole line the check refuses.
# A copy with a lineage (the snapshot's: READG, `<lineage> <bytes>`, snapcopy(), lib/snapshot.sh) is not read to sum
# it: its first bytes are the ones checked while the lineage is the same. What checked of it is kept apart
# ($STATE.copy.checked, the lineage in place of the sum), so a check of the records themselves and one of the copy,
# each in turn, never make the other read the whole file again.
checkpart() (
  flock 5 || exit 1
  n=0; l=0; sum=''; g=${READG:-}; size=${g#* }; g=${g% *}; cf=$STATE.checked
  if [[ $g == g* && $size =~ ^[0-9]+$ ]]; then cf=$STATE.copy.checked; else g=''; size=$(($(wc -c < "$READ"))) || exit 1; fi
  { read -r n l sum < "$cf"; } 2>/dev/null
  [[ "$n,$l" =~ ^[0-9]+,[0-9]+$ ]] && [ "$n" -le "$size" ] \
    && if [ -n "$g" ]; then [ "$sum" = "$g" ]; else [ "$(head -c "$n" "$READ" | cksum)" = "$sum" ]; fi || { n=0; l=0; }
  [ "$size" -gt "$n" ] || exit 0
  new() { tail -c +$((n + 1)) "$READ" | head -c $((size - n)); }
  # A last line with no newline is not read, so neither passed nor failed: the check does not hold the records' lock,
  # and a long line can reach the file in more than one write. The next check reads it once it is whole.
  # Its whole lines: as many as it has new lines, counted once (#532).
  lines=$(new | wc -l)
  size=$((n + $(new | head -n "$lines" | wc -c)))
  [ "$size" -gt "$n" ] || exit 0
  bad=$(new | jq -Rrn -f "$HERE/jq/check.jq" | head -n 1)
  [ -z "$bad" ] || exit 3
  { echo "$size $((l + lines)) ${g:-$(head -c "$size" "$READ" | cksum)}" > "$cf.new" && mv -f "$cf.new" "$cf"; } 2>/dev/null
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
# (endAt, null while open), the follow-ups and rollout actions its landed line names, its last review's USER-VISIBLE answer and the
# branch a land-branch card lands (null for a card of the loop), and log: every line of the card in order, marks
# included, cut to what the reviews list and the track are built from (step, of, result, time, counts, created, n: how
# many follow-ups a filed line names, reason: why an issue line failed, stop: on a blocked line, what its reason says of where the card stopped (worktree,
# deps, brief: the steps with no start line; yes: it waits for the owner's yes and failed nothing), took: the seconds since
# the card's line before it, which for a step with a start line is the time the step ran).
# A second argument names a file of card states (rows.jq: what a card's row needs of the lines it read; snaprows(),
# lib/snapshot.sh, keeps them): the first file then holds the lines past the ones each state read, and the answer is
# [row, state] of each card that file names.
rows() { # [records file: the retried file's lines are card records too] [file of card states]
  local states=${2:-}
  jq -cs --argjson max "$MAX_REVIEWS" --arg nodeps "$NODEPS" --arg yes "$YES" --arg lintyes "$LINTYES" --arg shut "$SHUT" --arg ownshut "$OWNSHUT" ${states:+--slurpfile states "$states"} -f "$HERE/jq/rows.jq" "${1:-$READ}"
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
  jq -c --argjson m "$models" --arg u "$url" --argjson t "$titles" --argjson red "$(redtitles)" '. + {models: $m.models, repoUrl: (if $u == "" then null else $u end)}
    | .cards |= map(.title = ($red[.card] // (if .title == "" then $t[.issue | tostring] // "" else .title end)))' <<<"$out"
}

# The health record (the cards are watched for when they are stuck). One JSON object, asked
# for over ssh once a minute by the Foreman's watcher, which wakes the Foreman
# on a new problem. It holds: time (now, so the reader needs no clock of its own; CONVEYOR_NOW, epoch seconds, stands
# for now when set: the tests' clock); loop (a `run` or `serve` holds this
# checkout's loop lock; asking takes that lock for an instant); commit (the Conveyor commit that loop started on, as
# its loop.json names it; null with no loop, or one that names none); newest (the time of the last line in the records);
# blocked (card, issue, reason, since; reviewRetried: true on a card that came after review-retry gave its issue back) and, apart from those, waiting: the cards blocked for the owner's yes to a visible
# change or a lint policy change; stuck (card, issue, step: the last one recorded or begun, since): every open card with neither a new line
# nor, from the step it is running, any output (its live record's `last`, which a card waiting at its claim brings up
# to date each poll, and a session its `progress`: a file or commit of its worktree, watch(); a test run's, its start and
# its cases beginning or ending; in its test step, its .test file and the run again of its failed tests on main,
# testouts(); between two steps, its bug-card check's run on main's code, proofs()) for STUCK seconds;
# every open card running a step again after the engine ended the step before it for no progress (since: when its
# progress stopped; did: "ended and retried", on any stuck entry of such a card); and at once every open
# card whose process (the pid and start its worktree line names) is gone, as nothing is left to write its line (but for
# a card in its land step while the loop runs: the loop lands it, and STUCK holds), or whose process or engine is
# stopped by a stop signal (state T), as nothing of it moves (stopped: {pid, of: "engine" or "card", since: when health
# first read it stopped, own: {pid, since, pids} when of is "engine" and the card's own process is stopped too, pids
# when of is "card": that process and each stopped one under it, which a SIGCONT must each reach}, on every
# stuck entry of such a card) (step
# waiting and waitsOn for a card waiting on a same-file card, never the landing it waits to begin; late: true on one
# whose process is gone or that is past its limit, so stuck whatever a stop says), and
# every open card that has waited STUCK seconds on a same-file card that is not alive (not on the belt, or its process
# gone: the wait never ends) (step waiting, since: when
# the wait began, waitsOn: that card's {card, issue, state}, as the belt's), every open card whose session (build,
# fix, rebase) has had no output and no CPU use for SESSION_STUCK seconds (each listed session, this or its process
# gone, has outputAt: the newest session line its live record of the step read, null when none was recorded (an edit
# in its worktree is not output), and process: "gone" (the card's process), "idle" with cpuAt: its session runs (the
# live record names its pid) and when the engine's watch of the step last read it using CPU (the live record's cpuAt,
# watch()), null when it read none, or "none": the card runs no session now, as in the pause before a step runs
# again), every open card that has waited on other cards for more
# than WAIT_LIMIT minutes in all (step waiting, since and waitsOn as above, waitedMin: the whole minutes of all its
# waits, waitedOn: each card it waited on, in order, as waitsOn), and every open card whose test step has a case
# running for CASE_STUCK seconds (step test, cases: their names, since: when the first of them started; testcases()); engineStopped ({pid, since, pids: it and each stopped process under it}: the
# loop's own process, as loop.json names it, while a stop signal holds it, with or without cards; else null); waitingOnCard (card, issue, since: when the
# wait began, waitsOn as stuck's): every open card waiting at its claim (the live record of the step it is running names
# the card it waits on and was brought up to date within STUCK seconds); unpushed (card, issue, sha, since): the landed commits in main that neither the last push that worked nor
# origin's main as last seen here holds; pushError (time, sha, reason, kind: check or transport, check: the check that
# failed, card and issue, and log, the push's log, when its push line names one: the landing it was pushed for; the last failed push since the oldest of those landed, else null), pushFailingSince (the first such failure, else null) and pushFails (how many such failures); pushFlaky (time, card,
# issue, files, issues: the last pushed line whose push went on over a pre-push hook that failed naming test files that
# each passed alone, pushone(), lib/push.sh, in the last 24 hours; else null); pushing (the push in progress,
# {pid, since, started, sha, stage: as pushing() in lib/push.sh writes it, log, sec: the seconds since its stage
# began, line: the newest line of its log or its last "N/M passed", stale: its process is gone and it did not end,
# cards: the cards it carries, each {card, issue}},
# whoever started it, else null; a landing during it waits for the next push); pushLast (the last push that ended, as
# pushlast() in lib/push.sh writes it, its ahead counted now, else null); gh (signed in); diskFreeKb (free space
# on the cards folder, null when df gives none); refused (card, issue, reason: "refused full run: <why>", since: the
# line's time): each test line of the last 24 hours whose run refused a full run (tests()), for the Foreman's watcher;
# untimed (UNTIMED, below): how many of the last card test runs recorded no test times, 0 when one did; split (SPLITM,
# below): the cards the rule Split large issues checked, kept and would split, with their first reviews; unchecked:
# how many landed cards' last lint line (lintline(), lib/lint.sh) has a command skipped for a missing tool; report: the
# pack's test.report ({runner, format, path, env, args, option}: the runner setup found and how its times are read), null with
# none; routes: each
# Claude route, subscription and proxy, with its state (routesnow()); quarantined (line, field, time): each line of the
# card records the check set aside ($QUARANTINE, check()), until the owner removes it from that file; serviceOld
# (commit: the commit the machine's Conveyor runs, refused: the pack fields its schema does not name, or its check's
# lines, project: the project's commit, or null): the machine's Conveyor on another commit refuses this pack, so it
# does not serve the project (machinerefuses(), lib/install.sh); null when it reads it; machineHold ({since, card, sha,
# controls, cases}): the machine hold while it stands (machinehold(), lib/mainred.sh: the loop picks no card), else
# null, for the Foreman's watcher; landingPr ({number, url, merge, cards}): the open pull request of Land as pr as
# GitHub last showed it ($LANDPR, prstate() and prsync(), lib/push.sh), with how many cards its pushed lines name and its last merge (a merge
# GitHub refused gives the reason), for the Board's Merge and the Foreman; null with none open; landingMerged ({number,
# merged, issues}): the last landing pull request merged, by Conveyor or on GitHub ($LANDPR's merged, until a new one is opened), with
# the issues whose pushed lines name it or an earlier one (each went to LANDING before it, so is merged with it), for
# the Foreman's watcher, else null. Every object of it that names a main-red fix card
# (card) also has name, "Main is red (<commit>)", as rows.jq names it, and so does a Tests page card ("Tests page:
# <file>"): the card has no issue (issue 0) to be shown by.
# A bad line is set aside first (check()); records that still do not check give no record: the reason and exit 1.
# It also says what the control record makes of the loop: state (running, paused, stopped, "paused by guard":
# the weekly limit reading is at or over the guard, or "control record unreadable"; a loop that is not running picks
# nothing, whatever `loop` says of there being one; the running loop's own "control record unreadable" stands over
# this code's reading) and reason (why the record is unreadable, or, paused by a sign-in failure, that failure and what
# to run: the record's signin; null otherwise), guard: at (the guard's percent, null for none), reading and
# readAt (the reading it is held against, null when no guard is set or there is no reading) and missing (true when a
# guard is set and there is no reading: the guard then pauses nothing), start (where new issues start: queue or held;
# null when the record does not read), builderCap (the cap in force), building (the running loop's cards counted against that
# cap at its last turn: every card on the belt but one that lands, run()) and waitingCount (its cards left
# out of the machine's count as they only wait; null for both when no loop runs), models and
# efforts (the ones in force, {claude, codex}: the next session's and the next review's), and homes (plan section 6).
# homes: each setting the loop reads, by its name in the pack (tunables.poll, models.allowed, rulings.log, checks)
# or the control record (control.cap, control.model, control.reviewer), as {value: the one in force, home: "pack",
# "schema default", "control record", "seed" (the control record leaves it to the seed, CTL0), or "none" for a pack
# field left out that has no default}.
homes() { # <control record>
  local a; modelsallowed a || a=null
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
# With no file to read, each is {} with no jq started.
live() { # every live record there is, as one object by card
  local f c o=''
  for f in "$CARDS"/*.live; do c=${f##*/}; [ ! -e "$f" ] || o+=$(jq -c --arg c "${c%.live}" '{($c): .}' "$f" 2>/dev/null)$'\n'; done
  if [ -n "$o" ]; then jq -cs 'add // {}' <<<"$o"; else echo '{}'; fi
}
# The live record of each bug-card check that runs now (bugproof.sh bugproof(): its run on main's code without the fix,
# or a main-red fix card's run of main's failing cases, redproof(), in $CARDS/mainrun/<card>.unfixed), as one object by
# card; the Board shows it as the card's proof, and health counts it as the card's output. That run is no step of the card's records: between its build
# line and its review's start line, the card's own live record is gone.
proofs() {
  local f c o=''
  for f in "$CARDS"/mainrun/*.unfixed.live; do c=${f##*/}; [ ! -e "$f" ] || o+=$(jq -c --arg c "${c%.unfixed.live}" '{($c): .}' "$f" 2>/dev/null)$'\n'; done
  if [ -n "$o" ]; then jq -cs 'add // {}' <<<"$o"; else echo '{}'; fi
}
# The output of each card's test run and of the run again of its failed tests on main (mainred.sh verdicts(), in
# $CARDS/mainrun/<card>, whose live record is mainrun/<card>.live), as one object by card: the newest of the card's .test
# file's write time and that live record's last and progress. Health counts it as the output of a card in its test step:
# while main's run runs, the card's own live record is gone and the card writes no line. One jq reads all the live
# records (each one line) and the .test times; with neither file, it is {} with no program started.
testouts() {
  local f c t o='' m=() s=("$CARDS"/*.test)
  for f in "$CARDS"/mainrun/*.live; do c=${f##*/}; c=${c%.live}; [[ $c == *.* ]] || [ ! -e "$f" ] || m+=("$f"); done
  if [ -e "${s[0]}" ]; then
    while read -r t f; do c=${f##*/}; c=${c%.test}; [[ $c == *.* ]] || o+=$c$'\t'$t$'\n'; done < <(p_mtimes "${s[@]}")
  fi
  [ -n "$o" ] || [ ${#m[@]} -gt 0 ] || { echo '{}'; return 0; }
  # A live record that is gone, half written or holds no time gives no entry, and takes no other card's with it.
  o=$(jq -cRn --arg t "$o" '[(inputs | input_filename as $f | try ({key: ($f | sub(".*/"; "") | rtrimstr(".live")),
        value: (fromjson | [.last, .progress] | map(strings | fromdate) | max)}) catch empty),
      ($t | splits("\n") | split("\t") | select(length == 2 and (.[1] | test("^[0-9]+$"))) | {key: .[0], value: (.[1] | tonumber)})]
    | map(select(.value | type == "number")) | group_by(.key) | map({key: .[0].key, value: (map(.value) | max | todate)}) | from_entries' \
    "${m[@]}" < /dev/null 2>/dev/null)
  echo "${o:-{\}}"
}
# The cards the loop leaves out of its count against the card cap: each card in its land step (<worktree>.nocap holds land, capmark(),
# lib/run.sh) that does not wait (no <worktree>.idle), and each card of a batch that has landed (batchlanded()), as one object by card,
# true each; {} for none. The Board shows them as offCap.
offcaps() {
  local f c s o=''
  for f in "$CARDS"/*.nocap "$CARDS"/*.batch; do
    c=${f##*/}; c=${c%.*}; [ -e "$f" ] || continue
    if batchlanded "$c"; then o+=$c$'\n'
    elif [ "$f" = "$CARDS/$c.nocap" ] && [ ! -e "$CARDS/$c.idle" ] && read -r s < "$f" && [ "$s" = land ]; then o+=$c$'\n'; fi
  done
  jq -Rsc 'split("\n") | map(select(. != "") | {(.): true}) | add // {}' <<<"$o"
}
aways() { # each card that gave way (giveway()): {to: the issue it gave way to, fixing: for the fix of its failed tests}, as one object by card
  local f c o=''
  for f in "$CARDS"/*.claim; do c=${f##*/}; [ ! -e "$f" ] || o+=$(jq -c --arg c "${c%.claim}" 'select(.away == true and (.to | type) == "number") | {($c): {to, fixing: (.fixing == true)}}' "$f" 2>/dev/null)$'\n'; done
  if [ -n "$o" ]; then jq -cs 'add // {}' <<<"$o"; else echo '{}'; fi
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
# prints no `TESTRUN sec` lines and no report of its runner was read (README.md, Test file times): of the
# last 5 card test runs that ran tests (pass or fail; no batch's reused line, no refused full run, none that selected
# no file), how many, when none of them recorded a file's times (times, an object even when each file was timed by
# the clock only); 0 when one did, or there is none. health and doctor say so.
UNTIMED='def untimed: [.[] | select(.step == "test" and (.result | IN("pass", "fail")) and .reused != true and (.refused | type) != "string"
    and .ended != "nothing selected" and (.selected.files // 1) > 0)] | .[-5:]
  | if length > 0 and all(.[]; .times | type != "object") then length else 0 end;'
# split (on the records and the retried lines): the cards the rule Split large issues checked (a split line, while it
# was shadow or on), for the Health view: kept (result kept) and wouldSplit (result split, built whole: in shadow, or
# slices that could not be filed), each {cards, reviewed (with a first review that said GO or NO-GO), go (that first
# review said GO), fixes (the fix lines of the reviewed ones)}, and split: the issues split into slices and not built
# (On). null when no card was checked.
SPLITM='def splitm($all): [$all | group_by(.card)[] | select(any(.step == "split"))
    | {r: (map(select(.step == "split")) | last | .result), built: any(.step == "worktree"),
       first: (map(select(.step == "review" and (.result | IN("GO", "NO-GO")))) | first | .result), fixes: (map(select(.step == "fix")) | length)}]
  | def m: {cards: length, reviewed: (map(select(.first != null)) | length), go: (map(select(.first == "GO")) | length), fixes: (map(select(.first != null) | .fixes) | add // 0)};
    if . == [] then null else {kept: (map(select(.r == "kept")) | m), wouldSplit: (map(select(.r == "split" and .built)) | m),
      split: (map(select(.r == "split" and (.built | not))) | length)} end;'
# What health reads of each line of the records (linesum(), lib/records.sh): every field it reads below, the cycles
# (DEPS) and the issues before their build (SEE) take of a line, and none other: a line's tail, review and token counts
# were most of the bytes it read. A test line's times only as whether they are an object (untimed).
HEALTHLINE='select(. != "") | fromjson | {card, issue, step, of, time, result, followups} + if .step == "worktree" then {pid, started}
    elif .step == "blocked" then {reason, retriedAt, retriedBy} elif .step == "landed" then {sha} elif .step == "push" then {sha, reason, kind, check, log} elif .step == "pushed" then {pr, flaky}
    elif .step == "picked" then {mainRed} elif .step == "lint" then {skipped: any(.lint.commands[]?; .result | strings | startswith("skipped"))} elif .step == "test" then {refused, reused, ended, selected, times: (if (.times | type) == "object" then {} else null end)}
    else {} end'
# Who gave a blocked card back is kept as its line's retriedBy (retry(), lib/issues.sh): `conveyor.sh retry` sets it
# (commands/retry.sh), review-retry for the standing review-retry's (needsretry(), lib/needsask.sh, and the Foreman's
# watcher, reviewretry(), foreman/watch-conveyor.sh, set CONVEYOR_REVIEWRETRY), owner for the owner's own.
# REVIEWBLOCK: the block reason review-retry takes, a card blocked by its review ("the fix for [P1] ... did not hold
# after <n> rounds", card.sh, with any notes block() adds after it in brackets, lib/push.sh), as a jq regex.
# REVIEWAGAIN, a jq def: reviewretried($n; $lines) is the blocked line review-retry last gave back of issue $n, among
# $lines (its card records and its retried lines), or null. It counts only a review-retry after the owner's own last
# retry of the issue (retriedBy owner) and after the issue's last landed or pushed line: either resets it. Any other
# give-back (a reopened or approved issue, a sign-in back, the Board's Hold, a Foreman's command, an answer auto decide
# may have given) records no owner, so it is no reset. A card of the issue blocked now with such a line came after
# that retry, so review-retry has already given the issue back once: its block goes to the owner (needsask()) and is
# not given back (health's reviewRetried, and `retry` itself refuses it under the lock: again(), commands/retry.sh).
# retrylines($old): the lines of the records (.) and of the retried file ($old) that reviewretried() reads, and no other,
# as it reads them again for each blocked card.
# shellcheck disable=SC2034 # REVIEWBLOCK is read by needsretry() and needsask() in lib/needsask.sh
REVIEWBLOCK='\Athe fix for \[P[0-3]\][\s\S]* did not hold after [0-9]+ rounds?( \[[\s\S]*\])?\z'
REVIEWAGAIN='def retrylines($old): [.[], $old[] | select(.step | IN("blocked", "landed", "pushed"))];
  def reviewretried($n; $l): ([$l[] | select(.issue == $n and (.step | IN("landed", "pushed"))) | .time] | max // "") as $land
  | [$l[] | select(.issue == $n and .step == "blocked" and (.retriedAt | type) == "string" and .retriedAt > $land)] as $r
  | ([$r[] | select(.retriedBy == "owner") | .retriedAt] | max // "") as $own
  | [$r[] | select(.retriedAt > $own and .retriedBy == "review-retry")] | max_by(.retriedAt);'
# When health first read each stopped process of the "<pid> TAB <started> TAB <card>" lines on stdin stopped, as ps
# gives no time a process stopped: <now> for one not read so before. $STATE.stopped keeps "<pid> TAB <started> TAB
# <epoch>" for those still stopped, so a stop is dated from the first reading of it, not from the card's last output.
# Prints "<pid> TAB <card> TAB <epoch>" a line; when the file cannot be written, each reads as stopped since <now>.
# With none stopped (no line), it empties the file and starts no program: health runs on every snapshot.
stopsince() { # <now>
  local f=$STATE.stopped w=$STATE.stopped.$$ l=''
  IFS= read -r -d '' l || :
  [ -n "$l" ] || { { : > "$f"; } 2>/dev/null; return 0; }
  { [ -f "$f" ] || : > "$f"; } 2>/dev/null || { printf '%s' "$l" | awk -F'\t' -v OFS='\t' -v now="$1" '{ print $1, $3, now }'; return; }
  printf '%s' "$l" | awk -F'\t' -v OFS='\t' -v now="$1" -v f="$f" -v w="$w" 'FILENAME == f { t[$1 FS $2] = $3; next }
    { k = $1 FS $2; if (!(k in t)) t[k] = now; if (!(k in kept)) { kept[k] = 1; print k, t[k] > w } print $1, $3, t[k] }' "$f" - \
    && if [ -f "$w" ]; then mv -f "$w" "$f"; else : > "$f"; fi
}

# READCHECKED, when set, says READ is a copy that check() has already passed and nothing appends to (the snapshot's):
# health does not check it again.
health() {
  local wt stopped en e t n loop=true gh=false ghr=null ghwhy='' free a not=() lv c r=null cap bw cyc=null pu=null pl=null pm pn bf=null st why='' said gone cm rm mc tr sp so co hd rc ps carry
  { [ -n "${READCHECKED:-}" ] || check; } && lv=${LIVEJSON:-$(live)} || return 1
  # The records and the retried lines, as health reads them (HEALTHLINE).
  hd=$(mktemp -d) || return 1
  linesum "$READ" "$STATE.health" "$hd/rec" "$HEALTHLINE" && linesum "$READ_OLD" "$RETRIED.health" "$hd/old" "$HEALTHLINE" || { rm -rf "$hd"; return 1; }
  # Each open card's process, as its last worktree line names it: "<card> TAB <pid> TAB <started>".
  wt=$(jq -rs '[group_by(.card)[] | select(all(.step | IN("landed", "closed", "blocked") | not))
      | map(select(.step == "worktree" and (.pid | type) == "number")) | last | select(.) | "\(.card)\t\(.pid)\t\(.started // "")"] | .[]' "$hd/rec") || { rm -rf "$hd"; return 1; }
  gone=$(while IFS=$'\t' read -r k p t; do [ -z "$k" ] || p_alive "$p" "$t" || printf '%s\n' "$k"; done <<<"$wt" | jq -Rcs 'split("\n") | map(select(. != ""))') || { rm -rf "$hd"; return 1; }
  c=$(ctl 2>/dev/null) || { c=null; why=$(notwhole); }
  if a=${ISSUESJSON:-$(openissues number,title,body,labels,createdAt 2>/dev/null)} && [ "$a" != null ]; then
    cyc=$(jq -c --slurpfile cards "$hd/rec" "$DEPS"' cycles($cards)' <<<"$a" 2>/dev/null) && [ -n "$cyc" ] || cyc=null
    bf=$(jq -c --slurpfile cards "$hd/rec" --argjson c "$c" --arg built "$BUILT" \
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
  # The engine (the loop's own process, as loop.json names it, idle or running cards) while the loop runs, and each
  # open card's process, when a stop signal holds it (state T, p_stopped): nothing of theirs moves until it is given
  # SIGCONT, and the loop's own stall watcher stops with it. {engine: {pid, since, pids} or null, cards: {"<card>": {pid,
  # of: "engine" or "card", since, own, pids (of "card")}}}: each live card of a stopped engine names the engine, as its
  # own process resumed under it still moves nothing, and own ({pid, since, pids}) when its own process is stopped too,
  # as resuming the engine leaves that one stopped. since: when health first read it stopped (stopsince()).
  en=''
  [ "$loop" = true ] && IFS=$'\t' read -r e t < <(jq -r '[.pid, .started] | @tsv' "$SAYS" 2>/dev/null) && [[ $e =~ ^[0-9]+$ ]] \
    && p_alive "$e" "$t" && p_stopped "$e" && en=$e$'\t'$t
  [[ ${CONVEYOR_NOW:-} =~ ^[0-9]+$ ]] && n=$CONVEYOR_NOW || printf -v n '%(%s)T' -1
  # With none stopped, the record is the one jq makes of no line, and no jq starts.
  stopped=$({ [ -z "$en" ] || printf '%s\t\n' "$en"
      while IFS=$'\t' read -r k p t; do
        [ -n "$k" ] && p_alive "$p" "$t" || continue
        [ -z "$en" ] || printf '%s\t%s\n' "$en" "$k"
        ! p_stopped "$p" || printf '%s\t%s\t%s\n' "$p" "$t" "$k"
      done <<<"$wt"; } | stopsince "$n") || { rm -rf "$hd"; return 1; }
  if [ -z "$stopped" ]; then stopped='{"engine":null,"cards":{}}'
  else
  stopped=$(jq -Rcs --arg e "${en%%$'\t'*}" 'split("\n") | map(select(. != "") | split("\t") | {pid: (.[0] | tonumber), card: .[1], since: (.[2] | tonumber | todate)})
      | {engine: (map(select(.card == "") | {pid, since}) | first // null),
         cards: (map(select(.card != "")) | group_by(.card) | map((map(select((.pid | tostring) == $e)) | first) as $g
           | (map(select((.pid | tostring) != $e) | {pid, since}) | first) as $o
           | {key: .[0].card, value: (if $g then {pid: $g.pid, of: "engine", since: $g.since} + (if $o then {own: $o} else {} end) else {pid: $o.pid, of: "card", since: $o.since} end)}) | from_entries)}' <<<"$stopped") || { rm -rf "$hd"; return 1; }
  # Each stopped process named (the engine, a card's own) with pids: it and every process under it that is stopped
  # (p_stoppedtree), it first, so the command that resumes it reaches the builder and its timeout wrapper too.
  sp=$(for p in $(jq -r '[.engine.pid?, (.cards[] | .pid, .own.pid?)] | map(numbers) | unique | .[]' <<<"$stopped"); do
      p_stoppedtree "$p" | jq -Rcs --arg p "$p" '{($p): split("\n") | map(select(. != "") | tonumber)}'; done | jq -cs 'add // {}') \
    && stopped=$(jq -c --argjson sp "$sp" 'def tree: . + {pids: ([.pid] + (($sp[.pid | tostring] // []) - [.pid]))};
      (.engine |= if . then tree else . end) | .cards |= map_values(if .of == "card" then tree else . end | if .own then .own |= tree else . end)' <<<"$stopped") \
    || { rm -rf "$hd"; return 1; }
  fi
  st=$(state "$c" "$(jq -r '.pct // empty' <<<"$r")")
  # A loop a sign-in failure paused (signinpause()) says why, and what to run.
  [ "$st" != paused ] || why=$(jq -r '.signin // ""' <<<"$c")
  if [ "$loop" = true ] && said=$(jq -ce 'select(.state == "control record unreadable" and (.pid | type == "number")) | {pid, reason}' "$SAYS" 2>/dev/null) \
    && kill -0 "$(jq -r .pid <<<"$said")" 2>/dev/null; then st='control record unreadable'; why=$(jq -r '.reason // ""' <<<"$said"); fi
  [ "$loop" = true ] && cm=$(jq -ce '.commit | strings' "$SAYS" 2>/dev/null) || cm=null
  # The running loop's count at its last turn: {building: the cards counted against the cap, waiting: those left out of the machine's count}.
  [ "$loop" = true ] && bw=$(jq -ce 'select((.building | type) == "number" and (.waiting | type) == "number") | {building, waiting}' "$SAYS" 2>/dev/null) || bw='{"building":null,"waiting":null}'
  # The push in progress, whoever started it (the loop, Push now, Push landed): stale when its process is gone and it
  # did not end (push() clears the record at its end); line, the newest line of its log, or its last "N/M passed".
  # started: when the push began (a record with none: its stage's since).
  if pu=$(jq -ce 'select((.pid | type == "number") and (.since | type == "string")) | {pid, since, started: ((.started | strings) // .since), sha, stage: (.stage // null), log: (.log // null), base: ([.base | arrays | .[] | strings])}' "$PUSHING" 2>/dev/null); then
    kill -0 "$(jq -r .pid <<<"$pu")" 2>/dev/null && a=false || a=true
    pu=$(jq -c --argjson stale "$a" --rawfile out <(f=$(jq -r '.log // empty' <<<"$pu"); [ -z "$f" ] || tail -c 65536 "$f" 2>/dev/null) '
      (($ENV.CONVEYOR_NOW // "" | tonumber?) // now) as $now
      | ($out | gsub("\u001b\\[[0-9;?]*[A-Za-z]"; "") | gsub("\r"; "\n") | split("\n") | map(select(test("\\S")))) as $l
      | . + {stale: $stale, sec: ([$now - (.since | fromdate), 0] | max | floor),
             line: (([$l[] | select(test("\\b[0-9]+/[0-9]+ passed\\b"))] | last) // $l[-1] // null | if . then .[0:300] else . end)}' <<<"$pu") || pu=null
  else pu=null; fi
  pl=$(jq -ce 'objects | select(.time | type == "string")' "$PUSHLAST" 2>/dev/null) || pl=null
  # Signed in (ghok, read without the network); only then whether GitHub answers (ghreach): null when signed out.
  # Not signed in: why (ghok's GHWHY, health ghWhy), so a wake can say it (#490). ghRead names the GitHub read both
  # answers are from (ghok's GHREAD).
  if ghok; then gh=true; ghreach && ghr=true || ghr=false; else ghwhy=$GHWHY; fi
  # The card the machine holds back (room()), while the loop runs: {issue, reason, since}.
  rm=null; [ "$loop" != true ] || rm=$(jq -ce 'select((.issue | type == "number") and (.reason | type == "string"))' "$ROOMF" 2>/dev/null) || rm=null
  free=''; { read -r _ && read -r _ _ _ free _; } 2>/dev/null < <(df -Pk "$CARDS" 2>/dev/null) || :; [[ $free =~ ^[0-9]+$ ]] || free=null
  mc=$(mhost); mc=${mc:-null}
  # The cores kept for the user (the host file's reserveCores, lib/slots.sh slot_reserved) and the test-slot pool's
  # size on the cores left (null when the pool cannot be read), or why this machine cannot keep cores, for the Rules tab.
  # The pool as the caller read it when SLOTSREAD is set (the snapshot's), else read here; slot_pool (slot_cpuset) also
  # read the cores kept (SLOT_KEPT), so no program starts for them again.
  co=$( { [ -n "${SLOTSREAD:-}" ] || slot_pool; } >/dev/null 2>&1 && n=$SLOT_N || n=null
    jq -cn --argjson n "$n" --arg r "$(printf '%s\n' "${SLOT_KEPT[@]+"${SLOT_KEPT[@]}"}")" --arg why "$(slot_reserve_why)" \
      '{reserved: ($r | split("\n") | map(select(. != "") | tonumber)), slots: $n, unavailable: (if $why == "" then null else $why end)}') || co=null
  # How the test times are read from the runner's report (the pack's test.report, written by setup), for untimed.
  # The pack's values as packget keeps them: no program of its own.
  packget test.report tr 2>/dev/null && [ -n "$tr" ] || tr=null
  # The machine's Conveyor on another commit whose own check refuses this pack (machinerefuses, lib/install.sh).
  so=$(machinerefuses | jq -Rc 'split("\t") | select(length == 3) | {commit: .[0], refused: .[1], project: (.[2] | if . == "" then null else . end)}') \
    && [ -n "$so" ] || so=null
  for a in "$(pushed)" "refs/remotes/$REMOTE/$BRANCH"; do
    [ -z "$a" ] || ! git rev-parse -q --verify "$a^{commit}" >/dev/null 2>&1 || not+=("$a")
  done
  # The last push's ahead, counted now: the commits main had at its end that the remote still lacks (a push by hand
  # since then moves the remote; a landing since then is not counted).
  [ "$pl" = null ] || ! pm=$(jq -re '.main | strings' <<<"$pl") || ! pn=$(git rev-list --count "$pm" --not "${not[@]}" 2>/dev/null) \
    || pl=$(jq -c --argjson n "$pn" '.ahead = $n' <<<"$pl")
  # The commits the push in progress carries (its cards, below): those of its commit past what the remote held when it
  # began (its record's base). Not past the remote now: the push moves $PUSHED as git push ends, before it writes its
  # cards' pushed lines. A record with no base: past the remote now.
  carry=''; ps=$(jq -r '.sha | strings' <<<"$pu" 2>/dev/null) && [ -n "$ps" ] && mapfile -t a < <(jq -r '.base[]' <<<"$pu") \
    && { [ ${#a[@]} != 0 ] || a=("${not[@]}"); } && carry=$(git rev-list "$ps" --not "${a[@]}" 2>/dev/null) || carry=''
  # The landing pull request as GitHub has it (prsync(), lib/push.sh); under `watch`, its slower timer asks (github()).
  [ -n "$GITHUB" ] || prsync
  jq -cs --argjson loop "$loop" --argjson gh "$gh" --argjson ghr "$ghr" --arg ghwhy "$ghwhy" --arg ghread "$GHREAD" --argjson free "$free" --argjson stuck "$STUCK" --argjson sstuck "$SESSION_STUCK" --argjson casestuck "$CASE_STUCK" --argjson waitlimit "$WAIT_LIMIT" --argjson gone "$gone" --argjson stopped "$stopped" --slurpfile livef <(printf '%s' "${lv:-{\}}") --argjson proof "$(proofs)" --argjson testout "$(testouts)" \
    --arg state "$st" --arg why "$why" --argjson commit "$cm" --argjson ctl "$c" --argjson r "$r" --arg yes "$YES" --arg lintyes "$LINTYES" \
    --argjson cap "$cap" --argjson bw "$bw" --arg repo "$REPO" --argjson room "$rm" --argjson machine "$mc" --argjson cores "$co" --argjson force "$(inforce "$c")" --argjson cycles "$cyc" --slurpfile before <(printf '%s\n' "$bf") --argjson pushing "$pu" --argjson pushlast "$pl" --argjson homes "$(homes "$c")" --argjson routes "$(routesnow)" --argjson report "$tr" --argjson serviceold "$so" \
    --slurpfile old "$hd/old" --slurpfile mh <(jq -c 'objects | {since, card, sha, controls, cases}' "$MACHINEHOLD" 2>/dev/null) --slurpfile lp <(jq -c 'objects | select(.merged == null and .closed == null and (.number | type) == "number") | {number, url, merge}' "$LANDPR" 2>/dev/null) --slurpfile lm <(jq -c 'objects | select(.merged != null and (.number | type) == "number") | {number, merged}' "$LANDPR" 2>/dev/null) --slurpfile qt <(jq -c 'objects | {line, field, time}' "$QUARANTINE" 2>/dev/null) --rawfile ahead <(git rev-list "refs/heads/$BRANCH" --not "${not[@]}" 2>/dev/null) --rawfile carry <(printf '%s\n' "$carry") "$UNTIMED$SPLITM$REVIEWAGAIN"'
    $livef[0] as $live | (($ENV.CONVEYOR_NOW // "" | tonumber?) // now) as $now
    | ($ahead | split("\n") | map(select(. != "")) | INDEX(.)) as $ahead
    | ([.[], $old[] | select(.step == "picked") | if (.mainRed | type) == "string" then {key: .card, value: "Main is red (\(.mainRed[0:12]))"}
        elif (.testFile | type) == "string" then {key: .card, value: "Tests page: \(.testFile)"} elif (.noIssue | type) == "string" then {key: .card, value: .noIssue} else empty end] | from_entries) as $names
    | [.[] | select(.step == "landed" and $ahead[.sha]) | {card, issue, sha, since: .time}] as $un
    # The cards the push in progress carries: each whose landed commit is one it carries.
    | ($carry | split("\n") | map(select(. != "")) | INDEX(.)) as $carry
    | (if $pushing == null then null else [.[] | select(.step == "landed" and $carry[.sha]) | {card, issue}] | unique_by(.card) end) as $carried
    | [.[] | select(.step == "push" and .result == "fail" and $un[0] and .time >= $un[0].since)] as $fail
    | [map(select(.step != "push")) | group_by(.card)[]
        # Its closing line as rows.jq names it: a blocked line a later landed, pushed or closed line of the record follows does not count.
        | {card: .[0].card, issue: .[0].issue, last: last, end: (map(select(.step | IN("landed", "closed", "blocked", "pushed"))) | . as $e
             | [range(length) as $i | $e[$i] | select(.step != "pushed" and (.step != "blocked" or ($e[$i + 1:] | all(.step == "blocked"))))] | last),
           # Its output: the live record of the step it began, or, between two steps (its last line no start), that of
           # the run of its bug-card check on main code (proofs(): the run of main failing cases of a main-red fix card too);
           # in its test step, the output of its test run and of the run again of its failed tests on main (testouts()).
           out: (last as $l | [($live[.[0].card] | select(. != null and $l.step == "start" and $l.of == .step)), ($proof[.[0].card] | select(. != null and $l.step != "start")),
             ($testout[.[0].card] | select(. != null and $l.step == "start" and $l.of == "test") | {last: .})
             | [.last, .progress] | map(strings) | max | strings] | max)}] as $c
    # reviewRetried: the card came after review-retry gave its issue back (reviewretried(), above),
    # so review-retry gives it back no more (foreman/lib.sh retryable()).
    | retrylines($old) as $all
    | ($c | map(select(.end.step == "blocked") | {card, issue, reason: .end.reason, since: .end.time}
        + (if (.issue | numbers) > 0 and reviewretried(.issue; $all) != null then {reviewRetried: true} else {} end))) as $b
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
    {time: ($now | todate), repo: $repo, loop: $loop, room: $room, machine: $machine, cores: $cores, commit: $commit, state: $state, reason: (if $why == "" then null else $why end),
       guard: {at: $ctl.guard, reading: $r.pct, readAt: $r.time, missing: ($ctl.guard != null and $r == null)}, start: $ctl.start, newest: (last.time // null),
       blocked: ($b | map(select(.reason | startswith($yes) or startswith($lintyes) | not))), waiting: ($b | map(select(.reason | startswith($yes) or startswith($lintyes)))),
       stuck: ($c | map(select(.end == null) | . + {since: ([.last.time, .out // ""] | max)}
           # A session (build, fix, rebase) that says nothing is listed after SESSION_STUCK, when that is sooner, and only
           # while it uses no CPU either: its live record of the step ($sl) has cpuAt, its last CPU use the watch of the
           # step read (watch()), so a session that works with no line for that long is not stuck. One so listed says what it
           # lacks: outputAt, the newest line that record read from the session (.last; null: no live output was recorded;
           # an edit in its worktree, .progress, is not output), and process: "gone" (the card process), "idle" (a session runs,
           # its record naming its pid, its last CPU use at cpuAt, null when none was read), or "none": no session runs now
           # (the pause before a step runs again, after a stall or a refusal of the model API, or the wait for its CLI).
           | (.last.step == "start" and (.last.of | IN("build", "fix", "rebase"))) as $ses | (.card | IN($gone[])) as $g
           | (.last.of as $o | $live[.card] | if $ses and . != null and .step == $o then . else {} end) as $sl
           | ($g or $now - ([.since, ($sl.cpuAt | strings) // ""] | max | fromdate) >= (if $ses then [$stuck, $sstuck] | min else $stuck end)) as $late
           | select($late or $stopped.cards[.card])
         | ($live[.card].waits.on // null) as $h
         | {card, issue, step: (if $h then "waiting" else .last | if .step == "start" then .of else .step end end), since} + (if $h then {waitsOn: holder($h)} else {} end)
           + (if $late then {late: true} else {} end)
           + (if $late and $ses then {outputAt: (($sl.last | strings) // null)} + (if $g then {process: "gone"} elif ($sl.pid | type) == "number" then {process: "idle", cpuAt: (($sl.cpuAt | strings) // null)} else {process: "none"} end) else {} end))
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
             | select($k != []) | {card, issue, step: "test", since: ($k | map(.since) | min), cases: ($k | map(.name))}])
         # A card whose process or engine is stopped says which, on each of its entries.
         | map(. + ($stopped.cards[.card] // null | if . then {stopped: .} else {} end))), engineStopped: $stopped.engine,
       waitingOnCard: [$c[] | select(.end == null and atclaim) | $live[.card] as $v | {card, issue, since: $v.at, waitsOn: holder($v.waits.on)}],
       unpushed: $un, pushError: ($fail | last | if . then {time, sha, reason, kind: (.kind // null), check: (.check // null), card, issue} + (if .log then {log} else {} end) else null end), pushFailingSince: ($fail[0].time // null), pushFails: ($fail | length), pushing: (if $pushing == null then null else $pushing + {cards: $carried} | del(.base) end), pushLast: $pushlast,
       pushFlaky: ([.[] | select(.step == "pushed" and (.flaky | type) == "object" and $now - (.time | fromdate) < 86400)] | last | if . then {time, card, issue, files: .flaky.files, issues: .flaky.issues} else null end),
       gh: $gh, ghReached: $ghr, ghWhy: (if $gh then null else $ghwhy end), ghRead: $ghread, diskFreeKb: $free, builderCap: $cap, building: $bw.building, waitingCount: $bw.waiting, models: $force.models, efforts: $force.efforts, cycles: $cycles, before: $before[0], homes: $homes,
       refused: [.[] | select(.step == "test" and (.refused | type) == "string" and $now - (.time | fromdate) < 86400) | {card, issue, reason: .refused, since: .time}],
       untimed: untimed, split: splitm([.[], $old[]]),
       unchecked: ([group_by(.card)[] | select(any(.step == "landed")) | map(select(.step == "lint")) | last | select(.skipped == true)] | length), report: $report, routes: $routes, quarantined: $qt, serviceOld: $serviceold, machineHold: ($mh[0] // null),
       landingPr: ([.[] | select(.step == "pushed" and (.pr | type) == "number") | {pr, card}] as $pp
         | $lp[0] // null | if . == null then null else . + {cards: ([$pp[] | select(.pr == $lp[0].number) | .card] | unique | length)} end),
       landingMerged: ([.[] | select(.step == "pushed" and (.pr | type) == "number" and .pr <= $lm[0].number) | .issue | numbers] as $mi
         | $lm[0] // null | if . == null then null else . + {issues: ($mi | unique)} end)}
    | walk(if type == "object" and (.card | type) == "string" and $names[.card] then .name = $names[.card] else . end)' "$hd/rec"
  rc=$?; rm -rf "$hd"; return $rc
}
