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

The Foreman's session is named `<project> - foreman` at its start, for example `conveyor-belt - foreman`. A Foreman of
several projects uses the name of the first one. A session that takes the role with `/conveyor-belt:foreman` gets the
name when you send your next message. A session that is not the Foreman gets no name from Conveyor. `/conveyor-belt:foreman off`
ends the role but leaves the name.

The Foreman keeps its saved state in `state.md`, in the Foreman's folder (`foreman` in the folder that
`conveyor.sh state-dir` prints). The line of a finished item starts with `- DONE`, and the next start moves those
items to an archive file. The cap on the saved state counts only its open lines, not the `- DONE` items. When the open
lines go over the cap, the first try to end the turn is refused, with a request to mark the finished items and make
the rest shorter. The next try ends the turn. The same first try is refused when an open line waits on something that is over: an
issue it waits on ("after #<n> lands", "close #<n>") that is no longer open, or a path it says to remove that is gone,
on this machine and on the build host. The request names each line and why.

Claude Code keeps the output of a hook over 10,000 characters out of the session. So the Foreman's start sends its text
in two outputs, each kept short. The first holds the fixed text, the rules of auto mode, the standing kinds of routine,
the live summary and the saved state. The live summary gets only the room that the text before it leaves, and is cut
at a whole line. Run `conveyor.sh foreman status` for the full status of the cards. The Board's Needs you panel shows
all open decisions. The start does not hold the Foreman's steps for a release's suite, a pack that is not committed
and a card that waits for main. It names a command that prints them, and the Foreman runs it when one of them comes
up. When the rules of auto mode and the standing kinds leave no room for the live summary, the start
puts them in `start-rest.md` in the Foreman's folder. A start or claim that also holds the rules does the same when
the move lets a larger set of the saved state and the rules fit. The sets, largest first: the saved state, the owner
rules and `rules.md`; the saved state and the owner rules; the owner rules only. When the move gives more room but the
same set, the text stays where it is. One line in their place tells the Foreman to read that file now.
When the saved state does not fit with the rest, the start leaves it out and
has one line in its place that tells the Foreman to read that file now, with its path. The second, a SessionStart
hook of its own, holds the project's `rules.md` from the Foreman's folder, and only in the Foreman's session: any other
session gets no rules. A `rules.md` that is too long for its output is cut at a whole line, and the last line names
the file and tells the Foreman to read the rest. When you make a running session the Foreman, no new start follows, so
the claim prints `rules.md` after the rest, cut the same way to what the limit leaves. A project whose plugin and
Conveyor commit are of different versions still gets its rules: when the plugin lacks the second hook, the first
output holds `rules.md` after the rest, cut the same way. When the Conveyor commit is older than the second hook, its
start holds `rules.md` before the rest when the whole fits, and otherwise has one line in its place that tells the
Foreman to read that file now.

The same second output starts with the rules on working with the owner. Every project's Foreman gets them, with no
`rules.md` needed; the plugin ships them, and `rules.md` follows them:

1. Scope is the owner's words. An issue for an owner's order opens with those words. Anything the Foreman adds goes to
   the owner item by item, by picker. An old order never covers a new issue. An order that overrides an older ruling
   notes that ruling in the issue.
2. A question from the owner gets an answer and nothing else: no filing, no fix and no picker, unless the owner orders it.
3. Before a picker, the Foreman reads `rulings.jsonl` in its folder for the topic. When a ruling covers it, the
   Foreman acts on it and cites it. It finds a typed order by session, source `"prompt"` and a phrase, never as the
   last row.
4. Pickers hold real options only. Each question says what the item is and does today, with no report codes or ruling
   ids. "Recommended" marks the Foreman's own choice. What it did not check is tagged [likely]. When the owner is silent
   for 30 minutes or more, the questions wait and go together later.
5. An approved mockup is the spec. Before done, the Foreman puts the live output beside it and lists every difference.
6. Closing an issue does not stop its card: `conveyor.sh shut <issue>` does.
7. A batch of cards is awaited by the idle wake ("Conveyor is idle"), not by one await line per card.
8. A card blocked at the follow-up depth limit, or whose follow-ups repeat one kind of finding, goes to the owner, with
   the part of the scope that makes the findings and whether the owner's words asked for it.
