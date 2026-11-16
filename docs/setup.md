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
- For the Board, an `openssl` whose `req` takes `-addext` (OpenSSL 1.1.1 or newer). It makes the Board's certificate.
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
commit is not installed on this machine, the guards are off, and each session shows one line that says so until
setup installs the commit.

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
- `claudeProxy`: the API proxy for Claude's sessions, and when they use it
  ([Configuration](configuration.md#the-control-record)). Setup writes it when it finds a local proxy (below).

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

Each time it runs, setup also asks if you want a fast lane and a research lane ([Lanes](lanes.md)). On yes, it makes
the lane, or keeps the lane that is already there.

Setup also looks for a local API proxy. This is a proxy that listens on this machine, for example on port 4141. For
Claude, it must answer the Anthropic Messages API, and setup looks only when no `claudeProxy` is set. For Codex, it
must answer the OpenAI Responses API, and setup looks only when Codex is installed and no `codexProxy` is set. When it
finds a proxy, setup checks the CLI's own login and asks which route each role uses, the builder (`--builder-route`)
and the reviewer (`--reviewer-route`):

- `fallback`: the role's sessions run on the CLI's own login. When that login fails before the session starts its
  work, the same step runs again at once through the proxy.
- `proxy`: the role's sessions always run through the proxy.
- `subscription`: the role's sessions never run through the proxy.

If both roles are `subscription`, setup writes nothing, and asks again on its next run. Otherwise it writes each proxy
it found in the host file, with each role's route: `claudeProxy` for Claude, and `codexProxy` for Codex. Each has the
proxy's base URL and the name of the variable that holds the proxy's key: `CLAUDE_PROXY_KEY` or `CODEX_PROXY_KEY`.
Setup never writes the key. If the proxy needs a key, set that variable in the environment that Conveyor runs in.
Conveyor gives `codexProxy` to each Codex session as Codex's own provider settings, and does not change Codex's
`config.toml`.

Then setup writes the pack, sets the project to follow the plugin's releases, installs the newest release, adds the
project to the host file, adds `/conveyor/state/` to `.git/info/exclude` so that git does not list the state folder,
creates the labels the pack names and runs `conveyor.sh doctor`. It gives the command that
commits the pack, `.conveyor/project.json`. Commit it on your default branch. `doctor` prints one `ok:` line for each thing in place. It prints a
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
`conveyor.sh setup [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] --fast-lane yes|no --research-lane yes|no [--builder-route subscription|fallback|proxy] [--reviewer-route subscription|fallback|proxy] [--pin] [--foreman]`,
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

Setup's last question is "Start Conveyor now as this machine's service?". Yes runs `install-service`. Beside it,
when the Board is not running, setup asks "Start the Board now?". Yes runs `conveyor.sh board`, which starts the
[Board](board.md) as this machine's user service. It asks for no password: **No login on this device** lets you in
from this machine. When that setting is off and no admin has a password, setup asks you for one in Claude Code's
prompt and gives it to `conveyor.sh board` in a file that it deletes. To log in from another device, add a user on the
Board's account page. To start either one later,
run `/conveyor-belt:setup` again in your project's checkout and answer yes.

`doctor` names the Board's address when it runs. When it does not run, `doctor` prints a `warning:` line with the fix.

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
- `maxLoad` and `minFreeMemMB`: no new card starts while the 1-minute load is above `maxLoad`, or the free memory (MB)
  is below `minFreeMemMB`. The Board shows the next card as "waiting for machine room". The Board's Tests page sets
  `maxLoad` as **Load limit** (`conveyor.sh machine load <number | off>`).
- `"mode": "pause"` pauses every project. `conveyor.sh machine pause` and `machine resume` write it, and so does the
  Board's machine head.
- `testSlots`: the size of the machine's pool of test slots, one core each (`conveyor/README.md`, Test slots).

None of these stops a card that already runs. While the host file is there and cannot be read, no new card starts.
`conveyor.sh doctor` names a second loop that runs beside the machine's.

## Troubleshooting

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
