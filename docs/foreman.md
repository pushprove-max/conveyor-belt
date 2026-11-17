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

The Foreman uses this command for its status checks. Its rules also tell it to run short commands in the foreground,
to put several checks into one command, and to read an image only when you ask or a check needs it.

A watcher wakes the Foreman when something needs it. The wake holds the outcome, so the Foreman does not have to look
it up:

- A card that the Foreman waits for lands: the wake names its commit.
- A blocked card: the wake names the reason.
- A release or full-test run that ends: the wake names the result and the failed cases.

A card that moves from one step to the next, as from build to review, gives no wake.

The Foreman's reply to a wake says only what needs you. If nothing needs you, the reply is the one word Idle. A
problem that the Foreman finds in Conveyor itself always needs you, because only you can fix it or file it. The
Foreman says it on a line of its own:

`Plugin problem (for the conveyor-belt repo): <what it saw>, card <card>, evidence <path>`

Each such problem also goes into `plugin-bugs.md` in the Foreman's folder, one line each: the time, the card, what the
Foreman saw and the evidence path. The Board's Health panel and `/units` then show "N plugin problems noted", with
the path of that file.

The watchers run from the Conveyor version that the project uses. When the project moves to a new version, as when
it follows the plugin's main and a new commit lands, the watchers stop within a minute and start again from the new
version. A card that lands while the version changes still wakes the Foreman. An update does not delete a version
that the Foreman's watchers still use. A later update deletes it, after those watchers stop.

## Is the Foreman listening?

`/units`, its band, its pane and the status line show one Foreman line:

- **Foreman listening**, in the colour for success: this session is the Foreman, its waiter runs from the Conveyor
  version that the project uses now, and its four watchers run.
- **Foreman not listening**, in the colour for a warning, with the reason:
  - `not the Foreman session`: another session has the Foreman role, or no session has it. In the Foreman's own
    session, run `/conveyor-belt:foreman` to take the role again.
  - `no waiter running`: no waiter runs for this session. The next end of a turn starts it.
  - `waiter on an old install`: the waiter runs from a version that the project does not use now.
  - `watcher down: <name>`: one of the watchers (`conveyor`, `limit`, `alerts` or `idle`) stopped and did not start
    again.

`/units` and the pane show one more line under it: the session that has the role, the waiter's process and its
version, and the state of each watcher. A project where no session has the role and no Foreman is set up shows no
Foreman line. The line comes from
the files in the Foreman's folder and from the process list of this machine. It does not start the waiter, and it
does not ask the host.

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
