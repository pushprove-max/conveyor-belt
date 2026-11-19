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
   it reads no commit or issue. The command prints the path of the draft, and says if the draft breaks
   a rule of the style. The head of `main` on GitHub has no notes yet, so it stops there.
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

   You choose for each run how the suite runs its test files: `conveyor.sh release-prep <version> --serial` runs them
   one at a time, and `--parallel` runs several at once on the machine's test slots. With neither, the run is serial.
   `conveyor.sh release-run [prep] <version>` takes the same choice at the end, for the `release-prep` it starts.
   Conveyor tells the suite command the choice, and the run's record keeps it as `mode` (`parallel` or `serial`). A run that runs only some files again uses the same choice. In parallel, a file holds one
   test slot while it runs, but an engine area file or the install check holds none, because each of its cases takes a slot. The suite never
   runs more files at once than the pool has slots (`testSlots` in the host file). The output shows each file's
   lines together, with its `-- ok` or `-- FAIL` line, when the file ends.

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
     is a pass (step 4), the suite does not run again. Otherwise the command runs it, and before it the check of the
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
- Changes that only touch tests, refactors or tools are not in the notes, or are in one plain line when a user sees
  no change.

`conveyor.sh release` and `conveyor.sh release-prep` check the notes for a `###` heading, an issue number, a commit
hash, a path or file name, and "Closes". When they find one, they stop and give the line and the rule.
