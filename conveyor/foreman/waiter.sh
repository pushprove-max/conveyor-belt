#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# waiter.sh [--check | --held] -- the Foreman's one waiter (the Foreman session only). It runs every watcher together
# as its own children and stays alive as their parent across turns. Only one runs per Foreman (waiter.lock).
# With no argument it is the Stop hook (asyncRewake), the one that can wake the session: when a watcher puts a wake in
# pending and exits, the waiter stops the rest and exits 2 with every pending wake, whole, on stderr, which wakes the
# session. It never blocks a turn: a stop while it is alive passes.
# The hook ends to deliver a wake, so before it exits it starts a waiter that listens while the turn it woke runs
# (--held, on this waiter's own lock, so no other waiter can start between the two): its watchers run, and what they
# find stays in pending. It cannot wake the session; the next stop takes over from it (stops it, then takes the lock)
# and delivers what is pending at once, so a wake seen during a turn reaches the session once that turn ends, once.
# --check is every other hook of the Foreman session (UserPromptSubmit, PostToolUse): when nothing holds waiter.lock
# (the waiter died, or its hook was ended at its timeout) it starts a --held waiter; when a waiter runs it does
# nothing. Every waiter ends when the session's process has gone (the nearest process above the hook that is no
# shell; CONVEYOR_FOREMAN_SESSION_PID in tests): it checks at each look, and again before and after it relays a wake,
# so a wake it could not relay stays in pending. A session that goes on in a new process runs its hooks from that
# one: a stop or hook that finds waiter.lock held by a waiter of another process that has ended takes over (stops it,
# then takes the lock), as that waiter would hold the lock and relay its wakes to no one.
# waiter.log, in the Foreman's folder, has a line when a waiter starts and when it ends, with why (lib.sh
# waiter_state reads it); a waiter killed with no chance to write leaves its start line last.
# The watchers: watch-conveyor.sh, watch-limit.sh, watch-alerts.sh, watch-idle.sh. One that exits with nothing put
# died: it is started again after 5 s, up to 3 times an hour each; past that one WATCHER DOWN wake names it, and it is
# not started again until the next stop (a held waiter leaves it out too: CONVEYOR_FOREMAN_DOWN).
# The hook is ended at its 86400 s timeout, and nothing would start it again in a day with no wake: after 23 hours
# with nothing it wakes the session with one renew line.
# The text relayed is never cut: every wake names every item (watch-conveyor.sh). It is kept as last-wake.txt, so the
# reply check (stop.sh) knows a turn a wake started. A relayed wake leaves pending only once it is on stderr: a kill
# before that relays it again, never loses it.
# The waiter and its watchers run from the install the shim started it from (versions/<commit>). Once a minute it
# reads the commit the project runs now (its pack's plugin.commit, else for a pack that follows the plugin its
# conveyor-engine.json commit, as shim.sh reads them); when that is another installed commit, it stops its watchers
# and runs again from that install, in this same process, so no wake is missed while the install moves. An update of
# the install (lib/install.sh, prune) keeps the version folder waiter.pid names while this waiter's pid runs: each
# waiter lists its Foreman folder in the machine's foremen file (lib/paths.sh FOREMEN), which every prune reads. When
# its install is gone all the same and the project's commit is not installed to move to, it stops its watchers, puts
# one WATCHER DOWN wake and ends (the Stop hook's waiter delivers it at once; a held one leaves it in pending for the
# next stop): the next hook of the session starts a
# waiter again through the shim, which installs the project's commit again.
# For tests: CONVEYOR_FOREMAN_WATCHERS (the watchers, one command line each, in place of the four),
# CONVEYOR_FOREMAN_RENEW (seconds, 82800), CONVEYOR_FOREMAN_LOOK (seconds between two reads of the commit, 60),
# CONVEYOR_FOREMAN_SESSION_PID (the session's process).
set -u
MODE=${1:-}
case $MODE in '' | --check | --held) ;; *) echo "usage: waiter.sh [--check | --held]" >&2; exit 2 ;; esac
SID=$(jq -r '.session_id // empty | strings' 2>/dev/null)
SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/waiter.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 0
foreman "$SID" || exit 0
# FROM: the commit of the install this copy runs from, by the path it was started by (the shim's, links not
# followed); empty when it runs from a checkout, which never moves.
VERSIONS=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/versions
FROM=${SELF%/conveyor/foreman/waiter.sh}
[ "${FROM%/*}" = "$VERSIONS" ] && [[ ${FROM##*/} =~ ^[0-9a-f]{40}$ ]] && FROM=${FROM##*/} || FROM=''
# moved: prints the commit the project runs now when it is installed and is not FROM; nonzero otherwise.
moved() {
  local c
  [ -n "$FROM" ] || return 1
  c=$(jq -r '.plugin.commit // empty | strings' "$CONVEYOR_MAIN/.conveyor/project.json" 2>/dev/null)
  [ -n "$c" ] || c=$(jq -r '.commit // empty | strings' "$CONVEYOR_MAIN/.git/conveyor-engine.json" 2>/dev/null)
  [[ $c =~ ^[0-9a-f]{40}$ ]] && [ "$c" != "$FROM" ] && [ -f "$VERSIONS/$c/conveyor/foreman/waiter.sh" ] && printf '%s' "$c"
}
LOG=$FD/waiter.log
log() { printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$*" >> "$LOG"; } 2>/dev/null
# The session's process: the nearest process above this one that is no shell (the shim and the hook's command line
# are), found once, by the hook, and passed on to the waiters it starts.
if [ -z "${CONVEYOR_FOREMAN_SESSION_PID:-}" ]; then
  p=$PPID
  while [ "${p:-1}" -gt 1 ]; do
    c=$(ps -o comm= -p "$p" 2>/dev/null) || break
    case ${c##*/} in bash | sh | dash | zsh | -bash | -sh | -zsh) p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') ;; *) break ;; esac
  done
  export CONVEYOR_FOREMAN_SESSION_PID=${p:-1}
fi
# held <pid>: 0 when that process is a waiter that listens until the next stop.
held() { [[ $1 =~ ^[0-9]+$ ]] && ps -o args= -p "$1" 2>/dev/null | grep -q '/conveyor/foreman/waiter\.sh --held'; }
# waiter.pid (in the Foreman's folder, lib.sh FD), "<pid> <commit it runs from, - from a checkout> <session's process>
# <session>", names
# the live waiter: a claim by another session of the same Foreman stops it (lib.sh claim), and an update keeps that
# commit's install. The session is last, as it may be empty. The mark is read again once waiter.pid is written: a claim or off
# between the first check and then read the old waiter.pid, so it is this waiter that stands down.
mkdir -p "$FD" || exit 0
if [ "$MODE" = --held ]; then
  flock -n 7 2>/dev/null || exit 0 # the lock its starter took, on fd 7: anything else is no lock of a waiter
else
  exec 7>>"$FD/waiter.lock" || exit 0
  if ! flock -n 7; then
    { read -r old _ osp _ < "$FD/waiter.pid"; } 2>/dev/null
    if [[ ${osp:-} =~ ^[0-9]+$ ]] && [ "$osp" != "$CONVEYOR_FOREMAN_SESSION_PID" ] && ! kill -0 "$osp" 2>/dev/null; then
      log "the $([ -z "$MODE" ] && echo stop || echo hook) of the session's process $CONVEYOR_FOREMAN_SESSION_PID takes over from the waiter $old, whose session's process $osp has ended"
    else
      osp=''
      [ -z "$MODE" ] || exit 0 # --check: a waiter runs
      held "${old:-}" || exit 0 # the waiter that runs can wake the session itself
      log "the stop takes over from the waiter $old, which listened during the turn"
    fi
    kill -TERM "$old" 2>/dev/null
    flock -w 10 7 || { log "the waiter $old did not stop in 10 s; this stop passes"; exit 0; }
  fi
fi
# stop_groups <process group>...: each group is gone before it returns (TERM, then KILL after 5 s).
stop_groups() {
  local p alive
  [ $# -gt 0 ] || return 0
  for p in "$@"; do kill -TERM -- "-$p" 2>/dev/null; done
  for _ in $(seq 50); do
    alive=; for p in "$@"; do kill -0 -- "-$p" 2>/dev/null && alive=1; done
    [ -n "$alive" ] || break
    sleep 0.1
  done
  for p in "$@"; do kill -KILL -- "-$p" 2>/dev/null; done
}
# watchers.pid (in the Foreman's folder): "<process group> <its start time>" of each watcher the waiter runs. A watcher
# closes fd 7, so a waiter killed with no time to stop its watchers frees the lock while they run on: the waiter that
# holds the lock next stops them. The start time is checked, so a group whose number was used again is left alone.
started() { local s; s=$(ps -o lstart= -p "$1" 2>/dev/null) && read -r s <<<"$s" && printf '%s' "$s"; }
orphans=()
while read -r g t; do
  [[ $g =~ ^[0-9]+$ ]] && [ -n "$t" ] && [ "$(started "$g")" = "$t" ] && orphans+=("$g")
done 2>/dev/null < "$FD/watchers.pid"
[ ${#orphans[@]} -eq 0 ] || { log "stops the watchers ${orphans[*]}, which a waiter killed before it could stop them left running"; stop_groups "${orphans[@]}"; }
rm -f "$FD/watchers.pid"
# handoff [<watcher left out>]: starts the waiter that listens until the next stop, on this one's lock (its fd 7), in
# a process group of its own, its output nowhere (a hook's stderr open would hold the wake back), and names it in
# waiter.pid before this one ends, so a stop that comes next finds it. The signals deliver ignores are set back first:
# a shell started with one ignored cannot trap it, and a held waiter that ignores TERM is never taken over.
handoff() {
  local p
  set -m
  (trap - TERM HUP INT; CONVEYOR_FOREMAN_DOWN=${1:-} exec bash "$SELF" --held <<<"$(jq -cn --arg s "$SID" '{session_id: $s}')" > /dev/null 2>&1) & p=$!
  set +m
  printf '%s %s %s %s\n' "$p" "${FROM:--}" "$CONVEYOR_FOREMAN_SESSION_PID" "$SID" > "$FD/waiter.pid"
  why="$why; the waiter $p listens until the next stop"
}
if [ "$MODE" = --check ]; then
  foreman "$SID" || exit 0
  why='nothing held waiter.lock'; [ -z "${osp:-}" ] || why="the waiter of the ended process $osp held waiter.lock"
  log "a hook of the session found no waiter running${osp:+ for its process}: it starts one"
  handoff; exit 0
fi
# Listed for the prune of every project of this machine, whose own lists may not name this Foreman's folder.
FOREMEN=${VERSIONS%/*}/foremen
{ grep -qxF "$FD" "$FOREMEN" || echo "$FD" >> "$FOREMEN"; } 2>/dev/null
printf '%s %s %s %s\n' "$$" "${FROM:--}" "$CONVEYOR_FOREMAN_SESSION_PID" "$SID" > "$FD/waiter.pid"
foreman "$SID" || exit 0
[ ! -f "$LOG" ] || [ "$(wc -l < "$LOG")" -le 400 ] ||{ tail -n 200 "$LOG" > "$LOG.new" && mv "$LOG.new" "$LOG"; } 2>/dev/null
why='' sp=''
log "started from ${FROM:-a checkout}${MODE:+, listening until the next stop}"
trap 'log "ended: ${why:-it stopped for no known reason}"' EXIT
ACK=$(mktemp) || { why='no temporary file could be made'; exit 0; }
# deliver: 0 when anything pending went to stderr while the session's process was alive. What it relays leaves
# pending only then: a wake relayed to an ended process, or one stderr would not take, waits for the next stop.
deliver() {
  : > "$ACK"
  live
  local text; text=$(pending_run "$ACK") || return 1
  trap '' TERM HUP INT
  printf '%s\n' "$text" >&2 || { trap onterm TERM HUP INT; return 1; }
  live
  printf '%s\n' "$text" > "$FD/last-wake.txt"
  while IFS= read -r f; do rm -f "$f"; done < "$ACK"
  why='it delivered a wake'
}
declare -A CMD=() PID=() TRIES=()
# stop_all: every watcher's process group is gone before it returns (TERM, then KILL after 5 s), so the waiter frees
# waiter.lock, which a claim waits on, only once no watcher of its runs: two Foremen never run the same watchers.
stop_all() {
  stop_groups "${PID[@]}"
  wait "${PID[@]}" 2>/dev/null; rm -f "$ACK" "$FD/watchers.pid"
}
# live: returns when the session's process is alive; else the waiter ends here, its watchers stopped and the lock
# freed, with nothing relayed.
live() {
  kill -0 "$CONVEYOR_FOREMAN_SESSION_PID" 2>/dev/null && return 0
  why="the session's process $CONVEYOR_FOREMAN_SESSION_PID has ended"; stop_all; exit 0
}
onterm() {
  kill "${sp:-}" 2>/dev/null; why="it was stopped (a claim, a stop that took over, or the end of its hook)"; stop_all; exit 0
}
trap onterm TERM HUP INT
[ -n "$MODE" ] || ! deliver || { rm -f "$ACK"; handoff; exit 2; }
# down <name>: 0 when the waiter that started this one left that watcher out (CONVEYOR_FOREMAN_DOWN).
down() { [ -n "${CONVEYOR_FOREMAN_DOWN:-}" ] && [ "$1" = "$CONVEYOR_FOREMAN_DOWN" ]; }
if [ -n "${CONVEYOR_FOREMAN_WATCHERS:-}" ]; then
  while IFS= read -r c; do [ -z "$c" ] || down "$c" || CMD[$c]=$c; done <<<"$CONVEYOR_FOREMAN_WATCHERS"
else
  for w in watch-conveyor.sh watch-limit.sh watch-alerts.sh watch-idle.sh; do down "$w" || CMD[$w]="bash $(printf %q "$FHERE/$w")"; done
fi
start() { # <name>: in its own process group, so stopping it stops its sleep too; without the lock
  set -m; bash -c "${CMD[$1]}" > /dev/null 2>&1 7>&- & PID[$1]=$!; set +m
  local w; for w in "${!PID[@]}"; do printf '%s %s\n' "${PID[$w]}" "$(started "${PID[$w]}")"; done > "$FD/watchers.pid"
}
# wakes: how many wakes are pending. A held waiter delivers none, so a watcher that exits as their count grows put one.
wakes() { local f n=0; for f in "$PENDING"/*.wake; do [ -f "$f" ] && n=$((n + 1)); done; echo "$n"; }
for w in "${!CMD[@]}"; do start "$w"; done
had=$(wakes)
renew=${CONVEYOR_FOREMAN_RENEW:-82800} look=${CONVEYOR_FOREMAN_LOOK:-60}
# The renew time, an epoch: a waiter that took a moved one's place (below) keeps that one's, as the hook it runs in
# is the same, ended at the same timeout. A held waiter runs in no hook, so it has none.
end=${CONVEYOR_FOREMAN_END:-$(( $(date +%s) + renew ))}
while :; do
  left=$(( end - $(date +%s) ))
  live
  if [ -n "$MODE" ]; then
    left=$look
  elif [ "$left" -le 0 ]; then
    echo "Renew: $((renew / 3600)) hours with nothing to report; no action needed. Reply: Idle" | pending_put
    deliver; why="$why (the renew)"; stop_all; handoff; exit 2
  fi
  sleep "$(( left < look ? left : look ))" 7>&- & sp=$!
  ended=''; wait -n -p ended "${PID[@]}" "$sp"; kill "$sp" 2>/dev/null
  [ -n "$MODE" ] || ! deliver || { stop_all; handoff; exit 2; }
  # The install moved: the watchers stop, and the waiter of the new install takes this one's place (its exec 7>>
  # closes this waiter.lock, so its flock takes it; a held one keeps its fd 7), with this one's renew time.
  if new=$(moved); then
    stop_all; log "moves to the install $new"; trap - EXIT
    CONVEYOR_FOREMAN_END=$end exec bash "$VERSIONS/$new/conveyor/foreman/waiter.sh" $MODE <<<"$(jq -cn --arg s "$SID" '{session_id: $s}')"
  fi
  # The install it runs from is gone, with no other to move to: its watchers cannot be started again from it, so it
  # never runs on with one missing. One wake, then it ends; no handoff, as its own waiter.sh is gone too.
  if [ -n "$FROM" ] && [ ! -f "$SELF" ]; then
    echo "WATCHER DOWN: the Conveyor install $VERSIONS/$FROM the Foreman's waiter ran from is gone, and the project's commit is not installed; the watchers stopped. The next hook of this session starts them again; if no wake comes after it, run /conveyor-belt:setup in $CONVEYOR_MAIN" | pending_put
    log "its install $FROM is gone"
    if [ -z "$MODE" ] && deliver; then why="$why (its install $FROM is gone)"; stop_all; exit 2; fi
    why="its install $FROM is gone; the wake waits in pending for the next stop"; stop_all; exit 0
  fi
  for w in "${!PID[@]}"; do
    [ "${PID[$w]}" = "${ended:-}" ] || continue
    # A held waiter's watcher that put a wake is started again: the wake waits in pending for the next stop.
    if [ -n "$MODE" ] && [ "$(wakes)" -gt "$had" ]; then had=$(wakes); sleep 5 7>&-; start "$w"; continue; fi
    now=$(date +%s); kept=()
    for t in ${TRIES[$w]:-}; do [ $((now - t)) -ge 3600 ] || kept+=("$t"); done
    if [ ${#kept[@]} -ge 3 ]; then
      echo "WATCHER DOWN: $w exited with nothing to report 4 times in an hour; it is not started again until the next stop" | pending_put
      if [ -n "$MODE" ]; then unset 'PID[$w]'; had=$(wakes); log "$w is down until the next stop"; continue; fi
      deliver; why="$why (WATCHER DOWN: $w)"; stop_all; handoff "$w"; exit 2
    fi
    TRIES[$w]="${kept[*]} $now"
    sleep 5 7>&-
    start "$w"
  done
done
