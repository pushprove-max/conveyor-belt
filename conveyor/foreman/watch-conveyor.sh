#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# watch-conveyor.sh [--once | --status [<project>]] -- the Foreman's Conveyor watcher, run by waiter.sh. Once a minute it asks the
# Foreman's own record, or each record of its group (lib.sh mine), never another project's, for `conveyor.sh
# snapshot` (lib.sh ask), or, when that read fails or is slow, `conveyor.sh health` for the blocked, waiting and
# before entries (record()), and, on any NEW problem, puts one wake in pending and
# exits. The problems, each a record's own:
#   a card waiting on the owner's yes       an issue waiting on the owner's yes before its build (health's before)
#   a card blocked; one blocked by its review, while the standing kind review-retry is on, the watcher retries itself
#     and wakes nothing for, unless that retry fails (reviewretry()); a card still blocked 30 minutes after a poll
#     first listed it, and once an hour after, while no open owner question names its issue (stillblocked()); of a
#     snapshot made before the last change to the card records, only a card health still lists blocked (recheck()),
#     its line ending "(as of <the snapshot's time>)"
#   a card stuck (health's stuck: no new step and no output, its process gone, a wait on other cards past the
#     limit, with the cards it waited on, or a test case that hangs, by name); one whose step the engine ended
#     for no progress and runs once more (did) is a new problem, and says so ("ended and retried"); a second stall
#     blocks the card, and its blocked alert says so; one whose process is stopped by a stop signal (health's
#     stopped) names the stopped process, since when health first read it so, and the command that resumes it, in
#     place of stuck, and a stopped engine (health's engineStopped), idle or not, is one item that does so for the
#     engine and names the cards it holds, and the command for each of their own processes stopped too; each only once
#     two polls in a row, at least a poll apart, list it
#   a card that has waited for main to change, or on another card, for the pack's foreman.waitWake minutes (default
#     10): it names the card, what it waits on and that card's step and last action (for main, each main-red fix card
#     open or blocked); once per wait, and "still waiting" after each further waitWake minutes of it
#   the record unreachable: no snapshot on three polls in a row and for 2 minutes, and none from one more read with a
#     longer wait (a live engine under a high machine load reads slowly)
#   an awaited issue landed: $FD/await-<repo>.txt lists issue numbers, one per line, of the record <repo>, so a
#     group's Foreman claimed in another checkout awaits the same issues of the same projects; one whose card has
#     pushed wakes once, naming the commit it landed as, but while another awaited issue of the record is on the belt and not
#     blocked, its wake is held, and the landings of the batch wake in one (holdlandings(); a restart of the waiter, or
#     any other wake made from a snapshot, sends them). The Foreman only appends to it: what was dropped is counted in await-done-<repo>.txt
#     ("<issue> <its lines in await-<repo>.txt then>"), so a line appended later awaits it again
#   a whole-suite run (a release's or the full test's, snapshot suites) that ended: its result, commit, reasons and
#     failed cases (a full test run whose process is gone, with no result: an error, with that reason)
#   the fix cards of a red release run (its record's fixes): each has landed, once, with release-prep started again
#     or why it did not start; one closed with no landed card, once, naming it, as the release then waits on the Foreman
#   a push that failed its check (health's pushError.kind check), at once and again for each commit it fails on: the
#     loop does not push again until main moves
#   a card's test step that refused a full run of its tests (health's refused: the engine's tests()), once a test line
#   the machine hold (health's machineHold: the engine's mainred.sh machinehold()), once a hold, naming the controls that fail
#   a merge of the landing pull request that GitHub refused (health's landingPr.merge), once a refusal, with GitHub's reason
#   every other entry of the Board's Needs you: .claude/scripts/dashboard_needs.json is the one list of its kinds,
#     which the Board reads too, each with the snapshot field it is read from (the whole test failing on main, an engine
#     update not taken, test issues held, a pipeline change held for the owner, a dependency that cannot be read,
#     and any kind added to the list later, under its kind). A held pipeline change's line names it, its parent and
#     its finding: "pipeline change held: #615 (follow-up of #597): <finding>"
#   no loop running, a push failing for over 10 minutes or listed under the Board's blocked cards (needsYou.blocked:
#   it failed twice), a control record the loop cannot read, a dependency cycle among open issues, Conveyor idle
#   (nothing on the belt and nothing to pick, in a snapshot made after the last change to the card records) on two
#   polls in a row, and, each on three polls in a row, gh signed out
#   (no token: `gh auth token`; the wake gives health's ghWhy) and GitHub not reached (gh signed in, but `gh auth
#   status` failed or timed out)
# Every wake names every item. Its first line lists every issue number by kind, per project:
#   Conveyor: shop: needs the owner's yes: #12 #15; blocked: #7 | site: needs the owner's yes: #19
# then one line per item, each cut alone if it must be; the wake as a whole is never cut.
# A problem reported is not reported again until it clears and comes back: conveyor-reported.txt holds the keys,
# "<repo>/<key>", of the reported problems still there, so a restart repeats nothing. While a record gives no
# snapshot, its reported problems stay reported. A watcher whose waiter's session's process has ended
# (CONVEYOR_FOREMAN_SESSION_PID, waiter.sh) puts no wake and marks nothing reported: it ends, and the next waiter's
# watcher finds the same problems new.
# A card blocked for two polls or more that no session has got yet (unreported, below) is named again, on `foreman
# status` and in the next wake: "not yet reported: blocked #N".
# A card that only moves on the belt (build to review, review to tests) needs no one and wakes nothing.
# Each poll writes one line to conveyor-polls.log in the Foreman's folder: its start, end, time taken, each record's
# outcome and read, and whether it woke (the main loop, below).
# --status prints the records' state for the Foreman to read, and reports nothing as seen (STATUS, below).
# For tests: CONVEYOR_FOREMAN_ASK (lib.sh), CONVEYOR_FOREMAN_NOW (the clock, epoch seconds), --once (one poll: exit 0
# with a wake put, 1 with nothing new).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
SEEN=$FD/conveyor-reported.txt HELDF=$FD/conveyor-held.txt
# The poll log, and this poll's outcome a record a line (record(), for the poll log): see the main loop, below.
PLOG=$FD/conveyor-polls.log POLLF=$FD/conveyor-poll.now PLOG_MAX=1000
POLL=60 DOWN_S=120 SLOW_S=150 PUSH_S=600
# The kinds of the Board's Needs you, the list the Board reads too: one that does not read stops the watcher here,
# never as a record read as unreachable.
KINDS=$FHERE/../../.claude/scripts/dashboard_needs.json
jq -e 'arrays | all(.[]; (.kind | strings) and (.from | arrays))' "$KINDS" >/dev/null || { echo "watch-conveyor: $KINDS does not read as the list of Needs you kinds" >&2; exit 1; }
RECS=$(mine) || exit 1

