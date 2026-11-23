#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The /units fetch: hooks/units.tsx runs it once a minute in the session's main checkout, and as soon as its short
# check (stamp, below) sees a record change. It prints the lines that
# hooks/sources.ts parseFetch reads, one tab-separated line each:
#   paths <the Research lane's worktree, empty when none is named> <home> <this checkout's record's repo, empty when none>
#   fast norecord | none | unread | ok <branch> <commits ahead of the default branch> <tracked files changed> <first subject>
#   foremandir <the Foreman's folder>, then foreman <its role, waiter and watchers> (below), only where a Foreman is expected
#   pluginbugs <how many> <file>: the plugin problems the Foreman noted (below), only when it noted one
#   testmap <the test map's state, JSON>: as it is made, or its state, where Conveyor runs for this checkout (below), only
#   with .conveyor/project.json here
#   engine <one line>: the project runs an old engine on this machine (below), only when it does
#   host <name> <how> <exit> [<path looked at>...], then for every record of the host file, in its order: <repo> <its
#   snapshot, or null>
# The lanes are the worktrees the host file names for this checkout's record (the record whose main is this checkout:
# lanes.fast.worktree and lanes.research.worktree, which `conveyor.sh lane ... create` writes; a path that starts with
# ~/ is under the home folder). norecord: the host file has no record of this checkout. That record's repo is the
# session's own project: its cards show with no project name, and the Fast lane's card is one of them.
# The snapshots are read as the Board reads them (.claude/scripts/dashboard.sh, conveyor()), from the host and engine
# its one reader of the host file gives (.claude/scripts/hostfile.sh): `conveyor.sh snapshot` of that engine, for every
# record, in one command. It runs here on one machine (the host file names no ssh target, as setup writes it, and the
# engine is this copy of Conveyor), or when this checkout is a record of the host file or the host's main, else over
# ssh to the host file's ssh target. A record whose snapshot fails prints null; the others still print. how: local or
# ssh, else why nothing was asked: nofile (no host file; the line then names the two paths looked at) or config (it
# is not understood).
# Usage: units-fetch.sh [feed | fresh <repo>... | stamp | foreman]. foreman: the Foreman's lines alone, nothing else read.
# feed: the Board's live feed is fresh, so the board is the
# feed's: only the lanes, the Foreman, the test map and the engine are read, and the host line is `host <empty> feed 0`.
# fresh: the short check saw these records change, so their snapshots are built now (`snapshot --fresh`), not the
# kept ones. stamp: the short check alone (below), which prints `stamps <local | ssh | none>`, then <repo> <checksum>
# for every record, and exits 1 when the host did not answer.
set -uo pipefail
. "${BASH_SOURCE[0]%/*}/../conveyor/lib/portable.sh" && p_tools
here=$PWD
mode=${1:-}; [ $# = 0 ] || shift
# The Foreman (conveyor/foreman/lib.sh FD, the folder its own hooks name): printed only where one is expected, its
# folder holding a role mark (session) that names a session, or its launcher's settings (settings.json). The line:
#   foreman <session the mark names> <waiter.pid's pid> <its commit, - from a checkout> <its session> <1 when that pid
#   runs conveyor/foreman/waiter.sh, else 0> <the commit the project runs now, as waiter.sh moved() reads it, empty when
#   none> <each watcher, name:up or name:down, while the waiter runs> <the waiter's state: listening, starting again
#   or down: <why>, as lib.sh waiter_state reads it from waiter.pid and waiter.log>
# The waiter writes waiter.pid only once it holds waiter.lock, and holds it while it runs, so a live waiter.sh by that
# pid holds the lock: the lock is not tried here, as a try that held it while a waiter started would make that waiter
# stand down. A watcher is up while a child of the waiter runs its watch-<name>.sh. Nothing is started; a read writes only
#   the waiter's end line, once, when waiter_state finds the waiter gone with no end line in waiter.log.
# foremandir <FD> goes before it: the folder whose role mark (session) and waiter.pid the mod looks at each second
# (hooks/units.tsx foremanTick). Mode `foreman` prints these two lines alone.
foreman_line() {
  fd='' wstate=''
  { IFS= read -r fd; IFS= read -r wstate; } < <(export CONVEYOR_MAIN=$here
    . "${BASH_SOURCE[0]%/*}/../conveyor/foreman/lib.sh" > /dev/null 2>&1 && printf '%s\n%s\n' "$FD" "$(waiter_state)")
  if [ -n "$fd" ] && { [ -s "$fd/session" ] || [ -f "$fd/settings.json" ]; }; then
    mark='' wpid='' wcommit='' wsid='' live=0 watch='' w3=''
    { read -r mark _ < "$fd/session"; } 2>/dev/null
    # "<pid> <commit> <session's process> <session>"; a waiter of an older engine writes "<pid> <commit> <session>": a
    # third field is the session's process only when a fourth follows or it is a number, as a session id never is.
    { read -r wpid wcommit w3 wsid < "$fd/waiter.pid"; } 2>/dev/null
    [ -n "$wsid" ] || [[ $w3 =~ ^[0-9]+$ ]] || wsid=$w3
    if [[ $wpid =~ ^[0-9]+$ ]]; then
      procs=$(p_procs)
      if awk -v p="$wpid" '$1 == p && index($0, "/conveyor/foreman/waiter.sh") { f = 1 } END { exit !f }' <<<"$procs"; then
        live=1
        for w in conveyor limit alerts idle; do
          s=down
          awk -v p="$wpid" -v n="/watch-$w.sh" '$2 == p && index($0, n) { f = 1 } END { exit !f }' <<<"$procs" && s=up
          watch="$watch${watch:+ }$w:$s"
        done
      fi
    fi
    cur=$(jq -r '.plugin.commit // empty | strings' .conveyor/project.json 2>/dev/null)
    [ -n "$cur" ] || cur=$(jq -r '.commit // empty | strings' .git/conveyor-engine.json 2>/dev/null)
    printf 'foremandir\t%s\n' "$fd"
    printf 'foreman\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$mark" "$wpid" "$wcommit" "$wsid" "$live" "$cur" "$watch" "$wstate"
  fi
}
[ "$mode" != foreman ] || { foreman_line; exit 0; }
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
# Which machine and which checkout, as the Board reads them: hostfile.sh, the one reader of the host file.
got='' ok=1 host='' main='' engine='' target=''
if [ -e "$cfg" ]; then
  got=$(bash "${BASH_SOURCE[0]%/*}/../.claude/scripts/hostfile.sh" "$here"); ok=$?
  { IFS= read -r -d '' host; IFS= read -r -d '' main; IFS= read -r -d '' engine; IFS= read -r -d '' target; } \
    < <(jq -j '(.host // ""), "\u0000", (.main // ""), "\u0000", (.engine // ""), "\u0000", (.target // ""), "\u0000"' <<<"$got" 2>/dev/null)
fi
# The snapshots are asked over ssh with a build machine, unless this checkout is a record of the host file or its main.
remote=0; [ "$ok" != 0 ] || [ -z "$target" ] || [ "$rec" = 1 ] || [ "$here" -ef "$main" ] || remote=1
# stamp: the short check. For every record, in one command where the snapshots are asked (one ssh call at most), a
# checksum of what a card started, a step, a landing or a block changes: the size and last 4 KiB of its cards.jsonl,
# its control.json and the queue (snapgh/issues), in its state folder (`conveyor.sh state-dir`), and its live records
# in its cards folder (lib/paths.sh CARDS: the name kept in the state folder's cards-folder, beside its main): which
# there are (each card's <card>.live and each bug card's proof run, mainrun/<card>.unfixed.live, views.sh proofs()),
# and the step and the card waited on that each card's names, as a step that only a live record writes shows (a fix
# after a GO, a wait, a proof run). A live record's other fields, rewritten as the step runs, are not read.
# hooks/units.tsx (knowsStamp) reads the next line's text to know that this script has the check: keep it as it is.
if [ "$mode" = stamp ]; then
  [ -e "$cfg" ] && [ "$ok" = 0 ] || { printf 'stamps\tnone\n'; exit 0; }
  scmd=$(jq -j --arg e "$engine/conveyor/conveyor.sh" '.records[]
    | "d=$(CONVEYOR_MAIN=\(.main | @sh) bash \($e | @sh) state-dir 2>/dev/null); k=$(head -n 1 \"$d/cards-folder\" 2>/dev/null); case $k in conveyor-cards|conveyor-cards-*) ;; *) k=conveyor-cards ;; esac; c=\(.main | sub("/+$"; "") | sub("/[^/]*$"; "") | @sh)/$k; printf \"%s\\t%s\\n\" \(.repo | @sh) \"$({ wc -c < \"$d/cards.jsonl\"; tail -c 4096 \"$d/cards.jsonl\"; cat \"$d/control.json\" \"$d/snapgh/issues\"; cd \"$c\" && { ls -1 -- *.live mainrun/*.unfixed.live; grep -o -H -E \"[{,].(step|on).:.[^,}]*\" -- *.live; }; } 2>/dev/null | cksum)\"; "' <<<"$got")
  if [ "$remote" = 0 ]; then out=$(timeout -k 2 10 bash -c "$scmd"); rc=$?; how=local
  else out=$(timeout -k 2 10 ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "$scmd" 2>/dev/null); rc=$?; how=ssh; fi
  [ "$rc" = 0 ] || exit 1
  printf 'stamps\t%s\n%s\n' "$how" "$out"; exit 0
fi
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
foreman_line
# The plugin problems the Foreman noted (conveyor/foreman/stop.sh, one "- " line each in plugin-bugs.md), printed only
# when there is one: pluginbugs <how many> <the file>.
n=0; [ -z "$fd" ] || n=$(grep -c '^- ' "$fd/plugin-bugs.md" 2>/dev/null) || n=0
[ "$n" -eq 0 ] || printf 'pluginbugs\t%s\t%s\n' "$n" "$fd/plugin-bugs.md"
# The test map of this checkout's project (`conveyor.sh testmap`, lib/testmap.sh mapstate()): testmap <its state, one
# JSON object>, printed only in a checkout with Conveyor's project settings, and read where Conveyor runs for it. Here,
# by this copy of Conveyor, unless the snapshots come from a build machine: then that machine's, in the same ssh
# command, of the record named as this checkout's folder (the record doctor names it served by, lib/setup.sh), and none
# when no record has that name. When the board is the feed's, the snapshots are not asked, but the map still is, over
# ssh on its own: the feed has no map. This machine's own map is never shown then.
tmcmd=''
if [ -f .conveyor/project.json ] && [ "$remote" = 0 ]; then
  tm=$(CONVEYOR_MAIN=$here timeout -k 2 20 bash "${BASH_SOURCE[0]%/*}/../conveyor/conveyor.sh" testmap 2>/dev/null) \
    && [[ $tm == '{'* ]] && printf 'testmap\t%s\n' "$tm"
elif [ -f .conveyor/project.json ]; then
  t=${here##*/}; t=${t//[^A-Za-z0-9._-]/-}
  tmcmd=$(jq -j --arg e "$engine/conveyor/conveyor.sh" --arg n "$t" 'first(.records[] | select(.repo == $n))
    | "tm=$(CONVEYOR_MAIN=\(.main | @sh) bash \($e | @sh) testmap 2>/dev/null) && case $tm in \"{\"*) printf \"testmap\\t%s\\n\" \"$tm\" ;; esac; "' <<<"$got" 2>/dev/null)
fi
# The project runs an old engine on this machine, where its hooks run (`conveyor.sh take stale`, lib/install.sh
# stalenote(): no remote is read): engine <the line>, only when it does.
if [ -f .conveyor/project.json ]; then
  en=$(CONVEYOR_MAIN=$here timeout -k 2 20 bash "${BASH_SOURCE[0]%/*}/../conveyor/conveyor.sh" take stale 2>/dev/null) \
    && [ -n "$en" ] && printf 'engine\t%s\n' "${en//$'\t'/ }"
fi
if [ "$mode" = feed ]; then
  [ -z "$tmcmd" ] || timeout -k 2 20 ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "$tmcmd" 2>/dev/null | grep -m1 '^testmap'$'\t'
  printf 'host\t\tfeed\t0\n'; exit 0
fi

[ -e "$cfg" ] || { printf 'host\t\tnofile\t0\t%s\t%s\n' "$mine" "$cfg"; exit 0; }
[ "$ok" = 0 ] || { printf 'host\t%s\tconfig\t0\n' "$host"; exit 0; }
# Every name and path is quoted for the shell (@sh), here or on the host. A record `fresh` names is asked for
# `snapshot --fresh`: its state changed since the kept snapshot may have been built, which a plain read would print.
[ "$mode" = fresh ] || set --
# Each snapshot is cut, on the machine that makes it, to the parts the pane draws (hooks/sources.ts parseRecord; the same
# cut as units_snap in .claude/scripts/dashboard_stream.py): the rest, the Tests page's history above all, grows without
# end and made the fetch too slow and too big to read. A snapshot that jq cannot cut prints null, as a failed one does.
view='with_entries(select(.key | IN("health", "needsYou", "belt", "landed", "landedCount", "queue", "cost", "awaitingDeploy", "suites", "snapshotAt", "recordsNow", "open", "declined", "declinedRest")))
  | if (.open | type) == "object" then .open |= with_entries(select(.key | IN("umbrellas", "held"))) else . end
  | if (.recordsNow | type) == "object" then .recordsNow |= {building} else . end
  | reduce ("declined", "declinedRest") as $k (.; if (.[$k] | type) == "array" then .[$k] |= map(select(type == "object" and .by == "judge") | {id, by, time}) else . end)'
# The cut runs in a bash that has taken the engine's PATH (p_path in conveyor/lib/portable.sh): on macOS the jq the engine
# needs is Homebrew's, and an ssh command's PATH has no Homebrew folder.
cutc='. "$1" && p_path && jq -c "$2"'
cmd=$(jq -j --arg e "$engine/conveyor/conveyor.sh" --arg l "$engine/conveyor/lib/portable.sh" --arg v "$view" --arg c "$cutc" '$ARGS.positional as $f | .records[]
  | "printf \"%s\\t\" \(.repo | @sh); { s=$(CONVEYOR_MAIN=\(.main | @sh) bash \($e | @sh) snapshot\(.repo as $r | if any($f[]; . == $r) then " --fresh" else "" end) 2>/dev/null) && printf \"%s\" \"$s\" | bash -c \($c | @sh) _ \($l | @sh) \($v | @sh) || echo null; }; "' --args "$@" <<<"$got")
if [ "$remote" = 0 ]; then out=$(timeout -k 2 50 bash -c "$cmd"); rc=$?; how=local
else out=$(timeout -k 2 50 ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 "$target" "$tmcmd$cmd" 2>/dev/null); rc=$?; how=ssh
  # The build machine's testmap line comes first, and goes before the host line, as parseFetch reads it.
  if [ -n "$tmcmd" ] && [[ $out == testmap$'\t'* ]]; then printf '%s\n' "${out%%$'\n'*}"; [[ $out == *$'\n'* ]] && out=${out#*$'\n'} || out=''; fi
fi
printf 'host\t%s\t%s\t%s\n%s\n' "$host" "$how" "$rc" "$out"
