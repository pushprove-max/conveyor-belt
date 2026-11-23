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

# Bug it catches (follow-up of issue 1538): a card whose landing found main moved ran its checks again at once, beside
# the cards the loop had picked while its land step was off the cap, so more cards worked than the cap. At cap 1, #17
# is held in its land step, #18 is picked meanwhile and held in its build, and main moves: #17's landing is stale. It
# must wait (<worktree>.capheld, caphold()) and run its checks again only once #18 no longer counts (it is in its land
# step). The case holds #18 at its after reading of the limit, in its land step, and the second checks of #17 note
# #18's land mark as they start: one let go while #18 was in its build notes none, and one let go in its review or Test
# step notes review or test (E3 of a later review).
# It runs the real loop: the hold is let go by the loop's turn (capfree() in turncount()) as #18's own process moves
# its marks, and the stale landing comes from cardland() itself; a direct call reads only marks the case wrote.
t_capstaleheld() {
  capwaitsetup "$(jq -cs . <(issue 17 2026-01-03) <(issue 18 2026-01-04))"
  echo 'case $PWD in *-18) : > "$STUB/building18"; flock "$STUB/build18.gate" true ;; esac; echo "${PWD##*-}" > "f${PWD##*-}.txt"' > "$STUB/build"
  # Each card's first product checks run on; a second run of #17's (after its stale landing) is marked, with #18's
  # land mark as it stands then (none when #18 has no .nocap).
  printf '%s\n' "n=\${PWD##*-}; [ ! -e \"\$STUB/checked\$n\" ] || { cat \"$T/$CASE/cards/\"*-18.nocap > \"\$STUB/at18\" 2>/dev/null || echo none > \"\$STUB/at18\"; : > \"\$STUB/rechecked\$n\"; }; : > \"\$STUB/checked\$n\"" > "$STUB/recheck.sh"
  tune --arg c "$STUB/recheck.sh" '.checks = [$c]'
  local lk
  # shellcheck disable=SC2034 # gate_limit is read by ungate() and capwaitrun()
  exec {lk}>>"$ST/limit.jsonl.lock" && flock "$lk" && gate_limit=$lk || fail "the case could not hold the limit reading's lock"
  gate build18; capwaitrun
  wait_until '[ -e "$STUB/building18" ]' 'cat "$STUB/run.out"' || fail "#18 was not picked while #17 was in its land step with the cap at 1"
  (cd "$R" && echo other > other.txt && git add other.txt && git commit -qm "another file") || fail "the case could not move main"
  ungate limit
  wait_until 'compgen -G "$T/$CASE/cards/*-17.capheld" >/dev/null' 'cat "$STUB/run.out"' || fail "#17's landing found main moved, but #17 did not wait for room under the cap of 1 with #18 building: $(cat "$STUB/run.out")"
  turns 3 # each would have let #17 go, were #18's build left out of the count
  [ ! -e "$STUB/rechecked17" ] || fail "#17 ran its product checks again beside #18's build with the cap at 1"
  # #18 cannot land now: it waits at its after reading of the limit, in its land step, until the case lets it go.
  # shellcheck disable=SC2034 # gate_limit is read by ungate()
  exec {lk}>>"$ST/limit.jsonl.lock" && flock "$lk" && gate_limit=$lk || fail "the case could not hold the limit reading's lock again"
  ungate build18
  wait_until '[ -e "$STUB/rechecked17" ]' 'cat "$STUB/run.out"' || fail "#17 did not run its checks again once #18 had left the cap: $(cat "$STUB/run.out")"
  [ "$(cat "$STUB/at18")" = land ] || fail "#17 ran its checks again with the cap at 1 while #18 still counted (its land mark then: $(cat "$STUB/at18")), not yet in its land step"
  ungate limit
  capwaitend
}

