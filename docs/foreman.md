# Foreman

The Foreman is a Claude Code session in a project's main checkout. It watches that project's Conveyor and brings you
what needs you: blocked cards, changes that wait for your yes, stuck cards and push errors. There is one Foreman per
project.

## Start it

Set it up once with `/conveyor-belt:setup --foreman`. Then type `/conveyor-belt:foreman` in a session in the main
checkout. You can also say "start your role" (or "you are the Foreman") as the whole message. These words do nothing in
a worktree, or in a checkout that is not a Conveyor project.

A new session in the main checkout takes the role when no session holds it, or when the session that holds it is gone.
When a live session holds it, the new session asks you whether to take it over (`conveyor/README.md`, Foreman).
The session that takes the role says so in one line: `This session is now the Foreman: …`. When the host file gives
the Foreman a name in `foreman.name`, the line shows it in brackets: `This session is now the Foreman (Ada): …`.
The session stays the Foreman when you continue or resume it, and after `/clear` in it. `/clear` in another session
does not give it the role. `/conveyor-belt:foreman off` ends the role, and it stays off after `/clear`.

When `/conveyor-belt:foreman` or your words make a session the Foreman, the Board opens in your default browser at
`https://localhost:<port>/`. It opens once for each claim. A claim by the session that is already the Foreman, a
resume, `/clear` or a compact opens no new tab. When the Board is not running, the claim says so in one line and
names a file for the start's output. `conveyor.sh board` then starts the Board from your checkout, and the Board opens
when it answers. The session is the Foreman all the same, also when the start fails. When something answers on the
port but fails the check of the Board's certificate, the claim says that, with curl's exit code, and opens nothing.
`conveyor.sh board` then replaces a certificate whose key does not name its curve and starts the Board again. The plugin option `boardAutoOpen` (set in `/plugin`) turns this off, as it turns
off the Board that opens when a session starts.

## Status and wakes

`conveyor.sh foreman status` prints the state of the Foreman's projects as short plain text. Give a project's name to
see only that project. It shows:

- each card on the belt, one a line: its issue, step, time in that step and title
- the cards that wait on other issues, and the held issues, by number
- the release or full-test run in progress: its commit, how long it has run, the cases done of all its cases, and the
  failed cases. With no run in progress, it shows how the last run ended.
- each item that needs you, one a line: a blocked card with its reason, a change that waits for your yes, a push
  error and a problem of the engine
- `not yet reported: blocked #N` for each card blocked for two polls or more that the Foreman has not got in a wake.
  The next wake names it too.
- the watcher's last poll: when it ended and how long it took, with what it read for each project
- last, the Foreman's waiter: `waiter: listening`, `waiter: starting again` or `waiter: down: <why>`

The Foreman uses this command for its status checks. Its rules also tell it to run short commands in the foreground,
to put several checks into one command, and to read an image only when you ask or a check needs it.

A watcher wakes the Foreman when something needs it. The wake holds the outcome, so the Foreman does not have to look
it up:

- A card that the Foreman waits for lands: the wake names its commit.
- A blocked card: the wake names the reason. When the snapshot fails or is slow, as when it is made anew from the
  whole card records, the watcher reads `conveyor.sh health`. A blocked card, or a change that waits for your yes,
  then wakes the Foreman from health at that poll, and does not wait for the snapshot.
- A release or full-test run that ends: the wake names the result and the failed cases.
- A card that waits for main to change, or waits on another card, for the minutes of the pack setting
  `foreman.waitWake` (in `.conveyor/project.json`): the wake names the card and what it waits on. For another card,
  it gives that card's step and last action. For main, it gives each main-red fix card that is open, with its step
  and last action, or blocked, with its reason. Each wait wakes the Foreman once. If the wait goes on for the same
  time again, the next wake says "still waiting".
