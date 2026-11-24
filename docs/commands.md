# Commands

## In Claude Code

- `/conveyor-belt:setup` sets up the project and runs `conveyor.sh doctor`. `/conveyor-belt:setup --foreman` also sets up
  the Foreman. `/conveyor-belt:setup --survey` asks for a test-speed survey. Setup asks if you want a fast lane and a
  research lane.
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
  and while a follow-up filed from #N is open. When the card of #N (or of a follow-up) lands, #N (or that follow-up) stops
  holding the issue, also with push off: the issue is built on top of the landed change. Any other open issue it waits
  on still holds it. `owner/repo#N` names an issue of another repository
  (`gh issue view --repo`). A repository that gh cannot read counts as open, and Needs you names the issue.
- The dependency guard is on by default. It keeps a waiting issue from being picked, whatever you do to it.
  `conveyor.sh control dep-guard off` turns it off (`dep-guard on` turns it on). Only then does
  `conveyor.sh control force <issue>` let that one issue be picked before the issues it depends on land.
- Before it picks an issue, the loop asks the builder's cheapest model whether the issue and a card on the belt change
  the same part of the same file. If they do, it adds `Depends on: #N` to the issue, with a comment. To remove a wrong
  dependency, use the Board's **Depends on…** ×, or `conveyor.sh control depends <issue> remove <N>`.
- `conveyor.sh retry <issue>` gives a blocked card back: the loop picks its issue again and starts from the card's kept
  work. An issue closed while its card was blocked is picked again on its own once it is opened again. A card that
  stopped for your yes to a visible change is the exception: if the issue's `## What customers or staff will see`
  section changed after the card stopped, the issue asks for a different change, and the next card builds from nothing.
  If the issue is held, `retry` also releases it. If the issue has no card, `retry` names the state folder it read
  and says to release the issue with `conveyor.sh control release <issue>`, which starts a new card. If another
  state folder of the checkout has a card of the issue, `retry` and `conveyor.sh doctor` name that folder too.
  A card can stop in flight: its process is gone or was stopped by a signal, or no process of its step ran for the
  pack's `tunables.stuck` plus `tunables.reviewPause`. `retry` first blocks that card and keeps its work, then gives
  it back. `retry` refuses a card whose process runs, and says to stop it with `shut` first.
- `conveyor.sh shut <issue>` or `conveyor.sh shut <card id>` stops an open card. It ends the card's processes, keeps
  its work as `retry` keeps it, and closes the card with the reason "shut by the owner". It holds nothing, and the
  loop does not pick the issue again on its own: `retry <issue>` gives the card back. A card in its land step is left
  to land, but a card that waits for room under the card cap after its landing failed is stopped. A card that has started to file its follow-ups or the slices of its issue is left to finish. `shut` prints what it did. If it did nothing to an issue, it says why and exits 4, for example when the issue has no
  card or its card landed. A failure, such as card records that it cannot lock, exits with another code.
- `conveyor.sh retry <issue> --fresh` gives a blocked card back without its kept work: the next card builds from
  nothing. The kept work moves to a dated folder under `kept-dropped/` in the state folder; it is not deleted.
- `conveyor.sh unblock <issue> --hold` takes a blocked card off the belt and holds its issue. Its kept work stays.
  After `conveyor.sh control release <issue>`, the loop picks the issue again and starts from that kept work. This is
  the Board's **Hold**.
- A parent issue keeps a large piece of work as one issue. Its parts are its GitHub sub-issues, and each part is an
  issue with its own number and its own card. The loop never picks an open issue that has sub-issues. At each turn,
  the loop closes an open parent when each of its parts is closed or landed on main, with a comment that names them
  and says which landed. This is the same with the rule **Push on landing** on or off.
  `conveyor.sh parts <parent> <issue>...` attaches the issues as sub-issues of the parent. You can also attach them on
  GitHub. The Board and `/units` get the parent of each issue in the queue, on the belt and in Needs you, and one
  entry for each parent with its parts done (closed, or landed and not pushed) of all and its parts on the belt.
