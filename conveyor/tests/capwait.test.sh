#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a card that only waits on another card takes no build slot (run(): idle()), issue 201.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Cap 1, every review a GO, a live record every second and a poll every second. Issue 16 is on the belt as card
# c6-16, holding a.txt: its process is a stand-in (holder), alive, so a card that changes a.txt waits on it at its
# landing claim until the case takes the claim away. The loop runs in the background (lp), its output in run.out.
capwaitsetup() { # <issues json>
  setup "$1"; for i in $(seq 1 12); do echo "$GO" > "$STUB/review.$i"; done
  tune '.tunables.live = 1 | .tunables.poll = 1'; mkdir -p "$T/$CASE/cards"; loop control cap 1 >/dev/null || fail "cap 1 was refused"
  watchturns
  landed 16 | jq -c '.card = "c6-16" | .step = "picked"' >> "$ST/cards.jsonl"
  command sleep 300 & holder=$!; jq -cn --argjson p "$holder" '{pid: $p, paths: ["a.txt"], held: true}' > "$T/$CASE/cards/c6-16.claim" # sleep: a stand-in for the holder's process, alive; cwfree ends it once no card is to wait on it
}
cwfree() { kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; } # the holder's stand-in ends
# gate <name>: the case holds a lock on $STUB/<name>.gate. A stub that runs `flock "$STUB/<name>.gate" true` blocks
# there, with no CPU used and no polling, until the case lets it go (ungate) or the case ends (its lock goes with it).
gate() { local g; exec {g}>"$STUB/$1.gate" && flock "$g" && printf -v "gate_$1" %s "$g"; }
ungate() { local v=gate_$1 g; g=${!v:-}; [ -z "$g" ] || exec {g}>&-; printf -v "$v" %s ''; }
# The loop's shell lets go of the case's gates: a stub under it that kept one open would wait on its own lock for ever.
capwaitrun() { ( local v g; for v in ${!gate_@}; do g=${!v}; [ -z "$g" ] || exec {g}>&-; done; loop run > "$STUB/run.out" 2>&1 ) & lp=$!; }
cwwaits() { jq -e '.waits.on' "$T/$CASE/cards/"*-"$1".live >/dev/null 2>&1; } # <issue>: its card waits on another card now
cwpicked() { [ -n "$(st "select(.issue == $1 and .step == \"picked\") | .card")" ]; } # <issue>
# The loop's own count at its last turn, as health gives it: "<building> <waiting>".
cwcounts() { loop health | jq -r '"\(.building) \(.waitingCount)"'; }
# The holder goes before the loop is waited for: a card that waits on it ends only once it is gone, so the loop's stop
# waited out the holder's 300 s, the case's whole limit (its file's `# timeout:` line).
capwaitend() { loop control stop >/dev/null; cwfree; wait "$lp" 2>/dev/null; }
# CPU load from other processes: two busy loops beside the loop, in the case's box (one core, where the runner has
# one, slot_box), so the engine gets about a third of it. Started before any gate, so no loop holds a gate's lock.
cwload() { local i; cwloads=(); for i in 1 2; do ( while :; do :; done ) & cwloads+=("$!"); done; }
cwunload() { kill "${cwloads[@]}" 2>/dev/null; wait "${cwloads[@]}" 2>/dev/null; cwloads=(); }

# Bug it catches: a card that waited on a same-file card for minutes, using no CPU, still took one of the cap's slots,
# so one fewer issue was built. With the cap at 1, #15 waits on c6-16, and #17 is picked meanwhile. Once the wait ends
# (#15 is in its tests), the cap is full again: #18 is not picked, nor once #15 lands while #17 still builds; it is
# picked once #17 ends.
t_capwait() {
  capwaitsetup "$(jq -cs . <(issue 15 2026-01-01) <(issue 16 2026-01-02) <(issue 17 2026-01-03) <(issue 18 2026-01-04))"
  cat > "$STUB/build" <<'EOF'
case $PWD in
  *-15) echo fifteen >> a.txt ;;
  *-17) : > "$STUB/building17"; flock "$STUB/go17.gate" true; exit 1 ;;
  *) echo "${PWD##*-}" > "f${PWD##*-}.txt" ;;
