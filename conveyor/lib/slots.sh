#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The machine's test slots. Sourced, never run.
# p_ncpu (the CPU count) is portable.sh's: a runner that sources this file alone gets it here.
declare -F p_ncpu > /dev/null || . "${BASH_SOURCE[0]%/*}/portable.sh"
# One pool for the machine, shared by every Conveyor on it (each checkout the host file names, and a test runner started
# by hand): the folder /tmp/conveyor-test-slots, the same whatever the user's environment names, holding one file per
# slot, 1 to N. N is the host file's testSlots, never more than the machine's cores less those kept for the user
# (slot_reserved), which it is with none. (The host file's testSlotsDir, else
# CONVEYOR_TEST_POOL, names another folder: a pool of the engine's own tests; slot_pool.) A test worker (the loop's test run of a card, one engine case) holds a slot while it runs: an flock on the slot's file, through a descriptor the worker and
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
# names only those. The cores kept for the user (slot_reserved) are left out, unless they are all the test may use.
# Nothing where taskset is not (macOS): no worker is pinned there.
slot_cpus() {
  slot_cpuset; [ ${#SLOT_CORES[@]} = 0 ] || printf '%s\n' "${SLOT_CORES[@]}"
}
# Sets, in the calling shell, SLOT_CORES (the cores slot_cpus prints) and SLOT_KEPT (the cores kept for the user,
# slot_reserved's), so a caller that needs both asks for the machine's cores and reads the host file once.
slot_cpuset() {
  local l r x k a=() c=() n
  SLOT_CORES=(); SLOT_KEPT=()
  command -v taskset >/dev/null || return 0
  n=$(p_ncpu) || n=''
  l=$({ [ -z "$n" ] || taskset -cp "0-$((n - 1))" "$BASHPID"; } >/dev/null 2>&1; taskset -cp "$BASHPID" 2>/dev/null)
  l=${l##*: }; IFS=, read -ra r <<<"$l"
  mapfile -t SLOT_KEPT < <(slot_reserved "$n"); k=" ${SLOT_KEPT[*]} "
  for x in "${r[@]}"; do [[ $x =~ ^[0-9]+(-[0-9]+)?$ ]] || continue; for ((l = 10#${x%-*}; l <= 10#${x#*-}; l++)); do a+=("$l"); [[ $k == *" $l "* ]] || c+=("$l"); done; done
  [ ${#c[@]} -gt 0 ] || c=("${a[@]}")
  SLOT_CORES=("${c[@]}")
}

# The cores kept for the user (the host file's reserveCores; docs/configuration.md, Cores kept for you), one a line:
# no test slot is on one (slot_cpus), and no card session or test run may run on one (slot_keepwords), so the
# user's terminal and apps always have free cores. A number keeps that many of the machine's highest-numbered cores; a
# list of core numbers keeps those. One core is always left for card work: a number of every core keeps all but
# core 0, and a list that names every core keeps all but its lowest. None where taskset is not (slot_reserve_why).
slot_reserved() { # [the machine's cores (nproc --all), when the caller has read them]
  local n=${1:-}
  command -v taskset >/dev/null || return 0
  [ -n "$n" ] || n=$(p_ncpu) || return 0
  jq -r --argjson n "$n" '.reserveCores
    | if type == "number" then floor | select(. > 0) | [range([$n - ., 1] | max; $n)]
      elif type == "array" then map(numbers | floor | select(. >= 0 and . < $n)) | unique | if length >= $n then .[1:] else . end
      else empty end | .[]' "${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json" 2>/dev/null
}

# The cores left for card work, as taskset takes them ("0,1,2"), when the host file keeps cores for the user
# (slot_reserved); fails when it keeps none.
slot_keep() {
  local k kl c=() i n
  mapfile -t kl < <(slot_reserved); [ ${#kl[@]} -gt 0 ] || return 1
  k=" ${kl[*]} "; n=$(p_ncpu) || return 1
  for ((i = 0; i < n; i++)); do [[ $k == *" $i "* ]] || c+=("$i"); done
  local IFS=,; echo "${c[*]}"
}

# Why this machine cannot keep cores for the user, empty where it can: no program can keep a process off a core
# on macOS, and Linux needs taskset (util-linux) for it.
slot_reserve_why() {
  if command -v taskset >/dev/null; then return 0; fi
  case $OSTYPE in
    darwin*) echo "macOS lets no program keep a process off a core" ;;
    *) echo "taskset (util-linux) is not installed" ;;
  esac
}

# Sets SLOT_DIR (the pool's folder), SLOT_N (its size), SLOT_CPUS (the cores of its slots: slot_cpus) and, inside a
# run that holds a slot, SLOT_HOME (the descriptor that holds it), SLOT_HOME_K (the slot's number) and SLOT_TURN (the turns already
# taken on it, above this runner); SLOT_HOME is empty outside one. SLOT_ONE is CONVEYOR_TEST_ONESLOT, read here (slot_take).
# Where the host file names no testSlotsDir, CONVEYOR_TEST_POOL (<size>:<folder>) names the pool instead: the engine's
# test runner (tests/lib.sh) names its own pool so to the loops its cases run, whose host file is the case's and names
# none. A case's loop read the machine's pool, found the case's slot of the runner's pool no slot of it, and waited
# for one of the machine's slots (the owner, 2026-11-14: the engine suite hung whenever the belts held them all).
slot_pool() {
  local host=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json f n p='' fd=${CONVEYOR_TEST_SLOT:-} c h=()
  # The host file's testSlotsDir and testSlots, read with one jq, each "" where it names none.
  mapfile -d '' -t h < <(jq -j '((.testSlotsDir | strings | select(startswith("/"))) // ""), "\u0000",
    ((.testSlots | numbers | floor | select(. >= 1) | tostring) // ""), "\u0000"' "$host" 2>/dev/null)
  SLOT_DIR=${h[0]:-}; [ -n "$SLOT_DIR" ] \
    || if [[ ${CONVEYOR_TEST_POOL:-} =~ ^([1-9][0-9]{0,5}):(/.*)$ ]]; then p=${BASH_REMATCH[1]} SLOT_DIR=${BASH_REMATCH[2]}; else SLOT_DIR=/tmp/conveyor-test-slots; fi
  # The cores, each followed by a space, read with no program but slot_cpus's own (#532).
  slot_cpuset; c=("${SLOT_CORES[@]}"); SLOT_CPUS=''; n=${#c[@]}; [ "$n" = 0 ] || printf -v SLOT_CPUS '%s ' "${c[@]}"; [ "$n" -ge 1 ] || n=$(p_ncpu)
  # A pool larger than the cores would put two slots on one core: it is the cores.
  SLOT_N=${p:-${h[1]:-}} && [ -n "$SLOT_N" ] && [ "$SLOT_N" -le "$n" ] || SLOT_N=$n
  mkdir -p "$SLOT_DIR" || { echo "conveyor: the test slots folder $SLOT_DIR cannot be made: no test can take a slot" >&2; return 1; }
  for ((f = 1; f <= SLOT_N; f++)); do
    [ -e "$SLOT_DIR/$f" ] || : >> "$SLOT_DIR/$f" || { echo "conveyor: the test slot $SLOT_DIR/$f cannot be made: no test can take a slot" >&2; return 1; }
  done
  SLOT_ONE=${CONVEYOR_TEST_ONESLOT:-}; SLOT_HOME=''; SLOT_HOME_K=''; SLOT_TURN=${fd#"${fd%%.*}"}; fd=${fd%%.*}
  slot_session || return 1
  case $fd in ''|*[!0-9]*) return 0 ;; esac
  # Only slots 1 to SLOT_N: a numbered file of the folder beyond them (a slot of a larger pool, since cut) is no slot.
  for ((f = 1; f <= SLOT_N; f++)); do
    if [ "/dev/fd/$fd" -ef "$SLOT_DIR/$f" ] && flock -n "$fd" 2>/dev/null; then SLOT_HOME=$fd; SLOT_HOME_K=$f; break; fi
  done
}

# A test run started inside a card's build, fix or rebase session (CONVEYOR_CARD, which builder() in lib/session.sh
# exports to the session) holds at most the pack's tunables.sessionTestSlots of the pool's slots at once, however
# many it could get: one session's run of 342 cases held about 12 slots while five other cards built, and slowed
# them all. The loop's own test step, the check on main and a release run carry no mark and keep their share. Sets
# SLOT_CAP, the folder of the card's permits ($SLOT_DIR/session/<card>, one file each, shared by every run of the
# session), empty for a run with no mark; slot_take, and slot_whole for a home slot, take a permit before each slot of the pool (slot_permit), and
# SLOT_CAPFD, a permit's descriptor inherited from the worker that started this run, is no permit of this run's. The pack is the
# one of the checkout the run is started in; with none that can be read, the cap is 2. SLOT_LIB, this file's folder
# as a full path, is read as the file is sourced: a case's keeper defines these functions again from a copy of them
# (tests/lib.sh run_case), where BASH_SOURCE names no file of the engine's.
SLOT_LIB=.; [[ ${BASH_SOURCE[0]} != */* ]] || SLOT_LIB=${BASH_SOURCE[0]%/*}; [[ $SLOT_LIB == /* ]] || SLOT_LIB=$PWD/$SLOT_LIB
slot_session() {
  local n i
  SLOT_CAP=''; SLOT_CAPN=0; SLOT_CAPFD=''
  [ -n "${CONVEYOR_CARD:-}" ] || return 0
  n=$(bash "$SLOT_LIB/pack.sh" get tunables.sessionTestSlots 2>/dev/null) && [[ $n =~ ^[1-9][0-9]{0,5}$ ]] || n=2
  SLOT_CAP=$SLOT_DIR/session/${CONVEYOR_CARD//[!A-Za-z0-9._-]/_}
  mkdir -p "$SLOT_CAP" || { echo "conveyor: the session's test slot permits folder $SLOT_CAP cannot be made: no test can take a slot" >&2; return 1; }
  for ((i = 1; i <= n; i++)); do
    [ -e "$SLOT_CAP/$i" ] || : >> "$SLOT_CAP/$i" || { echo "conveyor: the session's test slot permit $SLOT_CAP/$i cannot be made: no test can take a slot" >&2; return 1; }
  done
  SLOT_CAPN=$n
}

# Takes a permit of the session's (slot_session) that is free now: SLOT_CAPFD is the descriptor that holds it, which
# the worker inherits with its slot's, so the permit comes back when the slot does. 1 when none is free.
slot_permit() {
  local i
  for ((i = 1; i <= SLOT_CAPN; i++)); do
    { exec {SLOT_CAPFD}>>"$SLOT_CAP/$i"; } 2>/dev/null || continue
    flock -n "$SLOT_CAPFD" && return 0
    exec {SLOT_CAPFD}>&-
  done
  SLOT_CAPFD=''; return 1
}

# The Test step's word for a card that waits for a slot: how many of the pool are held.
slot_waiting() {
  echo "waiting for a test slot ($(slot_used) of $SLOT_N in use)"
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

# True when a process holds an flock on <file>; false for a file that is not there. Its lock is tried on a descriptor
# of this shell, so flock is the only program it starts (`flock -n <file> true` started two).
slot_held() { # <file>
  local fd rc=1
  { exec {fd}<"$1"; } 2>/dev/null || return 1
  flock -n "$fd" 2>/dev/null || rc=0
  exec {fd}<&-; return "$rc"
}

# True when a push waits for a slot (slot_first) and this is not it: the slot just taken is given back, so the push
# takes it ahead of every test worker that waits. A push's claim is a file of $SLOT_DIR/first that its push holds an
# flock on; one no process holds (its push was killed) counts for nothing.
slot_yield() {
  local f
  [ -z "${SLOT_FIRST:-}" ] || return 1
  for f in "$SLOT_DIR"/first/[0-9]*; do slot_held "$f" && return 0; done
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
  for f in "$d"/[0-9]*; do [ "$f" = "$d/$BASHPID" ] || slot_held "$f" || rm -f "$f"; done
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
  for f in "$d"/[0-9]*; do [ "$f" = "$SLOT_ASKF" ] || slot_held "$f" || rm -f "$f"; done
}
slot_unask() { [ -z "${SLOT_ASK:-}" ] || { rm -f "$SLOT_ASKF"; exec {SLOT_ASK}>&-; SLOT_ASK=''; }; }
# How many test runs of the machine ask now (slot_ask); 1 when none does.
slot_asked() {
  local f n=0
  for f in "$SLOT_DIR"/asks/[0-9]*; do slot_held "$f" && n=$((n + 1)); done
  [ "$n" -gt 0 ] && echo "$n"
}

# A runner's slot for its next worker, waited for: the run's home slot when no other worker of the run is on it
# (asked five times a second, so the next worker starts as the one before it ends), else a slot of the pool. A run
# told to keep to one slot (CONVEYOR_TEST_ONESLOT, read by slot_pool: the run of a card's failing cases on main beside
# the controls, verdicts() in lib/mainred.sh) never takes one of the pool: its workers run one at a time on its home
# slot, so a control that passes there passed on the slot of every failing case. A run in a card's session
# (slot_session) holds a permit of the session's for each slot of the pool it takes, and waits for one before it
# takes one; a turn on its home slot, a slot it holds already, needs none (a runner a worker of the session's run
# starts, whose permits that run's workers hold, then runs its workers one at a time on its home slot).
# With SLOT_STOP, the name of a function of the caller's, it asks that function before each try and returns 1, with
# no slot, once it is true: a run that stops at its first failure (fileeach() fast, the engine's runner) sees a failure
# while it waits, though a push takes each slot that comes free (slot_yield).
slot_take() {
  local i=0
  while :; do
    [ -z "${SLOT_STOP:-}" ] || ! "$SLOT_STOP" || return 1
    if [ -n "$SLOT_HOME" ] && { exec {SLOT_FD}>>"$SLOT_DIR/$SLOT_HOME_K$SLOT_TURN.t"; } 2>/dev/null; then
      flock -n "$SLOT_FD" && { SLOT_K=$SLOT_HOME_K; SLOT_ENV=$SLOT_HOME$SLOT_TURN.t; [ -z "${SLOT_CAPFD:-}" ] || { exec {SLOT_CAPFD}>&-; SLOT_CAPFD=''; }; return 0; }
      exec {SLOT_FD}>&-
      [ -z "${SLOT_ONE:-}" ] || { sleep 0.2; continue; }
    fi
    [ -z "${SLOT_CAP:-}" ] || [ -n "${SLOT_CAPFD:-}" ] || slot_permit || { sleep 0.2; continue; }
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
  # A run in a card's session with no slot yet waits for a permit of its session's (slot_session) before it asks for
  # a turn: a ticket left empty while it waits for a permit would make every run that asked after it, the check on
  # main too, wait behind it while turns and slots are free.
  while [ -n "${SLOT_CAP:-}" ] && [ -z "$SLOT_HOME" ] && [ -z "${SLOT_CAPFD:-}" ] && ! slot_permit; do sleep 0.5; done
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
      if ! slot_held "$d/$t"; then rm -f "$d/$t"; continue; fi
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
      elif slot_try || slot_wait 0.5; then
        # A home slot of the pool in a card's session holds a permit (slot_session) as long as the run holds the slot:
        # the turns slot_take gives on it take none. SLOT_CAPFD is emptied, not closed, so slot_take and slot_free,
        # which close SLOT_CAPFD, leave the permit's descriptor open.
        SLOT_HOME=$SLOT_FD SLOT_HOME_K=$SLOT_K SLOT_TURN='' SLOT_CAPFD=''
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
# here, before its work starts. A worker holds its session's permit (slot_permit) but takes none for the runners it
# starts: the slot it holds is theirs (SLOT_CAP emptied).
slot_mine() {
  local c
  export CONVEYOR_TEST_SLOT=$SLOT_ENV; SLOT_CAP=''
  [ -n "$SLOT_CPUS" ] || return 0
  read -ra c <<<"$SLOT_CPUS"
  [ -n "${c[SLOT_K - 1]:-}" ] && taskset -cp "${c[SLOT_K - 1]}" "$BASHPID" >/dev/null 2>&1 \
    || { echo "conveyor: test slot $SLOT_K has no core this worker can be pinned to: the worker does not start" >&2; exit 1; }
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
  closefds "$SLOT_FD" ${SLOT_CAPFD:+"$SLOT_CAPFD"} # the session's permit too (slot_permit)
  read -r g; cat > /dev/null
  # The processes' environments are read into a variable: a search started for the mark would carry it itself.
  while pgrep -g "${g:-none}" >/dev/null 2>&1 || { f=$(ps axeww -o pid= -o command= 2>/dev/null); [[ $f == *" $1"* ]]; }; do sleep 0.5; done
}

# Closes the runner's own descriptor of the slot, once the worker it started holds it too: the slot is then the
# worker's, and comes back when the worker and all it started have ended.
slot_free() { exec {SLOT_FD}>&-; [ -z "${SLOT_CAPFD:-}" ] || { exec {SLOT_CAPFD}>&-; SLOT_CAPFD=''; }; }

# How many slots of the pool are held now.
slot_used() {
  local i n=0
  for ((i = 1; i <= SLOT_N; i++)); do ! slot_held "$SLOT_DIR/$i" || n=$((n + 1)); done
  echo "$n"
}

# The words put before a card session, review or test run ("${KEEP[@]}" <command>) to start it on the cores left for
# card work (slot_keep, taskset -c), so it never runs on a core the host file keeps for the user; none when it keeps
# none. Sets KEEP.
slot_keepwords() {
  local k
  KEEP=()
  # shellcheck disable=SC2034 # KEEP is read in lib/session.sh, lib/review.sh and lib/testrun.sh
  k=$(slot_keep) && KEEP=(taskset -c "$k")
  return 0
}