- `conveyor.sh control` with no action prints the control record. Its other actions (pause, cap, order, rules, models,
  the judge, accounts, the dependency guard, the push check) are in `conveyor/README.md`, Control.
  A ready issue that `control order` names starts before the queued cards with no GitHub issue.

## Every command `conveyor.sh` takes

`conveyor.sh` is the `conveyor/conveyor.sh` of the release setup installed ([Install](setup.md#install)). Run it in
the project's checkout.

The loop:

- `run [--only <issue>[,<issue>...]] [max-cards]` runs the loop in the foreground until nothing is left to pick. It
  starts at most `max-cards` cards. With `--only`, it builds those issues and the follow-ups filed from them, and
  the open parts of a parent among them, and `max-cards` is how many build at once.
- `serve` runs the same loop with no end, for one project.
- `machine` runs the machine's one Conveyor, a loop for every record of the host file. `machine pause` and
  `machine resume` pause and resume every project.
- `why <pid | name>` names a process, its parents, and the card, step and project it belongs to, or says that no card
  owns it. `work` lists the busy processes by card and step, the heaviest first, then the busy work that no card
  owns. A closed card's processes show as left over, with the command that stops them. Both take `--json`
  (`conveyor/README.md`, Why the machine is busy).
- `bench drift [<engine commit>]` compares the cards that ran on an engine commit with the cards that ran on the
  commit before it: tokens, minutes, reviews to land, fix rounds, blocks and waits (the [drift watch](benchmarks.md#drift-watch)).
- `bench swe <n>` runs the first n tasks of SWE-bench Verified through Conveyor, n from 1 to 500, and the official
  harness grades them. `--arm <arm>` builds them with another arm, such as Codex alone or Claude with a plugin; give it
  more than once to compare arms on the same tasks. `--engine <version>` builds them with an earlier release or a
  commit, `--solo` with Claude alone. `bench swe arms` lists the arms and the state of their preflight, and
  `bench swe arms check <arm>` runs a preflight. `bench swe stop` ends a run, `bench swe results` shows every arm's and
  version's results side by side, and `bench swe diff <A> <B>` says why two arms or versions differ
  ([Benchmarks](benchmarks.md)). `bench swe history` prints every run with each arm's figures and the state of every
  arm, and `bench swe show <run>` prints one run's tasks by arm, both as JSON, for the Board's Benchmarks tab.
- `install-service` installs `machine` as the machine's service.
- `board` installs the [Board](board.md#install-the-board) as a user service, for the project of the checkout it runs in.

Cards:

- `parts <parent> <issue>...` attaches the issues as GitHub sub-issues of the parent ([Issues](#issues)).
- `retry <issue>` gives a blocked card back; with `--fresh`, its next card builds from nothing. `shut <issue>` stops an open card and shuts it, or shuts a blocked card whose issue was closed. `unblock <issue> --hold` holds a
  blocked card's issue and keeps its work. A main-red fix
  card has no issue. It shows as "Main is red (<commit>)". A card from the Tests page with the Rules tab's Tests page
  actions On (Cards with no GitHub issue) has no issue too. It shows as "Tests page: <file>". For these cards, use
  `retry <card id>` and `shut <card id>`. `retry 0` lists the blocked ones by card id. `control release <card id>`
  releases such a card that started held.
- `land-branch <branch>` lands a branch's tip as one card, reviewed and tested as any card. A branch named as a card
  id (`c<time>-<project>-<issue>`) lands as that issue. Other branches land as issue 0, also when the name has a
  number in it. A blocked card of issue 0 is closed with `shut <card id>`. Its kept patch stays, and its branch is
  not changed. When the branch's change is already on main, Needs you says so.
- `control [<action>]` changes the control record. `control depends` writes an issue's `Depends on:` line on GitHub.
  `control card <issue> ...` sets an issue's own builder, reviewer and judge, and `control card <issue> pick` asks the
  judge to choose them ([Configuration](configuration.md#settings-for-one-card)).

Tests:

- `full-test` runs the pack's `test.full` on main. `full-test push` runs it and pushes what landed when it is green.
  `full-test anyway <run id> [--by <who>]` pushes over a red run.
- `push-now` pushes what landed through the project's pre-push hook only, as Conveyor pushes each card when the rule
  is On, with no `test.full` run. It refuses when nothing waits for a push or a full test run is under way. Use it for
  a small change. Use `full-test push` when the whole suite must pass first.
- `pr merge` merges the open pull request of Land as `pr` now, with a merge commit, whatever the rule Merge PR says
  ([Merge PR](configuration.md#merge-pr)). It fails with GitHub's reason when GitHub refuses the merge.
- `lint` runs the pack's lint commands ([Lint](configuration.md#lint)) on the worktree it is called in. It reads the
  worktree as `git add -A` would stage it, so it sees an edit that is not staged and a file that is not tracked. It
  does not stage them and does not change the worktree or its index. It does add the content of the changed files to
  the repository's objects, as `git add` does. The change is from the commit the worktree is on. It prints each command's
  result: `pass`, `findings: <n>`, `skipped: missing <tool>`, `execution error: <why>` or `no files`. A command that
  has files to check, but whose trigger file main added after the commit of the worktree and the worktree does not
  have, is `skipped: missing <file>` with the rest of the reason that [Lint](configuration.md#lint) gives. Then it
  lists the findings on the lines that the change added or changed, and every finding of a command with
  `ratchet: false`. These make it exit 1. A finding with a `complexity` code on such a line is listed under "the gate decides these" and does
  not change the exit code. Findings on other lines are only counted. It exits 2 when a command ends in an execution
  error and no finding made it exit 1.
- `precheck [<issue> <reply file>]` runs, in the worktree it is called in, what the engine checks after a build or fix
  session: the pack's `test.checkCommand`, the commit trailers that the pack's `commit.trailers` requires of the
  files the change adds, and, with an issue number and a file that holds the reply so far, the form of the reply's
  `## Done when` section. It prints each failure and exits 1; with none it prints `precheck: passed`. It exits 2
  when a check cannot run. A session runs it before it ends, so a failure is mended in that session.
- `size --list` prints the files that have more lines than the limit of a size entry in the pack's lint commands
  ([The size entry](configuration.md#the-size-entry)). It prints one path a line, from the top of the worktree it is
  called in. It reads that worktree as `conveyor.sh lint` does, so it sees an edit that is not staged and a file that
  is not tracked. It does not read the exempt file, so it also prints the files that the exempt file names. To make
  the exempt file, send its output to that file. It changes nothing.
- `main-test` runs the whole test on main when one is due (the pack's `test.main`).
- `survey` files the monthly test-speed survey's issue when one is due (the pack's `test.survey`).
- `flaky add <case> <source> <note>` adds a flaky-test entry. `flaky off` adds one and files no issue.
- `testaction <judge | explain> <test file>` asks the Tests seat (the model set for test actions) about one test
  file in a read-only session. `testaction run <test file>` runs that test file alone, now, on a test slot.
  At most 3 run at once; the others wait as queued. `testaction stop <id>` stops one, or takes a queued one off
  (`conveyor/README.md`, Test actions).
- `testissue <test file> <title> <body>` files the Board's issue about one test file.
- `card [--release <version>] <title> <body>` is the Foreman's order (`foreman.sh ask <project> card ...`). With the
  rule **Foreman orders** On (**Release fix cards**, with `--release`), it starts a held card with no GitHub issue.
  Otherwise it files an issue and holds it.
- `cardissue <card id>` is the Board's File on GitHub on a landed card with no GitHub issue. It files an issue with
  the card's title and text, closes it with a comment that names the commit, and prints its address.
- `testmap` prints the state of the test map. `testmap build` makes the map now, on a test slot, and `testmap stop`
  stops that build ([The test map](configuration.md#the-test-map)).
- `mutate <test file>` runs a mutation check of one test file now: it changes a line of the code the file tests, up
  to 20 times, and records which changes the file caught. `serve` runs these checks by itself when no card is in
  its build or test step and no test of another project runs on the machine (`conveyor/README.md`, Mutation checks).
  `mutate ask <test file>...` puts files at the front of that queue and starts no check (the Board's Mutation check).
- `test-settings` saves a test setting in the pack: a "slow on purpose" mark,
  whether slow files file issues, the time the test history starts at (saved in the control record), and the test command that records a Wall only file's CPU time (`conveyor/README.md`, The test files in the snapshot).
- `prices` changes the model prices in the pack ([Configuration](configuration.md#the-pack)):
  - `prices set <model> <input> <output> <cache read> [<cache write>]` saves your price of one model, and
    `prices clear <model>` removes it.
  - `prices add <model> <claude|openai|opencode|other> <name> <input> <output> <cache read> [<cache write>]` adds a
    model that the Board does not know, and `prices remove <model>` removes it.
  - `prices name <model> [<name>]` sets or removes the model's display name.
  - `prices alias <model> add|remove <id>` adds or removes another model ID for the model.
- `testrules` sets the test rules that file issues about test files (`conveyor/README.md`, Test rules).

Declined findings:

- `declined add <card> <issue> <code | judge | owner> <why> <finding> [<kind>]` adds a line. `<kind>` is one of
  `claim wrong`, `cannot happen`, `fixed`, `rare case`, `not this change` or `other`. The reviewer is told not to
  raise the finding only when the kind is `claim wrong`, `cannot happen` or `fixed`. Added again for the same card and
  finding with another kind, the line takes the new kind and reason.
- `declined build <id>` files one as an issue.
- `declined dismiss [--by <who>] <id>...` hides lines from the Board's panel. The reviewer is still told not to raise
  them when their kind allows that.

The self-heals list and the docs list ([Harm or self-heals](cards.md#harm-or-self-heals)):

- `heals batch <area | ->` files one card with the area's open entries of the self-heals list as its scope. `-` takes
  the entries with no area. An entry whose card has not landed or closed waits. With no entry ready in the area, it
  files nothing and exits 2.
- `heals docs <area | ->` files one docs sweep card with the area's open entries of the docs list, in the same way.
  `release-prep` files one for each area that has entries, before it runs the suite.
- `heals harm <id>...` moves entries of the self-heals list up to harm: each gets its own follow-up card at once and
  leaves the list. Use it when a finding shows up in real logs or records. A card whose finding names a pipeline
  file is held until you release it.
- `heals drop <id>...` takes entries off the self-heals list now. Each is kept with the dropped entries, and comes
  back when a review finds it again.
- `heals sort` sorts the queued follow-up cards and the open finding issues: `harm` stays, `docs drift` goes to the
  docs list, and `self-heals`, `cleanup` and `already guarded` go to the self-heals list.

Lanes and the Foreman:

- `lane fast create | review | land | reset [--drop <sha>]` and `lane research create` ([Lanes](lanes.md)).
- `foreman [--new] [<claude argument>...]` starts the Foreman's Claude Code session in the main checkout. It resumes the
  last one unless you give `--new`.
- `foreman status [<project>]` prints the state of the Foreman's projects as short text ([Foreman](foreman.md)).
- `auto on | narrow | off | status | band | rules` is the Foreman's auto mode ([Foreman](foreman.md)): `on` and
  `narrow` start it, `off` ends it, `status` prints one line about it, `band` prints its state for the plugin's band,
  and `rules` prints what the Foreman is told while it is on. `conveyor.sh auto decide` is its decide step. `auto
  standing` prints the standing kinds of yes that are on, `auto standing <kind> on|off` turns one on or off, and `auto act
  <kind> <what>` logs a step taken under a kind that is on ([Foreman](foreman.md#standing-yes)).

Setup and the engine:

- `setup [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] [--test-patterns yes|no] [--file-command yes|no]
  [--test-map yes|no] --fast-lane yes|no --research-lane yes|no [--pin] [--foreman]` and `doctor` ([Setup](setup.md)). Yes to a lane makes that lane
  ([Lanes](lanes.md)). `--link yes|no` answers if each card's worktree links the dependency folders that setup found,
  and `--worktree-setup <command>` installs them in each card's worktree instead.
  `doctor` also tries each of the pack's lint commands once in the main checkout: a command with `{files}` on one
  tracked file that its `files` match, a command without it as it is. It prints one line for each command: `ok`,
  `findings: <n>`, `missing: <tool>`, `error: <first line>`, or `empty` when no tracked file matches (the command is
  not called) ([Lint](configuration.md#lint)).
- `setup pack-commit` shows the pack's change that is not committed. `setup pack-commit yes` commits only the pack on
  the default branch, and `setup pack-commit no` commits nothing ([Setup](setup.md)). When the rule "Push when a card
  lands" is on, `yes` also pushes the commit. If that push does not end in 30 seconds, it is stopped. The commit
  stays, and main's next push takes it.
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
- `pick replay judge <model> [<effort>] [--last <n>] [--estimate]` gives the findings that the project's judge ruled
  on to another judge, and compares the rulings ([Judge replay](configuration.md#judge-replay)). `--estimate` prints
  the estimated cost, and calls no model.
- `pick models <builder|reviewer|judge> <model>[=<min>-<max>]...` sets the pick list of a seat for the rule Pick
  settings, in `pick.<seat>` of the pack: the models that the judge can give the seat, each with its effort range.
  Leave `<min>` or `<max>` empty for no limit on that side. `pick models <seat> clear` removes the list
  ([Pick settings](configuration.md#the-judges-choice-of-seats)).

GitHub and releases:

- `gh-write <gh arguments>` runs a `gh` write through the privacy check.
- `release-prep <version> [--parallel | --serial]` prepares a release ([Releases](releases.md)). `--parallel` runs
  the suite's test files several at once. With neither flag the run uses `control suite-mode`, which is `serial` unless
  set. `release-run [prep] <version>` takes the same choice at the end.
- `release <version>` makes the release: the tag, the pinned marketplace entry and the GitHub release
  ([Releases](releases.md)). Only the owner decides a release: the Foreman runs it only after the owner says yes in
  chat. `release <version> --anyway --by <who>` releases over the failed suite of `release-prep` on the same commit
  ([A release over a failed suite](releases.md#a-release-over-a-failed-suite)).
  `release <version> --allow-commit <sha> [--allow-commit <sha>...] --by <who>` lets the privacy check pass over the
  named commits that are already on `main` on GitHub
  ([Pushed commits the privacy check finds](releases.md#pushed-commits-the-privacy-check-finds)).
- `release-run <version>` is the Board's **Release**: `release` alone when the suite of that version passed on the
  head of `main` and `main` did not move after it, else `release-prep`, then `release` when the suite passes.
  `release-run prep <version>` is its **Draft notes** and **Run suite**: `release-prep` alone, which releases nothing.
  `release-run anyway <version> --by <who>` is its **Release anyway**: `release --anyway` alone.
  `release-run stop` stops that run ([Releases](releases.md#a-release-from-the-board)). `release-run stop <version>`
  stops the run only when the run is of that version.
  `release-run stop <since>` is the **Stop** of a run that waits for its notes card. It ends only the wait of the run
  that started at `<since>`. If that run has started again, it stops nothing.
  `release-run atonce` prints the most test files a parallel suite runs at once on the machine it runs on.
  `release-run atonce --machine local` prints that number for a run on this machine.
  Add `--machine local` at the end to run that one suite on this machine, whatever `control suite-machine` chose.
- `control suite-mode serial` or `control suite-mode parallel` sets how the release suite runs its test files when a
  run names no mode. The default is `serial`. A `--serial` or `--parallel` flag on one run wins for that run.
- `control suite-machine local` runs the release suite on this machine, the default.
  `control suite-machine ssh <user@host> [--dir <folder>]` runs it on a Linux box over ssh.
  `control suite-machine devbox [--size <size>]` runs it on a Namespace Devbox that each run leases and gives back
  ([Where the suite runs](releases.md#where-the-suite-runs)).
- `suite-machine check [--json]` prints, for the machine the release suite runs on, each need as `ok` or `missing`:
  ssh reach, bash 5.1 or later, jq, git, each tool that `.conveyor/test-machine.sh` names, and its CPU count and test
  slots. For a devbox it prints the Namespace login.
