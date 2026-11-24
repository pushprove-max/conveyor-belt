#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Conveyor: one issue = one card. Pick, build in a fresh worktree, review, land, record.
# The state is in the state folder (`conveyor.sh state-dir`), its files and its database as state.py's header says;
# `conveyor.sh snapshot` reads it out for the Board.
# Usage: the command table below; `conveyor.sh` with no command, or with one the table does not hold, prints it.
# The rules are in README.md beside this script: the review rule, a landing conflict, an issue already fixed, the
# changed tests, a visible change, the push, land-branch, a blocked card's kept work, the marks, the live record, the
# stream, the control record and what is measured. The large jq programs are in jq/.
# Approve before build. A product issue may hold a section headed `## What customers or staff
# will see`: the screen, message or document, what it shows today and what it will show; or the one line `Nothing
# visible changes.` An issue whose section names a change and has no `Visible change approved:` line is not picked: it
# waits in "Needs you" to be approved before the build. Once approved, the build is held to that section, no more and
# no less: for a card that touches product code, the reviewer answers on the USER-VISIBLE line whether what the change
# shows matches it. A match lands with no second ask; any difference (more, less or other, wording included) stops the
# card with its patch kept, and the ask names the difference only. An issue with no section, or whose section says
# nothing visible changes, stops after review for the owner's yes when its change is visible, as before.
# All of this holds while the control record's rule "visible changes need the owner's yes" (rules.visible) is on (it is
# off by default, lib/control-defaults.json); off, no issue or card waits for an approval line and no brief or review asks for one (yesrule()).
set -uo pipefail
# The environment Conveyor was started with, taken before any variable of its own can shadow a name in it: a proxy's
# key is read from here by the variable name the user gave (proxyenv, codexmodel), whatever the engine's locals are called.
# `envof <name>` prints that variable's value as it was. The snapshot is kept in the function's own body, not in a
# variable, so no variable of the user's is taken or unset for it and every one still reaches the commands the engine
# runs (codex exec among them); it is not exported, so a variable proxyenv drops is not handed on inside it.
envof() {
  local -A e=(); local x d; while IFS= read -r -d '' x; do e[${x%%=*}]=${x#*=}; done; d=$(declare -p e)
  eval "envof() { local ${d#declare }
printf %s \"\${e[\$1]-}\"; }"; export -nf envof
}
envof < <(env -0)
# This script's folder, by bash's own text handling, not a dirname program (one started per command adds up); a path
# with no slash is in the current folder.
HERE=.; [[ ${BASH_SOURCE[0]} != */* ]] || HERE=${BASH_SOURCE[0]%/*}; HERE=$(cd "$HERE" && pwd -P)
# bash 5.1 for `wait -n -p`, run again in the bash first on PATH when this one is older; flock, and on macOS the GNU
# tools and Homebrew's copies first on PATH (lib/portable.sh, plan section 4). The service and the Board are started
# with this PATH and this bash.
. "$HERE/lib/portable.sh" && p_path && p_bash 5.1 "$HERE/conveyor.sh" "$@" && p_tools || exit 1
exec {LOGFD}>&2 # the engine's own stderr: gh_write's privacy warnings, whatever a caller does with its stderr
# Every git the engine runs, without the loop's run lock (fd 8): the project's hooks git starts (pre-commit, post-checkout,
# reference-transaction...) are not the loop, and one given the lock could pass it on to a second loop (run()).
git() { command git "$@" 8>&-; }
# The engine, one file a concern under lib/. Every command runs these two first: the main checkout, the installs, the
# host file, the state and cards folders, the accounts (paths.sh); the state folder made, the move into the main
# checkout, the record lines (records.sh). The command's script (commands/, below) then sources the other engine files
# it uses, each in this order, into this one shell: slots, busy, prompts, control, views, snapshot, issues, pick, session,
# review, testrun, claim, push, followups, flaky, fulltest, testaction, testfiles, mutate, testrules, survey, card, lane, run,
# machine, install, setup, requires, lint.
. "$HERE/lib/paths.sh" || exit 1
. "$HERE/lib/records.sh" || exit 1
# The command table, one line a command: `cmd <command> <its script under commands/> <its part of the usage message>`
# (- for a command the message leaves out). The line of the command given runs its script, in this shell, with this
# script's arguments; with no command, or one no line names, the usage message is built from the lines, in order.
CMD_RUN=; CMD_USAGE=
cmd() { [ "$3" = - ] || CMD_USAGE+=${CMD_USAGE:+ | }$3; [ "$1" != "${CMD_ARG-}" ] || CMD_RUN=$2; }
CMD_ARG=${1:-}
cmd run run.sh 'run [--only <issue>[,<issue>...]] [max-cards]'
cmd serve serve.sh 'serve'
cmd land-branch land-branch.sh 'land-branch <branch>'
cmd retry retry.sh 'retry <issue [--fresh] | card id>'
cmd shut shut.sh 'shut <issue [--closed] | card id>'
cmd unblock unblock.sh 'unblock <issue> --hold'
cmd parts parts.sh 'parts <parent> <issue>...'
cmd control control.sh 'control [<action>]'
cmd check check.sh 'check'
cmd cards cards.sh 'cards'
cmd health health.sh 'health'
cmd snapshot snapshot.sh 'snapshot [--fresh]'
cmd history history.sh 'history [test <test file> | donewhen <card id> | excerpts <card id>]'
cmd clis clis.sh 'clis'
cmd state-dir state-dir.sh 'state-dir'
cmd pick pick.sh 'pick --dry --issues <file> --state <dir> | pick replay judge <model> [<effort>] [--last <n>] [--estimate] | pick models <builder|reviewer|judge> <<model>[=<min>-<max>]... | clear>'
cmd gh-write gh-write.sh 'gh-write <gh arguments>'
cmd product product.sh 'product <sha>'
cmd pushable pushable.sh 'pushable'
cmd install install.sh 'install <commit>'
cmd take take.sh 'take [wait|stale]'
cmd install-service install-service.sh 'install-service'
cmd board board.sh 'board [--password-file <file>]'
cmd machine machine.sh 'machine [pause | resume]'
cmd why why.sh 'why <pid | name> [--json]'
cmd work work.sh 'work [--json]'
cmd bench bench.sh 'bench drift [<engine commit>] | bench swe <1-500> [--arm <arm>]... [--solo] [--engine <version | commit>] | bench swe arms [check <arm>...] | bench swe arms save <name> <spec json> | bench swe arms show <id> | bench swe stop [<run id>] | bench swe results [--json] | bench swe diff <A> <B> [--json] | bench swe versions'
cmd setup setup.sh 'setup [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] [--test-patterns yes|no] --fast-lane yes|no --research-lane yes|no [--link yes|no] [--worktree-setup <command>] [--lint <command> --lint-files <pathspec>...] [--lint-ready yes|no] [--lint-shared yes|no] [--size <lines>|no] [--size-files <pathspec>]... [--size-skip <folder>]... [--builder-route subscription|fallback|proxy|api] [--reviewer-route subscription|fallback|proxy|api] [--fallback-route proxy|api] [--claude-key none|settings|<key file>] [--codex-key none|settings|<key file>] [--claude-proxy <base URL>] [--codex-proxy <base URL>] [--pin] [--foreman]'
cmd setup setup.sh 'setup pack-commit [yes | no]'
cmd doctor doctor.sh 'doctor'
cmd lint lint.sh 'lint'
cmd precheck precheck.sh 'precheck [<issue> <reply file>]'
cmd size size.sh 'size --list'
cmd wording wording.sh 'wording adversarial | review'
cmd auto auto.sh 'auto on | narrow | off | status | band | rules | decide | rulings | send | standing [<run> | <kind> on|off] | act <kind> <what> | reserved'
cmd foreman foreman.sh 'foreman [status [<project>] | <claude argument>...]'
cmd lane lane.sh 'lane research create | lane fast create | review | land | reset [--drop <sha>]'
cmd flaky flaky.sh 'flaky add <case> <source> <note> | flaky off <case> <source> <note>'
cmd full-test full-test.sh 'full-test [push | anyway <run id> [--by <who>]]'
cmd push-now full-test.sh 'push-now'
cmd pr pr.sh 'pr merge'
cmd release-prep release-prep.sh 'release-prep <version> [--parallel | --serial]'
cmd release release-prep.sh 'release <version> [--anyway] [--allow-commit <sha>]... [--by <who>]'
cmd release-run release-prep.sh 'release-run [prep] <version> [--parallel | --serial] [--machine local] | release-run anyway <version> --by <who> | release-run stop [<version> | <since>] | release-run atonce [--machine local]'
cmd suite-machine suite-machine.sh 'suite-machine check [--json]'
cmd testaction testaction.sh 'testaction <judge | explain [--time <zone> <12-hour | 24-hour>] | run> <test file> | testaction stop <id>'
cmd testissue testaction.sh 'testissue <test file> <title> <body>'
cmd cardissue testaction.sh 'cardissue <card id>'
cmd card testaction.sh 'card [--release <version>] <title> <body>'
cmd mutate testaction.sh 'mutate <test file> | mutate ask <test file>...'
cmd test-settings test-settings.sh 'test-settings <what> [<file>] [<value>]'
cmd prices prices.sh 'prices set <model> <input> <output> <cache read> | prices clear <model>'
cmd testrules testrules.sh -
cmd watch watch.sh -
cmd github github.sh -
cmd main-test main-test.sh -
cmd survey survey.sh -
cmd declined declined.sh -
cmd heals heals.sh 'heals sort | heals batch <area | -> [--held | --queue] [--prio P2|P3] [--title <text>] [<id>...] | heals docs <area | -> [the same] | heals harm <id>... | heals drop <id>...'
cmd testmap testmap.sh 'testmap [build | stop]'
unset -f cmd
[ -n "$CMD_RUN" ] || { echo "usage: conveyor.sh $CMD_USAGE" >&2; exit 2; }
# shellcheck disable=SC1090 # the script is the table's, named at run time
. "$HERE/commands/$CMD_RUN"
