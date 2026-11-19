#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's keep-warm watcher, watch-idle.sh: one poll (--once) over a Claude config folder of its own, the clock
# set by CONVEYOR_FOREMAN_NOW. It pings when the marked Foreman's own transcript is 50 minutes old.
# Bugs: the newest transcript of any session in the checkout counted as the Foreman's activity, so another session
# active every 30 minutes kept it from ever pinging and the Foreman's 1-hour cache expired; and the project folder was
# looked for by the whole path, though Claude Code cuts a name past 200 characters to those, a dash and a hash, so a
# checkout with a long path never pinged. And a keepalive turn that wrote the whole cache again and read none of it
# (the cache was gone) was followed by more pings, each a full turn for nothing.
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
# One poll for the checkout path given, its Foreman marked ID, at NOW plus <seconds>; 0 with a new ping in pending.
poll() { # <case> <checkout path> [<seconds after NOW>]
  local fd=$T/$1/foreman
  mkdir -p "$fd/pending" "$T/$1/user" && printf '%s 2026-11-15T00:00:00Z\n' "$ID" > "$fd/session" && rm -f "$fd"/pending/*.wake
  HOME=$T/$1/user XDG_CONFIG_HOME=$T/$1/user/.config CLAUDE_CONFIG_DIR=$T/$1/cfg CLAUDE_PROJECT_DIR=$2 CONVEYOR_MAIN=$2 \
    CONVEYOR_FOREMAN_DIR=$fd CONVEYOR_FOREMAN_NOW=$((NOW + ${3:-0})) bash "$SRC/watch-idle.sh" --once \
    && grep -qF 'Keepalive: idle ' "$fd"/pending/*.wake
}
# A case whose Foreman got ping 1 51 minutes before NOW and answered it a minute later, 50 minutes before NOW, with
# the usage given (a JSON object, or a text that is not one).
pinged() { # <case> <usage>
  local d=$T/$1/cfg/projects/${P//[^A-Za-z0-9]/-}
  mkdir -p "$T/$1/foreman" && printf '1 %s\n' $((NOW - 51 * 60)) > "$T/$1/foreman/keepalive.txt"
  transcript "$d" "$ID" 50
  printf '{"type":"user","timestamp":"%s","message":{"content":"Keepalive"}}\n' "$(TZ=UTC p_date "@$((NOW - 51 * 60))" +%Y-%m-%dT%H:%M:%S.000Z)" > "$d/$ID.jsonl"
  printf '{"type":"assistant","timestamp":"%s","message":{"content":"Idle","usage":%s}}\n' "$(TZ=UTC p_date "@$((NOW - 50 * 60 - 5))" +%Y-%m-%dT%H:%M:%S.123Z)" "$2" >> "$d/$ID.jsonl"
  TZ=UTC touch -t "$(TZ=UTC p_date "@$((NOW - 50 * 60))" +%Y%m%d%H%M.%S)" "$d/$ID.jsonl"
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

# The ping's turn wrote the whole cache again and read none: no ping now, nor a minute later, and the stop is logged
# with the usage; activity 10 minutes after NOW starts the pings again 50 minutes later.
P=/r/main/project
stopped() {
  local d=$T/miss/cfg/projects/${P//[^A-Za-z0-9]/-}
  pinged miss '{"input_tokens":3,"cache_creation_input_tokens":41000,"cache_read_input_tokens":0}'
  ! poll miss "$P" && ! poll miss "$P" 60 && grep -qF 'wrote 41000 tokens to the cache and read none (input 3)' "$T/miss/foreman/keepalive.log" \
    && TZ=UTC touch -t "$(TZ=UTC p_date "@$((NOW + 600))" +%Y%m%d%H%M.%S)" "$d/$ID.jsonl" && poll miss "$P" 3600
}
check "a keepalive turn that wrote the cache and read none stops the pings until new activity" stopped

# Bug: the first turn after the ping was read, so a cold keepalive reply stopped the pings though the owner used the
# Foreman 2 minutes after the ping (too soon to reset the count) and that turn read the cache the ping wrote.
owner() {
  local d=$T/owner/cfg/projects/${P//[^A-Za-z0-9]/-}
  pinged owner '{"input_tokens":3,"cache_creation_input_tokens":41000,"cache_read_input_tokens":0}'
  printf '{"type":"user","timestamp":"%s","message":{"content":"Status?"}}\n{"type":"assistant","timestamp":"%s","message":{"content":"All quiet","usage":%s}}\n' \
    "$(TZ=UTC p_date "@$((NOW - 49 * 60 - 5))" +%Y-%m-%dT%H:%M:%S.000Z)" "$(TZ=UTC p_date "@$((NOW - 49 * 60))" +%Y-%m-%dT%H:%M:%S.000Z)" \
    '{"input_tokens":5,"cache_creation_input_tokens":300,"cache_read_input_tokens":41000}' >> "$d/$ID.jsonl"
  TZ=UTC touch -t "$(TZ=UTC p_date "@$((NOW - 49 * 60))" +%Y%m%d%H%M.%S)" "$d/$ID.jsonl"
  poll owner "$P" 60
}
check "an owner's turn after a cold keepalive reply, within 5 minutes of the ping: the pings go on" owner

pinged hit '{"input_tokens":3,"cache_creation_input_tokens":200,"cache_read_input_tokens":41000}'
check "a keepalive turn that read the cache: the pings go on" poll hit "$P"

pinged unread '"none"'
check "a keepalive turn whose usage cannot be read: the pings go on" poll unread "$P"

[ "$fails" = 0 ]