esac
EOF
  echo 'case $PWD in *-15) [ ! -e "$STUB/released" ] || { : > "$STUB/intests15"; flock "$STUB/go15.gate" true; } ;; esac' >> "$STUB/test-cmd"
  gate go15; gate go17; capwaitrun
  wait_until 'cwwaits 15' 'cat "$STUB/run.out"' || fail "#15 did not wait on c6-16"
  wait_until '[ -e "$STUB/building17" ]' 'cat "$STUB/run.out"' || fail "with #15 only waiting, #17 was not picked: the waiting card took the only slot"
  turns 2 # a turn after the pick has written the loop's count
  cwwaits 15 || fail "#15 no longer waits: #17 was not picked beside a waiting card"
  [ "$(cwcounts)" = "1 1" ] || fail "health does not give 1 building and 1 waiting card: $(cwcounts)"
  : > "$STUB/released"; rm -f "$T/$CASE/cards/c6-16.claim"; cwfree
  wait_until '[ -e "$STUB/intests15" ]' 'cat "$STUB/run.out"' || fail "#15 did not go on to its tests once its claim went"
  turns 3 # each would have picked #18, were #15 still left out of the count
  cwpicked 18 && fail "#18 was picked while #15, its wait over, and #17 both ran with the cap at 1"
  ungate go15
  wait_until "[ -n \"\$(st 'select(.issue == 15 and .step == \"landed\") | .card')\" ]" 'cat "$STUB/run.out"' || fail "#15 did not land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  turns 2
  cwpicked 18 && fail "#18 was picked while #17 still held the only slot"
  ungate go17
  wait_until 'cwpicked 18' 'cat "$STUB/run.out"' || fail "#18 was not picked once #17 ended"
  wait "$lp" || fail "run exited non-zero: $(cat "$STUB/run.out")"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "15 18 " ] || fail "#15 and #18 did not land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ -z "$(ls "$T/$CASE/cards"/*.idle 2>/dev/null)" ] || fail "a card's wait mark was left behind: $(ls "$T/$CASE/cards")"
}

# Bug it catches: with every waiting card left out, the loop would start card after card while the old ones piled up
# waiting. At most as many waiting cards as the cap are left out: with the cap at 1, #15 waits on c6-16 and #19 is
# picked; once #19 waits too (both change a.txt), one of the two counts again, so #18 is not picked.
t_capwaitmany() {
  capwaitsetup "$(jq -cs . <(issue 15 2026-01-01) <(issue 16 2026-01-02) <(issue 19 2026-01-03) <(issue 18 2026-01-04))"
  echo 'case $PWD in *-15|*-19) echo "${PWD##*-}" >> a.txt ;; *) echo "${PWD##*-}" > "f${PWD##*-}.txt" ;; esac' > "$STUB/build"
  capwaitrun
  wait_until 'cwwaits 15 && cwwaits 19' 'cat "$STUB/run.out"' || fail "#15 and #19 did not both wait"
  turns 3 # each would have picked #18, were both waiting cards left out of the count
  cwpicked 18 && fail "#18 was picked with two cards waiting and the cap at 1: more waiting cards than the cap were left out"
  cwwaits 15 && cwwaits 19 || fail "a waiting card went on during the turns: the case proves nothing"
  [ "$(cwcounts)" = "1 1" ] || fail "health does not give 1 building (the waiting card past the limit) and 1 waiting: $(cwcounts)"
  capwaitend
}

# Bug it catches: a card that runs its own checks and tests while it waits (a GO with batches on) uses CPU and test
# slots, so it counts as running then. #15 waits on c6-16 and runs its tests in the wait: #17 is not picked while
# they run, and is picked once they have passed and #15 only waits again.
t_capwaittests() {
  capwaitsetup "$(jq -cs . <(issue 15 2026-01-01) <(issue 16 2026-01-02) <(issue 17 2026-01-03))"; tune '.landBatch = 8'
  echo 'case $PWD in *-15) echo fifteen >> a.txt ;; *) echo seventeen > f17.txt ;; esac' > "$STUB/build"
  # In its wait, #15's claim says so (held false, from claim(); the holder's claim keeps it there till the case ends);
  # its live record does not: the test run writes over it as it starts, which on a busy machine came before this read.
  echo 'case $PWD in *-15) [ -e "$STUB/intests15" ] || { ! jq -e ".held == false" "$PWD.claim" >/dev/null 2>&1 || : > "$STUB/inwait15"; : > "$STUB/intests15"; flock "$STUB/go15.gate" true; } ;; esac' >> "$STUB/test-cmd"
  # Under CPU load (the 1.4.0 release run, a load of 36), #15 reached its tests before it waited and the case failed:
  # the holder's claim, not the cards' speed, makes #15 wait, so the load changes nothing. It ends once #15 is in its
  # tests, the window that race was in.
  cwload; gate go15; capwaitrun
  wait_until '[ -e "$STUB/intests15" ]' 'cat "$STUB/run.out"' || fail "#15 did not run its tests"
  cwunload
  [ -e "$STUB/inwait15" ] || fail "#15 ran its tests before it waited: the case proves nothing"
  turns 3 # each would have picked #17, were #15 left out of the count while its tests ran
  cwpicked 17 && fail "#17 was picked while #15 ran its tests in its wait"
  ungate go15
  wait_until 'cwpicked 17' 'cat "$STUB/run.out"' || fail "#17 was not picked once #15's tests passed and it only waited again"
  capwaitend
}
