#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the dependencies of a card's worktree (depdirs(), deps(), depsmissing() in lib/push.sh): setup's
# question that fills linkFromMain or worktree.setup, the links and the install in a new worktree, doctor's check, and
# the blocked reason of a card whose tests failed for want of them.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# One engine function, run in an engine shell of the checkout <main> (the runner sources every case file into one
# shell, so each name here at file level is this file's own: wd_).
wd_engine() { # <main> <function> [<argument>...]
  ( export CONVEYOR_MAIN=$1 CONVEYOR_CARDS=$T/$CASE/cards; shift; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && . "$SRC/lib/prompts.sh" && . "$SRC/lib/push.sh" && "$@" )
}
# <checkout>: node_modules at its top and in the workspace package packages/a, both ignored by git and untracked, and
# a tracked lockfile.
wd_folders() {
  mkdir -p "$1/node_modules/left-pad" "$1/packages/a/node_modules/x" && echo 'node_modules/' > "$1/.gitignore" && echo '{}' > "$1/packages/a/package.json" \
    && echo '{}' > "$1/package-lock.json" && git -C "$1" add .gitignore packages/a/package.json package-lock.json && git -C "$1" commit -qm deps \
    || fail "the dependency folders were not made in $1"
}

# Bugs: setup leaves linkFromMain empty in a project with installed dependencies (so every card's tests run without
# them), misses a workspace package's node_modules, writes them without asking, offers no install command when the
# lockfile makes linking unsafe, or rewrites the owner's linkFromMain on a rerun; and a worktree made after it lacks them.
t_workdepsetup() {
  local X out w; sample; X=$D/conveyor/conveyor.sh; wd_folders "$S"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no 2>&1) && fail "setup did not ask about the dependency folders: $out"
  grep -qF -- '--link <yes or no: link the dependency folders of the main checkout (node_modules, packages/a/node_modules) into each card' <<<"$out" \
    && grep -qF 'a lockfile (package-lock.json)' <<<"$out" && grep -qF -- '--worktree-setup with the command that installs them' <<<"$out" \
    && [ ! -e "$S/.conveyor/project.json" ] || fail "setup did not name both folders, the lockfile and the install command, or wrote the pack before the answer: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --link yes 2>&1) || fail "setup --link yes failed: $out"
  [ "$(jq -c '[.linkFromMain, .worktree]' "$S/.conveyor/project.json")" = '[["node_modules","packages/a/node_modules"],null]' ] \
    || fail "setup --link yes did not write both folders as linkFromMain: $(jq -c . "$S/.conveyor/project.json")"
  # The worktree a card gets now has both linked.
  w=$T/$CASE/card; git -C "$S" worktree add -q --detach "$w" HEAD && out=$(wd_engine "$S" deps "$w") || fail "deps failed in the new worktree: $out"
  [ "$(readlink "$w/node_modules")" = "$S/node_modules" ] && [ "$(readlink "$w/packages/a/node_modules")" = "$S/packages/a/node_modules" ] \
    || fail "the card worktree has not got the two folders linked: $(ls -la "$w" "$w/packages/a")"
  # The owner's edit stays: a rerun asks nothing and writes no folder back.
  jq '.linkFromMain = ["node_modules"]' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --link yes 2>&1) || fail "setup run again failed: $out"
  [ "$(jq -c .linkFromMain "$S/.conveyor/project.json")" = '["node_modules"]' ] || fail "setup run again rewrote the owner's linkFromMain: $(jq -c .linkFromMain "$S/.conveyor/project.json")"
}
# Bug: setup --worktree-setup does not write the install command, or writes the folders as links too.
t_workdepinstall() {
  local X out; sample; X=$D/conveyor/conveyor.sh; wd_folders "$S"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --worktree-setup 'npm ci' 2>&1) || fail "setup --worktree-setup failed: $out"
  [ "$(jq -c '[.linkFromMain, .worktree]' "$S/.conveyor/project.json")" = '[[],{"setup":"npm ci"}]' ] \
    || fail "setup --worktree-setup did not write worktree.setup alone: $(jq -c . "$S/.conveyor/project.json")"
}
# Bugs: worktree.setup does not run in a new worktree (so a card's build and tests have no dependencies), runs
# elsewhere, or fails with no reason and no non-zero exit.
t_workdepcmd() {
  local -x FILEMODE=1
  local w out; setup "[]"; w=$T/$CASE/card
  tune '.worktree.setup = "pwd -P > installed; echo noise"'
  git -C "$R" worktree add -q --detach "$w" HEAD && out=$(wd_engine "$R" deps "$w") || fail "deps with worktree.setup failed: $out"
  [ "$(cat "$w/installed" 2>&1)" = "$(cd "$w" && pwd -P)" ] && [ -z "$out" ] || fail "worktree.setup did not run once at the worktree's top, or its output was not kept back: $out $(cat "$w/installed" 2>&1)"
  tune '.worktree.setup = "echo cannot reach the registry; exit 3"'
  out=$(wd_engine "$R" deps "$w") && fail "deps passed with a failing worktree.setup"
  [ "$out" = 'worktree.setup (echo cannot reach the registry; exit 3) failed (exit 3): cannot reach the registry' ] || fail "the failing worktree.setup's reason: $out"
}
# Bugs: doctor (its line, doctordeps() in lib/setup.sh) passes a project whose new card worktrees lack its installed
# node_modules, names none of the fixes, leaves its test worktree, or names a folder the pack links.
t_workdepdoctor() {
  local -x FILEMODE=1
  local out; setup "[]"; tune '.linkFromMain = []'; mkdir -p "$R/node_modules/x" && echo 'node_modules/' >> "$R/.git/info/exclude"
  out=$(wd_engine "$R" eval '. "$SRC/lib/setup.sh" && doctordeps') && fail "doctor's check passed with node_modules missing in a card worktree: $out"
  [ "$out" = "missing: node_modules in a new card worktree (the main checkout has it, ignored by git, and the tests may need it); fix: add node_modules to the pack's linkFromMain, or set the pack's worktree.setup to the command that installs it, such as npm ci (/conveyor-belt:setup asks which)" ] \
    || fail "doctor did not name node_modules and its fixes: $out"
  [ "$(git -C "$R" worktree list | wc -l)" = 1 ] || fail "doctor left its test worktree: $(git -C "$R" worktree list)"
  tune '.linkFromMain = ["node_modules"]'
  out=$(wd_engine "$R" eval '. "$SRC/lib/setup.sh" && doctordeps') && [ "$out" = 'ok: a new card worktree has the dependency folders of the main checkout' ] \
    || fail "doctor's check with node_modules linked: $out"
  # An install command fills the folders in each worktree: no folder is named missing.
  tune '.linkFromMain = [] | .worktree.setup = "npm ci"'
  out=$(wd_engine "$R" eval '. "$SRC/lib/setup.sh" && doctordeps') && [ "$out" = "ok: the dependencies of each card's worktree: worktree.setup (npm ci) installs them" ] \
    || fail "doctor's check with worktree.setup set: $out"
}
# Bug: a card whose tests fail because its worktree lacks main's node_modules goes to a fix session, or is blocked for
# test failures, when nothing in its change is wrong.
t_workdepmissing() {
  # The test pack links node_modules: here the pack links nothing, as one setup wrote before it filled linkFromMain.
  # The card changes a.txt, linked to the stub test file (the per-file fixture), so its tests run.
  local -x FILEMODE=1
  local c out; branchsetup; wd_folders "$R"; tune '.linkFromMain = []'
  echo '[ -d node_modules ] || { echo "Cannot find module left-pad"; exit 1; }' > "$STUB/test-cmd"
  lane deps a.txt bee; echo "$GO" > "$STUB/review.1"
  out=$(loop land-branch deps 2>&1) && fail "a card whose worktree lacks node_modules landed: $out"
  c=$(newest)
  [ "$(st "select(.card == \"$c\" and .step == \"blocked\") | .reason")" = "tests: node_modules, packages/a/node_modules are missing in the card's worktree; add them to linkFromMain or set worktree.setup" ] \
    && [ "$(steps "$c")" = "picked worktree deps brief start review start blocked " ] && [ ! -s "$STUB/sessions" ] \
    || fail "the card was not blocked for the missing folders alone: $(st "select(.card == \"$c\")") $(cat "$STUB/sessions" 2>/dev/null)"
}