# A whole-suite run of the snapshot's suites (a release's or the full test's) on one line: under way, its commit, how
# long it has run, the cases done of the cases selected (the total when its runner gives it) and failed; ended, its result and commit; either way the failed cases by name.
# The names are the cases its runner named as ended (fulltest.sh suiteprog()): an engine case by its own name, never
# its file, so the line says cases, not files. A case stopped at its file's time limit (suiteprog()'s timedout) is
# named "<case> (timed out)", not as a plain failure.
SUITE='def took: if . < 3600 then "\(. / 60 | floor)m" else "\(. / 3600 | floor)h\(. % 3600 / 60 | floor)m" end;
  def suiteline($now): (if .kind == "release" then "release \(.version // "")" else "full test" end) as $k
    | (.sha // "" | if . == "" then "no commit yet" else .[0:12] end) as $c
    | [.timedout | arrays | .[] | tostring] as $late
    | ([.cases | arrays | .[] | tostring | if IN($late[]) then "\(.) (timed out)" else . end] | if length > 20 then "\(.[:20] | join(", ")) and \(length - 20) more" else join(", ") end) as $f
    | if .ended == null then "\($k) running on \($c) for \((.since | fromdate? | $now - .) // null | if . == null then "?" else took end): \(.done // 0)\(if .of == null then "" else " of \(.of)" end) cases done, \(.failed // 0) failed\(if $f == "" then "" else ": \($f)" end)"
      else "\($k) \(.state // "ended") on \($c) at \(.ended)\([.reasons | arrays | .[] | tostring] | if . == [] then "" else ": \(join("; "))" end)\(if $f == "" then "" else "; failed cases: \($f)" end)" end;'
# The issues of a snapshot, or of its history ($hist: `conveyor.sh history`, null when not read), whose card pushed:
# landed and not in health's unpushed, or in pushedCards. The snapshot holds only the newest of both lists (#544:
# with 110 pushed today an awaited issue among the oldest was in neither, and never woke the Foreman).
PUSHED='def pushed($hist): [.health.unpushed | arrays | .[] | objects | .card] as $unpushed
  | [(., ($hist | objects)) | (.metrics.cards | arrays | .[] | objects | select(.state == "landed" and (.card | IN($unpushed[]) | not)) | .issue | numbers),
     (.pushedCards | arrays | .[] | objects | .issue | numbers)];'
# A card by its issue, "#n"; a main-red fix card, which has no issue (issue 0), by its name, "Main is red (<commit>)"
# (health and the snapshot give it: rows.jq).
REF='def ref: (.name | strings) // "#\(.issue)";'
# A snapshot's problems, one per line: <key> TAB <kind> TAB <issue numbers, "#n" by spaces> TAB <text>. Fails for
# anything but a snapshot holding a health record. idle is a candidate here: record() reports it on its second poll.
# An awaited issue that landed names its commit (the snapshot's or the history's landed line of it); a whole-suite run
# that ended (snapshot suites) is one item, its line as the status command prints it, the failed cases named.
# The command that resumes a stopped process health names ({pid, pids}): a SIGCONT to each stopped process of its
# tree (pids), as one sent to it alone leaves those under it, the builder among them, stopped.
PROBLEMS=$SUITE$PUSHED$REF'def one: tostring | gsub("\\s+"; " ") | .[0:240];
  def cont: ([.pids | arrays | .[] | numbers] | if . == [] then null else . end) as $p | "`kill -CONT \($p // [.pid] | map(tostring) | join(" "))`";
  # Not idle when the card records changed after the snapshot was made (recordsNewer, commands/snapshot.sh): its empty
  # belt can leave out a card begun since (#1032).
  (type == "object" and .belt == [] and (.queue.next // null) == [] and .recordsNewer != true) as $idle
  | pushed($hist[0]) as $pushed
  | . as $snap
  # The push the Board lists under blocked (snapshot.sh: a push that failed twice), which health holds only as pushFailingSince.
  | any(.needsYou | objects | .blocked | arrays | .[]; objects | .push == true) as $pushheld
  # A blocked line of a snapshot made before the last change to the card records says when that snapshot was made (#1114),
  # but for one the status took from the card records now (NOWBLOCKED).
  | (if .recordsNewer == true and .blockedNow != true then (.snapshotAt | strings | " (as of \(.[11:16])Z)") // "" else "" end) as $asof
  | .health
  | if type == "object" and ([.loop, .gh] | all(type == "boolean")) and ([.blocked, .waiting, .stuck] | all(type == "array" and all(type == "object")))
    and (.time | fromdate | type == "number") and (.pushFailingSince | type == "null" or (fromdate | type == "number"))
  then . else error("not a health record") end
  | (.waiting[] | ["waiting:\(.card)", "needs the owner'"'"'s yes", ref, "\(ref) needs the owner'"'"'s yes since \(.since): \(.reason | one)"]),
    (.before | arrays | .[] | objects | select(.issue | numbers)
      | ["before:\(.issue)", "needs the owner'"'"'s yes", "#\(.issue)", "#\(.issue) needs the owner'"'"'s yes before its build since \(.since): \(.title | one)"]),
    (.blocked[] | ["blocked:\(.card)", "blocked", ref, "\(ref) is blocked since \(.since): \(.reason | one)\($asof)"]),
    # A stopped engine is one item, idle or not, naming the cards it holds; a card under it is not listed again.
    # A held card whose own process is stopped too names that one as well: resuming the engine leaves it stopped.
    (([.stuck[] | select(.stopped.of? == "engine")] | unique_by(.card)) as $h | [$h[] | ref] as $held
      | [$h[] | select((.stopped.own | objects | .pid | numbers) != null) | "; \(ref)'"'"'s own process is stopped too since \(.stopped.own.since): \(.stopped.own | cont) resumes it"] as $own
      | .engineStopped | objects | select(.pid | numbers)
      | ["stopped:engine:\(.pid)", "stopped", ($held | join(" ")), "the engine is stopped (state T) since \(.since): \(cont) resumes it"
        + (if $held == [] then "" else " (it holds \($held | join(", ")))" end) + ($own | join(""))]),
    (.stuck[] | if .stopped.of? == "engine" then empty
      elif ((.stopped | objects | .pid) // null | type) == "number" then ["stopped:\(.card):\(.stopped.pid)", "stopped", ref,
        "\(ref): its process is stopped (state T) since \(.stopped.since // .since): \(.stopped | cont) resumes it"]
      elif .did then ["stuck:\(.card):\(.did)", "stuck", ref, "\(ref) is stuck: no progress since \(.since) at \(.step); the engine \(.did) it"]
      else ["stuck:\(.card)", "stuck", ref, "\(ref) is stuck: " + (
      if (.waitedOn | type) == "array" then "it has waited on other cards for \(.waitedMin) minutes in all (\([.waitedOn[] | objects | ref] | join(", ")))"
      elif (.cases | type) == "array" then "its test step has had \(.cases | map(tostring) | join(", ") | one) running since \(.since)"
      else "no new step and no output since \(.since) (last step: \(.step))" end)] end),
    # An awaited landing while another awaited issue of this record is on the belt, not blocked, is "held landing": poll() sends
    # the held ones in one wake once none is left (holdlandings()).
    (([$snap.belt | arrays | .[] | objects | select(.landed != true) | .issue | numbers | select(IN($await[][0]) and IN($pushed[]) == false)]
        - [$snap.health.blocked | arrays | .[] | objects | .issue | numbers]) as $flying
      | $await[] | select(.[0] | IN($pushed[])) | .[0] as $i
      | (first($snap, ($hist[0] | objects) | .landed | arrays | .[] | objects | select(.issue == $i) | .sha | strings | select(. != "")) // "") as $sha
      | ["landed:\(.[0]):\(.[1])", (if ($flying | length) > 0 then "held landing" else "landed" end), "#\(.[0])", "#\(.[0]) landed\(if $sha == "" then "" else " as \($sha[0:12])" end): your step is due"]),
    ($snap.suites | arrays | .[] | objects | select(.ended != null)
      | ["suite:\(.kind | tostring | gsub("\\s"; "-")):\(.ended)", "suite ended", "", suiteline($now) | gsub("\\s+"; " ")]),
    # The fix cards of a red release run (the release record'"'"'s fixes, each {issue, state}, and restarted, which the
    # engine'"'"'s relfixes() writes, conveyor/lib/fulltest.sh; a run it started has by "fixes landed"): once a run. A
    # started run that ends red is read for its own fixes as any red run is.
    ($snap.suites | arrays | .[] | objects | select(.kind == "release") | (.version | tostring) as $v
      | [.fixes | arrays | .[] | objects | select(.issue | numbers)] as $fx | ($fx | map("#\(.issue)") | join(", ")) as $all
      | if .by == "fixes landed" and .ended == null then ["relfix:\($v):\(.since)", "release started again", "",
          "every fix card of release \($v)'"'"'s failed suite has landed: release-prep \($v) started again at \(.since)"]
        elif .step != "release-prep" or .state != "failed" or $fx == [] then empty
        elif all($fx[]; .state == "landed") then
          # relfixes() writes fixes and restarted in one go: all landed with no restarted is a hold it found. A card on
          # the belt, or a push owed, ends by itself and wakes nothing, unless the rule "Push when a card lands" is off
          # (the snapshot'"'"'s control.rules.push false): then nothing pushes until the owner does. A restart with no run
          # of its own two polls on is a run that did not begin. With Land as pr and Merge PR button (the control
          # record'"'"'s landAs and prMerge, else the pack'"'"'s), a push goes to the landing pull request and the suite runs
          # on the branch it goes into (relhead(), lib/push.sh): the owner must merge it too. Each reason has its own
          # key, so the merge still owed after the push wakes again.
          (($snap.health.unpushed | arrays | length) > 0) as $owed
          | ([$snap.control | objects | .rules | objects | .push] == [false]) as $pushoff
          | ((($snap.control | objects | .landAs) // $snap.packLandAs) == "pr"
              and (($snap.control | objects | .prMerge) // $snap.packPrMerge) == "button") as $bymerge
          | ([$snap.health.landingPr | objects | select(.merged == null and .closed == null) | .number | numbers][0]) as $pr
          | (if .restarted != null then select($now - (.restarted | fromdate? // $now) >= 2 * $poll)
              | ["restart", "release-prep was started again at \(.restarted), but no run began: run `conveyor.sh release-run prep \($v)`"]
            elif ($snap.belt | arrays | length) > 0 then empty
            elif $owed and $pushoff then ["push", "the landed commits are not pushed, and the rule Push when a card lands is off: press Push landed on the Board'"'"'s Control tab"
              + (if $bymerge then ", then Merge there, as the rule Land as is pr and the rule Merge PR is button: the suite runs on the branch the landing pull request goes into" else "" end)]
            elif $owed then empty
            elif $bymerge and $pr != null then ["merge", "landing pull request #\($pr) is not merged, and the rule Merge PR is button: press Merge on the Board'"'"'s Control tab"]
            else ["wait", "the commit the suite runs on does not hold each fix card'"'"'s commit yet (a landing pull request not merged, or the remote not read)"] end) as [$tag, $why]
          | ["relfix:\($v):\(.since):\($tag)", "release fixes landed", "", "every fix card of release \($v)'"'"'s failed suite has landed (\($all)), but release-prep \($v) did not start again: \($why)"]
        else $fx[] | select(.state == "closed")
          | ["relfixclosed:\($v):\(.issue)", "release fix closed", "#\(.issue)",
             "fix card #\(.issue) of release \($v)'"'"'s failed suite was closed with no landed card: release-prep \($v) does not start again by itself; run `conveyor.sh release-run prep \($v)` when its failure is fixed"]
        end),
    (select(.loop | not) | ["noloop", "no loop", "", "no loop is running"]),
    (select(.pushFailingSince != null) | .pushError as $e
      | if ($e | type) == "object" and $e.kind == "check" then
          ["push:\($e.sha)", "push blocked", ($e.name | strings) // ($e.issue | numbers | select(. > 0) | "#\(.)") // "",
           "push blocked: \($e.check // "a check" | one) failed after \(($e.name | strings) // ($e.issue | numbers | select(. > 0) | "#\(.)") // ($e.card // "the last landing" | one)); it will not pass on a retry"]
        elif $pushheld or (.time | fromdate) - (.pushFailingSince | fromdate) > $push then
          ["push", "push failing", "", "the push has failed since \(.pushFailingSince): \(.pushError.reason // "" | one)"]
        else empty end),
    # A push that went on over a pre-push hook that failed naming test files that each passed alone (health pushFlaky,
    # conveyor/lib/push.sh pushone()): once a push. Not "will not pass on a retry": they passed alone.
    (.pushFlaky | objects | (.issues | arrays | map("#\(.)")) as $i
      | ["pushflaky:\(.time)", "push flaky", ($i | join(" ")),
         "push went on: the pre-push hook failed naming \(.files | arrays | join(", ")), flaky: passed alone\(if $i == [] then "" else "; held for the owner: \($i | join(", "))" end)" | one]),
    (.refused | arrays | .[] | objects | ["refused:\(.card):\(.since)", "full test run refused", ref, "\(ref): the test step \(.reason | one)"]),
    # The machine hold (health machineHold, conveyor/lib/mainred.sh machinehold()): once a hold, by when it began.
    (.machineHold | objects | ["machine:\(.since)", "machine held", "",
      "the machine fails \(.controls | arrays | map(tostring) | join(", ")) on main, with no change to main that explains it: the loop picks no card until they pass again (found by \(.card // "a card"))" | one]),
    # A merge of the landing pull request that GitHub refused (health landingPr, conveyor/lib/push.sh mergeone()): once a refusal.
    (.landingPr | objects | select(.merge.result == "refused") | ["prmerge:\(.number):\(.merge.time)", "merge refused", "",
      "GitHub refused the merge of landing pull request #\(.number), which stays open: \(.merge.reason // "" | one)"]),
    # A card records line the check set aside (health quarantined, conveyor/lib/views.sh check()).
    (.quarantined | arrays | .[] | objects | ["quarantined:\(.line):\(.time)", "record set aside", "",
      "the card records line \(.line) is set aside in quarantined.jsonl: the record check refused its field \(.field | one)"]),
    # Signed out, with why (health ghWhy): a candidate, as ghreach is; record() reports it on its third poll in a row,
    # as one read can fail while gh holds its token (#490).
    (select(.gh | not) | ["gh", "gh signed out", "", "gh is signed out\((.ghWhy | strings | select(. != "") | ": " + one) // "")"]),
    # Signed in, but gh auth status did not answer (health ghReached): a candidate here, as idle is; record() reports it on its third poll in a row.
    (select(.gh and .ghReached == false) | ["ghreach", "GitHub not reached", "", "GitHub not reached: gh is signed in, but gh auth status failed or timed out"]),
    (select(.state == "control record unreadable") | ["control", "picks nothing", "", "the loop picks nothing: \(.reason // "the control record does not read" | one)"]),
    (.cycles | arrays | .[] | arrays | map(tostring) | ["cycle:\(join("-"))", "dependency cycle", (map("#" + .) | join(" ")),
      "issues \(map("#" + .) | join(", ")) depend on each other: none of them will be picked"]),
    # A card that has waited $wake minutes (the pack'"'"'s foreman.waitWake, the snapshot'"'"'s waitWake: read on the belt'"'"'s
    # host, as a remote belt'"'"'s pack is not on this machine; 10 when it gives none) on another card (health waitingOnCard) or
    # for main to change (its live action, mainred.sh mainwait(); the snapshot'"'"'s belt live.at is when that wait
    # began): what it waits on, with that card'"'"'s step and last action, or, for main, each main-red fix card open or
    # blocked. Its key holds the wait'"'"'s start and how many times $wake it has lasted, so each wait wakes once, and
    # again ("still waiting") after each further $wake minutes.
    (.blocked as $hb | (($snap.waitWake | numbers | select(. >= 1)) // 10) as $wake
      | def about($h): ($h | ref) as $r | ([$snap.belt | arrays | .[] | objects | select(.card == $h.card)] | first) as $b
          | ([$hb[] | select(.card == $h.card)] | first) as $x
          | if $b then "\($r) (at \($b.step), last action: \($b.live.action // "none"))"
            elif $x then "\($r) (blocked: \($x.reason))" else "\($r) (\($h.state // "gone"))" end;
      ([$snap.belt | arrays | .[] | objects | select((.name | strings) and (.landed | not)) | about(.)]
        + [$hb[] | select(.name | strings) | about(.)]
        | if . == [] then "no main-red fix card is open" else "main-red fix card " + join(", ") end) as $reds
      | ((.waitingOnCard | arrays | .[] | objects | {c: ., since, on: about(.waitsOn | objects)}),
         ($snap.belt | arrays | .[] | objects | select(.live.action | strings | startswith("waiting for main to change"))
           | {c: ., since: .live.at, on: "main to change (\(.live.action | ltrimstr("waiting for main to change: "))); \($reds)"}))
      | (.since | strings | fromdate?) as $t | (($now - $t) / 60 | floor) as $m | ($m / $wake | floor) as $n | select($n >= 1)
      | (.c | ref) as $r
      | ["wait:\(.c.card):\(.since):\($n)", "card waiting", $r,
          (if $n == 1 then "\($r) has waited \($m) minutes on " else "\($r) is still waiting, \($m) minutes now, on " end) + .on | gsub("\\s+"; " ") | .[0:600]]),
    # Every other kind of Needs you on the Board, from the list the Board reads too (.claude/scripts/dashboard_needs.json), each
    # read from the snapshot field the list names: waiting, before, blocked and stopped (the stopped engine) are read
    # from health, above (the push the Board lists under blocked wakes as "push failing"). A kind added to the list
    # later wakes under its name. Each line is cut alone (one).
    ($kinds[0][] | objects | select(.kind | IN("waiting", "before", "blocked", "stopped") | not) | (.kind | one) as $k | .from as $from
      | $snap | (try getpath($from) catch null) | (if type == "array" then .[] else . end) | objects
      | ((.issue | numbers | "#\(.)") // "") as $n
      | ([.issue, .ref, .commit, .time, .card] | map(select(. != null) | one) | join(":") | if . == "" then "" else ":" + . end) as $id
      | if $k == "pipeline" then ["pipeline:\(.issue)", "pipeline change held", $n,
          "pipeline change held: \($n)\((.parent | numbers | " (follow-up of #\(.))") // ""): \(.title // "")" | one]
        elif $k == "farDeps" then ["farDeps\($id)", "dependency unreadable", $n, "\($n) waits on \(.ref // "") in another repository, which cannot be read: \(.reason // "")" | one]
        elif $k == "engines" then ["engines\($id)", "engine update not taken", "", "the plugin commit \(.commit // "") was not taken: \(.reason // "")" | one]
        elif $k == "testRules" then ["testRules\($id)", "test issues held", "", "the test rules matched \(.matched) files, over the cap of \(.cap) a day, so they filed none" | one]
        elif $k == "prices" then (.models | arrays | map(tostring)) as $m | ["prices:\($m | join(","))", "models with no price", "",
          "\($m | length) models the belt runs or offers have no price: \($m | join(", ")); add them on the Board, Rules, Model prices" | one]
        elif $k == "tests" then ["tests:\(.issue)", "tests failing on main", $n,
          "the whole test fails on main (\(if $n == "" then "no issue filed" else $n end)): \(.cases | if type == "array" then map(tostring) | join(", ") else "no case named" end)" | one]
        else ["\($k)\(if $id == "" then ":" + (tojson | one) else $id end)", $k, $n, "\($k): \($n) \(.title // .reason // tojson)" | one] end),
    (select($idle) | ["idle", "idle", "", "Conveyor is idle: nothing in flight and nothing to pick"])
  | join("\t")'

# unreported <now>: of the problem lines on stdin (<repo> TAB <key> TAB <kind> TAB <issues> TAB <text>), each card
# blocked since two polls or more before <now> that no session has got: no wake was put for it (its key is not in
# conveyor-reported.txt: no watcher ran), or its wake is still in pending (no live session took it). One line each,
# "<repo>: not yet reported: blocked <the card: #N, or a main-red fix card's name>".
unreported() {
  jq -rRs --argjson now "$1" --argjson poll "$POLL" --arg seen "$(cat "$SEEN" 2>/dev/null)" \
    --arg pend "$(cat "$PENDING"/*.wake 2>/dev/null)" '($seen | split("\n")) as $seen | ($pend | split("\n")) as $pend
    | split("\n")[] | select(. != "") | split("\t") | select(.[2] == "blocked") | .[0] as $repo | .[4] as $text
    | ($text | capture(" is blocked since (?<t>[0-9T:-]+Z):") | .t | fromdate? // empty) as $t
    | select($now - $t >= 2 * $poll and (("\($repo)/\(.[1])" | IN($seen[]) | not) or ("\($repo): \($text)" | IN($pend[]))))
    | "\($repo): not yet reported: blocked \($text | sub(" is blocked since .*$"; ""))"'
}

# --status [<project>] (`conveyor.sh foreman status`): each record's state now as short plain text, read from one
# snapshot, with no wake put and nothing marked reported: the belt (its count, "as of <snapshotAt>, the belt has
# changed since" when the card records changed after the snapshot was made, or, while the loop runs then, the count
# now (loop.json's cards and the landed cards not yet pushed, recordsNow) with "the snapshot, as of <snapshotAt>, is behind the card records", and while the loop runs its cards
# building against the cap, loop.json's count now while the snapshot is behind (recordsNow, commands/snapshot.sh), and those waiting on another card, which that count leaves out; then, when the
# snapshot names the engine stopped and ps no longer shows it stopped, "the engine (pid <n>) runs" or "has ended"; then a card a line: issue, or a main-red fix card's name, step, time in step, title cut to 60 characters), the
# cards waiting on other issues and the held issues as issue numbers, the whole-suite run under way (else the last one
# that ended), then every problem a wake names (the blocked cards as NOWBLOCKED gives them), the push failing at once, the suite that ended left out (its line is
# above), and a release-prep started again by its landed fixes (it needs no one), each "needs you: <text>", then each card unreported names, "not yet reported: blocked #N". A record that gives no snapshot is one line, "<repo>: no snapshot (<why>)", the why
# never empty and one line (the last the engine said: of a stack trace, its error); when one read before (keepsnap),
# "<repo>: the last snapshot, made <age> ago (a new one failed: <why>):" in its place, and that snapshot's lines as above. <project> names one
# record of mine; with none, every one of them. Then the watcher's last poll, from
# the poll log: "watcher: last poll ended <time>, took <n> s (<outcomes>)", or "watcher: no poll logged yet". Last, the Foreman's
# waiter: "waiter: listening", "waiter: starting again" or "waiter: down: <why>" (lib.sh status_tail).
STATUS=$SUITE$REF'def num: if type == "number" then "#\(.)" else tostring end;
  (.belt | if type == "array" then length else 0 end) as $n
  # While the snapshot is behind the card records and the loop runs, the count on the belt is the one of now: loop.json'"'"'s
  # cards building and waiting, and the landed cards still on the belt for their push (recordsNow), and the line says
  # the snapshot the card lines below come from is behind (#1107: "0 on the belt" while 5 built).
  | ([.recordsNow | objects | select(.building | numbers) | .building + (.waitingCount // 0) + (.landed | numbers // 0)][0]) as $live
  | (if .recordsNewer == true and $live != null then
      "\($repo): \($live) on the belt now, from loop.json and the card records (the snapshot, as of \(.snapshotAt // "an unknown time"), is behind the card records: it lists \($n))"
    else "\($repo): \($n) on the belt"
      + (if .recordsNewer == true then " (as of \(.snapshotAt // "an unknown time"), the belt has changed since)" else "" end) end)
    # While the snapshot is behind the card records, the loop'"'"'s count is the one loop.json gives now (recordsNow).
    + (((if (.recordsNow | type) == "object" then .recordsNow | {building, waitingCount} else (.health | objects) // {} end) as $b
      | .health | objects | select(($b.building | type) == "number" and (.builderCap | type) == "number")
      | "; building \($b.building) of the cap \(.builderCap)\(if ($b.waitingCount // 0) > 0 then ", \($b.waitingCount) waiting not counted" else "" end)") // ""),
  (.belt | arrays | .[] | objects | "  \(ref) \(.step)\((.waitsOn | objects | select(.issue | numbers) | " on \(ref)") // "")"
    + " \((.stepAt | fromdate? | $now - .) // null | if . == null then "?" else took end) \(.title // "" | tostring | gsub("\\s+"; " ") | .[0:60] | sub(" $"; ""))"),
  (.queue.waiting | arrays | select(length > 0) | "waiting: " + (map(objects | "\(.issue | num) on \(.waitsFor | arrays | map(num) | join(" "))") | join(", "))),
  (.open.held | arrays | select(length > 0) | "held: " + (map(objects | .issue | num) | join(" "))),
  ([.suites | arrays | .[] | objects] as $s | ($s | map(select(.ended == null))) as $run
    | if $run != [] then $run[] | suiteline($now)
      else $s | map(select(.ended != null)) | max_by(.ended) | objects | "last " + suiteline($now) end)'
# The snapshot as the status reads its problems: while it is behind the card records (recordsNow, commands/snapshot.sh),
# its health's blocked and waiting cards are the ones the records hold blocked now, and of them those stopped for the
# owner's yes, so a card blocked or stopped for the yes since the snapshot was made is named as such, and one retried
# or landed since is not (#1101); being read now, their lines carry no "(as of <time>)" (blockedNow). The watcher's
# polls read the snapshot's own: a card it holds blocked is later waiting or not.
NOWBLOCKED='(if ((.recordsNow | objects | [.blocked, .waiting] | all(type == "array")) // false) and (.health | type) == "object" then
    .health.blocked = [.recordsNow.blocked[] | objects | select(.card | type == "string")]
    | .health.waiting = [.recordsNow.waiting[] | objects | select(.card | type == "string")] | .blockedNow = true
  else . end) | '
# The last snapshot of a record that read, kept by the status and each poll ($FD/conveyor-snapshot-<repo>.json,
# written whole and renamed into place, readable by this user alone: it holds the accounts' email addresses): the status
# shows it when a new one does not read.
keepsnap() { # <repo> <snapshot>
  { mkdir -p "$FD" && (umask 077 && printf '%s\n' "$2" > "$FD/conveyor-snapshot-$1.json.$$") && mv -f "$FD/conveyor-snapshot-$1.json.$$" "$FD/conveyor-snapshot-$1.json"; } 2>/dev/null \
    || rm -f "$FD/conveyor-snapshot-$1.json.$$"
}
# recheck <repo> <main> <snapshot>: the snapshot, with only the blocked cards (health.blocked) that `conveyor.sh health`,
# read from the card records and the retried lines now, still lists blocked, when the records changed after the
# snapshot was made (recordsNewer) and it lists a blocked card (#1114: a card retried, picked again or building since
# was named blocked again, and the Foreman acted on it again). When health does not read, the snapshot as it is.
recheck() {
  local cards
  if jq -e '.recordsNewer == true and (.health.blocked | arrays | length > 0)' <<<"$3" >/dev/null 2>&1 \
    && cards=$(ask "$1" "$2" health 2>/dev/null | jq -ce 'select(type == "object" and (.blocked | type == "array")) | [.blocked[] | objects | .card]' 2>/dev/null) \
    && jq -c --argjson c "$cards" '.health.blocked |= map(select(.card | IN($c[])))' <<<"$3" 2>/dev/null; then return; fi
  printf '%s\n' "$3"
}

# engstate <pid>: the state of that process now, as ps shows it on the host the snapshot comes from (over the host
# file's ssh target, as ask runs there), with no spaces; empty when no such process runs (ps exits 1 and says
# nothing); nonzero when the state does not read (ssh or ps failed).
engstate() {
  local target out rc
  target=$(host_ssh)
  if [ -n "$target" ]; then
    out=$(timeout -k 2 "${ASK_LIMIT:-45}" ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "LC_ALL=C ps -o stat= -p $1" < /dev/null 2>/dev/null); rc=$?
  else out=$(LC_ALL=C ps -o stat= -p "$1" 2>/dev/null); rc=$?; fi
  out=${out//[[:space:]]/}
  if [ "$rc" = 0 ] && [ -n "$out" ]; then echo "$out"; elif [ "$rc" = 1 ] && [ -z "$out" ]; then echo; else return 1; fi
}

if [ "${1:-}" = --status ]; then
  now=${CONVEYOR_FOREMAN_NOW:-$(date +%s)} n=0
  errf=$(mktemp) || exit 1; trap 'rm -f "$errf"' EXIT
  while IFS=$'\t' read -r repo main; do
    [ -z "${2:-}" ] || [ "$repo" = "$2" ] || continue
    n=$((n + 1))
    rec=$(ask "$repo" "$main" snapshot 2>"$errf"); rc=$?
    if [ "$rc" != 0 ] || ! jq -e objects <<<"$rec" >/dev/null 2>&1; then
      # Why, never an empty "()": the last line the engine said (a snapshot made anew says so before its long work;
      # of a program's stack trace, its error), else the ask's wait it ran past (a killed run says nothing), else its exit.
      why=$(grep -v '^[[:space:]]*$' "$errf" | tail -n 1 | tr -s '[:space:]' ' ' | cut -c1-200 | sed 's/^ *//; s/ *$//')
      [ -n "$why" ] || if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then why="it took over ${ASK_LIMIT:-45} s and was stopped"
        elif [ "$rc" = 0 ]; then why="the answer is not a snapshot"; else why="exit $rc, with nothing said"; fi
      # The last snapshot that read, with its age (its health record's time) and the why, in its place; else none.
      rec=$(cat "$FD/conveyor-snapshot-$repo.json" 2>/dev/null) && jq -e objects <<<"$rec" >/dev/null 2>&1 \
        || { echo "$repo: no snapshot ($why)"; continue; }
      age=$(jq -r --argjson now "$now" "$SUITE"'[.health.time | strings | fromdate?][0] | if . == null then "at an unknown time"
        elif $now - . < 60 then "under a minute ago" else "\($now - . | took) ago" end' <<<"$rec" 2>/dev/null) && [ -n "$age" ] || age='at an unknown time'
      echo "$repo: the last snapshot, made $age (a new one failed: $why):"
    else keepsnap "$repo" "$rec"; fi
    rec=$(recheck "$repo" "$main" "$rec")
    # The engine the snapshot names stopped (health engineStopped), read again now as ps shows it on the machine the
    # snapshot came from (#1107): a snapshot made before a SIGCONT, minutes old, still names it stopped. One that runs
    # or has ended is no longer a stopped engine, and a card it held is no longer held by it (one whose own process is
    # stopped stays, as that stop; one with an overdue test, a wait or a retry stays as that). A state that does not
    # read changes nothing.
    eng=''
    if IFS=$'\t' read -r ep es < <(jq -r '.health.engineStopped | objects | select(.pid | numbers) | [.pid, .since // "an unknown time"] | @tsv' <<<"$rec" 2>/dev/null) \
      && [[ $ep =~ ^[0-9]+$ ]] && st=$(engstate "$ep") && [[ $st != T* ]] \
      && r2=$(jq -c '.health.stuck |= map(if .stopped.of? == "engine" then
          ((.stopped.own | objects | select(.pid | numbers) | {pid, since, pids, of: "card"}) // null) as $o
          | if $o then .stopped = $o elif (.cases | type) == "array" or (.waitedOn | type) == "array" or .did != null then del(.stopped) else empty end
        else . end)
        | .health.engineStopped = null' <<<"$rec" 2>/dev/null); then
      eng="$repo: the engine (pid $ep) $([ -n "$st" ] && echo "runs (state $st now)" || echo "has ended"); the snapshot had it stopped since $es"
      rec=$r2
    fi
    jq -r --arg repo "$repo" --argjson now "$now" "$STATUS" <<<"$rec" 2>/dev/null || echo "$repo: the snapshot's belt does not read"
    [ -z "$eng" ] || echo "$eng"
    if probs=$(jq -r --argjson push -1 --argjson now "$now" --argjson poll "$POLL" --argjson await '[]' --argjson hist '[null]' --slurpfile kinds "$KINDS" "$NOWBLOCKED$PROBLEMS" <<<"$rec" 2>/dev/null); then
      awk -F'\t' '$1 != "" && $2 != "suite ended" && $2 != "release started again" { print "needs you: " $4 }' <<<"$probs"
      awk -v r="$repo" '$0 != "" { print r "\t" $0 }' <<<"$probs" | unreported "$now" | cut -d' ' -f2-
    else echo "needs you: unknown, the snapshot holds no health record"; fi
  done <<<"$RECS"
  [ "$n" -gt 0 ] || { echo "foreman status: $2 is none of this Foreman's projects ($(cut -f1 <<<"$RECS" | paste -sd' ' -))" >&2; exit 2; }
  status_tail
  exit 0
fi

mkdir -p "$FD" && touch "$SEEN" || exit 1
while IFS=$'\t' read -r r _; do touch "$FD/await-$r.txt" "$FD/await-done-$r.txt" || exit 1; done <<<"$RECS"

# One record's problems now, each line prefixed with its repo: <repo> TAB <key> TAB <kind> TAB <issues> TAB <text>.
record() { # <repo> <main> <now> <await>
  local repo=$1 main=$2 now=$3 await=$4 rec cur first last err held
  local down=$FD/conveyor-down-$repo.txt idle=$FD/conveyor-idle-$repo.txt ghreach=$FD/conveyor-ghreach-$repo.txt ghout=$FD/conveyor-ghout-$repo.txt stuckf=$FD/conveyor-stuck-$repo.txt errf=$FD/conveyor-watch-$repo.err
  local histf=$FD/conveyor-history-$repo.json
  # The history is asked for only when an awaited issue is not pushed by the snapshot alone; one that does not read
  # is left out (null), and the next poll asks again. It goes to jq in a file: a busy day's history is over the
  # 128 KB a single argument may hold (#544).
  readsnap() { # <ask limit, seconds>: rec, the history file and cur, the problems; nonzero when the record does not read (the ask's exit when it failed)
    rec=$(ASK_LIMIT=$1 ask "$repo" "$main" snapshot 2>"$errf") || return
    ! jq -e objects <<<"$rec" >/dev/null 2>&1 || { keepsnap "$repo" "$rec"; rec=$(recheck "$repo" "$main" "$rec"); }
    { jq -e --argjson await "$await" "${PUSHED}"'pushed(null) as $p | any($await[]; .[0] | IN($p[]) | not)' <<<"$rec" >/dev/null 2>&1 \
      && ASK_LIMIT=$1 ask "$repo" "$main" history 2>>"$errf" | jq -ce objects > "$histf" 2>>"$errf" || echo null > "$histf"; }
    cur=$(jq -r --argjson push "$PUSH_S" --argjson now "$now" --argjson poll "$POLL" --argjson await "$await" --slurpfile hist "$histf" --slurpfile kinds "$KINDS" "$PROBLEMS" <<<"$rec" 2>>"$errf")
  }
  # A snapshot that does not read, or not within the first wait (one made anew from the whole card records takes
  # minutes), is no reason to wake late on a card that needs the owner: `conveyor.sh health` holds the blocked, waiting
  # and before entries and needs no snapshot. hcur: those problems, as PROBLEMS gives them; nonzero when health does not read.
  readhealth() {
    local h all
    h=$(ask "$repo" "$main" health 2>>"$errf") \
    && all=$(jq -r --argjson push "$PUSH_S" --argjson now "$now" --argjson poll "$POLL" --argjson await '[]' --argjson hist '[null]' --slurpfile kinds "$KINDS" "{health: .} | $PROBLEMS" <<<"$h" 2>>"$errf") \
    && hcur=$(awk -F'\t' '$1 ~ /^(blocked|waiting|before):/' <<<"$all")
  }
  # The standing kind review-retry (lib/standing.sh), while the snapshot's pack turns it on (snapshot standing): each
  # card blocked by its review (card.sh: "the fix for [P1] ... did not hold after <n> rounds", as the Board's reviewWhy
  # reads it, with any notes block() adds after it in brackets, lib/push.sh) and not reported yet is given back with `conveyor.sh retry <issue>` on the record's host, and the act is
  # logged there (`auto act review-retry`: standinglog). Its line then keeps only its key: it wakes nothing, and is not
  # retried again while a snapshot still lists it. A retry that fails, or an act that is not logged, wakes as the block
  # does, with why. Another block, or a main-red fix card (no issue), wakes as before.
  reviewretry() {
    local card issue out rc note
    jq -e '.standing | arrays | index("review-retry") != null' <<<"$rec" >/dev/null 2>&1 || return 0
    while IFS=$'\t' read -r card issue; do
      ! grep -qxF "$repo/blocked:$card" "$SEEN" || continue
      out=$(ask "$repo" "$main" retry "$issue" 2>&1); rc=$?
      if [ "$rc" = 0 ]; then
        note=''; out=$(ask "$repo" "$main" auto act review-retry "retried #$issue: its card $card was blocked by its review" 2>&1) \
          || { rc=$?; note="#$issue was retried (review-retry), but the act was not logged"; }
      else note="the review-retry of #$issue failed"; fi
      out=$(tr -s '[:space:]' ' ' <<<"$out" | sed 's/^ *//; s/ *$//' | cut -c1-200)
      cur=$(K="blocked:$card" N="$note${note:+: ${out:-exit $rc}}" awk -F'\t' 'BEGIN { OFS = FS }
        $1 == ENVIRON["K"] { if (ENVIRON["N"] == "") { print $1 "\t\t\t"; next } $4 = $4 "; " ENVIRON["N"] } { print }' <<<"$cur")
    done < <(jq -r '.health.blocked[] | select((.issue | numbers) > 0 and (.reason | strings
      | test("\\Athe fix for \\[P[0-3]\\][\\s\\S]* did not hold after [0-9]+ rounds?( \\[[\\s\\S]*\\])?\\z"))) | "\(.card)\t\(.issue)"' <<<"$rec" 2>/dev/null)
  }
  # A blocked card reported and still blocked 30 minutes after a poll first listed it wakes again (#877): a Foreman
  # turn that neither cleared the block nor asked the owner left it with no reminder. $blockf holds each blocked card
  # of the last snapshot, its block's since and the poll that first listed it ("<card> TAB <since> TAB <epoch>"); a
  # card the snapshot no longer lists (retried, unblocked, shut or landed), or one blocked anew (a new since), starts
  # again. Its key holds the hours past those 30 minutes, so it wakes at 30 minutes and once each hour after. While an
  # open question of the record's decision ledger (lib.sh ledger) names the card's issue ("#<n>"), the key is kept with
  # no text: it wakes nothing and stays reported, so that hour gives no wake after the answer either. A card that
  # review-retry gave back (its line has no text) is left out.
  stillblocked() {
    local blockf=$FD/conveyor-blocked-$repo.txt asked out
    asked=$(d=$(ledger "$repo" "$main") && jq -cs '[group_by(.id)[] | last | select(.answeredAt == null) | .question | strings
      | scan("#([0-9]+)(?![0-9])") | "#" + .[0]] | unique' "$d/.claude/metrics/decisions.jsonl" 2>/dev/null) || asked='[]'
    out=$(jq -rRs --argjson now "$now" --argjson asked "$asked" --arg seen "$(cat "$SEEN")" --arg state "$(cat "$blockf" 2>/dev/null)" --arg repo "$repo" "$SUITE"'
      ($seen | split("\n")) as $seen
      | ($state | split("\n") | map(split("\t") | select(length == 3) | {key: "\(.[0])\t\(.[1])", value: (.[2] | tonumber? // empty)}) | from_entries) as $first
      | split("\n")[] | split("\t") | select(length == 4 and (.[0] | startswith("blocked:")) and .[3] != "")
      | (.[0] | ltrimstr("blocked:")) as $card | .[2] as $ref
      | (.[3] | capture(" is blocked since (?<t>[0-9T:-]+Z): (?<why>[\\s\\S]*)\\z")) as $b
      | ($first["\($card)\t\($b.t)"] // $now) as $f
      | "S\t\($card)\t\($b.t)\t\($f)",
        (($now - $f - 1800) as $e | select($e >= 0 and ("\($repo)/blocked:\($card)" | IN($seen[]))) | ($e / 3600 | floor) as $n
          | (if $ref | IN($asked[]) then "" else "\($ref) has been blocked for \($now - ($b.t | fromdate? // $f) | took): \($b.why)" end) as $text
          | "R\tstillblocked:\($card):\($b.t):\($n)\tstill blocked\t\($ref)\t\($text)")' <<<"$cur" 2>>"$errf") || return 0
    awk -F'\t' -v OFS='\t' '$1 == "S" { print $2, $3, $4 }' <<<"$out" > "$blockf.tmp" && mv "$blockf.tmp" "$blockf"
    cur+=$'\n'$(awk -F'\t' -v OFS='\t' '$1 == "R" { print $2, $3, $4, $5 }' <<<"$out")
  }
  # The outage so far ($down: its first failed poll, its last and how many failed in a row): a gap of more than three
  # polls since the last failed one is a new outage, timed from now. goes: set when the last failed poll's outage goes
  # on, so its reported unreachable key is still this outage's.
  local fails
  read -r first last fails 2>/dev/null < "$down" || first=
  local goes=1
  [[ $first =~ ^[0-9]+$ ]] && [[ $last =~ ^[0-9]+$ ]] && [ $((now - last)) -le $((POLL * 3)) ] || { first=$now goes='' fails=0; }
  [[ $fails =~ ^[0-9]+$ ]] || fails=0
  # A failed read that would make the record unreachable is read once more with the longer wait SLOW_S first (#241):
  # under a high machine load a live engine's snapshot can take longer than the first wait. An engine that fails
  # fast (stopped, its host down) fails the second read as fast, so its wake is not later; one that hangs wakes up to
  # SLOW_S seconds later. Before it, health is read (readhealth); when health lists a problem not reported yet, the
  # longer read waits for the next poll, so that wake is not SLOW_S seconds late, and the record is not called
  # unreachable at this poll. The poll's outcome for the poll log: ok, slow (stopped at its wait) or failed, and the
  # read it used (snapshot, health or none).
  local hcur="" hnew="" tried="" rc outcome=ok used=snapshot
  readsnap "${ASK_LIMIT:-45}"; rc=$?
  if [ "$rc" != 0 ]; then
    if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then outcome=slow; else outcome=failed; fi
    used=none fails=$((fails + 1))
    if readhealth; then
      used=health
      hnew=$(awk -F'\t' -v p="$repo/" '!cur { seen[$0]; next } $1 != "" && !((p $1) in seen)' "$SEEN" cur=1 - <<<"$hcur")
    fi
    # Unreachable only from the third failed poll in a row on (#715: most outages cleared on the poll after the first).
    if [ -z "$hnew" ] && [ "$fails" -ge 3 ] && [ $((now - first)) -ge "$DOWN_S" ]; then
      tried=1; readsnap "$SLOW_S"; rc=$?
      [ "$rc" != 0 ] || { outcome=slow used=snapshot; }
    fi
  fi
  printf '%s: %s, read %s\n' "$repo" "$outcome" "$used" >> "$POLLF"
  if [ "$rc" = 0 ]; then
    rm -f "$down"
    # Idle is a problem only on the second poll in a row that lists it ($idle marks the first); GitHub not reached
    # and gh signed out only on the third (#715: most cleared on the poll after the first). $ghreach and $ghout hold
    # how many polls in a row listed them, 1 or 2, and the GitHub read of the last (health ghRead, ghok()'s GHREAD): a
    # snapshot given again from the cache, or built again from the same GitHub folder read, is the same read, so it
    # counts as no new poll (#490). Health's own time is not the read's: a snapshot built again after a card update has
    # a new one.
    if ! grep -q $'^idle\t' <<<"$cur"; then rm -f "$idle"
    elif [ ! -e "$idle" ]; then touch "$idle"; cur=$(grep -v $'^idle\t' <<<"$cur"); fi
    local hread; hread=$(jq -r '.health.ghRead | strings' <<<"$rec" 2>/dev/null)
    thirdpoll() { # <key> <its file>: the key left in cur only on the third poll in a row that lists it
      local n r
      grep -q "^$1"$'\t' <<<"$cur" || { rm -f "$2"; return; }
      read -r n r 2>/dev/null < "$2" && [[ $n =~ ^[0-9]+$ ]] || n=0
      { [ -n "$hread" ] && [ "$n" != 0 ] && [ "$r" = "$hread" ]; } || n=$((n + 1))
      [ "$n" -lt 3 ] || return 0
      printf '%s %s\n' "$n" "$hread" > "$2"; cur=$(grep -v "^$1"$'\t' <<<"$cur")
    }
    thirdpoll ghreach "$ghreach"; thirdpoll gh "$ghout"
    # A stuck card is a problem only when two snapshots in a row, at least a poll apart, list it: one reading can
    # fall between two lines of a step that goes on, or catch a stop that a SIGCONT soon ends (a stopped one).
    # $stuckf holds each stuck key of the last snapshot and when a snapshot first listed it ("<key> TAB <epoch>"); a key the snapshot does not list is dropped from it. When that
    # file cannot be written, the stuck cards are reported at once.
    if touch "$stuckf" && : > "$stuckf.tmp" && held=$(awk -F'\t' -v now="$now" -v poll="$POLL" -v f="$stuckf" '
      FILENAME == f { t[$1] = $2; next }
      $1 ~ /^(stuck|stopped):/ { s = ($1 in t) ? t[$1] : now; print $1 "\t" s > (f ".tmp"); if (now - s < poll) next }
      { print }' "$stuckf" - <<<"$cur") && mv "$stuckf.tmp" "$stuckf"; then cur=$held; fi
    reviewretry
    stillblocked
  else
    # A failed poll breaks a run of idle polls, of polls that did not reach GitHub, and of polls with gh signed out.
    grep -qxF "$repo/idle" "$SEEN" || rm -f "$idle"
    grep -qxF "$repo/ghreach" "$SEEN" || rm -f "$ghreach"
    grep -qxF "$repo/gh" "$SEEN" || rm -f "$ghout"
    echo "$first $now $fails" > "$down"
    # Its reported keys stay reported (no text: a key already reported is never printed again). When health read, its
    # blocked, waiting and before entries are this poll's (hcur): one it no longer lists is dropped, so it wakes again
    # when it comes back. The unreachable key is this poll's only when the longer read was made; a poll that woke on
    # health in its place keeps it reported while the same outage goes on, so that outage is not reported again at the
    # next failed read. A new outage drops it, so its own failed longer read is reported.
    cur=$(awk -v p="$repo/" -v h="$used" -v t="$tried" -v g="$goes" 'index($0, p) == 1 && ($0 != p "unreachable" || (t == "" && g != "")) && !(h == "health" && substr($0, length(p) + 1) ~ /^(blocked|waiting|before):/) { print substr($0, length(p) + 1) "\t\t\t" }' "$SEEN")
    [ -z "$hcur" ] || cur+=$'\n'$hcur
    err=$(tr -s '[:space:]' ' ' < "$errf" | tail -c 200)
    # The install this watcher runs from, removed under it, fails every poll on its own missing files: the line names
    # that install and the fix, not the file it missed.
    [ -f "$KINDS" ] || err="the Conveyor install ${FHERE%/conveyor/foreman} the Foreman's watcher runs from is gone; run /conveyor-belt:setup in $2 to install the project's engine again"
    [ -z "$tried" ] || cur+=$'\n'"unreachable"$'\t'"unreachable"$'\t\t'"no snapshot for $(((now - first) / 60)) minutes${err:+ ($err)}"
  fi
  awk -F'\t' -v r="$repo" '$1 != "" { print r "\t" $0 }' <<<"$cur"
}

# The wake for the new problems (<repo> TAB <key> TAB <kind> TAB <issues> TAB <text> lines): the first line names
# every issue by kind, per project, then one line per item.
wake() {
  jq -rRs 'split("\n") | map(select(. != "") | split("\t") | {repo: .[0], kind: .[2], issues: .[3], text: .[4]}) as $all
    | ($all | map(.repo) | unique) as $repos
    | ["needs the owner'"'"'s yes", "blocked", "stuck", "unreachable", "landed"] as $first
    | "Conveyor: " + ([$repos[] as $r | [$all[] | select(.repo == $r)] as $mine
        | ($first + ($mine | map(.kind) | unique - $first)) as $kinds
        | "\($r): " + ([$kinds[] as $k | [$mine[] | select(.kind == $k)] | select(length > 0)
            | (map(.issues | select(. != "")) | join(" ")) as $n | if $n == "" then $k else "\($k): \($n)" end] | join("; "))]
        | join(" | ")),
      ($all[] | "\(.repo): \(.text)")'
}

# The landings held (record(): "held landing" rows) wait for the last awaited issue in flight to land and wake in one. They
# go at once when another wake of the Conveyor watcher goes, or when the waiter has restarted since they were first held.
# conveyor-held.txt keeps, while any is held, the waiter's pid from then and each held row, so its commit is still named
# when the batch ends after the snapshot's day (the snapshot lists a day's landings); the rows themselves are made again
# every poll, as nothing reports them yet. A poll with no row for a kept landing (its record did not read) keeps it.
# holdlandings() only reads the file: it sets cur (the held rows left out, or made plain "landed" rows) and hnew (what the
# file holds next). poll() writes hnew once the wake is in pending, so a wake that is not put (the session's process has
# ended, pending not written) leaves the file as it was and the next poll sends the same landings.
holdlandings() {
  local wp=- who old='' stored='' held left
  hnew=''
  if [ -e "$HELDF" ]; then
    old=$(head -n 1 "$HELDF"); stored=$(tail -n +2 "$HELDF")
    cur=$(awk -F'\t' -v OFS='\t' 'FILENAME == ARGV[1] { t[$1 FS $2] = $5; next }
      $2 ~ /^landed:/ && ($3 == "held landing" || $3 == "landed") && $5 !~ / landed as / && (($1 FS $2) in t) { $5 = t[$1 FS $2] } { print }' <(printf '%s\n' "$stored") - <<<"$cur")
  fi
  left=$(awk -F'\t' 'FILENAME == ARGV[1] { k[$1 FS $2]; next } !(($1 FS $2) in k)' <(printf '%s\n' "$cur") <(printf '%s\n' "$stored"))
  held=$(awk -F'\t' '$3 == "held landing"' <<<"$cur")
  [ -n "$held" ] || { hnew=$(heldrows "$old" "$left"); return 0; }
  { read -r wp _ < "$FD/waiter.pid"; } 2>/dev/null
  who=${wp:--}; : "${old:=$who}"
  if [ "$old" != "$who" ] || awk -F'\t' '!cur { seen[$0]; next } $3 != "held landing" && $2 != "" && !(($1 "/" $2) in seen) && $5 != ""' "$SEEN" cur=1 - <<<"$cur" | grep -q .; then
    cur=$(awk -F'\t' -v OFS='\t' '$3 == "held landing" { $3 = "landed" } { print }' <<<"$cur"); hnew=$(heldrows "$old" "$left")
  else cur=$(awk -F'\t' '$3 != "held landing"' <<<"$cur"); hnew=$(heldrows "$old" "$held"$'\n'"$left"); fi
}
heldrows() { # <pid> <rows>: the file's content for the held landings kept, nothing when there are none
  local rows; rows=$(grep . <<<"${2:-}")
  [ -z "$rows" ] || { printf '%s\n' "$1"; printf '%s\n' "$rows"; }
}
heldsave() { # the file holds hnew, or is removed when hnew is empty
  [ -n "$hnew" ] || { rm -f "$HELDF"; return 0; }
  printf '%s\n' "$hnew" > "$HELDF.tmp" && mv "$HELDF.tmp" "$HELDF"
}

poll() { # 0 when a wake was put in pending; 2 when one was due but the session's process has ended
  local now=${CONVEYOR_FOREMAN_NOW:-$(date +%s)} cur='' new late await repo main df hnew
  while IFS=$'\t' read -r repo main; do
    # [issue, its lines in await-<repo>.txt] for each awaited issue of the record past what was dropped: the count is
    # in its landed key, so an issue awaited again after its wake is a new key.
    await=$(awk 'FILENAME == ARGV[1] { done[$1] = $2; next } /^[1-9][0-9]*$/ { n[$0]++ }
      END { for (i in n) if (n[i] > done[i] + 0) print "[" i "," n[i] "]" }' "$FD/await-done-$repo.txt" "$FD/await-$repo.txt" | jq -sc sort)
    cur+=$(record "$repo" "$main" "$now" "$await")$'\n'
  done <<<"$RECS"
  holdlandings || return 1
  new=$(awk -F'\t' '!cur { seen[$0]; next } $2 != "" && !(($1 "/" $2) in seen) && $5 != ""' "$SEEN" cur=1 - <<<"$cur")
  # A new wake also names each blocked card an earlier wake holds that no session has got (unreported): the new
  # problems are this wake's own, so they are left out of that list.
  if [ -n "$new" ]; then
    [ -z "${CONVEYOR_FOREMAN_SESSION_PID:-}" ] || kill -0 "$CONVEYOR_FOREMAN_SESSION_PID" 2>/dev/null || return 2
    late=$(awk -F'\t' '!cur { n[$1 FS $2]; next } !(($1 FS $2) in n)' - cur=1 <<<"$new" <(printf '%s' "$cur") | unreported "$now")
    { wake <<<"$new"; [ -z "$late" ] || printf '%s\n' "$late"; } | pending_put || return 1
  fi
  awk -F'\t' '$2 != "" { print $1 "/" $2 }' <<<"$cur" > "$SEEN.tmp" && mv "$SEEN.tmp" "$SEEN" || return 1
  heldsave || return 1
  # An awaited issue is dropped only once its wake is in pending or was reported before; await-<repo>.txt is never
  # rewritten.
  while IFS=$'\t' read -r repo main; do
    df=$FD/await-done-$repo.txt
    awk -v p="$repo/landed:" 'FILENAME == ARGV[1] { if (index($0, p) == 1 && split(substr($0, length(p) + 1), k, ":") == 2) l[k[1]] = k[2]; next } { d[$1] = $2 }
      END { for (i in l) if (l[i] + 0 > d[i] + 0) d[i] = l[i]; for (i in d) print i, d[i] }' "$SEEN" "$df" > "$df.tmp" \
      && mv "$df.tmp" "$df" || return 1
  done <<<"$RECS"
  [ -n "$new" ]
}

utc() { TZ=UTC0 printf '%(%Y-%m-%dT%H:%M:%SZ)T' "$1"; }
while :; do
  t0=$EPOCHSECONDS; : > "$POLLF"
  poll; rc=$?
  # The poll log (PLOG): one line a poll, so a late wake can be told from the logs: its start, end, seconds taken,
  # each record's outcome (record()) and whether it woke. Past PLOG_MAX lines it keeps the newest half.
  t1=$EPOCHSECONDS
  { printf '%s %s %ss %s; %s\n' "$(utc "$t0")" "$(utc "$t1")" "$((t1 - t0))" "$(paste -sd'|' - < "$POLLF" | sed 's/|/ | /g')" \
      "$(case $rc in 0) echo woke ;; 2) echo "no wake: the session's process $CONVEYOR_FOREMAN_SESSION_PID has ended" ;; *) echo 'no wake' ;; esac)" >> "$PLOG"
    [ "$(wc -l < "$PLOG")" -le "$PLOG_MAX" ] || { tail -n $((PLOG_MAX / 2)) "$PLOG" > "$PLOG.tmp" && mv "$PLOG.tmp" "$PLOG"; }; } 2>/dev/null
  [ "$rc" != 0 ] && [ "$rc" != 2 ] || exit 0
  [ "${1:-}" != --once ] || exit 1
  sleep "$POLL"
done
