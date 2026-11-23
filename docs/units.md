# /units: Conveyor's board inside Claude Code

The plugin's `hooks/units.tsx` (registered by `hooks/index.tsx`, the hooks module `hooks/hooks.json` names under `modules`) shows Conveyor's board in
two places: `/units` and a side pane (`Conveyor`). With the pane on, a toast also shows when a card newly needs you or
lands. It only reads; it writes no file. It comes with the plugin: there is nothing else to
install.

It registers nothing outside a checkout with Conveyor's project settings (`.conveyor/project.json` in the main
checkout), so other projects on the profile are unaffected. In such a project it shows every project of the machine's
host file (its settings file), whether or not the session's project is the plugin's own.

## What it shows

This list is what `/units` prints. The pane shows the same board in a different layout: [The pane](#the-pane) tells
how. No time is estimated from past cards: only what was measured is shown. A figure is never cut: figures are
right-aligned and the title is what gives way.

- A head, two lines: `CONVEYOR`, dollars today and the Conveyor host (`● buildbox`); then the weekly limit with its
  reset (`weekly limit 94% · resets 1d 18h`) and the counts on the belt and queued. While the loop runs with a builder
  cap, the `ON THE BELT` head gives the cards on the belt and the cap. It also gives a card that lands or has landed,
  which the cap does not count (`ON THE BELT (2 of 7, 1 landing not counted)`). When the snapshot is older than the
  card records or the loop's own count, the head gives the count the loop gives now. When the loop gives no count, the
  head gives 0. The Board uses the loop's count only when the snapshot is older than the card records. With more than
  one project, each project's count follows its name (`ON THE BELT (bakery 1 of 3 · gadgetlab 1)`). In `/units` a
  third line gives how many findings the review's judge declined today (`judge declined 3 findings today`), from the
  snapshot's declined list (its `declined` and `declinedRest` lines by the judge, by this machine's day, each line
  once).
- **The Foreman**, under the head: `Foreman listening`, or `Foreman not listening` with the reason (`not the Foreman
  session`, `waiter starting again`, `waiter down: <why>`, `no waiter running`, `waiter on an old install`, `watcher
  down: <name>`; `docs/foreman.md` says what each one means). In `/units` (in the pane, under Machine details) a dim
  line under it gives the session that has the role, the waiter's process and version, and the state of each watcher.
  A narrow view wraps that line onto more lines, so no watcher is lost.
  A project where no session has the
  Foreman role and no Foreman is set up shows no Foreman line. [Foreman](foreman.md) tells what each reason means.
- **The whole suite**, in `/units` and the pane, under the head: while a release suite or a full test run is in
  progress, a line for it with the kind (`release 1.2.0` or `full test`), the short commit and the time it has run, and
  under it the cases done and the failures until now, once there are counts to show (`release 1.2.0 · a1b2c3d · running
  12m`, then `140 cases done · 2 failures`). While a
  release runs its failed cases again, the first line shows the pass of all the passes in place of the time, and the
  line under it shows its test files done and failed and when it last moved, in place of the counts (`release 1.2.0 ·
  a1b2c3d · failed cases again: pass 2 of 6`, then `1 file done · 1 failed · moved 3m ago`). When the run
  ends, the line shows the result (`passed 3m ago`) for 10 minutes, then it goes away.
  A release suite that runs on another machine (a Namespace Devbox or a Linux box over ssh, chosen in the control
  record) names it after the commit: `release 1.10.0 · 3342e0e · on Devbox XL · running 5m 20s`, then `1204 cases done ·
  0 failures` under it. Before the tests start, the line gives the step of the box instead of `running`: `starting the box`,
  `setting up`, `checking out` or, at the end, `bringing back results`, and there is no line of counts under it. When the run ends, it shows how long the run
  took, then how long ago it ended, and for a Devbox `box given back` once its lease is back (`passed 8m 50s · 2 min
  ago · box given back`). A suite on this machine has no machine part.
- **The test map**, in `/units` under the head and in the pane under Machine details: one line. While setup or a whole run on main makes the
  map, the line shows the test files run so far, the time so far and a bar
  (`Test map: 12 of 40 test files · 3m ▰▰▰▱▱▱▱▱▱▱`). A narrow view cuts the text and keeps the bar. After the run, the
  line shows the state of the map:
  - made: the source and test files that it maps, and how many commits it is behind main
    (`Test map: 120 source, 40 test files · 3 commits behind main`). A map that your project keeps has no count of
    commits.
  - not made yet: `Test map: not made yet · run /conveyor-belt:setup to make it`.
  - off: `Test map: off`, when `test.map` is `off` in `.conveyor/project.json`.
  - failed: `Test map: failed: <why>`, when the last run that made the map failed, or stopped before it ended.
