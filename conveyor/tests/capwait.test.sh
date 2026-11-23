#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the cap counts every card on the belt, in any step and waiting or not, but a card that lands (run():
# turncount(), offcap()), issue 1538.
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

# Bug it catches (issue 1538): the cap counted only the cards in a builder step, so a card in its review and a card
# that waited on another card left their slots free and the loop started more cards than the cap. With the cap at 2,
# #15 waits on c6-16 (a same-file card) and #17 is held in its review: #18 is not picked, as both count. Once #17 is in
# its land step, only #15 counts: health says 1, and #18 is picked while #17 is still in that step, before it lands.
# The case holds #17 in its land step at its after reading of the limit (reading fresh, lib/cardland.sh), asked for
# outside the card records' lock, which a pick needs: a hold inside the landing lock (main's pre-commit hook) would
# keep every pick out, and show nothing of the count.
# It runs the real loop: what it checks is the pick, turn by turn, as live cards stand, wait and move to their land step
# (their .idle and .nocap marks, lib/claim.sh, began()). A direct call to the count reads only marks the case wrote itself.
t_capland() {
  capwaitsetup "$(jq -cs . <(issue 15 2026-01-01) <(issue 16 2026-01-02) <(issue 17 2026-01-03) <(issue 18 2026-01-04))"
  loop control cap 2 >/dev/null || fail "cap 2 was refused"
  echo 'case $PWD in *-15) echo fifteen >> a.txt ;; *) echo "${PWD##*-}" > "f${PWD##*-}.txt" ;; esac' > "$STUB/build"
  echo 'case $PWD in *-17) : > "$STUB/inreview17"; flock "$STUB/review17.gate" true ;; esac' > "$STUB/review-cmd"
  local lk
  # shellcheck disable=SC2034 # gate_limit is read by ungate() and capwaitrun()
  exec {lk}>>"$ST/limit.jsonl.lock" && flock "$lk" && gate_limit=$lk || fail "the case could not hold the limit reading's lock"
  gate review17; capwaitrun
  wait_until 'cwwaits 15 && [ -e "$STUB/inreview17" ]' 'cat "$STUB/run.out"' || fail "#15 did not wait on c6-16 with #17 in its review"
  turns 3 # each would have picked #18, were the waiting card or the card in review left out of the count
  cwpicked 18 && fail "#18 was picked with the cap at 2, #15 waiting on another card and #17 in its review: one of them was left out of the count: $(cat "$ST/loop.json"); picks $(st 'select(.step == "picked") | .issue' | tr '\n' ' ')"
  [ "$(cwcounts)" = "2 1" ] || fail "health does not give 2 cards against the cap (#15, #17) and 1 waiting: $(cwcounts)"
  ungate review17
  wait_until '[ "$(cat "$T/$CASE/cards/"*-17.nocap 2>/dev/null)" = land ]' 'cat "$STUB/run.out"' || fail "#17 did not go on to its land step"
  # #17 waits at its after reading, in its land step and not yet landed: #18 is picked now, as only #15 counts.
  wait_until 'cwpicked 18' 'cat "$STUB/run.out"' || fail "#18 was not picked while #17 was in its land step with the cap at 2: $(cwcounts); $(cat "$ST/loop.json")"
  [ -z "$(st 'select(.issue == 17 and .step == "landed") | .card')" ] || fail "#17 had landed before #18 was picked, so the pick did not come during its land step"
  ungate limit
  capwaitend
}

