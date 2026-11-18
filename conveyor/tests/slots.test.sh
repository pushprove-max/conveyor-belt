#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the machine's test slots (lib/slots.sh), one pool that every test run on the machine takes its workers' slots from.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A pool of the case's own, of <n> slots: the host file's testSlots, in a folder no other case shares (testSlotsDir).
slotpool() { # <n>
  export XDG_CONFIG_HOME=$T/$CASE/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": $1, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
}

# A card's test step in its worktree <w>, run by the engine's own tests() (lib/testrun.sh) with the engine's libraries
# sourced as conveyor.sh and its run command (commands/run.sh) source them, the loop's settings those of the case's main: what `loop run` runs at a card's
# test step, without the card's build, review and landing, and its tests run again on a main that moved under it. The
# fields its test line takes of the run (testrec(), with its exit and seconds, as card.sh gives them) are left in
# <w>.rec. Whole cards' runs cost t_slots 12 to 18 s and t_slotclock 6 to 15 s. A card's test line is testrec()'s
# fields with its own (card.sh): batch.test.sh t_batchmask reads a card's .ended, and rerun.test.sh its .selected.
teststep() { # <w>: exits as tests() returns
  ( HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh"; grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    names || exit 1
    s=$SECONDS; tests "$1"; rc=$?; testrec "$1" "$rc" $((SECONDS - s)) > "$1.rec"; exit $rc )
}

