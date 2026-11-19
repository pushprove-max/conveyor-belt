# SPDX-License-Identifier: Apache-2.0
# The snapshot (the strip-down to Conveyor): one JSON object holding everything the Conveyor
# views show, so the dashboard and /units read one record and cannot disagree. Every object in it that names a
# main-red fix card (card), which has no issue (issue 0), also has name: "Main is red (<commit>)" (rows.jq). It holds:
# needsYou: waiting (the cards blocked for the owner's yes to a visible change: card, issue, title, sentence: the
#   reviewer's, since, files: {count, paths: the first 200 its blocked line names, or null}, shots: the project's own
#   screenshots it kept, {patch: the hash of the patch they were kept for, shots: [{file, caption}]}, and patch: the
#   hash of its kept patch now; both null when it kept none) and blocked
#   (every other blocked card: card, issue, title, reason: the sentence, tail: the end of the output that failed, with its
#   newlines, "" for none, since; and, while a push of main has failed again on its next try, one item for it:
#   push true, under the card of the last landing not pushed, reason naming the cards not pushed, unpushed: their
#   {card, issue}, tail: the push error, since: the first failure), and before (the issues waiting for the owner's yes
#   before their build, as health names them: issue, title, section, since; null when gh cannot list the issues), and
#   pipeline (the open follow-ups filed held for a finding on a pipeline file, followups(), while the control record
#   holds them: issue, title, cost: their "Cost to every card:" line, parent, since; null when gh cannot list the issues),
#   and farDeps (each open issue's dependency in another repository that could not be read, so the issue waits:
#   issue, title, ref: "owner/repo#N", line: the Depends on: line naming it, reason: what gh said; null when gh cannot list the issues),
#   and engine (for a pack that follows the plugin's main, the newest commit of it this machine did not take, until a
#   later one is taken: commit, reason (its failed check, or the hooks it lacks), since; else null), and testRules
#   (when the last pass of the test rules, lib/testrules.sh, had the switch on and matched more files than one day's
#   cap, so it filed nothing: time, matched, cap; else null).
#   mainTest, beside it, is the failure of the whole test on main that stands (maintest(): issue, cases, from, to,
#   since, exit), null when its last run passed or none ran, when the pack names no test.main, or when its issue is
#   known closed. fullTest is the full test suite of the Board (fulltest()): command (the pack names test.full), why
#   (the reason both buttons are off, else null), running ({since, sha, how} while a run or push holds its lock, else
#   null) and last (the last line of its record, else null). suites is each whole-suite run, the release's and the
#   full test's, in one shape (suites()): {kind ("release" or "full test"), version (a release's), step, sha, since,
#   ended (null while under way), state, done, failed, cases (the failed cases' names), timedout (a release's: those
#   of them that timed out, suiteprog()), files ({done, of, failed}),
#   moved, reasons}: the release
#   record of commands/release-prep.sh, its cases counted as the suite runs; the full test's run under way, else its
#   last run. release is main as the Release panel shows it (releasemain()): {tag, count, commits, next, notes, written,
#   head, releases}, null when main cannot be read. drift is the latest drift watch (driftof(), bench/drift.sh --json):
#   the ended cards of the latest engine commit a card ran on against those of the one before, null while there are not two. The
#   first two carry reviews
#   and track, as below: a blocked card is off the belt, and its track is where the step it stopped in is failed,
#   with the seconds that step ran.
# belt: every open card, then every card that has landed and is not yet pushed with its issue closed (landed true;
#   its step is push or issue, and it takes no builder slot; with the rule "Push when a card lands" off, a card whose
#   commit is not pushed is not among them: landed lists it, its track labelled "Landed, waiting for Push landed"): step (brief, build, review, fix, tests, landing: the one in progress, the one its live record names while that runs; proof while a bug card's new tests run on main's code without its fix, proofs(); waiting while it waits
#   on a same-file card, never the landing it waits to begin), waitsOn (that card's {card, issue, state}, else null), gaveWay (the issue
#   of the card it gave up its land turn to while it is fitted, reviewed, fixed or tested again: giveway(); else null),
#   gaveWayFixing (it gave that turn up for the fix of its failed tests), review (the number of
#   the review in progress, else null; it can pass `of`, the 3 of the review rule, after a landing conflict or a test
#   fix), stepAt (when the step began: its live record's at while it runs), model (the one running the step: a session's or a review's, else null),
#   tokens (fresh, so far) and usd so far: the finished steps and the live record of the running one. reading is
#   false, and usd null, while neither a finished session or review nor the live record holds a token: "no reading
#   yet", never $0; atEnd is true when, in that time, the running Claude session's answers all report usage 0 (a route
#   that streams none): "cost shown when the step ends". live is {turns, lastOutputAt, action, at} of the running step (at: when its live record began; for a
#   card waiting for main to change, testrun.sh mainwait(), when that wait began), or null. beyond: why it took a slot beyond the
#   project's cap ("main is red": a main-red fix, redfix()), null once it has landed or when it took none. reviews and
#   track are as below.
# reviews (of a belt card and of a landed one): its finished reviews in order: round, verdict (GO, NO-GO, or none),
#   counts (the findings by level; null for a review recorded before they were counted), sec, fixed (a fix round
#   followed it), and judge, what the judge (judged()) made of it: {ran: true, accepted, declined (how many findings of
#   each), go (its GO came from the judge declining every finding)}, or {ran: false, why} for a review the judge did
#   not read (its call failed, the judge is off, or the review held no finding or no verdict). survived: the findings
#   of a NO-GO that came back after a fix round told to fix them, each {id, rounds: how many fix rounds}, else [].
# track (the same two, and a card in needsYou): steps, the six steps every card is drawn with, Build, Review,
#   Fix, Test, Land, Push, each {name, state, sec}: done, now, skipped (the card did not need it: Fix after a GO, Build
#   of a card landed from a kept patch), failed or todo, with its measured seconds. Build is the set-up (worktree,
#   dependencies, brief) and the build, never the time the issue sat queued; Review and Fix are every round (n: how
#   many, the one in progress counted; Review has of, the rule's count); Test is to come again after a run that failed
#   (while it runs, n: the run that goes now, its sec the earlier runs' seconds);
#   Land holds the rebuild after a conflict and the filing of follow-ups; Push is the push of main and the close of
#   the issue (followups: how many were filed). at is the place of the step in progress (null on a card that has
#   ended), label what it is doing ("review 2 of 3", "fix after review 1", "filing follow-ups", "rebuilding after a
#   conflict", and after the landing "pushing", "push failed; it is tried again", "waiting for GitHub to close the
#   issue"; "Landed, waiting for Push landed", at null, while push is off and its commit is not pushed), since when that began (the live record's at while it runs), reason why Push failed (the push's error, or the issue left open), files a test
#   run's {run, of}, with now {file, at} the file that runs now and when it began (session.sh watch()), tests its cases {done, of, failed} (null when its command said no count: a line
#   `TESTRUN cases=N`; done and failed are the cases its runner named as ended, session.sh watch()), list the list of
#   tests it was given ({mode: "changed", files, by: "map" or "name", age: the made test map's commits behind} or
#   {mode: "whole", why}; null with no test.list: testrun.sh tests()), grown {before, after} the files of its change
#   before and after it was split for its size (growcheck(), lib/slices.sh; else null). No time is estimated from past cards. detail is every recorded step, the 17 of before (queued,
#   picked, worktree ready, dependencies linked, brief written, building, review 1, fix 1, review 2, fix 2, review 3,
#   tests, rebuild, landing, pushed, issue closed, follow-ups filed), each {name, state, sec} (follow-ups filed also
#   n), and detailAt the place in it of the step in progress.
# A card of needsYou, belt and landed also has parent (the issue whose landed line filed it as a follow-up, else
#   null) and its times: start (when its work was first picked up: a card resumed from a kept patch counts the
#   cards whose work it resumes, and a restarted card its issue's earlier runs), pickedAt (its own pick-up), priorSec (the seconds of those earlier cards, pick-up to
#   end), earlier (those cards, the first first: card, start, end, sec, reason, track, so the step view shows them)
#   and totalSec (priorSec and its own pick-up to its end; null while it is open: the view adds the time since
#   pickedAt). The time an issue sat queued is in none of them. stalls: how many times a build, fix, rebase or review
#   of it made no progress for STUCK seconds and was ended (watch()); the card detail shows it. split: what the rule
#   Split large issues made of its issue ({result, slices, filed}, rows.jq), null when the rule did not check it.
# repo: the project's name (REPO), as health names it too; health's room is the card the machine holds back (room()),
#   and its machine the machine's settings (mhost(): {cap, paused}, {unread: true} for a host file that
#   does not read, null when it sets none), the same for every project of the machine, and
#   its cores the cores kept for the user (lib/slots.sh slot_reserved) for the Rules tab too: {reserved: the core
#   numbers, slots: the test-slot pool's size on the cores left (null when not read), unavailable: why this machine
#   cannot keep cores (slot_reserve_why), else null}.
# queue: next (the first 10 issues pick would take, in its order: issue, title, priority, followup, retried, and room:
#   why the machine holds it back, on the one it holds; one forced past its wait also has forced: true and waitsFor:
#   the open issues it waits on, in order too, so it keeps its dependency tag); and, from the
#   control record, order (every issue pick would take, in its order, as next names them with room, and created: its
#   createdAt, areas: its area: labels, so the Rules tab can say what a Never build label would skip), holding (issue, title, priority, followup, retried, created: the issues the record holds; the Board
#   places one released before the snapshot catches up by them, as pick sorts; waitsFor: the open issues it waits on, [] for
#   none) and skipped (issue, title, rule: those its rules exclude; rule is the area
#   label never built, "follow-ups", or the priority); and waiting (every open issue with no card that waits on
#   an open issue it depends on and that pick would take once those land: none held, skipped or waiting for the
#   owner's yes before its build, which open.held gives with their wait; in pick order: issue, title, priority, followup, retried,
#   created, waitsFor: the open issues it waits on, open follow-ups of its dependencies included, waitsOn: each
#   number of waitsFor with its state ({issue, state}; state is one of "building", "blocked", "held", "waiting for a yes", "skipped by a rule", "waiting
#   for #N" (it waits on another issue too), "queued" or "open, no card"), so a wait says why it does not end, forced: `control
#   force` lets it be picked all the same, the dependency guard off; a forced one is in order too). All are null when gh cannot list the issues: the rest of the
#   record is still given. holding and skipped list only issues pick would take but for the record.
#   Each of order, holding and waiting, and each of open.held, also has since: when it came to Held or Queue, as
#   moved.json (MOVED) dates it, so the Board sorts those columns by the time in them, not by the issue's age.
#   Each issue of the queue, and each card of belt and needsYou.blocked, that is a GitHub sub-issue of a parent
#   (openissues()) also has umbrella: that parent's number.
# open: every open issue and where it is (issues: each with its labels), below at open; umbrellas: each open parent
#   (an issue with GitHub sub-issues) as one entry {issue, title, parts, done, all, inFlight, closed}; null when gh cannot list the issues.
# control: the whole control record as it stands, start (where new issues start) among it (null when it does
#   not read); forecast: below, at forecast.
# modelSettings: the build and review models and efforts in force, where each comes from and the choices: the CLIs
#   installed on this host with the models each has registered, and why a seat cannot start (modelsettings()).
# accounts: the names of the host file's accounts, the choices of the control record's account and reviewAccount.
# inFlight: the accounts the cards on the belt started on, whatever the control record names now, each pair once:
#   {account, reviewAccount}, as their worktree lines name them (null: the default login; for a review, its account).
# limits: the weekly limit reading of each Claude account a card started on the control record runs on, the guard's
#   (guardaccts, lib/paths.sh): [{account (null: the default login), uses (build, fix: repairs alone, review), pct, readAt, email (its
#   login on this machine)}]; null when it could not be read.
# areaPrefix: the pack's labels.areaPrefix, what an area label and an area rule start with.
# packLandAs: the pack's push.landAs (main or pr), the rule Land as while the control record's landAs is null; null
#   when the pack cannot be read.
# packPrMerge: the pack's push.prMerge (button, release or idle), the rule Merge PR while the control record's prMerge
#   is null; null when the pack cannot be read.
# standing: the pack's auto.standing, the standing kinds of routine yes that are on (lib/standing.sh), for the Rules
#   tab; null when the pack cannot be read.
# pushCheck: the pack's push.check (true or false), whether the run before a push runs when the control record's
#   pushCheck is null, for the Rules tab; null when the pack cannot be read.
# waitWake: the pack's foreman.waitWake (default 10), the minutes a card waits for main to change, or on another card,
#   before the Foreman's watcher wakes it; read here, on the belt's host, as the Foreman's machine may hold no pack.
# awaitingDeploy: the open issues labelled awaiting-deploy (built, waiting for the owner's deploy), apart from next and
#   from held, which never count them: issue, title, since (when the label was last added; null when GitHub did not
#   say), lowest number first. null when gh cannot list the issues.
# landed: the cards that landed today, or closed their issue as already fixed (step says which), newest first: usd, reviews, the
#   follow-up issues filed, rounds (the reviews list above; reviews is their number), fixes (its fix rounds: every fix line,
#   a fix after a failed Done-when check or failed tests too), track, and pushed (false while health lists its commit as unpushed; null for a closed card,
#   which has no commit), batch (the cards it landed with in one batch, itself among them, in order; null when it landed alone),
#   rollout (the rollout actions its landed line carries, {action, fails, place} each, rollouts(); [] when none).
#   Its usd, reviews and fixes, and a belt card's usd and tokens, are of every run of its issue (a card `retry` or a
#   new pick restarted: the runs below, at metrics); rounds and track are of its own run.
#   landedCount: how many there are, and landedUsd their usd added up (null when one has none); landed holds the
#   newest SNAPKEEP of them (below), and any older one still on the belt.
# declined: the lines of the declined list (DECLINED) the Board's Declined panel shows: not dismissed, not built and at
#   most 7 days old; newest first, each as its line is: id, time, card, issue, finding, by, why, repo (and name, a
#   main-red fix card's, from its records: it has issue 0); one the judge
#   declined with round and findings too (the review of its card it was declined in, and that review's findings as
#   the judge numbered them, [{n, finding}]; both null when they are not found in the card's records).
# declinedRest: every other line of the list, newest first, as its line is, with built (the issue filed for it) or
#   dismissed ({time, by}) when it has them: the panel's "Show every line" shows them.
# branches: the cards land-branch made that landed or closed, on any day (landed and cost.cards drop a card after
#   today and after the 7 days; a lane left as it was still has to be told its change landed): card, issue,
#   title, step, time. Only the newest of those that share an issue and a title, so a branch landed again is one row;
#   the newest SNAPKEEP of those rows, newest first, and past them the newest row of each lane's change (lanekeys), so a
#   lane left as it was is told its change landed however many land after it.
# pushedCards: every card whose commit was pushed on a day of the 7 days to today, whenever it landed (metrics.cards
#   and landed go by the landing): card, issue, time (the push), day (the push's day on this host, as day above). The Foreman's watcher wakes on an awaited issue's push
#   from it (#4042). It holds the newest PUSHKEEP of them, by the push: the watcher looks once a minute, and reads
#   HISTORY for an awaited issue that is in neither this list nor metrics.cards.
# The lists that grow with every card that lands are cut to their newest SNAPKEEP, so a snapshot read every second
# stays the same size however many cards land (README.md says its bound): landed, metrics.cards, cost.cards,
# cost.unpriced (newest step first; steps of one time in their order) and declinedRest (and pushedCards, above). Each list whole is in HISTORY, written by every snapshot as it
# ends; `conveyor.sh history` prints it, and the Board reads it when a panel that shows them opens. historySum: the
#   cksum of that history as written, less every waitMaxSec and runSec in metrics.cards (thisRun's too), which grow
#   with the clock while a card is blocked or open (null when it could not be written); the Board reads the history again only when
#   it or the day changed.
# health: the health record, which names builderCap, models and efforts as in force (the control record's, else the seed's).
# testSlots: the machine's test-slot pool (lib/slots.sh), {used: the slots a test run holds now, of: the pool's size};
#   null when the pool cannot be read.
# flaky: the cases of the flaky-test record (lib/flaky.sh) with entries in the last FLAKY_DAYS days to the health
#   record's time, most entries first: case, count (those entries), issue (the one last filed for it, else null),
#   files (the test files the case counts for, lib/testfiles.sh caseowners: a runner's case, its case file too).
# slowOff: the test files kept off card test steps for their CPU seconds (lib/testrun.sh slowoffs()), by file: file,
#   issue (its "Slow test" issue, whose card's landing brings it back) and why: cpu and sec in the card run that filed
#   it (card), last {cpu, card} (the card run before it), budget, and since.
# testActions: the test actions (lib/testaction.sh): seat (the Tests seat, {cli, model, effort}, else null), limit
#   (the seconds an action may run) and actions (the newest records, running and kept, and each file's newest older
#   judge with a verdict, newest first, each with text and textCut, the end of its text: testacts()), and allowed (the
#   pack's models by CLI, the builder's as modelSettings gives them, that the Board offers for a CLI that lists none;
#   null when the pack does not read).
# tests: each test file's figures, the test settings of the pack and the totals of the card test steps
#   (lib/testfiles.sh testspart() says what it holds); null when the pack cannot be read.
# testMap: the Tests page's Test map part: the map's state, its coverage tool, the last whole-suite run's seconds and
#   the last build by hand (lib/testmap.sh mapboard() says what it holds); null when the pack cannot be read.
# bench: the Benchmarks tab's live part: the SWE-bench runs' board.json (bench/swe.sh swe_board() says what it
#   holds: the run in progress, the versions, the expected figures; the tab reads the runs and results when shown,
#   `bench swe history` and `bench swe show`); null before any run.
# prices: the Rules tab's Model prices: builtIn (each row of the built-in price table: model, input, output, cacheRead,
#   cacheWrite, in $ per million tokens), overrides (the pack's prices, added models and aliases, which win over it),
#   names (each model's display name) and seen (each model ID the steps and the research lane's sessions of the last
#   30 days ran: model, sessions, routes, as: the model it is priced as, or null) and research (the pack's research lane model, or null); null when the
#   table cannot be run.
# checkRun: the check run the pack's checks.progress prints, as checkrun() below says; no such field without one.
# cost: usd of the steps that ended today and in the 7 days to today, those of a blocked card that `retry` moved
#   to the retried file among them (the money was spent; such a card is in no other part of the record); over the
#   cards that landed in those 7 days, perLanded (their average usd, each the dollars of every run of its issue) and
#   landedAfter (how many landed after 1, 2, 3 and more reviews of their own run). today, week and perLanded are the dollars of the steps that are priced: todayLeftOut,
#   weekLeftOut and perLandedLeftOut count the steps each leaves out for having no price, unpricedSteps is
#   the 7 days' count and unpriced lists those steps ({card, issue, step, time, why}); all three figures are null
#   only when the price table cannot be run. cards, one row for every card with a step that ended in the 7
#   days, the one worked on last first: card, issue, title, state (on the belt, blocked, landed, closed or retried)
#   and its usd of today and of the 7 days. A card landed or blocked on an earlier day is in it, so is a retried one.
#   A card restarted is one row, of its newest run: runs (how many), its usd those of every run's steps. picks: the
#   cards the rule Pick settings picked, on any day, one row a group and builder choice ({group, model, effort,
#   cards, landed, usd, firstTry, reviews, open}; a card's earlier runs count with it; usd null when a step of them
#   has no price).
# A day is this machine's local day (day names today). Dollars are list prices from the one price table
# (dashboard_limit.py, `cards`; the pack's prices win over its rows), at the models that ran the step (its session's result, else the model its line
# names), never at the models in force now: a step whose line names no model is unpriced. A step that table cannot
# price has no usd and says why (unpriced); a card's usd and a card row's sums over it are null, never the sum of
# the priced part (the totals above count it out instead); every usd is null when the table cannot be run.
# Every part is read from one copy of the card records and the retried file, taken when the snapshot begins
# (snapcopy): health, the rows and the queue cannot differ by a line written, or a card retried, while it is built (a
# card that landed between two reads was in landed but not in health's unpushed, so it showed as pushed). The copy
# and the rows are files in a folder of the snapshot's own, removed however it ends (it runs in a subshell).
TRACK=$(<"$HERE/jq/track.jq")
SNAPKEEP=20 PUSHKEEP=100
# The measurements of each card, as `metrics` on every card the snapshot shows, and their totals. A card's:
# queueSec (its issue opened to picked), slotSec (of that time, the seconds every slot was taken, from the samples;
# null when no sample covers it), buildSec, reviewSec, fixSec, testSec, rebuildSec (each step's seconds added up),
# landSec (every landing attempt, the one that met a conflict included), pushSec (landed to pushed), waitMaxSec (waiting on the owner: from the end of the issue's last blocked card to
# its retry, or to this card's pick when its retry time is not recorded, and for a card that is blocked now, its end to now), leadSec (issue opened to landed) and
# cycleSec (picked to landed), reviews, firstReview (its verdict), findings (by level, all reviews; null when a review
# has none counted), rebuilds, retries (the issue's blocked cards before it), blockClass (why it is blocked: visible
# change, no change, conflict, session failed, tests failed, timeout, prompt too long or other), depth, followups (how
# many it filed), diff ({files, added, removed}), limit ({before, after, used}: weekly limit percent; used is null
# when the limit reset during the card), usd (null when
# a step is unpriced), tokens, unpriced (how many of its steps have no price) and timeline: each finished step with
# its time, seconds, tokens, dollars, model (the one it was priced at, else the one its line names), effort,
# findings, tests, session stats, unpriced (why it has no price, null when it has one) and, on a step priced from
# the pack's prices, override (true) and, on a review whose reviewer or judge wrote cache, writes and judgeWrites (each
# {model, write, write1h}: the cache write tokens of its session, which keeps no transcript). A reading that was not
# taken is null: a session whose usage could not be read has tokens null, not 0. runSec (pick-up to end, or to now),
# fixes and testRuns (its fix and test lines). runs: how many runs of its issue the card's figures add up (the cards
# of the issue since it last landed or closed, with the retried ones, to this one): with more than one, usd, tokens,
# unpriced, each step's seconds, runSec, reviews, fixes and testRuns are their sums (usd and tokens null when a run's
# is), and thisRun holds the card's own; queueSec, leadSec, cycleSec and the rest stay its own.
# The snapshot's metrics: today, week (the 7 days to today) and prev (the 7 days before those) as totals() gives them;
# days, each of the 7 days oldest first ({day, landed, blocked, cycleSec: its median, firstReviewPass, perLandedUsd: null
# when a step of the day's landed cards is unpriced, so a part cost is never drawn as the whole});
# slots, today's samples by local hour ({hour, slots: the mean in use, cap}); cards, each card of the 7 days; and
# steps, each card with a step that ended in the last 25 h ({card, issue, name when it has one, steps: those steps'
# {step, time, writes, judgeWrites}}), not cut at SNAPKEEP as cards is: the Board's cache-write alert names the card step of each
# session that wrote cache in its 24 h by them, from more cards than the newest SNAPKEEP.
METRICS=$(<"$HERE/jq/metrics.jq")
# CARDRUNS (after METRICS; cardruns.py runs it on the cards of the issues that changed): given cards, every card of
# each issue among them, it prints for each, in their order, the card with its metrics and its runs' sums, then its
# waits ($waits in the snapshot) of the first kind, then of the second (arrays). It reads, past the cards of the card's
# issue, only $now, the samples ($smp), $every and $yes (cardruns.py keys the issue's summary on those).
# $blocks: the stretches the issue was blocked, which cardm counts. A card restarted (`retry`, or a stop and a new
# pick) is a new card of the same issue. Its runs are the cards of its issue since the issue last landed or closed, in
# the card records and the retried file, up to and with it ($runsOf, by card). A card of more than one run holds their
# sums: usd and x.tokens (what a belt card adds its live step to), runReviews and runFixes, runSteps (their steps: the
# cost rows and the per-landed averages count them), and in metrics every figure added up, with thisRun its own;
# metrics.runs counts them on every card. The waits: a blocked card from its end to when `retry` gave it back
# (retriedAt); a card retried before that was recorded, to the next pick of its issue; one still blocked (not retried,
# no later pick) to now; a retried one with neither is left out. Then a card whose issue was closed while it was
# blocked (x.blockedAt): from its block to its closed line.
CARDRUNS='. as $cs
    | ([$cs[] | if .x.blockedAt != null then {issue, end: .x.blockedAt, to: .x.endAt} else select(.step == "blocked") | {issue, end: .x.endAt, to: .x.retriedAt} end]) as $blocks
    | ([$cs[] | {card, issue, at: (.startedAt | fromdate)}]) as $picks
    | ($smp | map(.time | fromdate)) as $st | ($smp | map(select((.cap | type) == "number" and .slots >= .cap) | .time | fromdate)) as $sf
    | [$cs | map(. + {metrics: cardm($now; $blocks; $st; $sf; $every; $yes)})] as $all
    | ($all[0] | map(select(.issue != 0)) | group_by(.issue)
        | map(sort_by(.startedAt, .card) | reduce .[] as $k ({run: [], out: []}; .run += [$k] | .out += [{key: $k.card, value: .run}]
            | if ($k.step | IN("landed", "closed")) and $k.x.blockedAt == null then .run = [] else . end) | .out[])
        | from_entries) as $runsOf
    | def runsum(f): [.[] | f] | if any(. == null) then null else add end;
      def secsum(f): [.[] | f | numbers] | if length == 0 then null else add end;
      def own: {usd, tokens, unpriced, buildSec, reviewSec, fixSec, testSec, rebuildSec, landSec, runSec, reviews, fixes, testRuns};
    $all[0][] | ($runsOf[.card] // [.]) as $r | .runSteps = [$r[].steps[]] | .runReviews = ($r | map(.reviews) | add)
      | .runFixes = ($r | map(.metrics.fixes) | add)
      | if ($r | length) < 2 then .metrics.runs = 1
        else .usd = ($r | runsum(.usd) | if . == null then null else . * 10000 | round / 10000 end)
          | .x.tokens = {claude: ($r | map(.x.tokens.claude // 0) | add), codex: ($r | map(.x.tokens.codex // 0) | add)}
          | .metrics += {runs: ($r | length), thisRun: (.metrics | own), usd, tokens: ($r | runsum(.metrics.tokens)),
              unpriced: ($r | map(.metrics.unpriced) | add), buildSec: ($r | secsum(.metrics.buildSec)), reviewSec: ($r | secsum(.metrics.reviewSec)),
              fixSec: ($r | secsum(.metrics.fixSec)), testSec: ($r | secsum(.metrics.testSec)), rebuildSec: ($r | secsum(.metrics.rebuildSec)),
              landSec: ($r | secsum(.metrics.landSec)), runSec: ($r | secsum(.metrics.runSec)), reviews: ($r | map(.metrics.reviews) | add),
              fixes: .runFixes, testRuns: ($r | map(.metrics.testRuns) | add)} end
      | ., [select(.step == "blocked") | (.x.endAt | fromdate) as $e | .issue as $i | .card as $k
          | ([$picks[] | select(.issue == $i and .card != $k and .at >= $e) | .at] | min) as $nx
          | if .x.retriedAt != null then {from: $e, to: (.x.retriedAt | fromdate)}
            elif $nx != null then {from: $e, to: $nx} elif .x.retried then empty else {from: $e, to: $now} end],
        [select(.x.blockedAt != null) | {from: (.x.blockedAt | fromdate), to: (.x.endAt | fromdate)}]'
# checkRun, only when the pack's checks names a progress command: the check run it prints (pack.schema.json says its
# shape) with counts ({passed, failed, running, queued, reused}), done (passed, failed and reused lanes), all, and
# leftSec: while it runs and once a quarter of its lanes are done, the mean seconds of the done lanes with a time,
# times the lanes not done, over the lanes running (at least 1); else null; and lines, the block /units prints above
# ON THE BELT: `CHECK RUN <name> <sha> · <done>/<all> lanes · <elapsed> · ~<left> left` (the result in place of the
# time left once it ended), `✓ <passed> ✗ <failed> ▶ <running> … <queued>`, then up to 3 failed lanes and up to 3
# running lanes with how long each has run. null when it printed nothing, or the run ended an hour or more ago. {error: "check run: progress unreadable: <the first line of why>"} when the command fails,
# takes over 5 s, or prints anything but one JSON object of that shape. The command runs from main's checkout at most
# once every 10 s (<state>/checkrun.json keeps its answer, checkrun.json.lock lets one snapshot at a time run it), so
# views asking often, or at once, do not run it each time.
CHECKRUN_OK='
  def at: type == "string" and (try (sub("\\.[0-9]+Z$"; "Z") | fromdate | true) catch false);
  def lane: type == "object" and has("started") and has("sec") and (.name | type == "string")
    and (.state | IN("queued", "running", "passed", "failed", "reused"))
    and (.started == null or (.started | at)) and (.sec == null or (.sec | type == "number"));
  if length == 1 and (.[0] | type == "object" and has("ended") and has("result") and (.name | type == "string") and (.sha | type == "string")
      and (.started | at) and (.ended == null or (.ended | at)) and (.result | IN(null, "pass", "fail"))
      and (.lanes | type == "array" and all(.[]; lane)))
  then {run: .[0]} else {error: "it printed JSON that does not match the check-run shape"} end'
CHECKRUN_SHOW='
  def t: sub("\\.[0-9]+Z$"; "Z") | fromdate;
  def took: [., 0] | max | floor | if . < 60 then "\(.)s" elif . < 3600 then "\(. / 60 | floor)m"
    else "\(. / 3600 | floor)h \(. % 3600 / 60 | floor | tostring | if length < 2 then "0" + . else . end)m" end;
  if .error then {checkRun: {error: "check run: progress unreadable: \(.error)"}}
  elif .run == null or (.run.ended != null and now - (.run.ended | t) >= 3600) then {checkRun: null}
  else .run | [.lanes[].state] as $s | def n($k): [$s[] | select(. == $k)] | length;
    (n("passed") + n("failed") + n("reused")) as $done | ($s | length) as $all
    | [.lanes[] | select(.state | IN("passed", "failed", "reused")) | .sec | numbers] as $secs
    | (if .ended == null and $done < $all and $done * 4 >= $all and ($secs | length) > 0
        then ($secs | add / length) * ($all - $done) / ([n("running"), 1] | max) | round else null end) as $left
    | {checkRun: (. + {counts: {passed: n("passed"), failed: n("failed"), running: n("running"), queued: n("queued"), reused: n("reused")},
        done: $done, all: $all, leftSec: $left,
        lines: ([
          "CHECK RUN \(.name) \(.sha[:7]) · \($done)/\($all) lanes · \((.ended // now | if type == "string" then t else . end) - (.started | t) | took)"
            + (if $left != null then " · ~\($left | took) left" elif .ended != null then " · \(.result // "ended")" else "" end),
          "✓ \(n("passed")) ✗ \(n("failed")) ▶ \(n("running")) … \(n("queued"))"]
          + [.lanes[] | select(.state == "failed") | "  ✗ \(.name)"][:3]
          + [.lanes[] | select(.state == "running") | "  ▶ \(.name)" + (if .started != null then " \(now - (.started | t) | took)" else "" end)][:3])})}
  end'
# The whole-suite runs, each in one shape (suites, above): the release's (its record, commands/release-prep.sh) and
# the full test's (fulltest()). One under way is counted from its runner's marks (suiteprog(); a red full test's, while
# its failed cases run alone, from those kept as its run ended), and says main moved once
# main's head is not the one its suite started on (the record's main); a red release's, while its failed cases run alone,
# from the counts its record keeps (commands/release-prep.sh relsuite()). A release record left
# running with its lock free was ended from outside before it could say so: stopped, when the record was last written.
# A full test's run left so is shown as the line the next ask records for it: an error, with its reason.
suites() {
  local r fr l t m free
  if r=$(jq -ce 'objects | select(.kind == "release") | del(.pid)' "$CARDS/release/run.json" 2>/dev/null); then
    if [ "$(jq -r .ended <<<"$r")" = null ]; then
      if ( flock -n 9 ) 9>>"$CARDS/release/lock" 2>/dev/null; then
        t=$(p_stat "$CARDS/release/run.json") && r=$(jq -c --argjson t "${t#* }" '. + (.counts // {}) | del(.counts) | .state = "stopped" | .ended = ($t | todate)' <<<"$r")
      elif jq -e '.state == "running" and .sha != null' <<<"$r" > /dev/null; then
        # A card that lands while the suite runs moves main: the panel says so now, not at the suite's end.
        r=$(jq -c --slurpfile p <(suiteprog "$CARDS/release/wt") --arg h "$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)" \
          '. + (.counts // $p[0]) | del(.counts) | if .main != null and $h != "" and .main != $h then .moved = true else . end' <<<"$r"); fi
    fi
  fi
  # A full test's marker read before and after its lock is found free ended with no result (fulldead()): a run that
  # ends in between removes it, and one that starts in between writes a new one.
  { m=$(<"$FULLTEST.running"); } 2>/dev/null; free=''
  ! ( flock -n 9 ) 9>>"$FULLTEST.lock" 2>/dev/null || free=1
  if [ -z "$free" ] && fr=$(jq -ce 'objects' "$FULLTEST.running" 2>/dev/null); then
    fr=$(jq -c --slurpfile p <(suiteprog "$CARDS/fulltest/wt") '{kind: "full test", version: null, step: .how, sha, since, ended: null, state: "running", moved: false, reasons: []} + (.counts // $p[0])' <<<"$fr")
  elif l=$({ [ -n "$free" ] && [ -n "$m" ] && [ "$(cat "$FULLTEST.running" 2>/dev/null)" = "$m" ] && fulldead; } \
      || tail -n 1 "$FULLTEST" 2>/dev/null | jq -ce 'select(.kind == "run")' 2>/dev/null); then
    fr=$(jq -c '{kind: "full test", version: null, step: (if .push then "push" else "run" end), sha, since: null, ended: .time, state, done: null,
      failed: (.cases | length), cases: [.cases[].case], moved: false, reasons: (if .reason then [.reason] else [] end)}' <<<"$l")
  else fr=''; fi
  printf '%s\n' "$r" "$fr" | jq -cs 'map(objects | del(.main))'
}
# What the Release panel shows of main (docs/board.md): the newest vX.Y.Z tag, the commits since it (count; the newest
# 100, {sha, subject}), the version to release next, whether main holds its notes (docs/releases/<next>.md), written
# (every X.Y.Z of a docs/releases/<X.Y.Z>.md on main, for a version the owner types instead), main's head, and
# releases: whether the project releases with Conveyor (main holds docs/releases/, where release-prep's notes go).
# The next version is the newest docs/releases/<X.Y.Z>.md higher than the tag, else the tag's next minor (the next
# version after the newest release). plugin.json's version is not read: it can name a version with no notes.
relhigher() { [ "$1" != "$2" ] && [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]; } # <X.Y.Z> <X.Y.Z>
releasemain() {
  local h tag base next v w rel=false re='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
  h=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null) || { echo null; return; }
  tag=$(git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
  base=${tag#v}; base=${base:-0.0.0}
  [ "$(git cat-file -t "$h:docs/releases" 2>/dev/null)" != tree ] || rel=true
  w=$(git ls-tree --name-only "$h" docs/releases/ 2>/dev/null | sed -n 's|^docs/releases/\(.*\)\.md$|\1|p' | grep -E "$re" | sort -V)
  v=$(tail -n 1 <<<"$w")
  if [ -n "$v" ] && relhigher "$v" "$base"; then next=$v
  else next=$(awk -F. '{ print $1 "." $2 + 1 ".0" }' <<<"$base"); fi
  git log -n 100 --format='%H%x09%s' "${tag:+$tag..}$h" 2>/dev/null | jq -Rcs --arg h "$h" --arg t "$tag" --arg n "$next" --argjson rel "$rel" --arg w "$w" \
    --argjson c "$(git rev-list --count "${tag:+$tag..}$h" 2>/dev/null || echo null)" --argjson nt "$(git cat-file -e "$h:docs/releases/$next.md" 2>/dev/null && echo true || echo false)" \
    '{tag: (if $t == "" then null else $t end), count: $c, commits: [split("\n")[] | select(. != "") | split("\t") | {sha: .[0], subject: (.[1:] | join("\t"))}],
      next: $n, notes: $nt, written: [$w | split("\n")[] | select(. != "")], head: $h, releases: $rel}'
}
# The drift watch of the snapshot's copy of the records (bench/drift.sh --json), else null. It reads the worktree lines
# (the engine commits, in order) and the cards that ended, and a card writes no line that it reads after its end line:
# it is kept in $STATE.drift beside the sum of the worktree and end lines (landed, closed, blocked) it was made of, and
# made again only when they changed.
driftof() { # <scratch folder>
  local k v
  k=$(grep -hE '"step":"(worktree|landed|closed|blocked)"' -- "$1/${STATE##*/}" "$1/${RETRIED##*/}" 2>/dev/null | cksum) || { echo null; return; }
  if [ "$(head -n 1 "$STATE.drift" 2>/dev/null)" = "$k" ] && v=$(sed -n 2p "$STATE.drift") && [[ $v == null || $v == \{* ]]; then printf '%s\n' "$v"; return; fi
  v=$(cat -- "$1/${STATE##*/}" "$1/${RETRIED##*/}" 2>/dev/null | "$HERE/bench/drift.sh" --json /dev/stdin 2>/dev/null) || v=null
  { printf '%s\n%s\n' "$k" "$v" > "$STATE.drift.$$" && mv -f "$STATE.drift.$$" "$STATE.drift"; } 2>/dev/null || rm -f "$STATE.drift.$$"
  printf '%s\n' "$v"
}
checkrun() { # <scratch folder>; prints {} when the pack names no progress command, else {checkRun: ...}
  local cmd f=${STATE%/*}/checkrun.json out rc v
  cmd=''; ! packget checks cmd 2>/dev/null || cmd=$(jq -r 'objects | .progress // empty' <<<"$cmd" 2>/dev/null)
  [ -n "$cmd" ] || { echo '{}'; return; }
  # One snapshot at a time looks at the answer and runs the command, so two at once do not both run it.
  ( flock 9 && { [ -s "$f" ] && p_newer "$f" 10; } && exit 0
    # Its output goes to a file, not a pipe: a child it leaves in the background keeps a pipe open past the 5 s.
    (cd "$MAIN" && timeout -k 1 5 bash -c "$cmd" >"$1/progress.out" 2>"$1/progress.err" < /dev/null 7>&- 8>&- 9>&-); rc=$?
    out=$(cat "$1/progress.out" 2>/dev/null)
    if [ $rc = 124 ] || [ $rc = 137 ]; then v=$(jq -cn '{error: "it took over 5 s"}')
    elif [ $rc != 0 ]; then v=$(jq -cn --arg e "$(grep -m1 . "$1/progress.err" | cut -c1-200)" --arg rc "$rc" '{error: (if $e == "" then "exit \($rc)" else $e end)}')
    elif [ -z "${out//[[:space:]]/}" ]; then v='{"run":null}'
    else v=$(jq -cs "$CHECKRUN_OK" <<<"$out" 2>&1) || v=$(jq -cn --arg e "$(head -n 1 <<<"$v" | cut -c1-200)" '{error: $e}'); fi
    printf '%s\n' "$v" > "$f.$$" && mv -f "$f.$$" "$f" ) 9>>"$f.lock"
  jq -c "$CHECKRUN_SHOW" "$f" 2>/dev/null || echo '{"checkRun":{"error":"check run: progress unreadable: its last answer cannot be read"}}'
}
# The snapshot's copy, with no wait for the records' lock unless a new issue has to be held (adopt, before the copy):
# the loop's cards hold that lock for seconds at a time on a busy host, and every snapshot waited for it. The copy is
# taken under the lock a rewrite of the records holds (moveout), so no card is in both files or in neither, and only
# the whole lines of the records are read (check() says why). 3 when the copy was taken and the hold could not be saved.
snapcopy() { # [<open issues json>]
  local rc=0 c CTL_V
  [ -z "${1:-}" ] || { ctlread 2>/dev/null && c=$CTL_V && [ "$(adopted "$c" "$1" 2>/dev/null)" = "$c" ]; } || locked adopt "$1" || rc=3
  # The copy, and what the snapshot reads of the records past their rows, are the state database's answers to one
  # call (state.py), read at one time: the pushes, the cards waiting for the owner's yes (yes), the samples and the
  # declined list.
  ( flock 5 && stdb ask -o "$d/${STATE##*/}" lines cards -- -o "$d/${RETRIED##*/}" lines retried -- -o "$d/pushes" pushes \
      -- -o "$d/yes" yes "$YES" "$ST" -- -o "$d/samples" samples -- -o "$d/${DECLINED##*/}" lines declined ) 5>>"$STATE.checked.lock" \
    && { [ ! -e "$CONTROL" ] || cp -- "$CONTROL" "$d/control.json"; } && return $rc
}
# The rows of a records file of the copy, written to <to>, from a running summary of the file kept beside it (<kept>):
# a line `<key> <offset> <sum>` (key: rows.jq and what rows() passes it; offset: how many of the file's bytes the
# summary has read; sum: their cksum), then each card's row, one a line, in card order (as rows() gives them). A
# snapshot parses only the lines past the offset: each card they name has its row made anew from its own lines (rows.jq
# makes a card's row from that card's lines alone), found by a fixed-string search for its name, and every other row is
# kept. The summary is made anew from the whole file when it is missing, has another key, or its bytes are no longer
# the file's first bytes: `retry` rewrote the card records, shorter, or grown past the offset again since. Making
# every row from the whole file, on each line the loop wrote, was a fifth of a snapshot's work and grew every day.
# A summary made anew from a whole file that is not empty is said on stderr first, before that long work: card
# records rewritten (a retry, as `control resume` makes for the cards a sign-in failure blocked) or a new engine
# leave it to be made anew, and on a long history the snapshot then runs past a reader's wait (the Foreman's 45 s),
# which has only a killed run that said nothing. The message names those causes only when a summary was kept and no
# longer fits: with none kept yet (the first snapshot) it says so instead.
# What the Declined part reads of each line of the records (linesum(), lib/records.sh): every review line, with the
# judge's accepted and declined findings only (a card's reviews are counted for its round), and the picked line of a
# main-red fix card. It read every line of the records whole on each snapshot (#398).
JUDGEDLINE='select(. != "") | fromjson | objects | select(.step == "review" or (.step == "picked" and (.mainRed | type) == "string"))
  | {card, step} + if .step == "picked" then {mainRed} else {judge: (.judge | if type == "object" then {accepted, declined} else . end)} end'
snaprows() { # <records file> <kept> <to>
  local k r cs size h1 h2 o s n=-1 src=$1 rf=$3.rows skip=0
  # The key is the same for both files of one snapshot: worked out once, in the snapshot's shell (SNAPROWS_K).
  [ -n "${SNAPROWS_K:-}" ] || SNAPROWS_K=$({ cksum < "$HERE/jq/rows.jq" && printf '%s\n' "$MAX_REVIEWS" "$NODEPS" "$YES" "$SHUT"; } | cksum) || return 1
  # The file's sum and size from one cksum: a file not grown since the summary needs no other program to check it.
  k=$SNAPROWS_K && r=$(cksum < "$1") && cs=${r%% *} size=${r##* } && [[ $size =~ ^[0-9]+$ ]] || return 1
  # Read from a copy: a snapshot running beside this one may put a newer summary in its place meanwhile.
  cp -- "$2" "$3.sum" 2>/dev/null || : > "$3.sum"
  { read -r h1 h2 o s && [ "$h1 $h2" = "$k" ] && [[ $o =~ ^[0-9]+$ ]] && [ "$o" -le "$size" ] \
      && if [ "$o" = "$size" ]; then [ "$s" = "$cs" ]; else [ "$(head -c "$o" "$1" | cksum)" = "$s $o" ]; fi; } < "$3.sum" && n=$o
  # Not grown: the rows are the summary's, past its first line.
  if [ "$n" = "$size" ]; then rf=$3.sum skip=1
  else
    if [ "$n" -lt 0 ] && [ "$size" != 0 ]; then
      if [ -s "$3.sum" ]; then echo "conveyor: the snapshot is being made anew from the whole card records (a retry or a resume rewrote them, or the engine changed); this one takes longer" >&2
      else echo "conveyor: the snapshot is being made from the whole card records (no summary of them is kept yet); this one takes longer" >&2; fi
    fi
    : > "$3.kept"
    if [ "$n" -ge 0 ]; then
      # The cards the new lines name (as JSON strings), their lines, and the kept rows of the other cards. A row line
      # begins {"card":<name>, so its first comma ends the name.
      tail -c +$((n + 1)) "$1" | jq -c .card | sort -u > "$3.ids" \
        && grep -F -f "$3.ids" "$1" | jq -c --slurpfile t "$3.ids" 'select(.card | IN($t[]))' > "$3.lines" \
        && sed 's/^/{"card":/; s/$/,/' "$3.ids" | awk 'NR == FNR {t[$0]; next} FNR > 1 && !(substr($0, 1, index($0, ",")) in t)' - "$3.sum" > "$3.kept" || return 1
      src=$3.lines
    fi
    rows "$src" | jq -c '.[]' | cat "$3.kept" - | LC_ALL=C sort -s -t, -k1,1 > "$3.rows" || return 1
    { printf '%s %s %s\n' "$k" "$size" "$cs" && cat "$3.rows"; } > "$2.$$" 2>/dev/null && mv -f "$2.$$" "$2" || rm -f "$2.$$"
  fi
  awk -v s="$skip" 'BEGIN {printf "["} NR > s + 1 {printf ","} NR > s {printf "%s", $0} END {print "]"}' "$rf" > "$3"
}
snapshot() (
  next=null; held=null; built=null; queue=null; yes=$YES
  # A stop (TERM, INT, HUP) ends the snapshot once the command it runs has ended. A reader's timeout sends TERM to the
  # whole process group; one that comes as the shell starts a command reaches the shell after the fork and never the
  # new command. With no trap of its own, the shell then runs the EXIT trap at once, and the scratch folder is removed
  # under that command (cardruns.py failed with FileNotFoundError on cardruns.jq, #359).
  d=$(mktemp -d) || exit 1; trap 'rm -rf "$d"' EXIT; trap 'exit 143' TERM INT HUP
  # The issues first: a new one is held (adopt) before the copy, so the snapshot never shows it in the queue. When
  # its hold cannot be saved, the issues are not known: a new issue is never shown queued when it is not held.
  saw=$(clock) || exit 1; issues=$(openissues "$FIELDS" 2>/dev/null) || issues=''
  snapcopy "$issues"; case $? in 0) ;; 3) issues='' ;; *) echo "conveyor: cannot copy the card records" >&2; exit 1 ;; esac
  READ=$d/${STATE##*/}; READ_OLD=$d/${RETRIED##*/}; CONTROL=$d/control.json; LIVEJSON=$(live); : "${LIVEJSON:={\}}"
  # The control record read once, in this shell: the readers below (health's among them) find it kept (ctlread).
  if ctlread 2>/dev/null; then control=$CTL_V; else control=null; fi
  # A plain assignment inside the subshell, never a prefix on the call: a prefix would put the whole issue list in the
  # environment of every command health runs, and past the kernel limit each one fails with "Argument list too long".
  # The rows before health: health's summaries of the records go stale with the rows' one, and snaprows says so first.
  # The check before the rows: a line that does not check is set aside (and dropped from READ) before rows.jq reads it,
  # else one bad line stops the snapshot (#290). READ is this snapshot's own copy, so health need not check it again.
  # shellcheck disable=SC2034 # READCHECKED is read by health (lib/views.sh), which conveyor.sh sources beside this file
  check && READCHECKED=1 && snaprows "$READ" "$STATE.rows" "$d/rows" || exit 1
  # The machine's test-slot pool (lib/slots.sh slot_pool) read once, in this shell: health's cores and the slots in
  # use below read it. SLOTSREAD says it was read.
  SLOTSREAD=''; ! slot_pool >/dev/null 2>&1 || SLOTSREAD=1
  # shellcheck disable=SC2034 # read by health (lib/views.sh), which conveyor.sh sources beside this file
  h=$(ISSUESJSON=${issues:-null}; health) && printf '%s\n' "$h" > "$d/health" || exit 1
  snaprows "$READ_OLD" "$RETRIED.rows" "$d/old" 2>/dev/null || { echo "conveyor: $RETRIED does not read as card records; stopping" >&2; exit 1; }
  # A snapshot that reads GitHub itself (no `watch` feed, GITHUB unset: the Board's ssh path) reads the CLIs' models
  # too, as github() does for the feed, when the host's report is missing or CLI_TTL old; else a host the loop has
  # never run on offers each CLI with no models.
  [ -n "$GITHUB" ] || hostclis due >/dev/null 2>&1 || :
  models=$(jq -c .models <<<"$h"); settings=$(modelsettings "$control"); ACCT=$(ctlacct "$control")
  # A main-red fix card is titled from its entry as it is now (redtitles()), so a case added while it runs shows.
  # One card a line: the pricing below prices only the lines that changed since the last snapshot.
  # A bug card's check of its new tests on main's code (proofs()) runs between two steps, no start line before it: while
  # it runs (its live record there, the card open, its last line no start), it is the card's proof, the step in progress.
  jq -c --argjson m "$models" --argjson live "$LIVEJSON" --argjson proof "$(proofs)" --argjson away "$(aways)" --argjson red "$(redtitles)" --slurpfile old "$d/old" '(map($live[.card] as $v | $proof[.card] as $p
      | .title = ($red[.card] // .title) | .gaveWay = ($away[.card].to // null) | .gaveWayFixing = ($away[.card].fixing == true)
      | if $v != null and .result == "" and (.x.log | last | .step == "start" and .of == $v.step) then .live = ($v | {step, at, turns, last, usage, files, tests, list, action, waits, before} + (if $v.zero == true then {zero: true} else {} end) +(if $v.model then {model: $v.model} else {} end) + (if ($v.stalled | type) == "string" then {stalled: $v.stalled} else {} end)) else . end
      | if ($p | type) == "object" and .result == "" and (.x.log | last | .step != "start") then .proof = ($p | {at, files, tests, list, action}) else . end)
    + ($old[0] | map(.x.retried = true)) | map(.models = $m))[]' "$d/rows" > "$d/all" || exit 1
  # The pack's model prices, added models and aliases (prices) win over the built-in table; a pack that does not read
  # has none. The models the steps of the last 30 days ran are counted from since (seen).
  packget prices pp 2>/dev/null && [ -n "$pp" ] || pp='{}'
  packget auto.standing sk 2>/dev/null && [ -n "$sk" ] || sk=null
  packget push.check pc 2>/dev/null && [[ $pc =~ ^(true|false)$ ]] || pc=null
  packget lanes.research.model rmodel 2>/dev/null || rmodel=''
  # The research lane's sessions are no card's step: seen counts the models they ran from their transcripts in the
  # default login's projects folder (researchwt(), lib/control.sh); none, and none is read.
  rwt=$(researchwt)
  # The cards priced are kept beside the card records ($STATE.priced, dashboard_limit.py cardlines): a card whose line
  # is as it was at the last snapshot is not priced again. One priced card a line ($d/priced).
  jq -cn --argjson p "$pp" --arg rw "$rwt" --arg pj "$HOME/.claude/projects" '{prices: $p, since: ((($ENV.CONVEYOR_NOW // "" | tonumber?) // now) - 30 * 86400 | todate)}
      | if $rw == "" then . else .research = {worktree: $rw, projects: $pj} end' \
    | python3 "$HERE/../.claude/scripts/dashboard_limit.py" cardlines "$d/all" "$STATE.priced" "$d/priced" > "$d/pricedall" 2>/dev/null && pricedok=true \
    || { pricedok=false; jq -c '.usd = null | .steps |= map(.usd = null) | if .live then .live.usd = null else . end' "$d/all" > "$d/priced"; } || exit 1
  # prices: the Rules tab's Model prices, the built-in rows, the pack's entries, each model's display name and the
  # model IDs seen in 30 days, and the research lane's model for its mark; null when the table cannot be run.
  { $pricedok && jq -c --argjson o "$pp" --arg rm "$rmodel" '{builtIn: (.table | to_entries | map({model: .key, input: .value[0], output: .value[1], cacheRead: .value[2],
      cacheWrite: (.value[3] // (.value[0] * 1.25))})), overrides: $o, names, seen, research: (if $rm == "" then null else $rm end)}' "$d/pricedall"; } > "$d/prices" 2>/dev/null \
    && [ -s "$d/prices" ] || echo null > "$d/prices"
  echo null > "$d/issues"; echo null > "$d/upall"
  # What health reads of the records (HEALTHLINE), from its kept summary (health brought it up to date): the pick
  # order and the slow-test list below both read it.
  linesum "$READ" "$STATE.health" "$d/hrec" "$HEALTHLINE" && hrec=1 || hrec=''
  if [ -n "$issues" ]; then
    printf '%s\n' "$issues" > "$d/issues"
    # The order from what health reads of the records and the retried lines, each from its kept summary (UPREC, UPOLD).
    [ -n "$hrec" ] && linesum "$READ_OLD" "$RETRIED.health" "$d/hold" "$HEALTHLINE" \
      && UPREC=$d/hrec UPOLD=$d/hold upnext "$issues" '' all > "$d/upall" 2>/dev/null && [ -s "$d/upall" ] || echo null > "$d/upall"
    queue=$(jq -c --arg area "$AREA" 'map({issue: .number, title: (.title // "")[0:200], priority: .p, followup: (.later | not), retried: .again, created: .createdAt,
          areas: ([.labels[].name | select(startswith($area))] | sort), hold, rule, waits, before, forced})
        | {order: map(select((.hold | not) and .rule == null and (.waits == [] or .forced) and (.before | not)) | (if .forced then .waitsFor = .waits else del(.forced) end) | del(.hold, .rule, .waits, .before)),
           holding: map(select(.hold) | .waitsFor = .waits | del(.hold, .rule, .waits, .areas, .before, .forced)),
           skipped: map(select(.rule != null) | {issue, title, rule}),
           waiting: map(select(.waits != [] and (.hold | not) and .rule == null and (.before | not)) | del(.hold, .rule, .areas, .before) | .waitsFor = .waits | del(.waits))}' "$d/upall") && [ -n "$queue" ] && [ "$queue" != null ] || queue=null
    # The pick order is that whole list less what a pick leaves out (upnext.jq), not a second reading of the records.
    next=$(jq -c 'map(select((.hold | not) and .rule == null and (.waits == [] or .forced) and (.before | not))) | .[:10] | map({issue: .number, title: (.title // "")[0:200], priority: .p, followup: (.later | not), retried: .again} + (if .forced then {forced: true, waitsFor: .waits} else {} end))' "$d/upall") \
      && built=$(jq -c --arg built "$BUILT" 'map(select(.labels | any(.name == $built)) | {issue: .number, title: (.title // "")[0:200]}) | sort_by(.issue)' <<<"$issues") \
      && [ -n "$next" ] && [ -n "$built" ] || { next=null; built=null; }
    [ "$built" = null ] || [ "$built" = '[]' ] || built=$(jq -c --argjson s "$(labelled)" 'map(. + {since: ($s[.issue | tostring] // null)})' <<<"$built")
  fi
  cr=$(checkrun "$d")
  # The machine's test-slot pool (lib/slots.sh): how many of its slots a test run holds now, of how many.
  ts=$([ -n "$SLOTSREAD" ] && printf '{"used":%d,"of":%d}' "$(slot_used)" "$SLOT_N" 2>/dev/null) && [ -n "$ts" ] || ts=null
  # The readings of the account the next card will use.
  stdb ask -o "$d/limit" limit "$ACCT" 2>/dev/null || : > "$d/limit"
  # The reading of each account the guard reads for the record, as the guard acts on it (guardaccts).
  ga=$(guardaccts "$control") && [ -n "$ga" ] || ga=null
  # The samples and the pushes are the state database's (snapcopy).
  # The whole list of files each card waiting for the owner's yes changed, read from its kept patch: its blocked
  # line holds only the first 200. A card whose patch cannot be read has its line's list.
  while IFS=$'\t' read -r c k; do
    [ -r "$k/$c.patch" ] || continue
    git apply --numstat -z "$k/$c.patch" 2>/dev/null | jq -Rcs --arg c "$c" '{($c): (split("\u0000") | map(select(. != "") | split("\t") | .[2:] | join("\t") | .[0:300])) | select(length > 0)}' 2>/dev/null
  done < "$d/yes" | jq -cs 'add // {}' > "$d/paths" 2>/dev/null || echo '{}' > "$d/paths"
  # The project's own screenshots each such card kept (keepshots(), lib/push.sh), and the hash of its kept patch now:
  # the Board shows them only while the two hashes are one.
  while IFS=$'\t' read -r c k; do
    [ -r "$k/shots/shots.json" ] || continue
    jq -c --arg c "$c" --arg p "$(git hash-object -- "$k/$c.patch" 2>/dev/null)" \
      'objects | {($c): {patch: (if $p == "" then null else $p end), shots: {patch, shots}}}' "$k/shots/shots.json" 2>/dev/null
  done < "$d/yes" | jq -cs 'add // {}' > "$d/shots" 2>/dev/null || echo '{}' > "$d/shots"
  # Today and the 7 days are reckoned from the health record's time (CONVEYOR_NOW when set), as now is.
  # Each of the three days with its midnight's epoch (t0d, t0w, t0p), from one date program: day by bash's own printf.
  ht=$(jq -r '.time | fromdate' <<<"$h") && [[ $ht =~ ^[0-9]+$ ]] && printf -v day '%(%F)T' "$ht" \
    && { read -r day t0d && read -r since t0w && read -r prev t0p; } < <(printf '%s\n' "$day" "$day 6 days ago" "$day 13 days ago" | p_dates '+%F %s') \
    && [[ $t0p =~ ^[0-9]+$ ]] || exit 1
  # A failure stands only while the pack still names a whole test (maintest() runs none without one, so nothing clears
  # it) and, when the open issues were listed, while the issue it filed is open.
  packget test.main mt && [ -n "$mt" ] && mt=$(jq -ce --slurpfile iss "$d/issues" \
    '.fail | objects | select(.issue == null or $iss[0] == null or (.issue as $n | $iss[0] | any(.number == $n)))' "$MAINTEST" 2>/dev/null) || mt=null
  # The commit of the plugin's main (or newest release) this machine did not take, while the pack follows it (take(), lib/install.sh).
  packget plugin.follow eng && [ -n "$eng" ] && eng=$(jq -ce '.refused | objects | {commit, reason, since}' "$ENGINE" 2>/dev/null) || eng=null
  # The test owners, read once: testspart, below, reads these too.
  local defs refs
  testowners
  fl=$(jq -ce --slurpfile h "$d/health" --argjson days "$FLAKY_DAYS" --slurpfile defs <(printf '%s' "$defs") --slurpfile refs <(printf '%s' "$refs") '$h[0] as $h | '"$OWNERS"'($h.time | fromdate) as $t | [.filed | arrays | .[] | objects] as $f
    | [.entries | arrays | .[] | objects | select((.case | type) == "string" and ((.time | fromdate?) // 0) > $t - $days * 86400)] | group_by(.case)
    | map(.[0].case as $c | {case: $c, count: length, issue: ([$f[] | select(.case == $c) | .issue][-1] // null), files: ($c | caseowners)}) | sort_by(-.count, .case)' "$FLAKY" 2>/dev/null) || fl='[]'
  # The slow-test list, from what health reads of the snapshot's copy of the card records (hrec, above).
  so=$([ -n "$hrec" ] && slowoffs "$d/hrec" | jq -cs 'sort_by(.file)') || so='[]'
  # The last pass of the test rules, when its burst guard stopped it (testrulespass()).
  tr=$(jq -ce 'select(.on == true) | .time as $t | .burst | objects | {time: $t, matched, cap}' "$TESTRULES" 2>/dev/null) || tr=null
  # The full test suite (fulltest()): the run in progress, only while its lock is held (a run that was killed left its
  # file), and the last line of its record.
  packget test.full ft 2>/dev/null || ft=''
  fr=null; ( flock -n 9 ) 9>>"$FULLTEST.lock" 2>/dev/null || fr=$(jq -ce 'objects' "$FULLTEST.running" 2>/dev/null) || fr=null
  ft=$({ tail -n 1 "$FULLTEST" 2>/dev/null || :; } | jq -cs --arg ft "$ft" --slurpfile r <(printf '%s' "$fr") '$r[0] as $r | {command: ($ft != ""),
      why: (if $ft == "" then "the pack names no full test suite (test.full)" else null end), running: $r, last: (map(objects) | last)}' 2>/dev/null) || ft=null
  # The whole-suite runs and main as the Release panel shows it (suites(), releasemain()).
  su=$(suites) || su='[]'; rl=$(releasemain) || rl=null; dr=$(driftof "$d")
  packget foreman.waitWake ww 2>/dev/null && [[ $ww =~ ^[1-9][0-9]*$ ]] || ww=10
  packget push.landAs pla 2>/dev/null || pla=''
  packget push.prMerge ppm 2>/dev/null || ppm=''
  # Each card with its metrics and its runs' sums, then the waits ($d/cards: two arrays, $all[0] and $all[1]), from a
  # summary kept beside the card records ($STATE.cardruns): only the issues whose cards changed are made again.
  printf '%s\n%s\n' "$METRICS" "$CARDRUNS" > "$d/cardruns.jq" \
    && python3 "$HERE/cardruns.py" "$d/priced" "$STATE.cardruns" "$d/cards" "$d/cardruns.jq" "$d/samples" "$(jq -r '.time | fromdate' "$d/health")" "$SAMPLE" "$yes" \
    || exit 1
  jq -cn --slurpfile all "$d/cards" --slurpfile hs "$d/health" --slurpfile allp "$d/paths" --slurpfile shots "$d/shots" --argjson mt "$mt" --slurpfile fl <(printf '%s' "$fl") --slurpfile so <(printf '%s' "$so") --slurpfile ft <(printf '%s' "$ft") --slurpfile su <(printf '%s' "$su") --argjson rl "$rl" --argjson dr "$dr" --argjson eng "$eng" --argjson tr "$tr" --argjson m "$models" --argjson next "$next" --slurpfile built <(printf '%s' "$built") \
    --slurpfile iss "$d/issues" --slurpfile ua "$d/upall" --arg builtl "$BUILT" --arg fu "$FOLLOWUP" --argjson prio "$PRIOS" --arg area "$AREA" --argjson ww "$ww" --arg pla "$pla" --arg ppm "$ppm" \
    --argjson control "$control" --argjson settings "$settings" --argjson accts "$(acctnames)" --argjson ga "$ga" --slurpfile q <(printf '%s' "$queue") --slurpfile lim "$d/limit" --slurpfile smp "$d/samples" --slurpfile pu "$d/pushes" --argjson every "$SAMPLE" --argjson priced "$pricedok" --argjson cr "$cr" --argjson ts "$ts" \
    --argjson max "$MAX_REVIEWS" --argjson wait "$((CLOSE_WAIT + 300))" --arg yes "$yes" --arg day "$day" --arg since "$since" --arg prev "$prev" \
    --argjson t0d "$t0d" --argjson t0w "$t0w" --argjson t0p "$t0p" '$fl[0] as $fl | $so[0] as $so | $ft[0] as $ft | $su[0] as $su | $built[0] as $built | $q[0] as $q | '"$DEPS$LEVEL$INSIDE"'
    def day: fromdate | strflocaltime("%Y-%m-%d");
    def usd: if length == 0 then 0 elif any(.usd == null) then null else map(.usd) | add * 10000 | round / 10000 end;
    # The totals: the dollars of the steps that are priced, and how many are left out for having no price.
    def priced: [.[].usd | numbers] | add // 0 | . * 10000 | round / 10000;
    def leftout: map(select(.usd == null)) | length;
    def sofar: . as $card | (.live // {} | .usage // null) as $u
      | ((.steps | any(.step != "test")) or (($u // {} | [.[]] | add // 0) > 0)) as $reading
      # atEnd: no reading yet, and every answer of the running Claude session reports usage 0 (its route streams no
      # usage, #391): its cost is shown when the step ends, not "no reading yet".
      | {reading: $reading, atEnd: (($reading | not) and $card.live.zero == true),
         tokens: (.x.tokens | if $u == null then . elif $card.live.step == "review" and ($card.live.model // "" | startswith("claude-") | not) then .codex +=$u.input + $u.output
           else .claude += $u.input + ($u.write // 0) + ($u.write1h // 0) + $u.output end),
         usd: (if ($reading | not) or .usd == null or ($u != null and .live.usd == null) then null else (.usd + (.live.usd // 0)) * 10000 | round / 10000 end)};
    '"$TRACK"'
    '"$METRICS"'
    $hs[0] as $h
    # Every stretch waiting on the owner, and each card with its metrics and the sums of its runs: CARDRUNS says what
    # they hold. Here the runs of the issue of each card, to it ($runsOf, as CARDRUNS finds them), name the earlier
    # runs that the times of a card count; $later: the cards a later run of their issue follows (the cost rows show
    # that run, with their dollars in it).
    | $all[1] as $waits | ($h.time | fromdate) as $nowt
    | ($all[0] | map(select(.issue != 0)) | group_by(.issue)
        | map(sort_by(.startedAt, .card) | reduce .[] as $k ({run: [], out: []}; .run += [$k] | .out += [{key: $k.card, value: .run}]
            | if ($k.step | IN("landed", "closed")) and $k.x.blockedAt == null then .run = [] else . end) | .out[])
        | from_entries) as $runsOf
    | ([$runsOf[] | .[:-1][] | .card] | unique) as $later
    | ($h.unpushed | map(.sha)) as $un
    # A card that has landed is not done: its commit is pushed, then GitHub closes its issue. Until both are, it stays
    # on the belt (x.after: push, pushfail when a push that carried it failed, pushheld when it failed its check and
    # waits for main to move, issue, or issuefail when GitHub kept the
    # issue open), so a slow or failed push is
    # a step in progress or failed there. With the rule "Push when a card lands" off (rules.push false), nothing pushes
    # it until the owner presses Push landed: x.after is wait, and it is off the belt, listed only as landed and not
    # pushed, a failed Push landed too (needs-you and the Control tab say that the push failed). x.shut: the issue is known closed (the open issues were listed and it is not
    # among them), however it was closed: by GitHub, or by hand after GitHub did not.
    | (($control // {}) | .rules.push? == false) as $pushOff
    | ($all[0] | map(select(.x.retried | not)) | map(.x.shut = (.issue != 0 and $iss[0] != null and (.issue as $n | $iss[0] | any(.number == $n) | not)))
      | map(.x.after = (
        if .step != "landed" then null
        elif .sha | IN($un[]) then (if $pushOff then "wait" elif $h.pushError != null and $h.pushError.time >= .x.endAt then (if $h.pushError.kind == "check" then "pushheld" else "pushfail" end) else "push" end)
        else (.x.log | map(select(.step == "pushed")) | last) as $p | (.x.log | map(select(.step == "issue")) | last) as $il
          # A push into the pull request of Land as pr (its pushed line names it: pr) waits for no issue: the issue
          # closes when the owner merges the pull request, so the push is done, not failed.
          | if .issue == 0 or $p == null or $p.pr != null or .x.shut then null
            # No issue line yet: GitHub is waited for $wait; an issue line that never comes (the loop died) then
            # leaves Push failed while the issue is still open (or the open issues could not be listed).
            elif $il == null then (if ($h.time | fromdate) - ($p.time | fromdate) < $wait then "issue" else "issuefail" end)
            # GitHub did not close the issue (an issue line that failed): the card stays on Push, failed, while the
            # issue is still open (or the open issues could not be listed), so it is not lost from the belt.
            elif $il.result != "ok" then "issuefail"
            else null end
        end))) as $c
    # No time is estimated from past cards (each card builds something else). A card shows what was measured:
    # start, the first pick-up of its work (a card resumed from a kept patch counts the cards whose work it
    # resumes: start is the first of them, priorSec their seconds from pick-up to end), and totalSec, pick-up to the
    # end (a card on the belt adds the time since its own pick-up). The time it sat queued is not counted.
    # earlier: those earlier cards, the first first, each {card, start, end, sec (the seconds priorSec counts of it),
    # reason (why it ended, cut to 300 characters), track}, so the step view shows the steps priorSec counts.
    | ($all[0] | map({key: .card, value: {s: .startedAt, e: .x.endAt, from: .x.from}}) | from_entries) as $byCard
    | ([$all[0][] | .x.from | strings]) as $froms
    | ($all[0] | map(select(.card | IN($froms[])) | {key: .card, value: .}) | from_entries) as $rowOf
    | def secOf($p): if $p.e == null then 0 else ([($p.e | fromdate) - ($p.s | fromdate), 0] | max) end;
      def chain($f; $k): if $f == null or $k > 20 or $byCard[$f] == null then {sec: 0, start: null, earlier: []}
        else $byCard[$f] as $p | chain($p.from; $k + 1) as $r
          | {sec: ($r.sec + secOf($p)), start: ($r.start // $p.s),
             earlier: ($r.earlier + [$rowOf[$f] | {card, start: .startedAt, end: .x.endAt, sec: secOf($p), reason: ((.reason // "")[0:300]), track: track($max; null)}])} end;
      # The earlier runs of a restarted card ($runsOf) are earlier cards too, each once: its overall time and "Every step" hold them.
      def times: . as $c | chain(.x.from; 0) as $r | ($r.earlier | map(.card)) as $seen
        | [($runsOf[.card] // [])[:-1][] | select(.card | IN($seen[]) | not)] as $more
        | ($r.sec + ([$more[] | secOf({s: .startedAt, e: .x.endAt})] | add // 0)) as $prior
        | {start: ([$r.start, $more[].startedAt, $c.startedAt] | map(strings) | min), pickedAt: .startedAt, priorSec: $prior,
           earlier: ($r.earlier + [$more[] | {card, start: .startedAt, end: .x.endAt, sec: secOf({s: .startedAt, e: .x.endAt}), reason: ((.reason // "")[0:300]), track: track($max; null)}]
             | sort_by(.start)),
           totalSec: (if .x.endAt == null then null else $prior + ([(.x.endAt | fromdate) - (.startedAt | fromdate), 0] | max) end)};
    # A follow-up names the card it came from: the issue whose landed line lists it (/units shows "↳ #N").
    ([$all[0][] | select(.x.followups != null) | .issue as $p | .x.followups[] | {key: tostring, value: $p}] | from_entries) as $parents
    | def parent: $parents[.issue | tostring] // null;
    # A part names its parent (the issue it is a GitHub sub-issue of: umbrella, openissues()); an issue that is no part,
    # or all of them when the issues were not listed, has no umbrella field.
      ([$iss[0] // [] | .[] | select(.umbrella != null) | {key: (.number | tostring), value: .umbrella}] | from_entries) as $ums
    | def umbrella: $ums[.issue | tostring] | if . == null then {} else {umbrella: .} end;
      ($h.pushError.reason // null) as $perr
    | [$all[0][] | .steps[] | select((.time | day) >= $since)] as $steps
    # A card whose issue was closed while it was blocked (x.blockedAt) landed nothing: it is not among the landed.
    | [$c[] | select((.step | IN("landed", "closed")) and .x.blockedAt == null and (.x.endAt | day) >= $since)] as $week
    # The forecast: the cards in the queue, and the dollars they would take at the median of the cards that
    # landed (null with none priced); no time (a time from past cards is always wrong). pausesAt is the queued issue the
    # guard would pause at: the first one when the reading is at the guard already; else, at the percent of the
    # weekly limit a card has taken (the rise of the readings since the limit last reset, over the cards that ended
    # in that time), the one that would be picked once the reading has reached the guard. null when no guard is set,
    # there is no reading, nothing to measure a card by, or the queue ends first.
    | def median: sort | if length == 0 then null else (.[(length - 1) / 2 | floor] + .[length / 2 | floor]) / 2 end;
      def forecast: ($q.order // null) as $o
        | [$all[0][] | select(.step == "landed" and .usd != null) | .usd] as $usd
        | ($usd | median) as $pu
        | ($lim | map(select((.time | fromdate) >= ($h.time | fromdate) - 7 * 86400))
            | reduce .[] as $r ([]; if length > 0 and $r.pct < last.pct then [$r] else . + [$r] end)) as $seg
        | (if ($seg | length) < 2 then null else ($seg[0].time) as $a | ($seg | last | .time) as $b
            | [$c[] | select(.x.endAt != null and .x.endAt >= $a and .x.endAt <= $b)] | length
            | if . == 0 or ($seg | last | .pct) <= $seg[0].pct then null else (($seg | last | .pct) - $seg[0].pct) / . end end) as $per
        | ($h.guard.at) as $g | ($h.guard.reading) as $p
        | {cards: ($o | if . == null then null else length end),
           usd: (if $o == null or $pu == null then null else $pu * ($o | length) * 100 | round / 100 end),
           perCard: {usd: $pu, pct: ($per | if . == null then null else . * 100 | round / 100 end)},
           guard: $g, reading: $p,
           pausesAt: (if $o == null or $g == null or $p == null then null
             else (if $p >= $g then 0 elif $per == null then null else (($g - $p) / $per | ceil) end) as $k
               | if $k == null or $k >= ($o | length) then null else $o[$k].issue end end)};
    # Every open issue ("Move them to Held"): open counts them, and split says where each is:
    # queued (in pick order), held by you (the control record, and nothing else holds it), held by label or rule (or
    # by anything else that keeps it from the pick order: an issue it waits on, a card of it, a parent), or on the
    # belt; the four add up to open. issues lists every open issue, lowest number first (issue, title, priority,
    # labels, created, dependsOn: the numbers its own `Depends on:` lines name (needs, DEPS), the ones `control depends
    # remove` can take off, then the "owner/repo#N" of another repository they name (farneeds), unlike waitsFor, which adds follow-ups and leaves closed ones out), so the Rules tab can
    # list them all with their state. held lists every open issue that is
    # neither queued nor on the belt, each with why (reasons, one or more): you (the control record holds it; with
    # outside: true when someone outside the project opened it, INSIDE, so it waits for a release by the owner), label
    # (the built label, awaiting-deploy, holds it back; label names it), rule (a rule of the
    # control record excludes it; rule names it), waits (an open issue it depends on; waitsFor), card (a card of it
    # is blocked, or landed with the issue still open; step) or parent (a follow-up filed before its parent card
    # landed) or approve (it waits for the yes of the owner before its
# build, in "Needs you"). null when gh cannot list the issues.
    ($iss[0]) as $open | ($ua[0]) as $up
    | ([$c[] | select(.result == "" or .x.after != null) | .issue]) as $onbelt
    | ($q.order // [] | map(.issue)) as $queued
    # The column of each open issue (on the belt, queued, else held), for moved.json (movedsaw); null when the issues
    # were not listed.
    | (if $open == null or $up == null or $q == null then null else
        [$open[] | (.labels | map(.name)) as $l | {key: (.number | tostring), value: {col: (if .number | IN($onbelt[]) then "belt" elif .number | IN($queued[]) then "queue" else "held" end),
          by: {labels: $l, fu: ($l | index($fu) != null), p: level($l; $prio)}}}]
        | from_entries end) as $cols
    | (if $open == null or $up == null or $q == null then null else
        ($control // {} | .held // []) as $mine
        | ($up | map({key: (.number | tostring), value: .}) | from_entries) as $u
        | [$open[] | select((.number | IN($onbelt[])) | not) | . as $i | ($i.labels | map(.name)) as $l | $u[$i.number | tostring] as $e
            | ($l | index($fu) != null) as $isfu
            | ([(if $i.number | IN($mine[]) then {kind: "you"} + (if ($i.authorAssociation | type == "string") and ($i | inside | not) then {outside: true} else {} end) else empty end),
                ($l[] | select(. == $builtl) | {kind: "label", label: .}),
                (if $e.rule != null then {kind: "rule", rule: $e.rule} else empty end),
                (if ($e.waits // []) != [] then {kind: "waits", waitsFor: $e.waits} else empty end),
                (if $e.before then {kind: "approve"} else empty end),
                ([$c[] | select(.issue == $i.number and .result != "")] | last | if . == null then empty else {kind: "card", step: .step, card: .card} end)]) as $why
            | (if $why == [] and $e == null and $isfu then [{kind: "parent"}] elif $why == [] and $e == null then [{kind: "other"}] else $why end) as $why
            | select(($i.number | IN($queued[])) | not)
            | {issue: $i.number, title: ($i.title // "")[0:200], priority: level($l; $prio), followup: $isfu,
               labels: $l, created: $i.createdAt, parent: (($i.body // "") | capture("^Follow-up to #(?<n>[0-9]+)") | .n | tonumber) // null, reasons: $why,
               # The slices of a split issue (the rule Split large issues On), else the parts of a parent (its GitHub
               # sub-issues in this repository): it is their umbrella while it is open.
               umbrella: (([$c[] | select(.issue == $i.number and (.x.split.filed | type) == "array")] | last | .x.split.filed)
                 // ([($i.parts // [])[].number | numbers] | if . == [] then null else . end))}] as $hl
        | ($hl | map(select((.reasons | map(.kind) | unique) == ["you"])) | length) as $you
        | {count: ($open | length), held: $hl,
           # Each open parent (an issue with GitHub sub-issues) as one entry: its parts, how many of them are done
           # (closed) of all, those on the belt, and the closed ones (the Board shows them as landed).
           umbrellas: [$open[] | select((.parts // []) != []) | {issue: .number, title: (.title // "")[0:200], parts: [.parts[].ref],
             done: ([.parts[] | select(.open | not)] | length), all: (.parts | length), inFlight: [.parts[].number | numbers | select(IN($onbelt[]))],
             closed: [.parts[] | select(.open | not) | .ref]}],
           issues: ([$open[] | (.labels | map(.name)) as $l | {issue: .number, title: (.title // "")[0:200], priority: level($l; $prio), labels: $l, created: .createdAt, dependsOn: (needs + farneeds)}] | sort_by(.issue)),
           split: {queued: (($open | length) - ($hl | length) - ([$open[] | select(.number | IN($onbelt[]))] | length)), you: $you,
                   labelOrRule: (($hl | length) - $you), belt: ([$open[] | select(.number | IN($onbelt[]))] | length)}} end) as $openpart
    # Why an open issue that others wait on does not move (waitsOn in queue.waiting): its newest card first, then
    # a hold of the control record, a label, a rule, the yes of the owner, its own wait, the pick order; else no card.
    | def depstate($n): ([$c[] | select(.issue == $n)] | last) as $k
        | ($up // [] | map(select(.number == $n)) | .[0]) as $e
        | if $k != null and $k.result == "" then "building"
          elif $n | IN(($control // {} | .held // [])[]) then "held"
          elif $k != null and $k.step == "blocked" then (if $k.reason // "" | startswith($yes) then "waiting for a yes" else "blocked" end)
          elif $open // [] | any(.[]; .number == $n and any(.labels[]; .name == $builtl)) then "held"
          elif $e.rule != null then "skipped by a rule"
          elif $e.before then "waiting for a yes"
          elif ($e.waits // []) != [] and ($e.forced | not) then "waiting for \($e.waits | map(if type == "number" then "#\(.)" else . end) | join(", "))"
          elif $n | IN(($q.order // [] | map(.issue))[]) then "queued"
          else "open, no card" end;
    {time: $h.time, day: $day, repo: $h.repo,
       needsYou: {
         waiting: [$c[] | select(.step == "blocked" and (.reason | startswith($yes)))
           | {card, issue, title, sentence: ((.x.visible | select(startswith("yes: ")) | .[5:]) // (.reason | ltrimstr($yes))), since: .x.endAt, parent: parent, reviews: reviews, track: track($max; $perr), metrics, doneWhen: .x.doneWhen, split: .x.split, stalls: .x.stalls,
              files: (($allp[0][.card] // .x.paths) as $p | {count: (.x.diff.files // ($p | if . == null then null else length end)), paths: $p})}
             # The screenshots it kept, beside the hash of its kept patch now (the Board shows them while the two are one).
             + ($shots[0][.card] // {patch: null, shots: null})
             # A follow-up whose change goes beyond the yes up its chain: what goes beyond, as its reviewer said (the ask).
             + ((.reason | capture("\\(it goes beyond the yes of #(?<from>[0-9]+): (?<what>.*)\\)") | {beyond: {from: (.from | tonumber), what}}) // {})
             + times],
         blocked: [$c[] | select(.step == "blocked" and (.reason | startswith($yes) | not)) | {card, issue, title, reason, tail, since: .x.endAt, parent: parent, reviews: reviews, track: track($max; $perr), metrics, doneWhen: .x.doneWhen, split: .x.split, stalls: .x.stalls} + umbrella + times]
           # A push that failed again on its next try needs the owner, until a push works: one item, under the card
           # of the last landing not pushed, naming every card not pushed; its tail is what git and the hook said.
           # One that failed its check needs the owner at once: it is not tried again until main moves (checkheld()).
           + [($h.pushError.kind == "check") as $chk | select($h.pushFails >= 2 or $chk) | $h.unpushed as $u | $c[] | select(.card == $u[-1].card)
              | {card, issue, title, reason: ((if $chk then "push blocked: \($h.pushError.check) failed after \($h.pushError | if .issue == 0 then .card else "#\(.issue)" end). A retry will fail too, so the push waits until a fix lands on main"
                   else "the push of main keeps failing" end) + ". Not pushed: \($u | map(if .issue == 0 then .card else "#\(.issue)" end) | join(", "))"), tail: $h.pushError.reason,
                 since: $h.pushFailingSince, push: true, check: (if $chk then $h.pushError.check else null end), unpushed: ($u | map({card, issue})), parent: parent, reviews: reviews, track: track($max; $perr), metrics, doneWhen: .x.doneWhen, split: .x.split} + times],
         before: $h.before,
         engine: $eng,
         testRules: $tr,
         pipeline: (if $open == null then null else ($control // {} | .held // []) as $mine
           | [$open[] | select((.number | IN($mine[])) and (.body // "" | test("^Follow-up to #[0-9]+ \\(Conveyor card ")))
              | (.body | capture("(^|\n)Cost to every card: (?<c>[^\n]*)").c) as $cost
              | {issue: .number, title: (.title // "")[0:200], cost: $cost, parent: (.body | capture("^Follow-up to #(?<n>[0-9]+)").n | tonumber), since: .createdAt}]
           | sort_by(.issue) end),
         farDeps: (if $open == null then null else
           [$open[] | . as $i | farneeds[] as $r | select($i.far[$r].error != null)
              | {issue: $i.number, title: ($i.title // "")[0:200], ref: $r, reason: $i.far[$r].error,
                 line: ([$i.body // "" | splits("\r?\n") | select({body: .} | farneeds | index([$r]) != null)] | first // "" | sub("^\\s+"; "") | .[0:300])}]
           | sort_by(.issue) end)},
       mainTest: $mt,
       fullTest: $ft,
       suites: $su,
       release: $rl,
       drift: $dr,
       flaky: $fl,
       slowOff: $so,
       belt: [($c[] | select(.result == "")), ($c[] | select(.x.after != null and .x.after != "wait")) | sofar as $s | (.x.after != null) as $landed
         # The live record of a running step names it and when it began (#320): a fix session after a GO or a failed
         # test run is Fix from its own start, though the last step line of the card is still that review or test run.
         | (if $landed then (if .x.after | IN("issue", "issuefail") then "issue" else "push" end) elif .live.waits.on then "waiting" elif .proof then "proof"
            else {build: "build", review: "review", fix: "fix", test: "tests", rebase: "landing", land: "landing"}[.live.step // ""] // .x.at end) as $step
         | ((.live.at | strings) // .stepAt) as $stepAt
         # A card waiting on a same-file card: that card, its issue, and where it is (its step on the belt, blocked,
         # landed, closed, queued: `retry` gave its issue back, or gone: in no record).
         | (.live.waits.on // null | if . == null then null else . as $w | ([$all[0][] | select(.card == $w)] | last) as $r
             | {card: $w, issue: ($r.issue // ($w | capture("-(?<n>[0-9]+)$").n | tonumber? ) // null),
                state: (if $r == null then "gone" elif $r.x.retried then "queued" elif $r.result == "" then $r.x.at else $r.step end)} end) as $won
         | {card, issue, title, step: $step, waitsOn: $won, gaveWay: (if $landed then null else .gaveWay end), gaveWayFixing: (.gaveWayFixing and ($landed | not)), review: (if $step == "review" then .x.review // (.reviews + 1) else null end), of: $max, stepAt: $stepAt, landed: $landed,
         model: (.live.model // {build: $m.claude, fix: $m.claude, review: $m.codex}[$step] // null), tokens: $s.tokens, usd: $s.usd, reading: $s.reading, atEnd: $s.atEnd,
         # A proof run gives what it does now, "waiting for a test slot (2 of 2 in use)" while the slots are full (testrun.sh).
         live: (if .live then {turns: .live.turns, lastOutputAt: .live.last, action: (.live.action // null), at: (.live.at // null)}
           elif .proof then {turns: 0, lastOutputAt: null, action: (.proof.action // null), at: (.proof.at // null)} else null end),
         done: {tokens: .x.tokens, usd, reading: (.steps | any(.step != "test")), step: (.x.log | last | if .step == "start" then .of else null end)},
         # The step that runs now after a stall (stalled, in the live record) has no line yet: its stall is counted here.
         parent: parent, reviews: reviews, track: track($max; $perr), metrics, doneWhen: .x.doneWhen, split: .x.split, stalls: (.x.stalls + (if .live.stalled then 1 else 0 end)),
         beyond: (if $landed then null else .x.beyond end)} + umbrella + times],
       queue: {next: ($next | if . == null then null else map(. + {parent: parent} + umbrella + (if $h.room.issue == .issue then {room: $h.room.reason} else {} end)) end), order: ($q.order | if type == "array" then map(. + umbrella + (if $h.room.issue == .issue then {room: $h.room.reason} else {} end)) else null end),
         holding: ($q.holding // null | if . == null then null else map(. + umbrella) end), skipped: ($q.skipped // null | if . == null then null else map(. + umbrella) end),
         waiting: ($q.waiting // null | if . == null then null else map(. + {waitsOn: [.waitsFor[] | numbers | {issue: ., state: depstate(.)}]} + umbrella) end)},
       open: $openpart,
       control: $control,
       modelSettings: $settings,
       accounts: $accts,
       limits: $ga,
       inFlight: ([$c[] | select(.result == "" and .x.accounts != null) | .x.accounts] | unique),
       areaPrefix: $area,
       packLandAs: (if $pla == "" then null else $pla end),
       packPrMerge: (if $ppm == "" then null else $ppm end),
       waitWake: $ww,
       forecast: forecast,
       awaitingDeploy: $built,
       landed: [$week | sort_by(.x.endAt) | reverse[] | select((.x.endAt | day) == $day) | {card, issue, title, step, time: .x.endAt, usd, reviews: .runReviews, followups: .x.followups,
         parent: parent, rounds: reviews, fixes: .runFixes, track: track($max; $perr), sha, pushed: (if .step == "closed" then null else (.sha | IN($un[]) | not) end), metrics, doneWhen: .x.doneWhen, split: .x.split, stalls: .x.stalls, batch: .x.batch, rollout: .x.rollout} + times],
       branches: ([$c[] | select(.x.branch != null and (.step | IN("landed", "closed")) and .x.blockedAt == null)] | group_by([.issue, .title])
         | map(max_by(.x.endAt) | {card, issue, title, step, time: .x.endAt})),
       pushedCards: [$c[] | (.x.log | map(select(.step == "pushed")) | last) as $p | select($p != null and ($p.time | day) >= $since)
         | {card, issue, time: $p.time, day: ($p.time | day)}],
       health: $h,
       testSlots: $ts,
       cost: (($steps | map(select((.time | day) == $day))) as $td | [$week[] | .card] as $wk
         | [$all[0][] | select(.card | IN($wk[])) | .runSteps[]] as $ws | {
         today: (if $priced then $td | priced else null end), todayLeftOut: ($td | leftout), week: (if $priced then $steps | priced else null end), weekLeftOut: ($steps | leftout),
         perLanded: ($week | if length == 0 or ($priced | not) then null else length as $n | $ws | priced / $n * 10000 | round / 10000 end), perLandedLeftOut: ($ws | leftout),
         landedAfter: ($week | {"1": (map(select(.reviews == 1)) | length), "2": (map(select(.reviews == 2)) | length),
           "3": (map(select(.reviews == 3)) | length), more: (map(select(.reviews > 3)) | length)}),
         unpricedSteps: ($steps | leftout),
         unpriced: [$all[0][] | . as $k | .steps[] | select((.time | day) >= $since and .usd == null)
           | {card: $k.card, issue: $k.issue, step, time, why: (.unpriced // "the price table could not be run")}],
         cards: ([$all[0][] | select(.card | IN($later[]) | not) | [.runSteps[] | select((.time | day) >= $since)] as $s | select($s | length > 0)
             | {card, issue, title, state: (if .x.retried then "retried" elif .result == "" then "on the belt" else .step end), runs: .metrics.runs,
                today: ($s | map(select((.time | day) == $day)) | usd), week: ($s | usd), last: ($s | map(.time) | max)}]
           | sort_by(.last) | reverse | map(del(.last))),
         # The cards the rule Pick settings picked (x.pick, rows.jq), by group and builder choice, on any day: one a
         # card that no later run of its issue follows, with the newest pick of its runs (an earlier run, blocked with
         # the rule off, counts with it): cards, landed (landed or closed, as totals() counts them), usd (every step of
         # their runs, blocked, stopped and retried ones too; null when one step has no price), firstTry (landed ones
         # with no earlier run), reviews (the review rounds of the runs of the landed ones) and open (on the belt, or
         # blocked, and not retried: a card that `control stop` or `retry` moved out is not open).
         picks: ([$all[0][] | select(.card | IN($later[]) | not) | (($runsOf[.card] // [.]) | map(.x.pick | objects) | last) as $p
             | select($p != null) | .pick = $p] | group_by(.pick | [.group, .choice.model, .choice.effort])
           | map(.[0].pick as $p | map(select((.step | IN("landed", "closed")) and .x.blockedAt == null)) as $l
             | {group: $p.group, model: $p.choice.model, effort: $p.choice.effort, cards: length, landed: ($l | length), usd: ([.[].runSteps[]] | usd),
                firstTry: ($l | map(select(.metrics.runs == 1)) | length), reviews: ($l | map(.runReviews) | add // 0),
                open: (map(select((.x.retried | not) and (.result == "" or .step == "blocked"))) | length)}))}),
       metrics: {
         today: totals([$all[0][] | select(.x.endAt != null and (.x.endAt | day) == $day)]; [$smp[] | select((.time | day) == $day)]; [$pu[] | select((.time | day) == $day)]; $every; $waits; $t0d; $nowt),
         week: totals([$all[0][] | select(.x.endAt != null and (.x.endAt | day) >= $since)]; [$smp[] | select((.time | day) >= $since)]; [$pu[] | select((.time | day) >= $since)]; $every; $waits; $t0w; $nowt),
         prev: totals([$all[0][] | select(.x.endAt != null and (.x.endAt | day) >= $prev and (.x.endAt | day) < $since)]; [$smp[] | select((.time | day) >= $prev and (.time | day) < $since)];
           [$pu[] | select((.time | day) >= $prev and (.time | day) < $since)]; $every; $waits; $t0p; $t0w),
         days: [range(6; -1; -1) as $k | ($t0d + 43200 - $k * 86400 | strflocaltime("%Y-%m-%d")) as $dd
           | totals([$all[0][] | select(.x.endAt != null and (.x.endAt | day) == $dd)]; []; []; $every; []; 0; 0)
           | {day: $dd, landed, blocked, cycleSec: .cycleSec.p50, firstReviewPass, perLandedUsd: (.perLanded | if . == null or .leftOut > 0 then null else .usd end)}],
         slots: ([$smp[] | select((.time | day) == $day) | . + {hour: (.time | fromdate | strflocaltime("%H") | tonumber)}] | group_by(.hour)
           | map({hour: .[0].hour, slots: ([.[].slots] | add / length | r3), cap: ([.[].cap | numbers] | max)})),
         cards: ([$all[0][] | select((.x.endAt // .stepAt | day) >= $since)
           | {card, issue, title, state: (if .x.retried then "retried" elif .result == "" then "on the belt" else .step end), at: (.x.endAt // .stepAt), metrics}]
           | sort_by(.at) | reverse)}, cols: $cols} + $cr
    # Every object naming a main-red fix card (card) carries its name (rows.jq), as in health: it has no issue.
    | ([$all[0][] | select(.name) | {key: .card, value: .name}] | from_entries) as $nm
    | walk(if type == "object" and (.card | type) == "string" and $nm[.card] then .name = $nm[.card] else . end)' > "$d/out" || exit 1
  # Each issue in Held or Queue gets since from moved.json as this snapshot leaves it; none when the issues were not
  # listed, and moved.json is then left as it was.
  cols=$(jq -c '.cols as $c | if $c == null then null else [.open.held[] | select(any(.reasons[]; .kind | IN("you", "rule") | not)) | .issue | tostring] as $o
    | $c | with_entries(.value += {other: (.key | IN($o[]))}) end' "$d/out") || exit 1
  [ "$cols" = null ] || moved=$(movedlocked movedsaw "$cols" "$saw") || moved=null
  # declined: the lines the Declined panel shows, newest first; declinedRest: the others (dismissed, built or older
  # than 7 days), which an old line's "Show every line" still reaches. A line the judge declined carries the review it
  # was declined in, from the card's records (a retried card's too): round (the card's review it was, as its reviews
  # count them) and findings, every finding of that review with the number the judge gave it (n, judged(); the judge's
  # record keeps every finding whole, where the review's text in the record is cut short), [{n, finding}] in that
  # order, so the panel can say what an F<n> of its reason means. Both are null when no review of the card's records
  # declined it, or one of that review's findings has no number (the numbering is then unknown).
  # The review and picked lines it reads come from summaries kept beside the records (JUDGEDLINE, linesum()).
  linesum "$READ" "$STATE.judged" "$d/jrec" "$JUDGEDLINE" && linesum "$READ_OLD" "$RETRIED.judged" "$d/jold" "$JUDGEDLINE" \
  && jq -cs --slurpfile rec "$d/jrec" --slurpfile old "$d/jold" '(($ENV.CONVEYOR_NOW // "" | tonumber?) // now) as $now
    | def one: gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "");
    # Each card whose judge declined a finding: its reviews, each with its round, judge and the declined findings in
    # one line each (seen), made once here: made again for each declined line, this part took five times as long.
    ([$old[], $rec[] | objects | select(.step == "review")] | group_by(.card)
      | map(select(any(.[]; (.judge.declined // []) | length > 0)) | {key: .[0].card, value: (to_entries | map(.seen = [.value.judge.declined[]? | .finding | strings | one]))}) | from_entries) as $rv
    # Each main-red fix card (issue 0) by its name, as rows.jq names it: its declined lines carry it (name), not #0.
    | ([$old[], $rec[] | objects | select(.step == "picked" and (.mainRed | type) == "string") | {key: .card, value: "Main is red (\(.mainRed[0:12]))"}]
      | from_entries) as $mr
    | def numbered: [((.judge.accepted | arrays) // []) + ((.judge.declined | arrays) // []) | .[] | {n: ((.n | numbers) // null), finding}]
        | if any(.[]; .n == null) then null else sort_by(.n) end;
    map(objects | (if (.card | type) == "string" and $mr[.card] then .name = $mr[.card] else . end) | if .by == "judge" then (.finding | one) as $f
        | ([$rv[.card] // [] | .[] | select(any(.seen[]; . == $f))] | first) as $r
        | (if $r == null then null else $r.value | numbered end) as $n | . + {round: (if $n == null then null else $r.key + 1 end), findings: $n} else . end)
    | sort_by(.time) | reverse
    | def shown: .dismissed == null and .built == null and ((.time | fromdate?) // 0) >= $now - 7 * 86400;
    {shown: map(select(shown)), rest: map(select(shown | not))}' "$d/${DECLINED##*/}" > "$d/declined" 2>/dev/null && [ -s "$d/declined" ] || echo '{"shown":[],"rest":[]}' > "$d/declined"
  # testActions: the Tests seat (the control record's tests, null when none is set), the time limit of an action and
  # the actions' records it lists, running and kept, newest first (testacts(), lib/testaction.sh). tests: the test files'
  # figures, settings and totals (testspart(), lib/testfiles.sh), null when the pack cannot be read.
  testspart "$since" > "$d/tests" 2>/dev/null && [ -s "$d/tests" ] || echo null > "$d/tests"
  # testMap: the Test map part (mapboard(), lib/testmap.sh).
  mapboard "$MAIN" > "$d/testmap" 2>/dev/null && [ -s "$d/testmap" ] || echo null > "$d/testmap"
  # bench: the Benchmarks tab's live part, board.json of `conveyor.sh bench swe` (bench/swe.sh); a run in progress whose process
  # is gone (killed with no end written) is shown stopped, and soloKey is the key of the builder seat in force now
  # (swe_solokey()), not the one board.json kept from its last write. No program starts before the first run.
  echo null > "$d/bench"
  if [ -s "$ST/bench/swe/board.json" ]; then
    bp=$(jq -r 'objects | .live | objects | select(.state == "running") | .pid | numbers' "$ST/bench/swe/board.json" 2>/dev/null) || bp=''
    bf=objects; [ -z "$bp" ] || kill -0 "$bp" 2>/dev/null || bf='.live.state = "stopped" | .live.current = null | .live.active = null'
    bk=$(. "$HERE/bench/swe.sh" && swe_solokey "$(swe_solomodel)") || bk=''
    jq -c --arg bk "$bk" "$bf"' | if $bk == "" then . else .soloKey = $bk end' "$ST/bench/swe/board.json" > "$d/bench.new" 2>/dev/null && [ -s "$d/bench.new" ] && mv -f "$d/bench.new" "$d/bench"
  fi
  jq -c --slurpfile bn "$d/bench" --slurpfile tm "$d/testmap" --argjson mv "${moved:-null}" --slurpfile dec "$d/declined" --slurpfile ta <(testacts) --argjson tl "${TESTACTION_TIMEOUT:-null}" --slurpfile tp "$d/tests" --slurpfile pr "$d/prices" --argjson sk "$sk" --argjson pc "$pc" '$ta[0] as $ta | del(.cols) | .declined = $dec[0].shown | .declinedRest = $dec[0].rest | .prices = $pr[0] | .standing = $sk | .pushCheck = $pc
    | .testActions = {seat: (.control // {} | .tests // null), limit: $tl, actions: $ta, allowed: ((.modelSettings | objects | .builder.allowed) // null)} | .tests = $tp[0] | .testMap = $tm[0] | .bench = $bn[0] | def since: . + {since: $mv[.issue | tostring].at};
    if $mv == null then . else (.queue.order, .queue.holding, .queue.waiting) |= (if . == null then null else map(since) end) | .open.held |= map(since) end
    | .cost.unpriced |= (group_by(.time) | reverse | map(.[]))' "$d/out" > "$d/full" || exit 1
  # The lists whole go to HISTORY, by a file of their own beside it and one rename, so a reader never sees half of one;
  # the record printed holds the newest of each. A history that cannot be written leaves the last one and says so.
  # historySum is the cksum of the history written (null when none was), so it changes when any entry of it does; less
  # every waitMaxSec and runSec in a card's metrics (its runs' sums and thisRun too), which grow with the clock alone
  # while the card is blocked or open.
  hs=''
  { hf=$(mktemp "$HISTORY.XXXXXX") && jq -c '{landed, metrics: {cards: .metrics.cards}, cost: {cards: .cost.cards, unpriced: .cost.unpriced}, declinedRest, pushedCards}' "$d/full" > "$hf" \
      && hs=$(jq -c 'del(.metrics.cards[]?.metrics | .. | objects | .waitMaxSec, .runSec)' "$hf") && hs=$(printf '%s\n' "$hs" | cksum | tr ' ' -) && mv -f "$hf" "$HISTORY"; } \
    || { hs=''; rm -f "${hf:-}"; echo "conveyor: cannot write $HISTORY; the history the Board reads is the last one written" >&2; }
  # Past the cut, landed keeps every card still on the belt (the Board puts one landed today in Landed, not Building),
  # and branches the newest row of each lane's change (lanekeys), so a lane left as it was is still told it landed.
  jq -c --argjson k "$SNAPKEEP" --argjson p "$PUSHKEEP" --argjson lk "$(lanekeys)" --arg hs "$hs" '.landedCount = (.landed | length)
    | ((($ENV.CONVEYOR_NOW // "" | tonumber?) // now) - 90000) as $day
    | .metrics.steps = [.metrics.cards // [] | .[] | {card, issue, steps: [.metrics.timeline // [] | .[] | select((.time | fromdate? // 0) >= $day)
        | {step, time} + ({writes, judgeWrites} | with_entries(select(.value != null)))]} + (if .name then {name} else {} end) | select(.steps != [])]
    | .historySum = (if $hs == "" then null else $hs end)
    | .landedUsd = (if all(.landed[]; .usd | type == "number") then [.landed[].usd] | add // 0 else null end)
    | [.belt[] | select(.landed == true) | .card] as $on
    | .landed |= [to_entries[] | select(.key < $k or (.value.card | IN($on[]))) | .value]
    | (.metrics.cards, .cost.cards, .cost.unpriced, .declinedRest) |= .[:$k]
    | .branches |= (sort_by(.time) | reverse | .[:$k] + [.[$k:] as $o | $lk[] as $l
        | first($o[] | select(.issue == $l.issue and ($l.issue != 0 or .title == $l.title)))] | unique_by(.card) | sort_by(.time) | reverse)
    | .pushedCards |= (sort_by(.time) | reverse | .[:$p])' "$d/full"
)
# lanekeys -- what the Board finds the card that landed a lane's change by (dashboard.sh landing()), for each lane of
# MAIN that holds a change (the linked worktrees lanetips counts as lanes): a JSON list of {issue: the issue at the end
# of a branch named as a card id of this project (landbranch()), else 0; title: the subject of the oldest commit it
# has that BRANCH has not}.
lanekeys() {
  local l p q b f
  l=$(lanepath 2>/dev/null && cd "$LANE" 2>/dev/null && pwd -P)
  git -C "$MAIN" worktree list --porcelain 2>/dev/null | while IFS= read -r p; do
    [[ $p == 'worktree '* ]] && p=${p#worktree } || continue
    q=$(cd "$p" 2>/dev/null && pwd -P) && [ "$q" != "$MAIN" ] || continue
    { [ -n "$l" ] && [ "$q" = "$l" ]; } || [ "$(git -C "$p" config --worktree --get protocol.allow 2>/dev/null)" = never ] || continue
    f=$(git -C "$p" log --reverse --format=%s "refs/heads/$BRANCH..HEAD" 2>/dev/null | head -n 1); [ -n "$f" ] || continue
    b=$(git -C "$p" symbolic-ref -q --short HEAD 2>/dev/null) || b=''
    jq -cn --arg b "$b" --arg f "$f" --arg t "$CTAG" '{issue: (($b | capture("^c[0-9]{8}T[0-9]{6}-\($t)-(?<n>[1-9][0-9]{0,8})$").n | tonumber) // 0), title: $f}'
  done | jq -cs .
}
# history -- the lists the snapshot cuts, whole (HISTORY); a state with none yet has a snapshot taken first to write it.
history() {
  [ -s "$HISTORY" ] || snapshot >/dev/null || return 1
  jq -ce 'objects' "$HISTORY" || { echo "conveyor: $HISTORY does not read" >&2; return 1; }
}
