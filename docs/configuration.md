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
- `auto.standing`: the kinds of routine step that the Foreman takes without asking you. The kinds are `asked-fix` (a
  fix you asked for is filed and queued at once), `review-followup` (a follow-up that only finishes or corrects the
  change of a card you approved is queued), `release-check` (a failed check in a release you asked for gets one fix
  card, then the release goes on) and `fixed-block` (a card blocked by a cause that a landed fix removed waits on that
  fix and is tried again). Setup writes the list empty, so each kind is off until you turn it on in the Rules tab
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

A card's test run can get the list of the test files that its change touches. The pack's `test.list` tells how
your test command (`test.command`) takes the list:

- `args`: each path is added at the end of the command, for example `npm test` followed by the paths. If the command
  already names its test files, for example `node --test checks/*.js`, it gets no list and runs the whole suite. Use
  `placeholder` for such a command.
- `placeholder`: the paths go where `{files}` is in the command, for example `"command": "npx jest {files} --ci"`.
- `env`: an environment variable holds the paths, one on each line. [conveyor/README.md](../conveyor/README.md#the-list-of-tests-a-cards-run-is-given)
  gives its name.
- `runner`: for `go test` and `cargo test`, which take packages and test targets, not files. With `go test`, the
  folder of each `*_test.go` file goes where `./...` is in the command, for example `go test ./cart ./tax`. With
  `cargo test`, each `tests/<name>.rs` file adds `--test <name>` after `cargo test`. If the list holds another file,
  for example a helper module or a test module inside a source file, the card runs the whole suite.
- `none`: your command cannot take a list. Each card runs the whole suite.

Without `test.list`, your command gets no list. Use this when your command selects the tests itself.

The list holds:

- each test file that the change adds or changes;
- for each other changed file, the test files that `.conveyor/test-links.json` links to it, if your project has that
  file (`{"<file>": ["<test file>", ...]}`), and the test files that the [test map](#the-test-map) says cover that
  file;
- if neither gives a test, the test files whose name holds the name of that file, from the nearest folders. For example, a change to
  `src/cart/total.js` runs the test file of `total` in `src/cart/`, not one in another folder.

A change to a document (`.md`, `.txt`, `.rst`) adds no test. When the change touches one of the files below, the
command gets no list and runs the whole suite:

- a file that the test map marks as shared: more than half of the mapped tests read it;
- a file at the root of the repository, such as `package.json`, if the test map does not cover it;
- a config file (`.json`, `.yaml`, `.toml`, `.ini`, `.cfg`, `.conf`, `.lock`, or a name with `config`), if the test
  map does not cover it;
- a shared test file: a helper, setup, fixture or mock file, or a file in a folder of that name;
- a file that has no test that Conveyor can find.

A link in `.conveyor/test-links.json` wins over these rules, but not over a file that the test map marks as shared. `test.full` is not changed: it always runs the whole
suite. The Board shows the mode of a card's test run and how its tests were found: `changed: 7 files (map)`,
`changed: 7 files (by name)` or `whole suite: <why>`. With a made test map, it adds the age of the map, for example
`map 12 commits old`. `/units` shows `changed: 7 files` or `whole suite`.

### Whole suite in a card

The rule **Whole suite in a card** on the Rules tab sets if a card can run the whole suite. It is Off by default.
`conveyor.sh control rules wholeSuite=on` or `wholeSuite=off` also sets it. With the rule On, a card runs its tests
as this section says above.

With the rule Off, a card never runs the whole suite. The whole suite runs only in a release. The rule does not
change the runs of a release or of the full test suite. A card runs these test files:

- the test files of the list above;
- for a change that would run the whole suite, the test files that the test map and `.conveyor/test-links.json` link
  to the changed files, however many there are;
- for a changed document, the test files that the test map and `.conveyor/test-links.json` link to it.

If no test file is linked to the change, the card runs no test. The card's test line says so, and the release's run
covers the change.

A card can give its test files to your command only through `test.list`. If the pack has no `test.list`, has `none`,
or has a list form that the command cannot take, the card runs each test file alone with `test.fileCommand`. If the
pack sets neither, the card stops at its test step, and Needs you shows the reason. The reason names the settings that
fix it. `conveyor.sh doctor` shows a `warning:` line for a pack that sets neither `test.list` nor `test.fileCommand`.

A command can ignore the list that it gets. If a card's run reports more than ten test files for each file that it
gets, Conveyor stops the run. The card stops at its test step with a reason of the same kind. The check of a bug
card on main's code follows the same rule.

## The test map

The test map tells which test files cover which source files. With it, a card runs the tests that cover its change,
not only the tests with a matching name. The map works only with `test.list` set.

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
then shows how many source files and test files it mapped, and how long the run took. If your language has no tool
in the table, or if the run fails, setup tells you. Your cards then find their tests by name.

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
- A source file that the map does not cover gets its tests by name. If no test has a matching name, the card runs
  the whole suite and the Board says why.

To turn the map off, set `test.map` to `off` in the pack. Cards then find their tests by name. To use a map that your
project keeps, set `test.map` to its path from the root of the repository. Conveyor reads it in each card's worktree
and does not make it again. The file can be a JSON object (`{"<source file>": ["<test file>", ...]}`) or lines of
areas in the form of this project's `.conveyor/engine-areas.json`. A test file named without a folder is the tracked
test file of that name. The files of an area whose tests are `"all"` run the whole suite.

## The host file

The host file, `~/.config/conveyor/host.json`, holds this machine's settings: the terms file, the projects (`records`),
the machine's `cap` and pause, `maxLoad`, `minFreeMemMB`, `pressure`, `testSlots`, `steer`, `reserveCores`, the Claude accounts and the Foreman's
groups. Setup writes it. [Setup](setup.md#the-host-file) lists its keys, and [Run](setup.md#run) says what each
machine setting does.

## Card work yields to you

Conveyor often runs on the machine that you type on. With the host file's `steer` on, card work runs at a lower
priority than your own work:

- Card build, fix and review sessions run at a lowered CPU priority.
- Card test runs, mutation checks and the sessions of a test-speed survey card run at idle CPU and disk priority.

On Linux, a session runs at a higher `nice` value. Each card test run goes into a systemd slice of its own, with a low
`CPUWeight` and `IOWeight`. Without a user systemd, a test run gets the `ionice` idle class, and `nice` and
`SCHED_IDLE` only where your user can raise the priority again. On macOS, a test run starts with `taskpolicy -b` and a
session with `taskpolicy -c utility`.

Conveyor never lowers the Board's server, the Foreman's session or a process that you start.

When a test run waits for the CPU and gets almost none for a few seconds, Conveyor gives it its normal priority back
for a short time. Thus a test file does not time out because Conveyor lowered it. The CPU-second budget of a test file
stays the same.

`steer` is on when the host file does not set it. To turn it off, set **Card work yields to you** to Off on the Board's
Rules tab, or run `conveyor.sh machine steer off`. Card work then runs at normal priority, as your own work does.
`conveyor.sh doctor` shows the setting and what Conveyor lowers on this machine.

## Cores kept for you

The host file's `reserveCores` keeps cores out of all card work, so that your terminal and apps always have free
cores. It is 0 when the host file does not set it.

- A number keeps that many cores: the highest-numbered cores of the machine. `"reserveCores": 2` on a machine with
  16 cores keeps cores 14 and 15.
- A list of core numbers keeps those cores. `"reserveCores": [0, 1]` keeps cores 0 and 1.

No test slot is on a kept core, and the pool of test slots is never larger than the cores that are left. Card build,
fix and review sessions and card test runs start with `taskset` on the cores that are left. Where Conveyor puts a run
into a systemd scope, the scope's `AllowedCPUs` is the cores that are left too. Conveyor always leaves one core for
card work: a setting that keeps every core leaves the lowest of them.

`conveyor.sh doctor` and the **Cores kept for you** row on the Board's Rules tab show the kept cores and the number
of test slots that are left. To change the setting, edit the host file.

macOS cannot keep a process off a core, so the setting is not available there. Doctor and the Rules tab say so, with
the reason. On Linux, the setting needs `taskset` (util-linux).

## The machine room

Before a new card starts, and before a new test takes a test slot, Conveyor reads how hard pressed the machine is.
It gives the machine one state: Steady, Busy or Strained.

- Strained: no new card starts, and no new test takes a test slot.
- Busy: a new card starts only if, with it, no more than half of the host file's `cap` is in use. With no `cap`, Busy
  holds no card back.
- Steady: only the caps apply.

Cards and tests that already run do not stop.

Conveyor reads these figures:

- On Linux, the CPU pressure and the memory pressure: the "some avg10" of `/proc/pressure/cpu` and
  `/proc/pressure/memory`. Each is the percent of the last 10 seconds in which a task waited for the CPU, or for
  memory.
- On every system, the wake delay: how late a 10 ms sleep wakes, in ms. A test that waits for a slot reads the
  state again every few seconds.
- Where Conveyor cannot read the memory pressure, as on macOS, the free memory in MB.

The state is Strained when a figure gets to its Strained threshold. If not, it is Busy when a figure gets to its Busy
threshold. If not, it is Steady. Set the thresholds in the host file's `pressure`. These are the defaults:

```json
"pressure": {"busy": {"cpu": 40, "memory": 5, "wakeMs": 5, "freeMB": 2048},
             "strained": {"cpu": 80, "memory": 20, "wakeMs": 20, "freeMB": 512}}
```

`cpu` and `memory` are percents. A figure gets to its threshold when it is at or above it; the free memory gets to its
threshold when it is below it. A threshold that the host file does not set keeps its default.

When the host file sets `maxLoad` or `minFreeMemMB`, those settings hold new cards back, and the state holds no card
and no test back.

The Board's Health panel shows a Machine room row with the state and its figures. When the state holds new cards
back, `/units` shows one line under ON THE BELT with the figure over its limit, for example "machine strained: memory
pressure 25.5% (limit 20%) · new cards wait". When the state holds no card, it shows no line. A card that waits for the machine room says which figure holds it, for example "waiting for machine room:
Strained (memory pressure 25.5% is at or above 20%)".

## The control record

Each project has a control record in its state folder. It holds what the loop builds and in what order, the rules,
the models of each seat (a seat is the builder, the reviewer or the judge), the judge and the
accounts. `conveyor.sh control` or the Board's Control and Rules tabs set it. Every value is a setting:

- the number of cards at once (`conveyor.sh control cap`, or Cards at once on the Rules tab),
- the usage at which no new card starts,
- the builder, reviewer and judge, each a CLI, a model and an effort,
- the rules: P0 to P3, follow-ups, push, visible changes, whole suite in a card and the dependency guard,
- where new issues start.

A card that only waits on another card does not take one of the cards at once: for example, a card that waits to land
after a card that changes the same files. The loop leaves out no more waiting cards than the cap. Each waiting card
past that limit counts. A waiting card that runs its own checks or tests counts while they run.

Setup writes the control record of a new project. In it, new issues start held, and each issue that is open at setup
is held. Thus Conveyor builds no issue until you release it. Without this, the first loop would queue and build the
whole backlog of the project. Release an issue with `conveyor.sh control release <issue>` or on the Board. To let new
issues go into the Queue by themselves, run `conveyor.sh control start queue`, or set where new issues start on the
Rules tab. A second setup keeps the record as it is.

Each other value of a new project starts on Conveyor's default values (`conveyor/README.md`, Control). A record keeps each value it sets.
With the default push rule, Conveyor lands each card and pushes when you press "Push landed" on the Board, or on its
own once you turn push on in the Rules tab.
Only the keys it leaves out take those defaults. `default` sets a value back: for example `conveyor.sh control cap off`
or `conveyor.sh control model default`. For a seat, the default is the pack's first model for it (`models.allowed`, or with no list set the models that the CLIs report: [Models](#models)).

A model set with its CLI runs as set, whether the pack's `models.allowed` lists it or not. A model set without a CLI
must be one that `models.allowed` lists for the seat; if it is not, the seat runs on its default. A seat whose
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

## Models

Each seat (Builder, Reviewer, Judge) is a CLI and a model. The CLI is one of `claude`, `codex` and `opencode` that is
installed on the machine that runs the loop. The model is one that the CLI lists, or any name you type. On the Rules
tab, Other… in the model list gives a field for the name, and the model in force then says "(not listed)". A model the
CLI cannot run fails in the card, and the card shows the error.

`conveyor.sh control model|reviewer|judge <cli> <model> [effort]`, or the Rules tab, sets a seat. `default` clears it.
The effort is one that the CLI takes. The judge can run on the reviewer's CLI, and the Rules tab then says it is of
the same family. Left at default, the judge runs on another CLI than the reviewer's.

The host asks each CLI for its models:

- Codex: the models that your Codex account can use, from Codex's models cache (`models_cache.json` in `~/.codex`, or
  in `CODEX_HOME` when you set it). Codex gets the list again when it runs, so a new model shows up with no edit.
  When there is no cache, the host asks `codex debug models`.
- OpenCode: `opencode models`, one `<provider>/<model>` a line.
- Claude Code has no command and no file that lists the models your account can use (its `--model` takes an alias
  such as `opus`, or a full name). For Claude, the Board offers the list that comes with Conveyor, and a field for
  any other name.

`conveyor.sh clis` reads the lists again and prints them. The Board does not offer a CLI that is not installed. A seat
set to a CLI that the host no longer has is marked on the Board, and the loop starts no card on it.

Set `models.allowed` in the pack to keep your own list. When you do not set it (setup does not), the project uses
the models that the CLIs report: Codex's from its models cache, and for Claude the list that comes with Conveyor.

The pack's `models.allowed` limits nothing. Its first model for a seat is the seat's default, run by the CLI it is
listed under:

- for the builder: `claude`, `opencode` (as `opencode:<provider>/<model>`) and `codex-builder`
  (`models.allowed["codex-builder"]`),
- for the reviewer and the judge: `codex`, `claude-reviewer` and `opencode`.

A model that a seat runs, or that the project's model list has, can have no price. The model list is
`models.allowed` when you set it. When you do not, it is Conveyor's built-in models, with the Codex models that Codex
reports in place of the built-in Codex ones, and with no Codex models when Codex is not installed. The Rules tab shows such a
model under Model prices, in "Offered with no price". A model that only Codex reports, when you set
`models.allowed`, is not on this list. A model that the sessions of the last 30 days used, and that no price prices, shows in
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
