#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# A part of dashboard.sh, sourced by it, never run: the data contract of data.js, the jq program that cuts the page's
# parts (PANELS_JQ) and the builds of data.js (render, publish, republish).
#
# The data contract: {updatedAt, panels}. panels holds one part per panel of the page, under the panel's id, and a
# panel reads its own part and no other: {error, data}. error (a sentence) with data null means the part could not
# be read at all; a part read in part carries the reason beside the missing piece (cardsError, limitError, ...). A
# figure that was not read is null, never 0. The parts:
#   needs   cards {waiting, blocked} (null when Conveyor did not answer; each card with its reviews and its track,
#           where the step a blocked card stopped in is failed, with its seconds; and farDeps: each open issue's
#           dependency in another repository that could not be read, so the issue waits), tests (for each record whose whole
#           test on main fails now: the issue filed for it, the failing cases and the commits it failed between), prices
#           (for each record whose loop found models it runs or offers with no price: repo, models), decisions (null when no named ledger
#           read; decisionsError names each record whose ledger did not read, beside the decisions of those that did),
#           retrying (each landed card whose push of main failed and is tried again, not one whose issue GitHub kept open: repo, card, issue, title, url, and fix, the
#           issue of a card on the belt whose parent it is, else null), retried (the cards the live feed says
#           `retry` gave back, but those of held issues: repo, card, issue; none without a live feed), kinds (the kinds of Needs you, in order, as
#           dashboard_needs.json beside this script lists them: kind, from, title) and entries (for each kind, every record's
#           entries of it: repo, url, card, issue, title, reason, since).
#   belt    cards: every open card (but a landed card whose push failed, while Landed today shows it) with its step, the time the step began, model, its effort (null when not known), tokens and usd so far (reading
#           false and usd null before any token is read), its finished reviews, its track (the six steps Build, Review,
#           Fix, Test, Land, Push, with every recorded step as its detail) and its times: start (the first pick-up
#           of its work), pickedAt, priorSec and totalSec, as the snapshot gives them. No time is estimated.
#           A card that has landed stays here (landed true) until it is pushed and its issue is closed (with the rule
#           "Push when a card lands" off, the snapshot leaves an unpushed one out: Landed today shows it). cap: the card
#           cap (every project's own cap together; null when none is known), never the machine's cap: the cards counted
#           against it are the loop's own count, not the machine's.
#   belt3d  the Belt 3D panel, cut from the parts above and nothing else: repos, belt (each belt card's repo, card,
#           issue, title, url, step, stepAt, landed, waitsOn, usd, turns (its live record's), its reviews (round,
#           verdict, counts) and its track's steps, at, since, tests and files, and its records' name and at, and
#           replyCheck on a fix the Done-when check on a reply started), queue
#           ({next, held: the issues the
#           control record holds and those a rule or the owner's yes keeps from the pick while they wait (keptWaits),
#           each with waitsFor (what it waits on, [] for none), waiting: the snapshot's queue.waiting, which holds none
#           of them, each with waitsFor}, each issue's repo, issue, title, url; null when GitHub
#           did not list the issues), needs (every card of needs: kind waiting (its reason the visible change) or
#           blocked, with its reason, since, reviews, track and its metrics' usd) and landed (today's: repo, card,
#           issue, title, url, time, usd, its reviews' rounds and its track, as belt's but no records), and deck (what the deck behind
#           the floor reads out: host, state (the machine's, as machine's), used (the belt cards holding a slot, every
#           project's) and cap (the slots in force, as machine's); the page's project filter leaves it whole, as the head).
#   queue   next (the issues the loop takes next, in its order), held (how many open issues are held: the snapshot's
#           open.held, the Board's Held column, less those landed and not pushed; null when a record does not list them),
#           awaitingDeploy (the open issues labelled awaiting-deploy: built, waiting for the owner's PROD deploy; each with
#           issue, title, since) and waiting (the open issues that wait on an open issue they depend on and that the
#           loop would pick once it lands, as the snapshot's queue.waiting has them: none held or skipped, each with
#           waitsFor); all null when GitHub did not list the issues.
#   The lists that grow with landed cards (landed's cards, declined's rest, metrics' cards, cost's perCard and
#   unpriced) hold the newest the snapshot keeps (conveyor/README.md, The snapshot); --history builds these four
#   parts again from every entry, for the page server's GET /history.
#   landed  cards: the cards that landed today, each with its review count, time, its start and tookSec (from the first
#           pick-up of its work to the landing, the snapshot's totalSec), usd, its reviews in order (rounds, each with judge:
#           what the judge made of it, as the snapshot gives it), its fixes (fix rounds) and its track.
#   release records: each record's repo, url (its repository's https address, else null), release (main's newest tag,
#           the commits since it, the next version, whether main holds its notes, main's head, whether it releases
#           with Conveyor), suites (its whole-suite runs) and suiteMachine (its control record's rule for where a release's suite
#           runs, null for none) and suiteMode (its rule for how that suite runs its files, serial or parallel, null for none), as the snapshot gives them.
#   declined lines: the review findings the Declined panel shows (not dismissed, not built, at most 7 days old), of every
#           record, newest first: each with repo, repoUrl (its repository's https address, else null), id, time, card, issue, url, finding, by (who declined it: code, judge
#           or owner), why, built (the issue "File as issue" filed for it, else null), dismissed ({time, by}, else null),
#           round and findings (the review the judge declined it in and that review's findings as the judge numbered
#           them, [{n, finding}], else null), as the snapshot's declined gives them; rest: every other line, so, as its declinedRest gives them;
#           heals: each record's self-heals list, {repo, repoUrl, sorted (its last sort of the queued follow-ups, or null), areas
#           ([{area, count}]), entries (each with repo, repoUrl, id, time, card, issue, url, area, finding, why, effect),
#           docs (its docs list, {areas, entries} alike)}, as its selfheals gives it.
#   health  host {name, reachable, error}, records (each record's steered (the host answer's), repoUrl (its repository's https
#           address, else null), snapshotAt (when the build of its kept snapshot began, null from a snapshot
#           without it), loop, state (running, paused, stopped, as
#           its control record says; a loop not meant to run is off, not a fault), newest line, stuck cards, pushes,
#           cycles: the dependency cycles, flaky: the snapshot's flaky cases {case, count, issue, files, url}, null from a snapshot
#           without them, untimed: how many of the last card test runs recorded no test times, null from a snapshot
#           without it, unchecked: how many landed cards skipped a lint command for a missing tool, null likewise, report: the pack's test.report (the test runner setup found and how its times are read), null
#           likewise, timesPlan: what Record test times would do ({kind: report | wrap | card, ...}), null when no plan applies or from a snapshot without it, routes: each Claude route, subscription and proxy, with its state, null likewise, quarantined:
#           the lines of the card records set aside as not whole records {line, field, time}, null likewise,
#           serviceOld: the machine's Conveyor on another commit that refuses the pack {commit, refused, project}, null
#           when it reads it, or likewise, engineStopped: the engine stopped by a signal {pid, since, pids: it and each
#           stopped process under it}, null when it runs or likewise), limit (this machine's usage-limit reading: its cost, Codex and API spend figures), limits (the
#           weekly limit reading of each account the cards run on, as each record's guard reads it: limitsOf), accounts (every Claude account read here
#           and on the host, each with its own usage and what it is used for: accountsOf), stream
#           ({live, heardAt, since, error, writtenAt}: whether Conveyor's part is the live feed's, when the host was last
#           heard from, and when the feed last wrote it), update (--update's last word: {checkedAt, head, error, moved:
#           {from, to, at, restart, restartFailed?} | null}; null before its first run).
#   lanes   records: for each record of the host file, its repo, fast (branch, commits ahead of main, landing: the
#           card of that record that lands them) and research (branch, run); a lane the record does not name is null.
#   cost    todayUsd, weekUsd, perLandedUsd (the priced steps' dollars), todayLeftOut, weekLeftOut, perLandedLeftOut (the
#           steps each leaves out for having no price), todayEstimate, weekEstimate, perLandedEstimate (the priced steps of
#           each priced as an estimate), unpriced (those of the 7 days, each with why), landedAfter,
#           unpricedSteps, cards (today's, each with its usd, todayEstimate and weekEstimate; a restarted card's row with runs, its dollars every run's),
#           picks (the rule Pick settings' cards by group and builder choice, each row with its repo), trials
#           ({dropped, flagged}: the rule's dropped challengers and flagged trial cards, each with its repo), replays (each
#           record's last judge replay study and its judge settings, of an engine that runs the study), sessions
#           (every session on this machine: todayUsd, weekUsd, at list prices).
#   board   the Board, of the record on host.json's main (repo null when none is), with repos (every record's repo, in
#           host.json's order) and others ({repo: the same part, of that record} for every other record): state (running, paused,
#           stopped, paused by guard, control record unreadable), reason (why it picks nothing; null when
#           health gives none), loop, commit (the Conveyor commit the running loop started on, else null), control (the control record), cap (in force), guard ({at, reading, readAt,
#           missing}), modelSettings (the build and review models: the snapshot's, null from one without them), areaPrefix, limit
#           ({pct, from: loop (the guard's reading) or dashboard (this machine's reading)} | null), and the columns:
#           held, queue (pick order), skipped and waits (the issues that wait on an open issue they depend on,
#           with waitsFor; each null, with issuesError, when GitHub did not list the issues), building and review (each
#           card with stays: Stop now leaves it running, so it is not counted as requeued, and beyond: why it took a
#           slot beyond the cap, else null; a building card also files and tests, a running test run's progress as its
#           track has it), waiting
#           and blocked (Needs you; a blocked card with its track and reviews), landed (today: the newest the snapshot
#           keeps; today is {landed, usd}, every card of the day counted and its usd added up, null when one has none), each card with doneWhen (its last Done-when check, {items, met,
#           failed}, or null), split (what the rule Split large issues made of its issue, {result, slices, filed}, or
#           null), seats (the seats the rule Pick settings gave it, the pick's asked with its mode and run, the seats the card runs on that the rule set, or null) and stalls (how many times a step of it made no progress and was ended; 0 for none), and open (every open issue, as the snapshot's open: count,
#           split {queued, you, labelOrRule, belt}, held, each with its reasons, and issues, every open issue with its
#           labels and dependsOn, the numbers its Depends on: lines name; null when GitHub did not list them, and
#           umbrellas, each open parent with its parts, done of all, those in flight and the closed ones),
#           unpushed (the landed cards whose commits origin lacks, oldest first, each with since; null from a snapshot
#           without them), fullTest (the snapshot's: command, why, running, last; null from a snapshot without it) and
#           landingPr (health's: the open pull request of Land as pr, {number, url, cards, merge}, for Merge; null with none),
#           pushing and pushLast (health's: the push in progress and the last push that ended; null with none),
#           for Push landed and Run full test suite.
#           checkRuns: each record's check run (its snapshot's checkRun, conveyor.sh checkrun(), with its repo), of
#           every record, steered or not, whose pack names checks.progress and has one to show (repo null too: no
#           record steered); no field when none
#           names it.
#   rules   the Rules tab, of the same record (repo null when none is; repos and others as the Board's): repoUrl (its
#           GitHub address, null when it is none), state, control, cap, guard,
#           modelSettings and limit (as the Board's), areaPrefix (the pack's; null from a snapshot without
#           one), packPrMerge (the pack's push.prMerge, Merge PR while the record's prMerge is null; null from a snapshot
#           without it), packLandAs (the pack's push.landAs, Land as while the record's landAs is null; null from a snapshot
#           without it), packPick (the models Pick settings may give each seat, each with its effort range, and the
#           efforts each program takes; null from a snapshot without it), held, queue (each with its areas), skipped and waits (the snapshot's queue.waiting and, after it,
#           the held, skipped or yes-gated issues that wait too (keptWaits), each with waitsFor; each null,
#           with issuesError, when GitHub did not list the issues), building (how many cards are on the belt), onBelt
#           (their issues), beltSteps (every card on the belt, landed ones too: issue, step, landed; the waiting list
#           says where each issue a card waits on is), blocked (the blocked cards), forecast
#           (the snapshot's: cards, usd, perCard {usd, pct}, guard, reading, pausesAt; null from a snapshot without one;
#           no time), prices (the snapshot's: the built-in model prices, the pack's prices, added models and aliases,
#           each model's display name and the model IDs seen in 30 days, for Model prices and the Board's model names,
#           with missing: the models Needs you counts as having no price, needsYou.prices; null
#           from a snapshot without them), standing (the snapshot's: the pack's auto.standing, the standing kinds
#           of routine yes that are on; null from a snapshot without it), pushCheck (the snapshot's: the pack's
#           push.check, true or false; null from a snapshot without it), lintCommands (the snapshot's: the pack's
#           lint commands, each {run, files}; null from a snapshot without them), open (as the Board's: every held issue
#           with its labels and reasons, and every open issue) and readAt (when the build of the record's snapshot
#           began: by this machine's clock from the live feed, else the host's snapshotAt; older than updatedAt when
#           the snapshot is; null from a snapshot that does not say).
#   tests   the Tests page, of the same record (repo null when none is; repos and others as the Board's): tests (the
#           snapshot's: each test file's figures, each of its runs with its card's issue and url, each issue the Board
#           filed for it ($TAFILED) with its url, state (closed for an open one the snapshot's open issues lack), landed commit, fix and the proof's before and after CPU s, the pack's test
#           settings and the test steps' totals; null from a snapshot without it), and, for the page's actions, testActions (the snapshot's limit,
#           actions, each with its text, and allowed, the pack's models by CLI), control (the snapshot's control record: its tests is the Tests model), clis
#           (the CLIs installed on the host, as the judge's role offers them), flaky (the snapshot's flaky cases) and
#           testMap (the snapshot's: the Test map part, conveyor/lib/testmap.sh mapboard()); each null from a snapshot
#           without it.
#   bench   the Benchmarks tab: each record's (repo null when none is steered; repos and others as the Tests part's)
#           bench (the snapshot's: the run in progress, the SWE-bench runs' board.json, conveyor/bench/swe.sh
#           swe_board(), and the versions now, swe_versionsnow()), drift (the snapshot's: the latest drift watch, conveyor/bench/drift.sh)
#           and guard (its control record's weekly-limit guard: a change reads the runs again);
#           each null from a snapshot without it. The runs and their results are read when shown (--bench).
#   metrics records (each record's measured totals, today and week) and cards (each card of the 7 days with
#           its metrics: step timeline, seconds, tokens, dollars, findings; null from a snapshot without them), steps
#           (each card's steps of the last 25 h, uncut: the snapshot's metrics.steps, with its repo and url), and
#           compare (the 7 days side by side, {projects: a row a project, naming its repo; machine: the machine's}:
#           landed, leadSec (the median seconds from an issue's opening to its landing) and usd; a figure not measured
#           is null).
#   machine the machine's one Conveyor, over every project: host, state (paused: the host file's mode; running: a
#           project's loop runs; stopped: none does; not read: the host's host file does not read), cap (the slots
#           in force: every project's own cap together, no more than the machine cap), used (the cards holding a slot now, every project's together),
#           todayUsd and todayLeftOut (as cost's), repos, projects (each project on its own: repo, state, reason, loop,
#           mode (its control record's), cap (its own, in force), guard (its control record's weekly-limit guard) and used (its cards counted against its own cap, as belt's: loop.json's count while it is behind), needs (its cards
#           blocked or waiting for the owner's yes, its issues waiting for that yes before their build, and its open
#           decisions, each {repo, decision: its id, title: the question}), belt,
#           queue (pick order), held, waiting (its issues waiting on an open dependency, the snapshot's queue.waiting;
#           null when the snapshot does not list them), order (the issues its record pins), rules, models ({builder, reviewer}: model and
#           effort in force; judge: {on: false}, or {on: true, model, effort} in force, null when its record does not
#           read), landedToday, todayUsd, todayLeftOut) and foremen (as foremen() gives them, with foremenError).
#   A card's usd in belt, belt3d and board has estimate beside it (true when one of its steps is priced as an
#   estimate), as does board's today; machine's todayUsd has todayEstimate and metrics' compare usd has usdEstimate
#   (how many of the priced steps are estimates). The page marks such a figure as an estimate.
#   belt, belt3d, queue and cost's cards also carry byRepo ({repo: the fields that are one project's}: belt's cap and building, queue's held,
#   belt3d's queue while the queue of all is unknown,
#   cost's figures), which the
#   page shows in their place when it is filtered to one project.
# The Foreman's watchers read panels.health.data.limit from the same file (each Foreman reads its own projects'
# decisions from their ledgers, not panels.needs).