# Bug it catches (issue 1538): a card whose landing found main moved went back to its lint and product checks with its
# land mark still on, so the loop left it out of the cap's count while it ran them. #17 is held in its land step (count
# 0), main moves, and the landing finds it stale: the card is fitted onto main and runs its product checks again, held
# there by the case. The count is 1 and the land mark is gone while it runs them.
# It runs the real loop: the mark and the count are the loop's turn by turn, with the card's own process moving the mark
# (cardland()); a direct call to the count reads only marks the case wrote itself.
t_capstale() {
  capwaitsetup "$(jq -cs . <(issue 17 2026-01-03))"
  loop control cap 2 >/dev/null || fail "cap 2 was refused"
  echo 'echo "${PWD##*-}" > "f${PWD##*-}.txt"' > "$STUB/build"
  # The product checks of the first pass run on; those of the pass after the stale landing wait for the case.
  printf '%s\n' '[ -e "$STUB/checked" ] && { : > "$STUB/rechecked"; flock "$STUB/recheck.gate" true; }; : > "$STUB/checked"' > "$STUB/recheck.sh"
  tune --arg c "$STUB/recheck.sh" '.checks = [$c]'
  local lk
  # shellcheck disable=SC2034 # gate_limit is read by ungate() and capwaitrun()
  exec {lk}>>"$ST/limit.jsonl.lock" && flock "$lk" && gate_limit=$lk || fail "the case could not hold the limit reading's lock"
  gate recheck; capwaitrun
  wait_until '[ "$(cat "$T/$CASE/cards/"*-17.nocap 2>/dev/null)" = land ]' 'cat "$STUB/run.out"' || fail "#17 did not go on to its land step"
  wait_until '[ "$(cwsteps | cut -d" " -f1)" = 0 ]' 'cat "$STUB/run.out"' || fail "the count does not leave out #17 in its land step: $(cat "$ST/loop.json")"
  (cd "$R" && echo other > other.txt && git add other.txt && git commit -qm "another file") || fail "the case could not move main"
  ungate limit
  wait_until '[ -e "$STUB/rechecked" ]' 'cat "$STUB/run.out"' || fail "#17 did not run its product checks again after main moved: $(cat "$STUB/run.out")"
  ! compgen -G "$T/$CASE/cards/*-17.nocap" >/dev/null || fail "#17 runs its product checks again with its land mark still on: $(cat "$T/$CASE/cards/"*-17.nocap)"
  wait_until '[ "$(cwsteps | cut -d" " -f1)" = 1 ]' 'cat "$STUB/run.out"' || fail "the count leaves out #17 while it runs its product checks again: $(cat "$ST/loop.json")"
  ungate recheck
  capwaitend
}

# The loop's own count at its last turn, as loop.json gives it: "<building> <reviewing> <running>".
cwsteps() { jq -r '"\(.building) \(.reviewing) \(.running)"' "$ST/loop.json" 2>/dev/null; }

