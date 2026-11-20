#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# dashboard.sh [--install|--uninstall|--restart|--loop|--publish|--update|--history|--work|--older|--donewhen|--shot|--excerpts|--bench] -- the collector of the Conveyor dashboard (the
# strip-down to Conveyor). It writes one file, data.js in dashboard/ of the state folder (`conveyor.sh state-dir`)
# (`window.DASH = {...};`), which the static page in .claude/dashboard/ reads, through the page server's /events as it
# changes, or every 15 s when that stream is not open, and beside it limit.json, the usage limit alone, which the
# plugin's pane in Claude Code reads. No model call, ever.
# No argument collects once; --loop collects every 60 s, serves the page (dashboard_server.py), runs the live Conveyor
# feed (dashboard_stream.py) and is what --install runs as a user service; between cycles it also runs
# sync-install.sh when it is beside this script (a release folder has none), which reinstalls the main checkout's
# packages when they no longer match its lockfiles, and --update, which brings the main checkout forward to
# origin/main and restarts the service on new code.
# The live feed: Conveyor's part comes from one long-lived `conveyor.sh watch` per record, which
# dashboard_stream.py keeps in stream.json and publishes with --publish: data.js built again at once from that and
# the other parts as the last cycle read them (cache/part-*.json), so a card's step is on the page in seconds while
# the usage limit, the decisions and the lanes keep the 60 s cycle. A cycle reads Conveyor itself (the one ssh
# command below) only when stream.json is not fresh: the feed is not running.
#
# What it reads, each read only:
#   conveyor  `conveyor.sh snapshot` for every record conveyor/host.json names, in one ssh command to that host
#             (to host.json's `ssh` target), or in one command here on one machine (hostof), with each record's
#             GitHub address, the time of its last push that worked.
#   decisions the open decisions (decision.sh list) of each record's ledger, the file the host file's records[].ledger
#             names on this machine, each with its record's repo; a record that names none has none. An answer that is recorded is done: there is no main session to
#             send it to any more, so nothing waits on its message.
#   limit     the account's usage limit and list-price cost (dashboard_limit.py), with its own cache under cache/, and
#             every Claude account's usage, this machine's and (over ssh, at most once a TTL) the Conveyor host's;
#             on one machine they are the same accounts, read once.
#   lanes     each record's Fast lane worktree and Research lane worktree on this machine: the folders the host
#             file's records[].lanes.fast.worktree and records[].lanes.research.worktree name.
#   foremen   each Foreman of this machine (foremen()): a project's, or a group's of the host file's foreman.groups.
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
#   belt    cards: every open card (but a landed card whose push failed, while Landed today shows it) with its step, the time the step began, model, tokens and usd so far (reading
#           false and usd null before any token is read), its finished reviews, its track (the six steps Build, Review,
#           Fix, Test, Land, Push, with every recorded step as its detail) and its times: start (the first pick-up
#           of its work), pickedAt, priorSec and totalSec, as the snapshot gives them. No time is estimated.
#           A card that has landed stays here (landed true) until it is pushed and its issue is closed (with the rule
#           "Push when a card lands" off, the snapshot leaves an unpushed one out: Landed today shows it). cap: the
#           slots in force (every project's own cap together, no more than the machine cap; null when neither is known).
#           waiting: the cards on it that hold no slot as they only wait on another card (each loop's health.waitingCount).
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
#           project's) and cap (the slots in force, as belt's); the page's project filter leaves it whole, as the head).
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
#           with Conveyor) and suites (its whole-suite runs), as the snapshot gives them.
#   declined lines: the review findings the Declined panel shows (not dismissed, not built, at most 7 days old), of every
#           record, newest first: each with repo, repoUrl (its repository's https address, else null), id, time, card, issue, url, finding, by (who declined it: code, judge
#           or owner), why, built (the issue "File as issue" filed for it, else null), dismissed ({time, by}, else null),
#           round and findings (the review the judge declined it in and that review's findings as the judge numbered
#           them, [{n, finding}], else null), as the snapshot's declined gives them; rest: every other line, so, as its declinedRest gives them.
#   health  host {name, reachable, error}, records (each record's steered (the host answer's), repoUrl (its repository's https
#           address, else null), snapshotAt (when the build of its kept snapshot began, null from a snapshot
#           without it), loop, state (running, paused, stopped, as
#           its control record says; a loop not meant to run is off, not a fault), newest line, stuck cards, pushes,
#           cycles: the dependency cycles, flaky: the snapshot's flaky cases {case, count, issue, files, url}, null from a snapshot
#           without them, slowOff: the snapshot's test files kept off card test steps, each with its issue's url, null
#           likewise, untimed: how many of the last card test runs recorded no test times, null from a snapshot
#           without it, unchecked: how many landed cards skipped a lint command for a missing tool, null likewise, report: the pack's test.report (the test runner setup found and how its times are read), null
#           likewise, routes: each Claude route, subscription and proxy, with its state, null likewise, quarantined:
#           the lines of the card records set aside as not whole records {line, field, time}, null likewise,
#           serviceOld: the machine's Conveyor on another commit that refuses the pack {commit, refused, project}, null
#           when it reads it, or likewise), limit (this machine's usage-limit reading: its cost, Codex and API spend figures), limits (the
#           weekly limit reading of each account the cards run on, as each record's guard reads it: limitsOf), accounts (every Claude account read here
#           and on the host, each with its own usage and what it is used for: accountsOf), stream
#           ({live, heardAt, since, error, writtenAt}: whether Conveyor's part is the live feed's, when the host was last
#           heard from, and when the feed last wrote it), update (--update's last word: {checkedAt, head, error, moved:
#           {from, to, at, restart, restartFailed?} | null}; null before its first run).
#   lanes   records: for each record of the host file, its repo, fast (branch, commits ahead of main, landing: the
#           card of that record that lands them) and research (branch, run); a lane the record does not name is null.
#   cost    todayUsd, weekUsd, perLandedUsd (the priced steps' dollars), todayLeftOut, weekLeftOut, perLandedLeftOut (the
#           steps each leaves out for having no price), unpriced (those of the 7 days, each with why), landedAfter,
#           unpricedSteps, cards (today's, each with its usd; a restarted card's row with runs, its dollars every run's),
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
#           null), seats (the seats the rule Pick settings gave it, the pick's asked, or null) and stalls (how many times a step of it made no progress and was ended; 0 for none), and open (every open issue, as the snapshot's open: count,
#           split {queued, you, labelOrRule, belt}, held, each with its reasons, and issues, every open issue with its
#           labels and dependsOn, the numbers its Depends on: lines name; null when GitHub did not list them, and
#           umbrellas, each open parent with its parts, done of all, those in flight and the closed ones),
#           unpushed (the landed cards whose commits origin lacks, oldest first, each with since; null from a snapshot
#           without them), fullTest (the snapshot's: command, why, running, last; null from a snapshot without it) and
#           landingPr (health's: the open pull request of Land as pr, {number, url, cards, merge}, for Merge; null with none),
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
#           each model's display name and the model IDs seen in 30 days, for Model prices and the Board's model names; null
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
#           swe_board(), and the versions now, swe_versionsnow()) and drift (the snapshot's: the latest drift watch, conveyor/bench/drift.sh);
#           each null from a snapshot without it. The runs and their results are read when shown (--bench).
#   metrics records (each record's measured totals, today and week) and cards (each card of the 7 days with
#           its metrics: step timeline, seconds, tokens, dollars, findings; null from a snapshot without them), steps
#           (each card's steps of the last 25 h, uncut: the snapshot's metrics.steps, with its repo and url), and
#           compare (the 7 days side by side, {projects: a row a project, naming its repo; machine: the machine's}:
#           landed, leadSec (the median seconds from an issue's opening to its landing) and usd; a figure not measured
#           is null).
#   machine the machine's one Conveyor, over every project: host, state (paused: the host file's mode; running: a
#           project's loop runs; stopped: none does; not read: the host's host file does not read), cap (the slots
#           in force, as belt's), used (the cards holding a slot now, every project's together),
#           todayUsd and todayLeftOut (as cost's), repos, projects (each project on its own: repo, state, reason, loop,
#           mode (its control record's), cap (its own, in force), guard (its control record's weekly-limit guard) and used (its cards holding a slot), needs (its cards
#           blocked or waiting for the owner's yes, its issues waiting for that yes before their build, and its open
#           decisions, each {repo, decision: its id, title: the question}), belt,
#           queue (pick order), held, waiting (its issues waiting on an open dependency, the snapshot's queue.waiting;
#           null when the snapshot does not list them), order (the issues its record pins), rules, models ({builder, reviewer}: model and
#           effort in force; judge: {on: false}, or {on: true, model, effort} in force, null when its record does not
#           read), landedToday, todayUsd, todayLeftOut) and foremen (as foremen() gives them, with foremenError).
#   belt, belt3d, queue and cost's cards also carry byRepo ({repo: the fields that are one project's}: belt's cap and waiting, queue's held,
#   belt3d's queue while the queue of all is unknown,
#   cost's figures), which the
#   page shows in their place when it is filtered to one project.
# The Foreman's watchers read panels.health.data.limit from the same file (each Foreman reads its own projects'
# decisions from their ledgers, not panels.needs).
# Test seams: CONVEYOR_DASHBOARD_DIR, CONVEYOR_MAIN, CONVEYOR_WORKSPACES, CONVEYOR_SCRATCH, CONVEYOR_HOST_OS,
# XDG_CONFIG_HOME (where the host file is).
# Standalone (plan A9): the Board sources no support script of the project's (paths.sh, host-services.sh,
# peer-runtime.sh, .githooks/lib-workspaces.sh), so it runs from the release-1 files alone. The few values it took from
# them are resolved below, each by the same rule as its twin there.
set -uo pipefail
export GIT_OPTIONAL_LOCKS=0  # sampling never writes a worktree's index
HERE=$(cd "$(dirname "$0")" && pwd)
# The Mac's GNU tools (stat -c, date -d, xargs -d) lead PATH, ahead of a login shell's /usr/bin; --install writes this
# PATH into the job. Twin of paths.sh's Mac PATH repair.
if [ "$(uname -s)" = Darwin ]; then
  # Prepended even when already on PATH: one behind /usr/bin would leave Bash 3.2 and the BSD tools first.
  for d in /opt/homebrew/bin /opt/homebrew/opt/*/libexec/gnubin; do [ ! -d "$d" ] || PATH=$d:$PATH; done
  export PATH
fi
# The page server's Python: the Board's own virtualenv, which `conveyor.sh setup` fills from requirements.txt and
# `conveyor.sh doctor` checks (the same path in conveyor.sh's BOARD_VENV).
BOARD_PY=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/board-venv/bin/python3
# This machine's host file (plan section 6): the Conveyor host, its ssh target and its checkout, read by conveyor().
HOST_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json
# This machine's primary checkout: CONVEYOR_MAIN, which a Board installed outside any checkout is given (--install
# keeps it in the job); else this script's git common dir, so a worktree's copy and main's read the same checkout
# (twin of paths.sh's PP_MAIN). Never the host file's `main`: that is the Conveyor host's checkout, on another machine
# when the Board runs on the Mac.
if [ -n "${CONVEYOR_MAIN:-}" ]; then PP_MAIN=$CONVEYOR_MAIN
else
  PP_MAIN=$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || PP_MAIN=''
  case $PP_MAIN in
    */.git) PP_MAIN=${PP_MAIN%/.git} ;;
    *) echo "dashboard: cannot resolve the primary checkout from $HERE (git common dir: ${PP_MAIN:-none}); set CONVEYOR_MAIN" >&2; exit 1 ;;
  esac
