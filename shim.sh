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
if [ -z "$commit" ] && [ -n "$(jq -r '.plugin.follow // empty' "$pack" 2>/dev/null)" ]; then
  main=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && main=${main%/.git} \
    || off "$top is no git checkout: its engine cannot be found"
  engine() { jq -r '.commit // empty' "$main/.git/conveyor-engine.json" 2>/dev/null; }
  commit=$(engine)
  # The take's output goes on stderr, as a hook's stdout is read by Claude Code; it reads nothing of the hook's stdin,
  # which is the hook's own input.
  # When this machine last looked at the plugin's main (the file's time): a take is started once a minute at most.
  look=$main/.git/conveyor-engine.look
  first=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/conveyor/conveyor.sh
  # A hook never waits for that first take (its lock and GitHub can take longer than the hook's timeout): it starts
  # the take beside it, once a minute at most, and runs with the guards off until the take ends.
  if [ -z "$commit" ] && [ -n "${CONVEYOR_HOOK:-}" ]; then
    if [ -z "$(find "$look" -mmin -1 2>/dev/null)" ] && touch "$look"; then
      CONVEYOR_MAIN=$main nohup bash "$first" take < /dev/null > /dev/null 2>&1 &
    fi
  elif [ -z "$commit" ]; then
    touch "$look"; CONVEYOR_MAIN=$main bash "$first" take < /dev/null >&2; commit=$(engine)
  fi
  [ -n "$commit" ] || off "this project follows the plugin's $(jq -r .plugin.follow "$pack") and has taken no commit of it on this machine; run /conveyor-belt:setup"
fi
# A pin names a version folder, so only a full commit id may: anything else could name a path outside versions/.
[[ $commit =~ ^[0-9a-f]{40}$ ]] || off "this project pins no Conveyor Belt commit; run /conveyor-belt:setup"
dir=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/versions/$commit
[ -f "$dir/$1" ] || off "the project's Conveyor commit $commit is not installed; run /conveyor-belt:setup"
# A following project's take of main, by its current engine, with every stream away from the hook's, which Claude Code
# reads and waits on; its outcome is in the engine record (refused: Needs you on the Board).
if [ -n "$look" ] && [ -f "$dir/conveyor/conveyor.sh" ] && [ -z "$(find "$look" -mmin -1 2>/dev/null)" ] && touch "$look"; then
  CONVEYOR_MAIN=$main nohup bash "$dir/conveyor/conveyor.sh" take < /dev/null > /dev/null 2>&1 &
fi
# The path must stay inside the version folder once resolved, so neither a .. segment nor a symlink escapes it.
real=$(realpath "$dir/$1") && root=$(realpath "$dir") && [[ $real == "$root"/* ]] \
  || { echo "conveyor: the path $1 leaves the plugin" >&2; exit 2; }
exec "$dir/$1" "${@:2}"
