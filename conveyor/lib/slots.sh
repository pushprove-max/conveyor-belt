#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The machine's test slots. Sourced, never run.
# One pool for the machine, shared by every Conveyor on it (each checkout the host file names, and a test runner started
# by hand): the folder /tmp/conveyor-test-slots, the same whatever the user's environment names, holding one file per
# slot, 1 to N. N is the host file's testSlots, never more than the machine's cores, which it is with none. (The host file's testSlotsDir, else
# CONVEYOR_TEST_POOL, names another folder: a pool of the engine's own tests; slot_pool.) A test worker (the loop's test run of a card, one engine case, one unit of
# the closure test) holds a slot while it runs: an flock on the slot's file, through a descriptor the worker and
# everything it starts inherit, so the slot is held until the last process of the worker has ended, however each ends,
# and comes back then (a process that closed the descriptor: slot_left, slot_watch). A worker with no slot waits; it does not
# start. Slot k is the k-th core the machine lets a test use (slot_cpus), so no two slots are one core: a worker and
# what it starts are pinned to their slot's core (slot_mine; Linux, where taskset is), and a worker that cannot be
# pinned there does not start. A test command that starts more processes than it holds slots runs them on its own core, never on another run's. Test runs then never share a core, and a
# case's own waits are not stretched by another card's suite (the owner, 2026-11-12: with ten cards each running
# cores/2 cases the load reached 87).
# The loop's test run of a card holds one slot for the whole run: the run's home slot. CONVEYOR_TEST_SLOT tells what
# the run starts which descriptor holds it, and is believed only when that descriptor is a slot file of the pool whose
# lock it holds (slot_pool). A runner inside the run gives the home slot to one worker at a time (a turn: a lock on a
# file beside the slot's, named after it) and takes a slot of the pool for each worker beside it, so a run always has
# one worker going and never waits on the pool for it. A worker is itself a run for the runners it starts.

