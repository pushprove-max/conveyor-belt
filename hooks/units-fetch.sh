#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The /units fetch: hooks/units.tsx runs it once a minute in the session's main checkout. It prints the lines that
# hooks/sources.ts parseFetch reads, one tab-separated line each:
#   paths <the Research lane's worktree, empty when none is named> <home> <this checkout's record's repo, empty when none>
#   fast norecord | none | unread | ok <branch> <commits ahead of the default branch> <tracked files changed> <first subject>
#   host <name> <how> <exit> [<path looked at>...], then for every record of the host file, in its order: <repo> <its
#   snapshot, or null>
# The lanes are the worktrees the host file names for this checkout's record (the record whose main is this checkout:
# lanes.fast.worktree and lanes.research.worktree, which `conveyor.sh lane ... create` writes; a path that starts with
# ~/ is under the home folder). norecord: the host file has no record of this checkout. That record's repo is the
# session's own project: its cards show with no project name, and the Fast lane's card is one of them.
# The snapshots are read as the Board reads them (.claude/scripts/dashboard.sh, conveyor()): `conveyor.sh snapshot` of
# the clone the host file's main names, for every record, in one command. It runs here when this checkout is a record
# of the host file or that clone, else over ssh to the host file's ssh target. A record whose snapshot fails prints
# null; the others still print. how: local or ssh, else why nothing was asked: nofile (no host file; the line then
# names the two paths looked at), config (it is not understood) or nossh (it names no ssh target).
# Usage: units-fetch.sh [feed]. feed: the Board's live feed is fresh, so the board is the feed's: only the lanes are
# read, and the host line is `host <empty> feed 0`.
set -uo pipefail
. "${BASH_SOURCE[0]%/*}/../conveyor/lib/portable.sh" && p_tools
here=$PWD
# This machine's host file, else the checkout's committed conveyor/host.json (as the Board reads it).
mine=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json cfg=$here/conveyor/host.json
[ ! -e "$mine" ] || cfg=$mine

rec=0 fast='' research='' own=''
if [ -e "$cfg" ]; then
  while IFS= read -r -d '' m && IFS= read -r -d '' f && IFS= read -r -d '' r && IFS= read -r -d '' o; do
    [ "$m" = "$here" ] || { [[ $m == /* ]] && [ "$m" -ef "$here" ]; } || continue
    rec=1 fast=$f research=$r own=$o
    break
  done < <(jq -j 'def w: if type == "string" then . else "" end;
      .records | arrays | .[] | objects | (.main | w), "\u0000", (.lanes.fast.worktree | w), "\u0000", (.lanes.research.worktree | w), "\u0000",
      (.repo | w | select(test("^[A-Za-z0-9._-]+$")) // ""), "\u0000"' "$cfg" 2>/dev/null)
fi
# shellcheck disable=SC2088 # the host file's literal ~/ prefix is matched here, not expanded
[[ $fast != "~/"* ]] || fast=$HOME/${fast#"~/"}
# shellcheck disable=SC2088 # likewise
[[ $research != "~/"* ]] || research=$HOME/${research#"~/"}
printf 'paths\t%s\t%s\t%s\n' "$research" "$HOME" "$own"
base=$(jq -r '.defaultBranch // "main"' .conveyor/project.json 2>/dev/null) || base=main
if [ "$rec" = 0 ]; then printf 'fast\tnorecord\n'
elif [ -z "$fast" ] || [ ! -e "$fast/.git" ]; then printf 'fast\tnone\n'
else
  br=$(git -C "$fast" rev-parse --abbrev-ref HEAD 2>/dev/null) && n=$(git -C "$fast" rev-list --count "refs/heads/$base..HEAD" 2>/dev/null) \
    && d=$(git -C "$fast" status --porcelain --untracked-files=no 2>/dev/null | wc -l) \
    && printf 'fast\tok\t%s\t%s\t%s\t%s\n' "$br" "$n" "$((d))" "$(git -C "$fast" log --reverse --format=%s "refs/heads/$base..HEAD" 2>/dev/null | head -n 1 | tr '\t' ' ')" \
    || printf 'fast\tunread\n'
fi
[ "${1:-}" != feed ] || { printf 'host\t\tfeed\t0\n'; exit 0; }

[ -e "$cfg" ] || { printf 'host\t\tnofile\t0\t%s\t%s\n' "$mine" "$cfg"; exit 0; }
host=$(jq -er '.host | select(test("^[A-Za-z0-9._-]+$"))' "$cfg" 2>/dev/null) \
  && main=$(jq -er '.main | select(test("^/[A-Za-z0-9._/-]+$"))' "$cfg" 2>/dev/null) \
  && recs=$(jq -ec --arg m "$main" '(.records // [{repo: "project", main: $m}]) | select(type == "array" and length > 0
      and all(type == "object" and (.repo | type == "string" and test("^[A-Za-z0-9._-]+$")) and (.main | type == "string" and test("^/[A-Za-z0-9._/-]+$"))))' "$cfg" 2>/dev/null) \
  || { printf 'host\t%s\tconfig\t0\n' "${host:-}"; exit 0; }
# Each name and path was checked above to hold no character the shell reads, so they go into the command as they are.
cmd=$(jq -r '.[] | [.repo, .main] | @tsv' <<<"$recs" | while IFS=$'\t' read -r r m; do
  printf 'printf "%%s\\t" %s; { CONVEYOR_MAIN=%s bash %s/conveyor/conveyor.sh snapshot 2>/dev/null || echo null; }; ' "$r" "$m" "$main"
done)
if [ "$rec" = 1 ] || [ "$here" -ef "$main" ]; then out=$(timeout -k 2 50 bash -c "$cmd"); rc=$?; how=local
else
  target=$(jq -er '.ssh | select(type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._@-]*$"))' "$cfg" 2>/dev/null) \
    || { printf 'host\t%s\tnossh\t0\n' "$host"; exit 0; }
  out=$(timeout -k 2 50 ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 "$target" "$cmd" 2>/dev/null); rc=$?; how=ssh
fi
printf 'host\t%s\t%s\t%s\n%s\n' "$host" "$how" "$rc" "$out"