fi
# The worktrees folder whose sessions count in this project's cost (limit): CONVEYOR_WORKSPACES, else the parent of
# main's linked worktree Fast-lane, else of its first linked worktree; empty when there is none or two Fast-lane
# folders disagree. The lanes are not read from it: lanes() reads each record's from the host file. Twin of
# pp_workspaces_dir in .githooks/lib-workspaces.sh: a change to one is made to both.
workspaces_dir() {
  if [ -n "${CONVEYOR_WORKSPACES:-}" ]; then printf '%s\n' "$CONVEYOR_WORKSPACES"; return 0; fi
  local line wt first='' lane='' main=1
  while IFS= read -r -d '' line; do
    case $line in "worktree "*) wt=${line#worktree } ;; *) continue ;; esac
    if [ -n "$main" ]; then main=''; continue; fi
    [ -n "$first" ] || first=${wt%/*}
    if [ "${wt##*/}" = Fast-lane ]; then
      [ -z "$lane" ] || [ "$lane" = "${wt%/*}" ] || return 1
      lane=${wt%/*}
    fi
  done < <(git -C "$PP_MAIN" worktree list --porcelain -z 2>/dev/null)
  wt=${lane:-$first}
  [ -n "$wt" ] || return 1
  printf '%s\n' "$wt"
}
PP_WORKSPACES=$(workspaces_dir) || PP_WORKSPACES=''
# The scratch folder dashboard_limit.py counts closing review copies in: one per primary checkout, so one project's
# closing-review spend is its own; a project may set its own.
PP_SCRATCH=${CONVEYOR_SCRATCH:-${TMPDIR:-/tmp}/conveyor/scratch/$(printf '%s' "$PP_MAIN" | tr -c 'A-Za-z0-9' '-')}
# CONVEYOR_HOST_OS drives either branch in a test (twin of host-services.sh's hs_os).
host_os() { printf '%s' "${CONVEYOR_HOST_OS:-$(uname -s)}"; }
# The launchd label prefix of the Mac's job (host-services.sh's HS_PREFIX): --restart and --uninstall find the job by it.
LABEL_PREFIX=com.conveyor.
# The & is escaped: from Bash 5.2 a bare & in the replacement is the match.
xml() { local s=${1//&/\&amp;}; s=${s//</\&lt;}; printf '%s' "${s//>/\&gt;}"; }
# The cycle runs this script again as "$HERE/$NAME.sh"; the mark tells tools/closure.sh what that load reaches.
NAME=dashboard # closure: load
# The Board's folder: dashboard/ in the state folder of the primary checkout, as `conveyor.sh state-dir` names it
# (the engine beside this Board's files). A state folder that cannot be named (a host file that cannot be read)
# stops the Board, as it stops the engine.
OUT=${CONVEYOR_DASHBOARD_DIR:-}
if [ -z "$OUT" ]; then
  OUT=$(CONVEYOR_MAIN=$PP_MAIN bash "${HERE%/*/*}/conveyor/conveyor.sh" state-dir) && [ -n "$OUT" ] \
    || { echo "dashboard: the state folder cannot be named; set CONVEYOR_DASHBOARD_DIR" >&2; exit 1; }
  OUT=$OUT/dashboard
fi
CACHE=$OUT/cache
# The Board's files the job runs and the page it copies: a Board in a git checkout takes the primary checkout's when
# that checkout carries the Board (a worktree's copy goes when the worktree does); a release install, a git clone or
# not, whose project carries no Board, and one outside any checkout, take their own.
if git -C "$HERE" rev-parse --git-dir >/dev/null 2>&1 && [ -d "$PP_MAIN/.claude/dashboard" ]; then BOARD=$PP_MAIN/.claude
else BOARD=${HERE%/*}; fi
VIEW_SRC=$BOARD/dashboard
TTL=300          # the usage read: asked again once its copy is this old, so a 60 s collection stays under its rate limit
CYCLE_LIMIT=900  # --loop kills a cycle running longer (a hung read)
SSH_LIMIT=60     # the one ssh command; a snapshot lists GitHub's open issues, which takes seconds
ACTIVE=600       # a lane's session whose record moved in this many seconds is working (whole minutes: find -mmin)
HISTORY_TTL=60   # --history with no live feed (so no ledger key) gives the copy it built while it is this young
STREAM_FRESH=60  # stream.json older than this: the live feed is not running (it rewrites the file every 10 s)
PORT=${CONVEYOR_DASHBOARD_PORT:-8790}
RUN='' PUB='' SRV='' ALV='' STM='' LCK=''
# The heartbeat, the page server and the live feed end with the loop, or the page would read a stopped collector as
# alive. A build's lock of data.js goes with it.
trap 'rm -rf "${RUN:-}" "${PUB:-}" ${LCK:+"$LCK"}; for p in "$SRV" "$ALV" "$STM"; do [ -z "$p" ] || kill "$p" 2>/dev/null; done' EXIT
trap 'exit 143' TERM

iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# cached <key> <cmd>... -- the command's JSON, re-read once the copy is TTL old. Only a read that works and parses
# as JSON replaces the copy; a failed one keeps it. $RUN/st-<key> says which the caller got: fresh, stale (the last
# good copy) or not-measured (no copy: nothing is printed), and $RUN/why-<key> the reason. A failed read writes
# $CACHE/<key>.retry ("<retry-at epoch> <reason>"): until then the command is not run, so a 429 is not hit again
# every cycle. Retry-at is the TTL, or the `retry after <n> s` the command's stderr names when that is longer.
cached() {
  local key=$1 f=$CACHE/$1 tmp=$RUN/cache-$1 err=$RUN/err-$1 m=$CACHE/$1.retry at='' why='' rc=0 n st=''
  shift
  [ ! -s "$m" ] || read -r at why < "$m" || true
  if [ -s "$f" ] && [ $((NOW - $(stat -c %Y "$f"))) -lt $TTL ]; then st=fresh
  elif [[ $at =~ ^[0-9]+$ ]] && [ "$at" -gt "$NOW" ]; then :
  elif { "$@" > "$tmp" 2>"$err"; rc=$?; [ $rc -eq 0 ] && jq -e . "$tmp" >/dev/null 2>&1; }; then
    mv -f "$tmp" "$f" && rm -f "$m" && st=fresh
  else
    why=$(tail -n 1 "$err" | cut -c1-120)
    [ -n "$why" ] || { [ $rc -eq 0 ] && why='malformed response' || why='read failed'; }
    n=$(grep -oE 'retry after [0-9]+ s' "$err" | tail -n 1 | grep -oE '[0-9]+') || n=0
    n=$((10#${n:-0}))  # a leading zero must not read as octal
    [ "$n" -gt $TTL ] || n=$TTL
    printf '%s %s\n' $((NOW + n)) "$why" > "$RUN/retry-$key" && mv -f "$RUN/retry-$key" "$m"
  fi
  [ -n "$st" ] || { [ -s "$f" ] && st=stale || st=not-measured; }
  printf '%s' "$st" > "$RUN/st-$key"; printf '%s' "$why" > "$RUN/why-$key"
  [ ! -s "$f" ] || cat "$f"
}

# Conveyor's snapshot, read where conveyor/host.json says Conveyor runs (hostof): one fixed command each cycle, over
# ssh to the build machine, or here on one machine. For
# every record, in order, three lines: `conveyor.sh snapshot`, the checkout's origin address (empty when it names
# none) and the time its last push that worked was recorded (0 when there is none). Then a marker line, so an answer
# cut short is no answer. The answer is one object: {host, local (true on one machine), reachable, error, records}; a record is {repo, snap, steered (it is the record on host.json's main: the
# one the Board steers through POST /control), repoUrl, lastPushAt, readAt (the snapshot's snapshotAt: when the build
# of the kept snapshot it printed began; null when it does not say)}. reachable is false when ssh itself did not get through (its exit 255, or
# the time limit) and true when the host answered, whatever it said; records is null, with the reason in error, unless
# every record answered with a snapshot: never an earlier answer, and never a part of the records.
# hostof -- what the one command of a read needs of the host file, as hostfile.sh (its one reader, which says the
# rules) gives it: host (the machine Conveyor runs on), main (the checkout of the record the Board steers), engine (the
# checkout whose conveyor.sh runs), target (host.json's own `ssh`; empty on one machine, where every read runs here)
# and recs (its records, [{repo, main}]); remote is 1 when the file names a build machine, even one it does not say
# all of. 1, with why naming the field that is wrong, when it does not say them.
hostof() {
  local r rc=0
  host='' main='' engine='' target='' recs='' why='' remote=''
  r=$(bash "$HERE/hostfile.sh" "$PP_MAIN") || rc=$?
  { IFS= read -r -d '' host; IFS= read -r -d '' main; IFS= read -r -d '' engine; IFS= read -r -d '' target
    IFS= read -r -d '' recs; IFS= read -r -d '' why; IFS= read -r -d '' remote; } < <(jq -j '(.host // ""), "\u0000", (.main // ""), "\u0000",
      (.engine // ""), "\u0000", (.target // ""), "\u0000", (.records | if . == null then "" else tojson end), "\u0000",
      (.error // ""), "\u0000", (if .local == false then "1" else "" end), "\u0000"' <<<"$r" 2>/dev/null)
  [ "$rc" = 0 ] || { why=${why:-the host file could not be read}; return 1; }
}
# onhost <command> -- runs one read's command where Conveyor runs: over ssh to target, or here when there is none,
# under the same time limit. The keepalive ends a host that stops answering mid-command; the time limit one that
# stalls before its command starts.
onhost() {
  if [ -n "$target" ]; then
    timeout -k 2 "$SSH_LIMIT" ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 "$target" "$1"
  else timeout -k 2 "$SSH_LIMIT" bash -c "$1"; fi
}

# --check, for doctor (conveyor/lib/setup.sh): whether the Board reads the project where the host file says Conveyor
# runs (hostof), by the read every panel takes: the snapshot of every record (conveyor). Prints where, or why it
# cannot, and then fails. On one machine the Board's own copy of Conveyor must have its conveyor.sh.
check() {
  local host main engine target recs why remote out
  hostof || { echo "$why"; return 1; }
  [ -n "$target" ] || [ -f "$engine/conveyor/conveyor.sh" ] || { echo "the Board's copy of Conveyor at $engine has no conveyor/conveyor.sh"; return 1; }
  RUN=$(mktemp -d) || return 1
  out=$(conveyor)
  jq -e '.records | arrays' >/dev/null 2>&1 <<<"$out" || { jq -r '.error // "the Board read no snapshot"' <<<"$out" 2>/dev/null || echo "the Board read no snapshot"; return 1; }
  if [ -n "$target" ]; then echo "on the build machine $host, over ssh to $target"; else echo "on this machine ($host)"; fi
}

conveyor() {
  local host main engine target recs why remote cmd out rc=0 one=false read=0
  hostof || read=1
  [ -n "$remote" ] || one=true
  fail() { jq -cn --arg h "${host:-}" --argjson r "$1" --arg e "$2" --argjson l "$one" '{host: (if $h == "" then null else $h end), local: $l, reachable: $r, error: $e, records: null}'; }
  [ "$read" = 0 ] || { fail null "$why"; return 0; }
  cmd=$(jq -r --arg e "$engine/conveyor/conveyor.sh" 'map((.main | @sh) as $m | "CONVEYOR_MAIN=\($m) bash \($e | @sh) snapshot && { git -C \($m) remote get-url origin 2>/dev/null || echo; } && { stat -c %Y \"$(CONVEYOR_MAIN=\($m) bash \($e | @sh) state-dir)\"/pushed 2>/dev/null || echo 0; }") | join(" && ")
    + " && echo @@end"' <<<"$recs")
  out=$(onhost "$cmd" 2>"$RUN/err-conveyor") || rc=$?
  case $rc in
    0) ;;
    255|124|137) fail false "$host did not answer: $(tail -n 1 "$RUN/err-conveyor" | tr -d '\r' | cut -c1-160 | grep . || echo "no answer in $SSH_LIMIT s")"; return 0 ;;
    *) fail true "$host answered, but its Conveyor gave no snapshot: $(tail -n 1 "$RUN/err-conveyor" | tr -d '\r' | cut -c1-200 | grep . || echo "exit $rc")"; return 0 ;;
  esac
  jq -ecRs --arg h "$host" --arg m "$main" --argjson recs "$recs" --argjson one "$one" '
    def need(f): if f then . else error("shape") end;
    split("\n") as $l | ($recs | length) as $n
    | need(($l | index("@@end")) == 3 * $n)
    | {host: $h, local: $one, reachable: true, error: null,
       records: [range(0; $n) as $i | ($l[3 * $i] | fromjson) as $s
         | $s | need(type == "object" and ([.needsYou.waiting, .needsYou.blocked, .belt, .landed] | all(type == "array"))
             and ([.queue, .health, .cost] | all(type == "object")))
         | {repo: $recs[$i].repo, snap: $s, steered: ($recs[$i].main == $m),
            repoUrl: ($l[3 * $i + 1] | (capture("github\\.com[:/](?<p>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(\\.git)?$") | "https://github.com/\(.p)") // null),
            lastPushAt: ($l[3 * $i + 2] | tonumber? // 0 | if . > 0 then todate else null end),
            readAt: (($s.snapshotAt | strings) // null)}]}' <<<"$out" 2>/dev/null \
    || fail true "$host answered, but not with the snapshot of every record"
}

# What waits on the owner outside the cards: the open decisions of each project's ledger, the file the host file's
# records[].ledger names on this machine (never the Board's own checkout), each with its record's repo. A record that
# names no ledger has no decisions; a named ledger that does not read is a warning naming its record, beside the
# decisions of the ledgers that did. Also writes the owner's daily page (/digest.txt behind the login), one page a
# ledger, then the picker answers no ledger holds (empty with no ledger named); a run in which any named ledger failed
# keeps the last good page.
decisions() {
  local cfg=$HOST_FILE recs repo led got err='' errs=() leds=() named=0 nread=0 pages=true open=$RUN/decisions-open.jsonl
  [ -e "$cfg" ] || cfg=$PP_MAIN/conveyor/host.json
  recs='[]'
  if [ -e "$cfg" ]; then
    recs=$(jq -ec '[.records // [] | .[] | select(has("ledger")) | [(.repo | tostring), (.ledger | tostring)]]' "$cfg" 2>/dev/null) \
      || { jq -cn '{decisions: null, error: "conveyor/host.json records are not understood"}'; return 0; }
  fi
  : > "$OUT/.digest.txt.$$"; : > "$open"
  # NUL between fields: a path reaches decision.sh exactly as the host file has it (@tsv would double a backslash).
  # Each ledger's open decisions go to a file, never an argument: a long question would exceed the argument limit.
  while IFS= read -r -d '' repo && IFS= read -r -d '' led; do
    named=$((named + 1))
    if [ ! -e "$led" ]; then errs+=("no ledger for $repo at $led"); continue; fi
    if got=$(CONVEYOR_MAIN=$PP_MAIN CONVEYOR_LEDGER=$led bash "$HERE/decision.sh" list 2>"$RUN/err-decisions") \
        && got=$(jq -ce --arg r "$repo" 'arrays | map(select(.answeredAt == null) | {repo: $r, id, askedAt, question, options: (.options // null), proposedDefault: (.proposedDefault // null), source: (.source // null)})' <<<"$got" 2>/dev/null); then
      printf '%s\n' "$got" >> "$open"; nread=$((nread + 1)); leds+=("$led")
      { printf '# %s\n' "$repo" && CONVEYOR_MAIN=$PP_MAIN CONVEYOR_LEDGER=$led bash "$HERE/decision.sh" digest --no-picks 2>/dev/null && echo; } >> "$OUT/.digest.txt.$$" || pages=false
    else
      got=$(head -n 1 "$RUN/err-decisions" 2>/dev/null | cut -c1-200); errs+=("$repo: ${got:-the decision ledger could not be read}")
    fi
  done < <(jq -j '.[] | .[0], "\u0000", .[1], "\u0000"' <<<"$recs")
  # Picker answers name no project: one section after the projects, of those no read ledger holds a row for.
  [ "$nread" -eq 0 ] || { printf '# Picker answers no project ledger holds\n' && CONVEYOR_MAIN=$PP_MAIN bash "$HERE/decision.sh" digest --picks "${leds[@]}" 2>/dev/null; } >> "$OUT/.digest.txt.$$" || pages=false
  # The page is replaced only when every named ledger read: a page missing a project is a failed run. With no ledger
  # named, every one read and the page is empty: a removed ledger's decisions leave the page with it.
  if [ "${#errs[@]}" -eq 0 ] && $pages; then mv -f "$OUT/.digest.txt.$$" "$OUT/digest.txt"; else rm -f "$OUT/.digest.txt.$$"; fi
  [ "${#errs[@]}" -eq 0 ] || { err=$(printf '%s; ' "${errs[@]}"); err=${err%; }; }
  jq -cs --argjson none "$([ "$nread" -eq 0 ] && [ "$named" -gt 0 ] && echo true || echo false)" --arg e "$err" \
    '{decisions: (if $none then null else add // [] end), error: (if $e == "" then null else $e end)}' "$open"
}

# The usage limit and list-price cost. The usage read is Claude's own quota reading, the statusline's source, never a
# model call; dashboard_limit.py owns the math and keeps the only percent history there is, in cache/. The reading is
# one account's: after a switch the cached one and its retry deadline are dropped, so neither the other
# account's figure nor its 429 holds off this collect's read; each account's own 429 deadline, kept by
# dashboard_limit.py per account, still does. Prints {limit, error}.
# The Claude accounts of the Conveyor host (its host file's accounts and its own default login), each with its own
# usage, as the host's dashboard_limit.py reads them; over ssh to host.json's target, as conveyor() checks the host file.
# Prints the list.
hostaccounts() {
  local host main engine target recs why remote
  hostof && [ -n "$target" ] || { echo "no Conveyor host is named" >&2; return 1; }
  timeout -k 2 "$SSH_LIMIT" ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 \
    "$target" "python3 $(jq -rn --arg p "$main" '$p | @sh')/.claude/scripts/dashboard_limit.py accounts \"\${XDG_CACHE_HOME:-\$HOME/.cache}/conveyor/accounts\"" | jq -ce 'arrays'
}
# Every Claude account the Board can read, each with its own usage: this machine's (dashboard_limit.py accounts, the
# account in use from claude-usage, which limit() has just read) and the
# Conveyor host's (hostaccounts, asked at most once a TTL: cached). Prints {here, host: {name, accounts, error}}. The
# emails are for the page alone.
accounts() {
  local here acc st host main engine target recs why remote
  # The account in use is shown from limit()'s reading, never read a second time (a second read kept it refused, 429).
  here=$(python3 "$HERE/dashboard_limit.py" accounts "$CACHE" "$CACHE/claude-usage" 2>/dev/null | jq -ce 'arrays') || here=null
  # On one machine (the host file names no build machine: hostof) the Conveyor host is this machine: its accounts are
  # the ones just read, listed once, as the host's (no name: the page says "this machine"), so each shows what the
  # cards use it for.
  hostof
  if [ -z "$remote" ]; then
    jq -cn --argjson h "$here" '{here: [], host: {name: null, accounts: $h,
      error: (if $h == null then "the accounts on this machine were not read" else null end)}}'
    return 0
  fi
  acc=$(cached host-accounts hostaccounts) || acc=''
  st=$(cat "$RUN/st-host-accounts")
  jq -cn --argjson h "$here" --argjson a "${acc:-null}" --arg st "$st" --rawfile why "$RUN/why-host-accounts" --arg n "$host" \
    '{here: $h, host: {name: (if $n == "" then null else $n end), accounts: $a,
      error: (if $st == "fresh" then null elif $st == "stale" then "the accounts on the host were not read again (\($why)); showing the last read" else "the accounts on the host were not read: \($why)" end)}}'
}
limit() {
  local st have now_in_use out acc cx=${CODEX_HOME:-$HOME/.codex}/sessions
  have=$(jq -r '.account.folder // empty' "$CACHE/claude-usage" 2>/dev/null)
  now_in_use=$(python3 "$HERE/dashboard_limit.py" account | jq -r .folder)
  { [ -z "$have" ] || [ "$have" = "$now_in_use" ]; } || rm -f "$CACHE/claude-usage" "$CACHE/claude-usage.retry"
  # With the cache folder, fetch honours and keeps the account's own 429 deadline, which outlives the switch above.
  cached claude-usage python3 "$HERE/dashboard_limit.py" fetch "$now_in_use" "$CACHE" > /dev/null
  st=$(cat "$RUN/st-claude-usage")
  acc=$(accounts) || acc=null
  # The pack's model prices, added models and aliases win over the built-in table here too (use_prices); a pack that
  # does not read has none.
  if out=$(PP_SCRATCH=$PP_SCRATCH PP_PRICES=$(jq -c '.prices // {}' "$PP_MAIN/.conveyor/project.json" 2>/dev/null) python3 "$HERE/dashboard_limit.py" build "$st" "$CACHE/claude-usage" "$NOW" "$CACHE" "$HOME/.claude/projects" "$cx" "$PP_MAIN" ${PP_WORKSPACES:+"$PP_WORKSPACES"} 2>"$RUN/err-limit") \
      && jq -e 'objects' >/dev/null 2>&1 <<<"$out"; then
    jq -c --arg st "$st" --rawfile why "$RUN/why-claude-usage" --argjson acc "$acc" 'del(.history) | (.codex | objects) |= del(.history)
      | {limit: (. + {reading: $st}), error: (if $st == "fresh" then null elif $st == "stale" then "the usage read failed (\($why)); showing the last reading" else "the usage limit was not read: \($why)" end), accounts: $acc}' <<<"$out"
  else jq -cn --arg e "$(tail -n 1 "$RUN/err-limit" | cut -c1-200)" --argjson acc "$acc" '{limit: null, error: ("the usage limit could not be built" + (if $e == "" then "" else ": " + $e end)), accounts: $acc}'; fi
}

# latest_cwd <record> -- the folder a Claude session's record says it works in now: the cwd of the last of its lines
# that carry one, each such line read, so one long message cannot hide it.
latest_cwd() { grep -F '"cwd":' "$1" 2>/dev/null | jq -rR 'fromjson? | .cwd? | strings | select(test("\n") | not)' 2>/dev/null | tail -n 1; }

# One lane's worktree on this machine: {present, branch, ahead, subject, first, dirty, run}. ahead is the commits it
# has that main does not, subject the newest of them and first the oldest (the title Conveyor gives a card of a
# branch that names no issue); dirty counts its files with an uncommitted change, new files too. run is the newest Claude
# session in the folder (begun there, or working there now): when it began, when its record last moved, whether
# that was in the last ACTIVE seconds, and how its first prompt opens. A folder that is not there is {present: false}.
lane() { # <worktree>
  local d=$1 br ahead=null subj='' first='' dirty=null f g c cwd run=null
  [ -e "$d/.git" ] || { echo '{"present":false}'; return 0; }
  br=$(git -C "$d" symbolic-ref -q --short HEAD 2>/dev/null) || br=''
  if ahead=$(git -C "$d" rev-list --count main..HEAD 2>/dev/null); then
    [ "$ahead" = 0 ] || { subj=$(git -C "$d" log -1 --format=%s 2>/dev/null); first=$(git -C "$d" log --reverse --format=%s main..HEAD 2>/dev/null | head -n 1); }
  else ahead=null; fi
  dirty=$(git -C "$d" status --porcelain --untracked-files=all 2>/dev/null | grep -c .) || dirty=${dirty:-0}
  [[ $dirty =~ ^[0-9]+$ ]] || dirty=null
  # The newest record in the folder's ~/.claude/projects entry (Claude Code's folder naming; twin of pp_session_log).
  f=$(ls -t "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$d")"/*.jsonl 2>/dev/null | head -1)
  # Claude Code files a session under the folder it began in, and each record carries the folder it works in now
  # (cwd): a session begun in the main checkout or in a folder of the lane, working in the lane, is filed elsewhere.
  # A newer record that moved in the last ACTIVE seconds, whose latest cwd is the lane or a folder in it, is the run;
  # a session filed under the lane whose latest cwd has left it is not. The records that moved in the last ACTIVE
  # seconds, each with its latest cwd, are LANE_ACTIVE, which lanes() lists once a cycle.
  cwd=''
  if [ -n "$f" ]; then
    g=''
    while IFS=$'\t' read -r g c; do [ "$g" != "$f" ] || { cwd=$c; break; }; done <<<"$LANE_ACTIVE"
    [ "$g" = "$f" ] || cwd=$(latest_cwd "$f")
  fi
  case $cwd in ''|"$d"|"$d"/*) ;; *) f='' ;; esac
  while IFS=$'\t' read -r g c; do
    [ -n "$g" ] || continue
    [ -z "$f" ] || [ "$g" -nt "$f" ] || continue
    case $c in "$d"|"$d"/*) f=$g ;; esac
  done <<<"$LANE_ACTIVE"
  # The record is read in whole lines, however long, up to its first timestamp and first prompt and no further.
  [ -z "$f" ] || run=$(jq -cRn --argjson last "$(stat -c %Y "$f")" --argjson now "$NOW" --argjson active "$ACTIVE" '
      def prompt: select(.type == "user" and .isSidechain != true) | .message.content
        | if type == "string" then . else (arrays | map(select(.type == "text") | .text) | join(" ")) end | strings | select(length > 0);
      (label $done | foreach ((inputs | fromjson? | objects), null) as $o ({s: null, t: null};
         if $o then .s //= ([$o.timestamp | strings][0]) | .t //= ([$o | prompt][0]) else . end;
         if $o == null or (.s and .t) then ., break $done else empty end)) as $r
      | {startedAt: $r.s, lastAt: ($last | todate), active: ($now - $last < $active),
         topic: ($r.t | if . then gsub("\\s+"; " ") | .[0:160] else null end)}' "$f" 2>/dev/null) || run=null
  jq -cn --arg b "$br" --argjson a "$ahead" --arg s "$subj" --arg f "$first" --argjson d "$dirty" --argjson run "${run:-null}" \
    'def n: if . == "" then null else . end; {present: true, branch: ($b | n), ahead: $a, subject: ($s | n), first: ($f | n), dirty: $d, run: $run}'
}
# The lanes of every record of the host file, in its order: {records: [{repo, fast, research}]}. A lane is read from
# the folder the record's lanes.fast.worktree or lanes.research.worktree names on this machine (a path starting ~/
# is under the home folder), and is null when the record names none: a lane is the owner's own worktree, wherever
# `conveyor.sh lane fast create` or `lane research create` made it, and each writes its folder into the host file.
lanes() {
  local cfg=$HOST_FILE recs='[]' repo f r out='[]' LANE_ACTIVE='' g
  [ -e "$cfg" ] || cfg=$PP_MAIN/conveyor/host.json
  if [ -e "$cfg" ]; then
    recs=$(jq -ec 'def w: . // "" | if type == "string" then . else error("worktree") end;
        [.records // [] | .[] | [(.repo | tostring), (.lanes.fast.worktree | w), (.lanes.research.worktree | w)]]' "$cfg" 2>/dev/null) \
      || { jq -cn '{error: "conveyor/host.json records are not understood"}'; return 0; }
  fi
  # The Claude records that moved in the last ACTIVE seconds, each with its latest cwd, one "<record><tab><cwd>" a
  # line: listed and read once a cycle, not once a lane.
  while IFS= read -r g; do
    LANE_ACTIVE+=$g$'\t'$(latest_cwd "$g")$'\n'
  done < <(find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -mmin -$((ACTIVE / 60)) 2>/dev/null)
  while IFS= read -r -d '' repo && IFS= read -r -d '' f && IFS= read -r -d '' r; do
    [[ $f != "~/"* ]] || f=$HOME/${f#"~/"}
    [[ $r != "~/"* ]] || r=$HOME/${r#"~/"}
    f=$([ -z "$f" ] && echo null || lane "$f") && r=$([ -z "$r" ] && echo null || lane "$r") \
      && out=$(jq -c --arg repo "$repo" --argjson f "$f" --argjson r "$r" '. + [{repo: $repo, fast: $f, research: $r}]' <<<"$out") || return 1
  done < <(jq -j '.[] | .[] | ., "\u0000"' <<<"$recs")
  jq -c '{records: .}' <<<"$out"
}

# The Foremen of this machine, one a project or one a group (conveyor/foreman/lib.sh mine: a list of the host file's
# foreman.groups is one Foreman over the records it names; groups that name a project twice are not understood, and
# then each project has its own): {foremen: [{projects, group, held, since, lastWakeAt, waiting, pluginBugs,
# pluginBugsFile, pluginBugsUrl, pluginNotes}], error}; pluginBugs: how many plugin problems it noted (plugin-bugs.md,
# conveyor/foreman/stop.sh), pluginBugsFile: that file, pluginBugsUrl: its copy in the Board's folder
# (plugin-bugs/<first project>.txt, which the page server serves, as a browser opens no file:// link from an https
# page), pluginNotes: each note as {at, card, text, line} (stop.sh's "- <at> · card <card> · <text>"; at and card null
# for a line in no such form; line: the whole line, which the page's Dismiss names to POST /plugin-dismiss); all three
# null when it noted none. A Foreman's
# folder is foreman/ in the state folder of its first project (lib.sh's FD), which is the host file's stateDir for the
# host file's own checkout and that checkout's conveyor/state for any other (conveyor.sh's ST); the host file's own
# checkout is the one its main leads to, links followed, as the engine compares them. held: a session holds
# the role (the folder's session mark names one), since when it claimed it; lastWakeAt: when a wake was last relayed
# to it (last-wake.txt); waiting: the wakes owed to it and not relayed yet (pending/), the first line of each. A
# project whose folder holds no mark has no Foreman: held false, and the page says so. When the host file names an
# ssh target and a Foreman's first record's main is not on this machine (the belt runs on the host), the Foreman runs
# in a checkout here whose remote is that repository (lib.sh's mine and FD), so its folder is read there
# (checkout_of); with no such checkout, under main as before. There, the loop on the host notes a model with no
# built-in price in the host's folder (noprice(), conveyor/lib/control.sh), which this machine does not read: each such
# note the snapshot of one of the Foreman's projects gives (priceNotes, in <conveyor part>) is added to the folder read
# here, under the lock the loop takes. Once a model: price-notes.txt in the folder lists the models added, so a note
# dismissed or filed here does not come back; and none for a model a note in the file already names.
# checkout_of <repo> [<ledger>]: the main checkout on this machine whose remote the pack names (.remote, default
# origin) has that repository's name as the last part of its address (lib.sh's repo_name), looked for in the
# checkout holding the record's ledger, then in the folders beside the Board's own checkout. Nonzero when none has.
checkout_of() {
  local c r u cs=()
  [ -z "${2:-}" ] || { c=$(git -C "$(dirname -- "$2")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && cs+=("${c%/.git}"); }
  for c in "${PP_MAIN%/*}"/*/; do cs+=("${c%/}"); done
  for c in "${cs[@]}"; do
    [ -d "$c/.git" ] || continue
    r=$(jq -r '.remote // "origin" | strings' "$c/.conveyor/project.json" 2>/dev/null) && [ -n "$r" ] || r=origin
    u=$(git -C "$c" remote get-url -- "$r" 2>/dev/null) || continue
    u=${u%/}; u=${u%.git}; u=${u##*[/:]}
    [ "$u" != "$1" ] || { printf '%s' "$c"; return 0; }
  done
  return 1
}
foremen() { # <conveyor part>
  local cfg=$HOST_FILE rows projects main hm sd ssh led here dir sid since wake f out='[]' waiting host engine target recs why remote bugs url away
  # The copies are made again each read: a Foreman whose notes are gone has none left.
  rm -rf "$OUT/plugin-bugs"
  [ -e "$cfg" ] || cfg=$PP_MAIN/conveyor/host.json
  [ -e "$cfg" ] || { echo '{"foremen":[],"error":null}'; return 0; }
  # The host's main and its ssh target as hostof reads them (a host file it cannot read names neither).
  hostof || main=''
  rows=$(jq -ec --arg hm "$main" --arg ssh "$target" '(.records // []) as $r | (.foreman.groups // []) as $g
      | select(($r | type == "array" and all(type == "object" and (.repo | type == "string") and (.main | type == "string")))
          and ($g | type == "array" and all(type == "array" and all(type == "string"))))
      | (if ([$g[][]] | length == (unique | length)) then $g else [] end) as $g
      | (if $hm == "" then null else $hm end) as $hm | (.stateDir | if type == "string" and . != "" then . else null end) as $sd
      | ($ssh != "") as $ssh
      | [$r[].repo] as $at
      | [$r[] | .repo as $n | (first($g[] | select(index($n))) // [$n]) | map(select(. as $x | $at | index($x)))]
      | unique_by(.[0]) | sort_by(.[0] as $n | $at | index($n))
      | map(. as $p | first($r[] | select(.repo == $p[0])) as $f
          | {projects: $p, main: $f.main, hm: ($hm // ""), sd: ($sd // ""), ssh: (if $ssh then "1" else "" end),
             led: ($f.ledger | strings // "")})' "$cfg" 2>/dev/null) \
    || { jq -cn '{foremen: null, error: "conveyor/host.json records are not understood"}'; return 0; }
  while IFS= read -r -d '' projects && IFS= read -r -d '' main && IFS= read -r -d '' hm && IFS= read -r -d '' sd \
    && IFS= read -r -d '' ssh && IFS= read -r -d '' led; do
    # With ssh, a main not on this machine is the host's: the Foreman runs in a checkout here matched by its remote.
    away=''
    if [ -n "$ssh" ] && [ ! -d "$main" ]; then
      [[ $led != "~/"* ]] || led=$HOME/${led#"~/"}
      here=$(checkout_of "$(jq -r '.[0]' <<<"$projects")" "$led") && main=$here && away=1
    fi
    dir=$main/conveyor/state
    [ -z "$sd" ] || { [ "$main" != "$hm" ] && [ "$(cd "$main" 2>/dev/null && pwd -P)" != "$(cd "$hm" 2>/dev/null && pwd -P || echo "$hm")" ]; } || dir=$sd
    dir=$dir/foreman
    # The host's notes for models with no built-in price; only a note of noprice()'s form, one line, is added.
    [ -z "$away" ] || ( mkdir -p "$dir" && { flock -w 30 9 || exit 1
      while IFS= read -r l; do
        m=${l#*" · No built-in price for "}; m=${m%%": "*}
        ! grep -qxF -- "$m" "$dir/price-notes.txt" 2>/dev/null || continue
        grep -qF -- " · No built-in price for $m: " "$dir/plugin-bugs.md" 2>/dev/null \
          || { [ -s "$dir/plugin-bugs.md" ] || printf '# Plugin problems the Foreman noted (for the conveyor-belt repo)\n\n'; printf '%s\n' "$l"; } >> "$dir/plugin-bugs.md" || continue
        printf '%s\n' "$m" >> "$dir/price-notes.txt"
      done < <(jq -r --argjson p "$projects" '.records | arrays | .[] | objects | select(.repo | IN($p[])) | .snap.priceNotes | arrays | .[] | strings
          | select((contains("\n") or contains("\r") | not) and test("^- [^ ]+ · card - · No built-in price for (claude|gpt)-[A-Za-z0-9._\\[\\]-]+: "))' "$1" 2>/dev/null); } 9>>"$dir/noprice.lock" ) \
      || echo "dashboard: the notes for models with no built-in price could not be added to $dir/plugin-bugs.md" >&2
    sid='' since=''; { read -r sid since < "$dir/session"; } 2>/dev/null || true
    [[ $since =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]] || since=''
    wake=$(stat -c %Y "$dir/last-wake.txt" 2>/dev/null) && wake=$(iso "$wake") || wake=''
    waiting=$(for f in "$dir"/pending/*.wake; do [ ! -f "$f" ] || head -n 1 "$f" | cut -c1-200; done | jq -Rc . | jq -cs .) || waiting='[]'
    bugs=$(grep -c '^- ' "$dir/plugin-bugs.md" 2>/dev/null) || bugs=0
    notes=$({ grep '^- ' "$dir/plugin-bugs.md" 2>/dev/null || true; } | jq -Rc '(capture("^- (?<at>[^ ]+) · card (?<card>[^ ]+) · (?<text>.*)$")
      // {at: null, card: null, text: ltrimstr("- ")}) + {line: .}' | jq -cs .) || notes='[]'
    url=$(jq -r '.[0]' <<<"$projects"); url=plugin-bugs/${url//[^A-Za-z0-9._-]/_}.txt
    [ "$bugs" -eq 0 ] || { mkdir -p "$OUT/plugin-bugs" && cp -- "$dir/plugin-bugs.md" "$OUT/$url" && chmod 644 "$OUT/$url"; } || url=''
    out=$(jq -c --argjson p "$projects" --arg sid "$sid" --arg s "$since" --arg w "$wake" --argjson q "${waiting:-[]}" \
      --argjson nb "${bugs:-0}" --arg fb "$dir/plugin-bugs.md" --arg u "$url" --argjson nt "${notes:-[]}" \
      'def n: if . == "" then null else . end; . + [{projects: $p, group: ($p | length > 1), held: ($sid != ""), since: ($s | n), lastWakeAt: ($w | n), waiting: $q,
        pluginBugs: $nb, pluginBugsFile: (if $nb > 0 then $fb else null end), pluginBugsUrl: (if $nb > 0 then $u | n else null end),
        pluginNotes: (if $nb > 0 then $nt else null end)}]' <<<"$out") || return 1
  done < <(jq -j '.[] | (.projects | tojson), "\u0000", .main, "\u0000", .hm, "\u0000", .sd, "\u0000", .ssh, "\u0000", .led, "\u0000"' <<<"$rows")
  jq -c '{foremen: ., error: null}' <<<"$out"
}

# The page's parts from the five reads. One jq program, so every panel's part is cut from the same answers.
PANELS_JQ='
  def total: if length == 0 then 0 elif any(. == null) then null else add * 10000 | round / 10000 end;
  def link($r): if $r.repoUrl != null and (.issue | type) == "number" and .issue > 0 then "\($r.repoUrl)/issues/\(.issue)" else null end;
  def tag($r): . + {repo: $r.repo, url: link($r)};
  def few($r): map(tag($r) | {repo, card, issue, title, url} + .);
  # The state of the machine of the records (the record list): not read (its host file does not read), paused (the
  # host file says so), running (a loop of one of them runs), else stopped.
  def mstate: ([.[].snap.health.machine | objects][0] // null) as $m
    | if $m.unread == true then "not read" elif $m.paused == true then "paused" elif any(.[]; .snap.health.loop == true) then "running" else "stopped" end;
  # The slots in force of the records (the record list), the one slots figure of the page (issue 413: the head, the
  # machine bar and Belt 3D each gave their own): every project'"'"'s own cap together, and no more than the machine cap
  # where the host file sets one; null when neither is known.
  def slots: ([.[].snap.health.builderCap | numbers] | if length == 0 then null else add end) as $sum
    | ([.[].snap.health.machine | objects][0].cap | numbers) // null
    | if . == null then $sum elif $sum == null then . else [., $sum] | min end;
  # The cards of the records (the record list) that hold no slot as they only wait on another card: the count each
  # running loop leaves out of its own against its cap (health.waitingCount), together; 0 when none says.
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
         | {card, issue, name: (.name // null), title, step, waitsOn: (.waitsOn // null), gaveWay: (.gaveWay // null), gaveWayFixing: (.gaveWayFixing == true), stepAt, pickedAt: (.pickedAt // null), files: (.track.files // null), tests: (.track.tests // null), usd, reading, atEnd: (.atEnd == true),reason: (.track.reason // null), stays: stays, doneWhen: (.doneWhen // null), split: (.split // null), seats: (.seats // null), stalls: (.stalls // 0), beyond: (.beyond // null)}] | few($r),
       review: [$s.belt[] | select(.landed != true and .step == "review") | {card, issue, name: (.name // null), title, review, of, gaveWay: (.gaveWay // null), gaveWayFixing: (.gaveWayFixing == true), stepAt, usd, reading, atEnd: (.atEnd == true),stays: stays, doneWhen: (.doneWhen // null), split: (.split // null), seats: (.seats // null), stalls: (.stalls // 0), beyond: (.beyond // null)}] | few($r),
       waiting: [$s.needsYou.waiting[] | {card, issue, name: (.name // null), title, sentence, since, doneWhen: (.doneWhen // null), split: (.split // null), seats: (.seats // null), stalls: (.stalls // 0)}] | few($r),
       # Its track and reviews too: the card leads with why it failed (the tests that failed, the NO-GO reviews), as in Needs you.
       blocked: [$s.needsYou.blocked[] | {card, issue, name: (.name // null), title, reason, tail, since, track: (.track // null), reviews: (.reviews // null), doneWhen: (.doneWhen // null), split: (.split // null), seats: (.seats // null), stalls: (.stalls // 0)}] | few($r),
       landed: [$s.landed[] | {card, issue, name: (.name // null), title, step, time, usd, reviews, batch: (.batch // null), doneWhen: (.doneWhen // null), split: (.split // null), seats: (.seats // null), stalls: (.stalls // 0)}] | few($r),
       today: {landed: $s.landedCount, usd: $s.landedUsd},
       unpushed: ($s.health.unpushed // null | if . == null then null else map({card, issue, name: (.name // null), since}) | few($r) end), fullTest: ($s.fullTest // null),
       landingPr: ($s.health.landingPr // null),
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
       prices: ($s.prices // null), standing: ($s.standing // null), pushCheck: ($s.pushCheck | if type == "boolean" then . else null end), lintCommands: ($s.lintCommands | if type == "array" then . else null end), open: openOf($r), readAt: ($r.readAt // null)};
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
  # card'"'"'s block and stays), and a card stopped since is added, its title the one the snapshot'"'"'s belt gave it, and
  # fromRecords true: it has no track, reviews or changed files, so the page draws it anew once a snapshot gives them.
  # $behind: each such record, {repo, at (its snapshotAt), building (loop.json'"'"'s count now; 0 once no process of the
  # loop lives, as then none builds)}.
  | def nowOf($r): [$r.snap | select(.recordsNewer == true) | .recordsNow | objects | select([.blocked, .waiting] | all(type == "array"))
      | def cards: map(objects | select(.card | type == "string")); {blocked: (.blocked | cards), waiting: (.waiting | cards)}][0];
    def stopped($r): {card, issue, name, title: (.card as $k | first($r.snap.belt[] | select(.card == $k) | .title) // null), since, fromRecords: true} | tag($r);
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
           + [$blocked[] | own | mine | {state: "blocked", card, reason, tail, since}]
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
        cap: ($R | slots), waiting: ($R | idle),
        # building: while a record is behind its card records, the cards building now: loop.json'"'"'s count for each
        # such record (0 once its loop has exited: never the old belt'"'"'s), and for any other its cards on the belt not
        # landed less those that only wait (idle), as the page counts them; null when none is behind, and in byRepo for
        # a record that is not. behind: those records.
        building: (if $behind != [] then [$R[] | . as $r | first($behind[] | select(.repo == $r.repo) | .building | numbers)
            // (([$belt[] | select(.repo == $r.repo and .landed != true)] | length) as $a | $a - ([[$r] | idle, $a] | min))] | add else null end),
        behind: [$behind[] | {repo, at}],
        byRepo: ($R | map(.repo as $p | {key: .repo, value: {cap: (.snap.health.builderCap | if type == "number" then . else null end), waiting: ([.] | idle),
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
   release: (if $R == null then {error: $cerr, data: null} else {error: null, data: {records: ($R | map({repo, url: .repoUrl, release: (.snap.release // null), suites: (.snap.suites // null)}))}} end),
   # Declined: the declined list of every record (lines: the declined of its snapshot; rest: its declinedRest; none from
   # a snapshot from before it carried them), newest first.
   declined: (if $R == null then {error: $cerr, data: null} else {error: null, data: ({lines: "declined", rest: "declinedRest"} | map_values(. as $k
        | $R | map(. as $r | .snap[$k] | arrays | .[] | objects | tag($r)
        | {repo, repoUrl: ($r.repoUrl // null), id, time, card, issue, name: (.name // null), url, finding, by, why, built: (.built // null), dismissed: (.dismissed // null), round: (.round // null), findings: (.findings // null)}) | sort_by(.time) | reverse))} end),
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
        belt: [$belt[] | {repo, card, issue, name: (.name // null), title, url, step, stepAt, landed: (.landed == true), waitsOn: (.waitsOn // null), usd,
          turns: (.live.turns? // null), reviews: (.reviews | rounds),
          track: (.track | if type == "object" then track3 + {records: [.records | arrays | .[] | objects | {name, at: (.at // null)}
            + (if (.reason | type) == "string" and (.reason | startswith("the Done-when check failed")) then {replyCheck: true} else {} end)]} else null end)}],
        queue: (if any($R[]; .snap.queue.next == null) then null
          else $R | map(. as $r | .snap | queue3($r)) | {next: map(.next[]), held: map(.held[]), waiting: map(.waiting[])} end),
        needs: ([$waiting[] | . + {kind: "waiting", reason: "Visible change: \(.sentence // "no sentence")"}] + [$blocked[] | . + {kind: "blocked"}]
          | map({repo, card, issue, name: (.name // null), title, url, kind, reason, since, reviews: (.reviews | rounds), usd: (.metrics.usd // null), track: (.track | track3)})),
        landed: [$landed[] | {repo, card, issue, name: (.name // null), title, url, time, usd, reviews: (.rounds | rounds), track: (.track | track3)}],
        # What the deck behind the floor reads out: the host, its machine state (as the machine part has it) and the
        # slots as the "On the belt" tile of the head has them: the cards holding one (a card landed and waiting for its
        # push holds none, nor does a card that only waits on another card: idle) and the slots in force, as the Belt
        # part and the machine bar have them.
        deck: {host: $conv.host, state: ($R | mstate), used: ([([$belt[] | select(.landed != true)] | length) - ($R | idle), 0] | max),
          cap: ($R | slots)}}} end),
   health: {error: null, data: {
        host: {name: $conv.host, local: ($conv.local == true), reachable: $conv.reachable, error: $cerr}, stream: ($conv.stream // null),
        records: (if $R == null then null else $R | map({repo, repoUrl: (.repoUrl // null), lastPushAt, steered, snapshotAt: (.snap.snapshotAt // null)} + (.snap.health | {loop, state: (.state // null), newest, stuck, unpushed, pushError, pushFailingSince, gh, ghReached, diskFreeKb, builderCap, models, cycles: (.cycles // null), untimed: (.untimed // null), unchecked: (.unchecked // null), split: (.split // null), report: (.report // null), routes: (.routes // null), quarantined: (.quarantined // null), serviceOld: (.serviceOld // null)}) + {flaky: (. as $r | .snap.flaky | arrays | map(. + {url: link($r)})) // null}
          + {slowOff: (. as $r | .snap.slowOff | arrays | map(. + {url: link($r)})) // null}) end),
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
           # The figures of each project on its own, shown in place of the sums when the page is filtered to one project.
           byRepo: ($R | map({key: .repo, value: (.snap.cost | {todayUsd: .today, weekUsd: .week, perLandedUsd: .perLanded, landedAfter, unpricedSteps,
             todayLeftOut: (.todayLeftOut | numbers // 0), weekLeftOut: (.weekLeftOut | numbers // 0), perLandedLeftOut: (.perLandedLeftOut | numbers // 0)})}) | from_entries),
           unpriced: (if any($R[]; .snap.cost.unpriced | type != "array") then null
             else [$R[] as $r | $r.snap.cost.unpriced[] | tag($r) | {repo, card, issue, url, step, time, why} + (if .name then {name} else {} end)] end),
           # Every card with a step in the 7 days, the rows of each record in its own order (the one worked on last
           # first); null when the snapshot of a record is from before it carried the rows.
           perCard: (if any($R[]; .snap.cost.cards | type != "array") then null
             else [$R[] as $r | $r.snap.cost.cards[] | tag($r) | {repo, card, issue, title, url, state, runs, todayUsd: .today, weekUsd: .week} + (if .name then {name} else {} end)] end),
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
      def benchOf: {repo, bench: (.snap.bench | objects // null), drift: (.snap.drift | objects // null)};
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
            usdLeftOut: (.snap.cost.weekLeftOut | numbers // 0)}],
          machine: {landed: ([$R[].snap.metrics.week.landed] | if any(. == null) then null else add end),
              leadSec: (if any($R[]; .snap.metrics.cards | type != "array") then null
                else [$R[].snap.metrics.cards[] | select(.state | IN("landed", "closed")) | .metrics.leadSec | numbers] | sort
                  | if length == 0 then null else (.[(length - 1) / 2 | floor] + .[length / 2 | floor]) / 2 | round end end),
              usd: ([$R[].snap.cost.week] | total), usdLeftOut: ([$R[].snap.cost.weekLeftOut | numbers] | add // 0)}}}} end),
   # The one Conveyor of the machine over every project, each project on its own, and each Foreman. The settings of
   # the machine are those of the host file on the host, as the health of every record names them (health.machine;
   # null from a host file that sets none, and from a snapshot from before it said). A card holds a slot from its
   # pick to its landing (a landed card waiting for its push holds none, as belt counts them), but while it only waits
   # on another card (idle).
   machine: (if $R == null then {error: $cerr, data: null} else
        def used: [([.snap.belt[] | select(.landed != true)] | length) - ([.] | idle), 0] | max;
        def inforce: if type == "object" then {model: (.model // null), effort: (.effort // null)} else null end;
      {error: null, data: {host: $conv.host,
        state: ($R | mstate),
        cap: ($R | slots), used: ([$R[] | used] | add), todayUsd: ([$R[].snap.cost.today] | total),
        todayLeftOut: ([$R[].snap.cost.todayLeftOut | numbers] | add // 0), repos: [$R[].repo],
        projects: [$R[] | . as $r | .snap as $s | {repo, state: ($s.health.state // null), reason: ($s.health.reason // null), loop: $s.health.loop,
          mode: ($s.control.mode // null), cap: ($s.health.builderCap // null), guard: ($s.control.guard // null), used: used,
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
          landedToday: $s.landedCount, todayUsd: $s.cost.today, todayLeftOut: ($s.cost.todayLeftOut | numbers // 0)}],
        foremen: $fm.foremen, foremenError: $fm.error}} end)}'

# stream_conv -- the live feed's Conveyor part: stream.json, when dashboard_stream.py wrote it in the last
# STREAM_FRESH seconds and it holds a snapshot of every record. Nothing printed and 1 otherwise.
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

# publish_lock -- one build of data.js at a time: the cycle's and the feed's (--publish). A lock older than a minute
# is a build that was killed, and is taken over. The lock goes with this process (the EXIT trap) or with publish.
publish_lock() {
  local i
  for i in $(seq 100); do
    mkdir "$OUT/.publish.lock" 2>/dev/null && { LCK=$OUT/.publish.lock; return 0; }
    [ $(( $(date +%s) - $(stat -c %Y "$OUT/.publish.lock" 2>/dev/null || date +%s) )) -lt 60 ] || rmdir "$OUT/.publish.lock" 2>/dev/null
    sleep 0.1
  done
  echo "dashboard: another build of data.js holds $OUT/.publish.lock" >&2; return 1
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
  local k e='not read yet: the collector has just started and its first cycle is still reading'
  for k in limit decisions lanes foremen; do
    if [ -s "$CACHE/part-$k.json" ]; then cp "$CACHE/part-$k.json" "$RUN/$k.json" || return 1
    else jq -cn --arg k "$k" --arg e "$e" '{limit: {limit: null}, decisions: {decisions: null, unsent: []},
        lanes: {records: null}, foremen: {foremen: null}}[$k] + {error: $e}' > "$RUN/$k.json" || return 1; fi
  done
}

# --history: the Landed, Metrics, Cost and Declined parts as data.js has them, but built from every entry: each
# record's `conveyor.sh history` (the lists whole, of which its snapshot holds the newest) laid into its record. The
# page server gives it at GET /history, which the page asks for while one of those panels is shown, never with the
# live feed. Printed as {updatedAt, panels}, and kept in cache/history.json, with the ledger key it was built for in
# cache/history.key. The ledger key is cut from the live feed's records, with no host read
# (ledger_key). While the live feed's key is the kept one, the kept copy is printed; the page server's POST /control
# drops the kept copy and key, so the next ask builds again. With no key (no live feed, or a record with no
# historySum) the copy is printed while it is under HISTORY_TTL seconds old. The rest of each record is the live
# feed's (with none running, read as a cycle reads it), the other parts those the last cycle kept. A host that gives no
# history of every record prints nothing: exit 1. The page server reads the same key and copy itself (kept_history).
# ledger_key <conveyor.json>: each record's repo, snapshot historySum (the cksum of its history less the Metrics cards'
# wait and run times, so any other change to an entry changes it, and the clock alone does not) and day, as one line;
# nothing and 1 when a record has no historySum.
ledger_key() {
  jq -ce '[.records[] | {repo, h: .snap.historySum, day: .snap.day}] | select(all(.[]; .h | type == "string"))' "$1"
}
history() {
  local host main engine target recs why remote cmd f=$CACHE/history.json k=$CACHE/history.key at key='' live=''
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  stream_conv > "$RUN/conveyor.json" && live=1 && key=$(ledger_key "$RUN/conveyor.json") || key=''
  if [ -n "$key" ]; then  # the key before the copy: the copy is written before its key, and dropped after it
    [ "$(cat "$k" 2>/dev/null)" = "$key" ] && jq -ce 'objects' "$f" 2>/dev/null && return 0
  else
    at=$(stat -c %Y "$f" 2>/dev/null) && [ $(( $(date +%s) - at )) -lt $HISTORY_TTL ] && jq -ce 'objects' "$f" 2>/dev/null && return 0
  fi
  NOW=$(date +%s)
  hostof || { echo "dashboard: no history: $why" >&2; return 1; }
  cmd=$(jq -r --arg e "$engine/conveyor/conveyor.sh" 'map("CONVEYOR_MAIN=\(.main | @sh) bash \($e | @sh) history") | join(" && ") + " && echo @@end"' <<<"$recs")
  onhost "$cmd" > "$RUN/history" 2>"$RUN/err-history" \
    || { echo "dashboard: $host gave no history: $(tail -n 1 "$RUN/err-history" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  { [ -n "$live" ] || conveyor > "$RUN/conveyor.json"; } && kept_parts || return 1
  jq -c --argjson recs "$recs" --rawfile h "$RUN/history" '($h | split("\n")) as $l | ($recs | length) as $n
    | if ($l | index("@@end")) != $n or (.records | type) != "array" then error("no history of every record") else . end
    | ([range(0; $n) as $i | {key: $recs[$i].repo, value: ($l[$i] | fromjson | objects)}] | from_entries) as $x
    | .records |= map($x[.repo] as $o | if $o == null then . else .snap |= (.landed = $o.landed | .metrics.cards = $o.metrics.cards
        | .cost.cards = $o.cost.cards | .cost.unpriced = $o.cost.unpriced | .declinedRest = $o.declinedRest) end)' \
    "$RUN/conveyor.json" > "$RUN/conveyor.whole" 2>"$RUN/err-history" && mv -f "$RUN/conveyor.whole" "$RUN/conveyor.json" \
    || { echo "dashboard: $host gave no history of every record" >&2; return 1; }
  panels | jq -c '{updatedAt, panels: (.panels | {landed, metrics, cost, declined})}' > "$RUN/out" && [ -s "$RUN/out" ] \
    && mv -f "$RUN/out" "$f" || return 1
  # The key of the copy now kept; none with no key, so a later live feed's key never matches a copy built without it.
  if [ -n "$key" ]; then printf '%s\n' "$key" > "$RUN/key" && mv -f "$RUN/key" "$k"; else rm -f "$k"; fi
  cat "$f"
}

# --work: the Health panel's Work now, what keeps the Conveyor host busy now: `conveyor.sh work --json` of the first
# record, which reads every record's cards, in one command to the host (hostof, onhost), as one {host, groups, other}:
# every record's busy cards (its groups), the heaviest first, and the busy processes no record's card owns. Each
# command is cut to 200 characters. The page server gives it at GET /work, which the page asks for when the owner
# opens Work now or reads it again; never kept.
work() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no work reading: $why" >&2; return 1; }
  cmd=$(jq -er --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | .main | @sh | "CONVEYOR_MAIN=\(.) bash \($e | @sh) work --json")' <<<"$recs") \
    || { echo "dashboard: no work reading: the host file names no record" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" > "$RUN/work" 2>"$RUN/err-work" \
    || { echo "dashboard: $host gave no work reading: $(tail -n 1 "$RUN/err-work" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  jq -ce --arg h "$host" '{host: $h, groups: (.groups | sort_by(-.cpu) | map(.processes |= map(.command |= .[:200]))),
       other: (.other | map(.command |= .[:200]))}' "$RUN/work" 2>"$RUN/err-work" \
    || { echo "dashboard: $host gave no work reading" >&2; return 1; }
}

# --older <repo> <test file>: the older runs and test edits of one test file of a record, which the snapshot leaves
# out: its `conveyor.sh history test <file>` and its origin's address, in one command to the host (hostof, onhost), as
# {file, olderRuns, olderEdits}, each run tagged with its card's issue and that issue's url as the Tests part's runs
# are. The page server gives it at GET /older, which the Tests page asks for when a file's Timeline is opened; never
# kept.
older() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no older runs: $why" >&2; return 1; }
  cmd=$(jq -er --arg r "$1" --arg f "$2" --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | select(.repo == $r) | .main | @sh)
      | "CONVEYOR_MAIN=\(.) bash \($e | @sh) history test \($f | @sh) && { git -C \(.) remote get-url origin 2>/dev/null || echo; }"' <<<"$recs") \
    || { echo "dashboard: no older runs: the host file names no record $1" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" > "$RUN/older" 2>"$RUN/err-older" \
    || { echo "dashboard: $host gave no older runs: $(tail -n 1 "$RUN/err-older" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  jq -ceRs --arg r "$1" 'split("\n") as $l | ($l[1] | (capture("github\\.com[:/](?<p>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(\\.git)?$") | "https://github.com/\(.p)") // null) as $u
    | $l[0] | fromjson | objects | select((.olderRuns | type) == "array" and (.olderEdits | type) == "array")
    | .olderRuns |= map(objects | (.issue = ([.card | strings | capture("-(?<n>[1-9][0-9]{0,8})$").n | tonumber][0] // null))
        | . + {repo: $r, url: (if $u != null and .issue != null then "\($u)/issues/\(.issue)" else null end)})' "$RUN/older" 2>"$RUN/err-older" \
    || { echo "dashboard: $host gave no older runs" >&2; return 1; }
}

# --donewhen <repo> <card id>: a card's last Done-when check of a record, item by item, which the snapshot leaves out:
# its `conveyor.sh history donewhen <card id>`, in one command to the host (hostof, onhost), as {card, items: [{n, text,
# builder, reviewer}]}. The page server gives it at GET /donewhen, which the Board asks for when a card's Done-when line
# is opened; never kept.
donewhen() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no Done-when detail: $why" >&2; return 1; }
  cmd=$(jq -er --arg r "$1" --arg c "$2" --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | select(.repo == $r) | .main | @sh)
      | "CONVEYOR_MAIN=\(.) bash \($e | @sh) history donewhen \($c | @sh)"' <<<"$recs") \
    || { echo "dashboard: no Done-when detail: the host file names no record $1" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" > "$RUN/donewhen" 2>"$RUN/err-donewhen" \
    || { echo "dashboard: $host gave no Done-when detail: $(tail -n 1 "$RUN/err-donewhen" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  jq -ce 'objects | select(.items | type == "array")' "$RUN/donewhen" 2>"$RUN/err-donewhen" \
    || { echo "dashboard: $host gave no Done-when detail" >&2; return 1; }
}

# --shot <repo> <card> <file>: one screenshot a card waiting for the owner's yes kept, in its kept folder on the host
# (shots/ of kept/<card> in the record's state folder: keepshots(), conveyor/lib/push.sh), as base64 on one ssh
# command. The page server (GET /shot) checks the card and file are of the shapes the snapshot names.
shot() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no screenshot: $why" >&2; return 1; }
  cmd=$(jq -er --arg r "$1" --arg c "$2" --arg f "$3" --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | select(.repo == $r) | .main | @sh)
      | "f=\"$(CONVEYOR_MAIN=\(.) bash \($e | @sh) state-dir)\"/kept/\($c | @sh)/shots/\($f | @sh) && [ -f \"$f\" ] && base64 < \"$f\""' <<<"$recs") \
    || { echo "dashboard: no screenshot: the host file names no record $1" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" 2>"$RUN/err-shot" || { echo "dashboard: $host gave no screenshot $3 of card $2: $(tail -n 1 "$RUN/err-shot" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
}

# --excerpts <repo> <card id>: the lines a card's review findings cite, as each review kept them from the tree it read,
# which the snapshot leaves out: its `conveyor.sh history excerpts <card id>`, in one command to the host (hostof,
# onhost), as {card, excerpts: [{review, at, side, from, lines}]}. The page server gives it at GET /excerpts, which the
# Board asks for when a finding's place is opened; never kept.
excerpts() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no reviewed lines: $why" >&2; return 1; }
  cmd=$(jq -er --arg r "$1" --arg c "$2" --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | select(.repo == $r) | .main | @sh)
      | "CONVEYOR_MAIN=\(.) bash \($e | @sh) history excerpts \($c | @sh)"' <<<"$recs") \
    || { echo "dashboard: no reviewed lines: the host file names no record $1" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" > "$RUN/excerpts" 2>"$RUN/err-excerpts" \
    || { echo "dashboard: $host gave no reviewed lines: $(tail -n 1 "$RUN/err-excerpts" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  jq -ce 'objects | select(.excerpts | type == "array")' "$RUN/excerpts" 2>"$RUN/err-excerpts" \
    || { echo "dashboard: $host gave no reviewed lines" >&2; return 1; }
}

# --bench <repo> [<run>]: the Benchmarks tab's history (every run with each arm's figures, and the arms) or, with a
# run's id, that run's tasks by arm, which the snapshot leaves out: the record's `conveyor.sh bench swe history` or
# `bench swe show <run>`, in one command to the host (hostof, onhost). The page server gives it at GET /bench, which
# the tab asks for when it is shown and when a run is opened; never kept.
bench() {
  local host main engine target recs why remote cmd
  hostof || { echo "dashboard: no benchmarks: $why" >&2; return 1; }
  cmd=$(jq -er --arg r "$1" --arg run "$2" --arg e "$engine/conveyor/conveyor.sh" 'first(.[] | select(.repo == $r) | .main | @sh)
      | "CONVEYOR_MAIN=\(.) bash \($e | @sh) bench swe \(if $run == "" then "history" else "show \($run | @sh)" end)"' <<<"$recs") \
    || { echo "dashboard: no benchmarks: the host file names no record $1" >&2; return 1; }
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  onhost "$cmd" > "$RUN/bench" 2>"$RUN/err-bench" \
    || { echo "dashboard: $host gave no benchmarks: $(tail -n 1 "$RUN/err-bench" | tr -d '\r' | cut -c1-200)" >&2; return 1; }
  jq -ce 'objects' "$RUN/bench" 2>/dev/null || { echo "dashboard: $host gave no benchmarks" >&2; return 1; }
}

# view_files -- the page's files, relative to .claude/dashboard: the page, its core, its tab icon and one file per panel.
view_files() { (cd "$VIEW_SRC" && find . -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' -o -name '*.svg' \) | sed 's|^\./||' | LC_ALL=C sort); }
# copy_view -- copy each page file from the primary checkout into $OUT, skipping one that is already the same. Each
# --loop cycle runs it too, so a landed page change is served without a reinstall. The checksum of the installed page
# files, alive.js's `view`, is worked out here, when a file was copied or the list of files changed, into $OUT/.view
# (the list in $OUT/.view-files): alive reads that, not every page file each 15 s.
copy_view() {
  local f list moved=''
  list=$(view_files)
  while IFS= read -r f; do
    [ -n "$f" ] || continue  # no page files: the one empty line <<< gives
    cmp -s "$VIEW_SRC/$f" "$OUT/$f" && continue
    { mkdir -p "$(dirname "$OUT/$f")" && cp "$VIEW_SRC/$f" "$OUT/$f.new.$$" && mv -f "$OUT/$f.new.$$" "$OUT/$f"; } 2>/dev/null \
      || { rm -f "$OUT/$f.new.$$"; echo "dashboard: could not copy $VIEW_SRC/$f into $OUT" >&2; return 1; }
    moved=1
  done <<<"$list"
  [ -z "$moved" ] && [ -s "$OUT/.view" ] && [ "$list" = "$(cat "$OUT/.view-files" 2>/dev/null)" ] && return 0
  rm -f "$OUT/.view"  # a checksum that may be wrong is none, until the new one is in
  { printf '%s\n' "$list" > "$OUT/.view-files" \
    && (cd "$OUT" && xargs -d '\n' cat <<<"$list" 2>/dev/null) | cksum | cut -d' ' -f1 > "$OUT/.view.$$" \
    && mv -f "$OUT/.view.$$" "$OUT/.view"; } 2>/dev/null \
    || { rm -f "$OUT/.view.$$"; echo "dashboard: could not write the page's checksum into $OUT" >&2; return 1; }
}

# The job runs BOARD's copy (the primary checkout's, or the release install's). Every file it points at is checked
# before anything changes.
install() {
  local script=$BOARD/scripts/$NAME.sh f
  for f in "$script" "$VIEW_SRC/index.html" "$VIEW_SRC/app.css" "$VIEW_SRC/app.js"; do
    [ -s "$f" ] || { echo "dashboard: install needs $f, which is missing or empty" >&2; return 1; }
  done
  bash -n "$script" || { echo "dashboard: $script does not parse" >&2; return 1; }
  mkdir -p "$OUT" || return 1
  copy_view || return 1
  # The server needs the Board's own packages; without them the restarted job would serve nothing.
  "$BOARD_PY" -c 'import pyotp, segno, cryptography' 2>/dev/null \
    || { echo "dashboard: the Board's Python ($BOARD_PY) or its packages are missing: run /conveyor-belt:setup (conveyor.sh doctor names what is missing)" >&2; return 1; }
  # The page is served over HTTPS only; this makes the self-signed certificate once and keeps it after that.
  "$BOARD_PY" "${script%/*}/dashboard_server.py" make-cert >/dev/null || { echo "dashboard: could not make the HTTPS certificate" >&2; return 1; }
  # A restart that no one can get past the login (No login on this device off, and no admin with a password) serves a
  # page nobody can open, and the old server is gone by then. Asked here with the environment the job below is given,
  # so the store checked is the store the restarted job serves.
  "$BOARD_PY" "${script%/*}/dashboard_server.py" can-open || return 1
  # Every override set at install time goes into the job; with only PATH and HOME it reads the default folders.
  local k mac="" sysd=""
  for k in CONVEYOR_DASHBOARD_AUTH CONVEYOR_RULING_LOG CONVEYOR_DASHBOARD_DIR CONVEYOR_MAIN CONVEYOR_WORKSPACES CONVEYOR_SCRATCH XDG_CONFIG_HOME XDG_DATA_HOME; do
    [ -n "${!k:-}" ] || continue
    mac+="<key>$k</key><string>$(xml "${!k}")</string>"; sysd+="Environment=\"$k=${!k}\""$'\n'
  done
  if [ "$(host_os)" = Darwin ]; then
    local plist=$HOME/Library/LaunchAgents/$LABEL_PREFIX$NAME.plist
    mkdir -p "${plist%/*}" || return 1
    cat > "$plist.new.$$" <<EOF || { rm -f "$plist.new.$$"; return 1; }
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL_PREFIX$NAME</string>
<key>ProgramArguments</key><array><string>$(xml "$BASH")</string><string>$(xml "$script")</string><string>--loop</string></array>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>$(xml "$PATH")</string><key>HOME</key><string>$(xml "$HOME")</string>$mac</dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>$(xml "$OUT/$NAME.log")</string>
<key>StandardErrorPath</key><string>$(xml "$OUT/$NAME.log")</string>
</dict></plist>
EOF
    mv -f "$plist.new.$$" "$plist" || return 1
    launchctl bootout "gui/$(id -u)/$LABEL_PREFIX$NAME" 2>/dev/null || true
    # bootout returns before the job is gone; bootstrapping in that window fails (error 5).
    for _ in $(seq 50); do launchctl print "gui/$(id -u)/$LABEL_PREFIX$NAME" >/dev/null 2>&1 || break; sleep 0.1; done
    launchctl bootstrap "gui/$(id -u)" "$plist" || { echo "dashboard: launchctl refused $plist" >&2; return 1; }
  else
    local svc=$HOME/.config/systemd/user/$NAME.service
    mkdir -p "${svc%/*}" || return 1
    cat > "$svc" <<EOF || return 1
[Unit]
Description=Conveyor dashboard: re-collects $OUT/data.js every 60 s

[Service]
ExecStart="$BASH" "$script" --loop
Environment="PATH=$PATH"
Environment="HOME=$HOME"
${sysd}Restart=always
RestartSec=10
MemoryMax=256M

[Install]
WantedBy=default.target
EOF
    # restart, not `enable --now`, which leaves a running service on its old service file.
    systemctl --user daemon-reload && systemctl --user enable "$NAME.service" && systemctl --user restart "$NAME.service"
  fi
}

# alive -- the --loop heartbeat, $OUT/alive.js: the time now and the cycle stamps the loop left in $OUT/.cycle. The
# page tells a slow cycle (fresh heartbeat, old data.js) from a stopped collector (no heartbeat) by it. `view` is a
# checksum of the installed page files, as copy_view last worked it out ($OUT/.view; null before it has, which the
# page does not compare): a page left open reloads when it changes. No page file is read here.
alive() {
  local at age=null view=null  # snapshotAgeSec: how old the published data.js is, null before the first
  at=$(stat -c %Y "$OUT/data.js" 2>/dev/null) && age=$(( $(date +%s) - at ))
  view=$(cat "$OUT/.view" 2>/dev/null) && [[ $view =~ ^[0-9]+$ ]] && view="\"$view\"" || view=null
  printf 'window.DASH_ALIVE = {"at":"%s","view":%s,"snapshotAgeSec":%s,%s};\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$view" "$age" \
    "$(cat "$OUT/.cycle" 2>/dev/null || echo '"cycleStartedAt":null,"lastCycleSec":null')" > "$OUT/.alive.js.$BASHPID" \
    && mv -f "$OUT/.alive.js.$BASHPID" "$OUT/alive.js"
}
# cycle <start-epoch> <seconds|null> -- stamp the cycle for alive.js; written whole, so alive never reads half.
cycle() {
  printf '"cycleStartedAt":"%s","lastCycleSec":%s' "$(iso "$1")" "$2" > "$OUT/.cycle.tmp" && mv -f "$OUT/.cycle.tmp" "$OUT/.cycle"
  alive
}

# The job's own manager restarts it; the label is the one install wrote.
# cert -- the page server's certificate, kept when it loads, else made again by make-cert, with one line in the log
# that says why (make-cert's first line). 1 when openssl could not make it; the server's own error then follows.
cert() {
  local out
  out=$("$BOARD_PY" "$HERE/dashboard_server.py" make-cert 2>&1) \
    || { echo "$(date +%FT%T) dashboard: could not make the HTTPS certificate: ${out//$'\n'/ }" >&2; return 1; }
  [[ $out == 'certificate kept: '* ]] || echo "$(date +%FT%T) dashboard: ${out%%$'\n'*}" >&2
}

restart() {
  if [ "$(host_os)" = Darwin ]; then launchctl kickstart -k "gui/$(id -u)/$LABEL_PREFIX$NAME"
  else systemctl --user --no-block restart "$NAME.service"; fi
}

# The files the loop's long-lived processes run or read once: the loop, the page server, the live feed and what the
# live feed reads when it starts (its records and their host). The loop sources nothing. Every other file is
# read afresh by each cycle or request, so a change to it needs no restart.
RESTART_FILES=(.claude/scripts/dashboard.sh .claude/scripts/dashboard_server.py .claude/scripts/dashboard_stream.py
  conveyor/host.json)
# update -- brings the main checkout forward to origin/main (fetched at most every FETCH_EVERY seconds: fetch_main),
# by a fast-forward only, and restarts the service
# when one of RESTART_FILES changed. A checkout on another branch, with a merge in progress or with commits
# origin/main does not have is left as it is; a fast-forward that would overwrite a changed file is git's to refuse,
# with autostash off, so a changed file is never merged into the new code.
# Each run writes $OUT/update.json, which the Health part carries: {checkedAt, head, error (why the checkout was not
# brought forward), moved (the last move, kept across runs, so the page says the restart was on new code; with
# restartFailed while its restart has not succeeded, which each run retries)}.
update() {
  local m=$PP_MAIN br out err='' moved from to n restart=false
  moved=$(jq -ce '.moved | objects' "$OUT/update.json" 2>/dev/null) || moved=null
  # A restart that failed is still owed, through any later move too.
  if [ "$(jq -r '.restartFailed == true' <<<"$moved")" = true ]; then restart=true; moved=$(jq -c 'del(.restartFailed)' <<<"$moved"); fi
  br=$(git -C "$m" symbolic-ref -q --short HEAD 2>/dev/null) || br=''
  if [ "$br" != main ]; then err="the checkout is on ${br:-a detached HEAD}, not main; it is left as it is"
  elif git -C "$m" rev-parse -q --verify MERGE_HEAD >/dev/null; then err="a merge is in progress in the checkout; it is left as it is"
  elif ! out=$(fetch_main "$m" 2>&1); then err="origin/main could not be fetched: $({ grep -m 1 '^fatal:' <<<"$out" || tail -n 1 <<<"$out"; } | cut -c1-200)"
  elif ! n=$(git -C "$m" rev-list --count origin/main..main 2>&1); then err="origin/main could not be compared: $(tail -n 1 <<<"$n" | cut -c1-200)"
  elif [ "$n" -gt 0 ]; then err="main has $n commit(s) that origin/main does not; it is left as it is"
  elif [ "$(git -C "$m" rev-list --count main..origin/main)" -gt 0 ]; then
    from=$(git -C "$m" rev-parse HEAD)
    if ! out=$(git -C "$m" merge -q --ff-only --no-autostash origin/main 2>&1); then
      err="git refused the fast-forward: $(tr '\n\t' '  ' <<<"$out" | tr -s ' ' | cut -c1-300)"
    else
      to=$(git -C "$m" rev-parse HEAD)
      [ -z "$(git -C "$m" diff --name-only "$from" "$to" -- "${RESTART_FILES[@]}")" ] || restart=true
      moved=$(jq -cn --arg f "${from:0:12}" --arg t "${to:0:12}" --arg at "$(iso "$(date +%s)")" --argjson r $restart '{from: $f, to: $t, at: $at, restart: $r}')
      echo "$(date +%FT%T) dashboard: brought main forward ${from:0:12}..${to:0:12}$([ $restart = false ] || echo '; restarting on the new code')" >&2
    fi
  fi
  write_update "$err" "$moved" || return 1
  [ $restart = true ] || return 0
  restart && return 0
  write_update "the checkout moved to new code, but the restart failed; the dashboard still runs the old code" "$(jq -c '.restartFailed = true' <<<"$moved")"
  return 1
}
# fetch_main <checkout> -- fetches origin main at most every FETCH_EVERY seconds: $CACHE/update-fetched holds the time
# of the last fetch that worked, and a run before it is that old uses what that fetch got. A failed fetch writes no
# stamp, so the next run tries again; a stamp from the future (a clock set back) is taken as old.
FETCH_EVERY=300
fetch_main() {
  local now at
  now=$(date +%s); at=$(cat "$CACHE/update-fetched" 2>/dev/null) || at=''
  [[ $at =~ ^[0-9]+$ ]] && [ "$at" -le "$now" ] && [ $((now - at)) -lt $FETCH_EVERY ] && return 0
  timeout 120 git -C "$1" fetch -q origin main || return 1
  mkdir -p "$CACHE" && echo "$now" > "$CACHE/update-fetched"
}
# write_update <error> <moved> -- update.json, written whole.
write_update() {
  jq -cn --arg at "$(iso "$(date +%s)")" --arg h "$(git -C "$PP_MAIN" rev-parse --short=12 HEAD 2>/dev/null)" --arg e "$1" --argjson mv "$2" \
    '{checkedAt: $at, head: (if $h == "" then null else $h end), error: (if $e == "" then null else $e end), moved: $mv}' > "$OUT/.update.json.$$" \
    && mv -f "$OUT/.update.json.$$" "$OUT/update.json"
}

uninstall() {
  if [ "$(host_os)" = Darwin ]; then
    launchctl bootout "gui/$(id -u)/$LABEL_PREFIX$NAME" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$LABEL_PREFIX$NAME.plist"
  else
    systemctl --user disable --now "$NAME.service" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/$NAME.service"
    systemctl --user daemon-reload
  fi
}

case "${1:-}" in
  --install) install || { echo "dashboard: install FAILED" >&2; exit 1; }
             echo "dashboard installed; open $OUT/index.html, or https://<this host>.local:$PORT/ from the LAN"; exit 0 ;;
  --uninstall) uninstall; echo "dashboard uninstalled"; exit 0 ;;
  --restart) restart; exit $? ;;
  --update) mkdir -p "$OUT" || exit 1
            update || exit 1 ;;
  --loop) mkdir -p "$OUT" || exit 1
          rm -f "$OUT/.cycle"
          # Every 15 s while this loop lives; a cycle's start and end also write it at once.
          { while kill -0 $$ 2>/dev/null; do alive; sleep 15; done; } & ALV=$!
          last=null
          while :; do
            # Restarted here if it stopped. Its stderr stays in the log: "no certificate" must be seen. Before each
            # start, a certificate that is missing, empty or does not load is made again (cert): the server would
            # exit at once on it, every cycle.
            [ -n "$SRV" ] && kill -0 "$SRV" 2>/dev/null \
              || { cert; "$BOARD_PY" "$HERE/dashboard_server.py" "$PORT" "$OUT" >/dev/null & SRV=$!; }
            # The live feed, restarted here too; its stderr (a stream that keeps failing) stays in the log. The temp
            # files a feed that ended mid-write left are removed first: no feed writes them now.
            [ -n "$STM" ] && kill -0 "$STM" 2>/dev/null \
              || { rm -f "$OUT"/.stream.json.*; python3 "$HERE/dashboard_stream.py" "$OUT" "$PP_MAIN" >/dev/null & STM=$!; }
            copy_view || echo "dashboard: page refresh FAILED; the page keeps the last copy" >&2
            t0=$(date +%s); cycle "$t0" "$last"
            # The cycle is this script run once more, so a hung read can be killed from outside. TERM first,
            # KILL 10 s later; a KILLed cycle runs no exit trap, so its temporary files are cleared here.
            timeout -k 10 "$CYCLE_LIMIT" "$BASH" "$HERE/$NAME.sh"; rc=$?
            if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
              echo "$(date +%FT%T) dashboard: cycle killed after $CYCLE_LIMIT s; data.js keeps the last snapshot" >&2
              rm -rf "$OUT"/.run.* "$OUT"/.data.js.*
            fi
            last=$(( $(date +%s) - t0 )); cycle "$t0" "$last"
            [ "$last" -le 60 ] || echo "$(date +%FT%T) dashboard: cycle took $last s" >&2
            # The shared installs follow main's lockfiles here, between cycles, where sync-install.sh is installed (a
            # release folder has none). A wait repeats every cycle, so only a changed line is logged.
            si=''; [ ! -e "$HERE/sync-install.sh" ] || si=$(timeout -k 10 "$CYCLE_LIMIT" "$BASH" "$HERE/sync-install.sh" 2>&1)
            [ -z "$si" ] || [ "$si" = "${si_last-}" ] || echo "$si" | sed "s/^/$(date +%FT%T) /" >&2
            si_last=$si
            timeout -k 10 "$CYCLE_LIMIT" "$BASH" "$HERE/$NAME.sh" --update
            sleep 60 & wait $!; done ;;  # a foreground sleep would hold off the TERM trap that stops the server
  --publish) mkdir -p "$CACHE" || exit 1
             republish || { echo "dashboard: publishing the live feed FAILED; data.js keeps the last snapshot" >&2; exit 1; } ;;
  --history) mkdir -p "$CACHE" || exit 1
             history || exit 1 ;;
  --work) mkdir -p "$OUT" || exit 1
          work || exit 1 ;;
  --bench) [ $# = 2 ] || [ $# = 3 ] || { echo "usage: dashboard.sh --bench <repo> [<run>]" >&2; exit 2; }
           mkdir -p "$OUT" || exit 1
           bench "$2" "${3:-}" || exit 1 ;;
  --older) [ $# = 3 ] || { echo "usage: dashboard.sh --older <repo> <test file>" >&2; exit 2; }
           mkdir -p "$OUT" || exit 1
           older "$2" "$3" || exit 1 ;;
  --donewhen) [ $# = 3 ] || { echo "usage: dashboard.sh --donewhen <repo> <card id>" >&2; exit 2; }
              mkdir -p "$OUT" || exit 1
              donewhen "$2" "$3" || exit 1 ;;
  --shot) [ $# = 4 ] || { echo "usage: dashboard.sh --shot <repo> <card> <file>" >&2; exit 2; }
          mkdir -p "$OUT" || exit 1
          shot "$2" "$3" "$4" || exit 1 ;;
  --excerpts) [ $# = 3 ] || { echo "usage: dashboard.sh --excerpts <repo> <card id>" >&2; exit 2; }
              mkdir -p "$OUT" || exit 1
              excerpts "$2" "$3" || exit 1 ;;
  --check) check || exit 1 ;;
  "") mkdir -p "$OUT" || exit 1
      render || { echo "dashboard: collection FAILED; data.js keeps the last snapshot" >&2; exit 1; } ;;
  *) echo "usage: dashboard.sh [--install|--uninstall|--restart|--loop|--publish|--update|--history|--work|--older <repo> <test file>|--donewhen <repo> <card id>|--shot <repo> <card> <file>|--excerpts <repo> <card id>|--bench <repo> [<run>]|--check]" >&2; exit 2 ;;
esac