# Bugs it catches (E1 of this follow-up): capfree() left every card with <worktree>.idle out of its count. At cap 1,
# a card that waits for its seat's CLI (cliwake() starts it with no look at the cap), or a held card let go in an
# earlier turn and not awake yet (its .idle still there), left the slot free, so a held card was let go beside it.
# A card that waits on the held card at its claim (its live record names that card) is still left out, or the two
# would wait on each other for ever. capfree() is called alone on marks the case writes: each state is one a card's
# own wait writes (seatlive(), lib/control.sh; settle(), lib/claim.sh; landwait(), lib/claim.sh).
# Bugs it catches too (E3, E6 of a later review): a card marked "owed" in an earlier turn, its claim wait just ended
# (.idle gone) but its mark not yet read, had the mark taken away by the turn, so it went on beside the held card it
# had lent its slot to; and a card that waits at its land step for the landing turn (its live record names a card,
# with no waited field) lent its slot, though it never reads the mark.
t_capfreecount() {
  setup '[]'; local C=$T/$CASE/cards; mkdir -p "$C"
  command sleep 60 & local p=$! # sleep: a stand-in for the cards' processes, alive
  cfree() { # <the other card's marks: cli, claim, woken, land or owed>; prints whether held card c1 is still held after a turn at cap 1, and c2's mark
    rm -f "$C"/c*; : > "$C/c1.capheld"; : > "$C/c2.idle"
    case $1 in
      cli) jq -cn '{step: "review", cli: "claude", action: "waiting for claude"}' > "$C/c2.live" ;;
      claim) jq -cn '{step: "test", waits: {on: "c1", paths: ["a.txt"]}, waited: {before: 0, behind: ["c1"]}}' > "$C/c2.live" ;;
      land) jq -cn '{step: "land", waits: {on: "c1", paths: []}}' > "$C/c2.live" ;;
      owed) rm -f "$C/c2.idle"; echo owed > "$C/c2.capheld" ;;
    esac
    CONVEYOR_MAIN=$R CONVEYOR_CARDS=$C bash -c '. "$1/conveyor.sh" state-dir > /dev/null && . "$1/lib/card.sh" && . "$1/lib/run.sh" && capfree "$2 c2"$'"'\n'"'"$2 c1" 1' _ "$SRC" "$p" \
      || echo "capfree failed"
    { [ -e "$C/c1.capheld" ] && echo held || echo free; } | tr -d '\n'; echo " $(cat "$C/c2.capheld" 2>/dev/null)"
  }
  local r
  r=$(cfree cli); [ "$r" = "held " ] || fail "capfree with cap 1, c2 waiting for its CLI (live: cli claude) and c1 held: c1 was let go ($r)"
  r=$(cfree woken); [ "$r" = "held " ] || fail "capfree with cap 1, c2 let go from its hold in an earlier turn (.idle, no live record) and c1 held: c1 was let go ($r)"
  r=$(cfree claim); [ "$r" = "free owed" ] || fail "capfree with cap 1, c2 waiting at its claim on c1 (live: waits.on c1, waited) and c1 held: c1 stayed held, or c2 was not marked owed ($r)"
  r=$(cfree land); [ "$r" = "held " ] || fail "capfree with cap 1, c2 waiting at its land step for c1's landing turn (live: waits.on c1, no waited) and c1 held: c2 lent its slot ($r)"
  r=$(cfree owed); [ "$r" = "held owed" ] || fail "capfree with cap 1, c2 marked owed with no .idle (its wait just ended) and c1 held: c1 was let go, or c2's mark was taken away ($r)"
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null || :
}

