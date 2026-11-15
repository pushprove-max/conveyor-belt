---
description: Set up Conveyor Belt in this project (the pack, the plugin releases or main it follows or the commit it pins, its install, the Board's virtualenv, the labels, a first test-speed survey if wanted, the host file's record), then check this machine with conveyor doctor and start Conveyor as its service if wanted; with --foreman, also set up Foreman mode; with --survey, ask again whether to run a test-speed survey
argument-hint: "[--foreman] [--pin] [--survey]"
allowed-tools: Bash, AskUserQuestion
---

Set up Conveyor Belt in the project checkout this session runs in. Run every command from that checkout.
The arguments given were: `$ARGUMENTS`. When they hold `--foreman`, add `--foreman` to every setup command below
(it is safe to run again: it rewrites only the Foreman's own settings and never its saved state). When they hold
`--pin`, add `--pin` to every setup command below: a new project is then pinned to this plugin copy's commit instead of
following the plugin's releases. When they hold `--survey`, ask the user "Run a first test-speed survey now?" (yes / no)
before step 1, and add `--survey yes` or `--survey no`, as answered, to every setup command below.

1. Run `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" setup`.
   - When it exits 2 naming what setup needs (`--owner`, `--product`, `--test`, `--survey`), ask the user for exactly
     those, and nothing else: whose yes a change customers or staff will see needs; the path prefixes of product code;
     the command that runs a change's tests; "Run a first test-speed survey now?" (yes / no). Then run it again with
     the answers, each `--product` once per path, `--survey yes` or `--survey no`, every value quoted for the shell.
   - Any other failure: show its message, then go on to step 2, where doctor names what is missing and its fix.
2. Run `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" doctor` and show its output.
3. When `git status --porcelain -- .conveyor/project.json` prints a line (the pack is not committed, or setup changed
   it since its commit), give the user the
   one command that commits it, on the default branch: `git add .conveyor/project.json && git commit -m "Add the
   Conveyor pack"`. Do not run it yourself.
4. When doctor printed no `missing:` line, ask the user "Start Conveyor now as this machine's service?" (yes / no).
   On yes, run `"${CLAUDE_PLUGIN_ROOT}/conveyor/conveyor.sh" install-service` and show its output. On no, say that
   running `/conveyor-belt:setup` again in this checkout asks again and starts it on yes.
5. Reply with what setup changed (its `wrote`, `follows`, `took`, `pinned`, `installed`, `created`, `filed` and `saved` lines; none means it was already set up; or the failure it showed) and each `missing:` line
   doctor printed, with its fix. Make no change of your own to the pack, the pin or the labels. With `--foreman`, add
   that the Foreman is started by typing `/conveyor-belt:foreman` in a Claude Code session in this checkout (it stays
   the Foreman when continued or resumed; `/conveyor-belt:foreman off` ends it), that it is this project's Foreman
   only (another project gets its own by this same setup in its own checkout), and that the launcher
   `conveyor.sh foreman` (which sets `CONVEYOR_FOREMAN=1`) remains an advanced option. End the reply with one line:
   landed cards wait for "Push landed" on the Board until push is turned on in the Rules tab.
