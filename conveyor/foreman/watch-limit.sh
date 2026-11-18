#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# watch-limit.sh [<threshold %>=90] -- the Foreman's usage-limit watcher, run by waiter.sh. Every 5 minutes it reads
# Claude's own 7-day usage (dashboard_limit.py fetch, the Board's source; never a model call) and, once the usage is
# at or over the threshold, puts one wake in pending and exits: once per limit window. The seen keys
# (limit-<threshold>-<resets at>, or limit-<threshold>-unknown-<UTC date> for a reading with no reset time, so such
# a reading wakes at most once a day) are in limit-seen.txt, so a restart never repeats a wake.
# For tests: CONVEYOR_FOREMAN_LIMIT_CMD (run in place of the read; prints its JSON), CONVEYOR_FOREMAN_NOW (the clock),
# --once (one poll).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
[ "${1:-}" != --once ] || { ONCE=1; shift; }
T=${1:-90}; [[ $T =~ ^[0-9]+$ ]] || { echo "usage: watch-limit.sh [--once] [<threshold %>]" >&2; exit 2; }
SEEN=$FD/limit-seen.txt
mkdir -p "$FD" && touch "$SEEN" || exit 1
read_limit() {
  if [ -n "${CONVEYOR_FOREMAN_LIMIT_CMD:-}" ]; then bash -c "$CONVEYOR_FOREMAN_LIMIT_CMD"
  else timeout -k 2 30 python3 "$FHERE/../../.claude/scripts/dashboard_limit.py" fetch; fi
}
poll() { # 0 when a wake was put in pending
  local r used reset hour key
  # The reset time comes back with a jitter of a second or so (05:59:59.7, then 06:00:00.4), so the key holds it rounded
  # to the hour: one wake a window, not one a poll.
  r=$(read_limit 2>/dev/null | jq -er '.seven_day | select(.utilization | numbers) | (.resets_at // null) as $r
    | "\(.utilization) \($r // "unknown") \(if $r == null then "unknown" else ($r | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601 + 1800) / 3600 | floor | tostring end)"') || return 1
  read -r used reset hour <<<"$r"
  awk -v u="$used" -v t="$T" 'BEGIN { exit !(u >= t) }' || return 1
  key=limit-$T-$hour
  [ "$reset" != unknown ] || key=$key-$(TZ=UTC p_date "@${CONVEYOR_FOREMAN_NOW:-$(date +%s)}" +%F) || return 1
  ! grep -qxF -- "$key" "$SEEN" || return 1
  printf '7-day usage limit at %.0f%% (threshold %s%%; resets %s)\n' "$used" "$T" "$reset" | pending_put || return 1
  echo "$key" >> "$SEEN"
}
while :; do
  poll && exit 0
  [ -z "${ONCE:-}" ] || exit 1
  sleep 300
done