# Bug it catches (E4 of a later review): a card that no loop runs (land-branch, `lane fast land`) whose landing found
# main moved waited in caphold() for a loop's turn that never came. With no LOOPCARD, caphold() returns at once and
# leaves no mark; its sleep is made to end the call (exit 7), so a hold shows as rc 7, not as a hang.
# Bug it catches too (E1 of a later review): a main-red fix card (issue 0, no branch) whose landing found main moved
# waited for room under a cap filled by cards that wait for main, so for its fix: none could go on. It goes on at once.
t_capholdnoloop() {
  setup '[]'; mkdir -p "$T/$CASE/cards"
  # The engine's commands are a here-document: its lines are read one by one by the test lint, its comments too.
  fx_in "$(cat <<'EOF'
unset LOOPCARD; sleep() { [ "${FUNCNAME[1]}" != caphold ] || exit 7; command sleep "$@"; } # sleep: a stand-in that ends a hold, never a wait for a condition
caphold c1-1 1 "$CARDS/c1-1" land; echo "back $([ -e "$CARDS/c1-1.capheld" ] && echo marked || echo clean)"
LOOPCARD=1 br=''; caphold c2-0 0 "$CARDS/c2-0" land; echo "fix back $([ -e "$CARDS/c2-0.capheld" ] && echo marked || echo clean)"
EOF
)"
  grep -qx "back clean" "$T/$CASE/run.out" \
    || fail "caphold c1-1 1 <worktree> land, with no LOOPCARD: it waited for a loop's turn (rc $RC) or left its mark: $(cat "$T/$CASE/run.out")"
  [ "$RC" = 0 ] && [ "$(tail -n 1 "$T/$CASE/run.out")" = "fix back clean" ] \
    || fail "caphold c2-0 0 <worktree> land, with LOOPCARD=1 and br='' (a main-red fix card): it waited for room under the cap (rc $RC) or left its mark: $(cat "$T/$CASE/run.out")"
}

# Bugs it catches (E5 of two later reviews): stop spared a card that waits for room after its landing failed, as its
# last land step's start line looked like a landing under way; and a card spared as it has filed slices (halt() leaves
# it to finish) then waited for room for ever, as a stopped loop's turn let no held card go. Both cards wait in
# caphold() in their own processes; as in the loop's turn, halt() (turnended()) runs first, then turncount().
# Bug it catches too (E2 of a later review): a card that waited for room wrote no live record, so `health` listed it as
# stuck once SESSION_STUCK passed, and the loop's stuck check (turnended()) could end it. Its live record is checked
# while it waits, written again after the case makes it old (E5 of a later review: a record written once goes stale),
# and gone once it is let go.
t_capstop() {
  setup '[]'; mkdir -p "$T/$CASE/cards"
  # The engine's commands are a here-document, as in t_capholdnoloop.
  fx_in "$(cat <<'EOF'
LOOPCARD=1 LIVE=0.2; record c1-1 1 start ok '{"of":"land"}'
record c2-2 2 grown split '{"grown":{"mode":"on","files":5,"limit":3,"verdict":"split","why":"too big","filed":[101]}}'; record c2-2 2 start ok '{"of":"land"}'
( caphold c1-1 1 "$CARDS/c1-1" land ) & p1=$!
( caphold c2-2 2 "$CARDS/c2-2" land ) & p2=$!
i=0; until { [ -e "$CARDS/c1-1.idle" ] && [ -e "$CARDS/c2-2.idle" ]; } || [ $i -gt 100 ]; do command sleep 0.1; i=$((i + 1)); done # sleep: wait_until is not loaded in the engine shell fx_in runs
echo "live $(jq -r '"\(.step) \(.last | fromdate > now - 60) \(.action)"' "$CARDS/c1-1.live" 2> /dev/null)"
# The live record is made old; a wait that wrote it once and never again leaves it old.
jq -c '.last = "2000-01-01T00:00:00Z"' "$CARDS/c1-1.live" > "$CARDS/c1-1.live.old" && mv -f "$CARDS/c1-1.live.old" "$CARDS/c1-1.live"
i=0; until jq -e '.last | fromdate > now - 60' "$CARDS/c1-1.live" > /dev/null 2>&1 || [ $i -gt 50 ]; do command sleep 0.1; i=$((i + 1)); done # sleep: a bounded wait for caphold()'s next write of the record (LIVE, set below 1 s)
echo "refreshed $(jq -r '.last | fromdate > now - 60' "$CARDS/c1-1.live" 2> /dev/null)"
printf '%s c1-1\n%s c2-2\n' "$p1" "$p2" | halt | sed -e "s/^$p1 /ended /" -e "s/^$p2 /ended /"
# run()'s own variables that turncount() reads, as a stopped loop whose stop spared c2-2 has them
declare -A mine=([$p2]="c2-2 2") took=(); now=stopped cap=1 mhold="" htried=0 old="" why="" self="" said="" serve=""
turncount > /dev/null 2>&1
i=0; while { kill -0 "$p1" || kill -0 "$p2"; } 2> /dev/null && [ $i -lt 50 ]; do command sleep 0.1; i=$((i + 1)); done # sleep: a bounded wait, so a card left waiting fails the case, not hangs it
for p in "$p1" "$p2"; do if kill -0 "$p" 2> /dev/null; then echo "alive $p"; kill -TERM $(tree "$p") 2> /dev/null; fi; done
echo "c2-2 $([ -e "$CARDS/c2-2.capheld" ] && echo held || echo free) $([ -e "$CARDS/c2-2.live" ] && echo live || echo nolive)"
EOF
)"
  grep -qx 'live land true waiting for room under the card cap' "$T/$CASE/run.out" \
    || fail "caphold c1-1 1 <worktree> land, waiting: no live record of its land step brought up to date, so health and the loop's stuck check saw a card that says nothing: $(cat "$T/$CASE/run.out")"
  grep -qx 'refreshed true' "$T/$CASE/run.out" \
    || fail "caphold c1-1 1 <worktree> land, waiting with LIVE=0.2, its live record made old: the wait wrote the record once and never again, so it went stale while the card waited: $(cat "$T/$CASE/run.out")"
  grep -qx 'ended c1-1' "$T/$CASE/run.out" && ! grep -q 'ended c2-2' "$T/$CASE/run.out" \
    || fail "halt on c1-1 (its last line: start, of land, waitFor cap) and c2-2 (the same, with slices filed): it spared c1-1 or ended c2-2: $(cat "$T/$CASE/run.out")"
  grep -qx 'c2-2 free nolive' "$T/$CASE/run.out" && ! grep -q '^alive' "$T/$CASE/run.out" \
    || fail "turncount with now=stopped, cap 1 and only c2-2 (spared, with slices filed) left: c2-2 still waited for room, or its live record of the wait stayed: $(cat "$T/$CASE/run.out")"
  recok "$ST/cards.jsonl" "caphold c1-1 1 and c2-2 2 <worktree> land"
}