- **An old engine**, in `/units` and the pane, above the test map: when the project runs an older Conveyor commit on
  this machine than the newest one it can take, the line `doctor` prints (`Conveyor runs an old engine here: ...`), in
  red. A narrow view wraps it between words, so the command at its end stays whole. While a take of the newer commit
  runs, the line says so in its place (`Conveyor takes the plugin's main now: ...`).
  [Following releases or main](setup.md#following-releases-or-main-or-pinning-a-commit) tells what it means.

  A checkout with no `.conveyor/project.json` shows no test map line
  ([The test map](configuration.md#the-test-map)).
- **The judge**, in `/units` only: a card (needing you, on the belt or landed) whose latest review the judge ran on has
  a dim line `judge: 2 accepted, 1 declined`, with ` · GO from declines only` when the GO came from the judge declining
  every finding. A latest review the judge did not run on (off, failed, nothing to judge) has no such line.
- **Kept work**, in `/units`: a card (needing you, or on the belt) that took up the kept patch of an earlier card of
  its issue has a dim line that names that card, as its start line gives it:
  `resumed from the kept patch of card <card>: one session, then review`. A card of an issue with no kept patch has
  no such line.
- **NEEDS YOU**: one line, `NEEDS YOU  nothing`, when nothing does. Else cards waiting for your yes to a visible
  change (with the reviewer's sentence), then blocked cards (with the reason). A blocked card is off the belt, so the
  step it stopped in is said here: `failed at Build (step 1 of 6) after 12m`, then its six steps and one line for each
  finished review (`R1 NO-GO  1 P1, 2 P2`; a review recorded with no counts shows its verdict alone), and its
  measurements (below).
- **ON THE BELT**: under the heading, the same count against the builder cap as the head, when the loop gives it; then
  three lines a card and a blank line between cards.
  1. The issue and its short title in bold (a follow-up: what it fixes and the issue it came from, `Board: … ↳ #12`,
     never the raw `[P2] path:line …` title), then right-aligned when the card was picked up (local time, with the date
     when it is not today), its overall time so far (from its pick-up, never the time it sat queued; a card resumed
     from a kept patch counts the earlier card's time and shows its first start) and its cost (`no reading yet` before
     any token is read, never $0; `cost shown when the step ends` when the running session's route reports no token
     use until the step ends; `cost partial` when a step has no price).
  2. The six steps Build, Review, Fix, Test, Land, Push as one track: done `✓` with a filled join `━━`, the step in
     progress lit `▶`, to come dim, skipped `–` (Fix after a GO), failed `✗` in red. Where the width has room, a
     done step adds the time it took (`✓ Build 16m`) and a step that ran more than once its count (`Review 2 of 3`,
     `Fix 2`); the times give way first, then the counts, and what gave way is on a dim line under the track
     (`Test 16m · Land 16m`), so no measured time or count is lost. A lint fix before a review, after the build, is
     on Build: `▶ Build · lint fix` while it runs, then `✓ Build 16m · lint fixed`. A lint fix before the landing,
     or before a review after a fix, is a Fix step: `▶ Fix 2: lint findings`. A lint fix before a review after a
     rebuild is on Land: `▶ Land · lint fix`.
  3. The round (`round 1 of 3`), each finished round's verdict with its counts by level, and, right-aligned, the
     measured time in the step it is in (`fixing 2m`, `pushing 51s`, `push failed 3m`).
  A card that has landed stays on the belt, Push in progress, until main is pushed and its issue closed. With the
  rule "Push on landing" Off, a landed card that is not pushed is not on the belt: LANDED TODAY shows it. A Push
  that failed adds a fourth line, `✗` and the reason (the push's error, or that GitHub kept the issue open), cut to
  the width. From the live feed, while a step runs, a dim line follows: what it is doing now, its turns and the
  seconds since its last output (`now Bash: npm test · 3 turns · last output 6s ago`). The Test step runs no model,
  so in place of its turns it shows how far the tests are: `142 of 205 tests · 2 failed · last output 23s ago`; while
  the feed gives no test count, the test files run (`3 of 6 test files`); with neither, only its last output. The
  list that the run got comes first: `changed: 7 files`.
  Under the cards, a line for the push of each project. While the push runs: the commit, what runs and since when,
  its process and the time it has run (`push on a1b2c3d4e5f6: pre-push hook running since 4:37 AM · pid 4242 · 3m`;
  before the hook, `tests before the push running`, then `getting the push ready (worktree, dependencies, test
  slot)`; with no hook, `push running with no pre-push hook`; after a failed `git push`, `git push ended, finishing the
  push`; after the remote has the commit, `pushed, waiting for GitHub`), then the newest line of the hook's output, or
  its `N/M passed` line. A part that does not fit the width goes on to the
  next line, and a long log path continues over lines. A push whose process is gone and that did
  not end shows as stale, with its log (`✗ push on a1b2c3d4e5f6 is stale: … · Log: <path>`). For an hour after a push
  ends, and while a failed push leaves landed commits not pushed, the line gives its result: `✓ Push now of
  a1b2c3d4e5f6 passed 2m ago`, or `✗` with the failed test and the log, or `Push now started no push` and why. When
  main is still ahead of the remote after it, the line says so (`main is still 1 commit ahead of the remote`). The
  log is in the state folder ([Push](cards.md#push)).
- **QUEUE**: `next 5 of 9`: the next five, numbered, the title cut to fit, the priority right-aligned (with
  `follow-up` and `retried`); the issues that wait on another; then the held-back line (`held back: 1 P0 · 1 P1`),
  which goes on to more lines when it does not fit, so no count is lost. A reason too wide for one line goes on to
  more lines at its spaces, so no part of it is lost. A word wider than the line breaks between whole characters.
  With the rule "Push on landing" Off, `landed, not pushed:` follows, with each open issue whose card landed and
  that waits for the push, from today or an earlier day.
- **BUILT, WAITING FOR YOUR PROD DEPLOY**: the open issues labelled `awaiting-deploy`, which the loop never picks,
  with how long each has carried the label. Shown only when there is one.
- **LANDED TODAY**: the count of every card landed today and the day's cost in the heading; under it, the most
  recent cards, and `+N more` for the rest. Per card the time it landed, `✓`, the issue and short
  title, the last verdict and its round (`NO-GO r3`), and its cost (`pushing` while the push runs, `Landed, waiting for Push landed` with that rule Off, `not pushed`,
  `issue open` when GitHub did not close it); beneath, when it was picked up, its overall time to the landing and the
  follow-ups it filed (`↳ 3 follow-ups: #13 #14 #15`).
- **The measurements of a card**, in `/units` under each card that needs you, the same fields as the Board's per-card
  detail, less two that only the Board shows (what the card waited on in the queue, with the time under each cause,
  and the card whose landing broke main), in two lines: where its time went (`lead`, `cycle`, `queued`, `slot wait`, `build`, `review`, `fix`,
  `tests`, `landing`, `to push`, `waiting on you`), then what it made and cost (files and lines changed, findings by
  level, reviews, rebuilds, retries, follow-up depth, follow-ups filed, weekly limit points, tokens, dollars, and why
  it is blocked, for example `proof check` or `session failed`), then one line a finished step (its seconds, tokens, dollars, model, findings, tests and the
  session's own stats; a step with no price says why, `not priced: no model recorded`). A reading that was not taken
  reads `missing`, never 0; a snapshot from before the measurements shows none of these lines. Not in the pane. The header's `today` is the priced steps' dollars, with `+ N steps not priced` when some are left out.
- **FAST LANE**: the lane's open change (commits ahead of the default branch, uncommitted files) and its card: on the
  belt with its step, needing you, landed, or not landed.
- **RESEARCH LANE**: working or idle, with the time of its last activity.

A lane with no worktree on this machine is not shown: not in `/units` and not in the pane.

`/units` prints all of it in full. A card of the session's own project shows its issue alone; a card of any other
project carries its project's name (`widgetshop#12`). In a checkout that no record names, every card carries its
project's name.
A loop that is not picking says so after `CONVEYOR` in the header (`shop paused`, `shop stopped`, `shop paused by guard`, `shop: no loop process`), from the snapshot's health, so
`conveyor.sh control pause` or `stop` shows there; a running loop adds nothing. A loop that paused itself, after a
sign-in failed, shows the reason after the state (`shop paused: build: Claude Code's own sign-in expired; ...`).

## The pane

The pane shows the board as tables, from top to bottom. A line that is wider than the pane is cut, unless
this page says that it wraps. Before the first fetch answers, the pane shows `units: reading the Conveyor snapshot`.
Some lines wrap at their spaces when they are wider than the pane. These are that message, a line about what could
not be read, a fetch error and the snapshot age note. These wrap too, so no number or count is cut:

- The pass line of a whole-suite run that runs failed cases again goes on a line of its own. On a very narrow pane,
  `failed cases again:` and the pass go on two lines.
- The `ON THE BELT` head breaks inside a project's part, at its commas and then at its spaces.
- In PICK ORDER, a parent's title goes on lines under its row when its counts leave it no room, and a dependency's
  state under `Requires` breaks at its spaces. When a long project name leaves too little room beside the issue ID,
  the counts, the title and the states go on lines under the ID, indented by two spaces.
- In QUEUE, the `follow-up` and `retried` flags go on a line under the row when they leave the title no room. When
  more than one project has waiting issues, each issue they wait for shows its project name.

A word wider than the pane breaks between whole characters.

- **The head**: `/units` as a filled label, the Conveyor host in bold and, on the right, `DAY SPEND` and the dollars
  today.
- **The count band**, between two rules: `4 ON BELT · 0 READY · 5 WAITING · 0 NEEDS YOU`. `READY` counts the issues
  that the loop can pick now. `WAITING` counts the issues that wait on another card.
  When the line is wider than the pane, the dots lose their spaces. When it is still too wide, the band wraps to two
  lines: `ON BELT` and `READY` on the first, `WAITING` and `NEEDS YOU` on the second. `NEEDS YOU` is not cut off.
- **The status line**: the Foreman's state (`Foreman listening`, or `Foreman not listening` with the reason), a loop
  that is not picking (`shop paused`), and on the right `! 2 plugin problems` when the Foreman noted some.
- **`[ Machine details ]`**: closed at first. Click it, or press `m` while the pane has the focus, to open or close it.
  It shows the session that has the Foreman role, the waiter and the watchers, the link to the plugin problems file,
  the test map line and the weekly limit.
- The old-engine line and the whole-suite line, when there is one (while it runs, a second line with its counts, or the progress of the pass that runs failed cases again, when it has some), and the cards that need you, one line each.
- **BUILD MATRIX**: on the right, the project and its slots in use against the builder cap (`bookstore · 3/4
  slots`; the same count as the `ON THE BELT` head when the snapshot is older). One row for each card on the belt: the issue (`#486`; a card with no issue shows `red <commit>`, with the
  first 7 characters of the commit, for a fix of a red main, and `card <N>` for any other, with the number its card id ends in, or `card` when it ends in no number or in `-0` (a card that
  the Tests page files), as in WORKER ACTIVITY and
  LANDED TODAY), one column for each step (`B R F T L P`: Build,
  Review, Fix, Test, Land, Push), its overall time (`Age`), its cost and, last, its short title (`Title`; a card with no issue shows its whole name there). The title
  uses the remaining width of the row, and a title that is too long ends in `…`. A step shows `▶` while it runs,
  `✓` when it is done, `✗` when it failed and `·` when the card did not get to it (Fix after a GO, too). A dim
  legend is under the table. Each project with cards on the belt has its own matrix. Each other project of the
  machine has one dim line with its name and slots. When the row does not fit, the `Age` column is not shown. When
  fewer than 6 columns are left after the cost, the title is not shown.
- **WORKER ACTIVITY**: one line for each card: its mark, its issue and the command that runs now, made short. A path
  in the card's worktree shows as `worktree` (`cd worktree/x && git add -A`), and any other path shows only its last
  part. On the right: the tool (`Bash`) and the time the step started. A card that runs no command shows its step.
- **PICK ORDER**: on the right, `next 5 of 7` when more than five issues are ready (with `+` when a project listed its
  full ten), else how many the loop can pick now (`2 ready`). Under it, the next five issues in pick order, numbered,
  each with its issue (and project when the pane shows more than one), its title cut to fit and its priority
  right-aligned (`P0` and `P1` in the needs-you colour), then `follow-up` or `retried` when it is one. An issue the
  machine holds back says why on a line under it (`waiting for a machine slot: …`). Then two columns, `Waiting` and
  `Requires`: each issue that waits on other issues and is not forced, and the issues it waits for (`#489  #485  #486  #487  #488`), in
  the order that the loop picks them. When the issues it waits for do not fit on one line, they go on to more lines
  under `Requires`, so none is lost. With nothing ready and nothing waiting it reads `the queue is empty`, and with a
  queue GitHub did not list, `not read: GitHub did not list the issues`. The held-back line follows. When its
  counts do not fit on one line, they go on to more lines, so none is lost. A reason too wide for one line goes on to
  more lines at its spaces. A word wider than the line breaks between whole characters.
- **LANDED TODAY · 20**: the count of every card landed today; on the right, `5 most recent of 20`. One row for each of the five most recent cards: the time
  it landed, the issue, the last verdict and its round (`✓ GO r2`), its overall time and its cost (or `pushing`,
  `issue open` or `not pushed`). A card that still waits shows `waiting` there, and what it waits for (such as
  `Landed, waiting for Push landed`) on the line under its row.
- The Fast and Research lanes, and the lines about what could not be read. A line about what could not be read wraps
  at its spaces. A word wider than the line breaks between whole characters.

A section with nothing to show has one dim line: `nothing on the belt`, `nothing waiting`, `nothing landed today`.
The pane and `/units` write times of day in the form that the Board's **Time** setting gives, or the `time` setting
([Settings](#settings)).

## Settings

`time`, in `/config` under the plugin: `12-hour` (`3:04 PM`, the default) or `24-hour` (`15:04`). When the Board runs on
this machine and you set its **Time** in Customize, the pane uses the Board's setting in place of `time`, within a
minute. The pane uses the **Time** that a browser last sent. A browser sends its **Time** each time you set it, and
on opening the Board only one time: the first time, and only when its **Time** is not the default and the Board has
no **Time** from a browser yet.

The pane has its option in `/config`, under the plugin: `pane`, `auto`, `on` or `off`. `auto` is on in main, where the
Foreman runs, off in every other worktree (a card's, a lane's). `/units pane on|off` sets it for the current session.
`/units` has no other view: any other word after `/units` shows that only the pane exists.

The toasts go with the pane: with the pane on, a toast shows when a card newly needs you (`#3861 needs your yes`,
`#3850 is blocked`) or lands (`#3860 landed`, `#3858 closed as already fixed`). With the pane off, no toast shows.

With `pane` on, the pane opens when a session starts. Claude Code places a pane that opens by itself only in a wide
terminal. In a narrower one the pane waits, not drawn, and the session shows one line with the reason Claude Code gives
and says that `/units pane on` tries again. `/units pane on` places the pane at any width. `motion` (`off` by default, or `on`) turns the mark
of each card in the pane's WORKER ACTIVITY `◐ ◓ ◑ ◒` once a second; off, the mark stands still.

## What it reads

One fetch a minute while the pane is on, and one each time `/units` is typed (a session with the pane off fetches
nothing until then); a `/units` typed while a fetch is still waiting to start starts none of its own.

How fast the views follow the belt: with the live feed (below) running, a change is in the views within about
2 seconds. With no live feed, the mod makes a short check every 5 seconds: for each record, one checksum of its
`cards.jsonl`, `control.json` and queue, and of the step that each of its live cards (and each bug card's proof run)
is on now, all in one command (one `ssh` call when the records are on a build machine).
When a record's checksum changes, a fetch starts at once, and that record's snapshot is built new for it
(`conveyor.sh snapshot --fresh`), so a card started, a step, a landing or a block shows within about 5 seconds, plus
the time that build takes. If that fetch fails or brings no snapshot for the record, the next check asks for it
again, though its checksum has not changed since. Any other check that finds no change fetches nothing. When a project is pinned to an older engine
whose fetch script has no `stamp` mode, the mod skips this check for it.

The Foreman row follows the Foreman's folder at once: each second the mod looks at the write times of its role mark
(`session`) and `waiter.pid`, and when either one changes it reads the Foreman line alone and redraws the row, so a
`/clear` shows within about a second, not at the next fetch. A second with no change reads nothing.

The fetch is
`hooks/units-fetch.sh`, run in the main checkout. It reads the machine's host file, `~/.config/conveyor/host.json`
(under `$XDG_CONFIG_HOME` when that is set; else the checkout's `conveyor/host.json`), as the Board reads it:

- `conveyor.sh snapshot` of every record the host file names, from the clone its `main` names, in one command, each snapshot cut on that machine to the parts the pane draws. The
  command runs on this machine when the session's checkout is a record of the host file, or that clone; else over ssh
  to the host file's `ssh` target. Each record's snapshot is the last one Conveyor made, or a new one after a check
  found that record changed; when it is more than a minute
  old, a line under the board says its age and the time it was made.
- The lanes of the session's checkout: the folders its record names in `lanes.fast.worktree` and
  `lanes.research.worktree` (`conveyor.sh lane ... create` writes them; `~/` is the home folder). Of the Fast lane,
  with git: its branch, its commits ahead of the project's default branch, its tracked files changed. Its card is found as
  `conveyor.sh land-branch` names it: a branch named as a card id (`c<time>-<project>-<issue>`) lands as that issue,
  and any other branch lands as issue 0 under its first commit's subject. A checkout the host file has no record of shows
  `not read: the host file has no record of this checkout`.

The live feed. Where the Board runs, it keeps `stream.json` in its own folder from one long-lived `conveyor.sh watch`
per record, the same stream the Board shows, and beside it `units-feed.json`: the same, with each snapshot cut to the
parts the pane draws, so the Tests page's history does not grow it. The mod reads `units-feed.json`. It names that folder at the session's start the way
`.claude/scripts/dashboard.sh` does, from the Board job installed on this machine (the Mac's
`~/Library/LaunchAgents/com.conveyor.dashboard.plist`, else `~/.config/systemd/user/dashboard.service`), with the job's
own settings, not the session's: the Board's folder in its project's state folder. When it cannot be named (no Board
job here, or no state folder), each poll asks again, the board is read from the host, and a line under it says
`units: the live feed's folder was not found (no Board job here, or its state folder cannot be named); reading the host`.
While that file is fresh (written in the last 30 s), the board is read from it: once a second the mod looks at it, and
a file that changed is drawn at once (a rewrite that only moved its heartbeat, `stream.heardAt`, is not built into a
board again), so a card's step or a control change is in the views within about 2 seconds; the minute's fetch then
asks no host for the snapshots (it still reads the lanes and the test map). A stream that is down keeps its last board, with a note under it:
`units: the live stream is down (<why>); the board is as <host> was at <time>`. With no fresh file the fetch reads the
snapshot as above.

Then three reads on this machine:

- The 7-day limit, from the Board's limit file `limit.json` in the same folder as the feed (the `usedPct` and
  `resetsAt` of its health panel's limit, which the Board writes there each time it writes `data.js`), read again only
  when the file's write time changes. `/units` never reads `data.js`, whatever its size. With no folder named, or a
  `limit.json` that holds no limit, `weekly limit not read`. A folder with `data.js` and no `limit.json` comes from a
  Board on an older engine: the limit shows as not read, and a line under the board says
  `units: the Board's folder has data.js but no limit.json (the Board runs an older engine); the usage limit is not read`.
- The test map of the session's checkout, from `conveyor.sh testmap` of the plugin's own copy of Conveyor: the run
  that makes the map writes how far it is in `.conveyor/test-map.run.json`, beside the map. When Conveyor for this
  checkout runs on a build machine, the map is that machine's: `conveyor.sh testmap` runs there, in the same `ssh`
  command as the snapshots, for the record with this checkout's folder name. While the board comes from the live
  feed, an `ssh` command asks for the map only.
- The Research lane's last activity: the newest write to a Claude session log of its folder
  (`~/.claude/projects/<that path with dashes>/*.jsonl`, under `$CLAUDE_CONFIG_DIR` in place of `~/.claude` when that
  is set; a name over 200 characters is cut to its first 200, a dash and a hash, as Claude Code names the folder); it
  is working while that is under five minutes old.

## When something cannot be read

A snapshot that cannot be read is one plain note in every view, and nothing from an earlier fetch:
`units: the Conveyor snapshot cannot be read (<why>)`, where the reason is one of `<host> is unreachable`,
`<host> did not answer in time`, `<host> gave no snapshot`,
`this machine has no host file at <paths looked at>`, `the host file is not understood`,
`the fetch did not run` or `the fetch did not finish`, or
`the fetch printed over the 4.2 MB cap and was cut short` (the engine keeps a command's first 4 MiB of output).
In the pane, a note that is wider than the pane goes on to more lines at its spaces. A word wider than the pane, such
as a long host file path, breaks between whole characters. The Foreman line still shows under it.

Smaller gaps are named where they are: `weekly limit not read`, `today partial` and `cost partial` (a step could not be
priced: never a part sum), `QUEUE` `not read: GitHub did not list the issues`, and under the board `units: the <record> snapshot cannot be read` when one record of several fails. A Board feed
(`units-feed.json`) over the 4 MiB cap (shown as 4.2 MB; the engine refuses a larger read), or a limit file
(`limit.json`) over 16384 bytes, is not read, nor tried again each second, and a line under the board names its size
and the cap; with no board, that line comes first in the note every view draws.
