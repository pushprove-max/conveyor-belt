#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: card work yields to the user (issue 194; lib/slots.sh steer_words, steer_set, steer_use, steer_watch;
# the host file's steer, steer_on in lib/paths.sh): card sessions at lowered priority, card test runs at idle priority,
# given their normal priority back while they starve, and nothing else lowered; a test run's slice removed after it
# (steer_end, steer_sweep).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The host file's steer as a case's engine reads it: the case's own host file, with <steer> (none: the key left out).
steer_host() { # <true | false | none>
  HOST=$XDG_CONFIG_HOME/conveyor/host.json
  mkdir -p "${HOST%/*}" && if [ "$1" = none ]; then echo '{}'; else echo "{\"steer\": $1}"; fi > "$HOST" || fail "the host file could not be written"
  eval "$(sed -n '/^steer_on() {/p' "$SRC/lib/paths.sh")"
}
# What priority a command started behind STEER gets, and the caller's own: "<nice> <ionice class>" (ionice's word for
# the class: idle, best-effort, none).
prio() { echo "$(ps -o ni= -p "$1" | tr -d ' ') $( { ionice -p "$1" 2>/dev/null || echo none; } | cut -d: -f1)"; } # <pid>

# Bugs it catches: a build or review session started at the user's own priority, and took the machine its user types
# on. A session (the builder, and an OpenCode review, through the words each uses) runs at nice 10 above its caller;
# the caller, the loop or a process the user starts, keeps its own priority. With the host file's steer false, nothing
# is lowered (today's behaviour before the setting).
t_steersession() {
  # shellcheck disable=SC2034 # BUILD_TIMEOUT and REVIEW_TIMEOUT are read by builder() and ocrun()
  local d=$T/$CASE STEER STEER_HOW STEER_SLICE mine want BUILD_TIMEOUT=30 REVIEW_TIMEOUT=30
  mkdir -p "$d/bin" "$d/wt"; steer_host none
  command -v nice >/dev/null && command -v ionice >/dev/null || return 0
  # opencode stands in for every session's program: it writes its own priority beside the worktree.
  printf '%s\n' '#!/usr/bin/env bash' 'echo "$(ps -o ni= -p $$ | tr -d " ")" >> "$PWD.prio"; cat > /dev/null' > "$d/bin/opencode"; chmod +x "$d/bin/opencode"
  eval "$(sed -n '/^builder() {/,/^}/p' "$SRC/lib/session.sh"; sed -n '/^ocrun() {/,/^}/p' "$SRC/lib/review.sh")"
  mine=$(prio $BASHPID); want=$(( ${mine% *} + 10 > 19 ? 19 : ${mine% *} + 10 ))
  steer_words session
  [ "$STEER_HOW" = 'nice 10' ] || fail "a session is not lowered to nice 10: ${STEER[*]}"
  ( PATH=$d/bin:$PATH; builder "$d/wt" prompt opencode:p/m '' '' opencode ) || fail "the builder did not run: $(cat "$d/wt.err" 2>&1)"
  ( PATH=$d/bin:$PATH; ocrun "$d/wt" opencode:p/m high <<<prompt > /dev/null 2>&1 ) || fail "the review did not run"
  [ "$(paste -sd' ' "$d/wt.prio")" = "$want $want" ] || fail "the build and review sessions ran at nice $(paste -sd' ' "$d/wt.prio"), not $want"
  [ "$(prio $BASHPID)" = "$mine" ] || fail "the caller's own priority changed: $(prio $BASHPID), was $mine"
  steer_host false; steer_words session; rm -f "$d/wt.prio"
  [ ${#STEER[@]} = 0 ] && [ -z "$STEER_HOW" ] || fail "with steer off a session is still lowered: ${STEER[*]}"
  ( PATH=$d/bin:$PATH; builder "$d/wt" prompt opencode:p/m '' '' opencode ) || fail "the builder did not run with steer off"
  [ "$(cat "$d/wt.prio")" = "${mine% *}" ] || fail "with steer off the session ran at nice $(cat "$d/wt.prio"), not its caller's ${mine% *}"
}

# Bug it catches: a card's test run started at the user's priority. The loop's run of a card's tests (testonce(), the
# one a mutation check runs too) starts its command lowered: idle disk priority, and nice 19 and SCHED_IDLE where this
# user can undo them. The case runs in its slot's box (or with no user systemd), so the run is lowered process by
# process, not by a slice (t_steerslice).
t_steertestrun() {
  local w=$T/$CASE/wt out STEER STEER_HOW STEER_SLICE
  command -v ionice >/dev/null && ionice -c 3 sh -c 'ionice -c 2 -p $$' >/dev/null 2>&1 || return 0
  setup '[]'; git -C "$R" worktree add -q --detach "$w" && mkdir -p "$w.testlog" || fail "the worktree"
  steer_host none
  # shellcheck disable=SC2034 # LIVE and STUCK are read by watch(), which testonce() runs; names() is not run here
  out=$( ( LIVE=0.2 STUCK=1200; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards SLOT_HOME=$T/$CASE/slot CONVEYOR_TEST_BOX=1; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && reportask "$w" \
    && testonce "$w" 'echo "$(ps -o ni= -p $$ | tr -d " ") $(ionice -p $$ | cut -d: -f1)" > "$PWD.prio"' && steer_words test && echo "$STEER_HOW" ) 2>&1 ) \
    || fail "the run failed: $out $(cat "$w.test" 2>/dev/null)"
  [[ $out == *'ionice idle'* ]] || fail "a test run here is not lowered to ionice's idle class: $out"
  [ "$(cut -d' ' -f2 "$w.prio")" = idle ] || fail "the card's test command ran at disk priority $(cat "$w.prio"), not idle"
  [[ $out != *'nice 19'* ]] || [ "$(cut -d' ' -f1 "$w.prio")" = 19 ] || fail "the card's test command ran at nice $(cat "$w.prio"), not 19"
}

# Bug it catches: a test-speed survey card's build session runs its test files itself, and ran them at a session's
# priority, not a test run's. A whole card proves the card's choice reaches its sessions (card(), session1()): the
# survey card's build runs at idle disk priority, as its test step's run does, and its review at a session's nice 10.
t_steersurvey() {
  local mine b
  command -v ionice >/dev/null && ionice -c 3 sh -c 'ionice -c 2 -p $$' >/dev/null 2>&1 || return 0
  setup "$(issue 7 2026-01-01 bug area:billing P2 | jq -c '[. + {title: "Test-speed survey, first"}]')"
  # The pick takes a survey issue only in the pack's test.surveyHour: this hour, not about to turn.
  wait_until '[ "$(date +%M)" != 59 ]' || fail "the hour did not turn"
  tune --argjson h "$(date +%-H)" '.test.surveyHour = $h'
  echo "$GO" > "$STUB/review.1"; provenbug
  mine=$(ps -o ni= -p $BASHPID | tr -d ' ')
  b=$(cat "$STUB/build")
  printf '%s\n' 'echo "build $(ps -o ni= -p $$ | tr -d " ") $(ionice -p $$ | cut -d: -f1)" >> "$STUB/prio"' "$b" > "$STUB/build"
  echo 'echo "test $(ps -o ni= -p $$ | tr -d " ") $(ionice -p $$ | cut -d: -f1)" >> "$STUB/prio"' >> "$STUB/test-cmd"
  echo 'echo "review $(ps -o ni= -p $$ | tr -d " ")" >> "$STUB/prio"' > "$STUB/review-cmd"
  loop run >/dev/null || fail "run exited non-zero"
  grep -Eqx "build ($mine|19) idle" "$STUB/prio" && grep -Eqx "test ($mine|19) idle" "$STUB/prio" \
    && grep -qx "review $(( mine + 10 > 19 ? 19 : mine + 10 ))" "$STUB/prio" \
    || fail "the survey card's build and test run are not at idle priority, or its review not at nice 10: $(cat "$STUB/prio" 2>&1)"
}

# Bug it catches: on a Linux with the user's systemd, a test run lowered process by process lost it in every box its
# runner made (a box is a scope of its own, beside the run). The run goes in a slice of its own, CPUWeight and IOWeight
# 1, and a box made inside it goes in the same slice; up gives it 100 back, down 1 again, and its end leaves no setting
# behind. The caller stays where it was.
t_steerslice() {
  local d=$T/$CASE STEER STEER_HOW STEER_SLICE s mine
  mkdir -p "$d"; steer_host none
  command -v systemctl >/dev/null && timeout 10 systemd-run --user --scope --quiet true >/dev/null 2>&1 </dev/null || return 0
  mine=$(cat /proc/self/cgroup)
  ( unset CONVEYOR_TEST_BOX; steer_words test; s=$STEER_SLICE; [ -n "$s" ] || exit 3
    "${STEER[@]}" bash -c 'cat /proc/self/cgroup > "$1/cg"; . "$2/lib/slots.sh"; SLOT_N=1; slot_box; echo "${SLOT_BOX[*]}" > "$1/box"' _ "$d" "$SRC"
    w() { systemctl --user show -p CPUWeight -p IOWeight "$s" | paste -sd' '; }
    { w; steer_set up 0; w; steer_set down 0; w; steer_end; w; } > "$d/w"; echo "$s" > "$d/s" ) || fail "no slice was made where a user systemd scope can be"
  s=$(cat "$d/s")
  # Issue 331: the slice stayed active after the run ended, one per card process that ever ran.
  ! systemctl --user is-active --quiet "$s" || fail "the run's slice $s is still active after its end"
  grep -q "/$s/" "$d/cg" || fail "the run is not in its slice $s: $(cat "$d/cg")"
  grep -q -- "--slice=$s " "$d/box" || fail "a box made inside the run is not in the run's slice: $(cat "$d/box")"
  [ "$(cat "$d/w")" = "CPUWeight=1 IOWeight=1
CPUWeight=100 IOWeight=100
CPUWeight=1 IOWeight=1
CPUWeight=[not set] IOWeight=[not set]" ] || fail "the slice's weights were not 1, 100 when raised, 1 again, then gone: $(cat "$d/w")"
  [ "$(cat /proc/self/cgroup)" = "$mine" ] || fail "the caller moved: $(cat /proc/self/cgroup)"
}

# Bug it catches (issue 331): a run killed before its end (steer_end never ran) left its slice active for good. At the
# loop's start the slice of a process that is gone is removed; that of a live process, whose run may not have started
# yet, is kept.
t_steersweep() {
  local d=$T/$CASE live dead s
  mkdir -p "$d"
  command -v systemctl >/dev/null && timeout 10 systemd-run --user --scope --quiet true >/dev/null 2>&1 </dev/null || return 0
  sleep 60 & live=$! # sleep: a live process whose slice stays
  bash -c 'echo $$' > "$d/dead"; dead=$(cat "$d/dead") # a process that has ended
  for s in "$live" "$dead"; do
    systemctl --user set-property --runtime "conveyor_steer_$s.slice" CPUWeight=1 >/dev/null 2>&1 </dev/null
    systemd-run --user --scope --quiet --collect --slice="conveyor_steer_$s.slice" true >/dev/null 2>&1 </dev/null
  done
  systemctl --user is-active --quiet "conveyor_steer_$dead.slice" || fail "the stand-in slice of the ended process was not made"
  steer_sweep
  systemctl --user is-active --quiet "conveyor_steer_$live.slice" || fail "the slice of a live process was removed"
  ! systemctl --user is-active --quiet "conveyor_steer_$dead.slice" || fail "the slice of a process that is gone is still active"
  kill "$live" 2>/dev/null; steer_drop "conveyor_steer_$live.slice"
}

# Bug it catches: on macOS (taskpolicy) nothing was lowered. A session starts at the utility clamp, a test run in the
# background, and a run raised is taken out of the background and put back, process by process. taskpolicy is stubbed:
# Linux has none.
t_steermac() {
  local d=$T/$CASE STEER STEER_HOW STEER_SLICE g
  mkdir -p "$d/bin"; steer_host none
  printf '%s\n' '#!/usr/bin/env bash' 'echo "$*" >> "$TP_LOG"' 'while [[ ${1:-} == -* ]]; do case $1 in -c|-p) shift 2 ;; *) shift ;; esac; done' '[ $# = 0 ] || exec "$@"' > "$d/bin/taskpolicy"
  chmod +x "$d/bin/taskpolicy"
  export TP_LOG=$d/log; PATH=$d/bin:$PATH
  steer_words session; "${STEER[@]}" true
  steer_words test; "${STEER[@]}" true
  set -m; sleep 60 & g=$!; set +m # sleep: a stand-in run the case lowers and raises, then kills
  steer_set up "$g"; steer_set down "$g"; kill -- -"$g"
  [ "$(cat "$d/log")" = "-c utility true
-b true
-B -p $g
-b -p $g" ] || fail "taskpolicy was not asked for the utility clamp, the background, then out of it and back: $(cat "$d/log")"
}

# Bug it catches (Keel's rule): a test run lowered while the machine is busy could get no CPU, and time out only
# because it was lowered. A run whose CPU time does not grow while a process of it waits to run is raised after 3
# looks, lowered again 2 looks later, and raised again while it still starves. A run whose CPU time grows, or with
# nothing waiting to run, is never raised. steer_use and steer_set are stubbed: the case is about when, not how.
# The run is a plain child, in no group of its own, as testonce's is when the watch starts (timeout makes the group
# later) and a survey session's always is: a watcher that looked for the group ended at once, and raised nothing.
t_steerstarve() {
  local d=$T/$CASE g w
  mkdir -p "$d"
  set +m; sleep 60 & g=$! # sleep: a stand-in run the watcher looks at, then killed
  [ "$(ps -o pgid= -p "$g" | tr -d ' ')" != "$g" ] || { kill "$g"; fail "the run is a group of its own"; }
  watcher() { # <cpu step> <runnable>
    # shellcheck disable=SC2034 # STEER_TICK is read by steer_watch()
    ( STEER_HOW=stub STEER_SLICE='' STEER_TICK=0.02 step=$1 run=$2
      steer_use() { local c; c=$(( $(cat "$d/n" 2>/dev/null || echo 0) + 1 )); echo "$c" > "$d/n"; echo "$((c * step)) $run"; }
      steer_set() { echo "$1" >> "$d/set"; }
      steer_watch "$g" ) & w=$!
  }
  watcher 0 1
  wait_until '[ "$(head -n 3 "$d/set" 2>/dev/null | paste -sd, -)" = up,down,up ]' "cat '$d/set'" || fail "a starving run was not raised, lowered and raised again"
  kill "$w"; wait "$w" 2>/dev/null; rm -f "$d/set" "$d/n"
  watcher 50 1
  wait_until '[ "$(cat "$d/n" 2>/dev/null || echo 0)" -ge 12 ]' || fail "the watcher stopped looking"
  [ ! -e "$d/set" ] || fail "a run whose CPU time grows was raised: $(cat "$d/set")"
  kill "$w"; wait "$w" 2>/dev/null; rm -f "$d/n"
  watcher 0 0
  wait_until '[ "$(cat "$d/n" 2>/dev/null || echo 0)" -ge 12 ]' || fail "the watcher stopped looking"
  [ ! -e "$d/set" ] || fail "a run with nothing waiting to run was raised: $(cat "$d/set")"
  kill "$w" 2>/dev/null; kill "$g"
}

# Bug it catches: the watcher, started in the background, kept the lock its caller held (the whole test's on main), so
# the next whole test found it taken and never ran (maintest's cases). The lock is free once the caller lets it go.
t_steerwatchfd() {
  local d=$T/$CASE g w l
  mkdir -p "$d"
  set +m; sleep 60 & g=$! # sleep: a stand-in run the watcher looks at, then killed
  exec {l}>>"$d/lock"; flock "$l" || fail "the lock could not be taken"
  # shellcheck disable=SC2034 # STEER_TICK is read by steer_watch()
  ( STEER_HOW=stub STEER_SLICE='' STEER_TICK=0.02; steer_watch "$g" ) & w=$!
  exec {l}>&-
  WAIT_CEILING=10 wait_until 'flock -n "$d/lock" true' || fail "the watcher holds its caller's lock"
  kill "$w" "$g" 2>/dev/null
}

# Bugs it catches: the setting could be changed only by editing the host file; a value the Board sent that is neither
# on nor off was written; setting it lost the host file's other settings; health (the Board's Rules tab) and doctor
# did not say whether card work yields to the user, nor how.
t_machinesteer() {
  setup '[]'
  local H=$XDG_CONFIG_HOME/conveyor/host.json out
  mkdir -p "${H%/*}"
  jq -n --arg r "$R" '{records: [{repo: "solo", main: $r}], cap: 4}' > "$H"
  [ "$(loop health | jq -c .steer)" = true ] || fail "with no steer in the host file, health does not say card work yields: $(loop health | jq -c .steer)"
  out=$(loop doctor 2>&1); grep -q '^ok: card work yields to you (the host file.s steer is on): card sessions run at nice 10, card test runs at ' <<<"$out" \
    || fail "doctor does not say card work yields, and how: $(grep -i 'card work' <<<"$out")"
  out=$(loop machine steer off) && grep -q "no longer yields" <<<"$out" || fail "machine steer off was refused: $out"
  [ "$(jq -c '[.steer, .cap, (.records | length)]' "$H")" = '[false,4,1]' ] || fail "steer is not false, or a setting was lost: $(cat "$H")"
  [ "$(loop health | jq -c .steer)" = false ] || fail "health does not say steer is off"
  out=$(loop doctor 2>&1); grep -q "^ok: card work runs at normal priority: the host file's steer is off" <<<"$out" \
    || fail "doctor does not say steer is off: $(grep -i 'card work' <<<"$out")"
  for bad in yes 1 '' 'off;x'; do
    out=$(loop machine steer "$bad" 2>&1); [ $? = 2 ] && [ "$(jq .steer "$H")" = false ] || fail "steer \"$bad\" was not refused, or it changed the host file: $out; $(cat "$H")"
  done
  loop machine steer on > /dev/null && [ "$(jq -c '[has("steer"), .cap]' "$H")" = '[false,4]' ] || fail "on did not remove steer, or a setting was lost: $(cat "$H")"
}

# Bugs it catches: the starvation watch read nothing of a real run; and it read only the run's own process group, so a
# test runner's worker in a process group of its own (as the engine's cases are: tests/lib.sh run_case) was never seen
# starving, nor raised or lowered. A run whose idle leader starts a busy worker in a group of its own: the worker's CPU
# time grows, it counts as waiting to run or running (R), and steer_set lowers it.
t_steeruse() {
  local g w STEER_SLICE='' STEER_HOW='nice 19'
  set -m; bash -c 'set -m; bash -c "while :; do :; done" & wait' & g=$!; set +m
  wait_until "pgrep -P $g" || { kill -- -"$g"; fail "the worker did not start"; }
  w=$(pgrep -P "$g")
  [ "$(ps -o pgid= -p "$w" | tr -d ' ')" != "$g" ] || { kill -- -"$g" "$w"; fail "the worker is not in a group of its own"; }
  wait_until "read -r c n < <(steer_use $g); [ \"\$c\" -ge 20 ] && [ \"\$n\" -ge 1 ]" "steer_use $g" || { kill -- -"$g" "$w"; fail "a busy worker's CPU time and state are not read"; }
  steer_set down "$g"
  [ "$(ps -o ni= -p "$w" | tr -d ' ')" = 19 ] || { kill -- -"$g" "$w"; fail "the worker was not lowered: nice $(ps -o ni= -p "$w")"; }
  kill -- "$w"; kill -- -"$g"
}