# Bug it catches (E8 of a later review): a card that waited for room kept its landing turn, and a card that waits at
# its land step for that turn (landwait(), lib/claim.sh) counts against the cap, so at cap 1 neither went on. caphold()
# ends the turn before it waits; its sleep, a stand-in for the loop's turn, reads the turn and lets the card go.
t_capholdturn() {
  setup '[]'; mkdir -p "$T/$CASE/cards"
  # The engine's commands are a here-document, as in t_capholdnoloop.
  fx_in "$(cat <<'EOF'
LOOPCARD=1; echo '{}' > "$CARDS/c1-1.claim"; locked turntake c1-1 $$; echo "before: $(turnon || echo none)"
sleep() { [ "${FUNCNAME[1]}" = caphold ] || { command sleep "$@"; return; }; echo "held: $(turnon || echo none)"; rm -f "$CARDS/c1-1.capheld"; } # sleep: a stand-in for the loop's turn that lets the card go
caphold c1-1 1 "$CARDS/c1-1" land
EOF
)"
  [ "$RC" = 0 ] && grep -qx 'before: c1-1' "$T/$CASE/run.out" && grep -qx 'held: none' "$T/$CASE/run.out" \
    || fail "caphold c1-1 1 <worktree> land, c1-1 holding the landing turn: it kept the turn while it waited for room (rc $RC): $(cat "$T/$CASE/run.out")"
}

# Bug it catches (E7 of a later review): a card whose landing met another card's landing turn (TURNHELD) went back to
# wait for that turn, was then found passed, and was fitted again and ran its checks (settle()) at once, beside the
# cards the loop picked while its land step was off the cap. cardland() is called with land() answering TURNHELD and
# marking the card passed, caphold() and settle() stand-ins that say they ran: it waits for room before settle().
t_caplandturn() {
  setup '[]'; mkdir -p "$T/$CASE/cards"
  # The engine's commands are a here-document, as in t_capholdnoloop.
  fx_in "$(cat <<'EOF'
c=c1-1 n=1 wt=$CARDS/c1-1 br="" sprompt="" issue="" last="" ups="" left="" dec="" yesfrom="" ro="[]" cmsg="m" mates=() t=""
echo '{}' > "$wt.claim"
releasewait() { :; }; landwait() { :; }; redbrief() { :; }; began() { :; }; landextra() { :; }
locked() { [ "$1" = land ] || { "$@"; return; }; jq -c '.passed = true' "$wt.claim" > "$wt.claim.new" && mv -f "$wt.claim.new" "$wt.claim"; echo "$TURNHELD"; return 1; }
caphold() { echo "caphold $4"; }; settle() { echo settle; return 1; }
cardland; echo end
EOF
)"
  [ "$(tr '\n' ' ' < "$T/$CASE/run.out")" = "caphold land settle end " ] \
    || fail "cardland, land() answering TURNHELD and the card then passed: it did not wait for room before settle(): $(cat "$T/$CASE/run.out")"
}

