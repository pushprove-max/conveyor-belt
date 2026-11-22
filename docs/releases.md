# Releases

Each release has a version `X.Y.Z` and a tag `vX.Y.Z`.

- A release that only fixes things raises the last number (1.0.0 to 1.0.1).
- A release that adds a feature raises the middle number (1.0.1 to 1.1.0).
- A release with a change that breaks an existing project's settings (`.conveyor/project.json`) or setup raises the
  first number (1.1.0 to 2.0.0).

[Setup](setup.md#following-releases-or-main-or-pinning-a-commit) says how a project follows releases.

## Making a release

Only the repository owner decides a release. The Foreman runs `conveyor.sh release` only after the owner says yes
in chat. The project runs no GitHub Actions: every step runs on the build machine.

1. Read the Claude pricing page and the OpenAI pricing page again. Update the Board's built-in model prices (`PRICES`
   and `LONG_PRICES` in `.claude/scripts/dashboard_limit.py`) to match them, with the date you read them in the
   comment above the table. Commit the change on `main`.
2. On the build machine, run `conveyor.sh release-prep <version>`. A model writes a draft of the release notes in
   the [release notes style](#release-notes). It reads the issues that landed since the last tag, their
   titles and text, and the commit subjects. When the project has no release tag yet, the draft lists no changes:
   it is an overview of what the project does, in sections by area, from the README and the pages in `docs/`, and
   it reads no commit or issue. Each line of a draft after the first release must name the issues or commits it
   comes from. Then the model reads each line beside the text of those issues and commits. Conveyor leaves out a
   line that names no issue or commit since the last tag, and a line that its issues and commits do not support.
   The command lists the lines it left out. The issues and commits of each line it keeps go in
   `<version>.sources.json` beside the draft, not in the notes. Conveyor checks the draft against the style. When
   the check refuses some lines, the model rewrites those lines one time, and Conveyor checks the rewrite against
   its issues and commits in the same way. The command prints the path of the draft. If the draft still breaks a rule
   of the style, the command says so, and a note at the top of the draft lists the lines the check refuses, with
   their line numbers in the draft as saved. Delete that note when you fix the lines. The head of `main` on GitHub has no notes yet, so it stops there.
3. Read the draft and change what you need. Commit it as `docs/releases/<version>.md` on `main`, and push it.
4. You can run `conveyor.sh release-prep <version>` again. It runs the whole test suite (`test.full` in the pack, the
   project's settings, `.conveyor/project.json`) on the head of `main` on GitHub, and posts the result on that commit
   as the commit status `conveyor/release-suite`. It does not run the suite when the notes break the style. Push
   nothing to `main` after this step and before the next.

   Before the suite, when the project is a Claude Code plugin and the commits since the last tag change `hooks/`,
   `types/` or `.claude-plugin/plugin.json`, this step checks the plugin on the oldest Claude Code version that
   `plugin.json` supports (`engines.claude-code`, such as `>=2.1.322`). It installs that version with npm in the
   cards folder, apart from your own `claude`, which it does not change. Then it runs `claude plugin validate` with
   it on the plugin files of the commit. When the check fails, the step stops with the validate output, and it does
   not run the suite or post a status. When the commits do not change these files, the step does not do the check,
   and its output and the run's record say why.

   In this repository the suite is `.conveyor/test-full.sh`. It runs each area file under `conveyor/tests/`, and
   not the whole engine test, so each engine case runs once.

   The suite runs on this machine, or on a Linux box over ssh
   ([Where the suite runs](#where-the-suite-runs)).

   You choose for each run how the suite runs its test files: `conveyor.sh release-prep <version> --serial` runs them
   one at a time, and `--parallel` runs several at once on the machine's test slots. With neither, the run is serial.
   `conveyor.sh release-run [prep] <version>` takes the same choice at the end, for the `release-prep` it starts.
   Conveyor tells the suite command the choice, and the run's record keeps it as `mode` (`parallel` or `serial`). A run that runs only some files again uses the same choice. In parallel, a file holds one
   test slot while it runs, but an engine area file or the install check holds none, because each of its cases takes a slot. The suite never
   runs more files at once than the pool has slots (`testSlots` in the host file), or more than the **Test files at
   once** setting. The default is 2. Set it on the Board's Rules tab (Capacity), or with `conveyor.sh control atonce <n>`,
   a whole number from 1 to 999. A number above the pool's slots runs at the slots, and the Rules tab says so. On a
   box over ssh, the limit is the box's test slots, which can be fewer than its CPUs
   ([Where the suite runs](#where-the-suite-runs)); the Rules tab shows this machine's slots, not the box's. The
   next parallel run reads the setting. The run's record keeps the number it used as `atOnce`, beside `mode`, and
   `conveyor.sh release-run atonce` prints it. The output shows each file's
   lines together, with its `-- ok` or `-- FAIL` line, when the file ends. In parallel, the suite starts the longest
   files first. It takes each file's time from the newest suite run in `suiteruns.jsonl` (in the state
   folder), so the order costs no test run. Files that this run did not time, such as new files, start before the timed
   files. Files
   with the same time, or with no time, keep the suite's order. A run that runs only some files again orders them the
   same way. In serial, the files run in the suite's order.

   Each test file writes its temp files in a folder of its own. The suite removes the folder when the file ends,
   also when the run stops at its time limit. A card's test step runs its test files in the same way. All the files
   share the space of that folder's file system (`TMPDIR`, else `/tmp`) with each other and with Conveyor. That space
   is the free space of the file system, or what is left of your user's quota on it when that is less. Each file
   gets a share of that space: the host file's `testTmpMB`, in MB ([Setup](setup.md#the-host-file)), or 2048 when
   the host file does not set it. A file that fills its temp folder to its share stops and fails, and its output
   gives the share and the space. No single file that a test file writes, in any folder, can be larger than the
   share. The other files run on. Before a file starts, that space must hold a share for each file that runs, one
   for the new file and one for Conveyor. When files run at the same time, the file waits until a file that runs
   ends. When no file runs and the space is still too small, the file fails and does not run, and its output gives
   the space that is free and the space that it needs.

   The suite also checks the files that the plugin ships. It makes the list of these files and copies them into an
   empty folder. It fails when the copy does not have a file of the list, or has a file that is not on the list, and
   the output names the file. Then, from the copy, with a new home folder
   and no access to the checkout, it runs `conveyor.sh state-dir`, loads the Board server without starting it, and
   runs the shell write hook in a project with a rule and in a project with no rule. It does not run test files from
   the copy.

   An earlier suite run is a release's, or one of the Board's **Run full test suite** or **Push landed**. When one of
   them passed every file on the head of `main`, this step runs no test and posts the pass. When one was on a commit
   that is an ancestor of the head of `main`, this step runs again only some test files, and keeps the passes of the
   other files from that run:
   - the files that failed in that run,
   - the files that the commits since that run add or change,
   - the files that the changed-tests command (`test.command` in the pack, as a card's Test step runs it) picks for
     those changes.

   It runs the whole suite when there is no earlier run, when the commit of that run is not an ancestor of the head,
   or when the commits since change the `test` settings of the pack or a file that its suite commands name (such as
   `.conveyor/test-full.sh` or the engine's test runner). When the files pass, the status is a pass, and its text
   says how many files ran and how many passes it kept, and from which commit. The Release panel says the same
   in its step 2.

   When the suite fails, this step runs each failed case alone three times on the same commit, as **Run full test
   suite** does. A case that passes each time alone is flaky. It goes on the flaky-test record with the source
   "release <version> <commit>", and it does not stop the release. When the flaky-test record has this case from
   enough runs, Conveyor files an issue to make it stable, as it does after a full test run. When each failed case is
   flaky, the suite passes. The status then names the flaky cases, and the Release panel lists them in its step 2. A
   case that fails alone too stops the release, and the output gives the result of each of its runs alone.
5. Ask the owner for a yes in chat. After the yes, run `conveyor.sh release <version>` in the main checkout, on `main`.
   It stops, and changes nothing, when one of these is true:
   - the version is not higher than the newest tag, or its tag exists,
   - the checkout is not at the head of `main` on GitHub, or it has changes that are not committed,
   - there is no notes file, or the notes break a rule of the style that the style check reads,
   - the privacy check finds something in the tracked files or in a commit since the last tag (for a commit that is
     already on GitHub, see [Pushed commits the privacy check finds](#pushed-commits-the-privacy-check-finds)),
   - the whole test suite does not pass on the commit. When the newest `conveyor/release-suite` status on the commit
     is a pass (step 4), the suite does not run again. Otherwise the command runs it as step 4 does, with the passes
     of an earlier run on an ancestor kept for the files that do not run again. Before the suite, it runs the check of the
     mod on the oldest Claude Code version (step 4). When that check fails, the command stops with the validate
     output and does not run the suite. To release over a failed suite,
     see [A release over a failed suite](#a-release-over-a-failed-suite).

   The output gives the reason.
6. When all checks pass, the command sets the version in `plugin.json` and the tag in the marketplace entry, and
   makes the annotated tag. Then it pins the marketplace entry to the commit of that tag, pushes `main` and the tag,
   and makes the GitHub release with the notes as its text (`gh release create`).

With Land as `pr` and the rule Merge PR set to `release` ([Merge PR](configuration.md#merge-pr)), the cards wait in
the pull request from `conveyor/landing`. Step 4 then runs the suite on the head of `conveyor/landing`. In step 5,
the checkout must be at the head of `conveyor/landing`, and the checks read that commit. When a check stops the
release, the pull request stays open. When all checks pass, step 5 merges the pull request and moves your local `main`
to the merged `main` on GitHub. Step 6 then works on top of the merge: the release commit follows it, and the tag is on
that commit. When `main` on GitHub has a commit that
`conveyor/landing` does not have, the release stops before the merge. When GitHub refuses the merge, the release
stops with GitHub's reason, and the pull request stays open.

## Where the suite runs

The release suite runs on this machine unless you choose a Linux box over ssh or a Namespace Devbox. Card test steps
always run on this machine. Only the release suite moves.

- `conveyor.sh control suite-machine local` runs the suite on this machine. This is the default.
- `conveyor.sh control suite-machine ssh <user@host> [--dir <folder>]` runs it on that box. The folder is
  `~/conveyor-suite` unless you give one. It can be `~`, a folder under `~/`, or a full path.
- `conveyor.sh control suite-machine devbox [--size <size>]` runs it on a Namespace Devbox that Conveyor leases for
  each run. The size is `4x8` unless you give one. Conveyor leases the devbox under the tag
  `conveyor-suite-<project>`, with the `devbox` command, which must be installed on this machine and logged in to
  Namespace. The devbox stops by itself after 15 minutes without use.
- `conveyor.sh control suite-machine devbox --box <name>` runs it on a devbox you already have, such as one you made
  by hand. Use this when your account is at its devbox limit, because Conveyor can find a box only by its tag and a
  box with no tag counts against the limit. Conveyor starts that box and runs on it. It does not lease a box and does
  not give the box back. The box stops by itself when it is idle, by its own setting. `devbox list` shows the names.
  The commit status says "Namespace Devbox" and does not name the box.

The box needs bash 5.1 or later, jq and git. Conveyor connects with ssh and does not ask for a password, so set up an ssh
key for the box first. The box needs no access to the repository and gets no GitHub token. Conveyor sends it the
commit under test as a git bundle, and runs the pack's `worktree.setup` there after the checkout. When the commit
has `.conveyor/test-machine.sh`, Conveyor runs that script on the box first, and runs it again only after the script
changes. Use it to install what the tests need. A `# needs: <tool> [<version>]` line in it names each tool the suite needs, for the check below. The tool is the
command the suite runs; the check does not read the version.

A devbox needs the same bash, jq and git, and gets the commit and `.conveyor/test-machine.sh` as a box over ssh does.
The devbox keeps the time that script last ran. Each run copies that time into the devbox rule, also when the script did not run again, and the Board shows it on the Box line. Saving the rule again with the same size keeps the time; a new size has none until a run.
Conveyor starts the run on it with `devbox exec -d`, copies the output back as it does from a box, and gives the lease
back with `devbox release` when the run ends. It also gives the lease back when a step fails and when you run
`release-run stop`.

`conveyor.sh suite-machine check` prints one line for each need of the chosen machine, `ok` or `missing`: ssh reach,
bash 5.1 or later, jq, git, each tool that `.conveyor/test-machine.sh` names, and the CPU count and test slots.
For a devbox it prints two lines: the Namespace login, and the box the run will use. With `--box`, the line says whether
the account has that box. With no box named, Conveyor leases a box under the tag and gives it back at once, to learn
whether the account can give one. The line says whether the run reuses the box with the tag, or a new box was created
for it. When the account is at its devbox limit and no box is found, the line is `missing` and says to pick an existing
box with `--box <name>`, or remove one. With `--no-create`, the check does not ask for a box, so it creates none; the
Board runs a member's check that way. A devbox's bash, tools and test slots can be read only during a run.
`--json` prints the same as JSON. The command exits 1 when a need is missing.

A run on the box takes no test slot on this machine. In parallel mode it runs at most the box's test slots at once.
The box counts its test slots as this machine does: `testSlots` in the box's own
[host file](configuration.md#the-host-file), and never more than its cores. A run on the box has the same time limit
as a run here (`testTimeout`), timed by the box's clock. A run that ends after the limit fails as timed out, also
when its tests pass. When a run is still going after the limit, Conveyor stops it on the box.
The suite's output comes back to this machine at least every 10 seconds, so the Board shows its progress as it does
for a run here. The run's record keeps the machine as `machine`: its kind, its name, the step under way,
the seconds of each step, the devbox lease, and the reason when a step failed. The commit status names the machine.
For a box it says "a Linux box over ssh" and not the host name, because the status is public. For a devbox it says
"Namespace Devbox <size>". When the suite uses an earlier pass of the same commit and runs no test, the status names
no machine.

When the box cannot be reached, or its setup or checkout fails, the run ends as `not started` with the reason. When
the devbox cannot be leased, the reason is "Not logged in to Namespace" for a missing login. No
test runs, no status is posted, and the suite never moves to another machine by itself. `release-run stop` also
stops the suite on the box or the devbox. `release-run atonce` does not print a number for a devbox, because Conveyor
reads its test slots when a run leases it. To run one suite on this machine without a change to the rule, add `--machine local`:
`conveyor.sh release-run [prep] <version> [--parallel | --serial] --machine local`. That run does not use a pass
from a box, so the suite runs on this machine.

## Cards during a release

From the start of `release-prep` to the end of `release`, no card lands on `main`, and Conveyor holds the pushes of
cards. In that time, only the release itself changes `main` on GitHub. Step 6 pushes the two release commits (the
version and the marketplace pin) and the tag. With Merge PR `release`, step 5 also merges the pull request.
When `conveyor.sh release-run` runs the two commands, this is also true between them. Thus `main` does not move
while the suite runs, and the release does not stop because `main` moved. Cards continue to build, get reviews and run
their tests. A card that gets to its land step waits there, and the Board shows it as "waiting for the release". A
branch that you land with `conveyor.sh land-branch` waits in the same way. Merge PR `idle` does not merge the pull
request. On the Board, **Push now** and **Push anyway** push nothing and say that a release run is under way.
When **Push landed** finds the commit green, Conveyor does not push it, and the result gives the same reason. A run that starts while a card lands or a push runs waits until that card or push is done.

When the run ends, the waiting cards land in their usual order. This is true when the release goes out, and also when
the run fails, when a check stops it, and when you stop it (`conveyor.sh release-run stop`, or **Stop** on the Board).
When `release-prep` asks for the release notes, the run ends. Thus the commit of the notes in step 3 does not wait.

## Fix cards of a failed suite

When the suite of step 4 fails, file one fix card for each failure. Put the line `Release fix: <version>` in the body
of each fix card. The Foreman does this for you when the `release-check` kind of standing yes is on.

`conveyor.sh serve` reads these cards again after each wait of the `tunables.idle` setting in the pack. It reads only
the issues filed after the failed suite ended. The record of the run (`release/run.json` in the cards folder) lists
them under `fixes`, each with its state: `open`, `landed`, or `closed` (closed with no landed card). When each fix
card has landed, its commit is in the commit that step 4 tests, and no card is on the belt, Conveyor runs
`conveyor.sh release-run prep <version>` itself, one time. With Land as `pr` and the rule Merge PR set to `button` or
`idle`, step 4 tests `main` on GitHub, so this waits until the pull request is merged. The record of the new run says `by: "fixes landed"`. The run uses the passes of the earlier suite, as step 4 does. A
fix card that was closed with no landed card stops this. Then run step 4 again yourself.

## A release over a failed suite

Use this only when the owner says so, and only when the failures are not in the code that you release. An example is
a test that fails only when the machine is busy and passes when it runs alone. Fix the test in a later release.

Run `conveyor.sh release <version> --anyway --by <who>`, with the name of the person who decided. It releases the head
of `main` only when step 4 ran the suite on that same commit and the suite failed. It stops, and changes nothing, when
the suite did not run on the head of `main`, or when `main` moved after the suite ran. Then run step 4 again. All the
other checks of step 5 apply.

Before it releases, the command prints the failed files and cases. It does not run the suite again, and it posts no
status: the `conveyor/release-suite` status of the commit stays failure. The GitHub release has the notes, then a
section "Known test failures". This section says "released over a failed suite by <who>" and lists the failed files
and cases. The record of the release (`release/run.json` in the cards folder) keeps the same names. The privacy
check reads `<who>` and these names before anything is tagged. If it finds something, the command stops and releases
nothing.

On the Board, the Release panel shows **Release anyway** beside a failed suite on the head of `main`. The first click
shows the failed files and cases. The second click runs `conveyor.sh release-run anyway <version>`, with you, the Board
user, as `<who>`.

## Pushed commits the privacy check finds

The privacy check reads the message and the added lines of each commit since the last tag. A commit that is already
on `main` on GitHub stays in its history. Only a history rewrite and a force push can remove it. When the owner
decides to keep that history, run:

`conveyor.sh release <version> --allow-commit <sha> [--allow-commit <sha>...] --by <who>`

Name each commit that the refusal lists, and the person who decided as `<who>`. The privacy check then passes over
the named commits. It passes over a named commit only when that commit is on `main` on GitHub. If a named commit is
not there, the command stops and releases nothing. A finding in a commit that you do not name still stops the
release, and the check of the tracked files does not change. Before it releases, the command prints the commits it
passed over. The record of the release (`release/run.json` in the cards folder) keeps these commits and `<who>`. You
can use `--allow-commit` together with `--anyway`, with one `--by`.

## A release from the Board

The Release panel on the Board's Overview tab does steps 4 to 6 ([The Board](board.md#release)). Type the version and
click a button two times. The card has two buttons. The first writes the notes draft or runs the suite: **Draft notes**, **Run suite**, **Run
suite again** or **Run again on the new main**. The second is **Release** with the version. It is disabled, and says
what it waits for, until `main` has the notes and the suite passed on the head of `main`. The first button runs
`conveyor.sh release-run prep <version>`: `release-prep` alone, which releases nothing. For **Release**, the second click is the owner's yes. Conveyor
runs `conveyor.sh release-run <version>`: `release` alone when the suite of that version passed on the head of `main`
and `main` did not move after it, else `release-prep`, then `release` when the suite passes. The output of the two
is in `release/run.log` in the cards folder. When a step stops, the panel shows each reason, and nothing more runs. `/units` shows the run while it is in
progress ([/units](units.md)). `conveyor.sh release-run stop` is the panel's **Stop**.

## Release notes

The release notes are for the people who use Conveyor. Each release has its notes in `docs/releases/<version>.md`,
and the GitHub release shows them.

- The first line is the heading `# <version>`. The next line says in one sentence what the release is about.
- `##` sections have the name of what a user does or sees, for example Cards, The Board, In Claude Code or Setup.
  There are no `###` headings.
- Each bullet tells one change in plain English: what the user sees or can do now.
- The notes name no file, script or function, no path, no issue or pull request number, no commit hash and no
  internal part of the engine, and have no "Closes" line. They can name what a person types or sees: a slash command,
  a setup question, a setting or a button.
- The notes name no command file, and `conveyor.sh` is one. Name a command by what the user types in Claude Code or
  clicks on the Board, for example "Conveyor's doctor check".
- Changes that only touch tests, refactors or tools are not in the notes, or are in one plain line when a user sees
  no change.

`conveyor.sh release` and `conveyor.sh release-prep` check the notes for a `###` heading, an issue number, a commit
hash, a path or file name, and "Closes". When they find one, they stop and give the line and the rule.