- The machine fails test files on main, and no change to main explains it: the wake names those files. The loop
  picks no card until they pass again ([Cards](cards.md#tests)).

On a wake for a waiting card, the Foreman does more than report it. It finds why the card waits: it reads the log of
the card it waits on, the main-red record and the test log. Then it fixes the cause. If the belt is blocked and your
rules allow it, it makes a fix by hand. If not, it files an issue.

A card that moves from one step to the next, as from build to review, gives no wake.

The Foreman's reply to a wake says only what needs you. If nothing needs you, the reply is the one word Idle. A
problem that the Foreman finds in Conveyor itself always needs you. Who files it depends on the project:

- In any other project, you file it in the plugin's repository. The Foreman says it on a line of its own:

  `Plugin problem (for the conveyor-belt repo): <what it saw>, card <card>, evidence <path>`

- In the plugin's own repository, the Foreman files it there at once, as it files any other issue. The issue is held
  until you say yes. The line ends with the issue number:

  `Plugin problem (for the conveyor-belt repo): <what it saw>, card <card>, evidence <path>, filed as #<n>`

  If the line has no issue number, the Foreman cannot end its reply. It gets the reason and files the issue. When the
  Foreman starts, it gets a list of each entry in `plugin-bugs.md` that has no issue number. For each entry, it first looks for an issue that already reports the problem, such as
  one that you filed, and uses that issue's number. It files only the entries that no issue reports.

Each such problem also goes into `plugin-bugs.md` in the Foreman's folder, one line each: the time, the card, what the
Foreman saw and the evidence path. The Board's Health panel and `/units` then show "N plugin problems noted", with
the path of that file.

The watchers run from the Conveyor version that the project uses. When the project moves to a new version, as when
it follows the plugin's main and a new commit lands, the watchers stop within a minute and start again from the new
version. A card that lands while the version changes still wakes the Foreman. An update does not delete a version
that the Foreman's watchers still use. A later update deletes it, after those watchers stop.

## Is the Foreman listening?

`/units` and its pane show one Foreman line:

- **Foreman listening**, in the colour for success: this session is the Foreman, its waiter runs from the Conveyor
  version that the project uses now, and its four watchers run.
- **Foreman not listening**, in the colour for a warning, with the reason:
  - `not the Foreman session`: another session has the Foreman role, or no session has it. In the Foreman's own
    session, run `/conveyor-belt:foreman` to take the role again.
  - `waiter starting again`: the waiter stopped less than a minute ago. The next one starts on its own (see below).
  - `waiter down: <why>`: no waiter has run for more than a minute. `<why>` is the reason the last one gave when it
    stopped. Your next message to the Foreman starts it again.
  - `no waiter running`: the waiter that runs is not this session's.
  - `waiter on an old install`: the waiter runs from a version that the project does not use now.
  - `watcher down: <name>`: one of the watchers (`conveyor`, `limit`, `alerts` or `idle`) stopped and did not start
    again.

`/units` and the pane show one more line under it: the session that has the role, the waiter's process and its
version, and the state of each watcher. A project where no session has the role and no Foreman is set up shows no
Foreman line. The line comes from
the files in the Foreman's folder and from the process list of this machine. It does not start the waiter, and it
does not ask the host.

## The watcher recovers by itself

The waiter wakes the Foreman by ending. Before it ends, it starts a new waiter. The new waiter listens while the
Foreman answers the wake. A wake that comes during that turn waits. The Foreman gets it when the turn ends, and gets
it once.

When the waiter stops for any other reason, the next prompt or tool call of the Foreman session starts it again. A
check of the waiter's process runs at each of them. It starts a waiter only when none runs, and only one. A session
can go on in a new Claude process. The waiter of the old process then stops, and the next stop, prompt or tool call
starts a waiter for the new one. A wake that the old process did not get stays, and the new process gets it. When the
session is idle, no check runs, and the waiter stays down until your next message. The file `waiter.log` in the
Foreman's folder (`foreman` in the folder that `conveyor.sh state-dir` prints) has a line each time a waiter starts and each time
one stops, with the reason. A waiter that was killed has no time to write its reason. Its start line is then the last
line. The file `conveyor-polls.log` in the same folder has a line for each poll of the Conveyor watcher: when it
started and ended, how long it took, what it read for each project (the snapshot, health or nothing) and if it woke
the Foreman. It keeps only its newest lines. Use it to find why a wake came late.

## The Foreman on your own machine

The Foreman can run on your own machine while the belt runs on a host. Give your machine's host file (its
settings file, `~/.config/conveyor/host.json`) the host's `ssh` target and the project's record as the host has it:

```json
{"ssh": "devhost", "records": [{"repo": "shop", "main": "/srv/repos/shop"}]}
```

A checkout here whose `origin` remote is that repo gets that record, even when its path is different. The Foreman then
asks the host about the record over ssh. Open decisions for that record come from the ledger of this checkout.

## Away and auto

- `/conveyor-belt:away`: the owner is away. The Foreman works by the owner's own away rules, the file that the host
  file names as `foreman.away`.
- `/conveyor-belt:auto on | narrow | off`: the Foreman decides the owner's open decisions (the Board's ledger) for
  them, by their recorded way of deciding. It logs each decision with its question, pick, reason and whether it can be
  reversed, in `<state folder>/auto/<date>-<time>.md`. `on` decides every open decision that has a recommended option.
  `narrow` decides only formalities: an answer the owner already gave to the same question. It never decides what the
  pack's `auto.reserved` holds (the pack is the project's settings, `.conveyor/project.json`; by default production deploys, deletes, new feature flags, security and password
  settings, configured product values, and licence or consent questions). Those are listed under "Waiting for the
  owner". A band above the prompt shows whether auto is on.
