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
- `pipelineFiles`: the files that change how cards are built, reviewed, fixed, tested, landed or pushed. A follow-up
  that changes one is filed held.
- `auto.reserved`: what `/conveyor-belt:auto` never decides ([Foreman](foreman.md)).
- `test.full`: the full test suite, which "Push landed" runs. Setup sets it to your test command. `test.main`: the whole test on main. `test.survey`: the monthly test-speed survey.
  `test.firstSurvey`: the answer to setup's survey question.
- `tunables.pushRetry`: the seconds between two tries of a push that failed for the network or the remote.
- `prices`: your model prices, by model name, each `{"input": 3, "output": 15, "cacheRead": 0.3}` in dollars per
  million tokens. Each one wins over the Board's built-in price of that model. Set them on the Board's Rules tab
  (Model prices, [The Board](board.md#rules)) or with `conveyor.sh prices set <model> <input> <output> <cache read>`
  and `conveyor.sh prices clear <model>`.

## The host file

The host file, `~/.config/conveyor/host.json`, holds this machine's settings: the terms file, the projects (`records`),
the machine's `cap` and pause, `maxLoad`, `minFreeMemMB`, `testSlots`, the Claude accounts and the Foreman's groups.
Setup writes it. [Setup](setup.md#the-host-file) lists its keys, and [Run](setup.md#run) says what each machine
setting does.

## The control record

Each project has a control record in its state folder. It holds what the loop builds and in what order, the rules,
the models of each seat (a seat is the builder, the reviewer or the judge), the judge and the
accounts. `conveyor.sh control` or the Board's Control and Rules tabs set it. Every value is a setting:

- the number of cards at once (`conveyor.sh control cap`, or Cards at once on the Rules tab),
- the usage at which no new card starts,
- the builder, reviewer and judge, each a CLI, a model and an effort,
- the rules: P0 to P3, follow-ups, push, visible changes and the dependency guard,
- where new issues start.

A new project starts on Conveyor's default values (`conveyor/README.md`, Control). A record keeps each value it sets.
With the default push rule, Conveyor lands each card and pushes when you press "Push landed" on the Board, or on its
own once you turn push on in the Rules tab.
Only the keys it leaves out take those defaults. `default` sets a value back: for example `conveyor.sh control cap off`
or `conveyor.sh control model default`. For a seat, the default is the pack's first model for it (`models.allowed`).

A model set with its CLI runs as set, whether the pack's `models.allowed` lists it or not. A model set without a CLI
must be one that `models.allowed` lists for the seat; if it is not, the seat runs on its default. A seat whose
CLI is not installed does not start, and `conveyor.sh doctor` names it.

Models can run through an API proxy. `claudeProxy` in the host file, or the pack's `models.claudeProxy`, names its base
URL and the name of the variable that holds its key. It never holds the key. Codex uses the provider that its own
`config.toml` names.

## Models

Each seat (Builder, Reviewer, Judge) is a CLI and a model. The CLI is one of `claude`, `codex` and `opencode` that is
installed on the machine that runs the loop. The model is one that the CLI lists, or any name you type. On the Rules
tab, Other… in the model list gives a field for the name, and the model in force then says "(not listed)". A model the
CLI cannot run fails in the card, and the card shows the error.

`conveyor.sh control model|reviewer|judge <cli> <model> [effort]`, or the Rules tab, sets a seat. `default` clears it.
The effort is one that the CLI takes. The judge can run on the reviewer's CLI, and the Rules tab then says it is of
the same family. Left at default, the judge runs on another CLI than the reviewer's.

The host asks each CLI for its models:

- Codex: `codex debug models`.
- OpenCode: `opencode models`, one `<provider>/<model>` a line.
- Claude Code has no command that lists its models (its `--model` takes an alias such as `opus`, or a full name). The
  Board gives its seats a field for the name.

`conveyor.sh clis` reads the lists again and prints them. The Board does not offer a CLI that is not installed. A seat
set to a CLI that the host no longer has is marked on the Board, and the loop starts no card on it.

The pack's `models.allowed` limits nothing. Its first model for a seat is the seat's default, run by the CLI it is
listed under:

- for the builder: `claude`, `opencode` (as `opencode:<provider>/<model>`) and `codex-builder`
  (`models.allowed["codex-builder"]`),
- for the reviewer and the judge: `codex`, `claude-reviewer` and `opencode`.

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
