---
description: Set up Conveyor Belt in this project (the pack, the plugin releases or main it follows or the commit it pins, its install, the Board's virtualenv, the labels, a first test-speed survey if wanted, Serena for card sessions if wanted, the host file's record), then check this machine with conveyor doctor, offer to write a missing CLAUDE.md or AGENTS.md, and start Conveyor and the Board as this machine's services if wanted; with --foreman, also set up Foreman mode; with --survey, ask again whether to run a test-speed survey
argument-hint: "[--foreman] [--pin] [--survey]"
allowed-tools: Bash, AskUserQuestion, Read, Glob, Grep, Write
---

Set up Conveyor Belt in the project checkout this session runs in. Run every command from that checkout.
The arguments given were: `$ARGUMENTS`. When they hold `--foreman`, add `--foreman` to each run of step 1's setup command
(it is safe to run again: it rewrites the Foreman's own settings and sets the 1-hour prompt cache in this checkout's `.claude/settings.local.json`, keeping that file's other keys, and never touches the Foreman's saved state). When they hold
`--pin`, add `--pin` to each run of step 1's setup command: a new project is then pinned to this plugin copy's commit instead of
following the plugin's releases. When they hold `--survey`, ask the user "Run a first test-speed survey now?" (yes / no)
before step 1, and add `--survey yes` or `--survey no`, as answered, to each run of step 1's setup command. Add none of these to
`setup pack-commit` in step 3: it takes no other argument.

When `.conveyor/project.json` is not there, or has no `lint` field, ask the user "Which command lints the project, and
which files does it read?" (a command and its git pathspecs / none) before step 1. With a command, add
`--lint <command>` and `--lint-files <pathspec>`, once per pathspec, each quoted for the shell, to each run of step 1's
setup command. Show setup's line for it: setup tries the command and writes it only when the result is `ok` or
`findings: <n>`. For `missing`, `error` or `empty` the line says why it was not written; for `error`, it says the command
needs a wrapper script. Show setup's lines for the ready lint entries too: the entries and the `lint.policy` it wrote,
the one line that names the complexity rules, and the line for a language with no ready entry.

When `.conveyor/project.json` is not there, or has no `lint` field, also ask the user "Limit the length of files?" (the
most lines a file may have / no), and with a limit, the git pathspecs of the files it reads and "Which folders do you
leave out?" (folders / none), before step 1. Add `--size <lines>` or `--size no`, `--size-files <pathspec>` once per
pathspec and `--size-skip <folder>` once per folder, each quoted for the shell, to each run of step 1's setup command.
Show setup's line for the size entry: it names the exempt file `.conveyor/size-exempt.txt`, which step 3 commits
with the pack.

When `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" control` fails, or prints a record whose `rules.serena` is empty
or missing, ask the user "Use Serena for code search in card sessions? Setup installs it when it is missing." (yes /
no) before step 1, and add `--serena yes` or `--serena no`, as answered, to each run of step 1's setup command. Show
setup's lines for it: with yes it installs Serena with `uv tool install serena-agent` when Serena is missing, then sets
the rule Serena to build, fix and testfix; with no `uv`, or with uv's folder not on PATH, its line says what to do and
the rule stays off. Card sessions always start Serena with its web dashboard off; do not change
`~/.serena/serena_config.yml` here.

First install the requirements, then sign in, before step 1:

- Run `bash "${CLAUDE_PLUGIN_ROOT}/conveyor/lib/requires.sh" install` and show its output. It installs each requirement
  that is missing or below its minimum version (docs/setup.md, Requirements), with Homebrew on macOS and the system's
  package manager on Linux. When it exits 3, sudo needs this user's password: ask the user for it with
  AskUserQuestion (they type it as their own answer). Make a private folder with `mktemp -d`, write the password as the
  one line of a file `pw` in it with the Write tool, run the same command with `--password-file <that folder>/pw`
  (it deletes the file), then remove the folder. When it exits 3 again (sudo refused the password), ask again. Never
  put the password in a command, and never show it. On any other failure, show its message (it names the requirement
  and why) and stop: setup does not go on without its requirements. Never give the user commands to run instead.
- Sign in where a CLI is not signed in, each by the CLI's own login, run in the background with its output shown to
  the user as it comes (the address and code to open), waiting for it to end. Run each of these commands as
  `bash "${CLAUDE_PLUGIN_ROOT}/conveyor/lib/requires.sh" run <command>`, so it finds a CLI the install put in
  Homebrew's folder: when `gh auth status` fails, run
  `gh auth login --hostname github.com --git-protocol https --web`; when `claude auth status` fails, run
  `claude auth login`; when `codex login status` fails, run `codex login`. When a login fails, show its output, say
  which CLI is not signed in, and go on.

