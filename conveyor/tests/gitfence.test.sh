#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: git in the runner's setup and in each case reaches only the run's scratch folder (lib/gitfence.sh, issue 255).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug (#255): engine cases run in a linked worktree of the engine's checkout left `core.bare=true` in its shared
# config and an `init` commit on its HEAD: under the GIT_DIR that `git bisect run` exports, the runner's fixture
# (lib.sh fixture()) ran its git init, commit and `init --bare` on the worktree; gitfence() (lib/gitfence.sh) fences them. The runner, run whole from inside a
# linked worktree of a scratch repo, with that GIT_DIR, its scratch folder inside the worktree (TMPDIR), and one case
# that commits with an empty -C path: the case fails, naming no repository, and the scratch repo's config and refs
# (its own and the worktree's HEAD) are as they were.
# fxengine <dir> <case line>: the engine as it is in <dir>/src, with only one fixture case file in its tests/, holding
# # timeout: 30 and <case line> (and the stub CLIs lib.sh's setup copies), and a host file of the case's own
# (XDG_CONFIG_HOME): its runner takes no slot of the machine's.
fxengine() {
  local f s=$1/src
  mkdir -p "$s/tests" || fail "the fixture could not be made"
  export XDG_CONFIG_HOME=$1/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$1/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  for f in "$SRC"/*; do [ "${f##*/}" = tests ] || ln -s "$f" "$s/"; done
  ln -s "$SRC/tests/lib.sh" "$SRC/tests/wait.sh" "$SRC/tests/stubs" "$s/tests/"
  printf '%s\n' '# timeout: 30' "$2" > "$s/tests/fx.test.sh"
}

t_gitfence() {
  local d=$T/$CASE s w g rc was got
  s=$d/src w=$d/wt
  git init -q -b main "$d/repo" && git -C "$d/repo" commit -q --allow-empty -m one && git -C "$d/repo" worktree add -q --detach "$w" \
    && mkdir "$w/tmp" && g=$(git -C "$w" rev-parse --absolute-git-dir) || fail "the scratch repo and its worktree could not be made"
  fxengine "$d" 't_fxgit() { git -C "${FX_NOPATH:-}" commit -q --allow-empty -m stray; }'
  was=$(cat "$d/repo/.git/config"; git -C "$d/repo" for-each-ref; git -C "$w" rev-parse HEAD)
  (cd "$w" && GIT_DIR=$g TMPDIR=$w/tmp timeout 60 bash "$s/conveyor.test.sh") > "$d/run" 2>&1; rc=$?
  got=$(cat "$d/repo/.git/config"; git -C "$d/repo" for-each-ref; git -C "$w" rev-parse HEAD)
  [ "$got" = "$was" ] || fail "the run changed the scratch repo's config or refs: $(diff <(echo "$was") <(echo "$got")); $(cat "$d/run")"
  [ $rc = 1 ] && grep -q 'not a git repository' "$d/run" && ! grep -qx 'ok fxgit' "$d/run" \
    || fail "the case's git with no path did not fail naming no repository (exit $rc): $(cat "$d/run")"
}

# R143. Bug it catches: the runner's setup (tests/lib.sh) called gitfence() and went on when it failed, so the cases
# ran with no fence and could change the refs of the checkout the run was started in. A git function the runner is
# given fails `git rev-parse --local-env-vars` (gitfence() then returns 1) and runs the real git for all else. The runner of a
# fixture engine (fxengine()) is run whole: only its run shows that the runner stops before its first case. It exits
# non-zero, and its one case, which notes that it ran, did not run.
t_gitfencefails() {
  local d=$T/$CASE rc
  fxengine "$d" "t_fxran() { : > '$d/ran'; }"
  # An exported function, not a git first on PATH: the runner's p_tools() puts Homebrew's bin ahead of PATH on macOS.
  ( git() { [ "$*" != "rev-parse --local-env-vars" ] || return 1; command git "$@"; }; export -f git
    CONVEYOR_SHELL_TEST_CASE=fxran timeout 60 bash "$d/src/conveyor.test.sh" ) > "$d/run" 2>&1; rc=$?
  [ "$rc" != 0 ] && [ ! -e "$d/ran" ] \
    || fail "the runner, given a git whose rev-parse --local-env-vars fails, did not exit non-zero before its case ran (exit $rc, case ran: $([ -e "$d/ran" ] && echo yes || echo no)): $(cat "$d/run")"
  grep -q 'gitfence: git could not list the variables' "$d/run" || fail "the runner did not say why it stopped: $(cat "$d/run")"
}
