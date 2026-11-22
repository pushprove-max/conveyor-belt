#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a card that only waits on another card takes no build slot (run(): idle()), issue 201, nor does a
# card in a step that runs no builder session (run(): offcap()), issue 1305.
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
# The cases run the real loop: what they check is the loop's pick as live cards stand and take away their .idle marks
# from their own processes (lib/claim.sh) at a wait. A direct call to the count (lib/run.sh) reads only marks the case
# wrote, so it cannot show that a card's wait sets them, nor that the pick follows them turn by turn.
# The loop's shell lets go of the case's gates: a stub under it that kept one open would wait on its own lock for ever.
capwaitrun() { ( local v g; for v in ${!gate_@}; do g=${!v}; [ -z "$g" ] || exec {g}>&-; done; loop run > "$STUB/run.out" 2>&1 ) & lp=$!; }
cwwaits() { jq -e '.waits.on' "$T/$CASE/cards/"*-"$1".live >/dev/null 2>&1; } # <issue>: its card waits on another card now
cwpicked() { [ -n "$(st "select(.issue == $1 and .step == \"picked\") | .card")" ]; } # <issue>
# The loop's own count at its last turn, as health gives it: "<building> <waiting>".
cwcounts() { loop health | jq -r '"\(.building) \(.waitingCount)"'; }
# The holder goes before the loop is waited for: a card that waits on it ends only once it is gone, so the loop's stop
# waited out the holder's 300 s, the case's whole limit (its file's `# timeout:` line).
capwaitend() { loop control stop >/dev/null; cwfree; wait "$lp" 2>/dev/null; }

# Bug it catches: a card that waited on a same-file card for minutes, using no CPU, still took one of the cap's slots,
# so one fewer issue was built. With the cap at 1, #15 waits on c6-16, and #17 is picked meanwhile. Once the wait ends,
# #15 is in its tests, which take no build slot (t_capsteps), and #17 still builds: #18 is not picked, nor once #15
# lands; it is picked once #17 ends.
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
  turns 3 # each would have picked #18, were #17's build left out of the count
  cwpicked 18 && fail "#18 was picked while #17 built with the cap at 1"
  ungate go15
  wait_until "[ -n \"\$(st 'select(.issue == 15 and .step == \"landed\") | .card')\" ]" 'cat "$STUB/run.out"' || fail "#15 did not land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  turns 2
  cwpicked 18 && fail "#18 was picked while #17 still held the only slot"
  ungate go17
  wait_until 'cwpicked 18' 'cat "$STUB/run.out"' || fail "#18 was not picked once #17 ended"
  wait "$lp" || fail "run exited non-zero: $(cat "$STUB/run.out")"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "15 18 " ] || fail "#15 and #18 did not land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ -z "$(ls "$T/$CASE/cards"/*.idle "$T/$CASE/cards"/*.nocap 2>/dev/null)" ] || fail "a card's wait or step mark was left behind: $(ls "$T/$CASE/cards")"
}

# Bug it catches (issue 1305): a card past its build counted against the cap again once more cards waited than the
# cap, though out of its wait it holds no build slot. (The limit on waiting cards left out holds only the cards of a
# build, fix or rebase step, which wait for their seat's CLI alone.) With the cap at 1 and #18 held, #15 waits on c6-16
# and #19 is picked; #19 waits too (both change a.txt). The loop's count gives none building and 2 waiting, and once
# #18 is released it is picked beside the two waiting cards.
t_capwaitmany() {
  capwaitsetup "$(jq -cs . <(issue 15 2026-01-01) <(issue 16 2026-01-02) <(issue 19 2026-01-03) <(issue 18 2026-01-04))"
  loop control hold 18 >/dev/null || fail "hold 18 was refused"
  echo 'case $PWD in *-15|*-19) echo "${PWD##*-}" >> a.txt ;; *) : > "$STUB/building${PWD##*-}"; echo "${PWD##*-}" > "f${PWD##*-}.txt" ;; esac' > "$STUB/build"
  capwaitrun
  wait_until 'cwwaits 15 && cwwaits 19' 'cat "$STUB/run.out"' || fail "#15 and #19 did not both wait"
  turns 2 # a turn after both waits stood has written the loop's count
  [ "$(cwcounts)" = "0 2" ] || fail "health does not give none building and 2 waiting with #15 and #19 waiting past their build: $(cwcounts)"
  loop control release 18 >/dev/null || fail "release 18 was refused"
  wait_until '[ -e "$STUB/building18" ]' 'cat "$STUB/run.out"' || fail "#18 was not picked with the cap at 1 and the only cards on the belt waiting past their build"
  cwwaits 15 && cwwaits 19 || fail "a waiting card went on before #18 was picked: the case proves nothing"
  capwaitend
}

# The loop's own count at its last turn, as loop.json gives it: "<building> <reviewing> <running>".
cwsteps() { jq -r '"\(.building) \(.reviewing) \(.running)"' "$ST/loop.json" 2>/dev/null; }

# Bugs it catches (issue 1305): a card in its review held one of the cap's slots, though a review runs no builder
# session, so with the cap full of cards in review the loop built nothing; or, the other way, a card in its build was
# left out and the loop built more cards at once than the cap. With the cap at 1, #15's build and then its review
# hold until the case lets each go: #17 is not picked while #15 builds, and is picked while #15 is in its review, the
# loop's count then giving 1 card building (#17, held in its build) and 1 in review.
# It runs the real loop: what it checks is the pick, turn by turn, as a card's own steps stand and take away its
# .nocap mark (began(), lib/card.sh). A direct call to the count reads only marks the case wrote itself.
t_capsteps() {
  capwaitsetup "$(jq -cs . <(issue 15 2026-01-01) <(issue 16 2026-01-02) <(issue 17 2026-01-03))"
  cat > "$STUB/build" <<'EOF'
case $PWD in
  *-15) : > "$STUB/building15"; flock "$STUB/build15.gate" true ;;
  *-17) : > "$STUB/building17"; flock "$STUB/build17.gate" true ;;
esac
echo "${PWD##*-}" > "f${PWD##*-}.txt"
EOF
  echo 'case $PWD in *-15) : > "$STUB/inreview15"; flock "$STUB/review15.gate" true ;; esac' > "$STUB/review-cmd"
  gate build15; gate review15; gate build17; capwaitrun
  wait_until '[ -e "$STUB/building15" ]' 'cat "$STUB/run.out"' || fail "#15 did not start its build"
  turns 3 # each would have picked #17, were #15's build left out of the count
  cwpicked 17 && fail "#17 was picked while #15 built with the cap at 1: a card in its build was left out of the count"
  [ "$(cwsteps)" = "1 0 1" ] || fail "loop.json does not give 1 building (#15), none in review and 1 card in all: $(cat "$ST/loop.json")"
  ungate build15
  wait_until '[ -e "$STUB/inreview15" ]' 'cat "$STUB/run.out"' || fail "#15 did not go on to its review"
  wait_until '[ -e "$STUB/building17" ]' 'cat "$STUB/run.out"' || fail "with #15 in its review and the cap at 1, #17 was not picked: the review took the only build slot"
  turns 2 # a turn after the pick has written the loop's count
  # Bug: the Foreman's count on the belt (running, foreman/watch-conveyor.sh) left out the card in review.
  [ "$(cwsteps)" = "1 1 2" ] || fail "loop.json does not give 1 building (#17), 1 in review (#15) and 2 cards in all: $(cat "$ST/loop.json")"
  capwaitend
}

# Bug it catches (issue 1305): the machine's cap (the host file's cap) is over every card that builds, reviews or
# tests, but the loop gave room() its builder count, so a card in review left the machine's only slot free and a
# second card started past it. The project cap at 2 and the machine cap at 1: while #15 is in its review, and then
# while it runs its tests, #17 is not picked and waits for a machine slot; it is picked once #15 has ended.
# It runs the real loop for the reason t_capsteps gives: the count follows the card's own step marks, turn by turn.
t_capmachine() {
  mkdir -p "$T/$CASE/config/conveyor" && echo '{"cap": 1}' > "$T/$CASE/config/conveyor/host.json" || fail "the host file could not be written"
  capwaitsetup "$(jq -cs . <(issue 15 2026-01-01) <(issue 16 2026-01-02) <(issue 17 2026-01-03))"
  loop control cap 2 >/dev/null || fail "cap 2 was refused"
  linkset '{"a.txt": ["a.test.sh"], "f15.txt": ["a.test.sh"]}' # #15's file runs a test, so its Test step runs the stub
  echo 'case $PWD in *-17) : > "$STUB/building17" ;; esac; echo "${PWD##*-}" > "f${PWD##*-}.txt"' > "$STUB/build"
  echo 'case $PWD in *-15) : > "$STUB/inreview15"; flock "$STUB/review15.gate" true ;; esac' > "$STUB/review-cmd"
  echo 'case $PWD in *-15) : > "$STUB/intests15"; flock "$STUB/tests15.gate" true ;; esac' >> "$STUB/test-cmd"
  gate review15; gate tests15; capwaitrun
  wait_until '[ -e "$STUB/inreview15" ]' 'cat "$STUB/run.out"' || fail "#15 did not go on to its review"
  turns 3 # each would have picked #17, were #15's review left out of the machine's count
  cwpicked 17 && fail "#17 was picked while #15 was in its review with the machine cap at 1: the review was left out of the machine's count"
  [ "$(jq -r '"\(.issue) \(.reason)"' "$ST/room.json" 2>/dev/null)" = "17 waiting for a machine slot: 1 of the machine cap 1 in use" ] \
    || fail "#17 does not wait for a machine slot with #15 in its review: $(cat "$ST/room.json" 2>&1)"
  ungate review15
  wait_until '[ -e "$STUB/intests15" ]' 'cat "$STUB/run.out"' || fail "#15 did not go on to its tests"
  turns 3 # each would have picked #17, were #15's Test step left out of the machine's count
  cwpicked 17 && fail "#17 was picked while #15 ran its tests with the machine cap at 1: the Test step was left out of the machine's count"
  ungate tests15
  wait_until '[ -e "$STUB/building17" ]' 'cat "$STUB/run.out"' || fail "#17 was not picked once #15 had ended"
  capwaitend
}

# Bug it catches (issue 1305): with cards in their Test step left out of the builder cap, more cards test at once than
# the cap; their tests must still wait for the machine's test slots (lib/slots.sh), or test runs would share cores
# again. The cap at 1 and a pool of 1 slot: #15's tests hold the only slot until the case lets them go; #17 is picked
# meanwhile, builds and reaches its Test step, where it waits for the slot, its tests not started; they run once
# #15's have ended. Each card's file runs main's a.test.sh, and the two change different files, so neither waits on
# the other's claim.
# It runs the real loop: only cards that reach their Test step beside each other, past the cap, show that the pool
# and not the cap holds their tests (t_slots calls the Test step directly, with no loop and no cap).
t_captestslots() {
  unset CONVEYOR_TEST_SLOT; export CONVEYOR_TEST_POOL=1:$T/$CASE/slots
  capwaitsetup "$(jq -cs . <(issue 15 2026-01-01) <(issue 16 2026-01-02) <(issue 17 2026-01-03))"
  linkset '{"a.txt": ["a.test.sh"], "f15.txt": ["a.test.sh"], "f17.txt": ["a.test.sh"]}'
  echo 'echo "${PWD##*-}" > "f${PWD##*-}.txt"' > "$STUB/build"
  echo 'case $PWD in *-15) : > "$STUB/intests15"; flock "$STUB/go15.gate" true ;; *-17) : > "$STUB/intests17" ;; esac' >> "$STUB/test-cmd"
  gate go15; capwaitrun
  wait_until '[ -e "$STUB/intests15" ]' 'cat "$STUB/run.out"' || fail "#15 did not run its tests"
  wait_until 'jq -e ".step == \"test\" and .action == \"waiting for a test slot (1 of 1 in use)\"" "$T/$CASE/cards/"*-17.live >/dev/null 2>&1' 'cat "$STUB/run.out"' \
    || fail "#17 was not picked beside #15's tests, or did not wait for the slot they held: $(cat "$T/$CASE/cards/"*-17.live 2>/dev/null)"
  [ ! -e "$STUB/intests17" ] || fail "#17's tests ran while #15's held the only test slot"
  ungate go15
  wait_until '[ -e "$STUB/intests17" ]' 'cat "$STUB/run.out"' || fail "#17's tests did not run once #15's had ended"
  capwaitend
}
