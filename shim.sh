#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The plugin's shim (plan docs/plans/conveyor-plugin-2026-11-10.md, section 7). Claude Code runs whichever copy of the
# plugin it installed, possibly auto-updated; a plugin hook or skill calls this with a path inside the plugin, and it
# runs that path from the install of the project's engine, never from this copy: the commit the project's pack pins,
# or, for a pack that follows the plugin's main, the project's current engine on this machine (the newest commit taken
# here, in the main checkout's git folder: lib/install.sh, take()). A machine that has taken none takes one first,
# with this copy's engine. On a machine that has, it starts a take of main with that engine once a minute at most,
# beside the hook and never waited for, so a machine that runs hooks and commands but no loop moves with main too:
# the hook runs on the engine it has, and a later one on the commit taken. Otherwise it only resolves and execs.
# import.sh places it at the plugin's top as shim.sh.
# Usage: shim.sh <path in the plugin> [<arg>...]
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: shim.sh <path in the plugin> [<arg>...]" >&2; exit 2; }
top=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
pack=$top/.conveyor/project.json
commit=$(jq -r '.plugin.commit // empty' "$pack" 2>/dev/null); look=''
if [ -z "$commit" ] && [ -n "$(jq -r '.plugin.follow // empty' "$pack" 2>/dev/null)" ]; then
  main=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && main=${main%/.git} \
    || { echo "conveyor: $top is no git checkout: its engine cannot be found" >&2; exit 1; }
  engine() { jq -r '.commit // empty' "$main/.git/conveyor-engine.json" 2>/dev/null; }
  commit=$(engine)
  # The take's output goes on stderr, as a hook's stdout is read by Claude Code; it reads nothing of the hook's stdin,
  # which is the hook's own input.
  # When this machine last looked at the plugin's main (the file's time): a take is started once a minute at most.
  look=$main/.git/conveyor-engine.look
  [ -n "$commit" ] || { touch "$look"; CONVEYOR_MAIN=$main bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/conveyor/conveyor.sh" take < /dev/null >&2; commit=$(engine); }
  [ -n "$commit" ] || { echo "conveyor: this project follows the plugin's $(jq -r .plugin.follow "$pack") and has taken no commit of it on this machine; run /conveyor-belt:setup" >&2; exit 1; }
fi
# A pin names a version folder, so only a full commit id may: anything else could name a path outside versions/.
[[ $commit =~ ^[0-9a-f]{40}$ ]] || { echo "conveyor: this project pins no Conveyor Belt commit; run /conveyor-belt:setup" >&2; exit 1; }
dir=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/versions/$commit
[ -f "$dir/$1" ] || { echo "conveyor: the project's Conveyor commit $commit is not installed; run /conveyor-belt:setup" >&2; exit 1; }
# A following project's take of main, by its current engine, with every stream away from the hook's, which Claude Code
# reads and waits on; its outcome is in the engine record (refused: Needs you on the Board).
if [ -n "$look" ] && [ -f "$dir/conveyor/conveyor.sh" ] && [ -z "$(find "$look" -mmin -1 2>/dev/null)" ] && touch "$look"; then
  CONVEYOR_MAIN=$main nohup bash "$dir/conveyor/conveyor.sh" take < /dev/null > /dev/null 2>&1 &
fi
# The path must stay inside the version folder once resolved, so neither a .. segment nor a symlink escapes it.
real=$(realpath "$dir/$1") && root=$(realpath "$dir") && [[ $real == "$root"/* ]] \
  || { echo "conveyor: the path $1 leaves the plugin" >&2; exit 2; }
exec "$dir/$1" "${@:2}"
