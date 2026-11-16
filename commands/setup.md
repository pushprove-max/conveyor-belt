---
description: Set up Conveyor Belt in this project (the pack, the plugin releases or main it follows or the commit it pins, its install, the Board's virtualenv, the labels, a first test-speed survey if wanted, the host file's record), then check this machine with conveyor doctor, offer to write a missing CLAUDE.md or AGENTS.md, and start Conveyor and the Board as this machine's services if wanted; with --foreman, also set up Foreman mode; with --survey, ask again whether to run a test-speed survey
argument-hint: "[--foreman] [--pin] [--survey]"
allowed-tools: Bash, AskUserQuestion, Read, Glob, Grep, Write
---

Set up Conveyor Belt in the project checkout this session runs in. Run every command from that checkout.
The arguments given were: `$ARGUMENTS`. When they hold `--foreman`, add `--foreman` to every setup command below
(it is safe to run again: it rewrites only the Foreman's own settings and never its saved state). When they hold
`--pin`, add `--pin` to every setup command below: a new project is then pinned to this plugin copy's commit instead of
following the plugin's releases. When they hold `--survey`, ask the user "Run a first test-speed survey now?" (yes / no)
before step 1, and add `--survey yes` or `--survey no`, as answered, to every setup command below.

1. Run `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" setup`.
   - When it exits 2 naming what setup needs (`--owner`, `--product`, `--test`, `--survey`, `--fast-lane`,
     `--research-lane`), ask the user for exactly those, and nothing else: whose yes a change customers or staff will
     see needs; the path prefixes of product code; the command that runs a change's tests; "Run a first test-speed
     survey now?" (yes / no); "Make a fast lane (your own worktree for changes made by hand)?" (yes / no); "Make a
     research lane (a read-only sandboxed worktree)?" (yes / no). Then run it again with the answers, each `--product`
     once per path, `--survey yes` or `--survey no`, `--fast-lane yes` or `--fast-lane no`, `--research-lane yes` or
     `--research-lane no`, every value quoted for the shell.
   - Any other failure: show its message, then go on to step 2, where doctor names what is missing and its fix.
2. Run `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" doctor` and show its output.
3. When `git status --porcelain -- .conveyor/project.json` prints a line (the pack is not committed, or setup changed
   it since its commit), give the user the
   one command that commits it, on the default branch: `git add .conveyor/project.json && git commit -m "Add the
   Conveyor pack"`. Do not run it yourself.
4. For each `missing: CLAUDE.md` or `missing: AGENTS.md` line doctor printed, ask the user "Write an optimized
   CLAUDE.md (or AGENTS.md) for this project?" (yes / no). On no, write nothing. On yes, write that file at the root of
   this checkout, and only when no file or link of that name is there; never overwrite or edit a file that is there.
   Write it from the project itself, reading its code, its README and docs, and the pack `.conveyor/project.json`:
   what the project is, its layout, its languages, how and where its tests run (the pack's `test.command` and
   `test.full`), its conventions, and where its deeper docs live. Keep only what a session cannot learn from the code,
   give each rule its reason, use plain statements, and copy no other file's text: name the file instead.
   `CLAUDE.md` is read by the builder, the fixer, the Foreman and the lanes; `AGENTS.md` is read by the Codex reviewer
   and names `CLAUDE.md` for the project's content (read it first) rather than repeating it, adding only what a
   reviewer needs beyond it. Show each file you wrote, and give the user the one command that commits it, on the
   default branch: `git add CLAUDE.md AGENTS.md && git commit -m "Add the agent instruction files"` (naming only
   the files you wrote). Do not run it yourself.
5. When doctor printed no `missing:` line other than the `CLAUDE.md` and `AGENTS.md` ones, ask the user "Start Conveyor now as this machine's service?" (yes / no)
   and, beside it, when doctor printed the `warning: the Board is not running` line, "Start the Board now?" (yes / no).
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
6. Reply with what setup changed (its `wrote`, `follows`, `took`, `pinned`, `installed`, `created`, `filed` and `saved` lines; none means it was already set up; or the failure it showed), doctor's line "N open issues held; release one with
   `conveyor.sh control release <issue>` or on the Board", and each `missing:` line
   doctor printed, with its fix, the Board's address (the `the Board runs` line of step 5, or doctor's Board line), and each instruction file you wrote. List the lanes setup made (its `created: the fast lane` and `created: the research
   lane's worktree` lines), with the command that starts the research lane when setup printed one. Make no change of your own to the pack, the pin or the labels. With `--foreman`, add
   that the Foreman is started by typing `/conveyor-belt:foreman` in a Claude Code session in this checkout (it stays
   the Foreman when continued, resumed or cleared with `/clear`; `/conveyor-belt:foreman off` ends it), that it is this project's Foreman
   only (another project gets its own by this same setup in its own checkout), and that the launcher
   `conveyor.sh foreman` (which sets `CONVEYOR_FOREMAN=1`) remains an advanced option. End the reply with one line:
   landed cards wait for "Push landed" on the Board until push is turned on in the Rules tab.
