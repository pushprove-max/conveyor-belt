#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# watch-idle.sh [--once] -- keeps the Foreman session's 1-hour prompt cache warm while it is idle, run by waiter.sh.
# Past an hour with no turn the next turn writes the whole cache again; a turn every 50 minutes reads it instead.
# The last activity is the newest line timestamp in the Foreman's own transcript (the file time when no line in its
# last 500 carries one: Claude Code adds lines with no timestamp, such as cost-state or mode, long after a turn, and
# those are not activity), <marked session id>.jsonl in its
# project folder (Claude Code's, under CLAUDE_CONFIG_DIR, else ~/.claude: the checkout's path, every other character
# a dash, cut past 200 characters to those and a dash and a hash, as foreman.sh launch reads it); another session's
# transcript in that folder is not the Foreman's activity.
# Once a minute, when that is 50 minutes old, it puts one wake in pending and exits. At most 10 pings in a row, then
# none until real activity: keepalive.txt holds "<count> <epoch of the last ping>", and the count goes back to 0
# once the last activity is more than 5 minutes after the last ping (the ping's own turn ends within seconds).
# Before the next ping it reads the usage of the last assistant line at or after the last ping in the transcript: the
# ping's own turn, or the owner's turn when the owner used the Foreman within those 5 minutes. A turn that wrote the
# cache and read none of it (the cache was gone, a 5-minute cache, another model) stops the pings until real activity,
# as the 10th ping does, with a line in keepalive.log. A turn whose usage cannot be read changes nothing.
# For tests: CONVEYOR_FOREMAN_NOW (the clock), --once.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
IDLE_S=3000 REAL_S=300 MAX_PINGS=10
STATE=$FD/keepalive.txt KLOG=$FD/keepalive.log
PROJECTS=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects ENC=${CLAUDE_PROJECT_DIR:-$PWD}
ENC=${ENC//[^A-Za-z0-9]/-}
[ ${#ENC} -le 200 ] || ENC="${ENC:0:200}-*"
# The cache usage of the last assistant line at or after <epoch> in <transcript>, as "<written> <read> <input>";
# nothing when there is none or its usage cannot be read.
turn_usage() { # <transcript> <epoch>
  tail -n 500 "$1" 2>/dev/null | jq -Rnr --argjson at "$2" '
    [inputs | fromjson? | objects | select(.type == "assistant" and (.message | type) == "object")
      | select((try (.timestamp | sub("\\.[0-9]+"; "") | fromdateiso8601) catch -1) >= $at) | .message.usage][-1]
    | objects | select((.cache_creation_input_tokens | type) == "number" and (.cache_read_input_tokens | type) == "number")
    | "\(.cache_creation_input_tokens) \(.cache_read_input_tokens) \(.input_tokens // 0)"' 2>/dev/null
}
# The epoch of the newest line timestamp in the last 500 lines of <transcript>; nothing when none has one.
last_turn() { # <transcript>
  tail -n 500 "$1" 2>/dev/null | jq -Rnr '
    [inputs | fromjson? | objects | .timestamp | strings | try (sub("\\.[0-9]+"; "") | fromdateiso8601) catch empty] | max // empty' 2>/dev/null
}
poll() { # 0 when a ping was put in pending
  local now last=0 t f file='' count=0 at=0 id u w r i
  now=${CONVEYOR_FOREMAN_NOW:-$(date +%s)}
  id=$(marked); [ -n "$id" ] || return 1
  for f in "$PROJECTS"/$ENC/"$id.jsonl"; do
    t=$(last_turn "$f")
    [[ $t =~ ^[0-9]+$ ]] || { t=$(p_stat "$f" | cut -d' ' -f2) && [ -n "$t" ] || continue; }
    [ "$t" -gt "$last" ] && last=$t file=$f
  done
  [ "$last" -gt 0 ] && [ $((now - last)) -ge $IDLE_S ] || return 1
  { read -r count at < "$STATE"; } 2>/dev/null
  [[ $count =~ ^[0-9]+$ && $at =~ ^[0-9]+$ ]] || count=0 at=0
  [ $((last - at)) -gt $REAL_S ] && count=0
  [ "$count" -lt $MAX_PINGS ] || return 1
  if [ "$count" -gt 0 ]; then
    u=$(turn_usage "$file" "$at")
    read -r w r i <<< "$u"
    if [[ ${w:-} =~ ^[0-9]+$ && ${r:-} == 0 && $w -gt 0 ]]; then
      printf '%s stopped the pings until real activity: the last turn since ping %d wrote %d tokens to the cache and read none (input %s)\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$count" "$w" "$i" >> "$KLOG" 2>/dev/null
      printf '%s %s\n' "$MAX_PINGS" "$at" > "$STATE"
      return 1
    fi
  fi
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
