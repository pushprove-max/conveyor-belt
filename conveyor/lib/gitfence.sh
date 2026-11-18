#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The git fence of the engine's test cases (tests/lib.sh, issue 255). Sourced, never run.

# Git in this shell and its children reaches only the repos inside <dir>. The variables that name a repository
# (GIT_DIR and the others `git rev-parse --local-env-vars` lists) are unset, as they are the caller's: `git bisect run`
# exports GIT_DIR, and under it a case's `git init`, `git commit` and `git init --bare` worked on the checkout the run
# was started in (an `init` commit on its HEAD, core.bare=true in its shared config). GIT_CEILING_DIRECTORIES is <dir>:
# git looks for no repository above it, so a git command run in <dir> with no -C, or with an empty one, finds none
# and fails ("not a git repository"), even where <dir> is inside a checkout. Fails when git cannot list the variables.
gitfence() { # <dir>
  local v
  v=$(git rev-parse --local-env-vars) && [ -n "$v" ] || { echo "gitfence: git could not list the variables that name a repository" >&2; return 1; }
  # shellcheck disable=SC2086 # one variable's name a word
  unset $v
  export GIT_CEILING_DIRECTORIES=$1
}
