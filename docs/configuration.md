# Configuration

Conveyor reads three sets of settings: the pack (the project's settings), the host file (this machine's settings) and
the control record (what the loop does now).

## The pack

The pack is `.conveyor/project.json` in the project. You commit it. It says how Conveyor works in that project:
the owner, the product paths, the test commands, the labels, the models, the branch (`defaultBranch`), the privacy
mode and the engine the project runs (`plugin`, [Setup](setup.md#following-releases-or-main-or-pinning-a-commit)).
`conveyor/schema/pack.schema.json` describes every field. When `.conveyor/card-rules.md` is present, every card also
reads the project's own rules from it.

Some pack settings that this site names:

- `review.proof`: the proof a review finding needs. `any`, the default, takes any proof that can be reproduced. `real`
  asks for a proof with what the project really runs ([How a card goes](cards.md#review-and-the-judge)).
- `review.wording`: a file with the wording of `/conveyor-belt:review` in place of `conveyor/rules/review.md`.
- `review.screenshots`: the folder where your project's own run writes screenshots. The Board shows them beside the
  approval of a visible change ([Board](board.md#needs-you)). Conveyor does not take screenshots.
- `pipelineFiles`: the files that change how cards are built, reviewed, fixed, tested, landed or pushed. A follow-up
  that changes one is filed held.
- `auto.reserved`: what `/conveyor-belt:auto` never decides ([Foreman](foreman.md)).
- `auto.standing`: the kinds of routine step that the Foreman takes without asking you. The kinds are `asked-fix` (a
  fix you asked for is filed and queued at once), `review-followup` (a follow-up that only finishes or corrects the
  change of a card you approved is queued), `release-check` (a failed check in a release you asked for gets one fix
  card, then the release goes on), `fixed-block` (a card blocked by a cause that a landed fix removed waits on that
  fix and is tried again) and `review-retry` (a card blocked by its review is tried again, with no wake of the
  Foreman). Setup writes the list empty, so each kind is off until you turn it on in the Rules tab
  ([Foreman](foreman.md#standing-yes)).
- `test.full`: the full test suite, which "Push landed" runs. Setup sets it to your test command. `test.main`: the whole test on main. `test.mainAt`: a time of day, `"HH:MM"` in the machine's local time, after which the whole test on main runs once a day; unset, it runs at most once an hour. `test.survey`: the monthly test-speed survey.
  `test.firstSurvey`: the answer to setup's survey question.
- `test.control`: test files, as paths from the top of your checkout, that tell a broken machine from a broken main.
  When a card's failing cases fail on main too, the ones of these that passed before with main's content run beside
  them. When no test passed before with main's content, as with a test command that records no passes, all of
  these run. When none of them passes, the machine is at fault: no "Main is red" card opens, and the loop picks no
  card until the failing files pass again ([Cards](cards.md#tests)). Empty by default. When it is empty, no control
  runs, and a failure on main is main's unless its test file passed before with the same inputs.
- `linkFromMain`: the folders, as paths from the top of your checkout, that each card's worktree links from your
  checkout, such as `node_modules`. These are the dependencies its build and tests need. Setup fills it from the
  ignored dependency folders it finds, when you answer yes ([Setup](setup.md#setup)).
- `worktree.setup`: a command that each new worktree runs once, from its top, before the build and the tests, for
  example `npm ci`. Use it in place of `linkFromMain` when a card can change a lockfile. When it fails, the card is
  blocked with the end of its output.
- `tunables.pushRetry`: the seconds between two tries of a push that failed for the network or the remote.
- `tunables.sessionTestSlots`: the most test slots that a test run in a card's build, fix or rebase session holds at
  one time. The default is 2. The loop's own test step keeps its full share.
- `push.landAs`: the rule Land as, `main` (the default) or `pr`, until the control record sets it ([Land
  as](#land-as)).
- `push.prMerge`: the rule Merge PR, `button` (the default), `release` or `idle`, until the control record sets it
  ([Merge PR](#merge-pr)).
- `prices`: your model prices, added models and aliases, by model ID. Set them on the Board's Rules tab (Model
  prices, [The Board](board.md#rules)) or with `conveyor.sh prices` ([Commands](commands.md)). Each entry can have:
  - `input`, `output` and `cacheRead`, together, and `cacheWrite`: prices in dollars per million tokens. They win
    over the Board's built-in price of that model. A model with no built-in price is priced at them. With no
    `cacheWrite`, a 5-minute cache write costs 1.25 times `input`. An OpenCode model
    (`opencode:<provider>/<model>`) with prices uses them, not the cost that OpenCode reports.
  - `name`: the display name on the Board. The ID does not change.
  - `provider`: `claude`, `openai`, `opencode` or `other`, the group of an added model on the Board.
  - `aliases`: other model IDs for the same model, for example a proxy's ID. A session with one of these IDs is priced
    as this model and shows its display name.

  For example: `{"claude-sonnet-4-6": {"aliases": ["anthropic/claude-sonnet-4-6"]}, "my-model": {"name": "My model",
  "provider": "other", "input": 1, "output": 2, "cacheRead": 0.1}}`.

## How test files are found

Conveyor must know which files of your project are tests. It uses this to find the tests that a card adds or
changes, to run those tests on main's code for a bug card, and to keep tests out of product code.

The pack's `tests.patterns` is a list of globs that name your test files. Each glob is matched against a path from the
root of the repository:

- `*` and `?` match inside one folder name. `**` matches across folders.
- A glob that ends in `/`, for example `tests/`, matches each file in a folder of that name.
- A glob matches at any depth. A glob that starts with `/`, for example `/t/*.sh`, matches only from the root.

```json
"tests": {"patterns": ["src/test-*.mjs", "tests/"]}
```

When you set `tests.patterns`, it replaces the default. Without it, Conveyor uses a default for the common
conventions: `__tests__/`, `*.test.*`, `*.spec.*`, `test_*.py`, `*_test.py`, `*_test.go`, `tests/`, `test/`, `spec/`,
`*_spec.rb`, `*Test.java`, `*Tests.cs`, `test-*.mjs`, `*.t` and `t/*.sh`.

Your test runner is never a test file, also when a glob matches it. The test runner is a file that `test.command`,
`test.full`, `test.main` or `test.fileCommand` names, or a file that a `package.json` script of those commands names, for example
`scripts/run-tests.mjs` in `"test": "node scripts/run-tests.mjs"`. When a shell script of those commands starts a file
by its path, as in `node scripts/run-tests.mjs`, that file is a runner too. A test file that the script starts from a
list or a variable, as in `bash "$t"`, stays a test file. Each file in `test.wholeCommands` is a runner too. Given no list, the runner runs every test. So a card's
list of tests never holds a runner: when the test map, the links or a list of failed tests names one, the card leaves
it off, and the card's test log names it. A card
that changes the runner runs the test files that name the runner, and the tests that the test map and
`.conveyor/test-links.json` give it. The card's list and the test map show the runner with the reason "the test
runner, not a test".

For a bug card, Conveyor gives the card's test files to your test command (`test.command`) on main's code, without
the fix. If your test command cannot run a test file that it gets alone, set `test.fileCommand` to a command that
runs one test file, for example `"fileCommand": "node --test"`. Conveyor then runs it once for each test file, with
the file's path added at the end.

When a bug card has no file that the patterns match, the card goes back to its build. If it still has none, the card
is blocked with the reason `no test file found in the change (patterns: <list>)`. When your test command does not run
the test files that it gets, the card is blocked, and the reason says so. Correct `tests.patterns` or
`test.fileCommand`, then retry the card.

Some test commands run every test file, whatever files they get. For a bug card, such a command runs the full suite
on main's code, not only the card's test files. When the command runs far more test files than it gets, the check
result that the review sees says so, and `conveyor.sh doctor` shows a `warning:` line. Both tell you to set
`test.fileCommand`. When your test files run alone as plain scripts, for example `node <file>`, they name the value
to use. Setup also suggests that value when the pack has no `test.fileCommand`.

Setup suggests patterns when the default misses your test files ([Setup](setup.md#setup)). `conveyor.sh doctor`
shows a `missing:` line when the patterns match no tracked file, or when they miss test files that your test command
names.

## Tests inside product files

Some tests are in the same file as the code that they test, for example a Rust `#[cfg(test)]` module or a Python
doctest. For a bug card, Conveyor finds new tests of this type in the product files that the card changes. It runs
your test command on main's code with these tests and without the rest of the change. At least one test must fail
there. When you set `test.fileCommand`, Conveyor gives it each such product file.

Conveyor knows these kinds of test:

| Kind | Files | A test block |
|---|---|---|
| `rust` | `*.rs` | `#[cfg(test)]` or `#[test]` and the item after it, up to the bracket that closes the item |
| `python` | `*.py` | a `"""` or `'''` string with a `>>>` line in it |
| `elixir` | `*.ex`, `*.exs` | a `@doc """` or `"""` string with an `iex>` line in it |

To add a kind, add an entry to `tests.inline` in `.conveyor/project.json`. An entry has these fields:

- `files`: the globs of the files, as in `tests.patterns`.
- `start`: a POSIX extended regular expression. A test block starts where it matches.
- `end`: `braces` or a regular expression. With `braces`, the block ends where the brackets that open after `start`
  close. A `;` before the first bracket also ends it. With a regular expression, the block ends where it matches.
- `has`: a regular expression. This field is optional. When you set it, a block is a test only if one of its lines
  matches it.

```json
"tests": {"inline": {"zig": {"files": ["*.zig"], "start": "^[[:space:]]*test[[:space:]]", "end": "braces"}}}
```

Conveyor adds your entries to the kinds in the table. An entry with the name of a kind in the table replaces that
kind. Conveyor also counts the brackets inside strings.

A new test and the fix can be on the same line. Then Conveyor cannot take out the fix alone, and the card goes back
to its build. If they are still on the same line after the build, the card is blocked with the reason
`the new test and the fix are in the same lines of <file>; bugproof cannot take out the fix alone`. Put the test on
lines of its own, then retry the card.

## Which tests a card runs

A card never runs the whole suite. It runs each of its test files alone with the pack's `test.fileCommand`. Conveyor
adds the path of the file at the end of the command. The suite command (`test.full`) runs when you click Push landed or
Run full test suite on the Control tab, and in a release. These do not always run every file. When the suite passed
on the same commit, no test runs. After a suite run on an earlier commit, the files that failed there run again, and
so do the files that the commits since then add or change, and the files that `test.command` picks for those changes.
A change to the `test` settings of the pack, or to a file that its suite commands name (`test.full` and
`test.wholeCommands`, not `test.command` or `test.changed`), runs the whole suite
([releases.md](releases.md)). In this repository the suite is `.conveyor/test-full.sh`. It runs each area file under
`conveyor/tests/`. It does not run the whole engine test, even when `test.command` picks
it, so each engine case runs once. The whole test on main runs `test.main`.

A release's suite run is serial or parallel, as you choose for each run (`--serial` or `--parallel` after
`conveyor.sh release-prep <version>`; [releases.md](releases.md)). Conveyor tells the suite command the choice.
`.conveyor/test-full.sh` runs one file at a time in a serial run. In a parallel run, the script runs several files at once on the machine's test slots, never more
files than the pool has slots (`testSlots` in [the host file](#the-host-file)).

A test file can set its own time limit with a line `# timeout: <seconds>` among the comments at its top. Words after
the number are a note. Past that limit, Conveyor stops the file and every process that it started, and the output says
that the file timed out. A file without that line has the time limit of the card's test run (`testTimeout`).

If the pack has no `test.fileCommand`, Conveyor runs each test file with the runner of its language, from the folder
of the package that holds the file: `node --test`, vitest, jest or `bun test` under a `package.json`, `pytest`, `go
test` for the package of a `_test.go` file, `cargo test` for a `tests/<name>.rs` file, and `rspec`. It also runs
the class of a `src/<set>/java/` (or `kotlin/`, `groovy/`) file with Gradle or Maven, through `gradlew` or `mvnw` when
the project has one. It runs the class named as a `.cs` file with `dotnet test`, and the class named as a
`Tests/<target>/` file with `swift test`. It runs a `*Test.php` file with PHPUnit, a `*_test.exs` file with `mix test`,
and a `*_test.dart` file with `flutter test` or `dart test`. For a `.c`, `.cc`, `.cpp` or `.cxx` file, it runs the
CTest test with the same name as the file, in the `build/` folder of the CMake project. That folder must already
contain the build. If Conveyor has no
runner for a test file of a card, the card stops at its test step, and Needs you shows the reason. A bug card with a test file and a fix stops earlier, at its Build step, because its check cannot run that
file on main's code. A bug card whose change is only test files, or only comments in other `.js`, `.mjs`, `.cjs`,
`.ts`, `.mts` or `.cts` files with or without test files, has no check to run, and with a test file it stops at its
test step. A comment change in any other file, such as a `.sh` or `.py` file, is a fix, and that card stops at Build. The reason names the setting. If the pack has no `test.fileCommand` and Conveyor has no runner for one of the
project's test files, `conveyor.sh doctor` shows a `warning:` line that names that file.

A card runs the test files that its change adds or changes, as `tests.patterns` finds them. A shared helper or a test
runner is not a test file here.

Of a test file that is on main, the card runs only the test cases that the change adds or changes. A case is a
`t_<case>() {` line, the comment lines above it, and the lines to its closing `}`. Conveyor gives these cases to
your command ([conveyor/README.md](../conveyor/README.md)). A command that does not read them runs each file whole. A
file runs whole when the change touches a line outside all cases, such as a helper or setup, when the file is new, or
when no changed case is found in it. The card's test step says "the card ran 3 changed cases of 3 test files", and
the Board shows this note with the step.

If the change adds or changes no test file, the card runs 5 of the test files linked to the changed files:

- the test files that `.conveyor/test-links.json` links to a changed file, if your project has that file
  (`{"<file>": ["<test file>", ...]}`), and the test files that the [test map](#the-test-map) says cover it;
- if neither gives a test, the test files whose name holds the name of that file, from the nearest folders. For
  example, a change to `src/cart/total.js` runs the test file of `total` in `src/cart/`, not one in another folder.

A change to a document (`.md`, `.txt`, `.rst`) adds only the test files that `.conveyor/test-links.json` links to it
or that the test map says cover it. A document is never on the list, even when it is in a test folder. The files that
failed most recently in a test step run first, then the others in the order of the test map. The card's test step
says this, and the Board shows the note with the step. If no test file is linked to the change, the card runs no
test. The card's test line says so.

When a run fails, the card runs again only the files that did not pass. After a fix session that changed the card's
change, every file of its list runs again.

Before each push, Conveyor runs the test files that the test map and `.conveyor/test-links.json` link to the
landings since the last push. Each file runs alone. If a file fails, Conveyor finds the landing that broke it, files
a main-fix card, and holds the push ([Push](cards.md#push)).

`push.check` in `.conveyor/project.json` turns this run on or off. It is on in a new project. Set it to `false`, and
a push runs no test first. `conveyor.sh control push-check on` or `off`, or the Rules tab's **Test before a push**,
sets it in the control record, and that value wins over the pack's.

The check of a bug card on main's code runs at most `test.cardFiles` test files (in `.conveyor/project.json`). If
more are linked, the files that failed most recently in a test step run first.

The run before a push and the test map can run one test file with `test.command` when the pack has no
`test.fileCommand`. The pack's `test.list` tells how `test.command` takes the file:

- `args`: the path is added at the end of the command, for example `npm test` followed by the path. If the command
  already names its test files, for example `node --test checks/*.js`, use `placeholder`.
- `placeholder`: the path goes where `{files}` is in the command, for example `"command": "npx jest {files} --ci"`.

A test file's run can report more test files than it was given. Then Conveyor stops the run at once, with every
process that the run started. The card stops at its test step, and the reason names the file that ran the others.
The check of a bug card on main's code follows the same rule. The full suite of a release has no such limit.

## Split large issues

The rule **Split large issues** on the Rules tab sets what Conveyor does with a large issue before it builds it. It
has three settings: Off, Shadow and On. Shadow is the default. `conveyor.sh control rules split=off`, `split=shadow`
or `split=on` also sets it.

Conveyor checks an issue one time, when it picks the issue and before it makes the card's worktree. It checks the
issue again only after you edit its title or body. It does not check follow-ups, the slices of a split issue, or fix
cards that have no issue.

First, code measures the issue: the items of its Done when section, the file paths and the area labels that it names,
and its length. The limits are `split.doneWhen`, `split.files`, `split.areas` and `split.chars` in
`.conveyor/project.json`. When the issue is under all of them, Conveyor keeps it whole and asks no model.

When the issue reaches one limit, Conveyor asks the judge (Judge on the Rules tab) one time. The judge gets the issue
and the files that it names, as they are on main. It answers keep, or split into 2 or 3 slices:

- Each slice has a title, Done-when items of its own and the Done-when items of the issue that it covers.
- Each Done-when item of the issue is in exactly one slice.
- Each slice is a complete change that works alone, never half a feature.
- A slice that changes the same code as an earlier slice gets a `Depends on:` line for that slice.

When the answer breaks one of these rules, or the call fails, Conveyor keeps the issue whole. The card's `split` line
records the verdict, the slices and the reason.

- **Off**: Conveyor checks no issue.
- **Shadow**: the card's `split` line records the verdict and the slices, and Conveyor builds the issue as one card.
  The card on the Board shows "Would have split into N".
- **On**: Conveyor files each slice as a follow-up of the issue: it has the follow-up label, and its body starts with
  `Follow-up of #N`. The slices of a queued issue go in the queue. The slices of a held issue are held. If the issue
  is in the pick order, its slices take its place in the order. The `split` line records if the slices are held. The
  issue becomes their umbrella: Conveyor holds it and does not build it. The slices become its GitHub sub-issues, and
  Conveyor adds a comment that names the slice for each Done-when item. Held on the Board names its slices. Conveyor
  closes the issue when each of its slices is closed or landed ([Issues](commands.md#issues)). An issue split before its slices
  were sub-issues closes when the last slice lands, or closes because main already does what it asks.

The Health panel shows the cards that Conveyor checked while the rule was Shadow or On: how many it kept and how many
would split, and the first-review GO rate and the fix rounds of each group.

### A change that grows while it is built

A card's change can grow large while it is built and fixed. Before each review, Conveyor counts the files of the
card's change, with documentation (`*.md`) left out. When the count is more than `split.growFiles` in
`.conveyor/project.json`, the next review also asks the judge one time. The judge gets the issue and the change. It
answers keep, or it keeps the core change of the issue on the card and names 1 to 3 slices. Each slice has a title,
Done-when items of its own and the files of the change that it takes. Each file is in the core or in one slice.

- **Off**: Conveyor does not count the files.
- **Shadow**: the card's `grown` line records the answer, and the change stays as it is.
- **On**: Conveyor files each slice as a follow-up of the issue, with `Depends on:` the issue. The slices of a held
  issue are held, and the others go in the queue. Conveyor puts the files of the slices back to what main has, and
  one fix session makes the rest work alone. Then the card goes on to its review. The track on the Board and in
  /units shows that the card was split for its size, with the count of files before and after.

Conveyor does not count the files of a follow-up or of a fix card that has no issue.

## Pick settings

The rule **Pick settings** on the Rules tab records a group and a builder for each card. It has three settings: Off,
Shadow and On. Off is the default. `conveyor.sh control rules pick=off`, `pick=shadow` or `pick=on` also sets it.

Conveyor picks one time for each card, after the split check and before the build. Each slice of a split issue gets
its own pick. Fix cards that have no issue get no pick. Code puts the card in a group, and no model is asked:

- **small**, **medium** or **large**: small when the issue is under all the `split` limits in `.conveyor/project.json`.
  Medium when it is under two times each of these limits. Else large.
- **pipeline**, **docs** or **code**: pipeline when the issue names a path in `pipelineFiles`. Else docs when it has
  the label `documentation`, or when each path that it names is a Markdown file or a file under `docs/`. Else code.

The group is the two words, for example "small docs". The choice is the project's builder (Builder on the Rules tab),
or the challenger on a trial (below).
When you set the builder of a card (`conveyor.sh control card <issue> builder <model>`), the choice is your setting,
and the pick says that you chose it. Each step line of the card from then on, up to its end, has a `pick` field:
`group`, `choice` (model and effort), `by` (`owner` or `auto`), `trial` and `mode`. A card that starts again for the same issue, after a retry
or a stop, keeps the pick that the issue had.

- **Off**: Conveyor records no pick.
- **Shadow**: Conveyor records the pick, and the card builds on its builder as before.
- **On**: Conveyor records the pick. Some cards are trials, and the cards of a group that you promote build on the
  challenger.

### Trials

With the rule On, a trial card builds on the challenger, Sonnet 5.5 at medium effort (`claude-sonnet-5-5`), and its
pick has `trial: true`. All other cards build on the project's builder. Its review and judge use the project's
settings.

- **Eligible cards**: a card is eligible when its group is "small docs" or "small code", or a medium group that you
  added (below). The issue names no path in `pipelineFiles`. The cards of a medium group that you did not add use
  the project's settings. A card whose builder you set is not eligible. When you set the builder of a trial
  card's issue (`control card`) while the card runs, each later step of the card that uses the builder uses yours. The
  other steps keep their own settings.
- **Share**: 1 eligible card in 5 is a trial: the card of an issue whose number is a multiple of 5.
- **One at a time**: when a trial card is in progress, the next eligible card builds on the project's builder.
- **Retry**: when a trial card is blocked, its retry builds on the project's builder. This is true for a retry by
  `review-retry` and for a retry that you start. The rule does not retry a card itself.
- **Drop**: when two trial cards of a group are blocked after your last decision for the group, the group has no
  more trials. The next eligible card of
  that group builds on the project's builder, also when its issue is in the share. The blocked lines of the two cards
  in the card records are the record of the drop.
- **No challenger**: there are no trials when the project's builder is the challenger, or when `models.allowed` in
  `.conveyor/project.json` does not allow the challenger for the builder. There is also no trial when the Claude
  account of the challenger is at the weekly limit guard.

When the change of a trial card touches a path in `pipelineFiles`, the `pick` field also has `pipeline`: those paths.
The issue of a trial card names no such path.

The Cost panel on the Board shows a table of the picked cards, one row for each group and builder. Under the table,
**Pick settings trials** shows each group that has no more trials, with the two blocked cards. It also shows each trial
card whose change touches a path in `pipelineFiles`, with those paths.

### Your decision after ten trial cards

When ten trial cards of a group are done (landed, closed or blocked), **Needs you** on the Board asks you for a
decision about the challenger of that group. The line shows the trial cards and the default cards of the group: how
many there are, how many landed, and the spend for each landed card. The spend of a card includes all its runs, and
its blocked runs too, but not a run on a different challenger. When a step has no price, the spend shows as not known. Conveyor does not promote the challenger
itself. Give your decision with `conveyor.sh control pick <group> <decision>`, for example
`conveyor.sh control pick small docs promote`:

- **promote**: the cards of the group build on the challenger, with no more trials. 1 card in 5 of the group stays
  on the project's builder: the card of an issue whose number is a multiple of 5. A card whose builder you set keeps
  your setting.
- **keep**: the trials continue. Needs you asks again when ten more trial cards of the group are done. Trial cards
  that were blocked before your decision do not count for a drop.
- **drop**: the group has no more trials. Its cards build on the project's builder.

Two more decisions add trials. Conveyor does not make them itself:

- **add**: `conveyor.sh control pick medium <docs|code> add` makes the cards of that medium group eligible for
  trials. You can add a medium group after you gave a decision for the small group of the same kind.
- **next**: `conveyor.sh control pick <group> next`, for a group that you promoted, starts trials of the next
  challenger. The next challenger is Sonnet 5.5 at low effort, then Haiku 5.5 (`claude-haiku-5-5`) at medium effort,
  then Haiku 5.5 at low effort. The promoted cards of the group stay on the promoted challenger. The card of an issue
  whose number is a multiple of 5 is a trial of the next challenger. After ten trial cards, Needs you asks again:
  promote makes the next challenger the promoted one, keep continues the trials, and drop goes back to the challenger
  that you promoted before.

### Reviewer and judge

The reviewer and the judge of a card use the project's settings, until you promote a choice from a replay result
(see Judge replay, below). Give your decision with `conveyor.sh control pick <reviewer|judge> promote <model>
[<effort>]`. Conveyor refuses it when `replays.jsonl` has no result for that seat, model and effort. With the rule
On, each card that is not a trial then uses that choice, and its `pick` field has `seats`. A trial card keeps the
project's reviewer and judge. A reviewer or judge that you set for a card (`control card`) keeps your setting.
`conveyor.sh control pick <reviewer|judge> drop` takes the choice away.

### Back to Shadow

With the rule On, Conveyor compares the promoted cards of a group with its default cards before it starts each card.
It does this also for a group that you promote before it has trial cards.
When the promoted cards cost more for each landed card, Conveyor sets the rule to Shadow. **Needs you** then shows
a line with the two costs. The line stays until you set the rule again. Before you set it to On again, choose
`keep` or `drop` for the group, because the same costs set the rule to Shadow again. Conveyor uses the costs that the Board
showed last. It compares only the promoted cards of the challenger that is promoted now.

When the next challenger has trials, `keep` and `drop` keep the promoted challenger. The line then tells you to
choose `promote`, which builds on the next challenger in its place, or `drop` two times, which stops the trials and
builds on the defaults.

## Judge replay

A judge replay tells you how a different judge would rule on the findings that your judge already ruled on. It runs
only when you start it. Start it from the Cost panel on the Board, or with
`conveyor.sh pick replay judge <model> [<effort>] [--last <n>]`. The model must be one that the pack allows the
judge. With no effort, the effort is medium.

The replay takes the newest review lines, in the card records and the retried lines, where the judge accepted or
declined findings. By default it takes 20. `--last <n>` sets a different number. For each review, the replay judge
gets the same findings, the issue, the change of the card, and the findings that were declined on the cards of the
issue before that judge ran. The change is the commit that landed, or the kept patch of a blocked card, on the commit
that the review ran on. A review is skipped when its card has no landed commit and no kept patch. It is also skipped
when that change does not apply on that commit, or is not the change that the judge read, for example when a fix
round came after the review. For a finding of a kind that the project
always accepts, the replay uses the ruling that the judge itself gave.

The replay changes no card and no setting, and it runs no tests. The result shows:

- How many findings the replay judge ruled on as the recorded judge did.
- Each finding where the two rulings are different, with the reason that the replay judge gave.
- The findings that got no answer, for example when a judge call fails.
- The cost of the replay, and the cost of the recorded judge on the same reviews.

`--estimate` prints the estimated cost and calls no model: the token use of the recorded judge, at the price of the
model that you chose. On the Board, **Estimate the cost** shows this estimate, and **Run the replay** starts the
replay after a second click. Only an admin can start a replay. Only one replay can run at a time.

Each replay writes one line to `replays.jsonl` in the state folder. The line has the result and the usage of each
judge call, also of a call that failed. The Cost panel shows the last replay of each project beside the Pick settings
table.

## The project's checks

Set `test.checkCommand` in `.conveyor/project.json` to a command that runs your project's checks, for example a lint
or shellcheck. Conveyor runs it in the card's worktree after each build, fix and rebase session, and at the start of
the card's Test step. Exit 0 means that the checks pass.

When the checks fail after a session, the card goes to a fix session before any review or test. The fix session
gets the output of the checks. When the checks fail again after that fix session, the card is blocked.

When the checks fail at the start of a Test step, no test file runs. The test line shows one failure that names the
command. The card goes to a fix session with the output. This does not use the card's one test-fix round.

Conveyor keeps the result of the checks for each tree. On a tree that the checks ran on, the Test step does not run
them again. Your test command can read that result in its test log folder: the exit is in
`checks/<commit>-<tree>.rc` and the output is in `checks/<commit>-<tree>.out`.

Without `test.checkCommand`, Conveyor runs no such checks.

## Lint

The pack's `lint` field lists your project's lint commands. `conveyor.sh lint` runs them on a change, and `conveyor.sh
doctor` tries each one ([Commands](commands.md)). When the rule Lint check is on, each card runs them before each
review and before it lands ([Lint](cards.md#lint)). Without a `lint` field, or with the rule off, no lint command runs in a card.

`lint.commands` is a list. Each entry has these keys:

- `files`: git pathspecs of the source files that the command reads.
- `triggers`: git pathspecs of the scripts, config files, manifests and lock files that change the command's result.
  They are never given to the command as sources. The default is none.
- `run`: a shell command. `{files}` in it becomes the list of files, each one quoted for the shell. A command without
  `{files}` runs on the whole project.
- `ratchet`: `false` makes every finding of the command count, on any line. The default is `true`.
- `complexity`: the rule codes of the command that measure size, such as a limit on the length of a function.

`lint.policy` is a list of git pathspecs of the files that are lint policy, for example the config files of your
linters. The `lint` field itself is always lint policy. With the rule Lint check on, a card that changes lint policy
stops for your yes after its review ([Lint](cards.md#lint)). Conveyor reads `lint.policy` from the pack of your main
checkout, not from the card's change.

Git matches the pathspecs. A `*` also matches a `/`, and `:(exclude)<pathspec>` leaves files out.

Which files a command gets:

- A command with `{files}` gets the changed files that `files` matches. A renamed file has its new path. A deleted
  file is never given.
- When a file that `triggers` matches changes, the command gets every file of the tree that `files` matches. When the
  `lint` field changes, every command does. A deleted or renamed source file does not do this.
- When no file is left, the command is not called, and its result is `no files`.
- A command without `{files}` runs when a changed file, also a deleted one, matches `files` or `triggers`, or when the
  `lint` field changes. It is not called when no file of the tree matches `files`, and its result is `no files`.

The tree is the worktree as `git add -A` would stage it: a file that is not tracked yet and not ignored is a file of
the tree.

How a command runs: from the top of the worktree, with `bash -o pipefail -c`, on a test slot, for at most 5 minutes.
In `conveyor.sh lint`, `GIT_INDEX_FILE` names a copy of the index that holds the tree, so `git ls-files` in the
command also lists the files that are not tracked yet. `conveyor.sh doctor` gives the command the index of the main
checkout, so there `git ls-files` lists only the tracked files.
Conveyor reads the commands from the pack of your main checkout. The scripts and config files that a command loads
come from the worktree.

A finding is a line of the command's output in this form: `<path>:<line>[:<column>]: <text>`. The path is a file of
the tree, from its top, with no `./`. A path can hold spaces and colons. The first word of the text is the rule code.
Conveyor does not read other lines as findings.

The four results:

- Pass: the command exits 0 and prints no finding.
- Findings: the command exits 1 and prints one finding or more.
- Skipped: the first line is `lint: missing <tool>` and the command exits 127. Use this when the tool is not
  installed.
- Execution error: any other result. For example, another exit code, an exit 127 without that first line, an exit 1
  with no finding, an exit 0 with findings, or a command that runs for longer than 5 minutes.

### The ratchet

The ratchet decides which findings of a card are the card's own. An old finding that the card did not cause does not
count against the card. Base is the commit that the card's worktree is on.

Every finding of a command with `ratchet: false` is the card's. For any other command, the ratchet judges each
finding:

- A finding on a line that the card added or changed is the card's. Every line of a new file is a changed line.
- A finding with a `complexity` code on a changed line of a file that base has is an exception. It is the card's only
  when the base lines that the card's change replaced do not have the same finding.
- A finding on another line is the card's when base does not have the same finding on that line. Conveyor finds that
  line of base through the diff, so a line that moved down by one is compared with the line above it in base. A
  renamed file is compared with the file under its old path in base.

The same finding has the same file, line, rule code and text. A finding with a `complexity` code on a changed line
can be on any of the base lines that the card's change replaced. The numbers in the text must be equal, but not in a
finding with a `complexity` code. One base finding matches one finding of the card at most. So two equal findings
against one base finding give one finding of the card.

Conveyor gets the base findings from one run of the command on base, in a worktree at `cards/mainrun/<card>.lint` in
the cards folder. A command with `{files}` gets only the files that hold a finding to compare, each under its base
path. A command without `{files}` runs on the whole project. When no finding needs a base finding, Conveyor makes no
base run.

Before the base run, Conveyor makes the base worktree's copies of the files that the command's `triggers` and
`lint.policy` match equal to the card's. It writes each file that the card has and deletes each file that the card
deleted. The other files stay as base has them, also the trigger files of an earlier command. So a card that makes
a rule stricter gets no finding for old code that it did not touch.

The base worktree uses the same dependency folders as the card's worktree. Conveyor does not run `worktree.setup`
there. The base run holds one test slot, as the card's run does. Conveyor removes the base worktree when the run
ends. When the base run ends in an execution error or as skipped, the result of the command is an execution error.

For example:

```json
"lint": {
  "commands": [
    {"files": ["*.py"], "triggers": ["pyproject.toml"], "complexity": ["C901"], "run": "ruff check --output-format concise {files}"}
  ]
}
```

## The test map

The test map tells which test files cover which source files. With it, a card runs the tests that cover its change,
not only the tests with a matching name.

Setup makes the map. It runs your whole suite once with the coverage tool of your language, and it asks you first:

| Language | Tool | How it runs |
|---|---|---|
| Node | V8 coverage (`NODE_V8_COVERAGE`) | one test file at a time |
| Python | coverage.py with dynamic contexts | the whole suite once, one context for each test function |
| Go | `go test -coverprofile` | one package at a time |
| Rust | `cargo llvm-cov` | one test binary at a time |
| Ruby | SimpleCov | one spec file at a time |

Setup finds the language from the files at the root of the repository: `go.mod`, `Cargo.toml`, `Gemfile` or `.rspec`,
`package.json`, then `pyproject.toml`, `setup.py`, `setup.cfg`, `pytest.ini` or `tox.ini`. For Node and Ruby, each
test file runs with `test.fileCommand`, or with `test.command` and the file as `test.list` gives it. Without these,
Node uses `node --test` and Ruby uses `rspec`.

Setup writes the map to `.conveyor/test-map.json`, with the commit and the test command that it was made on. Setup
then shows how many source files and test files it mapped, and how long the run took. For Node, Go, Rust and Ruby,
if a test file fails under the run, the map does not include it, and the run continues with the other files. The map also does not include a
Node test file that imports `claude-code/testing`, because that file runs only under the test runner of Claude Code.
The map keeps a list of these files, each with the reason, and setup shows how many there are. If your language has
no tool in the table, if the tool fails, or if no test file is mapped, setup tells you. Your cards then find their
tests by name.

To make the map by hand, run `conveyor.sh testmap build`, or click **Build the test map** on the Board's Tests page.
The build runs on the build machine, on a test slot, and makes the map as setup does. The command returns when the
build starts. Only one build runs at a time. `conveyor.sh testmap stop` stops the build, and the map that was there
stays. The file `.conveyor/test-map.build.json` keeps the start, the end, the result and the reason of the last
build. When `test.map` is `off`, the command tells you how to turn the map on: remove `test.map` from the pack, then
run setup with `--test-map yes`, or run `conveyor.sh testmap build` again. When your language has no tool in the
table, or the tool is not installed, the command tells you why. When `test.map` names a map that your project keeps itself, the command tells you that Conveyor does not make that map.

The map stays current in these ways:

- When a card's test run passes, Conveyor maps each test file that the change adds and the map does not hold yet.
- The whole test on main (`test.main`) and the release check (`release-prep`) make the map again when the map is due.
  The map is due when it is more commits behind than `test.mapAge`, or when it was made with another test command.
  Coverage is then on for that run: `NODE_V8_COVERAGE` for Node, and coverage.py in each Python process for Python.
  If the run passes, Conveyor makes the map from the coverage of that run. It does not run the suite a second time.
  A Go, Rust or Ruby run cannot collect coverage in this way. For these languages, if the run passes, Conveyor runs
  the tests a second time with the tool that setup uses, and makes the map from that run.
- A source file that the map does not cover gets the test files that `.conveyor/test-links.json` links to it. If
  that file gives no test, the source file gets its tests by name. If no test has a matching name, the card runs no
  test for that file.

To turn the map off, set `test.map` to `off` in the pack. Cards then find their tests by name. To use a map that your
project keeps, set `test.map` to its path from the root of the repository. Conveyor reads it in each card's worktree
and does not make it again. The file can be a JSON object (`{"<source file>": ["<test file>", ...]}`) or lines of
areas in the form of this project's `.conveyor/engine-areas.json`. A test file named without a folder is the tracked
test file of that name. A card does not run the whole suite for the files of an area whose tests are `"all"`. A card
that changes this map runs the tests of each source file whose tests the change changes: the tests that the map gave
the file before and the tests that it gives the file now.

## The host file

The host file, `~/.config/conveyor/host.json`, holds this machine's settings: the terms file, the projects (`records`),
the machine's `cap` and pause, `testSlots`, `reserveCores`, the Claude accounts and the Foreman's
groups. Setup writes it. [Setup](setup.md#the-host-file) lists its keys, and [Run](setup.md#run) says what each
machine setting does.

## Cores kept for you

The host file's `reserveCores` keeps cores out of all card work, so that your terminal and apps always have free
cores. It is 0 when the host file does not set it.

- A number keeps that many cores: the highest-numbered cores of the machine. `"reserveCores": 2` on a machine with
  16 cores keeps cores 14 and 15.
- A list of core numbers keeps those cores. `"reserveCores": [0, 1]` keeps cores 0 and 1.

No test slot is on a kept core, and the pool of test slots is never larger than the cores that are left. Card build,
fix and review sessions and card test runs start with `taskset` on the cores that are left. Conveyor always leaves one
core for card work: a setting that keeps every core leaves the lowest of them.

`conveyor.sh doctor` and the **Reserved cores** row on the Board's Rules tab show the kept cores and the number
of test slots that are left. To change the setting, edit the host file.

macOS cannot keep a process off a core, so the setting is not available there. Doctor and the Rules tab say so, with
the reason. On Linux, the setting needs `taskset` (util-linux).

## The control record

Each project has a control record in its state folder. It holds what the loop builds and in what order, the rules,
the models of each seat (a seat is the builder, the reviewer or the judge), the judge and the
accounts. `conveyor.sh control` or the Board's Control and Rules tabs set it. Every value is a setting:

- the number of cards at once (`conveyor.sh control cap`, or Cards at once on the Rules tab),
- the usage at which no new card starts,
- the builder, reviewer and judge, each a CLI, a model and an effort, and the ones an issue has of its own ([Settings
  for one card](#settings-for-one-card)),
- the rules: P0 to P3, follow-ups, push, visible changes, split large issues and the dependency guard,
- where new issues start,
- Land as: `main` or `pr` (`conveyor.sh control land-as main|pr`, or Land as on the Rules tab; [Land
  as](#land-as)),
- Merge PR: `button`, `release` or `idle` (`conveyor.sh control pr-merge button|release|idle`, or Merge PR on the
  Rules tab; [Merge PR](#merge-pr)),
- the test run before a push (`conveyor.sh control push-check on|off`), when you set it over the pack's `push.check`.

A card that only waits on another card does not take one of the cards at once: for example, a card that waits to land
after a card that changes the same files. The loop leaves out no more waiting cards than the cap. Each waiting card
past that limit counts. A waiting card that runs its own checks or tests counts while they run.

Setup writes the control record of a new project. In it, new issues start held, and each issue that is open at setup
is held. Thus Conveyor builds no issue until you release it. Without this, the first loop would queue and build the
whole backlog of the project. Release an issue with `conveyor.sh control release <issue>` or on the Board. To let new
issues go into the Queue by themselves, run `conveyor.sh control start queue`, or set where new issues start on the
Rules tab. A second setup keeps the record as it is.

When new issues start in the Queue, Conveyor queues only the issues that the repository's owner, a member of its
organization or a collaborator opened. It holds each other open issue, whatever the setting, and the Board shows it in
Held with "Opened by someone outside the project: release it to build it". The reason: on a public repository, anyone
with a GitHub account can open an issue, and a card builds from the text of its issue with tools that change files.
Thus text from outside the project gets to a build only after you read it and release the issue. Release it with
`conveyor.sh control release <issue>` or on the Board, and Conveyor builds it as it builds other issues.

Each other value of a new project starts on Conveyor's default values (`conveyor/README.md`, Control). A record keeps each value it sets.
With the default push rule, Conveyor lands each card and pushes when you press "Push landed" on the Board, or on its
own once you turn push on in the Rules tab.
Only the keys it leaves out take those defaults. `default` sets a value back: for example `conveyor.sh control cap off`
or `conveyor.sh control model default`. For a seat, the default is the pack's first model for it (`models.allowed`, or with no list set the models that the CLIs report: [Models](#models)).

A model set with its CLI runs as set, whether the pack's `models.allowed` lists it or not. A model set without a CLI
must be one that `models.allowed` lists for the seat, or, for a Codex reviewer or judge, one that Codex reports (not when the pack's `models.allowed` has no `codex` list or an empty one); if it is not, the seat runs on its default. A seat whose
CLI is not installed does not start, and `conveyor.sh doctor` names it.

Models can run on a second route: an API proxy, or the provider's own API with your own key. `claudeProxy` in the
host file, or the pack's `models.claudeProxy`, sets the route for Claude. `codexProxy` in the host file sets the
route for Codex. In the host file, the route's `kind` is one of three. The pack's `models.claudeProxy` is always a
proxy.

- `subscription`: the CLI's own login only. The host file sets nothing else.
- `proxy` (also when `kind` is not set): a proxy at `baseUrl`. `keyEnv` names the variable that holds its key, and
  the proxy gets the key as a Bearer token.
- `api`: the provider's own API at `baseUrl`, for example `https://api.anthropic.com` for Claude or
  `https://api.openai.com/v1` for Codex. `keyEnv` names the key's variable: `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`.
  Claude gets the key as its API key (`x-api-key`), never as a Bearer token.

Conveyor gives Codex's route to each Codex session as Codex's own provider settings, so Codex's `config.toml` does
not change. With no `codexProxy`, Codex uses the provider that its own `config.toml` names. A key that Codex keeps
itself, from `codex login --with-api-key`, is Codex's own login: the `subscription` route.

The host file never holds a key, only the name of its variable. Each session reads the key when it starts, from the
first of these that has it:

1. The `env` of Claude Code's settings file, `~/.claude/settings.json`, under the name that `keyEnv` gives.
2. The key file that the route's `keyFile` names. The file holds the key as its first line. It must be yours, and
   only you may read or write it (mode 600). Conveyor does not read a key file with a looser mode.
3. The environment that Conveyor runs in. The machine's service starts with a bare environment, so its cards do not
   get a key from there. Keep the key in one of the first two places.

The `roles` of each route set the route of each role, `builder` (build, fix and rebase) and `reviewer` (review):

- `proxy` or `api`, or a role that `roles` does not name: the role's sessions always run on the second route.
- `fallback`: the role's sessions run on the CLI's own login first. When that login fails before the session starts
  its work (an expired login, no login, or a refused login), the same step runs again at once on the second route,
  and the card goes on. If the Claude route has no key, the session gets a stand-in key, so it does not try the
  failed login again. A step that fails on both routes is blocked, and its reason names both causes.
- `subscription`: the role's sessions never run on the second route.

`conveyor.sh doctor` shows each role's route. For a second route, it says where the service reads the key, or that
the service finds no key. For each part of a route that setup or the pack sets, it makes one call as the service makes
it, and shows the result: the CLI's own login, the proxy through the CLI, or the API with the key. A proxy that
works with no key is shown as a proxy that needs no key. When the API has no key, or a proxy refuses a call with no
key, doctor shows a `missing:` line that says where to put the key. Setup and doctor show a `conveyor: checking` line
before each of these calls, because a call can take some time.

The card's record and its timeline on the Board say which route each step used. The Board's Health shows each Claude
route, the subscription login and the second route, with its state: works, expired, not set, fails, or not checked.
A role on the second route is billed per token and has no usage limit. Conveyor does not read the usage limit of its
account, and it does not wait for one before a pick. A `fallback` role's account is read, because each of its sessions
starts on the CLI's own login. When no role runs on the subscription, the Usage limit row in Health says `API route: no
usage limit (billed per token)`. Each such project has its own row. When Conveyor runs on the Board's machine, the
row of the Board's own project also gives that project's cost today on that machine, from the session logs.
[Setup](setup.md#setup) finds the routes this machine can use and writes `claudeProxy` and `codexProxy` for you.

## Land as

Land as sets where the push sends the cards that landed. Either way, each card lands on your local default branch, in
order, and each next card builds on the last.

- `main`: the push sends main to the default branch of the remote (`remote` and `defaultBranch` in the pack). Each
  card's `Closes #N` line closes its issue when the push reaches the remote.
- `pr`: the push sends main to the branch `conveyor/landing` and keeps one pull request open from it into the
  default branch. The first push opens the pull request, and so does the first push after you merge it. Each later
  push updates it. Conveyor never pushes the default branch. The issues close when you merge the pull request.

At each push, Conveyor writes the pull request's body again. It lists every card in it, in the order they landed: the
`Closes #N` line, the title, the card id, its Done-when check (how many items are met, and each `D<n>` line of the
reply, met or not met), its fix rounds and the tests it ran (each file, with the cases it ran of a file it ran in part).

The pack's `push.landAs` sets the rule for the project. `conveyor.sh control land-as main|pr`, or Land as on the Board's
Rules tab, sets it in the control record, and the record wins over the pack. The rule Push on landing still
decides when a push happens.

## Merge PR

Merge PR sets who merges the pull request of Land as `pr`.

- `button` (the default): only you merge it. Use **Merge** on the Board's Control tab, or `conveyor.sh pr merge`.
- `release`: the release merges it. `release-prep` runs the whole suite on `conveyor/landing`. `release` checks
  that head first. When all checks pass, it merges the pull request, then makes the release on top of the merge. A release
  that a check stops merges nothing.
- `idle`: Conveyor merges it when no card is on the belt and no issue can be picked. When Test before a push is on,
  Conveyor first runs the test files linked to every card in the pull request, each one alone, on the head of
  `conveyor/landing`. Conveyor merges only when they all pass. A file that fails goes to a main-fix card, as in the run
  before a push. When Test before a push is off, Conveyor merges with no test run first
  ([Which tests a card runs](#which-tests-a-card-runs)).

With every rule, **Merge** shows on the Control tab while a pull request is open. Conveyor merges with a merge
commit. Then your local default branch moves to the remote's default branch, Conveyor closes the issues of the cards
in the pull request, and the next push opens a new pull request.

When GitHub refuses a merge (a failed check, a conflict), the pull request stays open. The Board shows GitHub's reason
beside **Merge**, and the Foreman gets the same reason.

The pack's `push.prMerge` sets the rule for the project. `conveyor.sh control pr-merge button|release|idle`, or Merge
PR on the Board's Rules tab, sets it in the control record, and the record wins over the pack.

## Models

Each seat (Builder, Reviewer, Judge) is a CLI and a model. The CLI is one of `claude`, `codex` and `opencode` that is
installed on the machine that runs the loop. The model is one that the CLI lists, or any name you type. On the Rules
tab, Other… in the model list gives a field for the name, and the model in force then says "(not listed)". A model the
CLI cannot run fails in the card, and the card shows the error.

`conveyor.sh control model|reviewer|judge <cli> <model> [effort]`, or the Rules tab, sets a seat. `default` clears it.
The effort is one that the CLI takes. The judge can run on the reviewer's CLI, and the Rules tab then says it is of
the same family. Left at default, the judge runs on another CLI than the reviewer's.

### Settings for one card

An issue can have its own builder, reviewer and judge, before it is picked or while its card is on the belt. Each one
is a model and an effort. A seat you do not set uses the project's.

- `conveyor.sh control card <issue> builder|reviewer|judge <model> [effort]` sets one seat. The model must be one
  that `models.allowed` lists for that seat: the builder's models for the builder, the review's models for the
  reviewer and the judge. Conveyor refuses any other model and names the allowed ones. The effort is one that the
  model's CLI takes. With no effort, the seat uses the project's effort, or `medium` when the model's CLI does not
  take that effort.
- `conveyor.sh control card <issue> <seat> clear` clears one seat. `conveyor.sh control card <issue> clear` clears
  all three.
- `conveyor.sh control card <issue> pick` asks the project's judge one time to choose the three seats for the issue.
  The judge gets the issue's text, its size and areas, the allowed models and their prices. It answers with a model,
  an effort (none for a model whose CLI takes none) and one line of reason for each seat. This changes nothing. To use the choice, set the seats.

The control record keeps these settings by issue number, so a retry of the card keeps them. The card's build, fix
and fitting sessions use its builder. Its review uses its reviewer, and its judge calls use its judge. A step that
already runs keeps its settings. The next step uses the new ones. On the Board, each card has Settings and Pick for
me ([The Board](board.md#settings-for-one-card)).

The host asks each CLI for its models:

- Codex: the models that your Codex account can use, from Codex's models cache (`models_cache.json` in `~/.codex`, or
  in `CODEX_HOME` when you set it). Codex gets the list again when it runs, so a new model shows up with no edit.
  When there is no cache, the host asks `codex debug models`. When `codexProxy` in the host file sends the Codex
  sessions of both roles through a proxy (no role in `codexProxy.roles` set to `subscription` or `fallback`), the
  host also asks the proxy for its `/v1/models` list, with the route's key. It adds the proxy's models to the Codex models, so a model that the proxy serves shows up before Codex reports it. A proxy that
  does not answer adds no models, and nothing fails. The host does not ask the OpenAI API (`kind` `api`) for its list.
- OpenCode: `opencode models`, one `<provider>/<model>` a line.
- Claude Code has no command and no file that lists the models your account can use (its `--model` takes an alias
  such as `opus`, or a full name). For Claude, the Board offers the pack's list, or the list that comes with Conveyor
  when you set none, and a field for any other name.

The Board's model menus offer the models that the CLI reports and then the models of the pack's `models.allowed` for
that CLI, each one time, then Other…. The pack's list adds models to the CLI's list. It does not replace it.

`conveyor.sh clis` reads the lists again and prints them. The Board does not offer a CLI that is not installed. A seat
set to a CLI that the host no longer has is marked on the Board, and the loop starts no card on it.

Set `models.allowed` in the pack to add models to the CLIs' lists, for example a model that the CLI does not report
yet. The models that Codex reports are added after the pack's `models.allowed.codex`, so a seat can run them too, and
the pack's first model stays the seat's default. An empty `models.allowed.codex` gets no Codex models, so the
reviewer stays on Claude. When you do not set `models.allowed` (setup does not), the project
uses the models that the CLIs report: Codex's from its models cache, and for Claude the list that comes with Conveyor.

`conveyor.sh doctor` shows a `warning:` line for each model that the pack's `models.allowed` lists for Codex or
OpenCode and that the CLI does not report, as a seat set to it may not start. A Codex family name, such as `sol`,
gets no warning when Codex has a model of that family. Doctor also shows a `warning:` line for each model that the
CLI reports and the pack leaves out. Doctor does not compare the lists for Codex when `models.allowed.codex` is empty
or not set, for OpenCode when the pack lists no OpenCode model, or for a CLI that gives no model list.

The pack's `models.allowed` limits nothing. Its first model for a seat is the seat's default, run by the CLI it is
listed under:

- for the builder: `claude`, `opencode` (as `opencode:<provider>/<model>`) and `codex-builder`
  (`models.allowed["codex-builder"]`),
- for the reviewer and the judge: `codex`, `claude-reviewer` and `opencode`.

A model that a seat runs, or that the project's model list has, can have no price. The model list is
`models.allowed` when you set it, with the Codex models that Codex reports added to its `codex` list when that list has a model in it. When you do not, it is Conveyor's built-in models, with the Codex models that Codex
reports in place of the built-in Codex ones, and with no Codex models when Codex is not installed. The Rules tab shows such a
model under Model prices, in "Offered with no price". A model that the sessions of the last 30 days used, and that no price prices, shows in
"Seen but not priced". The loop files one held issue for each such model, "Model price missing: <model>", and does
not file it again. A Codex family name, such as `sol`, is not a model ID: the check uses the model that Codex runs for
it. Add the price on the Rules tab (Model prices), or with `conveyor.sh prices add`. An OpenCode model
does not need a price: the Board shows the cost that OpenCode reports.

To use OpenCode for a seat:

1. Install OpenCode on the machine that runs the loop (`npm install -g opencode-ai`). Sign in to each provider with
   `opencode auth login`, or set the provider's key in `~/.config/opencode/opencode.json`. `opencode models` lists the
   models it can reach.
2. Set the seat: `conveyor.sh control reviewer opencode openrouter/<model> high`, or
   `conveyor.sh control judge opencode openrouter/<model>`, or pick OpenCode and then the model on the Rules tab.

For the reviewer and the judge, OpenCode gets the effort as the model's variant. OpenCode reviews are read-only: it can
read and search, but it cannot edit files or run commands. For the OpenCode and Codex builders, see OpenCode builder
and Codex builder in [conveyor/README.md](../conveyor/README.md).

## Privacy

Conveyor's state stays on your machine. The card records, the declined list, the decisions and the Board's users are
local files. Only the Board's signed-in users can see the Board.

Before the engine or the Board writes to GitHub, the privacy check (`conveyor/privacy/check.sh`) reads the text. It
looks for email addresses, private network addresses, home paths, access tokens and keys, and every word of your terms
file, when you have one. An address at `example.com`, `example.org` or `example.net` and a home path of the user `dev`
are not hits: they are names kept for examples. In `public` mode, the default, a hit posts nothing, and the state folder's `privacy` folder keeps the text. In
`private` mode, a hit is only a warning and Conveyor posts the text. `gh-write <gh arguments>` runs a `gh` write
through the same check.

The terms file is optional. It holds words that must never reach GitHub, such as people's names, private host names
and client names, one a line. To use one, name it in the host file as `"terms": "<file>"`. With no terms file, the
check runs with no word list. When the host file names a terms file that cannot be read, a `public` project posts
nothing, and `conveyor.sh doctor` names the file.