# The page's parts from the five reads. One jq program, so every panel's part is cut from the same answers.
PANELS_JQ='
  def total: if length == 0 then 0 elif any(. == null) then null else add * 10000 | round / 10000 end;
  def link($r): if $r.repoUrl != null and (.issue | type) == "number" and .issue > 0 then "\($r.repoUrl)/issues/\(.issue)" else null end;
  # repoUrl too: a card with no GitHub issue (a main-red fix, a Tests page card) has no url to take the repository
  # from, and its review'"'"'s file paths link to their lines in it (the page'"'"'s repoOf).
  def tag($r): . + {repo: $r.repo, repoUrl: ($r.repoUrl // null), url: link($r)};
  def few($r): map(tag($r) | {repo, card, issue, title, url} + .);
  # The state of the machine of the records (the record list): not read (its host file does not read), paused (the
  # host file says so), running (a loop of one of them runs), else stopped.
  def mstate: ([.[].snap.health.machine | objects][0] // null) as $m
    | if $m.unread == true then "not read" elif $m.paused == true then "paused" elif any(.[]; .snap.health.loop == true) then "running" else "stopped" end;
  # The slots in force of the records (the record list), the cap of the machine bar and of Belt 3D'"'"'s deck (issue 413:
  # each part gave its own; the Belt part counts against cardcap): every project'"'"'s own cap together, and no more than the machine cap
  # where the host file sets one; null when neither is known.
  # cardcap is the sum of the own caps of the projects alone: the card cap, which the Belt part counts against.
  def cardcap: [.[].snap.health.builderCap | numbers] | if length == 0 then null else add end;
  def slots: cardcap as $sum
    | ([.[].snap.health.machine | objects][0].cap | numbers) // null
    | if . == null then $sum elif $sum == null then . else [., $sum] | min end;
  # A card of a belt that counts against the card cap: every card but one that lands (offCap, from the loop'"'"'s own
  # mark) or has landed (landed), in any step, waiting or not.
  def counted: .landed != true and .offCap != true;
  # The cards of the records (the record list) that hold no machine slot as they only wait: the count each running loop
  # leaves out of the machine'"'"'s own (health.waitingCount), together; 0 when none says. The card cap leaves none out.
  def idle: [.[].snap.health.waitingCount | numbers] | add // 0;
  # The issues of a snapshot that wait on an open issue but that something else keeps from the pick as well (held,
  # skipped by a rule, waiting for the owner'"'"'s yes), so its queue.waiting leaves them out: each open.held entry with a
  # waits reason that queue.waiting does not list, as {issue, title, waitsFor}.
  def keptWaits($s): [$s.queue.waiting | arrays | .[].issue] as $w
    | [$s.open | objects | .held | arrays | .[] | select(.issue | IN($w[]) | not)
       | (first(.reasons[]? | select(.kind == "waits")) // null) as $x | select($x != null) | {issue, title, waitsFor: ($x.waitsFor // [])}];
  # Every Claude account the Board read (limit()'"'"'s accounts), this machine'"'"'s and then the host'"'"'s, each with its own
  # figures and what it is used for: on the host, the cards of each record whose control record names it (a record
  # naming none uses the default login), and its reviews when the reviewer is Claude and the record'"'"'s reviewAccount, else
  # its account, names it, and the cards in flight that started on it before the record named another (the
  # snapshot'"'"'s inFlight; a review account one names was a Claude reviewer'"'"'s as its card started, whatever the reviewer is
  # now), so an account a running card still uses is never shown as unused; here, the folder holding the marked Foreman session'"'"'s transcript (foreman; never the
  # metadata written last) is this machine'"'"'s Foreman, and on one machine a host account too. usedFor is null when the records were not read.
  def accountsOf($R): ($lim.accounts // null) as $a | if $a == null then null else
    def row($m): {machine: $m, name, email, usedPct, fiveHourPct, resetsAt, readAt, error};
    def or_none: if length == 0 then ["not used by the Conveyor"] else . end;
    # The host file'"'"'s account names, as the Rules tab offers them (each record'"'"'s snapshot accounts).
    ([($R // [])[] | (.snap.accounts // [])[]? | strings] | unique) as $names |
    {error: $a.host.error, list: ([($a.here // [])[] | row(null) + {usedFor: (if .foreman == true then ["this machine'"'"'s Foreman"] else [] end | or_none), cards: false, others: false}]
      + [($a.host.accounts // [])[] | . as $x | row($a.host.name) + ((if $R == null then null else
          [$R[] | (.snap.control // {}) as $c | .repo as $p | (.snap.inFlight // []) as $f
            | (.snap.modelSettings.reviewer.agent == "claude") as $cl
            # A role on an API route uses no account (billed per token): only the roles on the subscription login now
            # (the record'"'"'s routes, routesnow() in conveyor/lib/control.sh) use one.
            | (.snap.health.routes.subscription.roles // ["builder", "reviewer"]) as $on
            | ($on | index("builder") != null) as $bs | ($on | index("reviewer") != null) as $rs
            # A name is a host file account (the listedAs of a row), never a display name: an unlisted folder, the
            # default login too, may be shown under the name of a listed account, and no record naming that runs on it.
            | def mine($n): if $n == null then $x.default == true else any($x.listedAs[]?; . == $n) end;
              ($bs and mine($c.account)) as $b | ($rs and $cl and mine($c.reviewAccount // $c.account)) as $r
            | (if $b then "cards of \($p): build and fix" else empty end),
              (if $r then "cards of \($p): reviews" else empty end),
              (if $bs and ($b | not) and any($f[]; mine(.account)) then "cards in flight of \($p): build and fix" else empty end),
              (if $rs and ($r | not) and any($f[]; if .reviewAccount != null then mine(.reviewAccount) else $cl and mine(.account) end) then "cards in flight of \($p): reviews" else empty end)] end) as $u
        # cards: a card of a record runs on it (null: the records were not read); others: the Rules tab can move its
        # work to another account (the default login, for one that is not it, or a host file name it is not listed as).
        # On one machine (the host named by no name: accounts()) this machine'"'"'s accounts are the host'"'"'s, and its Foreman too.
        | (if $a.host.name == null and $x.foreman == true then ["this machine'"'"'s Foreman"] else [] end) as $fm
        | {usedFor: (if $u == null then null else $fm + $u | or_none end), cards: (if $u == null then null else $u != [] end),
           others: ($x.default != true or any($names[]; . as $n | any($x.listedAs[]?; . == $n) | not))})])} end;
  # The weekly limit of each account the cards of each record run on, as the record'"'"'s guard reads it on the build
  # machine (its snapshot'"'"'s limits, with the email of that machine'"'"'s login): {repo, account (null: the default
  # login), uses, pct, readAt, email}. Never this machine'"'"'s own login, which can be another account. null when
  # the records were not read.
  def limitsOf($R): if $R == null then null else [$R[] | .repo as $p | (.snap.limits // [])[] | objects | {repo: $p, account, uses, pct, readAt, email}] end;
  # A record'"'"'s reading for its Board and Rules: the guard'"'"'s, else the highest of its accounts'"'"' (a record with no
  # guard set), never this machine'"'"'s own login.
  def limitOf($s): ([($s.limits // [])[] | objects | .pct | numbers] | max) as $m
    | if $s.health.guard.reading != null then {pct: $s.health.guard.reading, from: "loop"} elif $m != null then {pct: $m, from: "loop"} else null end;
  # Every open issue of a record (open.issues, null from a snapshot without it) beside its held ones, each linked.
  def openOf($r): $r.snap.open | if type == "object" then {count, split, held: (.held | few($r)), issues: (.issues | if . == null then null else few($r) end),
    umbrellas: (.umbrellas | if type == "array" then few($r) else null end)} else null end;
  # The Board of one record: the loop as its control record steers it, in six columns.
  # stays: Stop now leaves the card running (halt() in conveyor/lib/run.sh): it has landed, is filing its follow-ups
  # or landing, or has filed them, or has filed the slices of a split (split.filed, or track.grown).
  def stays: .landed == true or (.done.step | IN("file", "land"))
    or any(.track.detail[]?; .name == "follow-ups filed" and .state == "done")
    or (.split.filed | type == "array" and length > 0) or .track.grown != null;
  def boardOf($r): $r.snap as $s | ([$s.landed[].card]) as $today
    | {repo: $r.repo, state: $s.health.state, reason: ($s.health.reason // null), loop: $s.health.loop, commit: ($s.health.commit // null), control: $s.control, cap: $s.health.builderCap,
       guard: $s.health.guard, modelSettings: ($s.modelSettings // null), areaPrefix: ($s.areaPrefix // null), limit: limitOf($s),
       held: ($s.queue.holding | if . == null then null else few($r) end),
       queue: ($s.queue.order | if . == null then null else few($r) end),
       skipped: ($s.queue.skipped | if . == null then null else few($r) end),
       waits: ($s.queue.order | if . == null then null else $s.queue.waiting // [] | few($r) end),
       issuesError: (if $s.queue.order == null then "GitHub did not list the open issues on \($conv.host)." else null end),
       # A card that landed on an earlier day and is still on the belt (its push or the close of its issue has not
       # gone through) is in Building with its Push step: Landed today holds only the cards of this day.
       building: [$s.belt[] | select((.landed != true and .step != "review") or (.landed == true and (.card as $c | $today | index($c) | not)))
         | {card, issue, name: (.name // null), title, step, waitsOn: (.waitsOn // null), gaveWay: (.gaveWay // null), gaveWayFixing: (.gaveWayFixing == true), stepAt, pickedAt: (.pickedAt // null), files: (.track.files // null), tests: (.track.tests // null), usd, estimate: (.estimate == true), reading, atEnd: (.atEnd == true),reason: (.track.reason // null), stays: stays, doneWhen: (.doneWhen // null), split: (.split // null), seats: (.seats // null), stalls: (.stalls // 0), beyond: (.beyond // null)}] | few($r),
       review: [$s.belt[] | select(.landed != true and .step == "review") | {card, issue, name: (.name // null), title, review, of, gaveWay: (.gaveWay // null), gaveWayFixing: (.gaveWayFixing == true), stepAt, usd, estimate: (.estimate == true), reading, atEnd: (.atEnd == true),stays: stays, doneWhen: (.doneWhen // null), split: (.split // null), seats: (.seats // null), stalls: (.stalls // 0), beyond: (.beyond // null)}] | few($r),
       waiting: [$s.needsYou.waiting[] | {card, issue, name: (.name // null), title, sentence, since, doneWhen: (.doneWhen // null), split: (.split // null), seats: (.seats // null), stalls: (.stalls // 0)}] | few($r),
       # Its track and reviews too: the card leads with why it failed (the tests that failed, the NO-GO reviews), as in Needs you.
       blocked: [$s.needsYou.blocked[] | {card, issue, name: (.name // null), title, reason, tail, since, track: (.track // null), reviews: (.reviews // null), doneWhen: (.doneWhen // null), split: (.split // null), seats: (.seats // null), stalls: (.stalls // 0)}] | few($r),
       landed: [$s.landed[] | {card, issue, name: (.name // null), title, step, time, usd, estimate: (.estimate == true), reviews, batch: (.batch // null), doneWhen: (.doneWhen // null), split: (.split // null), seats: (.seats // null), stalls: (.stalls // 0)}] | few($r),
       today: {landed: $s.landedCount, usd: $s.landedUsd, estimate: (($s.landedEstimate // 0) > 0)},
       unpushed: ($s.health.unpushed // null | if . == null then null else map({card, issue, name: (.name // null), since}) | few($r) end), fullTest: ($s.fullTest // null),
       landingPr: ($s.health.landingPr // null), pushing: ($s.health.pushing // null), pushLast: ($s.health.pushLast // null),
       open: openOf($r)};
  # The Rules of one record: its rules and what they produce: the queue, the held and the skipped, the cards on the
  # belt (building, how many; onBelt, their issues) and the cards blocked, and the snapshot'"'"'s forecast. The page
  # computes no queue of its own.
  def rulesOf($r): $r.snap as $s
    | {repo: $r.repo, repoUrl: ($r.repoUrl // null), state: $s.health.state, control: $s.control, cap: $s.health.builderCap, guard: $s.health.guard,
       modelSettings: ($s.modelSettings // null), accounts: ($s.accounts // null), areaPrefix: ($s.areaPrefix // null), packLandAs: ($s.packLandAs // null), packPrMerge: ($s.packPrMerge // null), packPick: ($s.packPick // null), limit: limitOf($s),
       held: ($s.queue.holding | if . == null then null else few($r) end),
       queue: ($s.queue.order | if . == null then null else few($r) end),
       skipped: ($s.queue.skipped | if . == null then null else few($r) end),
       waits: ($s.queue.order | if . == null then null else ($s.queue.waiting // []) + keptWaits($s) | few($r) end),
       issuesError: (if $s.queue.order == null then "GitHub did not list the open issues on \($conv.host)." else null end),
       building: [$s.belt[] | select(.landed != true)] | length, onBelt: [$s.belt[] | select(.landed != true) | .issue],
       beltSteps: [$s.belt[] | {issue, step, landed: (.landed == true)}],
       blocked: [$s.needsYou.blocked[] | {card, issue, name: (.name // null), title, since}] | few($r), forecast: ($s.forecast // null),
       prices: ($s.prices | if type == "object" then . + {missing: [$s.needsYou.prices.models | arrays | .[] | strings]} else null end), standing: ($s.standing // null), pushCheck: ($s.pushCheck | if type == "boolean" then . else null end), lintCommands: ($s.lintCommands | if type == "array" then . else null end), open: openOf($r), readAt: ($r.readAt // null)};
  # From the first pick-up of the work of the card to its landing: totalSec of the snapshot, else the time in its card id.
  def took: (.totalSec | numbers) // (try ((.card | capture("^c(?<d>[0-9]{8}T[0-9]{6})-").d | strptime("%Y%m%dT%H%M%S") | mktime) as $s
    | ((.time | fromdate) - $s) | select(. >= 0)) catch null) // null;
  $conv.records as $R | $conv.error as $cerr
  | ($R // [] | map(. as $r | .snap.belt[] | tag($r))) as $belt
  | ($R // [] | map(. as $r | .snap.landed[] | tag($r) | . + {tookSec: took}) | sort_by(.time) | reverse) as $landed
  # A record whose snapshot is behind its card records (recordsNewer, with recordsNow: conveyor.sh snapshot) has its
  # cards stopped for the owner from the records now, which stay current while a new snapshot takes minutes (#1101): its
  # waiting, the cards they hold stopped for the owner'"'"'s yes, and its blocked, those they hold blocked otherwise. A card
  # of the snapshot'"'"'s waiting or blocked that the records no longer hold so is left out (a failing push, push true, is no
  # card'"'"'s block and stays), and a card stopped since is added, its title the one the records give it (recordsNow), else the snapshot'"'"'s belt, and
  # fromRecords true: it has no track, reviews or changed files, so the page draws it anew once a snapshot gives them.
  # $behind: each such record, {repo, at (its snapshotAt), building (loop.json'"'"'s count now; 0 once no process of the
  # loop lives, as then none builds)}.
  | def nowOf($r): [$r.snap | select(.recordsNewer == true) | .recordsNow | objects | select([.blocked, .waiting] | all(type == "array"))
      | def cards: map(objects | select(.card | type == "string")); {blocked: (.blocked | cards), waiting: (.waiting | cards)}][0];
    def stopped($r): {card, issue, name, title: ((.title | strings) // (.card as $k | first($r.snap.belt[] | select(.card == $k) | .title)) // null), since, fromRecords: true} | tag($r);
    ($R // [] | map(. as $r | nowOf($r) as $now
      | (.snap.needsYou.waiting[] | select($now == null or (.card | IN($now.waiting[].card))) | tag($r)),
        ($now.waiting // [] | .[] | select(.card | IN($r.snap.needsYou.waiting[].card) | not) | stopped($r) + {sentence}))) as $waiting
  | ($R // [] | map(. as $r | nowOf($r) as $now
      | (.snap.needsYou.blocked[] | select($now == null or .push == true or (.card | IN($now.blocked[].card))) | tag($r)),
        ($now.blocked // [] | .[] | select(.card | IN($r.snap.needsYou.blocked[].card) | not) | stopped($r) + {reason, tail: null}))) as $blocked
  | [$R // [] | .[] | select(nowOf(.) != null) | {repo, at: (.snap.snapshotAt // null), building: ((.snap.recordsNow.building | numbers) // 0)}] as $behind
  # The issues waiting for the yes of the owner before their build; null when a record could not say (GitHub did not
  # list its open issues, or its snapshot is from before it said).
  | (if $R == null or any($R[]; .snap.needsYou.before | type != "array") then null
     else $R | map(. as $r | .snap.needsYou.before[] | tag($r)) end) as $before
  # The follow-ups filed held because their finding names a pipeline file, until the owner releases them.
  | ($R // [] | map(. as $r | .snap.needsYou.pipeline | arrays | .[] | tag($r))) as $pipeline
  # The dependencies in another repository that could not be read: the issue that names one waits until it reads.
  | ($R // [] | map(. as $r | .snap.needsYou.farDeps | arrays | .[] | tag($r))) as $farDeps
  # The whole test on main of each record, while its last run fails (the mainTest of the snapshot): the issue it filed.
  | ($R // [] | map(. as $r | .snap.mainTest | objects | tag($r) | {repo, issue, url, cases, from, to, since})) as $tests
  # The commit of the plugin main a record that follows it did not take (needsYou.engine): the commit and why.
  | ($R // [] | map(. as $r | .snap.needsYou.engine | objects | tag($r) | {repo, commit, reason, since})) as $engines
  # The last run of the test rules of a record, when it matched more files than the cap of one day and so filed none (needsYou.testRules).
  | ($R // [] | map(. as $r | .snap.needsYou.testRules | objects | tag($r) | {repo, time, matched, cap})) as $testRules
  # The models the loop of a record runs or offers with no price (needsYou.prices), which Model prices lists.
  | ($R // [] | map(. as $r | .snap.needsYou.prices | objects | select(.models | arrays | length > 0) | tag($r) | {repo, models})) as $prices
  # The card that lands the Fast lane of a record (conveyor.sh land-branch), one of the cards of that record: a branch named as a card id of the record
  # (c<time>-<project>-<issue>) is a card of that issue, and any other branch, a number in its name or not, is a card of issue 0 titled with the first commit of the branch. The landed list
  # holds only the cards of today, so a card that landed on an earlier day is found in the branches of the snapshot (the
  # newest land-branch cards that landed, on any day, and the newest that landed the change of each lane): the lane says it landed, with no time of day, for as long as it is
  # left as it was. A snapshot from before it carried branches has the cost rows, which end after 7 days.
  | def landing($l; $repo): if $R == null then null elif ($l.present | not) or ($l.ahead // 0) == 0 then {state: "none"} else
        (($l.branch // "") | (capture("^c[0-9]{8}T[0-9]{6}-\($repo | gsub("[^A-Za-z0-9]"; "-"))-(?<n>[1-9][0-9]{0,8})$").n | tonumber) // 0) as $n
        | def mine: select(.issue == $n and ($n != 0 or .title == $l.first));
          def own: select(.repo == $repo);
          ([$belt[] | own | mine | select(.landed != true) | {state: "belt", card, step, review, of, since: .stepAt}]
           + [$waiting[] | own | mine | {state: "waiting", card, reason: .sentence, since}]
           + [$blocked[] | own | mine | {state: "blocked", card, reason, tail, since, repoUrl}]
           + [$landed[] | own | mine | {state: "landed", card, since: .time, reviews}]
           + [$R[] | own | .snap.branches | arrays | .[] | mine | {state: "landed", card, since: null, reviews: null}]
           + [$R[] | own | .snap.cost.cards | arrays | .[] | mine | select(.state | IN("landed", "closed")) | {state: "landed", card, since: null, reviews: null}])[0]
          // {state: "none"} end;
  # A landed card whose push failed and that the loop tries again (its Push step failed): Needs you says so under its
  # tick, with the fix card building for it (a card on the belt whose parent it is), and the belt leaves out one that
  # landed today, which Landed today shows: the card is in one panel, not two. A Push step failed because GitHub kept
  # the issue open after main was pushed (the track reason "GitHub did not close the issue") is no failing push: it is not
  # in retrying and stays on the belt.
  def pushFailed: .landed == true and ((.track.steps // [])[5].state? == "failed")
    and ((.track.reason // "") | startswith("GitHub did not close the issue") | not);
  [$belt[] | select(pushFailed) | . as $c | {repo, card, issue, name: (.name // null), title, url,
       fix: ([$belt[] | select(.repo == $c.repo and .landed != true and .parent == $c.issue and $c.issue > 0) | .issue][0] // null)}] as $retrying
  | {needs: (if $R == null and $dec.decisions == null then {error: "Nothing could be read. Cards: \($cerr). Decisions: \($dec.error).", data: null}
      else {error: null, data: {cards: (if $R == null then null else {waiting: $waiting, blocked: $blocked, before: $before, pipeline: $pipeline, farDeps: $farDeps} end), cardsError: $cerr, behind: [$behind[] | {repo, at}], tests: $tests, engines: $engines, testRules: $testRules, prices: $prices,
        # The kinds of Needs you, in their order (dashboard_needs.json, which the Foreman watcher reads too), and
        # the entries of each, read from the snapshot field the list names: a kind the page has no row of its own for
        # shows these.
        kinds: $kinds, entries: ($kinds | map(.from as $f | {key: .kind, value: ($R // [] | map(. as $r | .snap | (try getpath($f) catch null)
          | (if type == "array" then .[] else . end) | objects | tag($r) | {repo, url, card, issue, name: (.name // null), title, reason, since}))}) | from_entries),
        decisions: $dec.decisions, decisionsError: $dec.error, retrying: $retrying,
        # The cards the host of each record gave back (the retried line of its stream): a blocked card among them waits for its turn.
        retried: ($R // [] | map(. as $r | .retried | arrays | .[] | objects | select(.card | type == "string") | {repo: $r.repo, card, issue}))}} end),
   belt: (if $R == null then {error: $cerr, data: null} else {error: null, data: {cards: [$belt[] | select((pushFailed and (. as $c | any($landed[]; .repo == $c.repo and .card == $c.card))) | not)],
        cap: ($R | cardcap),
        # building: while a record is behind its card records, the cards building now: loop.json'"'"'s count for each
        # such record (0 once its loop has exited: never the old belt'"'"'s), and for any other its cards on the belt not
        # landed or landing (counted), as the page counts them; null when none is behind, and in byRepo for
        # a record that is not. behind: those records.
        building: (if $behind != [] then [$R[] | . as $r | first($behind[] | select(.repo == $r.repo) | .building | numbers)
            // ([$belt[] | select(.repo == $r.repo and counted)] | length)] | add else null end),
        behind: [$behind[] | {repo, at}],
        byRepo: ($R | map(.repo as $p | {key: .repo, value: {cap: (.snap.health.builderCap | if type == "number" then . else null end),
          building: (first($behind[] | select(.repo == $p) | .building | numbers) // null)}}) | from_entries)}} end),
   queue: (if $R == null then {error: $cerr, data: null} else {error: null, data: (
        # held: how many open issues the Board holds (the snapshot open.held: by you, a label, a rule or a wait), the
        # count of its Held column but for the landed, not pushed ones (a card reason notPushed: done, waiting for the
        # push, not held back); null when a record does not list them.
        def heldN: .open.held | if type == "array" then map(select(any(.reasons[]?; .kind == "card" and .notPushed == true) | not)) | length else null end;
        # A record whose issues GitHub did not list leaves the queue of every project unknown; byRepo then holds the
        # whole queue of each record apart, so the page filtered to a project that was read shows its own.
        if any($R[]; .snap.queue.next == null) then {next: null, held: null, awaitingDeploy: null, waiting: null, issuesError: "GitHub did not list the open issues on \($conv.host).",
              byRepo: ($R | map(. as $r | {key: .repo, value: (if .snap.queue.next == null then {next: null, held: null, awaitingDeploy: null, waiting: null, issuesError: "GitHub did not list the open issues of \(.repo) on \($conv.host)."}
                else {next: [.snap.queue.next[] | tag($r)], held: (.snap | heldN), awaitingDeploy: [.snap.awaitingDeploy | arrays | .[] | tag($r)],
                      waiting: [.snap.queue.waiting | arrays | .[] | tag($r)], issuesError: null} end)}) | from_entries)}
        else {next: ($R | map(. as $r | .snap.queue.next[] | tag($r))),
              held: (if any($R[]; .snap | heldN == null) then null else $R | map(.snap | heldN) | add end),
              awaitingDeploy: ($R | map(. as $r | .snap.awaitingDeploy | arrays | .[] | tag($r))),
              waiting: ($R | map(. as $r | .snap.queue.waiting | arrays | .[] | tag($r))), issuesError: null,
              byRepo: ($R | map({key: .repo, value: {held: (.snap | heldN)}}) | from_entries)} end)} end),
   landed: (if $R == null then {error: $cerr, data: null} else {error: null, data: {day: $R[0].snap.day, cards: $landed}} end),
   # Release: the main of each record as its Release panel shows it, and its whole-suite runs (release and suites of
   # the snapshot; null from a snapshot from before them), with the address of its repository for the issue links.
   release: (if $R == null then {error: $cerr, data: null} else {error: null, data: {records: ($R | map({repo, url: .repoUrl, release: (.snap.release // null), suites: (.snap.suites // null), suiteMachine: (.snap.control.suiteMachine // null), suiteMode: (.snap.control.suiteMode // null)}))}} end),
   # Declined: the declined list of every record (lines: the declined of its snapshot; rest: its declinedRest; none from
   # a snapshot from before it carried them), newest first.
   declined: (if $R == null then {error: $cerr, data: null} else {error: null, data: ({lines: "declined", rest: "declinedRest"} | map_values(. as $k
        | $R | map(. as $r | .snap[$k] | arrays | .[] | objects | tag($r)
        | {repo, repoUrl: ($r.repoUrl // null), id, time, card, issue, name: (.name // null), url, finding, by, why, built: (.built // null), dismissed: (.dismissed // null), round: (.round // null), findings: (.findings // null)}) | sort_by(.time) | reverse))
        # heals: the self-heals list of each record that has one (the snapshot'"'"'s selfheals), its entries tagged.
        + {heals: [$R[] | . as $r | .snap.selfheals | objects | {repo: $r.repo, repoUrl: ($r.repoUrl // null), sorted: (.sorted // null), areas: (.areas // []),
            entries: [.entries[]? | objects | tag($r) | {repo, repoUrl, id, time, card, issue, url, area: (.area // null), finding, why, effect: (.effect // null)}],
            docs: (.docs | objects | {areas: (.areas // []), entries: [.entries[]? | objects | tag($r) | {repo, repoUrl, id, time, card, issue, url, area: (.area // null), finding, why, effect: (.effect // null)}]}) // {areas: [], entries: []},
            dropped: [.dropped[]? | objects | tag($r) | {repo, repoUrl, id, time, card, issue, url, area: (.area // null), finding, why, effect: (.effect // null), dropped: (.dropped // null), seen: (.seen // null)}]}]}} end),
   # Belt 3D: the belt, Needs you, the queue (next, held, waiting) and Landed today as above, each card with what its
   # lane, bay and details show.
   belt3d: (if $R == null then {error: $cerr, data: null} else
        def rounds: [arrays | .[] | objects | {round, verdict, counts: (.counts // null)}];
        def track3: if type == "object" then {steps, at, since, tests: (.tests // null), files: (.files // null)} else null end;
        def item($r): tag($r) | {repo, issue, title, url};
        # The queue of a snapshot: an issue held (holding) is in held with what it waits on, and so is a waiting one a
        # rule or the owner'"'"'s yes keeps from the pick (keptWaits); the snapshot'"'"'s queue.waiting lists neither.
        def queue3($r): . as $s | ([.queue.holding | arrays | .[].issue]) as $h | .queue | {next: [.next[] | item($r)],
          held: ([.holding | arrays | .[]] + [keptWaits($s)[] | select(.issue | IN($h[]) | not)] | map(item($r) + {waitsFor: (.waitsFor // [])})),
          waiting: [.waiting | arrays | .[] | item($r) + {waitsFor: (.waitsFor // [])}]};
        {error: null, data: {repos: [$R[].repo],
        # The queue of each record apart while the queue of all is unknown (a record was not listed), as the Queue part has it.
        byRepo: (if any($R[]; .snap.queue.next == null) then $R | map(. as $r | {key: .repo, value: {queue: (.snap | if .queue.next == null then null else queue3($r) end)}}) | from_entries else {} end),
        # The track of a belt card has its records too, each step it took and when (name and at alone), so its lane
        # shows when it went back a step; a fix the Done-when check on a reply started is marked (replyCheck), as it is
        # part of the step of the session it checks, not a step back from Fix (track.jq).
        belt: [$belt[] | {repo, card, issue, name: (.name // null), title, url, step, stepAt, landed: (.landed == true), waitsOn: (.waitsOn // null), usd, estimate: (.estimate == true),
          turns: (.live.turns? // null), reviews: (.reviews | rounds),
          track: (.track | if type == "object" then track3 + {records: [.records | arrays | .[] | objects | {name, at: (.at // null)}
            + (if (.reason | type) == "string" and (.reason | startswith("the Done-when check failed")) then {replyCheck: true} else {} end)]} else null end)}],
        queue: (if any($R[]; .snap.queue.next == null) then null
          else $R | map(. as $r | .snap | queue3($r)) | {next: map(.next[]), held: map(.held[]), waiting: map(.waiting[])} end),
        needs: ([$waiting[] | . + {kind: "waiting", reason: "Visible change: \(.sentence // "no sentence")"}] + [$blocked[] | . + {kind: "blocked"}]
          | map({repo, card, issue, name: (.name // null), title, url, kind, reason, since, reviews: (.reviews | rounds), usd: (.metrics.usd // null), estimate: (.metrics.estimate == true), track: (.track | track3)})),
        landed: [$landed[] | {repo, card, issue, name: (.name // null), title, url, time, usd, estimate: (.estimate == true), reviews: (.rounds | rounds), track: (.track | track3)}],
        # What the deck behind the floor reads out: the host, its machine state (as the machine part has it) and the
        # slots as the machine bar has them: the cards holding one of the machine'"'"'s (a landing card does; a card landed and
        # waiting for its push holds none, nor does a card that only waits: idle) and the slots in force.
        deck: {host: $conv.host, state: ($R | mstate), used: ([([$belt[] | select(.landed != true)] | length) - ($R | idle), 0] | max),
          cap: ($R | slots)}}} end),
   health: {error: null, data: {
        host: {name: $conv.host, local: ($conv.local == true), reachable: $conv.reachable, error: $cerr}, stream: ($conv.stream // null),
        records:(if $R == null then null else $R | map({repo, repoUrl: (.repoUrl // null), lastPushAt, steered, snapshotAt: (.snap.snapshotAt // null)} + (.snap.health | {loop, state: (.state // null), newest, stuck, unpushed, pushError, pushFailingSince, gh, ghReached, diskFreeKb, builderCap, models, cycles: (.cycles // null), untimed: (.untimed // null), unchecked: (.unchecked // null), split: (.split // null), report: (.report // null), timesPlan: (.timesPlan // null), routes: (.routes // null), quarantined: (.quarantined // null), serviceOld: (.serviceOld // null), engineStopped: (.engineStopped // null)}) + {flaky: (. as $r | .snap.flaky | arrays | map(. + {url: link($r)})) // null}) end),
        limit: $lim.limit, limitError: $lim.error, limits: limitsOf($R), accounts: accountsOf($R), update: $upd,
        # The plugin problems each Foreman noted, once under each of its projects (repo, as the project filter reads
        # it), so a grouped Foreman'"'"'s show whichever of its projects is picked; the page shows each file once.
        pluginBugs: [$fm.foremen | arrays | .[] | select((.pluginBugs | numbers) > 0) | . as $f | .projects[]
          | {repo: ., projects: $f.projects, count: $f.pluginBugs, file: $f.pluginBugsFile, url: $f.pluginBugsUrl, notes: ($f.pluginNotes // [])}]}},
   lanes: (if ($lanes.error // null) != null then {error: $lanes.error, data: null} else {error: null, data: {
        records: ($lanes.records | map(.repo as $repo | .fast |= (if . != null and .present then . + {landing: landing(.; $repo)} else . end))),
        cardsError: $cerr}} end),
   cost: (if $R == null and $lim.limit == null then {error: "Nothing could be read. Cards: \($cerr). Usage: \($lim.error).", data: null}
      else {error: null, data: {
        cards: (if $R == null then null else
          {day: $R[0].snap.day, todayUsd: ([$R[].snap.cost.today] | total), weekUsd: ([$R[].snap.cost.week] | total),
           landedAfter: ([$R[].snap.cost.landedAfter | to_entries[]] | group_by(.key) | map({key: .[0].key, value: (map(.value) | add)}) | from_entries),
           perLandedUsd: ([$R[] | {n: (.snap.cost.landedAfter | add), usd: .snap.cost.perLanded} | select(.n > 0)]
             | if length == 0 or any(.usd == null) then null else (map(.usd * .n) | add) / (map(.n) | add) * 10000 | round / 10000 end),
           unpricedSteps: ([$R[].snap.cost.unpricedSteps] | add),
           # The figures above are the dollars of the priced steps: how many steps each leaves out, and which and why
           # (null from a snapshot from before it said so: there a figure with an unpriced step is null instead).
           todayLeftOut: ([$R[].snap.cost.todayLeftOut | numbers] | add // 0), weekLeftOut: ([$R[].snap.cost.weekLeftOut | numbers] | add // 0),
           perLandedLeftOut: ([$R[].snap.cost.perLandedLeftOut | numbers] | add // 0),
           # How many of the priced steps of each figure are priced as an estimate: the figure is then shown as one.
           todayEstimate: ([$R[].snap.cost.todayEstimate | numbers] | add // 0), weekEstimate: ([$R[].snap.cost.weekEstimate | numbers] | add // 0),
           perLandedEstimate: ([$R[].snap.cost.perLandedEstimate | numbers] | add // 0),
           # The figures of each project on its own, shown in place of the sums when the page is filtered to one project.
           byRepo: ($R | map({key: .repo, value: (.snap.cost | {todayUsd: .today, weekUsd: .week, perLandedUsd: .perLanded, landedAfter, unpricedSteps,
             todayLeftOut: (.todayLeftOut | numbers // 0), weekLeftOut: (.weekLeftOut | numbers // 0), perLandedLeftOut: (.perLandedLeftOut | numbers // 0),
             todayEstimate: (.todayEstimate | numbers // 0), weekEstimate: (.weekEstimate | numbers // 0), perLandedEstimate: (.perLandedEstimate | numbers // 0)})}) | from_entries),
           unpriced: (if any($R[]; .snap.cost.unpriced | type != "array") then null
             else [$R[] as $r | $r.snap.cost.unpriced[] | tag($r) | {repo, card, issue, url, step, time, why} + (if .name then {name} else {} end)] end),
           # Every card with a step in the 7 days, the rows of each record in its own order (the one worked on last
           # first); null when the snapshot of a record is from before it carried the rows.
           perCard: (if any($R[]; .snap.cost.cards | type != "array") then null
             else [$R[] as $r | $r.snap.cost.cards[] | tag($r) | {repo, card, issue, title, url, state, runs, todayUsd: .today, weekUsd: .week,
               todayEstimate: (.todayEstimate | numbers // 0), weekEstimate: (.weekEstimate | numbers // 0)} + (if .name then {name} else {} end)] end),
           # The cards of the rule Pick settings by group and builder choice, the rows of each record with its repo; null when the
           # snapshot of a record is from before it carried them.
           picks: (if any($R[]; .snap.cost.picks | type != "array") then null else [$R[] as $r | $r.snap.cost.picks[] | {repo: $r.repo} + .] end),
           # The trials of the rule: the groups whose challenger was dropped and the trial cards flagged for a pipeline
           # file, each with its repo; a snapshot from before it carried them gives none.
           trials: {dropped: [$R[] as $r | ($r.snap.cost.trials.dropped // [])[] | {repo: $r.repo} + .],
             flagged: [$R[] as $r | ($r.snap.cost.trials.flagged // [])[] | {repo: $r.repo} + .]},
           # Each record whose engine runs the judge replay study: its last replay (null when none ran) and its judge
           # settings, whose models the replay can be asked on.
           replays: [$R[] | select(.snap.cost | has("replay")) | {repo, last: .snap.cost.replay, judge: (.snap.modelSettings.judge // null)}]} end),
        cardsError: $cerr,
        sessions: (if $lim.limit == null then null else {todayUsd: $lim.limit.today.spentUsd, todayComplete: ($lim.limit.today.complete // false), weekUsd: ($lim.limit.cost.week // null)} end),
        sessionsError: $lim.error}} end),
   # The Board: the loop on the main of host.json, as the control record steers it, in six columns.
   # Its checkRuns: the check run of each record whose pack names checks.progress, as its snapshot gives it, with its
   # repo (a record that steers nothing runs checks too, so they come when no record is steered as well); no field
   # when no pack names one.
   # Each record has its Board and its Rules, so the page can steer every record on the host: the record on the main
   # of host.json is the part itself, as before (repo null when none is), every record is named in repos (host.json
   # order), and each other record is under others, by its repo, in the same shape.
   board: (if $R == null then {error: $cerr, data: null} else
      (if any($R[]; .snap | has("checkRun")) then {checkRuns: [$R[] | select(.snap.checkRun != null) | .snap.checkRun + {repo}]} else {} end) as $runs
      | {error: null, data: (([$R[] | select(.steered)][0] | if . == null then {repo: null} else boardOf(.) end) + $runs
          + {repos: [$R[].repo], others: ([$R[] | select(.steered | not) | {key: .repo, value: (boardOf(.) + $runs)}] | from_entries)})} end),
   # cores: the cores kept for the user and the test slots left, the machine'"'"'s, the same in every record'"'"'s health
   # (health'"'"'s cores, null from a snapshot from before it said).
   rules: (if $R == null then {error: $cerr, data: null} else
      {error: null, data: (([$R[] | select(.steered)][0] | if . == null then {repo: null} else rulesOf(.) end)
          + {repos: [$R[].repo],
             cores: ([$R[].snap.health.cores | objects][0] // null), others: ([$R[] | select(.steered | not) | {key: .repo, value: rulesOf(.)}] | from_entries)})} end),
   # The Tests page, of the same records (repo null when none is steered; repos and others as the Board'"'"'s): each
   # record'"'"'s tests (its snapshot'"'"'s, testspart() of conveyor/lib/testfiles.sh; null from a snapshot without it or
   # whose pack does not read). Each run of a
   # file is tagged with its card'"'"'s issue (the number that ends the card id) and that issue'"'"'s url, for its link (older runs: --older),
   # and so is each of its Optimize issues (optimize: the Board'"'"'s filings, their state and proof numbers) and each of
   # its failures (failures: its failed test steps, each with its issue) with its issue'"'"'s url.
   tests: (if $R == null then {error: $cerr, data: null} else def runsOf($r): if type == "array" then map(. + {issue: ([.card | strings | capture("-(?<n>[1-9][0-9]{0,8})$").n | tonumber][0] // null)} | tag($r)) else . end;
      # An Optimize issue no card took (open) that is not among the snapshot'"'"'s open issues was closed on GitHub (the
      # Board'"'"'s Close its issue as done, or by hand): it is closed. With no list of open issues it stays as it is.
      def shut($o): if $o != null and .state == "open" and (.issue | IN($o[]) | not) then .state = "closed" else . end;
      def testsOf: . as $r | (.snap.open.issues | if type == "array" then [.[].issue] else null end) as $oi
        | {repo, tests: (.snap.tests | if type != "object" then null
        elif (.files | type) == "array" then .files |= map(if type == "object" then (.runs |= runsOf($r))
          | if (.failures | type) == "array" then .failures |= map(if type == "object" then tag($r) else . end) else . end
          | if (.optimize | type) == "array" then .optimize |= map(if type == "object" then tag($r) | shut($oi) else . end) else . end else . end) else . end),
        testActions: ((.snap.testActions | objects | {limit, actions, allowed}) // null), control: (.snap.control | objects // null), clis: ((.snap.modelSettings | objects | (.judge.clis // .reviewer.clis) | objects) // null),
        flaky: (.snap.flaky | arrays // null), testMap: (.snap.testMap | objects // null)};
      {error: null, data: (([$R[] | select(.steered)][0] | if . == null then {repo: null} else testsOf end)
          + {repos: [$R[].repo], others: ([$R[] | select(.steered | not) | {key: .repo, value: testsOf}] | from_entries)})} end),
   # The Benchmarks tab, of the same records (repo null when none is steered; repos and others as the Tests page'"'"'s):
   # each record'"'"'s bench (its snapshot'"'"'s: the run in progress and the versions, conveyor/bench/swe.sh swe_board()) and
   # drift (its snapshot'"'"'s latest drift watch, conveyor/bench/drift.sh). The runs and their results are read when the
   # tab shows them (--bench).
   bench: (if $R == null then {error: $cerr, data: null} else
      def benchOf: {repo, bench: (.snap.bench | objects // null), drift: (.snap.drift | objects // null), guard: ((.snap.control | objects | .guard) // null)};
      {error: null, data: (([$R[] | select(.steered)][0] | if . == null then {repo: null} else benchOf end)
          + {repos: [$R[].repo], others: ([$R[] | select(.steered | not) | {key: .repo, value: benchOf}] | from_entries)})} end),
   # What Conveyor measured: the totals of each record for today, the 7 days and the 7 before them, each of the 7
   # days and the slots of today by hour, and every card of the 7 days with its own measurements; cards null when the
   # snapshot of a record is from before it carried them (and prev, days and slots null from one before those).
   metrics: (if $R == null then {error: $cerr, data: null} else {error: null, data: {
        records: [$R[] | {repo, today: (.snap.metrics.today // null), week: (.snap.metrics.week // null), prev: (.snap.metrics.prev // null),
          days: (.snap.metrics.days // null), slots: (.snap.metrics.slots // null)}],
        cards: (if any($R[]; .snap.metrics.cards | type != "array") then null
          else [$R[] as $r | $r.snap.metrics.cards[] | tag($r) | {repo, card, issue, title, url, state, at, metrics} + (if .name then {name} else {} end)] end),
        # The steps of the last 25 h of every card, past the newest cards above (snapshot metrics.steps), for the cache-write alert.
        steps: [$R[] as $r | $r.snap.metrics.steps // [] | .[] | objects | tag($r) | {repo, card, issue, steps} + (if .name then {name} else {} end)],
        # The 7 days side by side: each project (projects, each naming its repo) and the machine. The time to land of the machine is
        # the median over the landed cards of every project (an issue already fixed, closed, is landed too, as in the
        # median of each project; one closed while blocked has no time to land), never a mean of their medians; null when
        # a record gave no cards. usd is the dollars of the priced steps, usdLeftOut the steps it leaves out (weekLeftOut of cost).
        compare: {projects: [$R[] | {repo, landed: (.snap.metrics.week.landed // null), leadSec: (.snap.metrics.week.leadSec.p50 // null), usd: .snap.cost.week,
            usdLeftOut: (.snap.cost.weekLeftOut | numbers // 0), usdEstimate: (.snap.cost.weekEstimate | numbers // 0)}],
          machine: {landed: ([$R[].snap.metrics.week.landed] | if any(. == null) then null else add end),
              leadSec: (if any($R[]; .snap.metrics.cards | type != "array") then null
                else [$R[].snap.metrics.cards[] | select(.state | IN("landed", "closed")) | .metrics.leadSec | numbers] | sort
                  | if length == 0 then null else (.[(length - 1) / 2 | floor] + .[length / 2 | floor]) / 2 | round end end),
              usd: ([$R[].snap.cost.week] | total), usdLeftOut: ([$R[].snap.cost.weekLeftOut | numbers] | add // 0),
              usdEstimate: ([$R[].snap.cost.weekEstimate | numbers] | add // 0)}}}} end),
   # The one Conveyor of the machine over every project, each project on its own, and each Foreman. The settings of
   # the machine are those of the host file on the host, as the health of every record names them (health.machine;
   # null from a host file that sets none, and from a snapshot from before it said). A card holds a slot from its
   # pick to its landing, a landing card too (a landed card waiting for its push holds none), but while it only waits (idle):
   # the machine'"'"'s count (room(), conveyor/lib/run.sh), not the card cap'"'"'s (counted). That count, with the machine cap, is
   # the machine'"'"'s figure; each project'"'"'s own row gives the cards counted against its own cap (counted), or, while
   # its snapshot is behind its card records, loop.json'"'"'s count ($behind), the same figure as the Belt panel'"'"'s.
   machine: (if $R == null then {error: $cerr, data: null} else
        def used: [([.snap.belt[] | select(.landed != true)] | length) - ([.] | idle), 0] | max;
        def inforce: if type == "object" then {model: (.model // null), effort: (.effort // null)} else null end;
      {error: null, data: {host: $conv.host,
        state: ($R | mstate),
        cap: ($R | slots), used: ([$R[] | used] | add), todayUsd: ([$R[].snap.cost.today] | total),
        todayLeftOut: ([$R[].snap.cost.todayLeftOut | numbers] | add // 0), todayEstimate: ([$R[].snap.cost.todayEstimate | numbers] | add // 0), repos: [$R[].repo],
        projects: [$R[] | . as $r | .snap as $s | {repo, state: ($s.health.state // null), reason: ($s.health.reason // null), loop: $s.health.loop,
          mode: ($s.control.mode // null), cap: ($s.health.builderCap // null), guard: ($s.control.guard // null),
          used: (first($behind[] | select(.repo == $r.repo) | .building | numbers) // ([$s.belt[] | select(counted)] | length)),
          needs: (([$s.needsYou.waiting[], $s.needsYou.blocked[], ($s.needsYou.before | arrays | .[]), ($s.needsYou.pipeline | arrays | .[]), ($s.needsYou.farDeps | arrays | .[]) | {card, issue, name: (.name // null), title}] | few($r))
            + [$dec.decisions | arrays | .[] | select(.repo == $r.repo) | {repo, decision: .id, title: .question}]),
          belt: ([$s.belt[] | select(.landed != true) | {card, issue, name: (.name // null), title, step}] | few($r)),
          queue: ($s.queue.order | if . == null then null else map({issue, title}) | few($r) end),
          held: ($s.queue.holding | if . == null then null else map({issue, title}) | few($r) end),
          waiting: ($s.queue.waiting | if . == null then null else map({issue, title}) | few($r) end),
          order: ($s.control.order // null), rules: ($s.control.rules // null),
          models: ($s.modelSettings | if type == "object" then {builder: (.builder | inforce), reviewer: (.reviewer | inforce),
            judge: ($s.control.judgeOn | if . == true then {on: true} + (($s.modelSettings.judge | inforce) // {model: null, effort: null})
              elif . == false then {on: false} else null end)} else null end),
          landedToday: $s.landedCount, todayUsd: $s.cost.today, todayLeftOut: ($s.cost.todayLeftOut | numbers // 0),
          todayEstimate: ($s.cost.todayEstimate | numbers // 0)}],
        foremen: $fm.foremen, foremenError: $fm.error}} end)}'

# stream_conv -- the live feed's Conveyor part: stream.json, when dashboard_stream.py wrote it in the last
# STREAM_FRESH seconds and it holds a snapshot of every record. Nothing printed and 1 otherwise.
STREAM_FRESH=60  # stream.json older than this: the live feed is not running (it rewrites the file every 10 s)
stream_conv() {
  local f=$OUT/stream.json at
  at=$(stat -c %Y "$f" 2>/dev/null) && [ $(( $(date +%s) - at )) -le $STREAM_FRESH ] || return 1
  jq -ce 'select(objects and (.records | type == "array") and (.stream | type == "object"))' "$f" 2>/dev/null
}

# Samples every source into a private folder, then publishes data.js with one rename. A failure keeps the last good
# data.js and exits nonzero. The two slow reads (ssh, the usage read) run beside the rest. Conveyor's part is the live
# feed's, taken as data.js is built, so a cycle never publishes an older one than the feed did; only with no feed
# running is Conveyor read here, by the one ssh command, and that part is marked as no live one (stream.live false,
# heardAt the time of the read).
render() {
  NOW=$(date +%s)
  mkdir -p "$CACHE" || return 1
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  cd "$PP_MAIN" || return 1
  local rc=0 a='' b k conv why
  stream_conv > "$RUN/conveyor.json" || { conveyor > "$RUN/conveyor.json" & a=$!; }
  limit > "$RUN/limit.json" & b=$!
  decisions > "$RUN/decisions.json" || rc=1
  lanes > "$RUN/lanes.json" || rc=1
  # The Foremen after Conveyor: they take the notes Conveyor's part gives.
  if [ -n "$a" ]; then wait "$a" || rc=1; fi
  foremen "$RUN/conveyor.json" > "$RUN/foremen.json" || rc=1
  wait "$b" || rc=1
  if [ -n "$a" ]; then
    why='the live feed is not running'; [ ! -e "$OUT/stream.json" ] || why='the live feed has stopped'
    jq -c --arg at "$(iso "$NOW")" --arg e "$why; Conveyor was read by the 60 s cycle" \
      '. + {stream: {live: false, heardAt: (if .records == null then null else $at end), since: null, error: $e}}' \
      "$RUN/conveyor.json" > "$RUN/conveyor.marked" 2>/dev/null && mv -f "$RUN/conveyor.marked" "$RUN/conveyor.json"
  fi
  for k in conveyor limit decisions lanes foremen; do
    jq -e 'objects' "$RUN/$k.json" >/dev/null 2>&1 || { echo "dashboard: reading $k failed" >&2; rc=1; }
  done
  [ $rc -eq 0 ] || return 1
  # The slow parts are kept for --publish, which builds data.js again with each change the feed brings.
  for k in limit decisions lanes foremen; do
    cp "$RUN/$k.json" "$CACHE/.part-$k.json.$$" && mv -f "$CACHE/.part-$k.json.$$" "$CACHE/part-$k.json" || return 1
  done
  publish_lock || return 1
  if conv=$(stream_conv); then printf '%s\n' "$conv" > "$RUN/conveyor.json"; fi
  publish
}

# panels [limit] -- {updatedAt, panels}: every panel's part, from the five parts in $RUN (conveyor, limit, decisions,
# lanes, foremen .json). With `limit`, a line before it: limit.json's ({limit: the health part's usedPct and resetsAt,
# null with no limit}), from the same jq run. It fails when the build fails or gives nothing (-e).
panels() {
  local upd two=''
  [ "${1-}" != limit ] || two=' | {limit: ((.panels.health.data.limit | objects | {usedPct, resetsAt}) // null)}, .'
  upd=$(jq -ce 'objects' "$OUT/update.json" 2>/dev/null) || upd=null
  jq -cne --slurpfile conv "$RUN/conveyor.json" --slurpfile lim "$RUN/limit.json" --slurpfile dec "$RUN/decisions.json" --slurpfile lanes "$RUN/lanes.json" \
    --slurpfile fm "$RUN/foremen.json" --argjson upd "$upd" --slurpfile kinds "$HERE/dashboard_needs.json" \
    --arg at "$(iso "$NOW")" '$conv[0] as $conv | $lim[0] as $lim | $dec[0] as $dec | $lanes[0] as $lanes | $fm[0] as $fm | $kinds[0] as $kinds | {updatedAt: $at, panels: ('"$PANELS_JQ"')}'"$two"
}

# publish -- data.js from the five parts in $RUN (conveyor, limit, decisions, lanes, foremen .json), with one rename,
# and limit.json beside it, with one rename of its own: the usage limit alone, for the plugin's pane in Claude Code,
# which never reads data.js (data.js grows with the projects and their tests, past any cap a reader can set).
# Each part was checked once before it is here, so it is not checked again: render checks what it read, stream_conv
# gives only a whole stream.json, and a kept part was checked by the cycle that kept it. data.js is panels' one jq
# output, so it is not parsed again either.
publish() {
  PUB=$(mktemp "$OUT/.data.js.XXXXXX") || return 1
  { panels limit | { IFS= read -r l && printf '%s\n' "$l" > "$RUN/limit.out" && printf 'window.DASH = ' && cat; } || exit 1; } > "$PUB" \
    || { echo "dashboard: the page parts could not be built" >&2; return 1; }
  printf ';\n' >> "$PUB"
  chmod 644 "$PUB" && mv -f "$PUB" "$OUT/data.js" || return 1
  chmod 644 "$RUN/limit.out" && mv -f "$RUN/limit.out" "$OUT/limit.json" || return 1
  rm -rf "$RUN" ${LCK:+"$LCK"}; RUN='' PUB='' LCK=''
}

# --publish: data.js again from the live feed's stream.json and the parts the last cycle kept. With no fresh
# stream.json it does nothing: the cycle publishes. A part no cycle has kept yet (the first start, its slow reads still
# out) goes on the page as "not read yet", so the feed's first card events never wait for those reads. stream.json is
# read once, under the lock, so no build publishes an older one than the build before it did.
republish() {
  NOW=$(date +%s)
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  kept_parts || return 1
  publish_lock || return 1
  stream_conv > "$RUN/conveyor.json" || return 0  # not fresh: the EXIT trap removes $RUN and the lock
  publish
}

# kept_parts -- the parts the last cycle kept (limit, decisions, lanes, foremen) into $RUN; one no cycle has kept yet
# is "not read yet".
kept_parts() {
  local k e
  for k in limit decisions lanes foremen; do
    e='not read yet: the collector has just started and its first cycle is still reading'
    # One open of the part: the cycle replaces a part by a whole new file, so this reads the old or the new one whole,
    # where cp fails on the swap. A part that cannot be read at all is "not read yet", as one no cycle has kept.
    if [ -s "$CACHE/part-$k.json" ]; then
      cat -- "$CACHE/part-$k.json" > "$RUN/$k.json" 2>/dev/null && continue
      e='not read yet: the last cycle kept this part, but it cannot be read now'
    fi
    jq -cn --arg k "$k" --arg e "$e" '{limit: {limit: null}, decisions: {decisions: null, unsent: []},
        lanes: {records: null}, foremen: {foremen: null}}[$k] + {error: $e}' > "$RUN/$k.json" || return 1
  done
}
