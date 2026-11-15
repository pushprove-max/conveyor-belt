#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# watch-idle.sh [--once] -- keeps the Foreman session's 1-hour prompt cache warm while it is idle, run by waiter.sh.
# Past an hour with no turn the next turn writes the whole cache again; a turn every 50 minutes reads it instead.
# The last activity is the modification time of the Foreman's own transcript, <marked session id>.jsonl in its
# project folder (Claude Code's, under CLAUDE_CONFIG_DIR, else ~/.claude: the checkout's path, every other character
# a dash, cut past 200 characters to those and a dash and a hash, as foreman.sh launch reads it); another session's
# transcript in that folder is not the Foreman's activity.
# Once a minute, when that is 50 minutes old, it puts one wake in pending and exits. At most 10 pings in a row, then
# none until real activity: keepalive.txt holds "<count> <epoch of the last ping>", and the count goes back to 0
# once the last activity is more than 5 minutes after the last ping (the ping's own turn writes within seconds).
# For tests: CONVEYOR_FOREMAN_NOW (the clock), --once.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
IDLE_S=3000 REAL_S=300 MAX_PINGS=10
STATE=$FD/keepalive.txt
PROJECTS=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects ENC=${CLAUDE_PROJECT_DIR:-$PWD}
ENC=${ENC//[^A-Za-z0-9]/-}
[ ${#ENC} -le 200 ] || ENC="${ENC:0:200}-*"
poll() { # 0 when a ping was put in pending
  local now last=0 t f count=0 at=0 id
  now=${CONVEYOR_FOREMAN_NOW:-$(date +%s)}
  id=$(marked); [ -n "$id" ] || return 1
  for f in "$PROJECTS"/$ENC/"$id.jsonl"; do
    t=$(p_stat "$f" | cut -d' ' -f2) && [ -n "$t" ] || continue
    [ "$t" -gt "$last" ] && last=$t
  done
  [ "$last" -gt 0 ] && [ $((now - last)) -ge $IDLE_S ] || return 1
  { read -r count at < "$STATE"; } 2>/dev/null
  [[ $count =~ ^[0-9]+$ && $at =~ ^[0-9]+$ ]] || count=0 at=0
  [ $((last - at)) -gt $REAL_S ] && count=0
  [ "$count" -lt $MAX_PINGS ] || return 1
  count=$((count + 1))
  printf 'Keepalive: idle %d min, refreshing the 1-hour cache (ping %d of %d). Nothing to do: reply Idle.\n' \
    $(((now - last) / 60)) "$count" $MAX_PINGS | pending_put || return 1
  printf '%s %s\n' "$count" "$now" > "$STATE"
}
while :; do
  poll && exit 0
  [ "${1:-}" != --once ] || exit 1
  sleep 60
done
