#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The decision log's two settings and the one test of whose session this is. Sourced, never run.
# The log is rulings.jsonl in the Foreman's folder of the project this runs in (conveyor/foreman/lib.sh FD: `foreman`
# in its state folder, a group of linked projects' in its first-named project's), one file every checkout and worktree
# of the project, or of its group, shares: each Foreman's decisions are its own projects'. Its ids start with the host
# file's rulingPrefix (default r): <prefix>-<YYYYMMDD>-<HHMMSS>-<question number, or p for a typed message>-<6 random hex>.

# The log's path; fails when the Foreman's folder cannot be named.
rulings_log() { ( . "${BASH_SOURCE[0]%/*}/../../../conveyor/foreman/lib.sh" && [ -n "$FD" ] && printf '%s/rulings.jsonl\n' "$FD" ) 2>/dev/null; }

# The id prefix; fails when the host file names one that is not letters and digits.
rulings_prefix() {
  local h=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json p=r
  [ ! -e "$h" ] || p=$(jq -r '.rulingPrefix // "r"' "$h" 2>/dev/null) || return 1
  [[ $p =~ ^[A-Za-z0-9]+$ ]] && printf '%s\n' "$p"
}

# True in the project's main checkout, the owner's and the Foreman's session. A linked worktree (a card, a worker or a
# reviewer) is never the owner's: a question asked there draws in that session only.
owner_session() { # <dir>
  local g c
  g=$(git -C "${1:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
  c=$(git -C "${1:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ "$g" = "$c" ]
}