# The owner (2026-11-12): ten cards each ran cores/2 cases at once, the load reached 87, and cases' timing waits and the
# suite timeout failed on cards whose change was sound. With a pool of 2, three cards' test runs of 2 workers each
# (a runner's: a slot for each worker, the run's home slot among them) never have more than 2 workers going, the
# third card waits with its live record saying so, and all three pass (the Board's card saying it waits:
# t_slotclock). A run's command is held to its slot's core (where the system can pin: taskset), so one that starts
# workers without a slot each gets no core beyond its own, with a core kept for the user too (reserveCores; issue
# 239: the run was started on all the cores left, taskset -c, after it was pinned, and saw them all).
t_slots() {
  local w i p=() h
  slotpool 2; setup "[]"
  h=$XDG_CONFIG_HOME/conveyor/host.json
  ! command -v taskset >/dev/null || [ "$(nproc --all)" -lt 3 ] || { jq '.reserveCores = 1' "$h" > "$h.new" && mv -f "$h.new" "$h"; } \
    || fail "the host file could not keep a core"
  for i in 7 8 9; do git -C "$R" worktree add -q --detach "$T/$CASE/cards/c$i" || fail "the worktree of c$i could not be made"; done
  # A worker counts the workers going as it starts. The first two runs' workers stay until a card is seen waiting
  # for a slot, so two runs are going at once whatever the machine's load.
  mkdir "$STUB/going"
  cat > "$STUB/test-cmd" <<EOF
echo x >> "\$STUB/tests"; nproc >> "\$STUB/cores"
. "\$CONVEYOR_TEST_SLOTS"; slot_pool || exit 1
for w in 1 2; do
  slot_take
  ( slot_mine; mkdir "\$STUB/going/\$BASHPID"; ls "\$STUB/going" | wc -l >> "\$STUB/peak"
    i=0; until [ -e "\$STUB/seen" ] || [ \$i -ge 300 ]; do i=\$((i + 1)); sleep 0.1; done
    sleep 0.3; rmdir "\$STUB/going/\$BASHPID" ) & # sleep: the slot is held a moment past the wait being seen
  slot_free
done
wait
EOF
  ( while [ -d "$STUB" ] && [ ! -e "$STUB/seen" ]; do
      for i in "$T/$CASE/cards"/*.live; do
        grep -qsF 'waiting for a test slot (2 of 2 in use)' "$i" || continue
        jq -e '.step == "test" and .action == "waiting for a test slot (2 of 2 in use)"' "$i" >/dev/null 2>&1 || continue
        cp "$i" "$STUB/waitlive"; : > "$STUB/seen"; break
      done
      sleep 0.05
    done ) & w=$!
  for i in 7 8 9; do teststep "$T/$CASE/cards/c$i" > "$T/$CASE/c$i.out" 2>&1 & p+=($!); done
  for i in 0 1 2; do wait "${p[$i]}" || : > "$STUB/failed.$((i + 7))"; done
  kill $w 2>/dev/null
  [ -e "$STUB/seen" ] || fail "with both slots held, no card's live record said it waits for a test slot: $(cat "$T/$CASE"/c*.out)"
  [ "$(sort -n "$STUB/peak" | tail -n 1)" = 2 ] || fail "the most workers at once was not 2, the pool: $(sort -n "$STUB/peak" | tail -n 1)"
  [ -z "$(ls "$STUB"/failed.* 2>/dev/null)" ] && [ "$(wc -l < "$STUB/tests")" = 3 ] \
    || fail "a test run did not pass, or not all three ran: $(ls "$STUB"/failed.* 2>/dev/null) $(cat "$T/$CASE"/c*.out "$T/$CASE"/cards/c*.test)"
  jq -e '.last != null and .files == {run: 0, of: null}' "$STUB/waitlive" >/dev/null || fail "the waiting card's live record: $(cat "$STUB/waitlive")"
  ! command -v taskset >/dev/null || [ "$(sort -u "$STUB/cores")" = 1 ] || fail "a run's command was not held to its slot's core: it saw $(sort -u "$STUB/cores" | tr '\n' ' ')cores"
  slot_pool && [ "$(slot_used)" = 0 ] || fail "a slot is still taken once the three runs ended: $(slot_used)"
}

# A slot must come back however its worker ends: one that kept a killed worker's slot would shrink the machine's pool
# for good, until no test on it could start. And it must not come back sooner: a slot given to the next worker while
# the killed one's case still ran put two on one core. An engine case's worker (run_case) is killed mid-case with a
# pool of 1: the slot stays taken while the case it started lives, and is free once that has ended, which it does
# with no word from the test: the case's keeper sees its worker gone and ends it (run_case).
# Holding a slot is shown, never said: a variable naming a file that is no slot of the pool, or a slot another holds,
# gives no home slot (a loop that believed it ran its tests with the pool full). The pool's size is the host file's
# testSlots, and the machine's cores when it names none; its folder is one, whatever the environment.
t_slotkill() {
  local pid f i
  slotpool 1; slot_pool || fail "the pool could not be made"
  [ "$SLOT_N" = 1 ] || fail "the pool is not the host file's testSlots: $SLOT_N"
  [ -z "$SLOT_HOME" ] || fail "the slot this case holds, of the machine's pool, was taken for a home slot of this pool"
  exec {f}>>"$T/$CASE/unheld"; CONVEYOR_TEST_SLOT=$f slot_pool; [ -z "$SLOT_HOME" ] || fail "a file that is no slot of the pool was taken for a home slot"
  # A numbered file of the folder beyond the pool's size (left by a larger pool) is no slot: a run that held it and
  # was believed would run its tests beside the pool's one worker, on no slot and pinned to no core.
  exec {f}>>"$SLOT_DIR/2"; flock -n "$f"; CONVEYOR_TEST_SLOT=$f slot_pool; [ -z "$SLOT_HOME" ] || fail "a numbered file beyond the pool's slots was taken for a home slot"
  exec {f}>&-; rm "$SLOT_DIR/2"
  t_slotnap() { echo "$BASHPID" > "$T/slotkill/nap"; exec sleep 30; } # sleep: a stand-in for a case still running
  slot_take; [ "$SLOT_K" = 1 ] || fail "a new pool has no free slot"
  CONVEYOR_TEST_SLOT=$SLOT_FD slot_pool; [ "$SLOT_HOME" = "$SLOT_FD" ] && [ "$SLOT_HOME_K" = 1 ] || fail "the descriptor that holds slot 1 was not taken for the home slot"
  slot_pool
  ( CASE=slotnap; run_case ) & pid=$!
  slot_free
  until [ -s "$T/$CASE/nap" ]; do sleep 0.05; done
  ! slot_try || fail "a slot was taken while the pool's one worker ran"
  ! slot_wait 0.2 || fail "a slot was waited for and got while the pool's one worker ran"
  [ "$(slot_used)" = 1 ] || fail "slots in use while the worker ran: $(slot_used)"
  exec {f}>>"$SLOT_DIR/1"; CONVEYOR_TEST_SLOT=$f slot_pool; [ -z "$SLOT_HOME" ] || fail "a slot another worker holds was taken for a home slot"
  kill -9 $pid; wait $pid 2>/dev/null
  i=0; until slot_try || [ $i -ge 100 ]; do i=$((i + 1)); sleep 0.1; done
  [ $i -lt 100 ] || fail "a worker killed mid-case, and its case, did not give the slot back"
  # The slot is given out here: the case is over (one that has ended and is not waited for yet is).
  [ -z "$(ps -o stat= -p "$(cat "$T/$CASE/nap")" | grep -v Z)" ] || fail "a killed worker's slot was given out while the case it started still ran"
  slot_free
  [ "$(slot_used)" = 0 ] || fail "slots in use with no worker: $(slot_used)"
  i=$(nproc --all); ! command -v taskset >/dev/null || i=$(taskset -c "0-$((i - 1))" nproc)
  # With no host file, inside an engine test run the pool is the runner's (CONVEYOR_TEST_POOL, t_slotcaseloop); outside
  # one, the machine's.
  rm "$XDG_CONFIG_HOME/conveyor/host.json"; CONVEYOR_TEST_POOL="1:$T/$CASE/run" slot_pool
  [ "$SLOT_DIR $SLOT_N" = "$T/$CASE/run 1" ] || fail "with no pool in the host file, the engine test run's pool was not taken: $SLOT_DIR $SLOT_N"
  unset CONVEYOR_TEST_POOL
  slot_pool; [ "$SLOT_N" = "$i" ] || fail "with no testSlots the pool is not the machine's cores: $SLOT_N"
  XDG_STATE_HOME=$T/$CASE/other slot_pool; [ "$SLOT_DIR" = /tmp/conveyor-test-slots ] || fail "the machine's pool is not one folder whatever the environment: $SLOT_DIR"
}

# A run that holds the pool's last slot must still run its workers, one after another, on that slot: a runner that
# waited on the pool for its second worker waited on the slot its own run held, until the suite's timeout. With a
# pool of 1 held as the run's home slot, three workers each run, never two at once, and a runner one of them starts
# gets the slot too (the worker's turn on it), not a wait.
t_slothome() {
  local d=$T/$CASE w i r
  slotpool 1; slot_pool && slot_try || fail "the pool's slot could not be taken"
  export CONVEYOR_TEST_SLOT=$SLOT_FD; slot_pool; [ "$SLOT_HOME_K" = 1 ] || fail "the run's slot is not its home slot"
  ( for w in 1 2 3; do
      slot_take
      ( slot_mine; mkdir "$d/on" || : > "$d/two"; [ "$CONVEYOR_TEST_SLOT" = "$SLOT_HOME.t" ] || : > "$d/pool"
        slot_pool; slot_take; [ "$SLOT_ENV" = "$SLOT_HOME.t.t" ] || : > "$d/pool"
        sleep 0.1; rmdir "$d/on"; echo x >> "$d/ran" ) & # sleep: the worker stays on the slot, so a second one at once would be seen
      slot_free
    done; wait; : > "$d/done" ) & r=$!
  wait_until "[ -e '$d/done' ]" > /dev/null 2>&1
  [ -e "$d/done" ] || { kill $r 2>/dev/null; fail "a run that holds the pool's one slot did not run its workers on it: $(wc -l < "$d/ran" 2>/dev/null) of 3 ran"; }
  [ "$(wc -l < "$d/ran")" = 3 ] || fail "not every worker ran: $(cat "$d/ran")"
  [ ! -e "$d/two" ] || fail "two workers were on the home slot at once"
  [ ! -e "$d/pool" ] || fail "a worker of the run was not given the home slot"
}

# A card that waited for a slot behind other cards' suites must not pay for their time: the wait once counted against
# its test timeout, and cards blocked on a timeout that was not theirs. The pool's one slot is held until the card has
# waited for it longer than its test timeout (3 s); the clock of its run must then start with the slot, and be the
# whole timeout. The clock is not run here but read: a `timeout` in the loop's PATH writes down the limit it was given
# (none: the run's clock is the loop's own, testclock, started beside it, so a wait for a whole-suite turn inside the
# run can be left out of it, t_slotwholeclock) and whether the slot had been let go by then, and runs the command with
# no limit, so however long a busy machine keeps the command from running, the case never times it out itself. On macOS p_tools puts Homebrew's
# GNU tools ahead of any stub on PATH, and the engine execs timeout, which no exported function is seen by: so the
# card's test step (teststep) is also given a Homebrew of the case's own ($STUB/brew, found by its gtimeout), whose
# timeout is the stub. It waits though the case's own slot is named to it (CONVEYOR_TEST_SLOT): that one is no slot of
# this pool. While it waits, the snapshot the Board draws says so, taken while the slot is held: the card c7 is at its
# test step by its records, as testcount.test.sh's countrun writes them.
# The owner's audit of 186 test runs (2026-11-13): a test record held one number for the slot wait and the run
# together, so nobody could say how long a run waited for a slot or what it ran. The card's test line holds its wait
# (the 4 s the slot was held at least: it counts whole seconds, so a wait it left out reads 0) and its run apart, the
# two within the step's seconds; what its runner's log says it selected and out of how many; how it ended; and the
# slots free beside its own as it started (none: the pool is its one slot), and the record check takes it. That was
# testrec.test.sh's t_testrecwait, a card of its own that waited 1 s.
t_slotclock() {
  local h k b real w=$T/$CASE/cards/c7 now rc l; real=$(command -v timeout)
  slotpool 1; setup "[$(issue 7 2026-01-01)]"; tune '.tunables.testTimeout = 3'
  git -C "$R" worktree add -q --detach "$w" || fail "the worktree could not be made"
  mkdir -p "$ST"; now=$(date -u +%FT%TZ)
  printf '%s\n' picked worktree deps brief start:build build start:review review:GO start:test | jq -cR --arg t "$now" 'split(":") as [$s, $x]
    | {card:"c7",issue:7,step:$s,time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
      + if $s == "start" then {of: $x} elif $x then {result: $x} else {} end' > "$ST/cards.jsonl"
  echo 'echo x >> "$STUB/tests"; printf "TESTRUN files=2 of=5\nTESTRUN cases=3 of=9\n" > "$CONVEYOR_TEST_LOG/r.log"' > "$STUB/test-cmd"
  printf '%s\n' '#!/usr/bin/env bash' "[ \"\$1 \$3\" = '--kill-after=30 bash' ] || exec '$real' \"\$@\"" \
    'if [ -e "$STUB/freed" ]; then echo "$2"; else echo "started before the slot was let go"; fi >> "$STUB/clock"; shift 2; exec "$@"' > "$STUB/timeout"
  chmod +x "$STUB/timeout"; b=$STUB/brew; mkdir -p "$b/bin"; ln -s "$STUB/timeout" "$b/bin/gtimeout"
  for k in coreutils:timeout coreutils:date coreutils:stat findutils:find gnu-sed:sed grep:grep; do
    mkdir -p "$b/opt/${k%%:*}/libexec/gnubin"; ln -s "$(command -v "${k#*:}")" "$b/opt/${k%%:*}/libexec/gnubin/${k#*:}"
  done
  ln -sf "$STUB/timeout" "$b/opt/coreutils/libexec/gnubin/timeout"
  slot_pool && slot_try || fail "the pool's slot could not be taken"
  # The slot is held until 5 s after the card began to wait (its live record's at, whole seconds: 4 s at least), past
  # its test timeout (3 s), the time the case is about; the card says it waits only after its first look for a slot.
  ( i=0; until a=$(jq -r 'select(.action == "waiting for a test slot (1 of 1 in use)") | .at | fromdate' "$T/$CASE/cards"/*.live 2>/dev/null) && [ -n "$a" ] || [ $i -ge 600 ]; do i=$((i + 1)); sleep 0.1; done
    [ $i -lt 600 ] && { : > "$STUB/waited"; loop snapshot > "$STUB/snap" 2>/dev/null & }
    until [ "$(date +%s)" -ge $((${a:-0} + 5)) ]; do sleep 0.1; done; wait; : > "$STUB/freed" ) & h=$!
  slot_free
  PATH=$b/bin:$PATH teststep "$w" > "$T/$CASE/step.out" 2>&1; rc=$?
  wait $h; out=$(cat "$T/$CASE/step.out" "$w.test" 2>&1)
  [ -e "$STUB/waited" ] || fail "the card did not wait for the held slot: $out"
  jq -e '[.. | objects | .live? | objects | .action] | index("waiting for a test slot (1 of 1 in use)") != null' "$STUB/snap" >/dev/null \
    || fail "the snapshot the Board draws does not say the card waits for a test slot: $(jq -c '[.. | objects | .live? | objects]' "$STUB/snap")"
  [ "$(cat "$STUB/clock" 2>/dev/null)" = 0 ] || fail "a run that waited longer than its timeout was not started with its clock after it got the slot: $(cat "$STUB/clock" 2>&1) $out"
  [ $rc = 0 ] && [ -s "$STUB/tests" ] || fail "a run that waited longer than its timeout did not pass: exit $rc: $out"
  l=$(jq -c '{card: "c7", issue: 7, step: "test", result: "pass", reason: "", sha: "", time: "2026-01-01T00:00:00Z", tokens: {claude: 0, codex: 0}} + .' "$w.rec") \
    || fail "the run left no test line's fields: $out"
  jq -e '(.wait | type) == "number" and .wait >= 4 and (.run | type) == "number"
      and .wait + .run <= .sec + 1 and .selected == {files: 2, filesOf: 5, cases: 3, casesOf: 9, kept: null} and .ended == "passed" and .slotsFree == 0' <<<"$l" >/dev/null \
    || fail "the test line does not hold the wait and the run apart, what was selected, how it ended and the slots free: $l"
  [ -z "$(jq -Rn -f "$SRC/jq/check.jq" <<<"$l")" ] || fail "the record check refuses the test line: $l"
}

# No time limit changes with the turns (the owner, 2026-11-13): a card's test step whose runner waits for a whole-suite
# turn waits outside its test timeout, as it does for its slot. Two runs hold the turns past the card's timeout (3 s);
# the card's whole-suite run (its test step, teststep) waits, then gets its turn, and passes the first time. A clock
# that ran through the wait timed the run out (124) before it started a case; the step's run again of what had not
# passed (tests()) then passed with the turns free, so a pass alone did not show it. The turns are the whole-suite
# runs' (slot_whole; wholerun, t_slotwhole below). This case and t_slotclock, each mostly a hold past a timeout, are
# near the file's top so the runner starts them among its first: this one was its last, and the file's time was its.
t_slotwholeclock() {
  local d=$T/$CASE h rc
  slotpool 3; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  setup "[]"; mkdir -p "$d"; tune '.tunables.testTimeout = 3'
  git -C "$R" worktree add -q --detach "$d/cards/c7" || fail "the worktree could not be made"
  echo '. "$CONVEYOR_TEST_SLOTS"; slot_pool && slot_whole && echo x >> "$STUB/tests"' > "$STUB/test-cmd"
  wholerun A; wholerun B
  wait_until "[ -e '$d/A.on' ] && [ -e '$d/B.on' ]" || fail "two whole-suite runs did not both get a turn"
  ( i=0; until grep -qs 'this one waits for its turn' "$d/cards"/*.test || [ $i -ge 600 ]; do i=$((i + 1)); sleep 0.1; done
    [ $i -lt 600 ] && : > "$STUB/waited"; sleep 5; : > "$d/A.go" ) & h=$! # sleep: the turns are held past the card's test timeout (3 s), the time the case is about
  teststep "$d/cards/c7" > "$d/step.out" 2>&1; rc=$?
  : > "$d/A.go"; : > "$d/B.go"; wait
  [ -e "$STUB/waited" ] || fail "the card's whole-suite run did not wait for a turn: $(cat "$d/step.out" "$d/cards/c7.test")"
  [ $rc = 0 ] && [ -s "$STUB/tests" ] \
    || fail "a run that waited for a turn longer than its timeout did not pass: exit $rc: $(cat "$d/step.out" "$d/cards/c7.test")"
  [ ! -e "$d/cards/c7.first" ] || fail "a run that waited for a turn longer than its timeout passed only when run again: its first run $(cat "$d/cards/c7.first")"
}

# The owner (2026-11-14): the engine suite hung whenever the belts held every one of the machine's slots. A case's
# loop read the machine's pool (its host file is the case's and names none), took the case's slot, of the runner's
# pool, for no slot of it, and waited in its card's test step for one of the machine's. A runner on a pool of its own
# (one slot) runs a case (the probe below) whose loop takes a card through its test step: the card's tests run on the
# case's slot, of the runner's pool, never on one of the machine's, and the card lands. A case that ran before it
# (slotcasehost) wrote a host file naming a pool of one slot of its own, as t_codexbuild does: the probe's loop does
# not read it (a bug: the cases shared one host file folder, so every loop after it waited for that pool's slot).
t_slotcaseloop() {
  local d=$T/$CASE
  slotpool 1
  CONVEYOR_SLOTCASE_PROBE=1 CONVEYOR_SHELL_TEST_CASE='slotcasehost slotcaseprobe' timeout 120 bash "$SRC/conveyor.test.sh" > "$d/run.out" 2>&1 \
    || fail "a case's loop did not run its card's tests on the case's slot: $(cat "$d/run.out")"
}
# The probes the case above runs: each passes in any other run.
t_slotcasehost() {
  [ -n "${CONVEYOR_SLOTCASE_PROBE:-}" ] || return 0
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/$CASE" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the host file was not written"
}
t_slotcaseprobe() {
  [ -n "${CONVEYOR_SLOTCASE_PROBE:-}" ] || return 0
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"
  printf '%s\n' "if [ \"/dev/fd/\${CONVEYOR_TEST_SLOT%%.*}\" -ef '$SLOT_DIR/1' ]; then echo case; else echo \"\$CONVEYOR_TEST_SLOT\"; fi >> \"\$STUB/slot\"" > "$STUB/test-cmd"
  loop run >/dev/null 2>&1 || fail "run exited non-zero"
  [ "$(cat "$STUB/slot" 2>/dev/null)" = case ] || fail "the card's tests did not run on the case's slot ($SLOT_DIR/1), but on: $(cat "$STUB/slot" 2>&1)"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
}

# Two slots on one core are two test runs on one core, the load this pool exists to end. On a machine that lets its
# tests use cores 2 and 3 alone (taskset, stood in for here), slot k was core k-1: both pins failed unsaid and the
# workers ran unpinned, on each other's cores; and a testSlots above the cores wrapped a slot round onto slot 1's
# core. The slots are the usable cores in order, a pool is never larger than them, and a worker whose pin is refused
# does not start.
t_slotcores() {
  local d=$T/$CASE
  slotpool 3
  taskset() { # -cp <pid>: the cores; -cp <cores> <pid>: a pin, written down unless it asks for every core
    [ $# != 2 ] || { echo "pid $2's current affinity list: 2-3"; return 0; }
    case $2 in 0-*) return 0 ;; esac
    echo "$2" >> "$d/pins"; [ ! -e "$d/refuse" ]
  }
  slot_pool || fail "the pool could not be made"
  [ "$SLOT_N" = 2 ] || fail "a pool of 3 slots on 2 usable cores is not cut to the cores: $SLOT_N"
  slot_take; ( slot_mine ) || fail "the worker of slot $SLOT_K did not start"
  slot_take; ( slot_mine ) || fail "the worker of slot $SLOT_K did not start"
  [ "$(tr '\n' ' ' < "$d/pins")" = "2 3 " ] || fail "the two slots are not the two usable cores: $(tr '\n' ' ' < "$d/pins")"
  : > "$d/refuse"
  ( slot_mine; : > "$d/started" ) 2>/dev/null
  [ ! -e "$d/started" ] || fail "a worker that could not be pinned to its slot's core started all the same"
}

# A test command may leave a process running that closed every descriptor it inherited (a program that starts another
# so: Python's subprocess), the slot's among them: the slot then came back when the command ended, and the next card's
# tests ran beside that process, on its core. With a pool of 1, a card's test command leaves such a process: the card
# lands without waiting for it, the slot stays taken while it lives, and is free once it has ended. That process
# lives until the case kills it, and push is off: a push takes a slot (push.sh), so the loop's push waited for the
# process, and the case found it ended (one of 60 s) or never ended (one that lives on).
t_slotleft() {
  local i
  slotpool 1; setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"; loop control rules push=off > /dev/null
  cat > "$STUB/test-cmd" <<'EOF2'
echo x >> "$STUB/tests"
( for ((f = 3; f < 256; f++)); do eval "exec $f>&-"; done; echo "$BASHPID" > "$STUB/left"; exec sleep 3600 ) > /dev/null 2>&1 & # sleep: a stand-in for a process the test command leaves, alive until the case kills it
until [ -s "$STUB/left" ]; do sleep 0.05; done
EOF2
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $out"
  kill -0 "$(cat "$STUB/left")" 2>/dev/null || fail "the process the test command left is not running: the case shows nothing"
  slot_pool || fail "the pool could not be made"
  ! slot_try || fail "the slot was given out while a process of the card's test command still ran"
  kill "$(cat "$STUB/left")"
  i=0; until slot_try || [ $i -ge 50 ]; do i=$((i + 1)); sleep 0.1; done
  [ $i -lt 50 ] || fail "the slot did not come back once the process the test command left had ended"
}

# An engine case may leave such a process too (a stub it starts through Python's subprocess): its slot then came back
# when the case ended, and the runner's next case ran beside that process, on its core. With a pool of 1, a case run
# as the runner runs it (run_case) leaves a process that closed every descriptor: the case ends and passes, the
# process is ended with it before it is reported (the case's keeper), and the slot is free once it has ended.
t_slotcase() {
  local pid d=$T/$CASE
  slotpool 1; slot_pool && slot_take || fail "the pool's slot could not be taken"
  t_slotstay() {
    ( for ((i = 3; i < 256; i++)); do eval "exec $i>&-"; done; echo "$BASHPID" > "$T/slotcase/left"; exec sleep 60 ) > /dev/null 2>&1 & # sleep: the process the case leaves, alive until the test kills it
    until [ -s "$T/slotcase/left" ]; do sleep 0.05; done
  }
  ( CASE=slotstay; run_case ) > "$d/out" 2>&1 & pid=$!
  slot_free
  wait $pid; grep -qx 'ok slotstay' "$d/out" || fail "the case that left a process did not end and pass: $(cat "$d/out")"
  [ -s "$d/left" ] || fail "the case left no process: the case shows nothing"
  [ -z "$(running "$(cat "$d/left")")" ] || fail "the process the case left runs on after the case is reported"
  wait_until slot_try || fail "the slot did not come back once the process the case left had ended"
}

# A case told to end (the runner is stopped) may leave such a process as well, one that ignores the signal its group
# is sent: the slot then came back as the case's process ended, with that process still on its core. With a pool of
# 1, a case still running is told to end after it started a process that closed every descriptor and ignores the
# signal: the case ends, that process is killed before the case's worker is gone (the case's keeper), and the slot
# is free once it has ended. The keeper kills it 3 s by the clock after the TERM it ignores, however slow each look for
# what the case left is: counted in 30 looks, each half a second here (as on a busy machine, a `ps` of it and a
# `pgrep` a process), the case took 18 s and more to end.
t_slotcaseterm() {
  local pid s d=$T/$CASE
  slotpool 1; slot_pool && slot_take || fail "the pool's slot could not be taken"
  eval "look_$(declare -f case_left)"; case_left() { sleep 0.5; look_case_left "$@"; } # sleep: a look as slow as on a busy machine
  t_slotterm() {
    ( trap '' TERM; for ((i = 3; i < 256; i++)); do eval "exec $i>&-"; done; echo "$BASHPID" > "$T/slotcaseterm/left"; exec sleep 60 ) > /dev/null 2>&1 & # sleep: the process the case leaves, alive until the test kills it
    sleep 60 # sleep: the case still runs when it is told to end
  }
  ( CASE=slotterm; run_case ) > "$d/out" 2>&1 & pid=$!
  slot_free
  until [ -s "$d/left" ]; do sleep 0.05; done
  s=$SECONDS; kill -TERM $pid; wait $pid; [ $? = 143 ] || fail "the case told to end did not end so: $(cat "$d/out")"
  [ $((SECONDS - s)) -lt 10 ] || fail "the case told to end took $((SECONDS - s)) s to end, not about 3 s and the looks after it"
  [ -z "$(running "$(cat "$d/left")")" ] || fail "the process of the case that ignores the signal runs on after the case's worker is gone"
  wait_until slot_try || fail "the slot did not come back once the process the case left had ended"
}

# The process a case leaves may be in a session of its own (a stub started as a daemon would be: Python's subprocess
# with start_new_session), outside the case's process group: looked for in that group alone, it was not found, and
# the slot came back with it still on its core. With a pool of 1, a case leaves such a process: it is in a group of
# its own, it is ended with the case before the case is reported (the case's keeper), and the slot is free once it
# has ended.
t_slotcasesession() {
  local pid d=$T/$CASE
  slotpool 1; slot_pool && slot_take || fail "the pool's slot could not be taken"
  t_slotapart() {
    python3 -c 'import subprocess; print(subprocess.Popen(["sleep", "60"], start_new_session=True).pid)' > "$T/slotcasesession/left"
    ps -o pgid= -p "$(cat "$T/slotcasesession/left")" | tr -d ' ' > "$T/slotcasesession/group"
  }
  ( CASE=slotapart; run_case ) > "$d/out" 2>&1 & pid=$!
  slot_free
  wait $pid; grep -qx 'ok slotapart' "$d/out" || fail "the case that left a process did not end and pass: $(cat "$d/out")"
  [ -s "$d/left" ] && [ "$(cat "$d/group")" = "$(cat "$d/left")" ] || fail "the process the case left is not in a group of its own: the case shows nothing"
  [ -z "$(running "$(cat "$d/left")")" ] || fail "the process the case left in a session of its own runs on after the case is reported"
  wait_until slot_try || fail "the slot did not come back once the process the case left had ended"
}

# That process may have emptied its environment too (a daemon started with an environment of its own: Python's
# subprocess with env={}), so it carries nothing of the case: no descriptor, not the case's process group, no
# variable the case set. Looked for by those, it was not found, and the slot came back with it still on its core.
# With a pool of 1, a case leaves such a process: it is ended with the case before the case is reported (the case's
# keeper, whose child it is by then), and the slot is free once it has ended.
t_slotcaseaway() {
  local pid d=$T/$CASE
  slotpool 1; slot_pool && slot_take || fail "the pool's slot could not be taken"
  t_slotbare() {
    python3 -c 'import subprocess; print(subprocess.Popen(["sleep", "60"], start_new_session=True, env={}).pid)' > "$T/slotcaseaway/left"
    ps -o pgid= -p "$(cat "$T/slotcaseaway/left")" | tr -d ' ' > "$T/slotcaseaway/group"
    # Read, not sized: procfs gives every file a size of 0, a full environment's among them.
    [ "$(uname -s)" != Linux ] || tr -d '\0' < "/proc/$(cat "$T/slotcaseaway/left")/environ" > "$T/slotcaseaway/environ"
  }
  ( CASE=slotbare; run_case ) > "$d/out" 2>&1 & pid=$!
  slot_free
  wait $pid; grep -qx 'ok slotbare' "$d/out" || fail "the case that left a process did not end and pass: $(cat "$d/out")"
  [ -s "$d/left" ] && [ "$(cat "$d/group")" = "$(cat "$d/left")" ] || fail "the process the case left is not in a group of its own: the case shows nothing"
  [ "$(uname -s)" != Linux ] || { [ -e "$d/environ" ] && [ ! -s "$d/environ" ]; } || fail "the process the case left has an environment: the case shows nothing"
  [ -z "$(running "$(cat "$d/left")")" ] || fail "the process the case left, in a session of its own with an empty environment, runs on after the case is reported"
  wait_until slot_try || fail "the slot did not come back once the process the case left had ended"
}

# The process that runs a case may be killed outright while the case runs (the runner's own end, or a case's stray
# kill): it then did nothing more, the slot's keeping among it, and the slot came back as the case ended with what
# the case left still on its core. With a pool of 1, a case leaves a process that closed every descriptor, then
# kills the process that runs it and its own keeper ($$ there), which then ends nothing: the slot stays taken while
# the left process lives, and is free once it has ended.
t_slotcasekill() {
  local pid d=$T/$CASE
  slotpool 1; slot_pool && slot_take || fail "the pool's slot could not be taken"
  t_slotdie() {
    python3 -c 'import subprocess; print(subprocess.Popen(["sleep", "60"]).pid)' > "$T/slotcasekill/left"
    echo "$BASHPID" > "$T/slotcasekill/case"; kill -KILL $$ "$RUNS"
  }
  ( export RUNS=$BASHPID; CASE=slotdie; run_case ) > "$d/out" 2>&1 & pid=$!
  slot_free
  wait $pid 2>/dev/null; [ $? = 137 ] || fail "the process that ran the case was not killed: $(cat "$d/out")"
  wait_until '! kill -0 "$(cat "$d/case")" 2>/dev/null' || fail "the case did not end"
  kill -0 "$(cat "$d/left")" 2>/dev/null || fail "the process the case left is not running: the case shows nothing"
  ! slot_try || fail "the slot was given out while a process of the case whose runner was killed still ran"
  kill "$(cat "$d/left")"
  wait_until slot_try || fail "the slot did not come back once the process the case left had ended"
}

# Where a case's keeper can be no subreaper (macOS), a loop the case left in a session of its own, with no parent, is
# in nothing the keeper knows: it was looked for by the case's mark in its environment alone, and one that had taken
# the mark out ran on after the case was reported. Processes started as a case's are, each in a session of its own:
# one with the mark taken out, which still has the case's scratch folder in its PATH (as every program started after
# a case's setup does), and one with an empty environment, started in that folder. Both are found by what they carry
# (case_far), and the case's keeper is not.
t_casefar() {
  local d=$T/$CASE far new='import subprocess, sys; print(subprocess.Popen(["sleep", "60"], start_new_session=True, env={} if sys.argv[1:] else None).pid)'
  mkdir -p "$d/stub"; trap 'kill $(cat "$T/$CASE/unmarked" "$T/$CASE/bare") 2>/dev/null' EXIT
  ( PATH=$d/stub:$PATH; exec env -u CONVEYOR_TEST_CASE_ID python3 -c "$new" ) > "$d/unmarked"
  ( cd "$d" && exec python3 -c "$new" bare ) > "$d/bare"
  far=$(case_far)
  grep -qx "$(cat "$d/unmarked")" <<<"$far" || fail "a process that took the case's mark out of its environment, with the case's scratch folder in its PATH, is not found: $far"
  ! command -v lsof >/dev/null || grep -qx "$(cat "$d/bare")" <<<"$far" || fail "a process with an empty environment, started in the case's scratch folder, is not found: $far"
  ! grep -qx "$$" <<<"$far" || fail "the case's keeper is taken for a process the case left: $far"
}

# Where a case's keeper can be no subreaper (macOS), a process the case left in a session of its own, with an empty
# environment and outside the case's scratch folder, has no mark, no folder in its environment and no working folder
# of the case: looked for by those alone, it ran on after the case was reported. Looked for as any process with no
# parent and no environment that began while the case ran, a program started meanwhile by someone else was ended as
# the case's. Two processes, each in a session of its own with an empty environment, started in /: one whose error
# output is the case's output file, as that of every program a case starts is, and one that has no file of the case
# open (started from another terminal while the tests ran). Only the first is found (case_far).
t_casebare() {
  local d=$T/$CASE far new='import subprocess, sys; n = subprocess.DEVNULL; print(subprocess.Popen(["sleep", "60"], start_new_session=True, env={}, stdin=n, stdout=n, stderr=None if sys.argv[1:] else n).pid)'
  command -v lsof >/dev/null || return 0
  mkdir -p "$d"; trap 'kill $(cat "$T/$CASE/bare" "$T/$CASE/other") 2>/dev/null' EXIT
  ( cd / && exec python3 -c "$new" bare ) > "$d/bare" 2>> "$T/$CASE.out"
  ( cd / && exec python3 -c "$new" ) > "$d/other"
  far=$(case_far)
  grep -qx "$(cat "$d/bare")" <<<"$far" || fail "a process with an empty environment, started outside the case's scratch folder with the case's output file as its error output, is not found: $far"
  ! grep -qx "$(cat "$d/other")" <<<"$far" || fail "a process with no parent and an empty environment that has no file of the case open is taken for one the case left: $far"
}

# A stand-in for a whole-suite runner, <name>: it asks for its turn (slot_whole), says it has it (<name>.on), and keeps
# it until told to end (<name>.go). Once it has its turn, a run inside it asks too and must not wait (<name>.inner):
# it would wait behind its own run. What slot_whole says goes to <name>.err.
wholerun() { # <name>
  ( slot_pool && slot_whole 2> "$d/$1.err" || exit 1; : > "$d/$1.on"
    ( slot_pool && slot_whole 2>> "$d/$1.err" ) && : > "$d/$1.inner"
    until [ -e "$d/$1.go" ]; do sleep 0.1; done ) &
}

# The owner (2026-11-13): a whole-suite run took half the pool, and with three other cards testing beside it a run
# took three times as long. Two whole-suite runs hold their turns of a pool of 3; a third (the engine's own runner, run
# whole) gets a slot but starts no case until one of the two ends, and then does, saying how long it waited as slot
# wait. A runner that took a turn per case instead of per run, or none, started its cases beside the two.
t_slotwhole() {
  local d=$T/$CASE r
  slotpool 3; mkdir -p "$d/log"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  wholerun A; wholerun B
  wait_until "[ -e '$d/A.on' ] && [ -e '$d/B.on' ]" "cat '$d/A.err' '$d/B.err'" || fail "two whole-suite runs did not both get a turn"
  wait_until "[ -e '$d/A.inner' ] && [ -e '$d/B.inner' ]" || fail "a run inside a run that holds a turn waited for a turn of its own"
  CONVEYOR_TEST_LOG=$d/log bash "$SRC/conveyor.test.sh" > "$d/run.out" 2>&1 & r=$!
  wait_until "grep -q 'this one waits for its turn' '$d/run.out'" "cat '$d/run.out'" \
    || { kill $r; fail "a third whole-suite run did not wait for its turn while two held theirs"; }
  [ ! -e "$d/log/cases" ] || { kill $r; fail "a third whole-suite run started a case while two held their turns: $(ls "$d/log/cases")"; }
  : > "$d/A.go"
  wait_until "ls '$d/log/cases' 2>/dev/null | grep -q ." "cat '$d/run.out'" || { kill $r; fail "the waiting whole-suite run started no case once a turn was free"; }
  kill -TERM $r; wait $r; : > "$d/B.go"; wait
  grep -q '^conveyor: slot wait: [0-9]* s for a whole-suite turn$' "$d/run.out" || fail "the wait for a turn was not said as slot wait: $(head -5 "$d/run.out")"
}

# Turns go in the order runs asked, or a run could be passed over again and again. With two runs holding the turns of a
# pool of 4, C asks and then D, each with a slot: the first turn freed is C's, and D's comes only with the next.
t_slotwholeorder() { wholeorder 4; }
# The same with the pool full (2 slots, the two runs holding the turns): C and D have no slot as they ask. A run that
# took its slot before its place in the order let D, given A's freed slot first, take the turn ahead of C.
t_slotwholequeue() { wholeorder 2; }
wholeorder() { # <pool size>
  local d=$T/$CASE
  slotpool "$1"; mkdir -p "$d"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  wholerun A; wholerun B
  wait_until "[ -e '$d/A.on' ] && [ -e '$d/B.on' ]" || fail "two whole-suite runs did not both get a turn"
  wholerun C; wait_until "grep -q 'waits for its turn' '$d/C.err'" || fail "a third whole-suite run did not wait"
  wholerun D; wait_until "grep -q 'waits for its turn' '$d/D.err'" || fail "a fourth whole-suite run did not wait"
  : > "$d/A.go"
  wait_until "[ -e '$d/C.on' ] || [ -e '$d/D.on' ]" || fail "no waiting run got the turn A gave up"
  [ -e "$d/C.on" ] && [ ! -e "$d/D.on" ] || fail "the turn went to the run that asked second, not first"
  : > "$d/B.go"
  wait_until "[ -e '$d/D.on' ]" || fail "the run that asked second did not get the next turn"
  : > "$d/C.go"; : > "$d/D.go"; wait
}

# A stand-in for a card's test step, <name>: it takes a slot of the pool (<name>.slot) and, once told (<name>.ask), its
# runner, given that slot as its home slot, asks for its turn as wholerun does, writing the seconds it has waited to
# <name>.wait on each look, as a card's runner does. The slot outlives the runner until told (<name>.free), as a
# card's step holds its slot around its runner.
cardrun() { # <name>
  ( slot_pool && until slot_try; do sleep 0.1; done; : > "$d/$1.slot"
    until [ -e "$d/$1.ask" ]; do sleep 0.1; done
    ( export CONVEYOR_TEST_SLOT=$SLOT_FD CONVEYOR_TEST_TURNWAIT=$d/$1.wait; slot_pool && [ -n "$SLOT_HOME" ] && slot_whole 2> "$d/$1.err" || exit 1; : > "$d/$1.on"
      until [ -e "$d/$1.go" ]; do sleep 0.1; done ); : > "$d/$1.ran"
    until [ -e "$d/$1.free" ]; do sleep 0.1; done ) &
}

# A card's step has its slot before its runner asks for a turn: it must still wait behind a run that asked before it
# with no slot yet, or later cards could pass a session's run again and again. Pool of 3: card A and run B hold the
# turns, card D holds the last slot; C asks with no slot, then D asks. A's runner ends (its card still holds the slot):
# a turn is free but no slot is, and D, who has one, once took the turn ahead of C. When A's slot comes free, C takes
# it and the turn; D's turn comes only when B ends.
t_slotwholecard() {
  local d=$T/$CASE
  slotpool 3; mkdir -p "$d"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  cardrun A; : > "$d/A.ask"; wait_until "[ -e '$d/A.on' ]" "cat '$d/A.err'" || fail "a card's whole-suite run did not get a turn"
  wholerun B; wait_until "[ -e '$d/B.on' ]" || fail "a second whole-suite run did not get a turn"
  cardrun D; wait_until "[ -e '$d/D.slot' ]" || fail "a card did not get the last slot"
  wholerun C; wait_until "grep -q 'waits for its turn' '$d/C.err'" || fail "a run with no slot did not wait"
  : > "$d/D.ask"; wait_until "grep -q 'waits for its turn' '$d/D.err'" || fail "a card's run that asked after one with no slot did not wait"
  : > "$d/A.go"
  # A asked first: its ticket is 1. Once it is gone, D has looked again when it has written its wait twice more.
  wait_until "[ ! -e '$d/slots/whole/1' ]" || fail "the turn of a run that ended was not given up"
  : > "$d/m1"; wait_until "[ '$d/D.wait' -nt '$d/m1' ]" || fail "the waiting card's run did not look again"
  : > "$d/m2"; wait_until "[ '$d/D.wait' -nt '$d/m2' ] || [ -e '$d/D.on' ]" || fail "the waiting card's run did not look again"
  [ ! -e "$d/D.on" ] || fail "a card's run that asked after a run with no slot yet took the turn ahead of it"
  : > "$d/A.free"
  wait_until "[ -e '$d/C.on' ]" "cat '$d/C.err'" || fail "the run that asked first got no turn once a slot came free"
  [ ! -e "$d/D.on" ] || fail "the card's run that asked second got a turn beside the one that asked first"
  : > "$d/B.go"
  wait_until "[ -e '$d/D.on' ]" || fail "the card's run that asked second did not get the next turn"
  : > "$d/C.go"; : > "$d/D.go"; : > "$d/D.free"; wait
}

# When every slot is held by a run waiting with one, an earlier run with no slot cannot get one unless a later run gives
# its slot up; letting the later run go ahead (as once) put a card ahead of a session that asked first. Pool of 1:
# card D holds it; C asks with no slot, then D asks. D's run gives the slot up, C takes it and its turn, and D's turn
# comes only when C ends, though D's step still runs. A run that kept its slot left C waiting, or deadlocked. D's runner
# takes back the slot its step holds: once the runner has ended, the step, still running, holds it. A runner that took
# the slot back on a descriptor of its own let it go as it ended, and the step's next test files ran on no slot.
t_slotwholefull() {
  local d=$T/$CASE
  slotpool 1; mkdir -p "$d"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  cardrun D; wait_until "[ -e '$d/D.slot' ]" || fail "a card did not get the pool's slot"
  wholerun C; wait_until "grep -q 'waits for its turn' '$d/C.err'" || fail "a run with no slot did not wait"
  : > "$d/D.ask"
  wait_until "[ -e '$d/C.on' ]" "cat '$d/C.err' '$d/D.err'" \
    || { : > "$d/D.go"; : > "$d/D.free"; : > "$d/C.go"; wait; fail "with every slot held by a run waiting with one, the run that asked first with no slot got no turn"; }
  [ ! -e "$d/D.on" ] || { : > "$d/D.go"; : > "$d/D.free"; : > "$d/C.go"; wait; fail "a card's run that asked second took a turn ahead of or beside the run that asked first"; }
  : > "$d/C.go"
  wait_until "[ -e '$d/D.on' ]" "cat '$d/D.err'" || { : > "$d/D.go"; : > "$d/D.free"; wait; fail "the card's run that gave its slot up got no turn once the first run ended"; }
  : > "$d/D.go"; wait_until "[ -e '$d/D.ran' ]" || { : > "$d/D.free"; wait; fail "the card's runner did not end"; }
  flock -n "$d/slots/1" true && : > "$d/D.lost"
  : > "$d/D.free"; wait
  [ ! -e "$d/D.lost" ] || fail "once its runner that gave the slot up and took it back had ended, the card's step, still running, held no slot"
}

# A run that gave slot k up waits to take k back, and only k: its step is pinned to k's core. A card's step can take k
# first, as k comes free, and ask after it: it must give k up to the run that asked first, or each waits for the other
# for good. Pool of 2: card E holds slot 1, card P holds slot 2 and never asks; ticket 1 is a run that gave slot 1 up
# (w1). E asks: it gives slot 1 up and waits for it, its turn coming only once slot 1 is its again.
t_slotwholeyield() {
  local d=$T/$CASE w
  slotpool 2; mkdir -p "$d/slots/whole"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  cardrun E; wait_until "[ -e '$d/E.slot' ]" || fail "a card did not get a slot"
  ( slot_pool && until slot_try; do sleep 0.1; done; : > "$d/P.slot"; until [ -e "$d/P.free" ]; do sleep 0.1; done ) &
  wait_until "[ -e '$d/P.slot' ]" || { : > "$d/E.free"; wait; fail "a second card did not get a slot"; }
  ( exec {w}>>"$d/slots/whole/1"; flock "$w"; echo w1 > "$d/slots/whole/1"; : > "$d/W.held"
    until [ -e "$d/W.go" ]; do sleep 0.1; done ) &
  wait_until "[ -e '$d/W.held' ]" || fail "the stand-in ticket was not taken"
  : > "$d/E.ask"
  wait_until "flock -n '$d/slots/1' true" "cat '$d/E.err'" || : > "$d/E.kept"
  [ ! -e "$d/E.on" ] || : > "$d/E.early"
  : > "$d/W.go"
  wait_until "[ -e '$d/E.on' ]" "cat '$d/E.err'" || : > "$d/E.none"
  : > "$d/E.go"; wait_until "[ -e '$d/E.ran' ]"; flock -n "$d/slots/1" true && : > "$d/E.lost"
  : > "$d/E.free"; : > "$d/P.free"; wait
  [ ! -e "$d/E.kept" ] || fail "a card's run holding the slot an earlier run waits to take back did not give it up"
  [ ! -e "$d/E.early" ] || fail "a card's run took its turn ahead of a run that asked before it"
  [ ! -e "$d/E.none" ] || fail "the card's run that gave its slot up got no turn once the earlier run had gone"
  [ ! -e "$d/E.lost" ] || fail "the card's step held no slot once its runner had taken its slot back and ended"
}

# Turns are for whole-suite runs alone: a run of a few chosen cases, with both turns held, starts and ends as before.
t_slotwholechosen() {
  local d=$T/$CASE
  slotpool 3; mkdir -p "$d"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  wholerun A; wholerun B
  wait_until "[ -e '$d/A.on' ] && [ -e '$d/B.on' ]" || fail "two whole-suite runs did not both get a turn"
  CONVEYOR_SHELL_TEST_CASE=slothome timeout 120 bash "$SRC/conveyor.test.sh" > "$d/run.out" 2>&1 \
    || fail "a run of a chosen case did not pass while two whole-suite runs held their turns: $(cat "$d/run.out")"
  grep -qx 'ok slothome' "$d/run.out" || fail "the chosen case did not run: $(cat "$d/run.out")"
  ! grep -q 'whole-suite' "$d/run.out" || fail "a run of a chosen case took a whole-suite turn: $(cat "$d/run.out")"
  : > "$d/A.go"; : > "$d/B.go"; wait
}
# Issue 346. Bug: a free slot was refused while the removed machine room read Strained (its old host file thresholds).
t_slotnoroom() { slotpool 1; local h=$XDG_CONFIG_HOME/conveyor/host.json; jq '.pressure = {strained: {wakeMs: 0, freeMB: 999999999}}' "$h" > "$h.n" && mv "$h.n" "$h"
  ( . "$SRC/lib/slots.sh" && slot_pool && slot_try ) || fail "a free test slot was refused under the old machine-room settings: $(cat "$h")"; }