9. A refusal by a safety check or a hook is never retried in another shape.
10. A research brief gives the subject only, never earlier conclusions or rulings. The Foreman applies its rulings after.
11. The Foreman never offers the owner manual work. A step only the owner can do (a login) is given alone, as one command.
12. A hold that you took off (on the Board, or with `control release`) is your release, not a fault. The Foreman does
    not hold that issue again unless you order it, and does not report it as a plugin problem.
13. An issue with a `## What to build` section needs a `## Design` section that settles what that section leaves open.

The Foreman uses the 1-hour prompt cache. `conveyor.sh foreman` starts its session with it. For a session in the main
checkout, `/conveyor-belt:setup --foreman` sets `CLAUDE_CODE_PROMPT_CACHE_TTL` to `1h` in the `env` of
`.claude/settings.local.json` there, and keeps the other settings in that file. When that file is not a JSON object,
setup leaves it as it is and says so. A session keeps the cache time it started with. When the session that takes the
role runs with another cache time, such as `5m`, the claim says so in one line. Start that session again to get the
1-hour cache.

To keep the Foreman's session short, set `foreman.compactAt` in the host file to a whole number from 1 to 100. It is
the percent of the model's context at which Claude Code compacts the session. Run `/conveyor-belt:setup --foreman`
again after you change it. With the key not set, nothing changes ([Configuration](configuration.md#the-foremans-compact-point)).

While the Foreman is idle, the waiter sends it a short keepalive turn every 50 minutes, so the cache stays warm. It sends
at most 10 keepalive turns in one idle spell: the count starts again when you use the Foreman. Before
the next one, it reads the usage of the last keepalive turn. When the turn wrote the cache again and read none of it,
the cache did not stay warm, so the waiter sends no more keepalive turns until the Foreman is active again. When you
used the Foreman after the last keepalive turn, the waiter does not read that usage, and the keepalive turns go on. Each
stop adds a line with the turn's usage to `keepalive.log` in the Foreman's folder. When the usage cannot be read, the
keepalive turns go on, up to that limit.

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

- when a new snapshot fails, the last saved one with its age and why the new read failed, as
  `<project>: the last snapshot, made <age> (a new one failed: <why>):`, and when no snapshot can be read or found,
  `<project>: no snapshot (<why>)`
- each card on the belt, one a line: its issue, step, time in that step and title
- when the card records changed after the last snapshot was made, "as of <time>, the belt has changed since" after the
  count of cards on the belt. The cards building and the blocked cards then come from the card records and
  `loop.json`, which are up to date. While the loop runs, the count on the belt comes from them too, and the
  line says the snapshot is behind the card records.
- when the snapshot shows the engine stopped and the engine runs now, "the engine (pid <n>) runs". The status reads
  the engine's process state each time it runs, on the machine of the belt (over `ssh` when the host file names a
  host).
- the pinned order that `control order` sets, first to last, as `pinned: #6 c20261101T000001-alpha-0`: an issue
  by its number, a card with no GitHub issue by its card ID
- the cards that wait on other issues, and the held issues, by number. After each held issue, in brackets, what holds it
  and the step that clears it: `#12 (your hold: control release)`, `#13 (split: waits for its parts #14 #15)` or
  `#16 (card blocked: retry)`. `control release` frees only an issue you hold. For any other, it changes nothing and
  prints a line on stderr that says so; the bracket names what to do instead. A held issue that you released, with
  **Queue** or **Remove the label and queue it** on the Board, with "Release it, first in the order" in **Needs you**
  on the Board, or with `control release`, also shows when: `#7 (waits for your yes; you released it
  2026-11-24T10:15:00Z)`. An issue you released that is now in the queue shows on its own line:
  `released by you: #9 at 2026-11-24T10:15:00Z`. The Foreman does not hold such an issue again. When auto gives
  that answer, the release does not show as yours. When the Foreman, the standing kind `review-retry` or auto retries
  the card of a held issue, the card goes back, but the issue stays held until you release it. To see who or what took a hold off, look in
  `<state folder>/holds-dropped.jsonl`: each line gives the time, the issue and who or what took the hold off
  (`owner` for your release). The file has only the holds of the control record. A hold that only a label made, and
  that **Remove the label and queue it** took off, has no line there.
- the release or full-test run in progress: its commit, how long it has run, the cases done of all its cases, and the
  failed cases. With no run in progress, it shows how the last run ended.
- each item that needs you, one a line: a blocked card with its reason, a change that waits for your yes, a push
  error, an issue that waits on a shut issue (`dependency cannot land`, with the reason) and a problem of the engine.
  A `dependency cannot land` line also wakes the Foreman.
- `not yet reported: blocked #N (card <id>)` for each card blocked for two polls or more that the Foreman has not
  got in a wake. The next wake names it too. A card with no issue shows its name and its card ID, for example
  `not yet reported: blocked Review follow-up of #7 (card <id>)`.
- the watcher's last poll: when it ended and how long it took, with what it read for each project
- last, the Foreman's waiter: `waiter: listening`, `waiter: starting again` or `waiter: down: <why>`

The Foreman uses this command for its status checks. Its rules also tell it to run short commands in the foreground,
to put several checks into one command, and to read an image only when you ask or a check needs it.

Before the Foreman starts a release's suite (`conveyor.sh release-run prep <version>` or `conveyor.sh release-run
<version>`), it asks you by the picker: "Run the test files one by one or in parallel?". **One by one** is slower and
puts the least load on the build machine. **In parallel** (for example **In parallel (2 at once)**, with the number
of files that run at once for that project) is faster, but puts more load on the build machine, and the
belt is slower while the suite runs. The Foreman adds your answer to the command: `--serial` or `--parallel`.

When the control record sets a suite machine other than this one, the Foreman also asks "Run the suite on which
machine?". The first option is the machine of the rule, marked Recommended. The second is **This machine** (the belt
is slower meanwhile), which adds `--machine local` to the command, so that this one suite runs here and the rule stays
as it is. With the rule on this machine, the Foreman does not ask this question.

A watcher wakes the Foreman when something needs it. The wake holds the outcome, so the Foreman does not have to look
it up:

- A card that the Foreman waits for lands: the wake names its commit. While another card that the Foreman waits for
  is still on the belt and not blocked, the wake is held. When the last of them lands, one wake names each landing and
  its commit. A card that lands while no other awaited card is on the belt wakes the Foreman at once. A restart of
  the waiter sends the held landings. Any other wake that the watcher makes from a snapshot names them too. A wake made
  from `conveyor.sh health` alone, because the snapshot is slow, does not: the landings stay held for the next one.
  To stop waiting for a card, the Foreman adds the line `-<issue>` to its list of awaited issues. That card then
  gives no wake when it lands, unless the Foreman adds the issue to the list again.
- A blocked card: the wake names the reason. When the snapshot fails or is slow, as when it is made anew from the
  whole card records, the watcher reads `conveyor.sh health`. A blocked card, or a change that waits for your yes,
  then wakes the Foreman from health at that poll, and does not wait for the snapshot. With the standing kind
  `review-retry` on, a card that its review blocked gives no wake, unless its retry fails, `review-retry` already
  retried an earlier card of its issue one time, its reason holds a word of `auto.reserved` or an item of your profile, or the watcher
  cannot read these words on the host ([Standing yes](#standing-yes)).
- A stopped process: the engine, or the process of a card, is stopped (state T in `ps`). The wake names it. Run
  `kill -CONT` with each process ID of the tree, as the wake gives it, on the machine where the engine runs to resume it.
- A card that is still blocked 30 minutes after its first wake: the wake says "#N has been blocked for <time> (since
  <time>)" and gives the reason. A card with no issue shows its name and its card ID in place of "#N", for example
  "Review follow-up of #7 (card <id>)". While the card stays blocked, the next wake comes one hour later, and then each hour. If one of
  your open questions names the card's issue (`#N`), there is no wake. A card that is retried, unblocked, shut or
  landed gives no more of these wakes.
- gh is signed out, GitHub does not answer, or the project gives no snapshot: the wake comes only when three polls in
  a row find it. One or two such polls give no wake. A gap of more than three polls since the last such poll (for
  example, a machine that was asleep) starts the count again at one.
- A release or full-test run that ends: the wake names the result and the failed cases.
- Each fix card of a failed release suite has landed
  ([Fix cards of a failed suite](releases.md#fix-cards-of-a-failed-suite)): the wake names the version. It says that
  release-prep started again, or why it did not start. A card on the belt, or a push that is still owed, gives no
  wake, because release-prep starts when it ends. If the Rules tab's **Push on landing** rule is off, a push
  that is owed gives the wake, because the push waits for you. If the rule **Land as** is pr and the rule **Merge
  PR** is button, the wake also asks you to merge the landing pull request, and a pull request that is not merged
  after the push gives one more wake.
- A fix card of a failed release suite was closed with no landed card: the wake names the issue. The release then
  waits for the Foreman, because release-prep does not start again by itself.
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

An issue that the Foreman files is held until you say yes. While the Foreman files it, every record of the host file
starts new issues held, follow-ups too. If the engine of one record cannot hold a follow-up that way, the filing
command does not run, even when it files in another project, and the Foreman is told to update that engine. After it files the issue, the Foreman holds it in the record for its GitHub repository. That
is the record whose main checkout on this machine has a remote (`origin`, or the pack's `remote`) for that
repository, so the record's name can be different, as when setup named it for its folder. This is also true when the
Foreman runs in a worktree of that main checkout. The owner and the name of the repository must both agree. A main
checkout that is not on this machine is read over `ssh` on the host that the host file's `ssh` names. If no record has
such a main checkout, it is the record with the name of the repository, unless its main checkout is for another
repository. Letter case does not count. If no record
is for the repository, the Foreman tells you the repository, the records it looked at, and the fix: set the `main` of
the project's record in the host file to its main checkout on this machine, or run `conveyor.sh setup` in that
checkout.

The Foreman files a fix issue only with a `## Cause` section. A fix issue is one with a `## What happens now` section
or the `bug` label. If the section is missing, the filing command does not run, and the Foreman is told what the
section must hold: where the bad data or behaviour comes from and why it is there at all, a place in the code that
already solves the same problem (or that none was found), and what the reader sees when the data is stale or missing.
The check also covers `foreman.sh ask <project> testissue`. An issue for new work that you ordered, with neither the
section nor the label, is not checked, and nor is an issue that the engine files itself, such as a follow-up.

The Foreman also files an issue with a `## What to build` section only with a `## Design` section, for a fix issue and
for new work. If the section is missing, the filing command does not run. The Foreman is told that the section must
decide what `## What to build` leaves open: where each new piece of data is kept (the file or record) and its key, each
limit as a number with its unit, the one place that reads it, and each choice made where the text says "for example" or
"A or B". A fix issue with neither `## Cause` nor `## Design` is refused for the missing `## Cause` first. The text of
the section is not judged.

The Foreman can also file an issue about a test file with `conveyor.sh testissue`, the Tests page's command. For a
Foreman session, this command holds the issue in the project's record and says so. It also holds an issue that it
files when the project's New issues start in is Held. When the Rules tab's **Tests page actions** (under **Cards with
no GitHub issue**) is On, the command files no issue. For a Foreman session, it starts a held card with no GitHub
issue and says so: `conveyor.sh control release <card id>` releases the card after your yes. The Foreman runs the
command with `foreman.sh ask <project> testissue`, so the issue or the card is held also when the project is on a
host, or is another project of the Foreman's group.

When the Rules tab's **Foreman orders** (under **Cards with no GitHub issue**) is On, the Foreman starts a change that
you order with `foreman.sh ask <project> card <title> <body>`. The command files no issue: it starts a held card with
no GitHub issue and says so, and `conveyor.sh control release <card id>` releases it after your yes. Off, the command
files a fix issue and holds it, and it refuses a body with no `## Cause` section, as the filing check does for any fix
issue. The filing check does not read the command. For the fix
card of a red release suite, the Foreman runs `foreman.sh ask <project> card --release <version> <title> <body>`.
**Release fix cards** decides the same way for it: On, the card has no GitHub issue, and Conveyor reads its
`Release fix: <version>` line and starts the suite again once each fix card has landed and its change is in the commit
the suite tests. Off, the command files a fix issue, and it refuses a body with no `## Cause` section in the same way.
When `card` or `testissue` is stopped at its time limit, or loses its connection to the host, after it filed the
issue, it still prints the issue's link and ends with success, and it tells the Foreman not to file the issue again.
The hold can be missing then: the Foreman holds the issue with `foreman.sh ask <project> control hold <issue>`, unless
you said yes to it, and takes the built label off it. When it is stopped or loses its connection before it printed a
link, or GitHub did not answer in time, the Foreman looks for the issue in the project before it files again: GitHub
can make the issue and still not answer.
**Review follow-ups** and **Split parts** are
for the cards that Conveyor files itself, so the Foreman does nothing for them; see
[Cards with no GitHub issue](cards.md#cards-with-no-github-issue).

The Foreman's start names `foreman.sh` by one command, `conveyor/foreman.sh` in the data folder (`~/.local/share`
unless `XDG_DATA_HOME` says otherwise). Its path does not change when the engine moves to a new version, and it runs
`foreman.sh` of the engine the project runs, the one its hooks run. The start writes it again when it is not there
or not up to date. When the start cannot write it, the start's text begins with a `# WARNING:` line that says so: the
start's `foreman.sh` command then may not run, or may run the command that is already there.

A card that moves from one step to the next, as from build to review, gives no wake.

### A blocked card that the Foreman takes

When the Foreman takes a blocked card (it runs the card by hand, files a fix card, or asks you with a picker), it
writes one line about it with `foreman.sh note <card> <what it does>`, as its start text tells it to (by
`foreman.sh procedures`, which the start names). /units then
shows the card under `FOREMAN HAS IT`, with the note and its age, in place of the block reason, and not under
`NEEDS YOU`. On the Board, the card shows the note and its age, marked `Foreman has it`, after the cards that wait
for you, in the Needs you column and in Overview's Needs you panel. A card that waits for your answer to the
Foreman's picker gets `foreman.sh note <card> --ask <the question>`: it stays under Needs you, with
`waits for your answer` and the note. Only the Foreman's own session can write a note, and only on a card that is
blocked: on a card that was retried, landed or was shut, the command fails and says so. It also fails on a card that
waits for your yes (a visible change or a lint policy change), as Needs you shows that card already. A new note on the same card
replaces the one before.

The note is kept with the card's project, on the machine where the belt runs (`foreman-notes` in that project's state
folder), so /units and the Board show it also when the Foreman runs on your own machine. A note shows only while its
card stays blocked and the Foreman keeps the note alive. The Foreman's Conveyor watcher does this at each poll, while
the Foreman session holds the role and runs in its Claude process. When the card is retried or held, lands or is
shut, the note goes away at once. When the session ends, another session takes the role, or you open another session in the
Foreman's Claude process with `/resume`, the note goes away within five minutes. While the watcher is down, the notes
go away too. A note that went away does not come back, also when the same session starts again: the Foreman writes
it again.

The Foreman's reply to a wake says only what needs you, and the `Done without asking` line for each step it took on a
standing yes since its last reply. While a push is blocked, the reply can also have one line that says what blocks
the push and which card clears it, for example `Push blocked: typecheck-web failed after #12; cleared by <card>.` A
wake for a blocked push with the same check and the same error as an earlier one says that it is a repeat of that
block, not a new one. When the push goes through after such a wake, one more wake comes, and the reply says
`Push went through: <what>.` If none of these is owed, the reply is the one word Idle. But while a wake names a
blocked card as `not yet reported`, or names it in its own first wake (`<project>: <card> is blocked since <time>:
<why>`), the Foreman cannot end its turn until it takes a step on that card: it logs an act
for it with `auto act`, it asks you about it, or the card moves (retried, shut or landed). The same holds on a turn
that you open, while `foreman status` names a card `not yet reported`, also when the build host is down and the
status shows the last snapshot. The act or the question
names the card by its id. A card that the wake names by its issue can also be named by its project and issue
together, as `alpha #7`, or by the project's GitHub repository and the issue, as `example/alpha#7` or the issue's
link. The repository is the one the build host's checkout has, so an issue of your fork names no card. A card's
name, or `#7` alone, names no card. A question that a hook refuses, as with auto on in full, does not count. A wake
text that you paste into your own message does not start this check. A problem that the Foreman finds in Conveyor itself always needs you. Who files it depends on the project:

- In any other project, you file it in the plugin's repository. The Foreman says it on a line of its own:

  `Plugin problem (for the conveyor-belt repo): <the command or step>, <what it did>, <what it expected>[, cause not checked: <what the Foreman thinks the cause is>], card <card>, evidence <path>`

- In the plugin's own repository, the Foreman files it there at once, as it files any other issue. The issue is held
  until you say yes. The line ends with the issue number:

  `Plugin problem (for the conveyor-belt repo): <the command or step>, <what it did>, <what it expected>[, cause not checked: <what the Foreman thinks the cause is>], card <card>, evidence <path>, filed as #<n>`

  If the line has no issue number, the Foreman cannot end its reply. It gets the reason and files the issue. When the
  Foreman starts, it gets a list of the entries in `plugin-bugs.md` that have no issue number. The list holds only the
  entries that fit in the start. A line after them tells the Foreman to read `plugin-bugs.md` for the rest. When no
  entry fits, one line in place of the list tells it to read that file. For each entry, it first looks for an issue that already reports the problem, such as
  one that you filed, and uses that issue's number. It files only the entries that no issue reports.

The line says what the Foreman saw: the command or step, what it did and what the Foreman expected. A cause that the
Foreman checked in the code or the logs goes in what it did, with where it checked. A cause that it did not check goes
in the last part of the line before the card, as `cause not checked: <text>`. The line is never refused for that part.
A clause that holds `[likely]` outside the part is noted inside it. The report that you file from the Board shows the
part on its own line, as `Cause (not checked): <text>`.

Each such problem also goes into `plugin-bugs.md` in the Foreman's folder, one line each: the time, the card, what the
Foreman saw and the evidence path. In the plugin's own repository, a line that is said again with `filed as #<n>` takes
the place of the first one. In another project, it is a second line. The Board's Health panel and `/units` then show "N plugin problems noted", with
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

A Foreman session that Claude Code starts or resumes gets its waiter at once, when the session starts, also when no one
types into it. That waiter can wake the session. When a waiter that can wake the session already runs, the start
leaves it running.

When the waiter stops for any other reason, the next prompt or tool call of the Foreman session starts it again. A
check of the waiter's process runs at each of them. It starts a waiter only when none runs, and only one. A session
can go on in a new Claude process. The waiter of the old process then stops, and the start of the new process, or its
next stop, prompt or tool call, starts a waiter for the new one. A wake that the old process did not get stays, and the new process gets it. When the
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
- Two `needs you` items from the engine are open decisions too, so auto decides them like any other
  ([Cards](cards.md)). A card that is blocked with its work kept: the recommended step is "Retry keeping the work",
  which gives the card back as `conveyor.sh retry <issue>` does. Auto retries an issue once for one block reason: when
  the issue is blocked again for the same reason after that retry, auto leaves it under "Waiting for the owner". A retry you pick yourself counts when you chose "Retry keeping the work", and does not count when you chose "Fresh retry". An issue that the nightly whole test filed for a test
  that fails on main, and the engine holds: the recommended step is "Release it, first in the order". On `narrow`, auto
  decides one only when you gave that answer to the same question before. After an engine upgrade, the engine can ask
  this decision again with no recommended step, when it cannot tell if an older engine acted on your answer. Auto
  does not decide that one: it stays under "Waiting for the owner". Auto leaves either one under "Waiting for the owner"
  when its text holds a word of `auto.reserved`, such as `delete`. A card stopped for your yes, and a main-red fix
  card, are not decisions, so auto does not touch them.
- Auto goes on deciding on the build machine (the host that has the card record) while your machine is off or the
  Foreman session is not running. Each time the engine posts a new open decision, the engine decides it by the same
  rules as `auto decide`. It logs each decision in the auto log on that host, then takes the step that the answer
  names. When `review-retry` is on ([Standing yes](#standing-yes)), the engine also retries a card that its review
  blocked, and logs that step in the ruling log. When the Foreman runs on your own machine, `/conveyor-belt:auto on`,
  `narrow` and `off` set the same mode on the host, with a log of its own there. `on` and `narrow` first send your
  picker answers from the ruling log on your machine to the host, with the items of `owner-way.md` on your machine,
  and each `auto decide` of the Foreman sends them again. When the items of `owner-way.md` change, the end of the
  Foreman's next turn sends them to the host. This also occurs while auto is off, because the watcher on the host
  holds a card for `review-retry` by the items it got last ([Standing yes](#standing-yes)). If the host does not get
  them, the Foreman tells you, because the engine and the watcher there decide by the items they got last. The end of each later turn sends them again. When the Foreman session starts again, it reads that log and
  tells you what the engine decided. What `auto.reserved` and `owner-way.md` hold, and anything against one of your
  rulings, still wait for you.
- `owner-way.md`: a project can keep a written profile of how its owner decides. Make it from the ruling log, and put
  it in the Foreman's folder, beside `rules.md`: `foreman` in the folder that `conveyor.sh state-dir` prints. For a
  group in `foreman.groups`, use the folder of the first project in the group. The
  Foreman keeps it current. While auto is on, the Foreman reads it before it decides. It keeps the file's "Never
  decide; ask" and "Hard lines" sections as it keeps `auto.reserved`. `auto decide` leaves a decision under "Waiting
  for the owner" when its text holds an item of those sections (a `- ` line under the heading), as it does for a word
  of `auto.reserved`. When the engine cut a long question, `auto decide` also reads the whole block reason or case
  list that the engine kept. So a question under "Waiting for the owner" can name no such word or item: it is in the
  part of the text that the question does not show. The plugin ships no such file. With no file,
  auto reads the ruling log, and on a host, the items of `owner-way.md` that your machine sent there.

## Standing yes

Some routine steps get the same yes from you each time. You can give that yes once, kind by kind. The Foreman then
takes those steps without asking. Each kind is off until you turn it on in the Rules tab of the Board ("... without
asking"). The pack keeps the list as `auto.standing`. A kind works whether `/conveyor-belt:auto` is on or off.

- `asked-fix`: you report a problem or ask for a fix. The Foreman files the issue and queues it at once.
- `review-followup`: the review of a card you approved files a follow-up. The Foreman queues the follow-up when it
  only finishes or corrects that card's own change. Conveyor does this itself for a follow-up on a pipeline file: when
  the finding names only files of its parent card's change and no word of `auto.reserved`, the follow-up is not held.
- `release-check`: a check fails in a release you asked for, such as a false privacy hit or a red test file. The
  Foreman files one fix card for each failure, with the line `Release fix: <version>` in its body. When the fix
  lands, the release goes on. After a failed suite, Conveyor runs the suite again itself when each fix card has landed
  ([Fix cards of a failed suite](releases.md#fix-cards-of-a-failed-suite)).
- `fixed-block`: a fix that landed removed the cause of a blocked card. The Foreman adds `Depends on: #<fix>` to the
  card's issue and runs `conveyor.sh retry <issue> --fresh`.
- `review-retry`: the review blocks no card on a finding. The card lands, and each open finding becomes a follow-up
  ([When the fix loop ends](cards.md#when-the-fix-loop-ends)). For an issue at the follow-up depth cap, a finding goes
  on the self-heals list in place of a follow-up. This kind acts only on a card that the card records
  still show blocked because the fix for a finding did not hold after its fix rounds. The Foreman's watcher runs
  `conveyor.sh retry <issue>` for that card on the host itself, one time for each issue, and logs the step in the
  ruling log. While auto is on, the engine on the host does this step too, also when the watcher is not running. The
  Foreman gets no wake for that card and does not tell you. If the retry fails, the blocked card wakes the Foreman, and
  the wake gives the reason of the failed retry. The engine does not retry a card whose block reason holds a word of
  `auto.reserved` (a finding tagged `[security]`, for example) or an item of the owner's profile, or when it cannot
  read `auto.reserved` or your profile on the host. Only a whole word counts: `rea` holds "the rea check", but not
  "already". The watcher then leaves the card blocked and wakes the Foreman with the block's reason. For a word or an
  item, the wake and each later reminder of the card also say that review-retry left the card for you, and name the word. The Foreman puts the card to you. The retried card goes through its review, its tests and
  its landing as any card does. When its review blocks it again because a fix did not hold, and auto is `on`, the
  engine gives the card back one time to land its kept patch, and files the finding as a follow-up (review-land). It
  does not do this when the reason names a P0, a word of `auto.reserved` or an item of your profile, or when the issue
  is at the follow-up depth cap. Otherwise the card comes to you in **Needs you** with both block reasons, and auto
  does not retry it. Review-land closes the card's open decision just before it gives the card back. After that, the
  Board refuses an answer to that decision, also while it still shows the question. A review block of another form,
  such as "review <n> is the last review and still holds a P1 finding", is not one that `review-retry` acts on. It gets the usual
  decision, and auto can answer it with a retry.

Some steps always go to you, whatever kinds are on: new engine behaviour that you did not ask for, a design choice, a
release that you did not ask for, and anything that `auto.reserved` holds.

The Foreman's start text lists each kind that is on, with these limits. It reads the kinds from each project's pack
on the host that runs its belt, where the Board turns them on or off. The commands the Foreman runs for a kind also
run on that host, for that project. `conveyor.sh auto standing` is different: it reads the pack of the checkout where
you run it, not the pack on the host. Each step
taken under a kind goes into the ruling log with its kind (source `standing`). For each kind but `review-retry`, the
Foreman then tells you about it in one line. A landing by `review-retry` while auto is on is in auto's log, so
`auto status`, the auto band and the Foreman's account of what auto did show it.
