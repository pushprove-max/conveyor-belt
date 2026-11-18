# Setup

This page lists what Conveyor needs, and how to install, set up, run and remove it. The front page,
[README.md](../README.md), has the short form of each step.

## Requirements

`/conveyor-belt:setup` checks each requirement below at its minimum version. It installs each one that is missing or
too old, with Homebrew on macOS and with the system's package manager (`apt-get` or `dnf`) on Linux. It installs the
Claude Code CLI and the Codex CLI with `npm`. When the package manager needs `sudo` and `sudo` asks for a password,
setup asks you for it in Claude Code. On macOS, setup needs Homebrew.

Setup checks the copy of each program that Conveyor runs: the first one on Conveyor's PATH. On macOS, Conveyor, its
service and the Board put Homebrew's folders first on their PATH, before `/usr/bin`. A newer copy in another folder
does not count. When an install fails, or leaves a program below its minimum version, setup stops and names the
requirement and the reason. `conveyor.sh doctor` names each requirement below its minimum version, with the version it
found and where.

- bash 5.1 or newer.
- jq 1.8 or newer. Apple's `/usr/bin/jq` 1.7.1 is too old.
- git.
- `flock` (on Linux, from util-linux).
- Python 3 with its `venv` module (on Debian or Ubuntu, the `python3-venv` package), for the Board's virtualenv.
- The GitHub CLI, `gh`, signed in. When it is not signed in, setup starts `gh auth login`.
- The Claude Code CLI, 2.1.322 or newer, signed in (`npm install -g @anthropic-ai/claude-code`). When it is not
  signed in, setup starts `claude auth login`.
- The Codex CLI, signed in, for the Codex reviewer and the Codex builder models (`npm install -g @openai/codex`). When
  it is not signed in, setup starts `codex login`.
- For the Board, an `openssl` whose `req` takes `-addext`: OpenSSL 1.1.1 or newer, or the LibreSSL in macOS's `/usr/bin/openssl`. It makes the Board's certificate.
- On macOS, Homebrew's coreutils, findutils, gnu-sed and grep. To install the Homebrew requirements by hand:
  `brew install bash jq coreutils findutils gnu-sed grep flock`.
- Matt Pocock's skills, the plugin `mattpocock-skills` of the official marketplace. `/conveyor-belt:plan` reads it.
  Setup installs it (`claude plugin install mattpocock-skills@claude-plugins-official`), and `conveyor.sh doctor` names
  it when it is missing.
