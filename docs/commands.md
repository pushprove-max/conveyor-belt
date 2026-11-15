# Commands

## In Claude Code

- `/conveyor-belt:setup` sets up the project and runs `conveyor.sh doctor`. `/conveyor-belt:setup --foreman` also sets up
  the Foreman. `/conveyor-belt:setup --survey` asks for a test-speed survey.
- `/conveyor-belt:foreman` makes this session the project's Foreman. `/conveyor-belt:foreman off` ends it.
- `/conveyor-belt:away`, in the Foreman session: the owner is away. The Foreman works by the owner's own away rules,
  the file that the host file (this machine's settings, `~/.config/conveyor/host.json`) names as `foreman.away`.
  Conveyor ships none.
- `/conveyor-belt:review [base] [focus]` runs one Codex adversarial pass. Then it runs Codex review rounds until one
  finds no P0 to P2 finding, and fixes and commits after each round. It reviews the commits since one base (by default
  the `defaultBranch` of the pack, the project's settings file `.conveyor/project.json`) and needs the Codex CLI. Its
  wording is `conveyor/rules/review.md`, or the file that the pack names as `review.wording`.
  `conveyor.sh wording adversarial|review` prints it. In the fast lane, each round is a preview by the card reviewer
  (`conveyor.sh lane fast review`), which never lands anything.
- `/conveyor-belt:plan <what you want to do>` picks the skill, or the skills in order, of Matt Pocock's skills for it,
  and says what to type. It only recommends.
- `/conveyor-belt:auto on | narrow | off`, in the Foreman session ([Foreman](foreman.md)).

## Issues

- `conveyor.sh control hold <issue>...` keeps issues from being built. `conveyor.sh control release <issue>...` lets
  them be built again.
- A `Depends on: #N` line in an issue's body (several numbers, comma separated) makes the issue wait while #N is open,
  and while a follow-up filed from #N is open. `owner/repo#N` names an issue of another repository
  (`gh issue view --repo`). A repository that gh cannot read counts as open, and Needs you names the issue.
- The dependency guard is on by default. It keeps a waiting issue from being picked, whatever you do to it.
  `conveyor.sh control dep-guard off` turns it off (`dep-guard on` turns it on). Only then does
  `conveyor.sh control force <issue>` let that one issue be picked before the issues it depends on land.
- Before it picks an issue, the loop asks the builder's cheapest model whether the issue and a card on the belt change
  the same part of the same file. If they do, it adds `Depends on: #N` to the issue, with a comment. To remove a wrong
  dependency, use the Board's **Depends on…** ×, or `conveyor.sh control depends <issue> remove <N>`.
- `conveyor.sh retry <issue>` gives a blocked card back: the loop picks its issue again and starts from the card's kept
  work. An issue closed while its card was blocked is picked again on its own once it is opened again.
- `conveyor.sh control` with no action prints the control record. Its other actions (pause, cap, order, rules, models,
  the judge, accounts, the dependency guard) are in `conveyor/README.md`, Control.

## Every command `conveyor.sh` takes

`conveyor.sh` is the `conveyor/conveyor.sh` of the release setup installed ([Install](setup.md#install)). Run it in
the project's checkout.

The loop:

- `run [--only <issue>[,<issue>...]] [max-cards]` runs the loop in the foreground until nothing is left to pick. It
  starts at most `max-cards` cards. With `--only`, it builds those issues and the follow-ups filed from them, and
  `max-cards` is how many build at once.
- `serve` runs the same loop with no end, for one project.
- `machine` runs the machine's one Conveyor, a loop for every record of the host file. `machine pause` and
  `machine resume` pause and resume every project.
- `install-service` installs `machine` as the machine's service.
- `board` installs the [Board](board.md#install-the-board) as a user service, for the project of the checkout it runs in.

Cards:

- `retry <issue>` gives a blocked card back. `shut <issue>` shuts a blocked card whose issue was closed. A main-red fix
  card has no issue: use `retry <card id>` and `shut <card id>`.
- `land-branch <branch>` lands a branch's tip as one card, reviewed and tested as any card.
- `control [<action>]` changes the control record. `control depends` writes an issue's `Depends on:` line on GitHub.

Tests:

- `full-test` runs the pack's `test.full` on main. `full-test push` runs it and pushes what landed when it is green.
  `full-test anyway <run id> [--by <who>]` pushes over a red run.
- `push-now` pushes what landed through the project's pre-push hook only, as Conveyor pushes each card when the rule
  is On, with no `test.full` run. It refuses when nothing waits for a push or a full test run is under way. Use it for
  a small change. Use `full-test push` when the whole suite must pass first.
- `main-test` runs the whole test on main when one is due (the pack's `test.main`).
- `survey` files the monthly test-speed survey's issue when one is due (the pack's `test.survey`).
- `flaky add <case> <source> <note>` adds a flaky-test entry. `flaky off` adds one and files no issue.
- `testaction <judge | explain> <test file>` asks the Tests seat (the model set for test actions) about one test
  file in a read-only session. `testaction run <test file>` runs that test file alone, now, on a test slot.
  `testaction stop <id>` stops one (`conveyor/README.md`, Test actions).
- `testissue <test file> <title> <body>` files the Board's issue about one test file.
- `test-settings` saves a test setting in the pack: the budget of all files or of one, a "slow on purpose" mark, and
  whether slow files file issues (`conveyor/README.md`, The test files in the snapshot).
- `prices set <model> <input> <output> <cache read>` saves your price of one model in the pack, and
  `prices clear <model>` removes it ([Configuration](configuration.md#the-pack)).
- `testrules` sets the test rules that file issues about test files (`conveyor/README.md`, Test rules).

Declined findings:

- `declined add <card> <issue> <code | judge | owner> <why> <finding>` adds a line.
- `declined build <id>` files one as an issue.
- `declined dismiss [--by <who>] <id>...` hides lines from the Board's panel. The reviewer is still told not to raise
  them.

Lanes and the Foreman:

- `lane fast create | review | land | reset [--drop <sha>]` and `lane research create` ([Lanes](lanes.md)).
- `foreman [--new] [<claude argument>...]` starts the Foreman's Claude Code session in the main checkout. It resumes the
  last one unless you give `--new`.
- `foreman status [<project>]` prints the state of the Foreman's projects as short text ([Foreman](foreman.md)).
- `auto on | narrow | off | status | band | rules` is the Foreman's auto mode ([Foreman](foreman.md)): `on` and
  `narrow` start it, `off` ends it, `status` prints one line about it, `band` prints its state for the plugin's band,
  and `rules` prints what the Foreman is told while it is on. `conveyor.sh auto decide` is its decide step.

Setup and the engine:

- `setup [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] [--pin] [--foreman]` and
  `doctor` ([Setup](setup.md)).
- `install <commit>` installs that commit read-only.
- `take`: a project that follows main takes main's newest commit when it passes its check.
- `wording adversarial|review` prints the review wording.
- `clis` reads each CLI's models again and prints them.

Reading the belt:

- `check` checks the pack and the card records.
- `cards` and `health` print the cards and the health record.
- `snapshot` prints the Board's snapshot. `watch` prints a snapshot, then a line for each change.
- `history` prints, whole, the lists the snapshot cuts to their newest: landed and pushed cards, metrics, cost and
  declined.
- `github <folder>` writes a snapshot's GitHub reads into a folder.
- `state-dir` prints the state folder.
- `product <commit>` exits 0 when that commit changed product code.
- `pushable` exits 0 when no follow-up of the first two priorities waits. Else it lists them.
- `pick --dry --issues <file> --state <dir>` prints the issue a pick would take from those inputs, and writes nothing.

GitHub and releases:

- `gh-write <gh arguments>` runs a `gh` write through the privacy check.
- `release-prep <version>` prepares a release ([Releases](releases.md)).
- `release <version>` makes the release: the tag, the pinned marketplace entry and the GitHub release
  ([Releases](releases.md)). Only the owner decides a release: the Foreman runs it only after the owner says yes in
  chat.
- `release-run <version>` is the Board's **Release**: `release-prep`, then `release` when the suite passes.
  `release-run prep <version>` is its **Draft notes** and **Run suite**: `release-prep` alone, which releases nothing.
  `release-run stop` stops that run ([Releases](releases.md#a-release-from-the-board)).
