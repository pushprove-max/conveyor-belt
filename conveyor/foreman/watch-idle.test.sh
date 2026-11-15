#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's keep-warm watcher, watch-idle.sh: one poll (--once) over a Claude config folder of its own, the clock
# set by CONVEYOR_FOREMAN_NOW. It pings when the marked Foreman's own transcript is 50 minutes old.
# Bugs: the newest transcript of any session in the checkout counted as the Foreman's activity, so another session
# active every 30 minutes kept it from ever pinging and the Foreman's 1-hour cache expired; and the project folder was
# looked for by the whole path, though Claude Code cuts a name past 200 characters to those, a dash and a hash, so a
# checkout with a long path never pinged.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
. "$SRC/../lib/portable.sh"; p_tools
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0
NOW=$(date +%s) ID=f0f0f0f0-0000-4000-8000-000000000001
# A transcript at <folder>/<name>.jsonl written <minutes> before NOW.
transcript() { # <folder> <name> <minutes>
  mkdir -p "$1" && : > "$1/$2.jsonl" && TZ=UTC touch -t "$(TZ=UTC p_date "@$((NOW - $3 * 60))" +%Y%m%d%H%M.%S)" "$1/$2.jsonl"
}
# One poll for the checkout path given, its Foreman marked ID; 0 with a ping put in pending.
poll() { # <case> <checkout path>
  local fd=$T/$1/foreman
  mkdir -p "$fd" "$T/$1/user" && printf '%s 2026-11-15T00:00:00Z\n' "$ID" > "$fd/session"
  HOME=$T/$1/user XDG_CONFIG_HOME=$T/$1/user/.config CLAUDE_CONFIG_DIR=$T/$1/cfg CLAUDE_PROJECT_DIR=$2 CONVEYOR_MAIN=$2 \
    CONVEYOR_FOREMAN_DIR=$fd CONVEYOR_FOREMAN_NOW=$NOW bash "$SRC/watch-idle.sh" --once \
    && grep -qF 'Keepalive: idle 50 min' "$fd"/pending/*.wake
}
check() { if "${@:2}"; then echo "ok [watch-idle]: $1"; else echo "FAIL [watch-idle]: $1" >&2; fails=$((fails + 1)); fi; }

# Another session's transcript, written a minute ago, beside the Foreman's, 50 minutes old.
P=/r/main/project
transcript "$T/other/cfg/projects/${P//[^A-Za-z0-9]/-}" a1a1a1a1-0000-4000-8000-000000000002 1
transcript "$T/other/cfg/projects/${P//[^A-Za-z0-9]/-}" "$ID" 50
check "another session's fresh transcript does not hold off the Foreman's ping" poll other "$P"

# A checkout path over 200 characters: its folder is the first 200 characters of the name, a dash and a hash.
L=/r/$(printf 'x%.0s' {1..210})/project E=${L//[^A-Za-z0-9]/-}
transcript "$T/long/cfg/projects/${E:0:200}-1a2b3c" "$ID" 50
check "the Foreman's transcript is found for a checkout path over 200 characters" poll long "$L"

[ "$fails" = 0 ]
