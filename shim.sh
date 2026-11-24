#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The plugin's shim (plan docs/plans/conveyor-plugin-2026-11-10.md, section 7). Claude Code runs whichever copy of the
# plugin it installed, possibly auto-updated; a plugin hook or skill calls this with a path inside the plugin, and it
# runs that path from the install of the project's engine, never from this copy: the commit the project's pack pins,
# or, for a pack that follows the plugin's main, the project's current engine on this machine (the newest commit taken
# here, in the main checkout's git folder: lib/install.sh, take()). A machine that has taken none takes one first,
# with this copy's engine (a hook starts that take and does not wait for it). On a machine that has, it starts a take
# of main with that engine once a minute at most, beside the hook and never waited for, so a machine that runs hooks
# and commands but no loop moves with main too:
# the hook runs on the engine it has, and a later one on the commit taken. Otherwise it only resolves and execs.
# import.sh places it at the plugin's top as shim.sh.
# A plugin hook (hooks/hooks.json sets CONVEYOR_HOOK=1) must never cost a session its tools, as the plugin is on in
# every project of its user: outside a Conveyor project (no git checkout, or no .conveyor/project.json) it does
# nothing, and in one whose engine cannot be found it runs no guard and says so once a session, not on each call.
# Usage: shim.sh <path in the plugin> [<arg>...]
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: shim.sh <path in the plugin> [<arg>...]" >&2; exit 2; }
top=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
pack=$top/.conveyor/project.json
# A lane (the research lane's hooks name it, CONVEYOR_LANE; the fast lane has its push refusal in its own config,
# lib/lane.sh laneseal) made by the first setup, before the pack was committed, has no pack of its own: its project's
# pack is the main checkout's. Bug (issue 1641): its start and guards were skipped there.
if [ ! -f "$pack" ] && [ -n "$top" ] && { [ -n "${CONVEYOR_LANE:-}" ] || [ "$(git -C "$top" config --worktree --get protocol.allow 2>/dev/null)" = never ]; }; then
  pack=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && pack=${pack%/.git}/.conveyor/project.json
fi
if [ -n "${CONVEYOR_HOOK:-}" ]; then
  [ -n "$top" ] && [ -f "$pack" ] && git -C "$top" rev-parse --git-dir >/dev/null 2>&1 || exit 0
