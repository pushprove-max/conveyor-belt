#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Benchmark phase 0, gate 2: is a replayed review exactly the review production ran? A review is its prompt (the
# bytes the reviewer read on stdin: the instructions, the brief, the Done-when evidence of the reply) and what it
# reads beside it: the worktree's HEAD, the staged change, the card's commit trailers and the context files (the
# engine's writing method rules/ste80.md, which every review prompt names by its path and the reviewer reads there,
# the worktree's AGENTS.md, the port's difference, the fix rounds), and the two paths the prompt names: the worktree's
# (its staged change is read at <worktree>.rv/staged.diff) and the engine folder's (its rules/ste80.md). A replay
# whose worktree or engine is at another path reads another prompt. snap keeps those of one review in a folder; compare
# checks two such folders byte for byte. A patch id (git patch-id) does not count: it reads no whitespace, no
# binary, no file mode and no context line, so two different reviews can share one.
# Usage:
#   promptcheck.sh snap <engine> <worktree> <prompt file> <folder> [<brief file>]
#                                                          keeps the review's inputs in <folder> (made; it must not
#                                                          exist); <engine> is the conveyor folder that ran the
#                                                          review. Read-only on the engine, the worktree and the
#                                                          card's files. The brief (the second argument of
#                                                          reviewed()) is kept as the part brief, which a replay
#                                                          (replay.sh) needs.
#   promptcheck.sh compare <production folder> <replay folder>
#                                                          prints "exact" and exits 0 when every part is the same
#                                                          bytes; else prints each part that differs or is in one
#                                                          folder only and exits 1. Exits 2 when a folder is no snap.
set -euo pipefail
export GIT_OPTIONAL_LOCKS=0 # a read must not refresh the index
# The parts every snap holds: a folder without one is no snap, so a compare can never pass on parts left out.
NEEDED=(prompt head staged.diff context/ste80.md engine worktree)
snap() { # <engine> <worktree> <prompt file> <folder> [<brief file>]
  local ste=$1/rules/ste80.md wt=$2 pr=$3 o=$4 br=${5:-}
  [ -f "$ste" ] || { echo "promptcheck: no writing method $ste" >&2; return 2; }
  [ -f "$pr" ] || { echo "promptcheck: no prompt file $pr" >&2; return 2; }
  git -C "$wt" rev-parse --verify -q HEAD >/dev/null || { echo "promptcheck: $wt is no git worktree with a HEAD" >&2; return 2; }
  [ -z "$br" ] || [ -f "$br" ] || { echo "promptcheck: no brief file $br" >&2; return 2; }
  [ ! -e "$o" ] || { echo "promptcheck: $o already exists" >&2; return 2; }
  mkdir -p "$o/context"
  cp "$pr" "$o/prompt"
  [ -z "$br" ] || cp "$br" "$o/brief"
  (cd "$1" && pwd -P) > "$o/engine"; (cd "$wt" && pwd -P) > "$o/worktree"
  cp "$ste" "$o/context/ste80.md"
  git -C "$wt" rev-parse HEAD > "$o/head"
  # The whole staged change, binary parts and modes included, as the reviewer's `git diff --cached` shows it.
  git -C "$wt" diff --cached --binary --no-renames HEAD > "$o/staged.diff"
  [ ! -f "$wt.trailers" ] || cp "$wt.trailers" "$o/trailers"
  [ ! -f "$wt/AGENTS.md" ] || cp "$wt/AGENTS.md" "$o/context/AGENTS.md"
  [ ! -f "$wt.port" ] || cp "$wt.port" "$o/context/port.diff"
  [ ! -d "$wt.rounds" ] || cp -RL "$wt.rounds" "$o/context/rounds"
}
parts() { (cd "$1" && find . -type f | LC_ALL=C sort); } # <folder>
compare() { # <production folder> <replay folder>
  local d p bad=0
  for d in "$1" "$2"; do
    for p in "${NEEDED[@]}"; do [ -f "$d/$p" ] || { echo "promptcheck: $d is no snap: it has no $p" >&2; return 2; }; done
  done
  while IFS= read -r p; do
    p=${p#./}
    if [ ! -f "$2/$p" ]; then echo "only in production: $p"; bad=1
    elif ! cmp -s "$1/$p" "$2/$p"; then echo "differs: $p ($(cmp "$1/$p" "$2/$p" 2>&1 | sed 's/^[^:]*: *//; s/.* differ: //' | head -n 1))"; bad=1; fi
  done < <(parts "$1")
  while IFS= read -r p; do p=${p#./}; [ -f "$1/$p" ] || { echo "only in the replay: $p"; bad=1; }; done < <(parts "$2")
  [ $bad = 1 ] && return 1
  echo exact
}
case "${1:-}" in
  snap) [ $# = 5 ] || [ $# = 6 ] || { echo "usage: promptcheck.sh snap <engine> <worktree> <prompt file> <folder> [<brief file>]" >&2; exit 2; }; snap "${@:2}" ;;
  compare) [ $# = 3 ] || { echo "usage: promptcheck.sh compare <production folder> <replay folder>" >&2; exit 2; }; compare "$2" "$3" ;;
  *) echo "usage: promptcheck.sh snap <engine> <worktree> <prompt file> <folder> [<brief file>] | compare <production folder> <replay folder>" >&2; exit 2 ;;
esac