- OpenCode 1.x, only for OpenCode models (`npm install -g opencode-ai`). Setup does not install it. See
  [Models](configuration.md#models).

Conveyor runs on macOS and Linux.

## Install

Add the plugin in Claude Code with `/plugin marketplace add pushprove-max/conveyor-belt`, then
`/plugin install conveyor-belt@conveyor-belt`. This installs the newest release, not what is on `main`. To get a new
release, run `/plugin marketplace update conveyor-belt`, or turn on auto-update for this marketplace in `/plugin`
(Marketplaces).

The plugin does nothing in a project until `/conveyor-belt:setup` runs there. A project with no
`.conveyor/project.json` keeps its Bash, Edit, Write and AskUserQuestion calls as they were. In a project whose
pinned commit is not installed on this machine, the guards are off, and each session shows one line that says so
until setup installs the commit. A project that follows releases or `main` installs its engine again
([Following releases or main](#following-releases-or-main-or-pinning-a-commit)).

Setup installs the newest release of the engine, and the loop runs from it. You do not clone the repository for
the loop. The shell commands in these pages are that release's `conveyor/conveyor.sh`, in
`~/.local/share/conveyor/versions/<commit>` (under `$XDG_DATA_HOME` when that is set), run in your project's checkout.
`conveyor.sh doctor` names the commit.

## The host file

The host file, `~/.config/conveyor/host.json`, holds this machine's settings
([Configuration](configuration.md#the-host-file)). Setup writes it and adds your project to it. Change it only to
set one of these keys:

By default, Conveyor and the Board run on one machine. The host file that setup writes holds only `records`, and the
Board reads every project on this machine. To read the belt from a separate build machine instead, set `host`, `ssh`
and `main` in the host file on the Board's machine.

- `terms`: the terms file. It is optional ([Privacy](configuration.md#privacy)).
- `host`: the name of the build machine, for the Board to show. A `host` that is this machine's name means one
  machine.
- `ssh`: the target the Board reads the build machine through. With no `ssh`, the Board reads this machine.
- `main`: the folder of the Conveyor checkout on the build machine ([The Board](board.md#install-the-board)).
- `records`: each project the loop serves. A record's `ledger` is that project's decision ledger. The Board shows its
  open decisions and answers them. A record's `lanes` are the folders of its lanes, which `conveyor.sh lane ... create`
  writes.
- `claudeProxy` and `codexProxy`: the route of Claude's and Codex's sessions, and when they use it
  ([Configuration](configuration.md#the-control-record)). Setup writes them when it finds a second route (below).

## Setup

Run `/conveyor-belt:setup` in Claude Code, in your project's checkout. It asks three things:

- who approves a change that customers or staff will see,
- the path prefixes of product code,
- the command that runs a change's tests.

It also asks "Run a first test-speed survey now?". Yes files one test-speed survey issue. Its card measures every test
file alone and names the slow ones (The first survey, in [conveyor/README.md](../conveyor/README.md)). The pack,
the project's settings file `.conveyor/project.json`, keeps the answer (`test.firstSurvey`), so setup does not ask
again. To ask for a survey later, run
`/conveyor-belt:setup --survey`, or `setup --survey yes` from a shell.

Setup also reads the names of your project's tracked files and your test command, to find how your test files are
named ([How test files are found](configuration.md#how-test-files-are-found)). When the default test-file patterns
miss files that look like tests, setup shows the patterns that it found and how many tracked files they match. Then it
asks if it can write them in the pack as `tests.patterns` (`--test-patterns yes|no`). If your pack already sets
`tests.patterns`, setup does not ask.

Setup also finds the test runner that your test command starts. For `npm test` and the other package scripts, it
reads the script in `package.json`. For node --test, vitest, jest, mocha, pytest and rspec, it asks if it can set
`test.list` to `args`. Then a card's test run gets only the tests that its change touches
([Which tests a card runs](configuration.md#which-tests-a-card-runs)). If the command already names its test files, for example
`node --test checks/*.js`, setup does not ask. For go test and cargo test, it asks if it can
set `test.list` to `runner`. These runners take packages and test targets, not test files, so a card's test run gets
the packages or test targets of the tests that its change touches. The answer is `--test-list yes|no`. If your pack already sets `test.list`, setup does not ask.

Setup then offers to make the test map ([The test map](configuration.md#the-test-map)). The map tells which test
files cover which source files, so a card runs only the tests that cover its change. To make it, setup runs your
whole suite once with the coverage tool of your language: V8 coverage for Node, coverage.py for Python,
`go test -coverprofile` for Go, `cargo llvm-cov` for Rust, or SimpleCov for Ruby. Before the run, setup names the
tool and the time of your last whole-suite run, if it knows it. The answer is `--test-map yes|no`. Yes runs the
suite and writes `.conveyor/test-map.json`, then shows how many source files and test files it mapped and how long
the run took. No sets `test.map` to `off` in the pack, and setup does not ask again. If your language has no tool in
this list, or if the tool is not installed, setup tells you and does not ask. Your cards then find their tests by
name.

From the same runner, setup finds how to read the times of each test file from the runner's own report. It does not
ask. When the test command already writes a report that Conveyor can read, for example `pytest --junitxml=report.xml`
or `go test -json ./...`, setup writes `test.report` in the pack with the report's `format` and `path`. Conveyor then
records each test file's clock seconds after each card test run. When the command writes no report, for example
`npm test` that runs `node --test`, jest, mocha or go test, setup has Conveyor ask the runner for one at each card
test run and each full test suite run, and your test command stays as it is. cargo test needs no report: its usual output gives the times. When
Conveyor cannot ask for a report, for example for jest followed by another command, setup writes the runner and the
report option that would give one (`option`). The Board's Health shows "Test times: Not recorded" with that option. Add the option to your test command and run setup
again. For a runner that setup does not know, set `test.report` yourself, for example
`{"runner": "make test", "format": "junit", "path": "reports"}` for JUnit XML files in the folder `reports`. The
section "Test file times" in `conveyor/README.md` lists each runner, its report option and its format.

Each time it runs, setup also asks if you want a fast lane and a research lane ([Lanes](lanes.md)). On yes, it makes
the lane, or keeps the lane that is already there.

Each card works in a worktree of its own, and a new worktree has no installed dependencies. Setup looks in your
checkout for the dependency folders that git ignores, such as `node_modules` (also in each package of a workspace),
`.venv`, `venv`, `vendor`, `target`, `.gradle` and `Pods`. It shows the list and asks if each card's worktree links
them from your checkout (`--link yes` or `--link no`). On yes, it writes the list as the pack's `linkFromMain`. A
link is not safe when a card can change a lockfile, because the card's tests then run on your checkout's packages.
The question names the lockfiles it finds. In that case, give the install command instead, for example
`--worktree-setup "npm ci"`. Setup writes it as the pack's `worktree.setup`, and each card's worktree runs it before
the build and the tests. Setup asks again on each run until the pack has `linkFromMain` or `worktree.setup`. It never
changes them after that, so your own edits stay.

Setup also looks for a second route for the CLI of each role, the builder and the reviewer, when that CLI has no route
in the host file. For Codex, it looks only when Codex is installed. A second route is one of these:

- A local API proxy. This is a proxy that listens on this machine, for example on port 4141. For Claude, it must
  answer the Anthropic Messages API. For Codex, it must answer the OpenAI Responses API. Setup looks at each proxy
  that it finds.
- The provider's own API with your own key: for Claude, the Anthropic API with `ANTHROPIC_API_KEY`; for Codex, the
  OpenAI API with `OPENAI_API_KEY`. Setup finds the key in the `env` of Claude Code's settings file
  (`~/.claude/settings.json`), in the environment that setup runs in, or in the key file that you give it.

When setup finds no key for a CLI, it first asks where you keep one (`--claude-key`, `--codex-key`): `none` when you
use no API key, `settings`, or the path of a key file (below).

Setup checks each route with one real call before it offers it: the CLI's own login, each proxy through the CLI, and
the API with your key. It shows each route that it checked. A route that fails is shown with the reason, and is not
offered. Each role is offered only the routes of its own CLI. When a role has more than its CLI's own login, setup
asks which route it uses, the builder (`--builder-route`) and the reviewer (`--reviewer-route`):

- `fallback`: the role's sessions run on the CLI's own login. When that login fails before the session starts its
  work, the same step runs again at once on the second route. When a CLI has both a proxy and the API, setup also
  asks which of the two is the second route (`--fallback-route proxy` or `--fallback-route api`).
- `proxy`: the role's sessions always run through the proxy. When more than one proxy works for the CLI, setup asks
  which one (`--claude-proxy`, `--codex-proxy`, with the proxy's base URL as setup shows it).
- `api`: the role's sessions always run on the provider's API with your key.
- `subscription`: the role's sessions run on the CLI's own login only.

For a CLI that takes the API, setup asks where the key is kept (`--claude-key`, `--codex-key`), when you did not
answer it before:

- `settings`: in the `env` of Claude Code's settings file, `~/.claude/settings.json`.
- The path of a key file. The file holds the key as its first line. It must be yours, and only you may read or
  write it (mode 600). Setup refuses a file with a looser mode. `/conveyor-belt:setup` can make the file for you: it
  asks for the key and writes it.

For a CLI that takes a proxy, setup asks where the proxy's key is kept (`--claude-proxy-key`, `--codex-proxy-key`),
when setup found that key only in your shell's environment. The answer is `settings` (the `CLAUDE_PROXY_KEY` or
`CODEX_PROXY_KEY` in the `env` of `~/.claude/settings.json`) or the path of a key file, as for the API key. Setup
checks the proxy with the key from there.

A proxy that needs no key works with no key set. Its sessions and checks send it a stand-in key, not the CLI's own
login.

Do not keep a key only in your shell's environment. The machine's service starts with a bare environment, so its
cards do not get a key from there.

Setup then writes the route of each CLI in the host file: `claudeProxy` for Claude, and `codexProxy` for Codex. Its
`kind` is `subscription`, `proxy` or `api` ([Configuration](configuration.md#the-control-record)). A `proxy` route
has the proxy's base URL, the name of the variable that holds the proxy's key (`CLAUDE_PROXY_KEY` or
`CODEX_PROXY_KEY`) and, when you gave one, the key file's path. An `api` route has the API's base URL, the name of the key's variable and, when you gave one, the
key file's path. Setup never writes a key. Setup does not ask again for a CLI whose route is in the host file.
Conveyor gives `codexProxy` to each Codex session as Codex's own provider settings, and does not change Codex's
`config.toml`.

`conveyor.sh doctor` shows each role's route, and checks it as the machine's service runs it: it reads the key from
the places that the service reads, not from your shell. Then it makes one real call on each part of the route that
the role uses: the CLI's own login, the proxy through the CLI, or the API with the key.

Then setup writes the pack, sets the project to follow the plugin's releases, installs the newest release, adds the
project to the host file, adds `/conveyor/state/` to `.git/info/exclude` so that git does not list the state folder,
creates the labels the pack names and runs `conveyor.sh doctor`. When the pack, `.conveyor/project.json`, is not
committed or setup changed it, setup shows you the change and asks "Commit the Conveyor pack (.conveyor/project.json)
on <default branch> now?". On yes, it commits only that file on your default branch, in your main checkout, and
pushes it when the Rules tab's **Push when a card lands** rule is On. Your other changes stay as they are. On no, the
pack stays on this machine: cards read the pack from the default branch, so they do not get it until you commit it.
When your checkout is on another branch, or the pack has a conflict, setup says so and does not ask. The Foreman asks
the same question when it finds the pack not committed. `doctor` prints one `ok:` line for each thing in place. It prints a
`missing:` line, with its fix, for each thing that is not. You can run `setup` again: it changes only what is not there
yet.

Setup and `doctor` also check the root of your checkout for the two files that give Conveyor's sessions your
project's context. `CLAUDE.md` is read by the builder, the fixer, the Foreman and the lanes. `AGENTS.md` is read by
the Codex reviewer. Each one gets an `ok:` line when it is there and a `missing:` line when it is not. A missing one
does not stop Conveyor, but its sessions then know your project only from the card rules. For each missing one,
`/conveyor-belt:setup` asks if it should write an optimized one. On yes, it writes the file from your project: what
the project is, its layout, its languages, how its tests run, its conventions and where its other docs are. It keeps
only what a session cannot learn from the code, and `AGENTS.md` points to `CLAUDE.md` instead of repeating it. It
shows you the file and gives the command that commits it; commit it yourself. On no, it writes nothing. Setup never
changes a `CLAUDE.md` or an `AGENTS.md` that is already there.

- `/conveyor-belt:setup --foreman` also sets up the [Foreman](foreman.md).
- `--pin` pins a new project to the commit of the plugin copy, in place of following releases (below).

From a shell, in your project's checkout, the same steps are
`conveyor.sh setup [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] [--test-patterns yes|no] [--test-list yes|no] [--test-map yes|no] --fast-lane yes|no --research-lane yes|no [--link yes|no] [--worktree-setup <command>] [--builder-route subscription|fallback|proxy|api] [--reviewer-route subscription|fallback|proxy|api] [--fallback-route proxy|api] [--claude-key none|settings|<key file>] [--codex-key none|settings|<key file>] [--claude-proxy <base URL>] [--codex-proxy <base URL>] [--claude-proxy-key settings|<key file>] [--codex-proxy-key settings|<key file>] [--pin] [--foreman]`,
then `conveyor.sh doctor`.

## Following releases or main, or pinning a commit

The pack's `plugin` names the engine the project runs, in one of three ways:

```json
"plugin": {"follow": "releases"}
"plugin": {"follow": "main"}
"plugin": {"commit": "<a full commit id>"}
```

- `{"follow": "releases"}`, the default for a new project. The project runs the plugin's newest published release, a
  `vX.Y.Z` tag with a GitHub release that is not a draft or a prerelease. The loop looks for a new release about once a
  minute. It installs and checks a new release, then takes it.
- `{"follow": "main"}`, to test changes before they are released. The loop takes each new commit of the plugin's
  pushed `main` in the same way.
- `plugin.commit`: the project runs exactly that commit. Nothing changes when `main` moves or a release is published.

Cards in flight end on the engine they started with. The loop moves to the new engine at its next pick. `conveyor
doctor` says which release or commit the project is on, and whether a newer one is out.

A machine that runs no loop moves too. The plugin's hooks and commands run from the engine the project took on that
machine. At most once a minute, a hook starts a take in the background. The next hook runs on the new engine. When that
take fails, the plugin's own copy of the engine does the take again, in case the fault is in the old engine. Each
background take writes its output and exit code to `.git/conveyor-engine.log` in the main checkout, which keeps the
last 10 takes and the last take that worked.

If the engine the project took is no longer installed on that machine, the next hook does not turn the guards off. It
does a take first and waits for it. The take installs the newest commit it can, and the hook then runs on that
commit. The hook shows one line that says so.

When the project runs an older commit than the newest one it can take, `conveyor.sh doctor`, the Foreman's start and
`/units` show one line:

```text
Conveyor runs an old engine here: commit 0543507, and the plugin's main is at 9f8e7d6 · last take that worked: 2026-11-16T05:10:00Z · last failure: <the reason> · to take it, run: cd <the main checkout> && bash <conveyor.sh> take
```

The line gives the commit the project runs, the newest commit, the time of the last take that worked, the reason the
last background take failed, and the command that takes the newest commit now. Run that command in a terminal. If it
fails too, its output says why. `doctor` reads the newest commit from GitHub. The Foreman and `/units` use the newest
commit that the last take found.

One take runs at a time. A take that starts while another one runs stops at once and does not wait. A later take
gets any newer commit. While a take runs, the same places show this line in place of the old-engine line:

```text
Conveyor takes the plugin's main now: commit 9f8e7d6; the project runs commit 0543507 until the take ends
```

When a new commit or release fails its check, or lacks a hook that the project's `.claude/settings.json` calls through
`shim.sh`, the project stays on the engine it has. Needs you on the Board names the commit and the reason. The entry
goes when a later commit or release is taken.

To pin a commit, or to pin another one:

1. Install the commit on every machine that runs the project: `conveyor.sh install <commit>`.
2. Set the pack's `plugin` to `{"commit": "<that id>"}` and commit it. Each loop moves to that commit at its next pick.

To follow again, set `plugin` back to `{"follow": "releases"}` or `{"follow": "main"}`.

## Run

Conveyor runs once per machine, and each project is a record of the host file. Setup adds the project as a record
(`{"records": [{"repo": "<name>", "main": "<its main checkout>"}]}`). The machine's one service, `conveyor-machine`
(`conveyor.sh machine`), keeps a loop running for every record. `conveyor.sh install-service` installs it: a systemd
user unit on Linux, a launchd agent on macOS. Install it while no card is in flight.

When the service already runs, `install-service` writes its file on the project's commit. If the running service is
on an older commit, `install-service` starts it again on the new one: `systemctl --user restart` on Linux, `launchctl
bootout` and `launchctl bootstrap` on macOS. The restart stops every project's loop and the cards in flight. Conveyor
picks those cards again, and their work is kept. Then `install-service` checks the commit that the service runs. It
prints `the machine's Conveyor runs Conveyor commit <commit> now`. If the service is not on the new commit, it prints
why and where the service's log is, and it exits with an error. Setup and `conveyor.sh take` do the same when they move
the project to a newer commit than the service's. Setup does this before it writes a new field in the pack. An older
Conveyor does not know a new field, and it does not run a project whose pack has one. When the service runs a
command such as `take` itself, the command does not stop the service. It prints the `install-service` command to run.

If the service runs a Conveyor that does not read the pack, its log names each field it does not know and the
project's commit. `doctor` prints a `missing:` line, and the Board's Health shows "Conveyor's version" as "Too old for
the pack". Each tells you to run `conveyor.sh install-service` in the project's checkout.

Setup's last question is "Start Conveyor now as this machine's service?". Yes runs `install-service`. Beside it,
when the Board is not running, setup asks "Start the Board now?". A Board that runs an older release than the
project is not asked about: setup starts it again on the project's release. Yes runs `conveyor.sh board`, which starts the
[Board](board.md) as this machine's user service. It asks for no password: **No login on this device** lets you in
from this machine. When that setting is off and no admin has a password, setup asks you for one in Claude Code's
prompt and gives it to `conveyor.sh board` in a file that it deletes. To log in from another device, add a user on the
Board's account page. To start either one later,
run `/conveyor-belt:setup` again in your project's checkout and answer yes.

`doctor` names the Board's address when it runs. When it does not run, `doctor` prints a `warning:` line with the fix.

The Board makes its certificate again each time it starts and finds the certificate missing or damaged. It writes one
line to its log that says so. A browser that trusted the old certificate shows a warning once for the new one.

When Conveyor runs on a build machine, the host file names it with `ssh` and a `host` that is not this machine. If a
record has your project's name (the name of its checkout's folder), `doctor` prints `ok: the project <name> is served
on the build machine <host>`. That record's `main` is the checkout on the build machine, so `doctor` prints no
`missing:` line for this checkout. Do not add a record for this checkout: Conveyor on this machine would then run a
second loop on the same repository. Setup does not ask to start Conveyor as this machine's service. It says once that
Conveyor for this project runs on the build machine.

Before it adds the project to the host file, setup writes the project's control record. By default, new issues start
held, and each issue that is open at setup is held. Thus the first loop builds nothing: it does not queue the backlog
of the project. Setup and `conveyor.sh doctor` say
"N open issues held; release one with `conveyor.sh control release <issue>` or on the Board". To let new issues go into the Queue by themselves, run `conveyor.sh control start queue`.
A second setup does not change the record ([The control record](configuration.md#the-control-record)).

Each project keeps its own pack, pin, checkout, state folder, control record, issue repo and push. Its cards folder is
`conveyor-cards` beside its checkout, or `conveyor-cards-<repo>` when another project shares that folder
(`conveyor-cards-<repo>-2` and on after that). Pausing or capping a project touches only that project.

The host file holds the machine's settings. Each is unset by default:

- `cap`: the most cards that build, review or test at once on this machine, across every project. Projects with work
  waiting take the free slots in turn.
- `"mode": "pause"` pauses every project. `conveyor.sh machine pause` and `machine resume` write it, and so does the
  Board's machine head.
- `testSlots`: the size of the machine's pool of test slots, one core each (`conveyor/README.md`, Test slots).
- `reserveCores`: 0 when unset. The cores that card work never uses, so that you always have free cores. A number
  keeps that many of the highest-numbered cores, and a list of core numbers keeps those cores
  ([Cores kept for you](configuration.md#cores-kept-for-you)).

None of these stops a card that already runs. While the host file is there and cannot be read, no new card starts.
Conveyor ignores `maxLoad`, `minFreeMemMB` and `pressure` in the host file. No card or test waits for the machine's
load, pressure or free memory. `conveyor.sh doctor` warns when the host file still sets one of them.
`conveyor.sh doctor` names a second loop that runs beside the machine's.

## Troubleshooting

A card is blocked with `tests: node_modules is missing in the card's worktree; add it to linkFromMain or set
worktree.setup`: your checkout has that dependency folder, and the card's worktree does not. Add the folder to the
pack's `linkFromMain`, or set `worktree.setup` to the command that installs it ([Configuration](configuration.md#the-pack)).
`conveyor.sh doctor` makes a test worktree and names each folder that is missing there, with the same fix.

`/plugin install conveyor-belt@conveyor-belt` fails with `git@github.com: Permission denied (publickey)`: release
1.1.0 and older clone the plugin over SSH, and this machine has no GitHub SSH key. Run this command once, then install
again. Git then fetches the plugin over HTTPS:

```sh
git config --global url."https://github.com/pushprove-max/conveyor-belt".insteadOf "git@github.com:pushprove-max/conveyor-belt"
```

## Uninstall

1. Stop the loop: `systemctl --user disable --now conveyor-machine.service` on Linux, or
   `launchctl bootout gui/$(id -u)/conveyor-machine` on macOS. Then delete that unit or agent file
   (`install-service` printed its path).
2. Stop the Board: `systemctl --user disable --now dashboard.service` on Linux, then delete
   `~/.config/systemd/user/dashboard.service`; or `launchctl bootout gui/$(id -u)/com.conveyor.dashboard` on macOS,
   then delete `~/Library/LaunchAgents/com.conveyor.dashboard.plist`.
3. Remove the plugin: `/plugin uninstall conveyor-belt@conveyor-belt` in Claude Code.
4. Remove the installed commits (they are read-only) and the host file:

   ```sh
   chmod -R u+w ~/.local/share/conveyor && rm -rf ~/.local/share/conveyor ~/.config/conveyor
   ```

5. In your project, delete `.conveyor/`, the `conveyor/state` folder and the `conveyor-cards` (or
   `conveyor-cards-<repo>`) folder beside the checkout. The labels that setup created stay on GitHub until you delete
   them.
