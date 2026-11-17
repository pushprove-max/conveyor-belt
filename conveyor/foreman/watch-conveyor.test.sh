#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, when the install it runs from is removed under it: one poll
# (--once) by a copy of the watcher in an install of its own, the project's snapshot unread for over 2 minutes.
# Bug (#186): another project's prune removed the install, and the watcher's line named the Board file it missed
# (dashboard_needs.json: No such file or directory), not the install that was gone or how to get it back.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail() { echo "FAIL [watch-conveyor]: $*" >&2; exit 1; }
A=$(printf 'a%.0s' {1..40}) NOW=$(date +%s)
export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data
I=$XDG_DATA_HOME/conveyor/versions/$A M=$T/alpha FD=$T/foreman
# The install of $A: the watcher, the Foreman's lib and the files they read, as an install holds them.
mkdir -p "$HOME" "$FD" "$XDG_CONFIG_HOME/conveyor" "$I/conveyor/lib" "$I/.claude/scripts" && cp -r "$SRC" "$I/conveyor/" \
  && cp "$SRC/../lib/portable.sh" "$I/conveyor/lib/" && cp "$SRC/../../.claude/scripts/dashboard_needs.json" "$I/.claude/scripts/" \
  && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
  && git init -q "$M" && mkdir -p "$M/.conveyor" && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
  || fail "the fixture was not made"
# The snapshot has been unread for 2 minutes; this poll's ask removes the install the watcher runs from, as the
# prune did, and fails as the engine of a removed install does.
echo "$((NOW - 120)) $((NOW - 60))" > "$FD/conveyor-down-alpha.txt"
CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_NOW=$NOW \
  CONVEYOR_FOREMAN_ASK="chmod -R u+w $I && rm -rf $I; echo \"bash: $I/conveyor/conveyor.sh: No such file or directory\" >&2; exit 127" \
  bash "$I/conveyor/foreman/watch-conveyor.sh" --once 2> "$T/err" || fail "no wake for the record unread for 2 minutes: $(cat "$T/err")"
[ ! -e "$I" ] || fail "the ask did not remove the install"
w=$(cat "$FD"/pending/*.wake)
grep -qF "alpha: no snapshot for 2 minutes (the Conveyor install $I the Foreman's watcher runs from is gone; run /conveyor-belt:setup in $M to install the project's engine again)" <<<"$w" \
  || fail "the wake does not name the install that is gone and the fix: $w"
echo "ok [watch-conveyor]"
