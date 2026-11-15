#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# waiter.sh -- the Foreman's one stop-hook waiter (Stop, asyncRewake, the Foreman session only). It runs every
# watcher together as its own children and stays alive as their parent across turns; when one puts a wake in pending
# and exits, the waiter stops the rest and exits 2 with every pending wake, whole, on stderr, which wakes the
# session. The next stop starts it again. It never blocks a turn, and only one runs per Foreman (waiter.lock): a
# stop while one is alive passes.
# The watchers: watch-conveyor.sh, watch-limit.sh, watch-alerts.sh, watch-idle.sh. One that exits with nothing put
# died: it is started again after 5 s, up to 3 times an hour each; past that one WATCHER DOWN wake names it.
# The hook is ended at its 86400 s timeout, and nothing would start it again in a day with no wake: after 23 hours
# with nothing it wakes the session with one renew line.
# The text relayed is never cut: every wake names every item (watch-conveyor.sh). It is kept as last-wake.txt, so the
# reply check (stop.sh) knows a turn a wake started. A relayed wake leaves pending only once it is on stderr: a kill
# before that relays it again, never loses it.
# The waiter and its watchers run from the install the shim started it from (versions/<commit>). Once a minute it
# reads the commit the project runs now (its pack's plugin.commit, else for a pack that follows the plugin its
# conveyor-engine.json commit, as shim.sh reads them); when that is another installed commit, it stops its watchers
# and runs again from that install, in this same hook, so no wake is missed while the install moves. An update of
# the install (lib/install.sh, prune) keeps the version folder waiter.pid names while this waiter's pid runs.
# For tests: CONVEYOR_FOREMAN_WATCHERS (the watchers, one command line each, in place of the four),
# CONVEYOR_FOREMAN_RENEW (seconds, 82800), CONVEYOR_FOREMAN_LOOK (seconds between two reads of the commit, 60).
set -u
SID=$(jq -r '.session_id // empty | strings' 2>/dev/null)
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 0
foreman "$SID" || exit 0
# FROM: the commit of the install this copy runs from, by the path it was started by (the shim's, links not
# followed); empty when it runs from a checkout, which never moves.
VERSIONS=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/versions
FROM=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
[ "${FROM%/*}" = "$VERSIONS" ] && [[ ${FROM##*/} =~ ^[0-9a-f]{40}$ ]] && FROM=${FROM##*/} || FROM=''
# moved: prints the commit the project runs now when it is installed and is not FROM; nonzero otherwise.
moved() {
  local c
  [ -n "$FROM" ] || return 1
  c=$(jq -r '.plugin.commit // empty | strings' "$CONVEYOR_MAIN/.conveyor/project.json" 2>/dev/null)
  [ -n "$c" ] || c=$(jq -r '.commit // empty | strings' "$CONVEYOR_MAIN/.git/conveyor-engine.json" 2>/dev/null)
  [[ $c =~ ^[0-9a-f]{40}$ ]] && [ "$c" != "$FROM" ] && [ -f "$VERSIONS/$c/conveyor/foreman/waiter.sh" ] && printf '%s' "$c"
}
# waiter.pid (in the Foreman's folder, lib.sh FD), "<pid> <commit it runs from, - from a checkout> <session>", names
# the live waiter: a claim by another session of the same Foreman stops it (lib.sh claim), and an update keeps that
# commit's install. The session is last, as it may be empty. The mark is read again once waiter.pid is written: a claim or off
# between the first check and then read the old waiter.pid, so it is this waiter that stands down.
mkdir -p "$FD" && exec 7>>"$FD/waiter.lock" && flock -n 7 && printf '%s %s %s\n' "$$" "${FROM:--}" "$SID" > "$FD/waiter.pid" || exit 0
foreman "$SID" || exit 0
ACK=$(mktemp) || exit 0
deliver() { # 0 when anything pending went to stderr
  : > "$ACK"
  local text; text=$(pending_run "$ACK") || return 1
  trap '' TERM HUP INT
  printf '%s\n' "$text" >&2 && printf '%s\n' "$text" > "$FD/last-wake.txt"
  while IFS= read -r f; do rm -f "$f"; done < "$ACK"
}
declare -A CMD=() PID=() TRIES=()
# stop_all: every watcher's process group is gone before it returns (TERM, then KILL after 5 s), so the waiter frees
# waiter.lock, which a claim waits on, only once no watcher of its runs: two Foremen never run the same watchers.
stop_all() {
  local p i alive
  for p in "${PID[@]}"; do kill -TERM -- "-$p" 2>/dev/null; done
  for i in $(seq 50); do
    alive=; for p in "${PID[@]}"; do kill -0 -- "-$p" 2>/dev/null && alive=1; done
    [ -n "$alive" ] || break
    sleep 0.1
  done
  for p in "${PID[@]}"; do kill -KILL -- "-$p" 2>/dev/null; done
  wait "${PID[@]}" 2>/dev/null; rm -f "$ACK"
}
trap 'kill "${sp:-}" 2>/dev/null; stop_all; exit 0' TERM HUP INT
deliver && { rm -f "$ACK"; exit 2; }
if [ -n "${CONVEYOR_FOREMAN_WATCHERS:-}" ]; then
  while IFS= read -r c; do [ -z "$c" ] || CMD[$c]=$c; done <<<"$CONVEYOR_FOREMAN_WATCHERS"
else
  for w in watch-conveyor.sh watch-limit.sh watch-alerts.sh watch-idle.sh; do CMD[$w]="bash $(printf %q "$FHERE/$w")"; done
fi
start() { # <name>: in its own process group, so stopping it stops its sleep too; without the lock
  set -m; bash -c "${CMD[$1]}" > /dev/null 2>&1 7>&- & PID[$1]=$!; set +m
}
for w in "${!CMD[@]}"; do start "$w"; done
renew=${CONVEYOR_FOREMAN_RENEW:-82800} look=${CONVEYOR_FOREMAN_LOOK:-60}
# The renew time, an epoch: a waiter that took a moved one's place (below) keeps that one's, as the hook it runs in
# is the same, ended at the same timeout.
end=${CONVEYOR_FOREMAN_END:-$(( $(date +%s) + renew ))}
while :; do
  left=$(( end - $(date +%s) ))
  if [ "$left" -le 0 ]; then
    echo "Renew: $((renew / 3600)) hours with nothing to report; no action needed. Reply: Idle" | pending_put
    deliver; stop_all; exit 2
  fi
  sleep "$(( left < look ? left : look ))" 7>&- & sp=$!
  wait -n -p done "${PID[@]}" "$sp"; kill "$sp" 2>/dev/null
  deliver && { stop_all; exit 2; }
  # The install moved: the watchers stop, and the waiter of the new install takes this one's place (its exec 7>>
  # closes this waiter.lock, so its flock takes it), with this one's renew time.
  if new=$(moved); then
    stop_all; CONVEYOR_FOREMAN_END=$end exec bash "$VERSIONS/$new/conveyor/foreman/waiter.sh" <<<"$(jq -cn --arg s "$SID" '{session_id: $s}')"
  fi
  for w in "${!PID[@]}"; do
    [ "${PID[$w]}" = "${done:-}" ] || continue
    now=$(date +%s); kept=()
    for t in ${TRIES[$w]:-}; do [ $((now - t)) -ge 3600 ] || kept+=("$t"); done
    if [ ${#kept[@]} -ge 3 ]; then
      echo "WATCHER DOWN: $w exited with nothing to report 4 times in an hour; it is not started again until the next stop" | pending_put
      deliver; stop_all; exit 2
    fi
    TRIES[$w]="${kept[*]} $now"
    sleep 5 7>&-
    start "$w"
  done
done