# Bug it catches (E10 of a later review): the rebuild reset its worktree to main, then waited for room; a card that
# landed meanwhile was not in it, so the session started on the earlier commit. A caphold() stand-in lands a commit on
# main; the rebuild must start on it. rebasesetup and conflicted are port.test.sh's.
t_caprebaseheld() {
  rebasesetup 7
  echo 'git log -1 --format=%s > "$STUB/started-on"; printf "ONE\ntwo\n" > a.txt' > "$STUB/rebuild"
  conflicted 7 'caphold() { echo held > "$R/c.txt" && git -C "$R" add c.txt && git -C "$R" commit -qm "landed while it waited"; }; land1; go=end; landconflict; outcome'
  [ "$(cat "$STUB/started-on" 2>&1)" = "landed while it waited" ] || fail "landconflict on #7, a card landing on main while it waited for room: the rebuild started on $(cat "$STUB/started-on" 2>&1)"
}

# Bug it catches (E11 of a later review): `shut` read a card that waits for room after its landing failed as in its
# land step, and left it to land. Its last line is the land step's start marked waitFor: cap (caphold()); shut ends it.
t_capshut() {
  local p l out
  setup "[$(issue 7 2026-01-01)]"
  command sleep 600 & p=$! # sleep: a stand-in for the card's process, waiting for room
  l='{card:"c1-7",issue:7,time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}'
  jq -cn --argjson p "$p" --arg s "$(p_started "$p")" "$l"' | (. + {step:"worktree",pid:$p,started:$s}), (. + {step:"start",of:"land"}), (. + {step:"start",of:"land",waitFor:"cap"})' >> "$ST/cards.jsonl"
  out=$(loop shut 7 2>&1)
  ! kill -0 "$p" 2>/dev/null && grep -qF 'card c1-7 was open in its land step' <<<"$out" && [ -n "$(st 'select(.card == "c1-7" and .step == "blocked")')" ] \
    || fail "shut 7, its card's last line the land step's start with waitFor cap: it was left to land: $out $(st 'select(.card == "c1-7")')"
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; return 0
}

# Bug it catches (R246): halt (control stop) spared every card with a filed line, so a card past its filing that waits in
# seatwait() for a missing CLI (its live record names the CLI) ran on after the stop; a card with a filed line and no
# such record is still spared.
t_haltseat() {
  setup '[]'; mkdir -p "$T/$CASE/cards"
  fx_in "$(cat <<'EOF'
record c1-1 1 filed ok '{"followups":[]}'; record c2-2 2 filed ok '{"followups":[]}'
jq -cn '{step: "review", at: "2026-11-01T00:00:00Z", last: "2026-11-01T00:00:00Z", turns: 0, cli: "codex", action: "waiting for codex"}' > "$CARDS/c1-1.live"
command sleep 600 & p1=$!; command sleep 600 & p2=$! # sleep: stand-ins for the two cards' processes
printf '%s c1-1\n%s c2-2\n' "$p1" "$p2" | halt | sed -e "s/^$p1 /ended /" -e "s/^$p2 /ended /"
kill "$p1" "$p2" 2> /dev/null
EOF
)"
  grep -qx 'ended c1-1' "$T/$CASE/run.out" && ! grep -q 'ended c2-2' "$T/$CASE/run.out" \
    || fail "halt on c1-1 (a filed line, its live record naming codex: waiting in seatwait) and c2-2 (a filed line only): it spared c1-1 or ended c2-2: $(cat "$T/$CASE/run.out")"
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