1. Run `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" setup`.
   - When it exits 2 naming what setup needs (`--owner`, `--product`, `--test`, `--survey`, `--test-patterns`, `--file-command`, `--test-map`, `--fast-lane`,
     `--research-lane`, `--link`, `--lint-ready`, `--lint-shared`, `--builder-route`, `--reviewer-route`, `--fallback-route`, `--claude-proxy`,
     `--codex-proxy`, `--claude-key`, `--codex-key`, `--claude-proxy-key`, `--codex-proxy-key`), ask
     the user for exactly those, and nothing else: whose yes a change customers or staff will
     see needs; the path prefixes of product code; the command that runs a change's tests; "Run a first test-speed
     survey now?" (yes / no); "Write these test-file patterns in the pack?" (yes / no), with the patterns and the count
     of tracked files that setup named; "Set the pack's test.fileCommand to the test command, so a card runs each of
     its test files alone through it?" (yes / no), with the runner that setup named; "Run the whole suite once under coverage to make the test map?" (yes / no), with
     the tool and the time that setup named; "Make a fast lane (your own worktree for changes made by hand)?" (yes / no); "Make a
     research lane (a read-only sandboxed worktree)?" (yes / no); "Link these dependency folders into each card's
     worktree?", showing the folders and the lockfiles setup named (yes / no / install them in each worktree with a
     command instead, such as `npm ci`: then pass `--worktree-setup <command>` in place of `--link`); "Write the ready
     lint entries for these tools?" (yes / no), with the tools and config files that setup named; "Put pyproject.toml,
     which holds ruff's config, in the pack's lint.policy?" (yes / no); "Which route does the builder use?" and "Which route
     does the reviewer use?", each offering only the routes that setup offered, with the routes and states that setup
     named (fallback: the CLI's own login first, the second route when it fails / proxy: always the local proxy / api:
     always the provider's API with your own key / subscription: the CLI's own login only); "Which second route does
     a fallback take?" (proxy / api); "Which local proxy does Claude (or Codex) go through?" (each base URL that setup
     named); "Where is your Anthropic (or OpenAI) API key kept?" (nowhere, I use no API key, when setup offers none /
     in the env of Claude Code's settings file, as setup named it / in a key file); "Where is the key of Claude's (or Codex's)
     local proxy kept?" (in the env of Claude Code's settings file / in a key file). For a key file, ask the user for the key with
     AskUserQuestion (they type it as their own answer). Make the folder with
     `mkdir -p -m 700 "${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/keys"`, write the key as the one line of the file
     `anthropic.key` (or `openai.key`, `claude-proxy.key`, `codex-proxy.key`) in it with the Write tool, then run `chmod 600` on that file. Never put the key
     in a command, and never show it. Then run it again
     with the answers, each `--product` once per path, `--survey yes` or `--survey no`, `--test-patterns yes` or
     `--test-patterns no`, `--file-command yes` or `--file-command no`, `--test-map yes` or `--test-map no`, `--fast-lane yes` or
     `--fast-lane no`, `--research-lane yes` or `--research-lane no`, `--link yes`, `--link no` or
     `--worktree-setup <command>`, `--lint-ready yes` or `--lint-ready no`, `--lint-shared yes` or `--lint-shared no`,
     `--builder-route` and `--reviewer-route` each
     `fallback`, `proxy`, `api` or `subscription`, `--fallback-route proxy` or `--fallback-route api`,
     `--claude-proxy` or `--codex-proxy` each the base URL chosen, and `--claude-key` or `--codex-key` each `none`,
     `settings` or the key file's path, `--claude-proxy-key` or `--codex-proxy-key` each `settings` or the key
     file's path, every value quoted for the shell.
   - When it exits 1 naming a key file (a mode that lets others read it, or no file there), or a key that is not in
     the settings file, show its message and ask the same question again.
   - When it ends 0 and says the project has no `.conveyor/test-machine.sh`, ask the user "Write a
     `.conveyor/test-machine.sh` from the pack's test commands, for a release suite that runs on an ssh box or a
     Namespace devbox?" (yes / no), then run setup again with `--test-machine yes` or `--test-machine no` and the same
     answers, but not `--survey`: the run that ended 0 saved that answer, and `--survey yes` again files a second survey issue. Tell the user that the script installs nothing yet: the project must finish it and commit it.
   - Any other failure: show its message, then go on to step 2, where doctor names what is missing and its fix.
2. Run `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" doctor` and show its output.
3. Run `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" setup pack-commit`. It checks the pack and the exempt files of its
   size entries itself, and prints `ok:` when they are committed and no change is waiting. When it exits 1 (the
   default branch is not checked out, or the pack has a conflict), show its message and ask nothing more about the
   pack. When it prints an `ask:` line, ask the user that question with AskUserQuestion ("Commit the Conveyor pack
   (.conveyor/project.json) on <default branch> now?", yes / no), with the change it printed shown in the question.
   On yes, run `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" setup pack-commit yes`; on no, run
   `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" setup pack-commit no`. Show its output: it says what it committed and
   pushed, or that the pack is not committed and stays on this machine, as cards read the pack from the default
   branch. Never ask the user to type a git command for the pack.
4. For each `missing: CLAUDE.md` or `missing: AGENTS.md` line doctor printed, ask the user "Write an optimized
   CLAUDE.md (or AGENTS.md) for this project?" (yes / no). On no, write nothing. On yes, write that file in the folder
   the `missing:` line names after "at the root of" (the main checkout, which doctor checks; from a linked worktree it
   is not this checkout), and only when no file or link of that name is there; never overwrite or edit a file that is there.
   Write it from the project itself, reading its code, its README and docs, and the pack `.conveyor/project.json`:
   what the project is, its layout, its languages, how and where its tests run (the pack's `test.command` and
   `test.full`), its conventions, and where its deeper docs live. Keep only what a session cannot learn from the code,
   give each rule its reason, use plain statements, and copy no other file's text: name the file instead.
   `CLAUDE.md` is read by the builder, the fixer, the Foreman and the lanes; `AGENTS.md` is read by the Codex reviewer
   and names `CLAUDE.md` for the project's content (read it first) rather than repeating it, adding only what a
   reviewer needs beyond it. Show each file you wrote, and give the user the one command that commits it, on the
   default branch, in that folder: `git -C <that folder> add CLAUDE.md AGENTS.md && git -C <that folder> commit -m
   "Add the agent instruction files" -- CLAUDE.md AGENTS.md` (naming only the files you wrote, both times; the paths
   after `--` keep out anything else staged in that folder). Do not run it yourself.
5. When doctor printed no `missing:` line other than the `CLAUDE.md` and `AGENTS.md` ones, ask the user "Start Conveyor now as this machine's service?" (yes / no)
   and, beside it, when doctor printed the `warning: the Board is not running` line, "Start the Board now?" (yes / no).
   But when doctor printed an `ok: the project <name> is served on the build machine <host>` line, do not ask the
   first question and do not run `install-service`, as a service here would be a second Conveyor on the same
   repository: say once that Conveyor for this project runs on the build machine `<host>`.
   On yes to the first, run `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" install-service` and show its output. On
   yes to the second, run `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" board` and show its output: it asks for no
   password, as "No login on this device" lets this machine in; an admin password for other devices is set later on
   the Board. When it stops with `"No login on this device" is off and no dashboard admin has a usable password`, ask
   the user with AskUserQuestion for a password for the Board's admin `admin` (they type it as their own answer; when
   board refuses it, it says why: ask again). Make a private folder with `mktemp -d`, write the
   password as the one line of a file `pw` in it with the Write tool, and run
   `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" board --password-file <that folder>/pw`, which deletes the file,
   gives the admin `admin` the password (adding it when it is not a user) and starts the Board; then remove the folder. Never put the password in a command, and never show it
   again. Never ask the user to run a command with `!` to finish setup. On no, say that running
   `/conveyor-belt:setup` again in this checkout asks again and starts it on yes.
6. Reply with what setup changed (its `wrote`, `follows`, `took`, `pinned`, `installed`, `set`, `created`, `filed` and `saved` lines; none means it was already set up; or the failure it showed), doctor's line "N open issues held; release one with
   `conveyor.sh control release <issue>` or on the Board", and each `missing:` line
   doctor printed, with its fix, the Board's address (the `the Board runs` line of step 5, or doctor's Board line), and each instruction file you wrote. List the lanes setup made (its `created: the fast lane` and `created: the research
   lane's worktree` lines), with the command that starts the research lane when setup printed one. Make no change of your own to the pack, the pin or the labels. With `--foreman`, add
   that the Foreman is started by typing `/conveyor-belt:foreman` in a Claude Code session in this checkout (it stays
   the Foreman when continued, resumed or cleared with `/clear`; `/conveyor-belt:foreman off` ends it), that it is this project's Foreman
   only (another project gets its own by this same setup in its own checkout), and that the launcher
   `conveyor.sh foreman` (which sets `CONVEYOR_FOREMAN=1`) remains an advanced option. End the reply with one line:
   landed cards wait for "Push landed" on the Board until push is turned on in the Rules tab.