# The cores the machine lets a test use, one a line, in order: asked of a process that first asks for every core, so
# a runner pinned to its own slot's core still names them all, and a machine that keeps its tests to some of its cores
# names only those. Nothing where taskset is not (macOS): no worker is pinned there.
slot_cpus() {
  local l r x
  command -v taskset >/dev/null || return 0
  l=$(taskset -cp "0-$(( $(nproc --all) - 1 ))" "$BASHPID" >/dev/null 2>&1; taskset -cp "$BASHPID" 2>/dev/null)
  l=${l##*: }; IFS=, read -ra r <<<"$l"
  for x in "${r[@]}"; do [[ $x =~ ^[0-9]+(-[0-9]+)?$ ]] || continue; for ((l = 10#${x%-*}; l <= 10#${x#*-}; l++)); do echo "$l"; done; done
}

# Sets SLOT_DIR (the pool's folder), SLOT_N (its size), SLOT_CPUS (the cores of its slots: slot_cpus) and, inside a run that holds
# a slot, SLOT_HOME (the descriptor that holds it), SLOT_HOME_K (the slot's number) and SLOT_TURN (the turns already
# taken on it, above this runner); SLOT_HOME is empty outside one.
# Where the host file names no testSlotsDir, CONVEYOR_TEST_POOL (<size>:<folder>) names the pool instead: the engine's
# test runner (tests/lib.sh) names its own pool so to the loops its cases run, whose host file is the case's and names
# none. A case's loop read the machine's pool, found the case's slot of the runner's pool no slot of it, and waited
# for one of the machine's slots (the owner, 2026-11-14: the engine suite hung whenever the belts held them all).
slot_pool() {
  local host=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json f n p='' fd=${CONVEYOR_TEST_SLOT:-} c
  SLOT_DIR=$(jq -er '.testSlotsDir | strings | select(startswith("/"))' "$host" 2>/dev/null) \
    || if [[ ${CONVEYOR_TEST_POOL:-} =~ ^([1-9][0-9]{0,5}):(/.*)$ ]]; then p=${BASH_REMATCH[1]} SLOT_DIR=${BASH_REMATCH[2]}; else SLOT_DIR=/tmp/conveyor-test-slots; fi
  # The cores, each followed by a space, read with no program but slot_cpus's own (#532).
  mapfile -t c < <(slot_cpus); SLOT_CPUS=''; n=${#c[@]}; [ "$n" = 0 ] || printf -v SLOT_CPUS '%s ' "${c[@]}"; [ "$n" -ge 1 ] || n=$(nproc --all)
  # A pool larger than the cores would put two slots on one core: it is the cores.
  SLOT_N=${p:-$(jq -er '.testSlots | numbers | floor | select(. >= 1)' "$host" 2>/dev/null)} && [ "$SLOT_N" -le "$n" ] || SLOT_N=$n
  mkdir -p "$SLOT_DIR" || { echo "conveyor: the test slots folder $SLOT_DIR cannot be made: no test can take a slot" >&2; return 1; }
  for ((f = 1; f <= SLOT_N; f++)); do
    [ -e "$SLOT_DIR/$f" ] || : >> "$SLOT_DIR/$f" || { echo "conveyor: the test slot $SLOT_DIR/$f cannot be made: no test can take a slot" >&2; return 1; }
  done
  SLOT_HOME=''; SLOT_HOME_K=''; SLOT_TURN=${fd#"${fd%%.*}"}; fd=${fd%%.*}
  case $fd in ''|*[!0-9]*) return 0 ;; esac
  # Only slots 1 to SLOT_N: a numbered file of the folder beyond them (a slot of a larger pool, since cut) is no slot.
  for ((f = 1; f <= SLOT_N; f++)); do
    if [ "/dev/fd/$fd" -ef "$SLOT_DIR/$f" ] && flock -n "$fd" 2>/dev/null; then SLOT_HOME=$fd; SLOT_HOME_K=$f; break; fi
  done
}

# Takes a slot of the pool that is free now: SLOT_FD is the descriptor that holds it, SLOT_K its number. 1 when none is
# free, or when a push waits for one (slot_yield).
slot_try() {
  for ((SLOT_K = 1; SLOT_K <= SLOT_N; SLOT_K++)); do
    { exec {SLOT_FD}>>"$SLOT_DIR/$SLOT_K"; } 2>/dev/null || continue
    if flock -n "$SLOT_FD"; then
      slot_yield || { SLOT_ENV=$SLOT_FD; return 0; }
      exec {SLOT_FD}>&-; return 1
    fi
    exec {SLOT_FD}>&-
  done
  return 1
}

# Waits up to [seconds] (1) for one slot of the pool, picked at random, so a waiting worker costs no busy loop. 1 when
# it has none yet, or a push waits for one (slot_yield): the caller asks again.
slot_wait() {
  SLOT_K=$((RANDOM % SLOT_N + 1))
  { exec {SLOT_FD}>>"$SLOT_DIR/$SLOT_K"; } 2>/dev/null || { sleep "${1:-1}"; return 1; }
  if flock -w "${1:-1}" "$SLOT_FD"; then
    slot_yield || { SLOT_ENV=$SLOT_FD; return 0; }
    exec {SLOT_FD}>&-; sleep 0.1; return 1
  fi
  exec {SLOT_FD}>&-; return 1
}

# True when a push waits for a slot (slot_first) and this is not it: the slot just taken is given back, so the push
# takes it ahead of every test worker that waits. A push's claim is a file of $SLOT_DIR/first that its push holds an
# flock on; one no process holds (its push was killed) counts for nothing.
slot_yield() {
  local f
  [ -z "${SLOT_FIRST:-}" ] || return 1
  for f in "$SLOT_DIR"/first/[0-9]*; do [ -e "$f" ] && ! flock -n "$f" true 2>/dev/null && return 0; done
  return 1
}

# A slot for a push, taken ahead of every test worker that waits for one (the owner, 2026-11-15: pushes ran outside the
# pool, beside every card's test units, and a full machine starved their pre-push checks until their limit killed
# them). It still waits while every slot is held, but gets the next one that comes free: its claim (slot_yield) makes a
# worker that takes that slot give it back. The claim is made under a hidden name, locked, then given its number, so no
# worker sees it unlocked and a push that is killed leaves none that counts; the push drops claims left so. Sets SLOT_FD
# and SLOT_K as slot_try does.
slot_first() {
  local d=$SLOT_DIR/first f cfd=''
  { mkdir -p "$d" && exec {cfd}>>"$d/.$BASHPID" && flock "$cfd" && mv -f "$d/.$BASHPID" "$d/$BASHPID"; } 2>/dev/null \
    || { [ -z "$cfd" ] || exec {cfd}>&-; rm -f "$d/.$BASHPID"; echo "conveyor: the push's claim on the next test slot could not be made in $d" >&2; return 1; }
  for f in "$d"/[0-9]*; do [ "$f" = "$d/$BASHPID" ] || ! flock -n "$f" true 2>/dev/null || rm -f "$f"; done
  until SLOT_FIRST=1 slot_try || SLOT_FIRST=1 slot_wait 0.1; do :; done
  rm -f "$d/$BASHPID"; exec {cfd}>&-
}

# A test run's ask, which the mutation checks of every project on the machine give way to (lib/mutate.sh mutheld()):
# a file of $SLOT_DIR/asks that the run (tests()) holds an flock on from before it waits for its slot until it ends.
# It is made as a push's claim is (slot_first): under a hidden name, locked, then given its number, so no one sees it
# unlocked. An ask no process holds (its run was killed) counts for nothing, and the next ask drops it. SLOT_ASK is
# the descriptor that holds it, empty when none was made.
slot_ask() {
  local d=$SLOT_DIR/asks f
  SLOT_ASK=''
  { mkdir -p "$d" && exec {SLOT_ASK}>>"$d/.$BASHPID" && flock "$SLOT_ASK" && mv -f "$d/.$BASHPID" "$d/$BASHPID"; } 2>/dev/null \
    || { [ -z "$SLOT_ASK" ] || exec {SLOT_ASK}>&-; SLOT_ASK=''; rm -f "$d/.$BASHPID"; return 1; }
  SLOT_ASKF=$d/$BASHPID
  for f in "$d"/[0-9]*; do [ "$f" = "$SLOT_ASKF" ] || ! flock -n "$f" true 2>/dev/null || rm -f "$f"; done
}
slot_unask() { [ -z "${SLOT_ASK:-}" ] || { rm -f "$SLOT_ASKF"; exec {SLOT_ASK}>&-; SLOT_ASK=''; }; }
# How many test runs of the machine ask now (slot_ask); 1 when none does.
slot_asked() {
  local f n=0
  for f in "$SLOT_DIR"/asks/[0-9]*; do [ -e "$f" ] && ! flock -n "$f" true 2>/dev/null && n=$((n + 1)); done
  [ "$n" -gt 0 ] && echo "$n"
}

# A runner's slot for its next worker, waited for: the run's home slot when no other worker of the run is on it
# (asked five times a second, so the next worker starts as the one before it ends), else a slot of the pool.
slot_take() {
  local i=0
  while :; do
    if [ -n "$SLOT_HOME" ] && { exec {SLOT_FD}>>"$SLOT_DIR/$SLOT_HOME_K$SLOT_TURN.t"; } 2>/dev/null; then
      flock -n "$SLOT_FD" && { SLOT_K=$SLOT_HOME_K; SLOT_ENV=$SLOT_HOME$SLOT_TURN.t; return 0; }
      exec {SLOT_FD}>&-
    fi
    if [ $((i++ % 5)) = 0 ] && slot_try; then return 0; fi
    slot_wait 0.2 && return 0
  done
}

# A whole-suite run's turn: at most two runs of a whole suite hold the pool's slots at once (the owner, 2026-11-13:
# a whole-suite run took half the pool, and with three other cards testing beside it a run took three times as long).
# A third waits for its turn as a whole, before any of its workers starts, not worker by worker beside the two, and
# waiting runs get their turns in the order they asked, whoever runs them (a card's test step, a session). A runner
# that runs every case of its suite calls this once, after slot_pool and before its first slot_take; a run of chosen
# cases never does. A turn is a ticket: a file of $SLOT_DIR/whole, numbered as the run asks, before it waits for
# anything, held by an flock through a descriptor the runner and all it starts inherit, as a slot is. A ticket says
# where its run is: empty (it has no slot yet), w<k> (it gave slot k up and waits to take it back), s (it has a slot
# and waits for its turn) or on (it holds a turn). A
# ticket no one holds (its run has ended, however) is dropped by the next runner that looks; tickets are made, dropped
# and changed under one lock, so none is dropped between its making and its flock, and no two runs take the last turn.
# A run holding a turn always has a slot for its workers: a runner with no home slot first takes a slot of the pool
# and makes it its home slot, one run at a time in the order they asked. A run with a slot takes its turn once fewer
# than two are on and no run that asked before it still waits, with a slot or without: a card's test step has its home
# slot before it asks, and one that took a slot freed by a run that ended does not take the turn ahead of a run that
# asked first. When every slot of the pool is held by a run waiting with one and a run that asked before them has no slot
# yet, no slot would come free for that one and no run would go on: the run that asked last of those with a slot gives
# its slot up (a card's step's slot too, as the lock is the descriptor's, which it inherited) and waits as one with
# none, so the run that asked first takes the slot and goes first. It keeps the descriptor and takes that same slot back
# on it (its ticket w<k> says which), so the step holds its slot again, on the core it is pinned to, until its command
# and all it started have ended, not only until this runner ends. A run holding slot k when a run that asked before it
# waits to take k back gives k up too, and waits for it behind that one: else each would wait for the other. A run inside a run
# that holds a turn takes none, as it would wait behind itself: CONVEYOR_TEST_WHOLE names the descriptor, believed only when it is a ticket of this pool whose lock it holds. The
# wait is said on stderr, to the run's output, as slot wait, and the seconds waited so far are written to the file
# CONVEYOR_TEST_TURNWAIT names, where there is one: the loop's test run does not count them against its timeout (tests()).
slot_whole() {
  local d=$SLOT_DIR/whole l n t s on first early held later yield gave='' gk='' waited='' at=$SECONDS fd=${CONVEYOR_TEST_WHOLE:-}
  mkdir -p "$d" || { echo "conveyor: the whole-suite turns folder $d cannot be made: no whole-suite run can take a turn" >&2; return 1; }
  case $fd in ''|*[!0-9]*) ;; *)
    for t in "$d"/[0-9]*; do [ "/dev/fd/$fd" -ef "$t" ] && flock -n "$fd" 2>/dev/null && return 0; done ;;
  esac
  { exec {l}>>"$d/lock"; } 2>/dev/null || { echo "conveyor: the whole-suite turns lock $d/lock cannot be opened" >&2; return 1; }
  flock "$l"
  # Above every number given out (next) and every ticket still there, so a lost next file puts no run ahead of one
  # that asked before it.
  n=$({ cat "$d/next" 2>/dev/null; ls "$d"; } | grep -x '[0-9]\{1,15\}' | sort -n | tail -n 1)
  n=$((10#${n:-0} + 1)); echo "$n" > "$d/next"
  { exec {SLOT_WHOLE}>>"$d/$n"; } 2>/dev/null && flock -n "$SLOT_WHOLE" && { [ -z "$SLOT_HOME" ] || echo s > "$d/$n"; } \
    || { flock -u "$l"; exec {l}>&-; echo "conveyor: the whole-suite turn $d/$n cannot be taken" >&2; return 1; }
  flock -u "$l"
  while :; do
    # first: no run that asked before this one waits ahead of it. held: the runs waiting with a slot, this one among them.
    # later: a run that asked after this one waits with a slot. yield: a run that asked before this one waits to take
    # back the slot this one holds.
    flock "$l"; on=0; first=1; early=''; held=1; later=''; yield=''
    for t in $(ls "$d" | grep -x '[0-9]\{1,15\}' | sort -n); do
      [ "$t" != "$n" ] || continue
      if flock -n "$d/$t" true 2>/dev/null; then rm -f "$d/$t"; continue; fi
      s=$(cat "$d/$t" 2>/dev/null)
      if [ "$s" = on ]; then on=$((on + 1))
      elif [ "$s" = s ]; then held=$((held + 1)); if [ "$((10#$t))" -gt "$n" ]; then later=1; elif [ -n "$SLOT_HOME" ]; then first=''; fi
      elif [ "$((10#$t))" -lt "$n" ]; then early=1; [ -z "$SLOT_HOME" ] || [ "$s" != "w$SLOT_HOME_K" ] || yield=1
      fi
    done
    if [ -n "$SLOT_HOME" ] && { [ -n "$yield" ] || { [ -n "$early" ] && [ "$held" -ge "$SLOT_N" ] && [ -z "$later" ]; }; } \
      && echo "w$SLOT_HOME_K" > "$d/$n"; then
      flock -u "$SLOT_HOME"; gave=$SLOT_HOME gk=$SLOT_HOME_K SLOT_HOME='' SLOT_HOME_K=''
    fi
    [ -z "$early" ] || first=''
    if [ -n "$SLOT_HOME" ] && [ -n "$first" ] && [ "$on" -lt 2 ]; then
      echo on > "$d/$n" || { flock -u "$l"; exec {l}>&-; echo "conveyor: the whole-suite turn $d/$n cannot be marked taken" >&2; return 1; }
      flock -u "$l"; break
    fi
    flock -u "$l"
    if [ -z "$SLOT_HOME" ] && [ -n "$first" ]; then
      if [ -n "$gave" ]; then flock -w 0.5 "$gave" && SLOT_HOME=$gave SLOT_HOME_K=$gk gave=''
      elif slot_try || slot_wait 0.5; then SLOT_HOME=$SLOT_FD SLOT_HOME_K=$SLOT_K SLOT_TURN=''
      fi
      [ -z "$SLOT_HOME" ] || { flock "$l"; echo s > "$d/$n"; flock -u "$l"; continue; }
    fi
    [ -n "$waited" ] || { waited=1; echo "conveyor: whole-suite runs hold the test slots' two turns or asked for one first: this one waits for its turn" >&2; }
    [ -z "${CONVEYOR_TEST_TURNWAIT:-}" ] || echo "$((SECONDS - at))" > "$CONVEYOR_TEST_TURNWAIT"
    [ -n "$first" ] && [ -z "$SLOT_HOME" ] || sleep 0.5
  done
  exec {l}>&-
  [ -z "$waited" ] || echo "conveyor: slot wait: $((SECONDS - at)) s for a whole-suite turn" >&2
  [ -z "$waited" ] || [ -z "${CONVEYOR_TEST_TURNWAIT:-}" ] || echo "$((SECONDS - at))" > "$CONVEYOR_TEST_TURNWAIT"
  export CONVEYOR_TEST_WHOLE=$SLOT_WHOLE
}

# Run by a worker as it starts, in its own process: what it starts is told the slot it holds, and it is pinned to
# the slot's core, with all it starts. A worker that cannot be pinned there would share another slot's core: it ends
# here, before its work starts.
slot_mine() {
  local c
  export CONVEYOR_TEST_SLOT=$SLOT_ENV
  [ -n "$SLOT_CPUS" ] || return 0
  read -ra c <<<"$SLOT_CPUS"
  [ -n "${c[SLOT_K - 1]:-}" ] && taskset -cp "${c[SLOT_K - 1]}" "$BASHPID" >/dev/null 2>&1 \
    || { echo "conveyor: test slot $SLOT_K has no core this worker can be pinned to: the worker does not start" >&2; exit 1; }
}

# The box a test file runs in (the owner, 2026-11-14: a test pinned to its slot's core could still move its work onto
# other cores, and take the machine from every other card): a hard limit of its slot's share of the machine, one core
# (CPUQuota=100%) and the machine's memory over the pool's slots (MemoryMax), a scope of the user's systemd that the
# command's own process moves into as it starts (systemd-run --user --scope), so it keeps its process, group,
# descriptors and environment. Sets SLOT_BOX to the words put before a command to start it so ("${SLOT_BOX[@]}"
# <command>), each box saying so to all it starts (CONVEYOR_TEST_BOX). None, and no limit (as before boxes), where no
# such scope can be made: no systemd-run (macOS), no user manager, or a systemd that cannot be told to leave the `$`
# of the command's words alone (--expand-environment); and inside a box already, as a box made there would be a scope
# beside it, outside its limit. Called once, after slot_pool: it tries a box (about 10 ms). Inside a steered card test
# run (steer_words: CONVEYOR_STEER_SLICE) each box goes in the run's slice, so it stays lowered with the run.
slot_box() {
  local m s=()
  SLOT_BOX=()
  [ -z "${CONVEYOR_TEST_BOX:-}" ] && command -v systemd-run >/dev/null 2>&1 || return 0
  m=$(awk -v n="$SLOT_N" '/^MemTotal:/ { printf "%d", $2 / 1024 / n }' /proc/meminfo 2>/dev/null) && [ "${m:-0}" -gt 0 ] || return 0
  [[ ! ${CONVEYOR_STEER_SLICE:-} =~ ^conveyor_steer_[0-9]+\.slice$ ]] || s=(--slice="$CONVEYOR_STEER_SLICE")
  SLOT_BOX=(systemd-run --user --scope --quiet --collect --expand-environment=no "${s[@]}" -p CPUQuota=100% -p "MemoryMax=${m}M" -- env CONVEYOR_TEST_BOX=1)
  timeout 10 "${SLOT_BOX[@]}" true >/dev/null 2>&1 </dev/null || SLOT_BOX=()
}

# Closes every descriptor from 3 up this shell holds, whatever its number, but those named. A shell that inherited
# many takes its lock and slot descriptors above 255, so a loop up to 255 left them open in the process that should
# hold none. /dev/fd lists the shell's own descriptors on Linux and macOS (the one the listing itself opens is closed
# again before the loop reaches it).
closefds() { # [<fd to keep>...]
  local f k
  for f in /dev/fd/*; do
    f=${f##*/}; [[ $f =~ ^[0-9]+$ ]] && [ "$f" -ge 3 ] || continue
    for k; do [ "$f" != "$k" ] || continue 2; done
    eval "exec $f>&-" 2>/dev/null
  done
}

# Run by a runner before slot_free, once its worker has ended, for a worker that ran as a process group of its own
# (the loop's test command, under timeout): a process of that group still alive may have closed the descriptor that
# holds the slot (a program that closes all it inherits before it starts another), and would run on with the slot
# given to the next worker. A process started here, which waits on nothing else, holds the slot until the group's
# last process has ended: it holds no other descriptor of the runner's (a lock, or a pipe the runner's caller reads
# to its end), and the runner waits on it nowhere.
slot_left() { # <process group>
  pgrep -g "$1" >/dev/null 2>&1 || return 0
  ( closefds "$SLOT_FD"
    while pgrep -g "$1" >/dev/null 2>&1; do sleep 0.5; done ) </dev/null >/dev/null 2>&1 &
  disown $!
}

# Run by a worker before it starts its work, as a process of its own that reads a pipe (an engine case, tests/lib.sh
# run_case): it holds the slot, and no other descriptor of the worker's, until the work and all the work left have
# ended. It is there before the work starts, so a worker killed at any moment leaves it behind. The work writes its
# process group down the pipe and keeps the pipe's other end, as does all it starts: the pipe's end is the work's
# end. A process still alive then closed what it inherited, the slot's descriptor too: it is found by the work's
# group, or, in a session or group of its own, by the work's mark in its environment (the work exports <mark>, a
# NAME=value no other process has). A signal that ends the worker's group does not end this process.
slot_watch() { # <mark>
  local f g
  trap '' TERM
  closefds "$SLOT_FD"
  read -r g; cat > /dev/null
  # The processes' environments are read into a variable: a search started for the mark would carry it itself.
  while pgrep -g "${g:-none}" >/dev/null 2>&1 || { f=$(ps axeww -o pid= -o command= 2>/dev/null); [[ $f == *" $1"* ]]; }; do sleep 0.5; done
}

# Closes the runner's own descriptor of the slot, once the worker it started holds it too: the slot is then the
# worker's, and comes back when the worker and all it started have ended.
slot_free() { exec {SLOT_FD}>&-; }

# How many slots of the pool are held now.
slot_used() {
  local i n=0
  for ((i = 1; i <= SLOT_N; i++)); do flock -n "$SLOT_DIR/$i" true 2>/dev/null || n=$((n + 1)); done
  echo "$n"
}

# Card work yields to the user (the host file's steer; docs/configuration.md, Card work yields to you): the machine a
# card runs on is often the one its user types on. Card build, fix and review sessions run at lowered CPU priority;
# card test runs (a mutation check's runs are test runs too) and a test-speed survey card's sessions at idle CPU and
# disk priority. Only the command started so is lowered, with all it starts: never the loop itself, the Board's server,
# the Foreman's session or a process the user starts. A steer of false in the host file lowers nothing (as before it;
# steer_on, lib/paths.sh).

# Sets STEER to the words put before a command of <kind> (session or test) to start it lowered ("${STEER[@]}"
# <command>), STEER_HOW to what they lower, in words (doctor names it; steer_set reads it), and STEER_SLICE to the
# systemd slice a test run is put in, else empty. All empty with steer off.
# macOS (taskpolicy): a session at the utility clamp (-c utility), a test run in the background (-b: idle CPU and
# disk). Linux: a session at nice 10. A test run: in a slice of the user's systemd of its own, conveyor_steer_<pid>,
# whose CPUWeight and IOWeight are 1 (of the default 100), set before the run starts; a test slot's box made inside
# the run goes in the same slice (slot_box). Where no such slice can be made (no user systemd, or inside a box, where
# a scope would leave the box's limit), each of ionice's idle class, nice 19 and SCHED_IDLE that this user can undo
# again (steer_set up; a move back from nice 19 or SCHED_IDLE needs a privilege most users lack): a lowering that
# could not be undone could starve a test file until its timeout.
steer_words() { # <session | test>
  local u b
  STEER=(); STEER_HOW=''; STEER_SLICE=''
  steer_on || return 0
  if command -v taskpolicy >/dev/null 2>&1; then
    if [ "$1" = session ]; then STEER=(taskpolicy -c utility); else STEER=(taskpolicy -b); fi
    STEER_HOW=${STEER[*]}; return 0
  fi
  if [ "$1" = session ]; then STEER=(nice -n 10) STEER_HOW='nice 10'; return 0; fi
  if [ -z "${CONVEYOR_TEST_BOX:-}" ] && command -v systemd-run >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    STEER_SLICE=conveyor_steer_$BASHPID.slice
    # Bound to the unit the caller runs in (the machine's service), so a stop of the loop's service stops the run too,
    # as when it ran in the service's own group. Only a unit of the user's systemd: a login's scope is the system's.
    u=$(sed -n 's|^0::||p' /proc/self/cgroup 2>/dev/null); b=()
    [[ $u != */user@*.service/* || ! ${u##*/} =~ ^[A-Za-z0-9:_.@-]+\.(service|scope)$ ]] || b=(-p "BindsTo=${u##*/}" -p "After=${u##*/}")
    STEER=(systemd-run --user --scope --quiet --collect --expand-environment=no --slice="$STEER_SLICE" "${b[@]}" -- env CONVEYOR_STEER_SLICE="$STEER_SLICE")
    if timeout 10 systemctl --user set-property --runtime "$STEER_SLICE" CPUWeight=1 IOWeight=1 >/dev/null 2>&1 </dev/null \
      && timeout 10 "${STEER[@]}" true >/dev/null 2>&1 </dev/null; then STEER_HOW='systemd CPUWeight=1 IOWeight=1'; return 0; fi
    steer_end; STEER=()
  fi
  ! command -v ionice >/dev/null 2>&1 || ! ionice -c 3 sh -c 'ionice -c 2 -p $$' >/dev/null 2>&1 || { STEER+=(ionice -c 3); STEER_HOW+=' ionice idle'; }
  ! nice -n 19 sh -c 'renice -n 0 -p $$' >/dev/null 2>&1 || { STEER+=(nice -n 19); STEER_HOW+=' nice 19'; }
  ! command -v chrt >/dev/null 2>&1 || ! chrt -i 0 sh -c 'chrt -o -p 0 $$' >/dev/null 2>&1 || { STEER+=(chrt -i 0); STEER_HOW+=' SCHED_IDLE'; }
  STEER_HOW=${STEER_HOW# }
}

# Drops the slice steer_words made (its runtime settings with it), once the run in it has ended.
steer_end() { [ -z "${STEER_SLICE:-}" ] || timeout 10 systemctl --user revert "$STEER_SLICE" >/dev/null 2>&1 </dev/null; STEER_SLICE=''; }

# The processes of the steered run <process group>: those of the group, and every process under its leader, as a test
# runner's workers can each be a process group of their own (the engine's own cases are: tests/lib.sh run_case).
steer_pids() { # <process group>
  { pgrep -g "$1"
    ps -A -o pid= -o ppid= | awk -v r="$1" '{ k[$2] = k[$2] " " $1; e[$1] = 1 }
      END { q[1] = r; n = 1; for (i = 1; i <= n; i++) { if (e[q[i]]) print q[i]; m = split(k[q[i]], c, " "); for (j = 1; j <= m; j++) q[++n] = c[j] } }'
  } 2>/dev/null | sort -un
}

# Gives the steered run <process group> its normal priority (up), or lowers it again as steer_words did (down): its
# slice's weights, else each of its processes (steer_pids).
steer_set() { # <up | down> <process group>
  local p w=1 c=3 n=19 i=-i
  [ "$1" = down ] || { w=100 c=2 n=0 i=-o; }
  if [ -n "$STEER_SLICE" ]; then
    timeout 10 systemctl --user set-property --runtime "$STEER_SLICE" "CPUWeight=$w" "IOWeight=$w" >/dev/null 2>&1 </dev/null; return 0
  fi
  for p in $(steer_pids "$2"); do
    case $STEER_HOW in
      taskpolicy*) if [ "$1" = up ]; then taskpolicy -B -p "$p"; else taskpolicy -b -p "$p"; fi ;;
      *) [[ $STEER_HOW != *ionice* ]] || ionice -c "$c" -p "$p"
         [[ $STEER_HOW != *'nice 19'* ]] || renice -n "$n" -p "$p"
         [[ $STEER_HOW != *SCHED_IDLE* ]] || chrt "$i" -p 0 "$p" ;;
    esac
  done >/dev/null 2>&1
}

# The CPU time of <process group>'s processes (steer_pids), in hundredths of a second, and how many of them are
# runnable now: "<cpu> <runnable>". Linux reads /proc (each process's own times and its waited-for children's); elsewhere ps.
steer_use() { # <process group>
  local p l a c=0 n=0 hz
  if [ -r /proc/self/stat ]; then
    hz=$(getconf CLK_TCK 2>/dev/null) && [ "${hz:-0}" -gt 0 ] || hz=100
    for p in $(steer_pids "$1"); do
      read -r l < "/proc/$p/stat" 2>/dev/null || continue
      read -ra a <<<"${l##*) }"
      [ "${a[0]}" != R ] || n=$((n + 1)); c=$((c + a[11] + a[12] + a[13] + a[14]))
    done
    echo "$((c * 100 / hz)) $n"; return 0
  fi
  l=$(steer_pids "$1" | paste -sd, -)
  [ -n "$l" ] || { echo '0 0'; return 0; }
  ps -o stat= -o time= -p "$l" 2>/dev/null | awk '{ k = split($2, t, ":"); s = 0; for (i = 1; i <= k; i++) s = s * 60 + t[i]; c += int(s * 100 + 0.5); if ($1 ~ /^R/) n++ }
    END { printf "%d %d\n", c, n }'
}

# No starvation, beside a steered run <process group>: a run with a process waiting to run (runnable) whose CPU time
# grows by less than a tenth of a second in 3 looks (a look each STEER_TICK seconds, 1 by default) gets its normal
# priority back for 2 looks, then is lowered again. A test file then never times out only because it was lowered.
# Its CPU-second budget is not changed: the budget counts the CPU time it used, whatever its priority.
# It looks while the run's leader <process group> lives, not its group: the watch starts before timeout makes the
# group (testonce), and a survey session (session.sh) is never a group of its own; steer_pids finds its processes.
# Started in the background, it first closes every descriptor it was given, whatever its number (closefds), as
# testclock does: a lock its caller holds (the whole test's on main, maintest()) would else stay held by it, and by
# the sleep it leaves when killed.
steer_watch() { # <process group>
  local c n base=-1 k=0 up=0
  [ -n "$STEER_HOW" ] || return 0
  closefds
  exec </dev/null >/dev/null 2>&1
  while kill -0 "$1" 2>/dev/null; do
    sleep "${STEER_TICK:-1}"
    read -r c n < <(steer_use "$1") || break
    if [ "$up" -gt 0 ]; then up=$((up - 1)); [ "$up" -gt 0 ] || steer_set down "$1"; base=$c k=0; continue; fi
    if [ "$n" -gt 0 ] && [ "$base" -ge 0 ] && [ $((c - base)) -lt 10 ]; then k=$((k + 1)); else base=$c k=0; fi
    [ "$k" -lt 3 ] || { steer_set up "$1"; up=2; }
  done
}