- `owner-way.md`: a project can keep a written profile of how its owner decides. Make it from the ruling log, and put
  it in the Foreman's folder, beside `rules.md`: `foreman` in the folder that `conveyor.sh state-dir` prints. For a
  group in `foreman.groups`, use the folder of the first project in the group. The
  Foreman keeps it current. While auto is on, the Foreman reads it before it decides. It keeps the file's "Never
  decide; ask" and "Hard lines" sections as it keeps `auto.reserved`. The plugin ships no such file. With no file,
  auto reads only the ruling log.

## Standing yes

Some routine steps get the same yes from you each time. You can give that yes once, kind by kind. The Foreman then
takes those steps without asking. Each kind is off until you turn it on in the Rules tab of the Board ("... without
asking"). The pack keeps the list as `auto.standing`. A kind works whether `/conveyor-belt:auto` is on or off.

- `asked-fix`: you report a problem or ask for a fix. The Foreman files the issue and queues it at once.
- `review-followup`: the review of a card you approved files a follow-up. The Foreman queues the follow-up when it
  only finishes or corrects that card's own change. Conveyor does this itself for a follow-up on a pipeline file: when
  the finding names only files of its parent card's change and no word of `auto.reserved`, the follow-up is not held.
- `release-check`: a check fails in a release you asked for, such as a false privacy hit or a red test file. The
  Foreman files one fix card for it. When the fix lands, the release goes on.
- `fixed-block`: a fix that landed removed the cause of a blocked card. The Foreman adds `Depends on: #<fix>` to the
  card's issue and runs `conveyor.sh retry <issue> --fresh`.

Some steps always go to you, whatever kinds are on: new engine behaviour that you did not ask for, a design choice, a
release that you did not ask for, and anything that `auto.reserved` holds.

The Foreman's start text lists each kind that is on, with these limits. It reads the kinds from each project's pack
on the host that runs its belt, where the Board turns them on or off. The commands the Foreman runs for a kind also
run on that host, for that project. `conveyor.sh auto standing` is different: it reads the pack of the checkout where
you run it, not the pack on the host. Each step
taken under a kind goes into the ruling log with its kind (source `standing`). The Foreman then tells you about it in
one line.