fi
# off <message>: the engine cannot be found. A skill's call fails with the message; a hook's passes, and the first
# in a session (the session_id of its input) shows the user one line.
off() {
  [ -n "${CONVEYOR_HOOK:-}" ] || { echo "conveyor: $1" >&2; exit 1; }
  local sid seen
  sid=$(jq -r '.session_id // empty' 2>/dev/null) && [[ $sid =~ ^[A-Za-z0-9_-]{1,128}$ ]] || exit 0
  seen=${TMPDIR:-/tmp}/conveyor-guards-off.$(id -u)
  # set -C: the file is made only if it is not there, so of the hooks a tool call runs side by side, one speaks.
  # The folder is made here, one level under TMPDIR, so its mode applies to it; a hook beside this one may make it.
  { mkdir -m 700 "$seen" 2>/dev/null || [ -d "$seen" ]; } && (set -C; : > "$seen/$sid") 2>/dev/null || exit 0
  jq -cn '{systemMessage: "Conveyor'"'"'s guards are off in this project until /conveyor-belt:setup installs its commit"}'
  exit 0
}
commit=$(jq -r '.plugin.commit // empty' "$pack" 2>/dev/null); look=''
# The project's main checkout (empty outside a git checkout): the command run below works on it, not on the version
# folder it runs from, which has no .git (CONVEYOR_MAIN, lib/paths.sh).
main=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && main=${main%/.git} || main=''
if [ -z "$commit" ] && [ -n "$(jq -r '.plugin.follow // empty' "$pack" 2>/dev/null)" ]; then
  [ -n "$main" ] || off "$top is no git checkout: its engine cannot be found"
  engine() { jq -r '.commit // empty' "$main/.git/conveyor-engine.json" 2>/dev/null; }
  commit=$(engine)
  # The hooks that set CONVEYOR_PIN (the Foreman's two SessionStart hooks, which together make its context) run on one
  # engine: the first to read the engine record keeps its commit for the session (the session_id of its input) for a
  # minute, as a file made with ln, which only one of them can make; each then reads it. A take that publishes
  # between their two reads would else run `rules` on one engine and `start --rules-apart` on the other, so the
  # Foreman starts with no rules, or with them twice. The input is read here and given back to the engine's command.
  if [ -n "${CONVEYOR_PIN:-}" ]; then
    input=$(cat); exec < <(printf '%s' "$input")
    sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
    if [[ $sid =~ ^[A-Za-z0-9_-]{1,128}$ ]]; then
      # The pins are in the project's git folder, beside the engine record: whoever can write there can name the engine
      # already. A folder in TMPDIR has a name that others can guess, and one made first by another user would turn the
      # pin off (or name the engine) for every Foreman hook of this user.
      pins=$main/.git/conveyor-engine-pins; pin=$pins/$sid
      if mkdir -p "$pins" 2>/dev/null; then
        # A pin over a minute old is a session's earlier start, never this one's: every such pin is removed (sessions
        # of other ids leave theirs), never the other hook's new one.
        find "$pins" -type f -mmin +1 -delete 2>/dev/null
        # An engine record that names no commit is pinned too (as `none`): the second hook then also finds none, not the
        # commit a take published between the two.
        tmp=$(mktemp "$pin.XXXXXX") && printf '%s' "${commit:-none}" > "$tmp" && ln "$tmp" "$pin" 2>/dev/null; rm -f "$tmp"
        pinned=$(cat "$pin" 2>/dev/null)
        if [[ $pinned =~ ^[0-9a-f]{40}$ ]]; then commit=$pinned; elif [ "$pinned" = none ]; then commit=''; fi
      fi
    fi
  fi
  # The take's output goes on stderr, as a hook's stdout is read by Claude Code; it reads nothing of the hook's stdin,
  # which is the hook's own input.
  # When this machine last looked at the plugin's main (the file's time): a take is started once a minute at most.
  look=$main/.git/conveyor-engine.look
  first=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/conveyor/conveyor.sh
  # The log of the takes started beside a hook, next to the engine record (ENGINELOG, lib/paths.sh): one JSON line a
  # take, the last 10 kept, and before them the newest that worked when none of them did: {time, by (the commit whose engine ran it, or "plugin copy"), exit, output (its last 2000
  # characters), note}. doctor, the Foreman's start and /units read it (stalenote(), lib/install.sh).
  log=$main/.git/conveyor-engine.log
  # logged <conveyor.sh> <by> [<note>] [wait]: one take by that engine, kept in the log; returns its exit code. With
  # wait (the plugin copy's take only), it waits for a take that runs now, not ending at once. Its output goes to a
  # file, not a pipe: a Board the take starts again keeps the take's streams open after the take ends.
  logged() {
    local o rc t
    o=$(mktemp "$log.out.XXXXXX") || return 1
    CONVEYOR_MAIN=$main bash "$1" take ${4:+"$4"} < /dev/null > "$o" 2>&1; rc=$?
    # The newest take that worked is kept even when 10 failures came after it: the stale-engine line names its time.
    t=$(mktemp "$log.XXXXXX") && { { [ ! -f "$log" ] || jq -cnR '[inputs | fromjson? | objects] | ([.[] | select(.exit == 0)] | last) as $ok
        | .[-9:] | (if $ok != null and all(.[]; .exit != 0) then [$ok] + . else . end)[]' "$log"; } || :
      jq -cn --arg by "$2" --argjson rc "$rc" --rawfile out "$o" --arg n "${3:-}" \
        '{time: (now | todate), by: $by, exit: $rc, output: $out[-2000:]} + (if $n == "" then {} else {note: $n} end)'
    } > "$t" && mv "$t" "$log" || rm -f "$t"
    rm -f "$o"; return "$rc"
  }
  # bgtake <conveyor.sh> <by>: that take beside the hook, never waited for, with every stream away from the hook's,
  # which Claude Code reads and waits on. When it fails and is not the plugin copy's own, the plugin copy's take runs
  # next (the newest take code on this machine, which mends a fault in an old engine's own take) and the log says so.
  bgtake() {
    ( trap '' HUP
      logged "$1" "$2" || [ "$1" -ef "$first" ] || logged "$first" "plugin copy" "the take by $2 failed, so the plugin copy's take ran"
    ) < /dev/null > /dev/null 2>&1 &
  }
  # A hook never waits for that first take (its lock and GitHub can take longer than the hook's timeout): it starts
  # the take beside it, once a minute at most, and runs with the guards off until the take ends.
  if [ -z "$commit" ] && [ -n "${CONVEYOR_HOOK:-}" ]; then
    if [ -z "$(find "$look" -mmin -1 2>/dev/null)" ] && touch "$look"; then
      bgtake "$first" "plugin copy"
    fi
  elif [ -z "$commit" ]; then
    touch "$look"; CONVEYOR_MAIN=$main bash "$first" take wait < /dev/null >&2; commit=$(engine)
  fi
  [ -n "$commit" ] || off "this project follows the plugin's $(jq -r .plugin.follow "$pack") and has taken no commit of it on this machine; run /conveyor-belt:setup"
fi
# A pin names a version folder, so only a full commit id may: anything else could name a path outside versions/.
[[ $commit =~ ^[0-9a-f]{40}$ ]] || off "this project pins no Conveyor Belt commit; run /conveyor-belt:setup"
dir=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/versions/$commit
# A following project's taken commit whose install is gone (removed by a prune, or by hand) is repaired, not run with
# the guards off: the plugin copy's take runs here, waited for, which takes the newest commit the pack follows or
# installs the taken one again, and the command runs on what it took. Once repaired, the next call finds it installed, so this
# says so once.
if [ -n "$look" ] && [ ! -e "$dir" ]; then
  touch "$look"; logged "$first" "plugin copy" "the project's commit $commit was not installed, so the plugin copy's take ran in the foreground" wait
  was=$commit; commit=$(engine)
  [[ $commit =~ ^[0-9a-f]{40}$ ]] && dir=${dir%/*}/$commit && [ -f "$dir/$1" ] \
    && echo "conveyor: the project's Conveyor commit $was was not installed; the plugin's $(jq -r .plugin.follow "$pack") was taken again, and this runs on $commit" >&2
fi
[ -f "$dir/$1" ] || off "the project's Conveyor commit $commit is not installed; run /conveyor-belt:setup"
# A following project's take of main, by its current engine (bgtake): its outcome is in the engine record (refused:
# Needs you on the Board) and in the log.
if [ -n "$look" ] && [ -f "$dir/conveyor/conveyor.sh" ] && [ -z "$(find "$look" -mmin -1 2>/dev/null)" ] && touch "$look"; then
  bgtake "$dir/conveyor/conveyor.sh" "$commit"
fi
# The path must stay inside the version folder once resolved, so neither a .. segment nor a symlink escapes it.
real=$(realpath "$dir/$1") && root=$(realpath "$dir") && [[ $real == "$root"/* ]] \
  || { echo "conveyor: the path $1 leaves the plugin" >&2; exit 2; }
# A main checkout the caller names is kept.
[ -z "$main" ] || export CONVEYOR_MAIN=${CONVEYOR_MAIN:-$main}
exec "$dir/$1" "${@:2}"
