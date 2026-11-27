# SPDX-License-Identifier: Apache-2.0
# The snapshot (the strip-down to Conveyor): one JSON object holding everything the Conveyor
# views show, so the dashboard and /units read one record and cannot disagree. Every object in it that names a
# main-red fix card (card), which has no issue (issue 0), also has name: "Main is red (<commit>)" (rows.jq). It holds:
# needsYou: waiting (the cards blocked for the owner's yes to a visible change or a lint policy change: card, issue, title, sentence: the
#   reviewer's, with the lint policy files it changes, or the policy files alone for a lint policy stop, since, files: {count, paths: the first 200 its blocked line names, or null}, shots: the project's own
#   screenshots it kept, {patch: the hash of the patch they were kept for, shots: [{file, caption}]}, and patch: the
#   hash of its kept patch now; both null when it kept none) and blocked
#   (every other blocked card: card, issue, title, reason: the sentence, onMain: true on a land-branch card whose
#   branch's change is already on main (it can be shut), tail: the end of the output that failed, with its
#   newlines, "" for none, since; and, while a push of main has failed again on its next try, one item for it:
#   push true, under the card of the last landing not pushed, reason naming the cards not pushed, unpushed: their
#   {card, issue}, tail: the push error, since: the first failure), and before (the issues waiting for the owner's yes
#   before their build, as health names them: issue, title, section, since; null when gh cannot list the issues), and
#   pipeline (the open follow-ups filed held for a finding on a pipeline file, followups(), while the control record
#   holds them: issue, title, cost: their "Cost to every card:" line, parent, since; null when gh cannot list the issues),
#   and farDeps (each open issue's dependency in another repository that could not be read, so the issue waits:
#   issue, title, ref: "owner/repo#N", line: the Depends on: line naming it, reason: what gh said; null when gh cannot list the issues),
#   and shutDeps (each waiting issue's dependency whose newest card the owner or the engine shut, so no card builds it
#   and the wait cannot end, one forced past its wait left out: issue, title, dependency, card: the shut card, since: its end,
#   reason: who shut it and the way out; null when gh cannot list the issues),
#   and engine (for a pack that follows the plugin's main, the newest commit of it this machine did not take, until a
#   later one is taken: commit, reason (its failed check, or the hooks it lacks), since; else null), and testRules
#   (when the last pass of the test rules, lib/testrules.sh, had the switch on and matched more files than one day's
#   cap, so it filed nothing: time, matched, cap; else null), and prices (the models the belt runs or offers with no
#   price, as serve's last look found them, noprice(): models; else null), and stopped (the engine, while a stop signal
#   has held it for over a minute, as health's engineStopped: title, reason (with the kill -CONT command that resumes
#   it and each stopped process under it), since, pid, pids; else null), and pick (the rule Pick settings: a decision for each
#   group whose tenth trial card ended, {group, title, reason, since, time (since again: the Foreman watcher keys it on time), trial, default}, cost.trials.groups' due; and,
#   while the control record holds pickBack, the rule's own return to shadow, {group: null, title, reason, since, time}).
#   priceNotes, beside it, is each plugin problem note serve's look made for a model the built-in price table does
#   not price, as the Foreman's plugin-bugs.md holds it now, less one filed since ([] for none): a Board on another
#   machine than the belt adds it to the Foreman's folder there (.claude/scripts/dashboard.sh foremen()). priceFiled
#   is each model a filed note of that form there names, or whose note the Board there filed or dismissed, whatever
#   project of the group noted it ([] for none): that Board takes out its unfiled copy of the note.
#   mainTest, beside it, is the failure of the whole test on main that stands (maintest(): issue, cases, from, to,
#   since, exit), null when its last run passed or none ran, when the pack names no test.main, or when its issue is
#   known closed. fullTest is the full test suite of the Board (fulltest()): command (the pack names test.full), why
#   (the reason both buttons are off, else null), running ({since, sha, how} while a run or push holds its lock, else
#   null) and last (the last line of its record, else null). suites is each whole-suite run, the release's and the
#   full test's, in one shape (suites()): {kind ("release" or "full test"), version (a release's), step, sha, since,
#   ended (null while under way), state, done, failed, cases (the failed cases' names), timedout (a release's: those
#   of them that timed out, suiteprog()), files ({done, of, failed}),
#   moved, reasons}, and a release's rerun (while its failed cases run alone: {round, of, case, since, done, failed,
#   files, at: when that pass last moved}; else null), and its coverage ("running" while its run makes the coverage
#   map, ended or not: relcov(), lib/relcov.sh): the release
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
#   on a same-file card, never the landing it waits to begin), offCap (true while the card lands, in its land step and not waiting: the one kind of open card that the loop's count against the card cap leaves out; false for the rest, a landing rebuilt after a conflict and a wait for a release run too: offcaps(), lib/views.sh), waitsOn (that card's {card, issue, state}, else null), gaveWay (the issue
#   of the card it gave up its land turn to while it is fitted, reviewed, fixed or tested again: giveway(); else null),
#   gaveWayFixing (it gave that turn up for the fix of its failed tests), review (the number of
#   the review in progress, else null; it can pass `of`, the 3 of the review rule, after a landing conflict or a test
#   fix), stepAt (when the step began: its live record's at while it runs), model (the one running the step: a session's or a review's, else null), effort (the effort that model runs at, from the step's live record; null when it names none),
#   tokens (fresh, so far) and usd so far: the finished steps and the live record of the running one; usdKnown, the
#   dollars of those that are priced, and notPriced, how many are not (usd is null while one is not); estimate, true
#   when a step is priced as an estimate (the price table's estimate: its usage was read only in part, or not at all, and then it is the median of its model's steps of its kind). reading is
#   false, and usd null, while neither a finished session or review nor the live record holds a token: "no reading
#   yet", never $0; atEnd is true when, in that time, the running Claude session's answers all report usage 0 (a route
#   that streams none): "cost shown when the step ends". live is {turns, lastOutputAt, action, at} of the running step (at: when its live record began; for a
#   card waiting for main to change, mainred.sh mainwait(), when that wait began), or null. beyond: why it took a slot beyond the
#   project's cap ("main is red": a main-red fix, redfix() or pick.sh redtests()), null once it has landed or when it took none. reviews and
#   track are as below.
# reviews (of a belt card and of a landed one): its finished reviews in order: round, verdict (GO, NO-GO, or none),
#   counts (the findings by level; null for a review recorded before they were counted), sec, fixed (a fix round
#   followed it), and judge, what the judge (judged()) made of it: {ran: true, accepted, declined, outside (how many findings of
#   each; outside: found outside the card's change, filed as follow-ups, only when it found any; selfheals: written to
#   the self-heals list, only when it wrote any), go (its GO came from the judge accepting no finding)}, or {ran: false, why} for a review the judge did
#   not read (its call failed, the judge is off, or the review held no finding or no verdict). survived: the findings
#   of a NO-GO that came back after a fix round told to fix them, each {id, rounds: how many fix rounds}, else [].
#   loopEnd: on the review that ended the fix loop, {stop: why (card.sh loopstop()), own: the card's own reviews (the record's pass), rounds}, else null.
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
#   n, and outside: the findings the judge found outside the card's change, each {finding, issue}, when it filed any), and detailAt the place in it of the step in progress.
# A card of needsYou, belt and landed also has parent (the issue whose landed line filed it as a follow-up, else
#   null) and its times: start (when its work was first picked up: a card resumed from a kept patch counts the
#   cards whose work it resumes, and a restarted card its issue's earlier runs), pickedAt (its own pick-up), priorSec (the seconds of those earlier cards, pick-up to
#   end), earlier (those cards, the first first: card, start, end, sec, reason, track, so the step view shows them)
#   and totalSec (priorSec and its own pick-up to its end; null while it is open: the view adds the time since
#   pickedAt). The time an issue sat queued is in none of them. stalls: how many times a build, fix, rebase or review
#   of it made no progress for STUCK seconds and was ended (watch()); the card detail shows it. split: what the rule
#   Split large issues made of its issue ({result, slices, filed}, rows.jq), null when the rule did not check it. seats:
#   the seats the judge gave it under the rule Pick settings (its pick's asked: each seat's model, effort, why and
#   clamp, or failed, or guard: pickjudge(), lib/modelpick.sh), with the pick's mode and run (the seats the card runs
#   on that the rule set, each with who set it: seatsof, below), null when the rule did not pick it.
# repo: the project's name (REPO), as health names it too; health's room is the card the machine holds back (room()),
#   and its machine the machine's settings (mhost(): {cap, paused}, {unread: true} for a host file that
#   does not read, null when it sets none), the same for every project of the machine, and
#   its cores the cores kept for the user (lib/slots.sh slot_reserved) for the Rules tab too: {reserved: the core
#   numbers, slots: the test-slot pool's size on the cores left (null when not read), unavailable: why this machine
#   cannot keep cores (slot_reserve_why), else null}.
# queue: next (the first 10 issues pick would take, in its order: issue, title, priority, followup, retried, and room:
#   why the machine holds it back, on the one it holds; one forced past its wait also has forced: true and waitsFor:
#   the open issues it waits on, in order too, so it keeps its dependency tag; release: the version of the release it
#   waits for, while the release limit (rellimit(), lib/pick.sh) keeps it off the belt, in order too); and, from the
#   control record, order (every issue pick would take, in its order, as next names them with room, and created: its
#   createdAt, areas: its area: labels, so the Rules tab can say what a Never build label would skip), holding (issue, title, priority, followup, retried, created: the issues the record holds; the Board
#   places one released before the snapshot catches up by them, as pick sorts; waitsFor: the open issues it waits on, [] for
#   none) and skipped (issue, title, rule: those its rules exclude; rule is the area
#   label never built, "follow-ups", or the priority); and waiting (every open issue with no card that waits on
#   an open issue it depends on and that pick would take once those land: none held, skipped or waiting for the
#   owner's yes before its build, which open.held gives with their wait; in pick order: issue, title, priority, followup, retried,
#   created, waitsFor: the open issues it waits on, open follow-ups of its dependencies included, waitsOn: each
#   number of waitsFor with its state ({issue, state}; state is one of "building", "shut" (its newest card was shut: shutDeps), "blocked", "held", "waiting for a yes", "skipped by a rule", "waiting
#   for #N" (it waits on another issue too), "queued" or "open, no card"), so a wait says why it does not end, forced: `control
#   force` lets it be picked all the same, the dependency guard off; a forced one is in order too). All are null when gh cannot list the issues: the rest of the
#   record is still given. holding and skipped list only issues pick would take but for the record.
#   Each of order, holding and waiting, and each of open.held, also has since: when it came to Held or Queue, as
#   moved.json (MOVED) dates it, so the Board sorts those columns by the time in them, not by the issue's age.
#   Each issue of the queue, and each card of belt and needsYou.blocked, that is a GitHub sub-issue of a parent
#   (openissues()) also has umbrella: that parent's number.
#   cards: every card with no GitHub issue that waits to be picked (TCQUEUE), in the order pick takes them: {card: its
#   id, title, kind: the name the Board shows it by, priority, created: when it was filed, held, waitsFor: issue numbers,
#   "owner/repo#N" and card ids, rule: the area label never built or "follow-ups" that skips it, else null}. null when
#   their record is missing or cannot be read. Given with or without the open issues.
# open: every open issue and where it is (issues: each with its labels), below at open; umbrellas: each open parent
#   (an issue with GitHub sub-issues) as one entry {issue, title, parts, done, all, inFlight, closed}; null when gh cannot list the issues.
# control: the whole control record as it stands, start (where new issues start) among it (null when it does
#   not read); forecast: below, at forecast.
# modelSettings: the build and review models and efforts in force, where each comes from and the choices: the CLIs
#   installed on this host with the models each has registered, and why a seat cannot start (modelsettings()).
# accounts: the names of the host file's accounts, the choices of the control record's account and reviewAccount.
# inFlight: each open card on the belt with the accounts it started on, whatever the control record names now:
#   {card, issue, step (its step on the record: rows.jq x.at), account, reviewAccount}, the accounts as its worktree
#   line names them (null: the default login; for a review, its account).
# limits: the weekly limit reading of each Claude account a card started on the control record runs on, the guard's
#   (guardaccts, lib/paths.sh): [{account (null: the default login), uses (build, fix: repairs alone, review), pct, readAt, email (its
#   login on this machine)}]; null when it could not be read.
# areaPrefix: the pack's labels.areaPrefix, what an area label and an area rule start with.
# packPick: the models the rule Pick settings may give each seat, shown and set in the Rules tab's Pick settings row
#   (`conveyor.sh pick models`): {lists: the pack's pick ({<seat>: {<model>: {min, max}}}; {} when it sets none),
#   efforts: the efforts each program takes (EFFORTS, lib/paths.sh), the words of each model's effort menus}.
# packSplit: the four limits of the rule Split large issues in force (split.doneWhen, split.files, split.areas and
#   split.chars, read by splitcheck(), lib/slices.sh), shown and set in the Rules tab (`conveyor.sh split-limits`):
#   {doneWhen, files, areas, chars}, each {n, from: pack when the pack sets it, default when the schema's default
#   counts, default: the schema's default, which Use default sets}; null when the pack cannot be read.
# packLandAs: the pack's push.landAs (main or pr), the rule Land as while the control record's landAs is null; null
#   when the pack cannot be read.
# packPrMerge: the pack's push.prMerge (button, release or idle), the rule Merge PR while the control record's prMerge
#   is null; null when the pack cannot be read.
# standing: the pack's auto.standing, the standing kinds of routine yes that are on (lib/standing.sh), for the Rules
#   tab; null when the pack cannot be read.
# pushCheck: the pack's push.check (true or false), whether the run before a push runs when the control record's
#   pushCheck is null, for the Rules tab; null when the pack cannot be read.
# lintCommands: the pack's lint.commands, each {run, files}, listed read-only beside the rule Lint check on the Rules
#   tab; [] when the pack sets none, null when the pack cannot be read.
# waitWake: the pack's foreman.waitWake (default 10), the minutes a card waits for main to change, or on another card,
#   before the Foreman's watcher wakes it; read here, on the belt's host, as the Foreman's machine may hold no pack.
# awaitingDeploy: the open issues labelled awaiting-deploy (built, waiting for the owner's deploy), apart from next and
#   from held, which never count them: issue, title, since (when the label was last added; null when GitHub did not
#   say), lowest number first. null when gh cannot list the issues.
# landed: the cards that landed today, or closed their issue as already fixed (step says which), newest first: usd
#   (with usdKnown, notPriced and estimate, as a belt card's), reviews, the
#   follow-up issues filed, rounds (the reviews list above; reviews is their number), fixes (its fix rounds: every fix line,
#   a fix after a failed Done-when check or failed tests too), track, and pushed (false while health lists its commit as unpushed; null for a closed card,
#   which has no commit), batch (the cards it landed with in one batch, itself among them, in order; null when it landed alone),
#   rollout (the rollout actions its landed line carries, {action, fails, place} each, rollouts(); [] when none).
#   A card with no GitHub issue (issue 0) that its record keeps (testcard(), lib/testaction.sh) also has body, and
#   filed and filedUrl once File on GitHub filed an issue from it (cardissue()).
#   Its usd, reviews and fixes, and a belt card's usd and tokens, are of every run of its issue (a card `retry` or a
#   new pick restarted: the runs below, at metrics); rounds and track are of its own run.
#   landedCount: how many there are, and landedUsd their usd added up (null when one has none), landedEstimate how
#   many of them have a step priced as an estimate; landed holds the
#   newest SNAPKEEP of them (below), and any older one still on the belt.
# declined: the lines of the declined list (DECLINED) the Board's Declined panel shows: not dismissed, not built and at
#   most 7 days old; newest first, each as its line is: id, time, card, issue, finding, by, why, repo (and name, a
#   main-red fix card's, from its records: it has issue 0); one the judge
#   declined with round and findings too (the review of its card it was declined in, and that review's findings as
#   the judge numbered them, [{n, finding}]; both null when they are not found in the card's records).
# declinedRest: every other line of the list, newest first, as its line is, with built (the issue filed for it) or
#   dismissed ({time, by}) when it has them: the panel's "Show every line" shows them.
# selfheals: the self-heals list (SELFHEALS) as the Board's Self-heals tab shows it (healssnap()): entries,
#   every line no batch card holds yet (each one a batch card would file), newest first, each as its line is; areas,
#   [{area (null for none), count}] of those lines, the most first; docs, the docs list (DOCSDRIFT) as {entries, areas}
#   alike; dropped, the entries that expired off the list (HEALSDROPPED, healsexpire()), each as its line is, with
#   dropped: {time, why}, the latest first; sorted, the last sort of the queued follow-ups (HEALSSORT): {time, ended, items (how many it
#   sorted), moved (how many went to a list), failed (the judge's failure, when it failed)}, null when none ran.
# branches: the cards land-branch made that landed or closed, on any day (landed and cost.cards drop a card after
#   today and after the 7 days; a lane left as it was still has to be told its change landed): card, issue,
#   title, step, time. Only the newest of those that share an issue and a title, so a branch landed again is one row;
#   the newest SNAPKEEP of those rows, newest first, and past them the newest row of each lane's change (lanekeys), so a
#   lane left as it was is told its change landed however many land after it.
# pushedCards: every card whose commit was pushed on a day of the 7 days to today, whenever it landed (metrics.cards
#   and landed go by the landing): card, issue, sha (its landed commit), time (the push), day (the push's day on this host, as day above). The Foreman's watcher wakes on an awaited issue's push
#   from it (#4042), and names its commit from sha: landed holds only today's landings (metrics.cards' sha, each card's
#   landed commit, names it while the push is in no pushed line yet). It holds the newest PUSHKEEP of them, by the push: the watcher looks once a minute, and reads
#   HISTORY for an awaited issue that is in neither this list nor metrics.cards.
# The lists that grow with every card that lands are cut to their newest SNAPKEEP, so a snapshot read every second
# stays the same size however many cards land (README.md says its bound): landed, metrics.cards, cost.cards,
# cost.unpriced (newest step first; steps of one time in their order) and declinedRest (and pushedCards, above). Each list whole is in HISTORY, written by every snapshot as it
# ends; `conveyor.sh history` prints it, and the Board reads it when a panel that shows them opens. historySum: the
#   cksum of that history as written, less every waitMaxSec and runSec in metrics.cards (thisRun's too), which grow
#   with the clock while a card is blocked or open (null when it could not be written); the Board reads the history again only when
#   it or the day changed.
# health: the health record, which names builderCap, models and efforts as in force (the control record's, else the seed's),
#   and timesPlan, what Record test times would do while its untimed is above 0 (timesplan(), lib/setup.sh: {kind: report |
#   wrap | card, ...}), else null.
# testSlots: the machine's test-slot pool (lib/slots.sh), {used: the slots a test run holds now, of: the pool's size};
#   null when the pool cannot be read.
# flaky: the cases of the flaky-test record (lib/flaky.sh) with entries in the last FLAKY_DAYS days to the health
#   record's time, most entries first: case, count (those entries), issue (the one last filed for it, else null),
#   files (the test files the case counts for, lib/testfiles.sh caseowners: a runner's case, its case file too).
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
#   cacheWrite, in $ per million tokens), aliases (the built-in aliases: {alias: the model it is priced as}), overrides (the pack's prices, added models and aliases, which win over it),
#   names (each model's display name) and seen (each model ID the steps and the research lane's sessions of the last
#   30 days ran: model, sessions, routes, as: the model it is priced as, or null, and lane: true for one only the
#   research lane's sessions ran) and research (the pack's research lane model, or null); null when the
#   table cannot be run.
# checkRun: the check run the pack's checks.progress prints, as checkrun() below says; no such field without one.
# cost: usd of the steps that ended today and in the 7 days to today, those of a blocked card that `retry` moved
#   to the retried file among them (the money was spent; such a card is in no other part of the record); over the
#   cards that landed in those 7 days, perLanded (their average usd, each the dollars of every run of its issue) and
#   landedAfter (how many landed after 1, 2, 3 and more reviews of their own run). today, week and perLanded are the dollars of the steps that are priced: todayLeftOut,
#   weekLeftOut and perLandedLeftOut count the steps each leaves out for having no price, todayEstimate,
#   weekEstimate and perLandedEstimate the steps of each priced as an estimate, unpricedSteps is
#   the 7 days' count and unpriced lists those steps ({card, issue, step, time, why}); all three figures are null
#   only when the price table cannot be run. cards, one row for every card with a step that ended in the 7
#   days, the one worked on last first: card, issue, title, state (on the belt, blocked, landed, closed or retried)
#   and its usd of today and of the 7 days, with todayEstimate and weekEstimate (its steps of each priced as an estimate). A card landed or blocked on an earlier day is in it, so is a retried one.
#   A card restarted is one row, of its newest run: runs (how many), its usd those of every run's steps. picks: the
#   cards the rule Pick settings picked, on any day, one row a group and builder choice ({group, model, effort,
#   cards, landed, usd, estimate, firstTry, reviews, open}; a card's earlier runs count with it; usd null when a step of them
#   has no price, estimate how many of them are priced as an estimate). trials: {dropped: [{group, model, effort, cards}], flagged: [{card, issue, group, files}]}, the
#   groups whose trial challenger two blocked trial cards dropped, and the trial cards whose change touches pipeline files;
#   groups: each group that had trial or promoted cards, {group, model, effort (the challenger), decision and decidedAt (the
#   owner's, `control pick`, else null), trial, default and promoted ({cards, landed, ended, usd, perLanded}), due, over, and back while over: the rule's reason to go back to shadow},
#   as the comment above its jq says.
#   replay: the last judge replay study (the last line of REPLAYS, replay() in lib/replay.sh) with no
#   calls (all of its differ), else null.
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
# null when no sample covers it), waitWhy (of that time, the seconds under each cause the samples name for its issue:
# cap, overlap, Depends on, held, guard or machine hold; lib/records.sh sample()), buildSec, reviewSec, fixSec, testSec,
# rebuildSec (each step's seconds added up),
# landSec (every landing attempt, the one that met a conflict included), pushSec (landed to pushed), waitMaxSec (waiting on the owner: from the end of the issue's last blocked card to
# its retry, or to this card's pick when its retry time is not recorded, and for a card that is blocked now, its end to now), leadSec (issue opened to landed) and
# cycleSec (picked to landed), reviews, firstReview (its verdict), findings (by level, all reviews; null when a review
# has none counted), rebuilds, retries (the issue's blocked cards before it), blockClass (why it is blocked: the class
# its blocked line names, proof check, api error, stall or timeout, else visible change, no change, conflict, session failed, tests failed, timeout,
# prompt too long, lint, setup, product check, engine error or other), brokeMain (the card whose landing turned main red,
# as its test line names it; null for none), depth, followups (how
# many it filed), diff ({files, added, removed}), limit ({before, after, used}: weekly limit percent; used is null
# when the limit reset during the card), usd (null when
# a step is unpriced), tokens, unpriced (how many of its steps have no price), usdKnown (the dollars of those that are
# priced), estimate (true when one is priced as an estimate) and timeline: each finished step with
# its time, seconds, tokens, dollars, model (the one it was priced at, else the one its line names), effort,
# findings, tests, session stats, unpriced (why it has no price, null when it has one) and, on a step priced from
# the pack's prices, override (true), on one priced as an estimate, estimate (how it was made), and, on a review whose reviewer or judge wrote cache, writes and judgeWrites (each
# {model, write, write1h}: the cache write tokens of its session, which keeps no transcript). A reading that was not
# taken is null: a session whose usage could not be read has tokens null, not 0. runSec (pick-up to end, or to now),
# fixes and testRuns (its fix and test lines). runs: how many runs of its issue the card's figures add up (the cards
# of the issue since it last landed or closed, with the retried ones, to this one): with more than one, usd, tokens,
# unpriced, usdKnown, each step's seconds, runSec, reviews, fixes and testRuns are their sums (usd and tokens null when a run's
# is; estimate when a run's is), and thisRun holds the card's own; queueSec, leadSec, cycleSec and the rest stay its own.
# The snapshot's metrics: today, week (the 7 days to today) and prev (the 7 days before those) as totals() gives them;
# days, each of the 7 days oldest first ({day, landed, blocked, cycleSec: its median, firstReviewPass, perLandedUsd: null
# when a step of the day's landed cards is unpriced or priced as an estimate, so a part cost is never drawn as the
# whole, nor an estimate as exact});
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
    | ([$smp[] | select((.wait | type) == "object") | (.time | fromdate) as $t | .wait | to_entries[] | select(.value | type == "string") | {k: .key, t: $t, why: .value}]
        | group_by(.k) | map({key: .[0].k, value: map({t, why})}) | from_entries) as $sw
    | [$cs | map(. + {metrics: cardm($now; $blocks; $st; $sf; $sw; $every; $yes)})] as $all
    | ($all[0] | map(select(.issue != 0)) | group_by(.issue)
        | map(sort_by(.startedAt, .card) | reduce .[] as $k ({run: [], out: []}; .run += [$k] | .out += [{key: $k.card, value: .run}]
            | if ($k.step | IN("landed", "closed")) and $k.x.blockedAt == null then .run = [] else . end) | .out[])
        | from_entries) as $runsOf
    | def runsum(f): [.[] | f] | if any(. == null) then null else add end;
      def secsum(f): [.[] | f | numbers] | if length == 0 then null else add end;
      def own: {usd, tokens, unpriced, usdKnown, estimate, buildSec, reviewSec, fixSec, testSec, rebuildSec, landSec, runSec, reviews, fixes, testRuns};
    $all[0][] | ($runsOf[.card] // [.]) as $r | .runSteps = [$r[].steps[]] | .runReviews = ($r | map(.reviews) | add)
      | .runFixes = ($r | map(.metrics.fixes) | add)
      | if ($r | length) < 2 then .metrics.runs = 1
        else .usd = ($r | runsum(.usd) | if . == null then null else . * 10000 | round / 10000 end)
          | .x.tokens = {claude: ($r | map(.x.tokens.claude // 0) | add), codex: ($r | map(.x.tokens.codex // 0) | add)}
          | .metrics += {runs: ($r | length), thisRun: (.metrics | own), usd, tokens: ($r | runsum(.metrics.tokens)),
              unpriced: ($r | map(.metrics.unpriced) | add), usdKnown: ($r | map(.metrics.usdKnown // 0) | add * 10000 | round / 10000),
              estimate: any($r[]; .metrics.estimate == true), buildSec: ($r | secsum(.metrics.buildSec)), reviewSec: ($r | secsum(.metrics.reviewSec)),
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
# When the logs of a whole-suite run in <worktree> last changed, epoch seconds: the newest of its output and its log
# folder (suiteprog() reads both), empty with none. It is the last move of a run that has no live record.
logmoved() { # <worktree>
  local logs=()
  mapfile -d '' logs < <(find "$1.testlog" -print0 2>/dev/null)
  p_mtimes "$1.test" "${logs[@]}" | sort -rn | sed -n '1s/ .*//p'
}
suites() {
  local r fr l t m free p at lg again
  if r=$(jq -ce 'objects | select(.kind == "release") | del(.pid)' "$CARDS/release/run.json" 2>/dev/null); then
    if [ "$(jq -r .ended <<<"$r")" = null ]; then
      if ( flock -n 9 ) 9>>"$CARDS/release/lock" 2>/dev/null; then
        t=$(p_stat "$CARDS/release/run.json") && r=$(jq -c --argjson t "${t#* }" '. + (.counts // {}) | del(.counts, .coverage) | .state = "stopped" | .ended = ($t | todate)' <<<"$r")
      elif jq -e '.state == "running" and .sha != null' <<<"$r" > /dev/null; then
        # A card that lands while the suite runs moves main: the panel says so now, not at the suite's end. While the
        # failed cases run alone (rerun), the counts are the suite's, and the worktree's progress is the pass under way:
        # its done, failed and files, and at, when its test run last moved (the live record's progress or its logs' last change, whichever is later; not before the pass).
        # The record is read again (again) after the logs: a pass that ended meanwhile (fulljudge(), lib/fulltest.sh)
        # changed its rerun, and its logs can be the next pass's or the suite's, so a rerun read again unchanged is the
        # only one shown with that progress; one that changed is shown with none.
        p=$(suiteprog "$CARDS/release/wt"); at=$(jq -r '.progress // empty' "$CARDS/release/wt.live" 2>/dev/null); lg=$(logmoved "$CARDS/release/wt")
        { again=$(<"$CARDS/release/run.json"); } 2>/dev/null || again=''
        # The progress and the record read again go through files: a large failed suite passes the 128 KiB a single argument may hold on Linux.
        r=$(jq -c --slurpfile p <(printf '%s' "${p:-null}") --arg h "$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)" \
          --arg at "$at" --arg lg "$lg" --rawfile again <(printf '%s' "$again") \
          '($p[0] // null) as $p | (if .counts != null and (.rerun | type) == "object" and ([$again | fromjson? | objects | .rerun] | first) == .rerun then .rerun += ($p | {done, failed, files})
              + {at: ([.rerun.since, $at, (if $lg == "" then null else $lg | tonumber | todate end)] | map(select(type == "string" and . != "")) | max)} else . end)
            | . + (.counts // $p) | del(.counts) | if .main != null and $h != "" and .main != $h then .moved = true else . end' <<<"$r"); fi
    # A run whose end was written before its coverage map (relsuite(), commands/release-prep.sh) and that let the lock
    # go with the map's mark still on (killed while the map was made): the map no longer runs.
    elif [ "$(jq -r '.coverage // ""' <<<"$r")" = running ] && ( flock -n 9 ) 9>>"$CARDS/release/lock" 2>/dev/null; then
      r=$(jq -c 'del(.coverage)' <<<"$r")
    fi
  fi
  # A full test's marker read before and after its lock is found free ended with no result (fulldead()): a run that
  # ends in between removes it, and one that starts in between writes a new one. The lock is tried shared: the loop's
  # clearing of a dead run's marker (fullreap()) holds it shared, so only a run or an ask holds it.
  { m=$(<"$FULLTEST.running"); } 2>/dev/null; free=''
  ! ( flock -n -s 9 ) 9>>"$FULLTEST.lock" 2>/dev/null || free=1
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
  local h tag='' base next v w='' t rel=false re='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' a b
  h=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null) || { echo null; return; }
  # The shell reads each list git gives (the newest tag first; the notes' names): no grep, sed, tail or awk of its own.
  while IFS= read -r t; do [[ $t =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && { tag=$t; break; }; done < <(git tag -l --sort=-version:refname 'v*')
  base=${tag#v}; base=${base:-0.0.0}
  while IFS= read -r t; do
    rel=true; t=${t#docs/releases/}; [[ $t == *.md && ${t%.md} =~ $re ]] && w+=${t%.md}$'\n'
  done < <(git ls-tree --name-only "$h" docs/releases/ 2>/dev/null)
  w=${w%$'\n'}; [ -z "$w" ] || w=$(sort -V <<<"$w")
  v=${w##*$'\n'}
  if [ -n "$v" ] && relhigher "$v" "$base"; then next=$v
  else IFS=. read -r a b _ <<<"$base"; next="$a.$((10#$b + 1)).0"; fi
  git log -n 100 --format='%H%x09%s' "${tag:+$tag..}$h" 2>/dev/null | jq -Rcs --arg h "$h" --arg t "$tag" --arg n "$next" --argjson rel "$rel" --arg w "$w" \
    --argjson c "$(git rev-list --count "${tag:+$tag..}$h" 2>/dev/null || echo null)" --argjson nt "$([[ $'\n'$w$'\n' == *$'\n'"$next"$'\n'* ]] && echo true || echo false)" \
    '{tag: (if $t == "" then null else $t end), count: $c, commits: [split("\n")[] | select(. != "") | split("\t") | {sha: .[0], subject: (.[1:] | join("\t"))}],
      next: $n, notes: $nt, written: [$w | split("\n")[] | select(. != "")], head: $h, releases: $rel}'
}
# The drift watch of the snapshot's copy of the records (bench/drift.sh --json), else null. It reads the worktree lines
# (the engine commits, in order) and the cards that ended, and a card writes no line that it reads after its end line:
# it is kept in $STATE.drift beside the sum of the worktree and end lines (landed, closed, blocked) it was made of, and
# made again only when they changed. Those lines of the copy, and what drift.sh reads of each line of it (DRIFTIN:
# the fields it reads, a tenth of the line's size), come from summaries of it kept beside the records
# ($STATE.driftlines and $STATE.driftin, linesum(), lib/records.sh): a search of the whole copy for them, and
# drift.sh given the whole copy each time a card started or ended, read the whole history.
DRIFTLINE='select(test("\"step\":\"(worktree|landed|closed|blocked)\""))'
DRIFTIN='select(. != "") | fromjson | objects | select((.card | type) == "string") | {card, step, time, tokens}
  + if .step == "worktree" then {engine} elif .step | IN("landed", "closed", "blocked") then {waitSec} else {} end'
driftof() { # <scratch folder>
  local k v='' ok=''
  linesum "$READ" "$STATE.driftlines" "$1/driftlines" "$DRIFTLINE" 2>/dev/null || { echo null; return; }
  # A retried file with no such line is no failure (grep's 1, which pipefail passes on).
  k=$({ printf '%s\n' "$(<"$1/driftlines")"; grep -hE '"step":"(worktree|landed|closed|blocked)"' -- "$1/${RETRIED##*/}" || [ $? = 1 ]; } 2>/dev/null | cksum) || { echo null; return; }
  { read -r ok && read -r v; } 2>/dev/null < "$STATE.drift" || :
  if [ "$ok" = "$k" ] && [[ $v == null || $v == \{* ]]; then printf '%s\n' "$v"; return; fi
  linesum "$READ" "$STATE.driftin" "$1/driftin" "$DRIFTIN" 2>/dev/null || { echo null; return; }
  v=$(cat -- "$1/driftin" "$1/${RETRIED##*/}" 2>/dev/null | "$HERE/bench/drift.sh" --json /dev/stdin 2>/dev/null) || v=null
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
# The copy of the card records is made from one the snapshot keeps between builds ($STATE.copy): the state database
# gives the lines added since the last build alone (`since`, state.py), or all of them when the records were rewritten
# since (a retry, a line set aside) or no copy is kept. Copying the whole records on each build read 30,000 lines for
# one new line. $STATE.copy.at holds `<end> <mark> <lineage> <bytes>`: what to ask next time, a name that changes at
# each whole copy (within one lineage the copy only grows, so the summaries of it are kept: snaprows, linesum and the
# check), and the copy's size. It is removed while the copy changes: a build stopped then leaves none, and the next
# copies the whole records. This build's copy is the kept one, never copied again: a hard link to it
# ($STATE.copy.r<the snapshot's pid>, removed when the snapshot ends; a copy of it where no hard link can be made),
# and a note in the scratch folder ($d/lineage) of `<lineage> <bytes>` of it. The lines a later build adds go to the
# kept copy in place, unless a build still running reads it (its link is to the same file): the copy is then written
# anew under its name, and that build's link keeps the lines it read. $STATE.copy.counts holds how many lines each
# card has in the copy (`<count>\t<card>`, as RECCOUNT counts them): with SNAPCOUNTS set (snapkeep), they are written
# there too.
snapcopy() { # [<open issues json>]
  local rc=0 c CTL_V r=$STATE.copy.r$BASHPID
  [ -z "${1:-}" ] || { ctlread 2>/dev/null && c=$CTL_V && [ "$(adopted "$c" "$1" 2>/dev/null)" = "$c" ]; } \
    || lockedfor "the snapshot's adopt" adopt "$1" || rc=3
  # The copy, and what the snapshot reads of the records past their rows, are the state database's answers to one
  # call (state.py), read at one time: the pushes, the cards waiting for the owner's yes (yes), the samples and the
  # declined list.
  ( flock 5 || exit 1
    k=$STATE.copy e=0 m=- g='' b=0 w=''
    { read -r e m g b < "$k.at"; } 2>/dev/null
    [ -f "$k" ] && [ -f "$k.counts" ] && [[ $e =~ ^[0-9]+$ && $b =~ ^[0-9]+$ && $g == g* ]] || e=0 b=0
    stdb ask -o "$d/since" since cards "$e" "$m" -- -o "$d/${RETRIED##*/}" lines retried -- -o "$d/pushes" pushes \
      -- -o "$d/yes" yes "$YES" "$ST" -- -o "$d/samples" samples -- -o "$d/${DECLINED##*/}" lines declined || exit 1
    read -r f e m n < "$d/since" && [[ $f =~ ^[0-9]+$ && $n =~ ^[0-9]+$ ]] || exit 1
    # The archive files as they are with this copy (an archive run writes them under this lock): archrows() reads them
    # to these sizes only, so a card the run moves after the copy is counted once, in the copy.
    for l in "$ARCHIVE"/cards-[0-9][0-9][0-9][0-9]-[0-9][0-9].jsonl.gz; do [ ! -e "$l" ] || p_filekey "$l" || exit 1; done > "$d/archat"
    # The ended list too (endedrecs(), lib/records.sh, which reads this copy in the snapshot): a moved card's test lines
    # are in the copy of the records or in this one, never in both.
    [ ! -e "$ENDED" ] || cp -- "$ENDED" "$d/ended.jsonl" || exit 1
    # The links of builds that ended (their process gone) are removed, with what the check left beside one (dropbad's
    # <copy>.kept); one of a build still running to the kept copy as it is means that build reads it (w).
    for l in "$k".r*; do
      p=${l##*.r}; p=${p%.kept}; [[ $p =~ ^[0-9]+$ ]] && [ "$l" != "$r" ] || continue
      if kill -0 "$p" 2>/dev/null; then [ ! "$l" -ef "$k" ] || w=1; else rm -f -- "$l"; fi
    done
    [ "$f" != 0 ] || g=g${EPOCHREALTIME//[!0-9]/}-$BASHPID b=0
    if [ "$f" = 0 ] || [ "$n" != 0 ]; then
      tail -n +2 "$d/since" > "$d/new" && rm -f -- "$k.at" "$k.new" || exit 1
      if [ "$f" = 0 ]; then o=/dev/null; cp -- "$d/new" "$k.new"
      elif [ -n "$w" ]; then o=$k.counts; cp -- "$k" "$k.new" && cat -- "$d/new" >> "$k.new"
      else o=$k.counts; cat -- "$d/new" >> "$k"; fi && { [ ! -e "$k.new" ] || mv -f -- "$k.new" "$k"; } \
        && LC_ALL=C awk "$RECCOUNT" "$o" "$d/new" > "$k.counts.new" && mv -f -- "$k.counts.new" "$k.counts" \
        && b=$((b + n)) && printf '%s %s %s %s\n' "$e" "$m" "$g" "$b" > "$k.at.$$" && mv -f -- "$k.at.$$" "$k.at" || exit 1
    fi
    # The counts are read by the shell: a program more on each build (t_snapexec) for a file of one line a card.
    { [ -z "${SNAPCOUNTS:-}" ] || if [ -s "$k.counts" ]; then printf '%s\n' "$(<"$k.counts")"; fi > "$SNAPCOUNTS" || rm -f -- "$SNAPCOUNTS"; } \
      && { ln -f -- "$k" "$r" 2>/dev/null || cp -- "$k" "$r"; } && printf '%s %s\n' "$g" "$b" > "$d/lineage" ) 5>>"$STATE.checked.lock" \
    && { [ ! -e "$CONTROL" ] || cp -- "$CONTROL" "$d/control.json"; } && return $rc
}
# How many lines each card has in the files given (`<count>\t<card>`, one card a line), a first file of such counts
# added in: a line counts for the card its text begins with ({"card":"<card>").
RECCOUNT='FILENAME == ARGV[1] {split($0, f, "\t"); n[f[2]] += f[1]; next}
  match($0, /^\{"card":"[^"]*"/) {n[substr($0, 10, RLENGTH - 10)]++} END {for (c in n) print n[c] "\t" c}'
# The rows of a records file of the copy, written to <to>, from a running summary of the file kept beside it (<kept>):
# a line `<key> <offset> <sum>` (key: rows.jq and what rows() passes it; offset: how many of the file's bytes the
# summary has read; sum: their cksum, or the copy's lineage when the caller gives one: snapcopy), then a line for each
# card, in card order: `<the card as JSON> TAB <its row> TAB <its state>` (the state rows.jq folded its lines into:
# what the row needs of them). A snapshot parses only the lines past the offset: rows.jq makes the row of each card
# they name from its kept state and those lines alone, and every other row is kept. Searching the whole file for the
# older lines of those cards, and giving them to rows.jq, read the whole history on each build. The summary is made
# anew from the whole file when it is missing, has another key, or its bytes are no longer the file's first bytes:
# `retry` rewrote the card records, shorter, or grown past the offset again since. With a lineage, the copy's first
# bytes are the summary's while the lineage is the same, and the file is not read to check them. Making every row from
# the whole file, on each line the loop wrote, was a fifth of a snapshot's work and grew every day.
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
snaprows() { # <records file> <kept> <to> [<lineage> <size>]
  # The key is the same for both files of one snapshot: worked out once, in the snapshot's shell (SNAPROWS_K).
  [ -n "${SNAPROWS_K:-}" ] || SNAPROWS_K=$({ cksum < "$HERE/jq/rows.jq" && printf '%s\n' "$MAX_REVIEWS" "$NODEPS" "$YES" "$LINTYES" "$SHUT" "$OWNSHUT" "$ENGSHUT"; } | cksum) || return 1
  local k=$SNAPROWS_K r cs size h1 h2 o s n=-1 g=${4:-} rf=$3.rows skip=0
  # With a lineage, the caller gives the copy's size; else the file's sum and size come from one cksum: a file not
  # grown since the summary needs no other program to check it.
  if [ -n "$g" ]; then size=${5:-} cs=$g; else r=$(cksum < "$1") && cs=${r%% *} size=${r##* }; fi
  [[ $size =~ ^[0-9]+$ ]] || return 1
  # Read from a copy: a snapshot running beside this one may put a newer summary in its place meanwhile.
  cp -- "$2" "$3.sum" 2>/dev/null || : > "$3.sum"
  { read -r h1 h2 o s && [ "$h1 $h2" = "$k" ] && [[ $o =~ ^[0-9]+$ ]] && [ "$o" -le "$size" ] \
      && if [ -n "$g" ] || [ "$o" = "$size" ]; then [ "$s" = "$cs" ]; else [ "$(head -c "$o" "$1" | cksum)" = "$s $o" ]; fi; } < "$3.sum" && n=$o
  # Not grown: the rows are the summary's, past its first line.
  if [ "$n" = "$size" ]; then rf=$3.sum skip=1
  else
    if [ "$n" -lt 0 ] && [ "$size" != 0 ]; then
      if [ -s "$3.sum" ]; then echo "conveyor: the snapshot is being made anew from the whole card records (a retry or a resume rewrote them, or the engine changed); this one takes longer" >&2
      else echo "conveyor: the snapshot is being made from the whole card records (no summary of them is kept yet); this one takes longer" >&2; fi
    fi
    if [ "$n" -ge 0 ]; then
      # The new lines (the bytes up to the size alone), the cards they name, the kept state of each (none for a new
      # card) and the kept lines of the other cards. The names are read before the summary (getline): a file of none
      # (the new lines were pushes alone, which no row reads) names no card, and every kept line stays.
      tail -c +$((n + 1)) "$1" | head -c $((size - n)) > "$3.lines" && jq -rR "$ROWKEY" "$3.lines" > "$3.ids" \
        && awk -F'\t' -v ids="$3.ids" -v st="$3.states" 'BEGIN {while ((getline l < ids) > 0) t[l]; printf "" > st}
             FNR > 1 {if ($1 in t) print $3 > st; else print}' "$3.sum" > "$3.kept" \
        && rows "$3.lines" "$3.states" | jq -r "$ROWLINE" | cat "$3.kept" - | LC_ALL=C sort -s -t$'\t' -k1,1 > "$3.rows" || return 1
    else
      rows "$1" /dev/null | jq -r "$ROWLINE" | LC_ALL=C sort -s -t$'\t' -k1,1 > "$3.rows" || return 1
    fi
    { printf '%s %s %s\n' "$k" "$size" "$cs" && cat "$3.rows"; } > "$2.$$" 2>/dev/null && mv -f "$2.$$" "$2" || rm -f "$2.$$"
  fi
  awk -F'\t' -v s="$skip" 'BEGIN {printf "["} NR > s + 1 {printf ","} NR > s {printf "%s", $2} END {print "]"}' "$rf" > "$3"
}
# The card of each line of a records file on stdin that is no push, as JSON: the first field of its card's line in
# the summary (snaprows).
ROWKEY='select(. != "") | fromjson | select(.step != "push") | .card | tojson'
# Each [row, state] rows() gives with states, as its card's line in the summary (snaprows).
ROWLINE='.[] | "\(.[1].k | tojson)\t\(.[0] | tojson)\t\(.[1] | tojson)"'
# The rows of the archived cards (archrecs(), lib/records.sh), written to <to> as one JSON array ([] with no archive):
# the snapshot's cards are those of allrecs, so its cost, tokens, metrics and history count a card whose lines went to
# the archive. They are made by snaprows, with its summary beside the records ($STATE.archrows), and kept with a key of
# the archive files' names, sizes and times and the rows' key ($STATE.archived): the archive is read only when one of
# its files changed. Call it after snaprows has set SNAPROWS_K. The archived push lines, as the state database's pushes
# question gives the live ones (state.py), are written to <pushes to> (nothing with no archive) and kept the same way
# ($STATE.archpushes): the push totals count them too. The archive files are those snapcopy() noted with the copy
# (<scratch folder>/archat), read to the sizes they had then.
archrows() { # <scratch folder> <to> <pushes to>
  local f k
  k=$(cat -- "$1/archat") || return 1
  [ -n "$k" ] || { echo '[]' > "$2" && : > "$3"; return; }
  k=$(printf '%s\n%s\n' "$SNAPROWS_K" "$k" | cksum) || return 1
  { read -r f && [ "$f" = "$k" ] && cat > "$2"; } 2>/dev/null < "$STATE.archived" && [ -s "$2" ] \
    && { read -r f && [ "$f" = "$k" ] && cat > "$3"; } 2>/dev/null < "$STATE.archpushes" && return 0
  archrecs "$1/archat" > "$1/archived" && snaprows "$1/archived" "$STATE.archrows" "$2" && jq -cR "$ARCHPUSH" "$1/archived" > "$3" || return 1
  { printf '%s\n' "$k" && cat "$2"; } > "$STATE.archived.$$" 2>/dev/null && mv -f "$STATE.archived.$$" "$STATE.archived" || rm -f "$STATE.archived.$$"
  { printf '%s\n' "$k" && cat "$3"; } > "$STATE.archpushes.$$" 2>/dev/null && mv -f "$STATE.archpushes.$$" "$STATE.archpushes" || rm -f "$STATE.archpushes.$$"
}
# One push or pushed line of the records, as the state database's pushes question gives it: {step, time, sec[, head]}.
ARCHPUSH='fromjson? | objects | select(.step == "push" or .step == "pushed") | {step, time, sec}
  + if (.head | type) == "string" and .head != "" then {head} else {} end'
# The self-heals list and the last sort as the snapshot gives them (selfheals, above).
healssnap() {
  jq -cn --slurpfile e <(jq -c 'objects' "$SELFHEALS" 2>/dev/null) --slurpfile d <(jq -c 'objects' "$DOCSDRIFT" 2>/dev/null) \
    --slurpfile x <(jq -c 'objects' "$HEALSDROPPED" 2>/dev/null) \
    --slurpfile s <({ tail -n 1 "$HEALSSORT" 2>/dev/null || :; } | jq -c 'objects' 2>/dev/null) \
    'def open: map(select(.batched == null)) | sort_by(.time) | reverse; def areas: group_by(.area) | map({area: .[0].area, count: length}) | sort_by(-.count);
    ($e | open) as $o | ($d | open) as $do
    | {entries: $o, areas: ($o | areas), docs: {entries: $do, areas: ($do | areas)}, dropped: ($x | sort_by(.dropped.time // "") | reverse),
       sorted: ($s[0] // null | if . == null then null else {time, ended, items: ([.items[]? | select(.moved == null)] | length),
         moved: ([.items[]? | select((.effect // "harm") != "harm" and .done)] | length)} + (if .judge.failed then {failed: .judge.failed} else {} end) end)}'
}
# branchon <tip> <base> <scratch folder>: whether main, whose history holds <tip>, still holds the change of the branch
# at <tip>. The change is what landing <tip> on <base> adds to it: <base> is main's commit the card was picked against
# (the picked line's base, landbranch()), which took the change to land that, the merge of the two (git merge-tree,
# here <land>), so a part of <tip> main had already, in another commit, is not part of it. A base git no longer has, or
# the two do not merge: not said to be on main (a card with no base is read against its kept patch's base: below). A file the change
# moved is read at its new name (only the lines it changed there are its own), its old name as one it took out. Else main still
# holds the change when what main changed since <land> (git diff -U0, by line of <land>'s files, a file main moved
# read at the name it had there) removes no line the change added, and adds back no line the change took out beside
# where it took it out (from the line before the hunk's new lines to the line after them; a line main changes there is
# not put back unless it is one of those), takes out no file the change changed (a file moved with so much of it
# changed that git does not pair the two names is read as one taken out), and moves no file to the name of one the
# change took out. A file whose content the change changed holds while main has not made it a binary file or changed
# what such a file holds since (a file the change only moved, or whose mode alone it set, has no content of the
# change's), and a file whose mode it set (made, took out, or gave a new mode) while main has not changed its mode
# since. Each check that cannot run says the change is not on main.
branchon() {
  local l
  [[ $2 =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] && l=$(git merge-tree --write-tree "$2^{commit}" "$1" 2>/dev/null) && l=${l%%$'\n'*} && [ -n "$l" ] \
    && git diff -U0 -M --no-ext-diff --no-textconv --no-color --src-prefix=a/ --dst-prefix=b/ "$2^{commit}" "$l" > "$3/onmain.br" 2>/dev/null \
    && git diff -U0 -M --no-ext-diff --no-textconv --no-color --src-prefix=a/ --dst-prefix=b/ "$l" "refs/heads/$BRANCH" > "$3/onmain.mn" 2>/dev/null || return 1
  # Per file (its diff --git line; a file the branch moved under the key of its new name, from its rename to line, and
  # its old name as one the branch took out), the branch's added ranges (lo, hi) and, per hunk that took lines out, the lines it
  # took out (gone), the places after a line of <land> where they were (p0 to p1) and whether the branch changed
  # it as a binary file (bin); then each file of main's since
  # <land>, under the key of its name in <land> (key(), from its rename from line), its header read whole before hdr()
  # weighs a deletion or a mode change (git writes the mode lines before the rename lines), then each hunk against
  # them, its added lines read before done() weighs it.
  awk 'function hunk(   o, n) { split(substr($2, 2), o, ","); split(substr($3, 2), n, ",")
         A = o[1] + 0; B = (2 in o) ? o[2] + 0 : 1; C = n[1] + 0; D = (2 in n) ? n[2] + 0 : 1 }
    function done(   i, j, s0, s1) { if (!inh || D == 0) return
      s0 = (B == 0) ? A : A - 1; s1 = A + B - (B == 0 ? 0 : 1)
      for (i = 1; i <= nr[k]; i++) if (s0 <= p1[k, i] && s1 >= p0[k, i]) for (j = 1; j <= nadd; j++) if ((k, i, add[j]) in gone) bad = 1 }
    function key(p) { return (p ~ /^"/) ? "diff --git \"a/" substr(p, 2) " \"b/" substr(p, 2) : "diff --git a/" p " b/" p }
    function hdr() { if (hd && (k in seen) && (dl || (mk && (k in mode)))) bad = 1; hd = 0 }
    FNR == 1 { inh = 0; nadd = 0 }
    FILENAME == ARGV[1] && /^diff --git / { k = $0; seen[k] = 1; inh = 0; next }
    FILENAME == ARGV[1] && !inh && /^(old mode|new mode|new file mode|deleted file mode) / { mode[k] = 1; next }
    FILENAME == ARGV[1] && !inh && /^rename from / { o = key(substr($0, 13)); seen[o] = 1; mode[o] = 1; next }
    FILENAME == ARGV[1] && !inh && /^rename to / { o = key(substr($0, 11)); seen[o] = 1; if (k in mode) mode[o] = 1; k = o; next }
    FILENAME == ARGV[1] && !inh && /^Binary files / { bin[k] = 1; next }
    FILENAME == ARGV[1] && /^@@ / { hunk(); inh = 1
      if (D > 0) { na[k]++; lo[k, na[k]] = C; hi[k, na[k]] = C + D - 1 }
      if (B > 0) { nr[k]++; p0[k, nr[k]] = (D > 0) ? C - 1 : C; p1[k, nr[k]] = (D > 0) ? C + D - 1 : C }
      next }
    FILENAME == ARGV[1] && inh && /^-/ { gone[k, nr[k], substr($0, 2)] = 1; next }
    FILENAME == ARGV[1] { next }
    /^diff --git / { done(); hdr(); k = $0; hd = 1; mk = 0; dl = 0; inh = 0; nadd = 0; next }
    hd && /^rename from / { k = key(substr($0, 13)); next }
    hd && /^rename to / { if (key(substr($0, 11)) in mode) bad = 1; next }
    hd && /^(old mode|new mode|new file mode) / { mk = 1; next }
    hd && /^deleted file mode / { dl = 1; next }
    hd && /^(Binary files |@@ )/ { hdr() }
    !(k in seen) { next }
    !inh && /^Binary files / { if ((k in bin) || na[k] || nr[k]) bad = 1; next }
    /^@@ / { done(); hunk(); inh = 1; nadd = 0
      if (B > 0) for (i = 1; i <= na[k]; i++) if (A <= hi[k, i] && A + B - 1 >= lo[k, i]) bad = 1
      next }
    inh && /^\+/ { add[++nadd] = substr($0, 2) }
    END { done(); hdr(); exit bad }' "$3/onmain.br" "$3/onmain.mn"
}
# The Tests page parts of the snapshot (tests: testspart(); testMap: mapboard()) and the test owners they read
# (testowners()) are kept in SNAPPARTS, a file each: the length of the key it was made under on its first line, then
# that key's text, then the part (the shell compares the key: no program sums it). A build whose key of a part is the same takes the kept part and computes nothing; another key, or a kept
# file that is missing or cannot be read, computes the part as before and keeps it. Each part read every input again on
# every build, 7 to 16 seconds of it, though /units reads only testMap of them.
# What must stay true: a part is never kept under a key newer than what it read. snapkeys() reads every key before the
# parts read their inputs, so a record, flaky entry or pack written while a part is computed gives the next build
# another key, and that build computes the part again.
SNAPPARTS=${STATE%/*}/snapparts
# snapkeys sets SK_OWNERS, SK_TESTS and SK_MAP, the key texts of the three parts, from what each reads. A file is keyed
# by its size, mtime and ctime to the nanosecond and inode, a link's by its target's (snapfiles; no line when it is
# not there): written again, even to the same size in the same second, it gives another key. <since> is testspart()'s first day of the 7 days.
# SK_OWNERS, for testowners(), and the start of the other two: main's checkout, its HEAD and the change of its tracked
#   files since (git diff HEAD: an edit not committed is read too) and the list of its tracked files (git ls-files: a
#   deletion or an add staged changes the index, not the diff), which give the tracked test files (testtracked()),
#   their text (the cases, the hollow and proxy checks, the runner the test command names) and the test-speed survey
#   (.conveyor/test-times.json); of the pack ($PACK, untracked in some projects, and left out of main's diff), only the
#   keys the parts read, its test and tests objects (the test.* keys, the test rules' settings and tests.patterns), as
#   packok() checked them, so a change to another key keeps the parts; the engine's code that computes the parts and
#   the pack schema's defaults; and the tools on PATH that neverwhy() looks for (node, python3).
# SK_TESTS, for testspart(): <since>, and TZ with /etc/localtime (its 7 days are local days); the test history's start
#   (the control record's testsFrom, of the build's copy, control: its other fields are not read); the sum of the
#   retried lines and the card records as the part reads them (testlines(): the test, picked, landed, bugproof, review,
#   blocked and closed lines, and of each only the fields TESTLINE keeps; read once, kept in SK_LINES, which testspart()
#   then reads in their place), so a line the part does not read (a card's start, its sessions) leaves the key as it was; the flaky entries inside FLAKY_DAYS of now (flakyAgain counts them
#   from the clock, so an entry that ages out changes the part with no file written); and the files FLAKY, slow.json,
#   SUITERUNS, TESTRULES, TESTRULESLOG, TAFILED, TACARDS, the test actions' records ($TESTACTS/*.json) and the mutation
#   checks' ($MUTS/*.json, $MUTS/asked). $TESTACTS/neverloads is not keyed: it holds parse results by each file's
#   content, which main's key already names.
# SK_MAP, for mapboard(): the pack's test.map; the made map (mappath()), the progress of a run that makes it
#   (mapprogpath()), the record of a build by hand (mapbuildpath()) and suiteruns.jsonl (the suite's seconds); with
#   test.map unset, main's language and its coverage tool's check, run as mapboard() runs it (maplang(), maptool(): a
#   tool installed, as a gem with no Gemfile, changes no file the key could name); with a map the project keeps itself,
#   that file (mapread() reads it in main's checkout, tracked or not). Empty, so the part is not kept, when the pack
#   cannot be read, or while the progress or the build record names a pid: whether that process still runs changes the
#   part with no file written.
# Main's diff, its tracked files, the pack's two objects and the engine's files and schema go into one sum, each after a
# NUL (the diff holds none, a path is never empty), so a key is a few lines; the files of the three keys are read by one
# find, "/" between the keys' lists.
snapkeys() { # <since>
  local m n l tm tv='' tsv='' from='' p i=0 st=('' '' '') ex=() mf=()
  case $PACK in "$MAIN"/*) ex=(":(exclude,literal)${PACK#"$MAIN"/}") ;; esac
  packget test tv tests tsv 2>/dev/null || tv='' tsv=''
  # A pack that cannot be read: no key of the map (a newline is no value packget gives).
  packget test.map tm 2>/dev/null || tm=$'\n'
  case $tm in '' | off | $'\n') ;; *) mf=("$MAIN/$tm") ;; esac
  while IFS= read -r l; do if [ "$l" = "${l% /}" ]; then st[i]+=$l$'\n'; else i=$((i + 1)); fi; done < <(snapfiles "$SCHEMA" "$HERE"/conveyor.sh "$HERE"/lib/*.sh "$HERE"/jq/* / \
    /etc/localtime "$FLAKY" "${STATE%/*}/slow.json" "$SUITERUNS" "$TESTRULES" "$TESTRULESLOG" "$TAFILED" "$TACARDS" "$TESTACTS"/*.json "$MUTS"/*.json "$MUTS/asked" / \
    "$(mappath)" "$(mapprogpath)" "$(mapbuildpath)" "${STATE%/*}/suiteruns.jsonl" "${mf[@]}")
  m=$(printf 'head %s\n' "$(git -C "$MAIN" rev-parse -q --verify HEAD 2>/dev/null)"
    printf 'main %s\n' "$({ git -C "$MAIN" diff --no-ext-diff --no-textconv --binary HEAD -- "${ex[@]}" 2>/dev/null; printf '\0tracked\0'
      git -C "$MAIN" ls-files -z 2>/dev/null; printf '\0pack\0%s\0%s\0engine\0%s' "$tv" "$tsv" "${st[0]}"; } | git hash-object --stdin)"
    command -v node python3)
  SK_OWNERS=$m
  { IFS= read -r from; IFS= read -r n; } < <(jq -rn --argjson c "${control:-null}" --argjson d "$FLAKY_DAYS" '(($c | objects | .testsFrom) // "" | tostring),
    (try (input | (($ENV.CONVEYOR_NOW // "" | tonumber?) // now) as $t
      | [.entries | arrays | .[] | objects | select(((.time | fromdate?) // 0) > $t - $d * 86400)] | length) catch "none")' "$FLAKY" 2>/dev/null)
  [ -n "$n" ] || n=none
  # The lines, read once: testspart() takes them from SK_LINES (testlines()), so it reads what its key names.
  unset SK_LINES; SK_LINES=$(testlines) || unset SK_LINES
  l=$(cksum <<<"${SK_LINES-}")
  SK_TESTS=$m$'\n'$(printf 'since %s\ntz %s\nfrom %s\nlines %s\nflaky %s\n%s' "$1" "${TZ-unset}" "$from" "$l" "$n" "${st[1]}")
  SK_MAP=''
  [ "$tm" != $'\n' ] || return 0
  for p in "$(mapprogpath)" "$(mapbuildpath)"; do [ ! -r "$p" ] || [[ $(<"$p") != *'"pid"'* ]] || return 0; done 2>/dev/null
  case $tm in
    off) l='' ;;
    '') l=$(maplang "$MAIN"); l="lang $l"$'\n'"tool $(maptool "$l" "$MAIN"; echo " $?")" ;;
    *) l='' ;; # its file is in the find's third list
  esac
  SK_MAP=$m$'\n'"map $tm"$'\n'$l$'\n'${st[2]}
}
# `<size> <mtime> <ctime> <inode> <path>` of each file, a line each, from one GNU find (a stat a file was a program a
# file, and the test actions' records are one a file); a file that is not there, or a glob that matched none, gives none.
snapfiles() { find -L "$@" -maxdepth 0 -printf '%s %T@ %C@ %i %p\n' 2>/dev/null || :; } # <file>...
# snappart <name> <key text> <to> <command> [<arg>...]: the part kept under the key written to <to>; else the command's
# output written there, and kept under the key when the command succeeds with output and the key is not empty. Exit 1
# when the command fails. A part that cannot be kept is computed again next time, nothing else.
snappart() {
  local f=$SNAPPARTS/$1 k=$2 o=$3 h l
  shift 3
  if [ -n "$k" ] && { IFS= read -r h && [ "$h" = "${#k}" ] && IFS= read -r -N "$h" l && [ "$l" = "$k" ] && cat > "$o"; } 2>/dev/null < "$f" && [ -s "$o" ]; then
    return 0
  fi
  "$@" > "$o" || return 1
  [ -z "$k" ] || [ ! -s "$o" ] || { { [ -d "$SNAPPARTS" ] || mkdir -p "$SNAPPARTS"; } && { printf '%s\n%s' "${#k}" "$k"; cat -- "$o"; } > "$f.$BASHPID" \
    && mv -f -- "$f.$BASHPID" "$f"; } 2>/dev/null || rm -f -- "$f.$BASHPID"
}
# The test owners (testowners()) as two lines, defs then refs, for snappart.
snapowners() { local defs refs; testowners; printf '%s\n%s\n' "$defs" "$refs"; }
# queue.cards: the entries $e of the cards' record (null: not read) that no card of the records $c took, in the
# record's order, each with the test file a Tests page card is about (file, else null: the Foreman's wake names a held
# one whose file fails on main beside a card waiting for main, watch-conveyor.sh). What a card waits on, the rules that skip it and a card given back are read as testpick()
# (lib/testaction.sh) reads them. Another repository's issue is open unless the read of it says closed: $cf, the read
# for these cards (queuedfar(); null: none), else an open issue's. With the open issues not listed ($iss null), an
# issue a card waits on counts as open.
TCQUEUE='def tcqueue($e; $c; $iss; $cf; $shuts; $fu; $rules; $prio):
  if $e == null then null else
    ([$c[] | {key: .card, value: true}] | from_entries) as $have
    | ([$c[] | select(.step == "landed" or (.step == "closed" and ((.reason // "") | IN($shuts[]) | not))) | {key: .card, value: true}] | from_entries) as $ended
    | landed($c) as $done | [$c[] | select(.x.followups) | {issue, followups: .x.followups}] as $fc
    | (if $iss == null then null else [$iss[].number] end) as $open | (([($iss // [])[].far // {}] + [$cf // {}]) | add) as $far
    | def ended($d): ((first($e[] | . as $x | select($d | IN($x.id, $x.card, ($x.was // [])[]))) | .card) // $d) as $k | $ended[$k] != null;
    [$e[] | select(.card == null or $have[.card] == null) | (.labels // [$prio[-1]]) as $l
      | {card: .id, title: (.title // "")[0:200], kind: (.label // (if .file != null then "Tests page" else "Card" end)),
         priority: level($l; $prio), created: .time, held: (.held == true), file: ((.file | strings) // null),
         waitsFor: ([ups($fc; needs)[] | select(($open == null or IN($open[])) and (IN($done[]) | not))]
           + [farneeds[] as $r | select($far[$r].open != false) | $r]
           + [.body // "" | splits("\r?\n") | select(test("^\\s*Depends on:")) | scan("c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]*-[0-9]+(?![A-Za-z0-9_])")
              | select(ended(.) | not) | (capture("-(?<n>[1-9][0-9]*)$").n | tonumber) // .] | unique),
         rule: (([$l[] | select(IN(($rules.never // [])[]))] | sort | .[0])
           // (if $rules.followups == false and ($l | index($fu)) != null then "follow-ups" else null end))}]
  end;'
# The state now of each issue of another repository that a `Depends on:` line of a waiting card with no GitHub issue
# names, as {"owner/repo#N": {open}} (farstates()), as testpick() asks it. No open issue need name it, so the open
# issues' reads alone left it open for good. Fails when the record or the card records cannot be read.
queuedfar() {
  local have rec
  [ -s "${TACARDS:-}" ] || return 0
  have=$(stdb ask issue cards 0) \
    && rec=$(printf '%s\n%s\n' "$(jq -c '.cards | arrays' "$TACARDS" 2>/dev/null)" "$have" | jq -Rcn 'input | fromjson as $r
      | ([inputs | fromjson? | objects | .card | strings] | INDEX(.)) as $have
      | $r | map(select(.card == null or $have[.card] == null) | {body})' 2>/dev/null) \
    && rec=$(farstates "$rec") && jq -c '[.[].far // {}] | add // {}' <<<"$rec"
}
# <folder>: queuedfar's answer kept in the GitHub folder as cardfar, beside the issues; no file when it cannot be read.
# With no record of the cards nothing runs.
queuedfarkeep() {
  [ -s "${TACARDS:-}" ] || return 0
  queuedfar > "$1/cardfar.new" && mv -f "$1/cardfar.new" "$1/cardfar" || rm -f "$1/cardfar.new" "$1/cardfar"
}
snapshot() (
  next=null; held=null; built=null; queue=null; yes=$YES
  lintyes=$LINTYES
  # A stop (TERM, INT, HUP) ends the snapshot once the command it runs has ended. A reader's timeout sends TERM to the
  # whole process group; one that comes as the shell starts a command reaches the shell after the fork and never the
  # new command. With no trap of its own, the shell then runs the EXIT trap at once, and the scratch folder is removed
  # under that command (cardruns.py failed with FileNotFoundError on cardruns.jq, #359). The link to the kept copy of
  # the card records that snapcopy made goes with it.
  d=$(mktemp -d) || exit 1; trap 'rm -rf -- "$d" "$STATE.copy.r$BASHPID"' EXIT; trap 'exit 143' TERM INT HUP
  # The issues first: a new one is held (adopt) before the copy, so the snapshot never shows it in the queue. When
  # its hold cannot be saved, the issues are not known: a new issue is never shown queued when it is not held.
  # The loop's own list (ISSUES, asked of GitHub before each pick, a shut card's issue taken out: run.sh) is read in
  # place of the feed's copy when it is newer: a new issue shows at the loop's next pick, not the feed's next read.
  saw=$(clock) || exit 1
  if [ -n "$GITHUB" ] && [ -s "$ISSUES" ] && [ "$ISSUES" -nt "$GITHUB/issues" ]; then issues=$(<"$ISSUES")
  else issues=$(openissues "$FIELDS" 2>/dev/null) || issues=''; fi
  snapcopy "$issues"; case $? in 0) ;; 3) issues='' ;; *) echo "conveyor: cannot copy the card records" >&2; exit 1 ;; esac
  # READ is the kept copy of the card records (snapcopy's link) and READG its lineage and size, which the check, the
  # rows and the summaries of READ (linesum(), lib/records.sh) read in place of a sum of the whole copy.
  # shellcheck disable=SC2034 # read by endedrecs() (lib/records.sh)
  READ_ENDED=$d/ended.jsonl
  READ=$STATE.copy.r$BASHPID; READ_OLD=$d/${RETRIED##*/}; CONTROL=$d/control.json; LIVEJSON=$(live); : "${LIVEJSON:={\}}"
  { read -r READG < "$d/lineage"; } 2>/dev/null || READG=''
  # The control record read once, in this shell: the readers below (health's among them) find it kept (ctlread).
  if ctlread 2>/dev/null; then control=$CTL_V; else control=null; fi
  # A plain assignment inside the subshell, never a prefix on the call: a prefix would put the whole issue list in the
  # environment of every command health runs, and past the kernel limit each one fails with "Argument list too long".
  # The rows before health: health's summaries of the records go stale with the rows' one, and snaprows says so first.
  # The check before the rows: a line that does not check is set aside (and dropped from READ) before rows.jq reads it,
  # else one bad line stops the snapshot (#290). READ is this snapshot's own copy, so health need not check it again.
  # The copy's lineage and size (READG) go to the rows unless the check dropped a line from the copy (it empties
  # READG): it is then no longer the copy kept, and the rows are checked against the copy's bytes instead.
  # shellcheck disable=SC2034 # READCHECKED is read by health (lib/views.sh), which conveyor.sh sources beside this file
  check && READCHECKED=1 && snaprows "$READ" "$STATE.rows" "$d/rows" "${READG% *}" "${READG#* }" || exit 1
  # The machine's test-slot pool (lib/slots.sh slot_pool) read once, in this shell: health's cores and the slots in
  # use below read it. SLOTSREAD says it was read.
  SLOTSREAD=''; ! slot_pool >/dev/null 2>&1 || SLOTSREAD=1
  # A snapshot that reads GitHub itself (no `watch` feed, GITHUB unset: the Board's ssh path) reads the CLIs' models
  # too, as github() does for the feed, when the host's report is missing or CLI_TTL old; else a host the loop has
  # never run on offers each CLI with no models.
  [ -n "$GITHUB" ] || hostclis due >/dev/null 2>&1 || :
  # The host's report, the models.allowed in force and the Claude routes, worked out once in this shell (HOST_K,
  # MODELS_K, ROUTES_K; modelsallowed reads the host's report): health, modelsettings, each seat and the guard's
  # accounts below run in subshells, and each would work them out again with its own jq runs.
  modelsallowed allowed 2>/dev/null || :; routesnow >/dev/null
  # shellcheck disable=SC2034 # read by health (lib/views.sh), which conveyor.sh sources beside this file
  # The plan of Record test times joins health (timesadd(), lib/setup.sh), while the last card test runs recorded none.
  h=$(ISSUESJSON=${issues:-null}; health) && h=$(timesadd "$h") && printf '%s\n' "$h" > "$d/health" || exit 1
  snaprows "$READ_OLD" "$RETRIED.rows" "$d/old" 2>/dev/null || { echo "conveyor: $RETRIED does not read as card records; stopping" >&2; exit 1; }
  models=$(jq -c .models <<<"$h"); settings=$(modelsettings "$control"); ACCT=$(ctlacct "$control")
  # A main-red fix card is titled from its entry as it is now (redfix.sh redtitles()), so a case added while it runs shows.
  # One card a line: the pricing below prices only the lines that changed since the last snapshot.
  # A bug card's check of its new tests on main's code (proofs()) runs between two steps, no start line before it: while
  # it runs (its live record there, the card open, its last line no start), it is the card's proof, the step in progress.
  # A step that waits for its seat's CLI (seatwait(), its live record's cli) is shown with no start line before it too:
  # the judge's check of a test file for hollow cases waits after the build line.
  # A running step whose result named the models that ran it keeps their split (stats.byModel, watch()): its live part is priced at each one's rate.
  # The archived cards' rows come first (archrows): the cards are those of allrecs, archive then live records.
  archrows "$d" "$d/arows" "$d/apushes" && cat -- "$d/apushes" >> "$d/pushes" || exit 1
  allrows=$d/rows; [ "$(head -c 2 "$d/arows")" = '[]' ] || { jq -cs 'add' "$d/arows" "$d/rows" > "$d/allrows" && allrows=$d/allrows; } || exit 1
  jq -c --argjson m "$models" --slurpfile livef <(printf '%s' "$LIVEJSON") --argjson proof "$(proofs)" --argjson away "$(aways)" --argjson capoff "$(offcaps)" --argjson red "$(redtitles)" --slurpfile old "$d/old" '$livef[0] as $live | (map($live[.card] as $v | $proof[.card] as $p
      | .title = ($red[.card] // .title) | .gaveWay = ($away[.card].to // null) | .gaveWayFixing = ($away[.card].fixing == true) | .offCap = ($capoff[.card] == true)
      | if $v != null and .result == "" and ((.x.log | last | .step == "start" and .of == $v.step) or ($v.cli | type) == "string") then .live = ($v | {step, at, turns, last, usage, files, tests, list, action, waits, before} + (if $v.zero == true then {zero: true} else {} end) +(if $v.model then {model: $v.model} else {} end) + (if ($v.effort | type) == "string" and $v.effort != "" then {effort: $v.effort} else {} end) + (if ($v.stalled | type) == "string" then {stalled: $v.stalled} else {} end) + (if ($v.stats.byModel | type) == "object" then {stats: {byModel: $v.stats.byModel}} else {} end)) else . end
      | if ($p | type) == "object" and .result == "" and (.x.log | last | .step != "start") then .proof = ($p | {at, files, tests, list, action}) else . end)
    + ($old[0] | map(.x.retried = true)) | map(.models = $m))[]' "$allrows" > "$d/all" || exit 1
  # The pack's model prices, added models and aliases (prices) win over the built-in table; a pack that does not read
  # has none. The models the steps of the last 30 days ran are counted from since (seen).
  packget prices pp 2>/dev/null && [ -n "$pp" ] || pp='{}'
  packget auto.standing sk 2>/dev/null && [ -n "$sk" ] || sk=null
  packget push.check pc 2>/dev/null && [[ $pc =~ ^(true|false)$ ]] || pc=null
  { packget lint lc 2>/dev/null && lc=$(jq -c '(.commands // []) | map({run, files})' <<<"${lc:-null}" 2>/dev/null) && [ -n "$lc" ]; } || lc=null
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
  # prices: the Rules tab's Model prices, the built-in rows and aliases, the pack's entries, each model's display name and the
  # model IDs seen in 30 days, and the research lane's model for its mark; null when the table cannot be run.
  { $pricedok && jq -c --argjson o "$pp" --arg rm "$rmodel" '{builtIn: (.table | to_entries | map({model: .key, input: .value[0], output: .value[1], cacheRead: .value[2],
      cacheWrite: (.value[3] // (.value[0] * 1.25))})), aliases, overrides: $o, names, seen, research: (if $rm == "" then null else $rm end)}' "$d/pricedall"; } > "$d/prices" 2>/dev/null \
    && [ -s "$d/prices" ] || echo null > "$d/prices"
  echo null > "$d/issues"; echo null > "$d/upall"
  # The other repositories' issues the waiting cards name: as kept in the GitHub folder (GITHUB), else asked now.
  local cardfar=/dev/null
  if [ -n "$GITHUB" ]; then [ ! -s "$GITHUB/cardfar" ] || cardfar=$GITHUB/cardfar
  elif [ -s "${TACARDS:-}" ] && queuedfar > "$d/cardfar"; then cardfar=$d/cardfar; fi
  # What health reads of the records (HEALTHLINE), from its kept summary (health brought it up to date): the pick
  # order and the slow-test list below both read it.
  linesum "$READ" "$STATE.health" "$d/hrec" "$HEALTHLINE" && hrec=1 || hrec=''
  if [ -n "$issues" ]; then
    printf '%s\n' "$issues" > "$d/issues"
    # The order from what health reads of the records and the retried lines, each from its kept summary (UPREC, UPOLD).
    [ -n "$hrec" ] && linesum "$READ_OLD" "$RETRIED.health" "$d/hold" "$HEALTHLINE" \
      && UPREC=$d/hrec UPOLD=$d/hold upnext "$issues" '' all > "$d/upall" 2>/dev/null && [ -s "$d/upall" ] || echo null > "$d/upall"
    # The release limit, read as a dry pick reads it (rellimit(), lib/pick.sh: no write, no log): while it is on, each
    # issue in order and next that is not that release's gets release, the version it waits for, as the pick leaves it
    # out until the release is out or stopped. Off, or a limit or release record that does not read: no issue gets it.
    rw=null
    if rl=$(DRYPICK=1 rellimit "$issues" 2>/dev/null) && [ -n "$rl" ]; then
      rw=$(jq -ce --slurpfile r "$CARDS/release/run.json" '{issues, version: ($r[0].version | strings)}' <<<"$rl" 2>/dev/null) || rw=null
    fi
    # shellcheck disable=SC2016 # jq text, not shell
    relwait='def relwait: if $rw != null and (.issue | IN($rw.issues[]) | not) then .release = $rw.version else . end;'
    queue=$(jq -c --arg area "$AREA" --argjson rw "$rw" "$relwait"'map({issue: .number, title: (.title // "")[0:200], priority: .p, followup: (.later | not), retried: .again, created: .createdAt,
          areas: ([.labels[].name | select(startswith($area))] | sort), hold, rule, waits, before, forced})
        | {order: map(select((.hold | not) and .rule == null and (.waits == [] or .forced) and (.before | not)) | (if .forced then .waitsFor = .waits else del(.forced) end) | del(.hold, .rule, .waits, .before) | relwait),
           holding: map(select(.hold) | .waitsFor = .waits | del(.hold, .rule, .waits, .areas, .before, .forced)),
           skipped: map(select(.rule != null) | {issue, title, rule}),
           waiting: map(select(.waits != [] and (.hold | not) and .rule == null and (.before | not)) | del(.hold, .rule, .areas, .before) | .waitsFor = .waits | del(.waits))}' "$d/upall") && [ -n "$queue" ] && [ "$queue" != null ] || queue=null
    # The pick order is that whole list less what a pick leaves out (upnext.jq), not a second reading of the records.
    next=$(jq -c --argjson rw "$rw" "$relwait"'map(select((.hold | not) and .rule == null and (.waits == [] or .forced) and (.before | not))) | .[:10] | map({issue: .number, title: (.title // "")[0:200], priority: .p, followup: (.later | not), retried: .again} + (if .forced then {forced: true, waitsFor: .waits} else {} end) | relwait)' "$d/upall") \
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
  # line holds only the first 200. A card whose patch cannot be read has its line's list. No such card: no jq.
  [ -s "$d/yes" ] && while IFS=$'\t' read -r c k; do
    [ -r "$k/$c.patch" ] || continue
    git apply --numstat -z "$k/$c.patch" 2>/dev/null | jq -Rcs --arg c "$c" '{($c): (split("\u0000") | map(select(. != "") | split("\t") | .[2:] | join("\t") | .[0:300])) | select(length > 0)}' 2>/dev/null
  done < "$d/yes" | jq -cs 'add // {}' > "$d/paths" 2>/dev/null || echo '{}' > "$d/paths"
  # The project's own screenshots each such card kept (keepshots(), lib/push.sh), and the hash of its kept patch now:
  # the Board shows them only while the two hashes are one.
  [ -s "$d/yes" ] && while IFS=$'\t' read -r c k; do
    [ -r "$k/shots/shots.json" ] || continue
    jq -c --arg c "$c" --arg p "$(git hash-object -- "$k/$c.patch" 2>/dev/null)" \
      'objects | {($c): {patch: (if $p == "" then null else $p end), shots: {patch, shots}}}' "$k/shots/shots.json" 2>/dev/null
  done < "$d/yes" | jq -cs 'add // {}' > "$d/shots" 2>/dev/null || echo '{}' > "$d/shots"
  # Each blocked land-branch card of issue 0 whose branch's change is already on main (another card landed the same
  # change): the branch merged into main gives main's own tree, as landbranch() finds "nothing to land". Needs you says
  # it can be shut. A branch whose tip main's history holds merges into main's tree whatever main did since (a revert
  # of its change too): main must still hold its change (branchon(), from main's commit the card was picked against).
  # A card picked by an engine that kept no such commit (no base) is read against the commit block() kept beside its
  # kept patch (<kept>/<card>.base: main's commit the card's worktree was on, the branch's change staged on it), as
  # the records name it, never one guessed from main's history: with neither, it is not said to be on main, unless the
  # tip is main's own tip (main's tree is then the tip's own).
  # The cards come from the rows (rows.jq: step is the closing step, x.branch and x.base the picked line's branch and
  # main's commit, kept the kept patch's folder, kept/<card> in the state folder), and a branch that is gone is not said to be on main. The fields are
  # split on the unit separator, not on a tab: read joins tabs, so an empty field would move the rest.
  # The same jq gives the landed commits of the cards of issue 0, each after a record separator, for soff (below).
  mc=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null) && mtree=$(git rev-parse -q --verify "$mc^{tree}" 2>/dev/null) || mtree=''
  on=$({ [ -n "$mtree" ] && jq -r '.[] | select(.issue == 0) | if .step == "landed" then .sha | strings | "\u001e\(.)"
        elif .step == "blocked" and (.x.branch | type) == "string" then [.card, .x.branch, (.x.base | strings // ""), (.kept | strings // "")] | join("\u001f")
        else empty end' "$d/rows" 2>/dev/null; } \
    | while IFS=$'\x1f' read -r c b base k; do
        [[ $c != $'\x1e'* ]] || { printf '%s\n' "${c#?}" >> "$d/landed0"; continue; }
        tip=$(git rev-parse -q --verify "refs/heads/$b^{commit}" 2>/dev/null) || continue
        if git merge-base --is-ancestor "$tip" "$mc" 2>/dev/null; then
          [ -n "$base" ] || [ -z "$k" ] || base=$(cat -- "$ST/$k/$c.base" 2>/dev/null) || base=''
          if [ "$tip" = "$mc" ] || { [ -n "$base" ] && branchon "$tip" "$base" "$d"; }; then printf '%s\n' "$c"; fi
        elif t=$(git merge-tree --write-tree "$mc" "$tip" 2>/dev/null) && [ "${t%%$'\n'*}" = "$mtree" ]; then printf '%s\n' "$c"; fi
      done)
  # No card on main: no jq to write the empty list.
  if [ -z "$on" ]; then echo '[]'; else jq -Rcs 'split("\n") | map(select(. != ""))' <<<"$on" 2>/dev/null || echo '[]'; fi > "$d/onmain"
  # The landed commits of cards with no GitHub issue that main does not hold (offmain()): a split's slice card landed
  # with one is not landed (sliceCards, below), as umbrellas() does not count it. Main unread: none is left out. As
  # offmain() prints whole commit ids, the shell writes their list for jq.
  soff=$([ -z "$mc" ] || [ ! -s "$d/landed0" ] || offmain "$mc" < "$d/landed0") || soff=''
  soffj=''; for sc in $soff; do [[ ! $sc =~ ^[0-9a-f]+$ ]] || soffj+=${soffj:+,}\"$sc\"; done
  # Today and the 7 days are reckoned from the health record's time (CONVEYOR_NOW when set), as now is.
  # Each of the three days with its midnight's epoch (t0d, t0w, t0p), from one date program: day by bash's own printf.
  ht=$(jq -r '.time | fromdate' <<<"$h") && [[ $ht =~ ^[0-9]+$ ]] && printf -v day '%(%F)T' "$ht" \
    && { read -r day t0d && read -r since t0w && read -r prev t0p; } < <(printf '%s\n' "$day" "$day 6 days ago" "$day 13 days ago" | p_dates '+%F %s') \
    && [[ $t0p =~ ^[0-9]+$ ]] || exit 1
  # A failure stands only while the pack still names a whole test (maintest() runs none without one, so nothing clears
  # it) and, when the open issues were listed, while the issue it filed is open. It goes to jq in a file (--slurpfile):
  # the failure of a few hundred cases passed the system's limit on one argument (--argjson), and no snapshot was made.
  packget test.main mt && [ -n "$mt" ] && mt=$(jq -ce --slurpfile iss "$d/issues" \
    '.fail | objects | select(.issue == null or $iss[0] == null or (.issue as $n | $iss[0] | any(.number == $n)))' "$MAINTEST" 2>/dev/null) || mt=null
  # The commit of the plugin's main (or newest release) this machine did not take, while the pack follows it (take(), lib/install.sh).
  packget plugin.follow eng && [ -n "$eng" ] && eng=$(jq -ce '.refused | objects | {commit, reason, since}' "$ENGINE" 2>/dev/null) || eng=null
  # The keys of the kept Tests page parts, read before any of them reads its inputs (snapkeys()).
  snapkeys "$since"
  # The test owners, read once (kept: snappart()): testspart, below, reads these too.
  local defs='{}' refs='{}'
  snappart owners "$SK_OWNERS" "$d/owners" snapowners && { IFS= read -r defs && IFS= read -r refs; } < "$d/owners" || testowners
  fl=$(jq -ce --slurpfile h "$d/health" --argjson days "$FLAKY_DAYS" --slurpfile defs <(printf '%s' "$defs") --slurpfile refs <(printf '%s' "$refs") '$h[0] as $h | '"$OWNERS"'($h.time | fromdate) as $t | [.filed | arrays | .[] | objects] as $f
    | [.entries | arrays | .[] | objects | select((.case | type) == "string" and ((.time | fromdate?) // 0) > $t - $days * 86400)] | group_by(.case)
    | map(.[0].case as $c | {case: $c, count: length, issue: ([$f[] | select(.case == $c) | .issue][-1] // null), files: ($c | caseowners)}) | sort_by(-.count, .case)' "$FLAKY" 2>/dev/null) || fl='[]'
  # The last pass of the test rules, when its burst guard stopped it (testrulespass()).
  [ -s "$TESTRULES" ] && tr=$(jq -ce 'select(.on == true) | .time as $t | .burst | objects | {time: $t, matched, cap}' "$TESTRULES" 2>/dev/null) || tr=null
  # The models the belt runs or offers with no price, as serve's last look found them (noprice()); and, from the same
  # jq, the models of its notes (pnm, below).
  np='' pnm=''
  [ ! -s "$NOPRICE" ] || { IFS= read -r np && IFS= read -r pnm; } < <(jq -c '(try ((.missing | arrays | map(strings) | select(length > 0) | {models: .}) // null) catch null),
    (try [.notes | arrays | .[] | strings | select(startswith("- ")) | capture(" · No built-in price for (?<m>[^ :]+): ").m] catch [])' "$NOPRICE" 2>/dev/null) || :
  [ -n "$np" ] || np=null; [ -n "$pnm" ] || pnm='[]'
  # The plugin problem notes that look made for the models the built-in price table does not price (noprice()), as the
  # Foreman's plugin-bugs.md (foremandir()) holds them now: a note filed since (stop.sh puts "filed as #<n>" at its
  # end, after whatever its FILED takes before it: a comma, a semicolon, white space or none) or taken out (the Board's File and Dismiss) is not given, so no Board adds it again.
  # Nor is a note for a model a filed line names: outside the plugin's own repository stop.sh adds the filed line as a
  # row of its own and leaves the note it files as it was. Each model a filed line there names is given too (priceFiled),
  # whatever project of the group noted it, and even when $NOPRICE names none (that project may have left the group), so
  # a Board on another machine takes out its copy of a note filed here: a note no longer given is not filed for that.
  # So is each model the folder's noprice-noted lists (noprice() puts each model it notes there) with no open note there:
  # the Board's File and Dismiss take the note out of plugin-bugs.md and leave no filed line.
  pn='{"notes":[],"filed":[]}' pnf=''
  if pnf=$(foremandir) && { [ -s "$pnf/plugin-bugs.md" ] || [ -s "$pnf/noprice-noted" ]; }; then
    pn=$({ grep '^- ' "$pnf/plugin-bugs.md" 2>/dev/null || true; } | jq -Rcs --argjson m "$pnm" --arg k "$(cat "$pnf/noprice-noted" 2>/dev/null)" \
      'def mod: capture(" · No built-in price for (?<m>[^ :]+): ").m // null;
      def filed: test("filed as #[1-9][0-9]*[[:space:]]*\\.? · evidence: "; "i");
      [splits("\n") | select(startswith("- "))] as $l | [$l[] | select(filed) | mod | strings] as $f
      | [$l[] | select(filed | not) | mod | strings] as $o
      | {notes: [$l[] | select(filed | not) | select(mod as $x | $x != null and ($m | index([$x]) != null) and ($f | index([$x]) == null))],
         filed: ($f + [$k | splits("\n") | select(test("^(claude|gpt)-[A-Za-z0-9._\\[\\]-]+$")) | select(. as $x | $o | index([$x]) == null)] | unique)}') \
      || pn='{"notes":[],"filed":[]}'
  fi
  # With SNAPNOTES set (snapkeep), the file those notes are read from, an empty line when none is read: a reader of the
  # kept snapshot leaves its notes out once that file changed after its build began (snapprint). Written while the
  # notes' models are known, so a build that finds them all filed names the file the older kept snapshot's came from.
  [ -z "${SNAPNOTES:-}" ] || printf '%s\n' "${pnf:+$pnf/plugin-bugs.md}" > "$SNAPNOTES" || :
  # The full test suite (fulltest()): the run in progress, only while its lock is held by a run or an ask (a run that
  # was killed left its file; fullreap() holds it shared, as this one tries it), and the last line of its record.
  packget test.full ft 2>/dev/null || ft=''
  fr=null; ( flock -n -s 9 ) 9>>"$FULLTEST.lock" 2>/dev/null || fr=$(jq -ce 'objects' "$FULLTEST.running" 2>/dev/null) || fr=null
  ft=$({ tail -n 1 "$FULLTEST" 2>/dev/null || :; } | jq -cs --arg ft "$ft" --slurpfile r <(printf '%s' "$fr") '$r[0] as $r | {command: ($ft != ""),
      why: (if $ft == "" then "the pack names no full test suite (test.full)" else null end), running: $r, last: (map(objects) | last)}' 2>/dev/null) || ft=null
  # The whole-suite runs and main as the Release panel shows it (suites(), releasemain()).
  su=$(suites) || su='[]'; rl=$(releasemain) || rl=null; dr=$(driftof "$d")
  packget foreman.waitWake ww 2>/dev/null && [[ $ww =~ ^[1-9][0-9]*$ ]] || ww=10
  packget push.landAs pla 2>/dev/null || pla=''
  packget push.prMerge ppm 2>/dev/null || ppm=''
  packget pick pef 2>/dev/null && [ -n "$pef" ] || pef='{}'
  sw='' sf='' sa='' sc='' psp=null; packget split.doneWhen sw split.files sf split.areas sa split.chars sc 2>/dev/null \
    && psp=$(jq -ce --slurpfile s "$SCHEMA" '(.split // {}) as $p | $s[0].properties.split.properties as $d | $ARGS.positional as $v
      | [["doneWhen", "files", "areas", "chars"] | to_entries[] | .value as $k | {key: $k, value: {n: ($v[.key] | tonumber),
        from: (if $p | has($k) then "pack" else "default" end), default: $d[$k].default}}] | from_entries' \
      --args "$sw" "$sf" "$sa" "$sc" < "$PACK" 2>/dev/null) || psp=null
  # Each card with its metrics and its runs' sums, then the waits ($d/cards: two arrays, $all[0] and $all[1]), from a
  # summary kept beside the card records ($STATE.cardruns): only the issues whose cards changed are made again.
  printf '%s\n%s\n' "$METRICS" "$CARDRUNS" > "$d/cardruns.jq" \
    && python3 "$HERE/cardruns.py" "$d/priced" "$STATE.cardruns" "$d/cards" "$d/cardruns.jq" "$d/samples" "$ht" "$SAMPLE" "$yes" \
    || exit 1
  # The records of the cards with no GitHub issue (testcard(), lib/testaction.sh), by their card: body, filed and filedUrl, which a landed one shows
  # ($tac); and by their id, the card each has now and all its cards ($tid); and the entries themselves for queue.cards
  # (queued, null when the record is not read): one jq reads all, none when there is no record.
  jq -cn --slurpfile all "$d/cards" --slurpfile hs "$d/health" --slurpfile allp "$d/paths" --slurpfile shots "$d/shots" --slurpfile onm "$d/onmain" --slurpfile mt <(printf '%s' "$mt") \
    --slurpfile tt <({ [ -s "$TACARDS" ] && jq -c '[.cards | arrays | .[] | objects] as $e
      | {tac: (try ([$e[] | select(.card | type == "string") | {key: .card, value: {body: (.body // null), filed: (.filed // null), filedUrl: (.filedUrl // null)}}] | from_entries) catch {}),
         tid: (try ([$e[] | select(.id | type == "string") | {key: .id, value: {card: (.card // null), all: ([.id, .card] + (.was // []) | map(strings))}}] | from_entries) catch {}),
         queued: (if (.cards | type) == "array" then $e else null end)}' "$TACARDS" 2>/dev/null; } \
      || echo '{"tac":{},"tid":{},"queued":null}') \
    --arg shut0 "$SHUT" --arg shut1 "$OWNSHUT" --arg shut2 "$ENGSHUT" --slurpfile soff <(printf '[%s]' "$soffj") --slurpfile fl <(printf '%s' "$fl") --slurpfile ft <(printf '%s' "$ft") --slurpfile su <(printf '%s' "$su") --argjson rl "$rl" --argjson dr "$dr" --argjson eng "$eng" --argjson tr "$tr" --argjson np "$np" --argjson m "$models" --argjson next "$next" --slurpfile built <(printf '%s' "$built") \
    --slurpfile iss "$d/issues" --slurpfile cf "$cardfar" --slurpfile ua "$d/upall" --arg builtl "$BUILT" --arg fu "$FOLLOWUP" --argjson prio "$PRIOS" --arg area "$AREA" --argjson ww "$ww" --arg pla "$pla" --arg ppm "$ppm" --arg pef "$pef" --argjson efforts "$EFFORTS" --argjson psp "$psp" \
    --argjson control "$control" --argjson settings "$settings" --argjson accts "$(acctnames)" --argjson ga "$ga" --slurpfile q <(printf '%s' "$queue") --slurpfile lim "$d/limit" --slurpfile smp "$d/samples" --slurpfile pu "$d/pushes" --argjson every "$SAMPLE" --argjson priced "$pricedok" --argjson pn "$pn" --argjson cr "$cr" --argjson ts "$ts" \
    --argjson max "$MAX_REVIEWS" --argjson wait "$((CLOSE_WAIT + 300))" --arg yes "$yes" --arg lintyes "$lintyes" --arg nobenefit "$NOBENEFIT" --arg day "$day" --arg since "$since" --arg prev "$prev" \
    --argjson t0d "$t0d" --argjson t0w "$t0w" --argjson t0p "$t0p" '$fl[0] as $fl | $ft[0] as $ft | $su[0] as $su | $built[0] as $built | $q[0] as $q
    | [$shut0, $shut1, $shut2] as $shuts | [$tt[0].tac] as $tac | [$tt[0].tid] as $tid | '"$DEPS$LEVEL$INSIDE$TCQUEUE"'
    def day: fromdate | strflocaltime("%Y-%m-%d");
    def usd: if length == 0 then 0 elif any(.usd == null) then null else map(.usd) | add * 10000 | round / 10000 end;
    # The totals: the dollars of the steps that are priced, and how many are left out for having no price.
    def priced: [.[].usd | numbers] | add // 0 | . * 10000 | round / 10000;
    def leftout: map(select(.usd == null)) | length;
    # And how many of the priced ones are priced as an estimate: a figure with one is shown as an estimate (~$4.12).
    def estimated: map(select(.estimate != null)) | length;
    # The dollars of a card beside its usd, which is null while a step of its runs has no price: usdKnown, the dollars of
    # the steps that are priced; notPriced, how many are not; estimate, whether one is priced as an estimate.
    def gap: .runSteps | {usdKnown: priced, notPriced: leftout, estimate: any(.[]; .estimate != null)};
    # The seats of a card (seats, above): the pick of the Judge (the asked of its pick) with the mode of the pick and
    # run, the seats the card runs on that the rule set (pickpromote(), picktrial(), pickseats(), pickjudge(),
    # lib/modelpick.sh), each {model, effort, by}: by card (the owner set the builder), trial (the challenger of the
    # group, at trialEffort when the effort of the Judge moved it), promoted (a promoted challenger, or a seat the owner
    # promoted from a replay) or judge (the seat of the Judge, with the rule On and no failed pick nor guard; for the
    # builder, when the pick says judged, or has no judged and its choice is the builder the Judge chose: a card picked
    # before the pick said judged builds on its choice; a card the rule kept on another builder, that of the project,
    # is not); null for a seat the rule left at the default of the project.
    def seatsof: (.x.pick | objects | select(.asked | objects) | . as $p | .asked as $a
      | ($p.mode == "on" and ($a.failed | type) != "string" and ($a.guard | type) != "string") as $on
      | ($p.choice | objects | select(.model | type == "string") | {model, effort}) as $c
      | $a + {mode, run: ({builder: (if $c == null then null elif $p.by == "owner" then $c + {by: "card"}
            elif $p.trial == true then $c + {effort: ($p.trialEffort // $c.effort), by: "trial"}
            elif $p.promoted == true then $c + {by: "promoted"}
            elif $on and ($p.judged == true or ($p.judged == null and $c == (($a.builder | objects | {model, effort}) // null))) then $c + {by: "judge"} else null end)}
          + ([("reviewer", "judge") as $k | {key: $k, value: (if $p.trial == true then null
              elif ($p.seats[$k].model | type) == "string" then ($p.seats[$k] | {model, effort, by: "promoted"})
              elif $on and ($a[$k].model | type) == "string" then ($a[$k] | {model, effort, by: "judge"}) else null end)}] | from_entries))}) // null;
    def sofar: . as $card | (.live // {} | .usage // null) as $u
      | ((.steps | any(.step != "test")) or (($u // {} | [.[]] | add // 0) > 0)) as $reading
      # atEnd: no reading yet, and every answer of the running Claude session reports usage 0 (its route streams no
      # usage, #391): its cost is shown when the step ends, not "no reading yet".
      | {reading: $reading, atEnd: (($reading | not) and $card.live.zero == true),
         tokens: (.x.tokens | if $u == null then . elif $card.live.step == "review" and ($card.live.model // "" | startswith("claude-") | not) then .codex +=$u.input + $u.output
           else .claude += $u.input + ($u.write // 0) + ($u.write1h // 0) + $u.output end),
         usd: (if ($reading | not) or .usd == null or ($u != null and .live.usd == null) then null else (.usd + (.live.usd // 0)) * 10000 | round / 10000 end)}
      # The running step counts as a step priced, or one not, once it holds a usage.
      + (gap | .usdKnown = ((.usdKnown + ($card.live.usd // 0)) * 10000 | round / 10000) | .notPriced += (if $u != null and $card.live.usd == null then 1 else 0 end));
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
    # reason (why it ended, whole to 800 characters, else its first and last 400 cut at a word, joined by " … ": a reason
    # says what happened at its end, as the block "did not hold after <n> round(s)" does; without the note "; <retried>"
    # the row adds after it), retried (why the loop retried the card itself, else null: apart, so the Board does not
    # read the note as part of the finding of a review block), track}, so the step view shows the steps priorSec counts.
    | ($all[0] | map({key: .card, value: {s: .startedAt, e: .x.endAt, from: .x.from}}) | from_entries) as $byCard
    | ([$all[0][] | .x.from | strings]) as $froms
    | ($all[0] | map(select(.card | IN($froms[])) | {key: .card, value: .}) | from_entries) as $rowOf
    | def secOf($p): if $p.e == null then 0 else ([($p.e | fromdate) - ($p.s | fromdate), 0] | max) end;
      def reasonOf: ("; " + (.x.retriedWhy // "")) as $n | (.reason // "")
        | (if $n != "; " and endswith($n) then .[0:length - ($n | length)] else . end) | if length <= 800 then . else (.[0:400] | sub("\\s+\\S*$"; "")) + " … " + (.[-400:] | sub("^\\S*\\s+"; "")) end;
      def chain($f; $k): if $f == null or $k > 20 or $byCard[$f] == null then {sec: 0, start: null, earlier: []}
        else $byCard[$f] as $p | chain($p.from; $k + 1) as $r
          | {sec: ($r.sec + secOf($p)), start: ($r.start // $p.s),
             earlier: ($r.earlier + [$rowOf[$f] | {card, start: .startedAt, end: .x.endAt, sec: secOf($p), reason: reasonOf, retried: (.x.retriedWhy // null), track: track($max; null)}])} end;
      # The earlier runs of a restarted card ($runsOf) are earlier cards too, each once: its overall time and "Every step" hold them.
      def times: . as $c | chain(.x.from; 0) as $r | ($r.earlier | map(.card)) as $seen
        | [($runsOf[.card] // [])[:-1][] | select(.card | IN($seen[]) | not)] as $more
        | ($r.sec + ([$more[] | secOf({s: .startedAt, e: .x.endAt})] | add // 0)) as $prior
        | {start: ([$r.start, $more[].startedAt, $c.startedAt] | map(strings) | min), pickedAt: .startedAt, priorSec: $prior,
           earlier: ($r.earlier + [$more[] | {card, start: .startedAt, end: .x.endAt, sec: secOf({s: .startedAt, e: .x.endAt}), reason: reasonOf, retried: (.x.retriedWhy // null), track: track($max; null)}]
             | sort_by(.start)),
           totalSec: (if .x.endAt == null then null else $prior + ([(.x.endAt | fromdate) - (.startedAt | fromdate), 0] | max) end)};
    # A follow-up names the card it came from: the issue whose landed line lists it (/units shows "↳ #N").
    ([$all[0][] | select(.x.followups != null) | .issue as $p | .x.followups[] | {key: tostring, value: $p}] | from_entries) as $parents
    | def parent: $parents[.issue | tostring] // null;
    # A part names its parent (the issue it is a GitHub sub-issue of: umbrella, openissues()); an issue that is no part,
    # or all of them when the issues were not listed, has no umbrella field.
      ([$iss[0] // [] | .[] | select(.umbrella != null) | {key: (.number | tostring), value: .umbrella}] | from_entries) as $ums
    | def umbrella: $ums[.issue | tostring] | if . == null then {} else {umbrella: .} end;
      # Why the push failed, on the card: the check that failed and the log of the push first, then its error.
      ($h.pushError // null | if . == null then null
        else [(.check | strings | "\(.) failed"), (.log | strings | "Log: \(.)"), (.reason // "the push of main failed")] | join(". ") end) as $perr
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
    # by anything else that keeps it from the pick order: an issue it waits on, a card of it, a parent), landed (its
    # newest card landed while push is off, not pushed yet: never queued, and the push closes it), or on the belt; the
    # five add up to open. issues lists every open issue, lowest number first (issue, title, priority,
    # labels, created, dependsOn: the numbers its own `Depends on:` lines name (needs, DEPS), the ones `control depends
    # remove` can take off, then the "owner/repo#N" of another repository they name (farneeds), unlike waitsFor, which adds follow-ups and leaves closed ones out), so the Rules tab can
    # list them all with their state. held lists every open issue that is
    # neither queued nor on the belt, each with why (reasons, one or more): you (the control record holds it; with
    # outside: true when someone outside the project opened it, INSIDE, so it waits for a release by the owner), label
    # (the built label, awaiting-deploy, holds it back; label names it), rule (a rule of the
    # control record excludes it; rule names it), standing (the benefit hold, NOBENEFIT in lib/pick.sh: a rule of
    # Conveyor itself, which a line in the issue releases, not Rules; rule names it), waits (an open issue it depends on; waitsFor), card (a card of it
    # is blocked, or landed with the issue still open; step; notPushed: true when it landed while push is off and is
    # not pushed yet) or parent (a follow-up filed before its parent card
    # landed) or approve (it waits for the yes of the owner before its
# build, in "Needs you"). Each also has released: when the owner last released it from the held list of the control
    # record (`control release`, Queue on the Board), else null. null when gh cannot list the issues.
    ($iss[0]) as $open | ($ua[0]) as $up
    # A card landed while push is off (x.after wait) is off the belt: its issue is landed, not pushed (held, below).
    | ([$c[] | select(.result == "" or (.x.after != null and .x.after != "wait")) | .issue]) as $onbelt
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
                (if $e.rule == $nobenefit then {kind: "standing", rule: $e.rule} elif $e.rule != null then {kind: "rule", rule: $e.rule} else empty end),
                (if ($e.waits // []) != [] then {kind: "waits", waitsFor: $e.waits} else empty end),
                (if $e.before then {kind: "approve"} else empty end),
                ([$c[] | select(.issue == $i.number and .result != "")] | last | if . == null then empty else {kind: "card", step: .step, card: .card}
                  + (if .x.after == "wait" then {notPushed: true} else {} end) end)]) as $why
            | (if $why == [] and $e == null and $isfu then [{kind: "parent"}] elif $why == [] and $e == null then [{kind: "other"}] else $why end) as $why
            | select(($i.number | IN($queued[])) | not)
            # The slices of a split made cards with no GitHub issue (splitcards(), lib/slices.sh), each {card: its id,
            # state}: landed (a card of its entry, $tid, landed with its commit on main ($soff: those main does not hold,
            # offmain()) or ended already done on main, as umbrellas() counts it), shut (the card its entry has now was
            # shut by hand) or waiting; null for an issue no such split holds.
            | ([$c[] | select(.issue == $i.number and (.x.split.cards | type) == "array" and .x.split.cards != [])] | last | .x.split.cards
                | if . == null then null else map(. as $d | ($tid[0][$d] // {card: $d, all: [$d]}) as $e
                    | {card: $d, state: (if any($c[]; (.card | IN($e.all[])) and ((.step == "landed" and (.sha | IN($soff[0][]) | not)) or (.step == "closed" and (.reason | IN($shuts[]) | not)))) then "landed"
                        elif any($c[]; .card == ($e.card // $d) and .step == "closed" and (.reason | IN($shuts[]))) then "shut" else "waiting" end)}) end) as $sc
            # Its own hold, once the card of the split closed, is held by the split (split: true): the Board and `foreman status` name it so, never as held by the owner.
            | (if $sc != null and any($why[]; .kind == "card" and .step == "closed") then $why | map(if .kind == "you" then . + {split: true} else . end) else $why end) as $why
            | {issue: $i.number, title: ($i.title // "")[0:200], priority: level($l; $prio), followup: $isfu,
               labels: $l, created: $i.createdAt, parent: (($i.body // "") | capture("^Follow-up to #(?<n>[0-9]+)") | .n | tonumber) // null, reasons: $why,
               released: ($control // {} | .released // {} | .[$i.number | tostring] // null),
               # The slices of a split issue (the rule Split large issues On), else the parts of a parent (its GitHub
               # sub-issues in this repository): it is their umbrella while it is open.
               umbrella: (([$c[] | select(.issue == $i.number and (.x.split.filed | type) == "array")] | last | .x.split.filed)
                 // ([($i.parts // [])[].number | numbers] | if . == [] then null else . end)),
               sliceCards: $sc}] as $hl
        | ($hl | map(select((.reasons | map(.kind) | unique) == ["you"])) | length) as $you
        | [$hl[] | select(any(.reasons[]; .notPushed == true)) | .issue] as $unpushed
        | {count: ($open | length), held: $hl,
           # Each open parent (an issue with GitHub sub-issues) as one entry: its parts, how many of them are done
           # (closed, or landed and not pushed) of all, those on the belt, and the closed ones (the Board shows them as landed).
           umbrellas: [$open[] | select((.parts // []) != []) | {issue: .number, title: (.title // "")[0:200], parts: [.parts[].ref],
             done: ([.parts[] | select((.open | not) or (.number | IN($unpushed[])))] | length), all: (.parts | length), inFlight: [.parts[].number | numbers | select(IN($onbelt[]))],
             closed: [.parts[] | select(.open | not) | .ref]}],
           issues: ([$open[] | (.labels | map(.name)) as $l | {issue: .number, title: (.title // "")[0:200], priority: level($l; $prio), labels: $l, created: .createdAt, dependsOn: (needs + farneeds)}] | sort_by(.issue)),
           split: {queued: (($open | length) - ($hl | length) - ([$open[] | select(.number | IN($onbelt[]))] | length)), you: $you,
                   labelOrRule: (($hl | length) - $you - ($unpushed | length)), landed: ($unpushed | length), belt: ([$open[] | select(.number | IN($onbelt[]))] | length)}} end) as $openpart
    # Why an open issue that others wait on does not move (waitsOn in queue.waiting): its newest card first, then
    # a hold of the control record, a label, a rule, the yes of the owner, its own wait, the pick order; else no card.
    # "shut": its newest card was shut by the owner or the engine ($shuts[1:], OWNSHUT and ENGSHUT; lib/issues.sh): its
    # issue stays open and no turn picks it until `retry` gives it back, so nothing builds it (shutDeps in Needs you).
    | def shutcard($n): [$c[] | select(.issue == $n)] | last | if . != null and .step == "closed" and (.reason | IN($shuts[1:][])) then . else null end;
      def depstate($n): ([$c[] | select(.issue == $n)] | last) as $k
        | ($up // [] | map(select(.number == $n)) | .[0]) as $e
        | if $k != null and $k.result == "" then "building"
          elif shutcard($n) != null then "shut"
          elif $n | IN(($control // {} | .held // [])[]) then "held"
          elif $k != null and $k.step == "blocked" then (if $k.reason // "" | startswith($yes) or startswith($lintyes) then "waiting for a yes" else "blocked" end)
          elif $open // [] | any(.[]; .number == $n and any(.labels[]; .name == $builtl)) then "held"
          elif $e.rule != null then "skipped by a rule"
          elif $e.before then "waiting for a yes"
          elif ($e.waits // []) != [] and ($e.forced | not) then "waiting for \($e.waits | map(if type == "number" then "#\(.)" else . end) | join(", "))"
          elif $n | IN(($q.order // [] | map(.issue))[]) then "queued"
          else "open, no card" end;
    # The groups of the rule Pick settings that had trial cards (picktrial(), lib/modelpick.sh), each with the decision
    # of the owner on it (picks in the control record, `control pick`). A card here is one that no later run of its issue
    # follows, picked by auto in a run of it, with the spend of all its runs, as picks counts them, but a run on another challenger: a trial card when a
    # run of it was a trial; else a promoted card when its newest pick is promoted (pickpromote(): by its mark, not its
    # choice, as the builder of the project can be the challenger too); else a default card when that pick is by auto. A group
    # is here when it had a trial or a promoted card, so a group promoted before any trial gets its cost check too; its
    # challenger is the choice of its trial or promoted runs (a retry of a trial card builds on the default).
    # Each side: cards, landed, ended (landed, closed or blocked, and not given
    # back), usd (null when a step has no price, or is priced as an estimate: a guess never decides over) and perLanded (usd / landed: null with none landed, or usd null).
    # due: when the tenth trial card ended after the last decision of the owner (of all of them, before the first), while the
    # owner has not promoted or dropped the challenger; else null. over: in a group promoted now (also while its next
    # challenger is on trial), promoted cards of the choice promoted now cost more per landed card than default cards (modelpick() then sets the rule to shadow, with back, the Needs you line, as its reason).
    def dollars: if . == null then "not known" else (. * 100 | round) as $c | "$\($c / 100 | floor).\($c % 100 | tostring | if length == 1 then "0" + . else . end)" end;
    ([$all[0][] | select(.card | IN($later[]) | not) | ($runsOf[.card] // [.]) as $rs | ($rs | map(.x.pick | objects)) as $ps
        | select(any($ps[]; .by == "auto"))
        | ($ps | map(select(.trial == true or .promoted == true)) | last | .choice) as $chc
        | {group: ($ps | last | .group), trial: any($ps[]; .trial == true), promoted: ($ps | last | .promoted == true), by: ($ps | last | .by),
           challenger: $chc,
           landed: ((.step | IN("landed", "closed")) and .x.blockedAt == null), ended: (.result != "" and (.x.retried | not)),
           # Not the spend of a run on another challenger (one the owner replaced before a retry): it does not count for this one.
           end: .x.endAt, usd: ([$rs[] | select((.x.pick | objects | (.trial == true or .promoted == true) and [.choice.model, .choice.effort] != [$chc.model, $chc.effort]) // false | not) | .steps[]
             | if .estimate != null then .usd = null else . end] | usd)}]
      | group_by(.group) | map(select(any(.[]; .trial or .promoted)))
      | map(.[0].group as $g | ($control // {} | .picks // {} | .[$g // ""]) as $d
        # A group whose next challenger the owner put on trial (`control pick <group> next`) has it as its challenger,
        # and its trial side is the trials of that one only.
        | ($d.challenger // (map(.challenger | objects) | first)) as $ch
        | map(select((.trial | not) or $d.challenger == null or ([.challenger.model, .challenger.effort] == [$ch.model, $ch.effort])))
        | def side: {cards: length, landed: (map(select(.landed)) | length), ended: (map(select(.ended)) | length),
            usd: (map(.usd) | if any(. == null) then null else add // 0 | . * 10000 | round / 10000 end)}
            | .perLanded = (if .landed > 0 and .usd != null then .usd / .landed * 10000 | round / 10000 else null end);
        (map(select(.trial and .ended and ($d == null or .end > $d.at))) | sort_by(.end)) as $since
        | map(select(.trial | not)) as $rest
        # The choice promoted now: the one kept while the next is on trial, else the promoted challenger. The promoted
        # side is its cards only, not those of a choice the owner replaced since (promote after next).
        | (if $d.promoted != null then $d.promoted elif $d.decision == "promote" then $ch else null end) as $pc
        | {group: $g, model: $ch.model, effort: $ch.effort, decision: ($d.decision // null), decidedAt: ($d.at // null),
           trial: (map(select(.trial)) | side), default: ($rest | map(select((.promoted | not) and .by == "auto")) | side), promoted: ($rest | map(select(.promoted and $pc != null and [.challenger.model, .challenger.effort] == [$pc.model, $pc.effort])) | side),
           due: (if ($d.decision // "" | IN("promote", "drop")) or ($since | length) < 10 then null else $since[9].end end)}
        | .over = ($pc != null and .promoted.perLanded != null and .default.perLanded != null and .promoted.perLanded > .default.perLanded)
        # The commands named are those that end the promoted choice: while the next challenger is on trial, keep keeps
        # the promoted choice and drop goes back to it, so promote (the next one in its place) or a second drop (no trials).
        | if .over then .back = "Promoted cards of \(.group) on \($pc.model) at \($pc.effort) effort cost \(.promoted.perLanded | dollars) for each landed card, more than the \(.default.perLanded | dollars) of its default cards. Conveyor set Pick settings to Shadow. Before you set it to On again, "
            + if $d.promoted != null then "choose promote or drop for the group. promote builds on \($ch.model) at \($ch.effort) effort in its place: conveyor.sh control pick \(.group) promote. drop, two times, ends the trials and builds on the defaults: conveyor.sh control pick \(.group) drop, then conveyor.sh control pick \(.group) drop."
              else "choose keep or drop for the group: conveyor.sh control pick \(.group) keep or drop." end else . end)) as $pg
    | {time: $h.time, day: $day, repo: $h.repo,
       needsYou: {
         waiting: [$c[] | select(.step == "blocked" and (.reason | startswith($yes) or startswith($lintyes)))
           # A stop for a lint policy change alone says so, whatever the reviewer said is visible (the rule on visible
           # changes off); a visible stop that changes lint policy too keeps the policy files after the sentence of the review.
           | {card, issue, title, sentence: (if .reason | startswith($lintyes) then .reason | ltrimstr($lintyes)
               else .reason as $r | (.x.visible | select(startswith("yes: ")) | .[5:] + (($r | capture("(?<p>; it also changes lint policy: [^;]*)$").p) // "")) // (.reason | ltrimstr($yes)) end), since: .x.endAt, parent: parent, reviews: reviews, track: track($max; $perr), metrics, doneWhen: .x.doneWhen, split: .x.split, seats: seatsof, stalls: .x.stalls,
              files: (($allp[0][.card] // .x.paths) as $p | {count: (.x.diff.files // ($p | if . == null then null else length end)), paths: $p})}
             # The screenshots it kept, beside the hash of its kept patch now (the Board shows them while the two are one).
             + ($shots[0][.card] // {patch: null, shots: null})
             # A follow-up whose change goes beyond the yes up its chain: what goes beyond, as its reviewer said (the ask).
             + ((.reason | capture("\\(it goes beyond the yes of #(?<from>[0-9]+): (?<what>.*)\\)") | {beyond: {from: (.from | tonumber), what}}) // {})
             + times],
         blocked: [$c[] | select(.step == "blocked" and (.reason | startswith($yes) or startswith($lintyes) | not))
             | {card, issue, title, reason, tail, since: .x.endAt, parent: parent, reviews: reviews, track: track($max; $perr), metrics, doneWhen: .x.doneWhen, split: .x.split, seats: seatsof, stalls: .x.stalls}
             # A land-branch card with the change of its branch already on main ($onm) says so apart from its reason,
             # which the Board reads by its form (the finding of a review, the failing tests): shut is all it needs.
             + (if .card | IN($onm[0][]) then {onMain: true} else {} end) + umbrella + times]
           # A push that failed again on its next try needs the owner, until a push works: one item, under the card
           # of the last landing not pushed, naming every card not pushed; its tail is what git and the hook said.
           # One that failed its check needs the owner at once: it is not tried again until main moves (checkheld()).
           # Not while its fix card (health pushError.fix: redfix.sh pushred()) leaves the owner nothing to do (its
           # needsYou false: it waits for its pick, is on the belt, or landed with the loop to push it). One that needs
           # the owner names that card (fix).
           + [($h.pushError.kind == "check") as $chk | ($h.pushError.fix | objects // null) as $fx
              | select($h.pushFails >= 2 or $chk) | select($chk and $fx != null and $fx.needsYou != true | not)
              | $h.unpushed as $u | $c[] | select(.card == $u[-1].card)
              | {card, issue, title, reason: ((if $chk then "push blocked: \($h.pushError.check) failed after \($h.pushError | if .issue == 0 then .card else "#\(.issue)" end). A retry will fail too, so the push waits until a fix lands on main"
                   + (if $fx == null then "" else (if $fx.card == null then ". Its fix card is not picked yet" elif $fx.state == "landed" then ". Its fix card \($fx.card) landed" else ". Its fix card \($fx.card) is \($fx.state)" end)
                     + (if $fx.state == "landed" and (($control // {}) | .rules.push? == false) then ", and the rule Push when a card lands is off: push main with Push now" elif $h.loop != true then ", and no loop is running to pick it or push main: start the loop"
                       elif $fx.state == "queued" and $h.state != "running" then ", and the loop is \($h.state), so it picks no card: resume the loop" else "" end) end)
                   else "the push of main keeps failing" end) + ". Not pushed: \($u | map(if .issue == 0 then .card else "#\(.issue)" end) | join(", "))"), tail: ([($h.pushError.log | strings | "Log: \(.)"), ($h.pushError.reason | strings)] | if . == [] then null else join(". ") end),
                 since: $h.pushFailingSince, push: true, check: (if $chk then $h.pushError.check else null end), fix: (if $chk then $fx else null end), unpushed: ($u | map({card, issue})), parent: parent, reviews: reviews, track: track($max; $perr), metrics, doneWhen: .x.doneWhen, split: .x.split} + times],
         before: $h.before,
         engine: $eng,
         testRules: $tr,
         prices: $np,
         # The engine held by a stop signal (state T) for over a minute, as health reads it (engineStopped): it starts
         # no card until a SIGCONT resumes it; the command it gives also resumes each stopped process under it, whose
         # cards make no progress while held (#1106: only foreman status said so).
         # pids: the pid of the engine, then each stopped process under it (health, views.sh).
         stopped: ($h.engineStopped | objects | select(.since | strings | fromdate? | . != null and ($h.time | fromdate) - . > 60)
           | (.pids | map(tostring) | join(" ")) as $p
           | {title: "The engine is stopped", reason: "A stop signal holds the engine (state T), so it starts no card. Run kill -CONT \($p) to resume it and each stopped process under it.",
              since, pid, pids}) // null,
         # The rule Pick settings: one decision a group whose ten trial cards ended ($pg due), with the counts and spend
         # of both sides, and the line of the return of the rule to shadow (pickBack in the control record, modelpick()).
         pick: ([$pg[] | select(.due != null) | {group, title: "Pick settings: decide on \(.model) at \(.effort) effort for \(.group) cards",
             reason: "Trial cards on \(.model): \(.trial.cards), \(.trial.landed) landed, \(.trial.perLanded | dollars) for each landed card. Default cards: \(.default.cards), \(.default.landed) landed, \(.default.perLanded | dollars) for each landed card. Conveyor does not promote by itself. Choose promote, keep or drop: conveyor.sh control pick \(.group) promote, keep or drop.",
             since: .due, time: .due, trial, default}]
           + [$control // {} | .pickBack | objects | {group: null, title: "Pick settings went back to Shadow", reason, since: .at, time: .at}]),
         pipeline: (if $open == null then null else ($control // {} | .held // []) as $mine
           | [$open[] | select((.number | IN($mine[])) and (.body // "" | test("^Follow-up to #[0-9]+ \\(Conveyor card ")))
              | (.body | capture("(^|\n)Cost to every card: (?<c>[^\n]*)").c) as $cost
              | {issue: .number, title: (.title // "")[0:200], cost: $cost, parent: (.body | capture("^Follow-up to #(?<n>[0-9]+)").n | tonumber), since: .createdAt}]
           | sort_by(.issue) end),
         farDeps: (if $open == null then null else
           [$open[] | . as $i | farneeds[] as $r | select($i.far[$r].error != null)
              | {issue: $i.number, title: ($i.title // "")[0:200], ref: $r, reason: $i.far[$r].error,
                 line: ([$i.body // "" | splits("\r?\n") | select({body: .} | farneeds | index([$r]) != null)] | first // "" | sub("^\\s+"; "") | .[0:300])}]
           | sort_by(.issue) end),
         # A wait that cannot end: an issue waiting on one whose card was shut (depstate "shut"), which no card builds.
         # One forced past its wait (`control force`, the dependency guard off) is picked all the same: no wait to flag.
         # A dependency its own Depends on: line names can be removed from that line; an open follow-up of one (waitsFor
         # adds them) is not on it, so the way out is to close the follow-up.
         shutDeps: ($q.waiting // null | if . == null then null else
           [.[] | select(.forced | not) | . as $w | (first($open // [] | .[] | select(.number == $w.issue) | needs) // []) as $own
             | .waitsFor[] | numbers | shutcard(.) as $k | select($k != null)
             | {issue: $w.issue, title: ($w.title // "")[0:200], dependency: $k.issue, card: $k.card, since: $k.x.endAt,
                reason: "#\($w.issue) waits for #\($k.issue)\(if $k.issue | IN($own[]) then "" else ", an open follow-up of a dependency on its Depends on: line" end), but \(if $k.reason == $shuts[1] then "the owner" else "the engine" end) shut its card \($k.card), so no card builds #\($k.issue). Run conveyor.sh retry \($k.issue) to build it, or \(if $k.issue | IN($own[]) then "remove #\($k.issue) from the Depends on: line of #\($w.issue)" else "close #\($k.issue)" end)."}]
           | sort_by(.issue, .dependency) end)},
       mainTest: $mt[0],
       priceNotes: $pn.notes,
       priceFiled: $pn.filed,
       fullTest: $ft,
       suites: $su,
       release: $rl,
       drift: $dr,
       flaky: $fl,
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
         | {card, issue, title, step: $step, waitsOn: $won, gaveWay: (if $landed then null else .gaveWay end), gaveWayFixing: (.gaveWayFixing and ($landed | not)), review: (if $step == "review" then .x.review // (.reviews + 1) else null end), of: $max, stepAt: $stepAt, landed: $landed, offCap: (.offCap == true and ($landed | not)),
         model: (.live.model // {build: $m.claude, fix: $m.claude, review: $m.codex}[$step] // null), effort: (if .live.model then .live.effort // null else null end), tokens: $s.tokens, usd: $s.usd, usdKnown: $s.usdKnown, notPriced: $s.notPriced, estimate: $s.estimate, reading: $s.reading, atEnd: $s.atEnd,
         # A proof run gives what it does now, "waiting for a test slot (2 of 2 in use)" while the slots are full (testrun.sh).
         live: (if .live then {turns: .live.turns, lastOutputAt: .live.last, action: (.live.action // null), at: (.live.at // null)}
           elif .proof then {turns: 0, lastOutputAt: null, action: (.proof.action // null), at: (.proof.at // null)} else null end),
         # What the live stream (watch.py lay()) adds the running step to: the figures of the finished steps, with their known dollars and gap.
         done: ({tokens: .x.tokens, usd} + gap + {reading: (.steps | any(.step != "test")), step: (.x.log | last | if .step == "start" then .of else null end)}),
         # The step that runs now after a stall (stalled, in the live record) has no line yet: its stall is counted here.
         parent: parent, reviews: reviews, track: track($max; $perr), metrics, doneWhen: .x.doneWhen, split: .x.split, seats: seatsof, stalls: (.x.stalls + (if .live.stalled then 1 else 0 end)),
         beyond: (if $landed then null else .x.beyond end)} + umbrella + times],
       queue: {next: ($next | if . == null then null else map(. + {parent: parent} + umbrella + (if $h.room.issue == .issue then {room: $h.room.reason} else {} end)) end), order: ($q.order | if type == "array" then map(. + umbrella + (if $h.room.issue == .issue then {room: $h.room.reason} else {} end)) else null end),
         holding: ($q.holding // null | if . == null then null else map(. + umbrella) end), skipped: ($q.skipped // null | if . == null then null else map(. + umbrella) end),
         waiting: ($q.waiting // null | if . == null then null else map(. + {waitsOn: [.waitsFor[] | numbers | {issue: ., state: depstate(.)}]} + umbrella) end),
         cards: tcqueue($tt[0].queued; $c; $iss[0]; $cf[0]; $shuts; $fu; $control.rules // {}; $prio)},
       open: $openpart,
       control: $control,
       modelSettings: $settings,
       accounts: $accts,
       limits: $ga,
       inFlight: [$c[] | select(.result == "" and .x.accounts != null) | {card, issue, step: .x.at} + .x.accounts],
       areaPrefix: $area,
       packLandAs: (if $pla == "" then null else $pla end),
       packPrMerge: (if $ppm == "" then null else $ppm end),
       packPick: (try {lists: ($pef | fromjson), efforts: $efforts} catch null),
       packSplit: $psp,
       waitWake: $ww,
       forecast: forecast,
       awaitingDeploy: $built,
       landed: [$week | sort_by(.x.endAt) | reverse[] | select((.x.endAt | day) == $day) | {card, issue, title, step, time: .x.endAt, usd} + gap + {reviews: .runReviews, followups: .x.followups,
         parent: parent, rounds: reviews, fixes: .runFixes, track: track($max; $perr), sha, pushed: (if .step == "closed" then null else (.sha | IN($un[]) | not) end), metrics, doneWhen: .x.doneWhen, split: .x.split, seats: seatsof, stalls: .x.stalls, batch: .x.batch, rollout: .x.rollout} + times
         + (if .issue == 0 then $tac[0][.card] // {} else {} end)],
       branches: ([$c[] | select(.x.branch != null and (.step | IN("landed", "closed")) and .x.blockedAt == null)] | group_by([.issue, .title])
         | map(max_by(.x.endAt) | {card, issue, title, step, time: .x.endAt})),
       pushedCards: [$c[] | (.x.log | map(select(.step == "pushed")) | last) as $p | select($p != null and ($p.time | day) >= $since)
         | {card, issue, sha, time: $p.time, day: ($p.time | day)}],
       health: $h,
       testSlots: $ts,
       cost: (($steps | map(select((.time | day) == $day))) as $td | [$week[] | .card] as $wk
         | [$all[0][] | select(.card | IN($wk[])) | .runSteps[]] as $ws | {
         today: (if $priced then $td | priced else null end), todayLeftOut: ($td | leftout), todayEstimate: ($td | estimated), week: (if $priced then $steps | priced else null end), weekLeftOut: ($steps | leftout), weekEstimate: ($steps | estimated),
         perLanded: ($week | if length == 0 or ($priced | not) then null else length as $n | $ws | priced / $n * 10000 | round / 10000 end), perLandedLeftOut: ($ws | leftout),
         perLandedEstimate: ($ws | estimated),
         landedAfter: ($week | {"1": (map(select(.reviews == 1)) | length), "2": (map(select(.reviews == 2)) | length),
           "3": (map(select(.reviews == 3)) | length), more: (map(select(.reviews > 3)) | length)}),
         unpricedSteps: ($steps | leftout),
         unpriced: [$all[0][] | . as $k | .steps[] | select((.time | day) >= $since and .usd == null)
           | {card: $k.card, issue: $k.issue, step, time, why: (.unpriced // "the price table could not be run")}],
         cards: ([$all[0][] | select(.card | IN($later[]) | not) | [.runSteps[] | select((.time | day) >= $since)] as $s | select($s | length > 0)
             | {card, issue, title, state: (if .x.retried then "retried" elif .result == "" then "on the belt" else .step end), runs: .metrics.runs,
                today: ($s | map(select((.time | day) == $day)) | usd), week: ($s | usd), last: ($s | map(.time) | max),
                todayEstimate: ($s | map(select((.time | day) == $day)) | estimated), weekEstimate: ($s | estimated)}]
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
                estimate: ([.[].runSteps[]] | estimated),
                firstTry: ($l | map(select(.metrics.runs == 1)) | length), reviews: ($l | map(.runReviews) | add // 0),
                open: (map(select((.x.retried | not) and (.result == "" or .step == "blocked"))) | length)})),
         # The trials of the rule Pick settings (picktrial(), lib/modelpick.sh), of every card on any day: dropped, a
         # group whose challenger two blocked trial cards dropped, with the challenger and those cards; flagged, a trial
         # card whose change touches pipeline files (pick.pipeline, trialflag()), with those files.
         # A card whose issue was closed while it was blocked (x.blockedAt) still counts: picktrial() counts its blocked line.
         # As picktrial(), a block before the last decision of the owner on the group (`control pick`, keep) does not count.
         trials: {dropped: ([$all[0][] | select((.step == "blocked" or .x.blockedAt != null) and .x.pick.trial == true) | .x.pick.group as $g
               | select((.x.blockedAt // .x.endAt // "") > ($control // {} | .picks // {} | .[$g // ""].at // ""))] | group_by(.x.pick.group)
             | map(select(map(.card) | unique | length >= 2) | {group: .[0].x.pick.group, model: .[0].x.pick.choice.model, effort: .[0].x.pick.choice.effort, cards: (map(.card) | unique)})),
           flagged: [$all[0][] | select(.x.pick.trial == true and (.x.pick.pipeline | type == "array")) | {card, issue, group: .x.pick.group, files: .x.pick.pipeline}],
           groups: $pg}}),
       metrics: {
         today: totals([$all[0][] | select(.x.endAt != null and (.x.endAt | day) == $day)]; [$smp[] | select((.time | day) == $day)]; [$pu[] | select((.time | day) == $day)]; $every; $waits; $t0d; $nowt),
         week: totals([$all[0][] | select(.x.endAt != null and (.x.endAt | day) >= $since)]; [$smp[] | select((.time | day) >= $since)]; [$pu[] | select((.time | day) >= $since)]; $every; $waits; $t0w; $nowt),
         prev: totals([$all[0][] | select(.x.endAt != null and (.x.endAt | day) >= $prev and (.x.endAt | day) < $since)]; [$smp[] | select((.time | day) >= $prev and (.time | day) < $since)];
           [$pu[] | select((.time | day) >= $prev and (.time | day) < $since)]; $every; $waits; $t0p; $t0w),
         days: [range(6; -1; -1) as $k | ($t0d + 43200 - $k * 86400 | strflocaltime("%Y-%m-%d")) as $dd
           | totals([$all[0][] | select(.x.endAt != null and (.x.endAt | day) == $dd)]; []; []; $every; []; 0; 0)
           | {day: $dd, landed, blocked, cycleSec: .cycleSec.p50, firstReviewPass, perLandedUsd: (.perLanded | if . == null or .leftOut > 0 or .estimate > 0 then null else .usd end)}],
         slots: ([$smp[] | select((.time | day) == $day) | . + {hour: (.time | fromdate | strflocaltime("%H") | tonumber)}] | group_by(.hour)
           | map({hour: .[0].hour, slots: ([.[].slots] | add / length | r3), cap: ([.[].cap | numbers] | max)})),
         cards: ([$all[0][] | select((.x.endAt // .stepAt | day) >= $since)
           | {card, issue, title, state: (if .x.retried then "retried" elif .result == "" then "on the belt" else .step end), at: (.x.endAt // .stepAt), sha, metrics}]
           | sort_by(.at) | reverse)}, cols: $cols} + $cr
    # Every object naming a main-red fix card (card) carries its name (rows.jq), as in health: it has no issue.
    | ([$all[0][] | select(.name) | {key: .card, value: .name}] | from_entries) as $nm
    | walk(if type == "object" and (.card | type) == "string" and $nm[.card] then .name = $nm[.card] else . end)' > "$d/out" || exit 1
  # Each issue in Held or Queue gets since from moved.json as this snapshot leaves it; none when the issues were not
  # listed, and moved.json is then left as it was.
  # other: something besides your hold and the rules keeps it in Held; nodep: the same, its dependencies left out;
  # alone: your hold is the only thing that does.
  cols=$(jq -c '.cols as $c | if $c == null then null else [.open.held[] | select(any(.reasons[]; .kind | IN("you", "rule") | not)) | .issue | tostring] as $o
    | [.open.held[] | select(any(.reasons[]; .kind | IN("you", "rule", "waits") | not)) | .issue | tostring] as $nd
    | [.open.held[] | select(.reasons != [] and all(.reasons[]; .kind == "you")) | .issue | tostring] as $y
    | $c | with_entries(.value += {other: (.key | IN($o[])), nodep: (.key | IN($nd[])), alone: (.key | IN($y[]))}) end' "$d/out") || exit 1
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
  # figures, settings and totals (testspart(), lib/testfiles.sh), null when the pack cannot be read. It and testMap are
  # kept while their inputs are unchanged (snappart()).
  snappart tests "$SK_TESTS" "$d/tests" testspart "$since" 2>/dev/null && [ -s "$d/tests" ] || echo null > "$d/tests"
  # testMap: the Test map part (mapboard(), lib/testmap.sh).
  snappart testmap "$SK_MAP" "$d/testmap" mapboard "$MAIN" 2>/dev/null && [ -s "$d/testmap" ] || echo null > "$d/testmap"
  # bench: the Benchmarks tab's live part, board.json of `conveyor.sh bench swe` (bench/swe.sh); a run in progress whose process
  # is gone (killed with no end written) is shown stopped, and soloKey is the key of the builder seat in force now
  # (swe_solokey()), not the one board.json kept from its last write.
  # versions is the list now (swe_versionsnow(): a source on this machine is read from its local refs on each snapshot,
  # with no network call; a source named by URL is read again only when the source or the hour changes), with no run
  # needed: before the first run, the part holds the versions alone. It is put in by the jq that adds the part.
  echo null > "$d/bench"
  bv=$(. "$HERE/bench/swe.sh" && swe_versionsnow 2>/dev/null) && [ -n "$bv" ] || bv=null
  if [ -s "$ST/bench/swe/board.json" ]; then
    bp=$(jq -r 'objects | .live | objects | select(.state == "running") | .pid | numbers' "$ST/bench/swe/board.json" 2>/dev/null) || bp=''
    bf=objects; [ -z "$bp" ] || kill -0 "$bp" 2>/dev/null || bf='.live.state = "stopped" | .live.current = null | .live.active = null'
    bk=$(. "$HERE/bench/swe.sh" && swe_solokey "$(swe_solomodel)") || bk=''
    jq -c --arg bk "$bk" "$bf"' | if $bk == "" then . else .soloKey = $bk end' "$ST/bench/swe/board.json" > "$d/bench.new" 2>/dev/null && [ -s "$d/bench.new" ] && mv -f "$d/bench.new" "$d/bench"
  fi
  jq -c --slurpfile bn "$d/bench" --argjson bv "$bv" --slurpfile tm "$d/testmap" --argjson mv "${moved:-null}" --slurpfile dec "$d/declined" --slurpfile sh <(healssnap) --slurpfile ta <(testacts) --argjson tl "${TESTACTION_TIMEOUT:-null}" --slurpfile tp "$d/tests" --slurpfile pr "$d/prices" --argjson sk "$sk" --argjson pc "$pc" --argjson lc "$lc" \
    --slurpfile rp <({ tail -n 1 "$REPLAYS" 2>/dev/null || :; } | jq -c 'objects' 2>/dev/null) '$ta[0] as $ta | del(.cols) | .declined = $dec[0].shown | .declinedRest = $dec[0].rest | .selfheals = $sh[0] | .prices = $pr[0] | .standing = $sk | .pushCheck = $pc | .lintCommands = $lc
    | .cost.replay = ($rp[0] // null | if . == null then null else del(.calls) end)
    | .testActions = {seat: (.control // {} | .tests // null), limit: $tl, actions: $ta, allowed: ((.modelSettings | objects | .builder.allowed) // null)} | .tests = $tp[0] | .testMap = $tm[0] | .bench = ($bn[0] | if $bv == null then . else (objects // {}) | .versions = $bv end) | def since: . + {since: $mv[.issue | tostring].at};
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
    | .landedEstimate = ([.landed[] | select(.estimate == true)] | length)
    | [.belt[] | select(.landed == true) | .card] as $on
    | .landed |= [to_entries[] | select(.key < $k or (.value.card | IN($on[]))) | .value]
    | (.metrics.cards, .cost.cards, .cost.unpriced, .declinedRest) |= .[:$k]
    | .branches |= (sort_by(.time) | reverse | .[:$k] + [.[$k:] as $o | $lk[] as $l
        | first($o[] | select(.issue == $l.issue and ($l.issue != 0 or .title == $l.title)))] | unique_by(.card) | sort_by(.time) | reverse)
    | .pushedCards |= (sort_by(.time) | reverse | .[:$p])' "$d/full"
)
# lanekeys -- what the Board finds the card that landed a lane's change by (dashboard_panels.sh landing()), for each lane of
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