# Bugs it catches (issue 1538): a card in its review was left out of the cap's count, so the loop started a second card
# at once with the cap at 1; or, the other way, a card in its build was left out. With the cap at 1, #15's build and
# then its review hold until the case lets each go: #17 is not picked in either, and is picked once #15 has ended; the
# loop's count gives 1 in the build and 1 in the review.
# It runs the real loop: what it checks is the pick, turn by turn, as a card's own steps stand and take away its
# .nocap mark (began(), lib/card.sh). A direct call to the count reads only marks the case wrote itself.
t_capsteps() {
  capwaitsetup "$(jq -cs . <(issue 15 2026-01-01) <(issue 16 2026-01-02) <(issue 17 2026-01-03))"
  echo 'case $PWD in *-15) : > "$STUB/building15"; flock "$STUB/build15.gate" true ;; *-17) : > "$STUB/building17" ;; esac; echo "${PWD##*-}" > "f${PWD##*-}.txt"' > "$STUB/build"
  echo 'case $PWD in *-15) : > "$STUB/inreview15"; flock "$STUB/review15.gate" true ;; esac' > "$STUB/review-cmd"
  gate build15; gate review15; capwaitrun
  wait_until '[ -e "$STUB/building15" ]' 'cat "$STUB/run.out"' || fail "#15 did not start its build"
  turns 3 # each would have picked #17, were #15's build left out of the count
  cwpicked 17 && fail "#17 was picked while #15 built with the cap at 1: a card in its build was left out of the count"
  [ "$(cwsteps)" = "1 0 1" ] || fail "loop.json does not give 1 building (#15), none in review and 1 card in all: $(cat "$ST/loop.json")"
  ungate build15
  wait_until '[ -e "$STUB/inreview15" ]' 'cat "$STUB/run.out"' || fail "#15 did not go on to its review"
  turns 3 # each would have picked #17, were #15's review left out of the count
  cwpicked 17 && fail "#17 was picked while #15 was in its review with the cap at 1: the review was left out of the count"
  # Bug: the Foreman's count on the belt (running, foreman/watch-conveyor.sh) left out the card in review.
  [ "$(cwsteps)" = "1 1 1" ] || fail "loop.json does not give 1 building (#15, in its review), 1 in review and 1 card in all: $(cat "$ST/loop.json")"
  # Bug: with no card ids in loop.json, the snapshot could not tell a card that landed since the loop's turn, still
  # in running, from one landed before it, and counted it twice (commands/snapshot.sh recordsnow()).
  [ "$(jq -r '[.cards[] | sub(".*-"; "")] | join(" ")' "$ST/loop.json" 2>/dev/null)" = "15" ] \
    || fail "loop.json does not name the card of #15 it counts: $(cat "$ST/loop.json")"
  ungate review15
  wait_until '[ -e "$STUB/building17" ]' 'cat "$STUB/run.out"' || fail "#17 was not picked once #15 had ended"
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

# Bug it catches (issue 1538): a card in its Test step was left out of the cap's count (a card's step mark, as the review
# and land marks are), so the loop started a second card while the first ran its tests. With the cap at 1, #15's tests
# hold until the case lets them go: #17 is not picked meanwhile, health gives 1, and it is picked once #15 has ended.
# It runs the real loop for the reason t_capsteps gives: the count follows the card's own step marks, turn by turn.
t_captestcap() {
  capwaitsetup "$(jq -cs . <(issue 15 2026-01-01) <(issue 16 2026-01-02) <(issue 17 2026-01-03))"
  linkset '{"a.txt": ["a.test.sh"], "f15.txt": ["a.test.sh"]}' # #15's file runs a test, so its Test step runs the stub
  echo 'case $PWD in *-17) : > "$STUB/building17" ;; esac; echo "${PWD##*-}" > "f${PWD##*-}.txt"' > "$STUB/build"
  echo 'case $PWD in *-15) : > "$STUB/intests15"; flock "$STUB/tests15.gate" true ;; esac' >> "$STUB/test-cmd"
  gate tests15; capwaitrun
  wait_until '[ -e "$STUB/intests15" ]' 'cat "$STUB/run.out"' || fail "#15 did not go on to its tests"
  turns 3 # each would have picked #17, were #15's Test step left out of the count
  cwpicked 17 && fail "#17 was picked while #15 ran its tests with the cap at 1: the Test step was left out of the count"
  [ "$(cwcounts)" = "1 0" ] || fail "health does not give 1 card against the cap (#15, in its tests) and none waiting: $(cwcounts)"
  ungate tests15
  wait_until '[ -e "$STUB/building17" ]' 'cat "$STUB/run.out"' || fail "#17 was not picked once #15 had ended"
  capwaitend
}

# Bug it catches (issue 1305): cards test at once as many as the cap, and their tests must still wait for the machine's
# test slots (lib/slots.sh), or test runs would share cores again. The cap at 2 and a pool of 1 slot: #15's tests hold
# the only slot until the case lets them go; #17 is picked meanwhile, builds and reaches its Test step, where it waits
# for the slot, its tests not started; they run once
# #15's have ended. Each card's file runs main's a.test.sh, and the two change different files, so neither waits on
# the other's claim.
# It runs the real loop: only cards that reach their Test step beside each other show that the pool and not the cap
# holds their tests (t_slots calls the Test step directly, with no loop and no cap).
t_captestslots() {
  unset CONVEYOR_TEST_SLOT; export CONVEYOR_TEST_POOL=1:$T/$CASE/slots
  capwaitsetup "$(jq -cs . <(issue 15 2026-01-01) <(issue 16 2026-01-02) <(issue 17 2026-01-03))"
  loop control cap 2 >/dev/null || fail "cap 2 was refused"
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

# Bug caught: loop.json's cards were every card the loop still held (mine), and running only those whose job was
# live, so a card that had landed and ended before the count, not yet reaped, was in cards with running 0; the
# snapshot then left it out of landed too (commands/snapshot.sh recordsnow()), and the Foreman's status read "0 on the
# belt now". The card ids named are those running counts: here a card that builds and one taken over, not the one ended.
t_runcards() {
  eval "$(sed -n '/^cardsrun() {/,/^}/p' "$SRC/lib/run.sh")"
  declare -f cardsrun >/dev/null || fail "no cardsrun() in lib/run.sh"
  local got
  # In a subshell: its job table holds only the cards' stand-ins, not the case runner's jobs, as run()'s holds its own.
  # The other jobs beside the cards (pusher and the rest) are unset, as when none runs.
  got=$(local -A mine=() took=(); local running runcards p
    sleep 30 & mine[$!]='c1-1 1'; p=$! # sleep: a card that still builds
    ( exit 0 ) & mine[$!]='c2-2 2'; wait "$!" # a card whose job has ended
    mine[999999999]='c3-3 3' took[999999999]=x # a card an earlier loop started, taken over
    cardsrun; echo "$running of ${#mine[@]} held (${#took[@]} taken over): $(printf '%s' "$runcards" | sort | paste -sd' ')"; kill "$p"; wait "$p" 2>/dev/null)
  [ "$got" = '2 of 3 held (1 taken over): c1-1 c3-3' ] \
    || fail "for a card that builds (c1-1), one whose job ended (c2-2) and one taken over (c3-3), running and the cards named are '$got', not '2 of 3 held (1 taken over): c1-1 c3-3'"
}
