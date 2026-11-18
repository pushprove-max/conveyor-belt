# /units: Conveyor's board inside Claude Code

The plugin's `hooks/units.tsx` (registered by `hooks/index.tsx`, the hooks module `hooks/hooks.json` names under `modules`) shows Conveyor's board in
two places: `/units` and a side pane (`Conveyor`). With the pane on, a toast also shows when a card newly needs you or
lands. It only reads; it writes no file. It comes with the plugin: there is nothing else to
install.

It registers nothing outside a checkout with Conveyor's project settings (`.conveyor/project.json` in the main
checkout), so other projects on the profile are unaffected. In such a project it shows every project of the machine's
host file (its settings file), whether or not the session's project is the plugin's own.

## What it shows

`/units` and the pane are drawn at the pane's 62 columns. No time is estimated from past cards: only what was measured
is shown. A figure is never cut: figures are right-aligned and the title is what gives way.

- A head, two lines: `CONVEYOR`, dollars today and the Conveyor host (`● buildbox`); then the weekly limit with its
  reset (`weekly limit 94% · resets 1d 18h`) and the counts on the belt and queued. While the loop runs with a builder
  cap, the `ON THE BELT` head gives the cards on the belt and the cap, and the cards that take no build slot: those
  that wait on another card, and a landed card in Push (`ON THE BELT (2 of 7, 1 waiting and 1 landing not counted)`). With more than one project, each project's count
  follows its name (`ON THE BELT (bakery 1 of 3 · gadgetlab 1)`). In `/units` a third line gives how
  many findings the review's judge declined today (`judge declined 3 findings today`), from the snapshot's declined
  list (its `declined` and `declinedRest` lines by the judge, by this machine's day, each line once).
- **The Foreman**, under the head: `Foreman listening`, or `Foreman not listening` with the reason (`not the Foreman
  session`, `waiter starting again`, `waiter down: <why>`, `no waiter running`, `waiter on an old install`, `watcher
  down: <name>`; `docs/foreman.md` says what each one means). In `/units` and the pane a dim
  line under it gives the session that has the role, the waiter's process and version, and the state of each watcher.
  A narrow view wraps that line onto more lines, so no watcher is lost.
  A project where no session has the
  Foreman role and no Foreman is set up shows no Foreman line. [Foreman](foreman.md) tells what each reason means.
- **The whole suite**, in `/units` and the pane, under the head: while a release suite or a full test run is in
  progress, one line for it: the kind (`release 1.2.0` or `full test`), the short commit, the time it has run, the cases
  done and the failures until now (`release 1.2.0 · a1b2c3d · running 12m · 140 cases done · 2 failures`). When the run
  ends, the line shows the result (`passed 3m ago`) for 10 minutes, then it goes away.
- **The test map**, in `/units` and the pane, under the head: one line. While setup or a whole run on main makes the
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
     any token is read, never $0; `cost partial` when a step has no price).
  2. The six steps Build, Review, Fix, Test, Land, Push as one track: done `✓` with a filled join `━━`, the step in
     progress lit `▶`, to come dim, skipped `–` (Fix after a GO), failed `✗` in red. Where the width has room, a
     done step adds the time it took (`✓ Build 16m`) and a step that ran more than once its count (`Review 2 of 3`,
     `Fix 2`); the times give way first, then the counts, and what gave way is on a dim line under the track
     (`Test 16m · Land 16m`), so no measured time or count is lost.
  3. The round (`round 1 of 3`), each finished round's verdict with its counts by level, and, right-aligned, the
     measured time in the step it is in (`fixing 2m`, `pushing 51s`, `push failed 3m`).
  A card that has landed stays on the belt, Push in progress, until main is pushed and its issue closed. With the
  rule "Push when a card lands" Off, a landed card that is not pushed is not on the belt: LANDED TODAY shows it. A Push
  that failed adds a fourth line, `✗` and the reason (the push's error, or that GitHub kept the issue open), cut to
  the width. From the live feed, while a step runs, a dim line follows: what it is doing now, its turns and the
  seconds since its last output (`now Bash: npm test · 3 turns · last output 6s ago`). The Test step runs no model,
  so in place of its turns it shows how far the tests are: `142 of 205 tests · 2 failed · last output 23s ago`; while
  the feed gives no test count, the test files run (`3 of 6 test files`); with neither, only its last output. When
  the pack sets `test.list`, the list that the run got comes first: `changed: 7 files` or `whole suite`.
- **QUEUE**: `next 5 of 9`: the next five, numbered, the title cut to fit, the priority right-aligned (with
  `follow-up` and `retried`); the issues that wait on another; then the held-back line.
- **BUILT, WAITING FOR YOUR PROD DEPLOY**: the open issues labelled `awaiting-deploy`, which the loop never picks,
  with how long each has carried the label. Shown only when there is one.
- **LANDED TODAY**: the count and the day's cost in the heading; per card the time it landed, `✓`, the issue and short
  title, the last verdict and its round (`NO-GO r3`), and its cost (`pushing` while the push runs, `Landed, waiting for Push landed` with that rule Off, `not pushed`,
  `issue open` when GitHub did not close it); beneath, when it was picked up, its overall time to the landing and the
  follow-ups it filed (`↳ 3 follow-ups: #13 #14 #15`).
- **The measurements of a card**, in `/units` under each card that needs you, the same fields as the Board's per-card
  detail, in two lines: where its time went (`lead`, `cycle`, `queued`, `slot wait`, `build`, `review`, `fix`,
  `tests`, `landing`, `to push`, `waiting on you`), then what it made and cost (files and lines changed, findings by
  level, reviews, rebuilds, retries, follow-up depth, follow-ups filed, weekly limit points, tokens, dollars, and why
  it is blocked), then one line a finished step (its seconds, tokens, dollars, model, findings, tests and the
  session's own stats; a step with no price says why, `not priced: no model recorded`). A reading that was not taken
  reads `missing`, never 0; a snapshot from before the measurements shows none of these lines. Not in the pane. The header's `today` is the priced steps' dollars, with `+ N steps not priced` when some are left out.
- **FAST LANE**: the lane's open change (commits ahead of the default branch, uncommitted files) and its card: on the
  belt with its step, needing you, landed, or not landed.
- **RESEARCH LANE**: working or idle, with the time of its last activity.

A lane with no worktree on this machine is not shown: not in `/units` and not in the pane.

`/units` prints all of it in full. The pane shows the same with the cards that need you one line each and the landed
list cut to five. A card of the session's own project shows its issue alone; a card of any other project carries its
project's name (`widgetshop#12`). In a checkout that no record names, every card carries its project's name.
A loop that is not picking says so after `CONVEYOR` in the header (`shop paused`, `shop stopped`, `shop paused by guard`, `shop: no loop process`), from the snapshot's health, so
`conveyor.sh control pause` or `stop` shows there; a running loop adds nothing. A loop that paused itself, after a
sign-in failed, shows the reason after the state (`shop paused: build: Claude Code's own sign-in expired; ...`).

## Settings

The pane has its option in `/config`, under the plugin: `pane`, `auto`, `on` or `off`. `auto` is on in main, where the
Foreman runs, off in every other worktree (a card's, a lane's). `/units pane on|off` sets it for the current session.
`/units` has no other view: any other word after `/units` shows that only the pane exists.

The toasts go with the pane: with the pane on, a toast shows when a card newly needs you (`#3861 needs your yes`,
`#3850 is blocked`) or lands (`#3860 landed`, `#3858 closed as already fixed`). With the pane off, no toast shows.

With `pane` on, the pane opens when a session starts. Claude Code places a pane that opens by itself only in a wide
terminal. In a narrower one the pane waits, not drawn, and the session shows one line with the reason Claude Code gives
and says that `/units pane on` tries again. `/units pane on` places the pane at any width. `motion` (`off` by default, or `on`) turns the mark
of each card on the belt `◐ ◓ ◑ ◒` once a second; off, the mark stands still.

## What it reads

One fetch a minute while the pane is on, and one each time `/units` is typed (a session with the pane off fetches
nothing until then); a `/units` typed while a fetch is still waiting to start starts none of its own. The fetch is
`hooks/units-fetch.sh`, run in the main checkout. It reads the machine's host file, `~/.config/conveyor/host.json`
(under `$XDG_CONFIG_HOME` when that is set; else the checkout's `conveyor/host.json`), as the Board reads it:

- `conveyor.sh snapshot` of every record the host file names, from the clone its `main` names, in one command. The
  command runs on this machine when the session's checkout is a record of the host file, or that clone; else over ssh
  to the host file's `ssh` target.
- The lanes of the session's checkout: the folders its record names in `lanes.fast.worktree` and
  `lanes.research.worktree` (`conveyor.sh lane ... create` writes them; `~/` is the home folder). Of the Fast lane,
  with git: its branch, its commits ahead of the project's default branch, its tracked files changed. Its card is found as
  `conveyor.sh land-branch` names it: the issue is the first number in the branch name, and a branch that names none
  lands as issue 0 under its first commit's subject. A checkout the host file has no record of shows
  `not read: the host file has no record of this checkout`.

The live feed. Where the Board runs, it keeps `stream.json` in its own folder from one long-lived `conveyor.sh watch`
per record, the same stream the Board shows. The mod names that folder at the session's start the way
`.claude/scripts/dashboard.sh` does, from the Board job installed on this machine (the Mac's
`~/Library/LaunchAgents/com.conveyor.dashboard.plist`, else `~/.config/systemd/user/dashboard.service`), with the job's
own settings, not the session's: the Board's folder in its project's state folder. When it cannot be named (no Board
job here, or no state folder), each poll asks again, the board is read from the host, and a line under it says
`units: the live feed's folder was not found (no Board job here, or its state folder cannot be named); reading the host`.
While that file is fresh (written in the last 30 s), the board is read from it: once a second the mod looks at it, and
a file that changed is drawn at once (a rewrite that only moved its heartbeat, `stream.heardAt`, is not built into a
board again), so a card's step or a control change is in the views within about 2 seconds; the minute's fetch then
asks no host for the snapshots (it still reads the lanes and the test map). A stream that is down keeps its last board, with one line under it:
`units: the live stream is down (<why>); the board is as <host> was at <time>`. With no fresh file the fetch reads the
snapshot as above.

Then three reads on this machine:

- The 7-day limit, from the Board's data file `data.js` in the same folder as the feed (its health panel's
  `panels.health.data.limit.usedPct` and `.resetsAt`), read again only when the file's write time changes; with no
  folder named, `usage limit not read`.
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

A snapshot that cannot be read is one plain line in every view, and nothing from an earlier fetch:
`units: the Conveyor snapshot cannot be read (<why>)`, where the reason is one of `<host> is unreachable`,
`<host> did not answer in time`, `<host> gave no snapshot`,
`this machine has no host file at <paths looked at>`, `the host file is not understood`,
`the fetch did not run` or `the fetch did not finish`, or
`the fetch printed over the 4.2 MB cap and was cut short` (the engine keeps a command's first 4 MiB of output).
The Foreman line still shows under it.

Smaller gaps are named where they are: `usage limit not read`, `today partial` and `cost partial` (a step could not be
priced: never a part sum), `QUEUE` `not read: GitHub did not list the issues`, and under the board `units: the <record> snapshot cannot be read` when one record of several fails. A Board feed
(`stream.json`) or data file (`data.js`) over the 4 MiB cap (shown as 4.2 MB; the engine refuses a larger read) is not
read, nor tried again each second, and a line under the board names its size and the cap; with no board, that line
comes first in the one line every view draws.
