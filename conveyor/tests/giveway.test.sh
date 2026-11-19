#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the land turn goes to a card that is ready (a card that is not gives way).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The fixture of most cases: main's a.txt of 20 lines, and for each card <n> a worktree c<n>-<n> on main with its
# picked line, in the order given. No loop runs: each case calls the engine's own functions (gweng) on what it seeds.
gwcards() { # <n>...
  local n
  setup '[]'; seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in "$@"; do
    git -C "$R" worktree add -q "$CARDS/c$n-$n" -b "card-$n" main
    echo "{\"card\":\"c$n-$n\",\"issue\":$n,\"step\":\"picked\",\"time\":\"2026-01-01T00:00:0${n}Z\",\"tokens\":{\"claude\":0,\"codex\":0},\"result\":\"ok\",\"sha\":\"\",\"reason\":\"\",\"repo\":\"main\",\"title\":\"card $n\"}" >> "$ST/cards.jsonl"
  done
}
gwchg() { (cd "$CARDS/c$1-$1" && sed -i "$2" a.txt && git add -A); } # <n> <sed script>: card <n>'s change to a.txt, staged
gwclaim() { echo "{\"pid\":$$,\"paths\":[\"a.txt\"],$2}" > "$CARDS/c$1-$1.claim"; } # <n> <the rest of its claim>: alive, on a.txt
gwc() { jq -c "$2" "$CARDS/c$1-$1.claim"; } # <n> <jq filter>: card <n>'s claim
# <command...> in main's checkout, with the engine's files sourced as `conveyor.sh run` sources them, on this case's
# main and cards folder: land(), settle(), claim() and giveway() as the engine runs them, with what they call.
gweng() {
  # shellcheck source=/dev/null # the engine's own files, by the list commands/run.sh names
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$CARDS; . "$SRC/conveyor.sh" state-dir > /dev/null || exit 1
    for l in $(sed -n 's|^\. "\$HERE/lib/\([a-z]*\)\.sh" .*|\1|p' "$SRC/commands/run.sh"); do . "$HERE/lib/$l.sh" || exit 1; done
    names && cd "$R" && "$@" )
}
# A change of #8 that applies only on #7's (line 1 seven): #8 stacked on #7 (stackto()), its worktree on main plus #7's
# change and its own change after it, red there (stackred). On main alone #8 is not ready (ready()).
gwstack8() {
  gwchg 7 1s/.*/seven/
  (cd "$CARDS/c8-8" && sed -i 1s/.*/seven/ a.txt && git commit -qam "main plus #7's change" && sed -i 1s/.*/seven-eight/ a.txt && git add -A)
  jq -cn --arg b "$(git -C "$CARDS/c8-8" rev-parse HEAD)" '{on: "c7-7", base: $b, id: "x", restacks: 0}' > "$CARDS/c8-8.stack"
  echo '{"issue":8,"stackred":true}' > "$CARDS/c8-8.ready"
}
# Main gets b.txt, a file no card touches, as another card's landing in other files moves it.
gwmainb() { echo flag > "$R/b.txt" && git -C "$R" add b.txt && git -C "$R" commit -qm "main adds b.txt"; }
# watch() as a fix session of card <n> runs under it, its live record copied to $STUB/live once watch() has taken up
# the session's one output line: the look that read that line read the claim first. A real process stands for the
# session, as watch() looks at the claim only between the looks it takes while one runs: no call of a function
# shows what it writes there. The process polls the live record for that line (10 s at most), then ends.
gwlive() { # <n>
  # shellcheck disable=SC2329 # called by gweng
  gwwatch() {
    local wt=$CARDS/c$1-$1
    # shellcheck disable=SC2034 # read by watch(): a look every 0.05 s, and no stall in the case's time
    LIVE=0.05 STUCK=600
    echo '{"type":"system"}' > "$wt.out"
    ( WAIT_CEILING=10 wait_until "jq -e .last '$wt.live' >/dev/null 2>&1" 2>/dev/null; cp "$wt.live" "$STUB/live" ) &
    watch $! "$wt.out" "$wt.live" fix
  }
  gweng gwwatch "$1"
}

# Bug: a card that took its land turn kept it through a rebase, a new review, a fix and its tests, and every card that
# shares a file with it waited the whole time (7 ready cards waited 2.5 hours on one). #7 holds a.txt and needs a
# rebase while #8, its change clashing with #7's on line 8, waits: #7 gives way (its claim holds nothing, counted,
# naming #8 among those it gave way for), #8 then claims a.txt, and #7's claim and the Board name #8.
t_giveway() {
  gwcards 7 8; gwchg 7 8s/.*/seven-8/; gwchg 8 '1s/.*/eight/;8s/.*/eight-8/'
  gwclaim 7 '"held":true,"gave":0'; gwclaim 8 '"held":false,"passed":false'
  gweng giveway c7-7 "$CARDS/c7-7" && [ "$(gwc 7 '[.held, .away, .gave, .for]')" = '[false,true,1,["c8-8"]]' ] \
    || fail "#7 did not give way for its rebase to the waiting #8, counted once: $(cat "$CARDS/c7-7.claim")"
  w=$(gweng claim c8-8 "$CARDS/c8-8" $$) && [ -z "$w" ] && [ "$(gwc 8 .held)" = true ] || fail "#8 did not claim a.txt once #7 gave way: $w $(cat "$CARDS/c8-8.claim")"
  [ "$(gwc 7 '[.held, .away, .gave, .to]')" = '[false,true,1,8]' ] || fail "#7's claim does not name #8, which took its turn: $(cat "$CARDS/c7-7.claim")"
  out=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq -c '.belt[] | select(.issue == 7) | .gaveWay' <<<"$out" 2>/dev/null)" = 8 ] || fail "the snapshot does not say #7 gave way to #8: $(jq -c .belt <<<"$out" 2>&1 | head -c 2000)"
}

# Bug: a card gave way only to a card already waiting when it began its rebase, so one that came to land during the
# rebase waited the whole session. #7 gives way with no card waiting; #8 comes to its claim after that, claims a.txt
# at once, and #7 names it.
t_givewaylate() {
  gwcards 7 8; gwchg 7 8s/.*/seven-8/; gwchg 8 '1s/.*/eight/;8s/.*/eight-8/'
  gwclaim 7 '"held":true,"gave":0'
  gweng giveway c7-7 "$CARDS/c7-7" && [ "$(gwc 7 '[.held, .away, .gave, .for]')" = '[false,true,1,[]]' ] \
    || fail "#7 did not give way for its rebase with no card waiting: $(cat "$CARDS/c7-7.claim")"
  w=$(gweng claim c8-8 "$CARDS/c8-8" $$) && [ -z "$w" ] && [ "$(gwc 8 .held)" = true ] || fail "#8, come during #7's rebase, did not claim a.txt: $w"
  [ "$(gwc 7 '[.held, .away, .to]')" = '[false,true,8]' ] || fail "#7 does not name #8, which came after it gave way: $(cat "$CARDS/c7-7.claim")"
}

# Bug: a card that gave way could take its turn back before the card it gave way to looked again. #7 gave way to #8,
# which waits and has not looked again: #7, back at its claim, waits for #8 and stays away; once #8 holds a.txt, #7
# waits on it as on any holder; once #8 has landed (its change on main, its landed line, its worktree and claim gone,
# as land() and clean() leave them), #7 claims a.txt.
t_givewayback() {
  gwcards 7 8; gwchg 7 8s/.*/seven-8/; gwchg 8 '1s/.*/eight/;8s/.*/eight-8/'
  gwclaim 7 '"held":false,"away":true,"gave":1,"for":["c8-8"],"to":null'; gwclaim 8 '"held":false,"passed":false'
  w=$(gweng claim c7-7 "$CARDS/c7-7" $$) && [ "$(jq -r .on <<<"$w")" = c8-8 ] && [ "$(gwc 7 '[.held, .away, .back]')" = '[false,true,true]' ] \
    || fail "#7 took its turn back before #8, which it gave way to, looked again: $w $(cat "$CARDS/c7-7.claim")"
  w=$(gweng claim c8-8 "$CARDS/c8-8" $$) && [ -z "$w" ] && [ "$(gwc 8 .held)" = true ] || fail "#8 did not claim a.txt, #7 waiting for it: $w"
  w=$(gweng claim c7-7 "$CARDS/c7-7" $$) && [ "$(jq -r .on <<<"$w")" = c8-8 ] || fail "#7 did not wait on #8, which holds a.txt: $w"
  git -C "$CARDS/c8-8" diff --cached | git -C "$R" apply --index && git -C "$R" commit -qm "card 8" || fail "#8's change did not go onto main"
  echo "{\"card\":\"c8-8\",\"issue\":8,\"step\":\"landed\",\"sha\":\"$(git -C "$R" rev-parse main)\"}" >> "$ST/cards.jsonl"
  git -C "$R" worktree remove --force "$CARDS/c8-8" && rm -f "$CARDS"/c8-8.* || fail "#8's worktree could not be removed"
  w=$(gweng claim c7-7 "$CARDS/c7-7" $$) && [ -z "$w" ] && [ "$(gwc 7 '[.held, .away]')" = '[true,null]' ] \
    || fail "#7 did not claim a.txt once #8 landed: $w $(cat "$CARDS/c7-7.claim")"
}

# The cases below run one card through the real loop (loop run): what they protect is card()'s order of calls on its
# land step (fit the card onto main as it is now, claim its files again, run its checks again, block or land), and only
# card() makes those calls; a direct call of settle(), checks() or land() passes with card() skipping one. One card
# only, with the stub sessions, so no case waits on a second card.
# #7 (issue 7, every review GO) changes a.txt's last line to seven; its check $STUB/both-check.sh is <check>. With
# $STUB/broken-build, its build also leaves a file `broken` that fails its tests until its test-fix session removes it.
gwone() { # <check>
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2 3 4 5; do echo "$GO" > "$STUB/review.$i"; done
  seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  printf '%s\n' "$1" > "$STUB/both-check.sh"; tune --arg a "$STUB/both-check.sh" '.checks = [$a]'
  echo 'if grep -q "^# The changed tests fail" "$STUB/brief"; then rm -f broken; else sed -i 20s/.*/seven/ a.txt; [ ! -e "$STUB/broken-build" ] || : > broken; fi' > "$STUB/build"
  echo '[ ! -e broken ] || { echo "FAIL broken.test"; exit 1; }' >> "$STUB/test-cmd"
}
# Nothing of #7 landed: it is blocked by its check, which printed <failure>, and main does not have its line.
gwblocked() { # <failure> <what moved main>
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = "a product check failed; nothing landed." ] \
    && st 'select(.issue == 7 and .step == "blocked") | .tail' | grep -q "$1" \
    || fail "#7, fitted onto main after $2, was not checked again there: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ -z "$(st 'select(.step == "landed") | .issue')" ] && ! grep -qx seven "$R/a.txt" || fail "#7 landed a combination its checks never passed ($2): $(cat "$R/a.txt")"
}
# Bug: a card that gave way ran its checks and tests on a main without the card that landed meanwhile; fitted onto
# that card's main, it landed with no second run, a combination that never passed them. #7's tests fail and it gives
# way for their fix; during its tests after the fix (its third run, holding nothing), #8's change to the first line
# lands. A check forbids it beside #7's last line.
t_givewaycheck() {
  gwone '! { [ "$(head -n 1 a.txt)" = eight ] && [ "$(tail -n 1 a.txt)" = seven ]; } || { echo "eight and seven together"; exit 1; }'
  : > "$STUB/broken-build"
  { echo 'case $PWD in *-7) n=$(($(cat "$STUB/runs7" 2>/dev/null || echo 0) + 1)); echo $n > "$STUB/runs7"'
    echo '  [ $n != 3 ] || { cp "$PWD.claim" "$STUB/awayclaim"; sed -i 1s/.*/eight/ "$R/a.txt"; git -C "$R" commit -qam "card 8"; } ;; esac'; cat "$STUB/test-cmd"; } > "$STUB/test-cmd.new" \
    && mv "$STUB/test-cmd.new" "$STUB/test-cmd"
  loop run >/dev/null 2>&1
  [ "$(jq -c '[.held, .away]' "$STUB/awayclaim" 2>/dev/null)" = '[false,true]' ] || fail "#7 had not given way when main moved: $(cat "$STUB/awayclaim" 2>/dev/null)"
  gwblocked 'eight and seven together' "#8 landed while #7 was away"
}
# A card that never gave way: main gets b.txt (a file #7 does not hold, so no card waits) at the moment $STUB/bmove
# names: during #7's tests (test) or between its tests and its landing (land, at the limit reading land asks for). A
# check forbids b.txt beside #7's line: it passes on the main #7's tests ran on, runs again on main with b.txt, and
# blocks #7 there.
heldmove() { # <test|land>
  gwone '! { [ -e b.txt ] && [ "$(tail -n 1 a.txt)" = seven ]; } || { echo "b.txt and seven together"; exit 1; }'
  echo "$1" > "$STUB/bmove"
  printf '%s\n' 'echo flag > "$R/b.txt" && git -C "$R" add b.txt && git -C "$R" commit -qm "main adds b.txt" && rm -f "$STUB/bmove"' > "$STUB/addb"
  echo '[ "$(cat "$STUB/bmove" 2>/dev/null)" != test ] || . "$STUB/addb"; : > "$STUB/tested"' >> "$STUB/test-cmd"
  CONVEYOR_LIMIT_CMD='[ ! -e "$STUB/tested" ] || [ "$(cat "$STUB/bmove" 2>/dev/null)" != land ] || . "$STUB/addb"' loop run >/dev/null 2>&1
  [ ! -e "$STUB/bmove" ] || fail "main never got b.txt ($1): $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  gwblocked 'b.txt and seven together' "main moved ($1)"
}
# Bug: main moved during the tests of a card that held its files throughout, and it landed onto that unchecked.
t_heldtestmove() { heldmove test; }
# Bug: main moved after a card's last checks and tests, before it took the landing lock, and it landed onto that.
t_heldlandmove() { heldmove land; }

# The owner (2026-11-13): a change that passed its tests and still applies to a main that moved is not tested again.
# #7's tests pass (tested()) and main gets b.txt, which #7 does not touch, during them (test) or after them (land):
# settle() fits #7 onto that main with no session and no second review (exit 0, not 2), its tests stand there
# (testedhere(): card() runs none; readysince(): it is ready), and land() lands it there.
# It catches a card that runs its whole test run again each time main moves under it: with 10 to 20 minute runs and
# several landings an hour, it holds its files run after run while finished cards wait on it.
heldpass() { # <test|land>
  local rc out
  gwcards 7; gwchg 7 1s/.*/seven/; gwclaim 7 '"held":true,"gave":0'; echo '{"issue":7}' > "$CARDS/c7-7.ready"
  [ "$1" = land ] || gwmainb || fail "main did not move"
  gweng tested "$CARDS/c7-7"
  [ "$1" != land ] || gwmainb || fail "main did not move"
  gweng settle c7-7 7 "$CARDS/c7-7" '' land '{}'; rc=$?
  [ $rc = 0 ] && [ "$(git -C "$CARDS/c7-7" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] \
    || fail "#7 was not fitted onto the main that moved ($1) with no review again: exit $rc"
  gweng testedhere "$CARDS/c7-7" && gweng readysince "$CARDS/c7-7" >/dev/null \
    || fail "#7's tests do not stand on the main that moved ($1) in a file it does not touch: $(cat "$CARDS/c7-7.ready")"
  out=$(gweng land c7-7 7 "$CARDS/c7-7" "card 7") || fail "#7 did not land on the main that moved ($1): $out"
  [ "$(git -C "$R" log -1 --format=%s main~1)" = "main adds b.txt" ] && [ "$(head -n 1 "$R/a.txt")" = seven ] && [ "$(st 'select(.step == "landed") | .issue')" = 7 ] \
    || fail "#7 did not land on the main that moved ($1): $(git -C "$R" log --format=%s -3)"
}
# Main moved during the card's tests.
t_heldtestpass() { heldpass test; }
# Main moved after the card's tests ended, before its landing.
t_heldlandpass() { heldpass land; }

# No card is passed forever: #7, whose claim has given way 3 times already, keeps its turn through its rebase (as
# before give-ways) while #8 waits on it.
t_givewaykeep() {
  gwcards 7 8; gwchg 7 8s/.*/seven-8/; gwchg 8 '1s/.*/eight/;8s/.*/eight-8/'
  gwclaim 7 '"held":true,"gave":3'; gwclaim 8 '"held":false,"passed":false'
  ! gweng giveway c7-7 "$CARDS/c7-7" && [ "$(gwc 7 '[.held, .away, .gave]')" = '[true,null,3]' ] \
    || fail "#7, passed 3 times, did not keep its claim through its rebase: $(cat "$CARDS/c7-7.claim")"
  w=$(gweng claim c8-8 "$CARDS/c8-8" $$) && [ "$(jq -r .on <<<"$w")" = c7-7 ] && [ "$(gwc 8 .held)" = false ] \
    || fail "#8 did not wait on #7, which kept its turn: $w $(cat "$CARDS/c8-8.claim")"
}

# Bug: a card ready to land waited on a holder through the fix of the holder's failed tests (an hour of fix, review and
# tests). The owner: "why are other cards waiting for it? can't they go in front". #7 holds a.txt and its tests fail
# while #8, stacked on it and red there (gwstack8), waits: #7 gives way for the fix (fixing), #8 goes past it (on main
# alone it is not ready: only a give-way for a fix lets a stacked card go on), and #7's claim, its live record
# (watch()) and the Board (the snapshot's gaveWay and gaveWayFixing) name #8.
t_givewayfix() {
  gwcards 7 8; gwstack8; gwclaim 7 '"held":true,"gave":0'; gwclaim 8 '"held":false,"passed":false'
  gweng giveway c7-7 "$CARDS/c7-7" fixing && [ "$(gwc 7 '[.held, .away, .gave, .for, .fixing]')" = '[false,true,1,["c8-8"],true]' ] \
    || fail "#7 did not give way to #8 for the fix of its failed tests: $(cat "$CARDS/c7-7.claim")"
  w=$(gweng claim c8-8 "$CARDS/c8-8" $$) && [ -z "$w" ] && [ "$(gwc 8 .held)" = true ] \
    || fail "#8, stacked on #7 and red there, waited on #7 away for the fix of its tests: $w $(cat "$CARDS/c8-8.claim")"
  [ "$(gwc 7 .to)" = 8 ] || fail "#7's claim does not name #8, which went in front: $(cat "$CARDS/c7-7.claim")"
  gwlive 7; [ "$(jq -c '[.step, .gaveWay]' "$STUB/live" 2>/dev/null)" = '["fix",8]' ] || fail "#7's live record does not name #8: $(cat "$STUB/live" 2>/dev/null)"
  out=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq -c '.belt[] | select(.issue == 7) | [.gaveWay, .gaveWayFixing]' <<<"$out" 2>/dev/null)" = '[8,true]' ] \
    || fail "the snapshot does not say #7 gave way to #8 while fixing: $(jq -c .belt <<<"$out" 2>&1 | head -c 2000)"
}

# With no card waiting, the fix of failed tests goes as it always did: #7 gives way for it, but no card takes its
# turn, and its claim, its live record and the Board name none.
t_givewayfixalone() {
  gwcards 7; gwchg 7 1s/.*/seven/; gwclaim 7 '"held":true,"gave":0'
  gweng giveway c7-7 "$CARDS/c7-7" fixing && [ "$(gwc 7 '[.away, .fixing, .for, .to]')" = '[true,true,[],null]' ] \
    || fail "#7's claim names a card for the fix of its failed tests, with none waiting: $(cat "$CARDS/c7-7.claim")"
  gwlive 7; [ "$(jq -c '[.step, .gaveWay]' "$STUB/live" 2>/dev/null)" = '["fix",null]' ] || fail "#7's live record names a card that went in front: $(cat "$STUB/live" 2>/dev/null)"
  out=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq -c '.belt[] | select(.issue == 7) | [.gaveWay, .gaveWayFixing]' <<<"$out" 2>/dev/null)" = '[null,false]' ] \
    || fail "the snapshot says #7 gave way to a card: $(jq -c .belt <<<"$out" 2>&1 | head -c 2000)"
}

# Issue 428, through the real loop as gwone() says why (card()'s calls on its main-moved path): #7's first tests fail
# and main moves (b.txt) during them, so #7 is fitted onto main (settle()) and what failed runs again there before any
# fix round; that run's claim is kept ($STUB/fitclaim). Main's pre-commit hook, which land() runs just before it lands,
# keeps the claim #7 lands on ($STUB/landclaim). Every run of #7 on the moved main <passes|fails>; one that fails is
# fixed, and #7 lands.
gwmoved() { # <passes|fails>
  local out
  gwone :; [ "$1" = passes ] || : > "$STUB/broken-build"
  { echo 'case $PWD in *-7) if [ ! -e b.txt ]; then [ -e "$R/b.txt" ] || { echo b > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qnm "main moves"; }'
    echo '  echo "FAIL broken.test"; exit 1; fi; [ -e "$STUB/fitclaim" ] || cp "$PWD.claim" "$STUB/fitclaim" ;; esac'; cat "$STUB/test-cmd"; } > "$STUB/test-cmd.new" \
    && mv "$STUB/test-cmd.new" "$STUB/test-cmd"
  printf '#!/bin/sh\nfor c in "%s"/*-7.claim; do [ ! -e "$c" ] || cp "$c" "%s/landclaim"; done\n' "$T/$CASE/cards" "$STUB" > "$R/.git/hooks/pre-commit"
  chmod +x "$R/.git/hooks/pre-commit"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  grep -q "main moved since its commit" <<<"$out" || fail "#7 did not take the main-moved path: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] && [ "$(tail -n 1 "$R/a.txt")" = seven ] && [ -e "$R/b.txt" ] \
    || fail "#7 did not land on the moved main ($1 there): $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}
# Bug it catches: #7 kept its claim through its run on the moved main, so #8, stacked on it, waited until the run ended.
# card() gives way for that run as for a fix round (fixing), and claim() lets a stacked card past such a claim
# (t_givewayfix). Here that run fails, and goes to the fix round.
t_givewaymoved() {
  gwmoved fails
  [ "$(jq -c '[.held, .away, .fixing]' "$STUB/fitclaim" 2>/dev/null)" = '[false,true,true]' ] \
    || fail "#7 held its claim through its tests on the moved main: $(cat "$STUB/fitclaim" 2>/dev/null)"
}
# Bug it catches: #7, given way for its run on the moved main, which passes, landed on that claim (held false), as
# nothing claimed its files again: the land step's claim again (settle()) holds a.txt when land() commits.
t_givewaymovedpass() {
  gwmoved passes
  [ "$(jq -c '[.held, .away]' "$STUB/fitclaim" 2>/dev/null)" = '[false,true]' ] || fail "#7 had not given way for its run on the moved main: $(cat "$STUB/fitclaim" 2>/dev/null)"
  [ "$(jq -c .held "$STUB/landclaim" 2>/dev/null)" = true ] || fail "#7 landed without claiming its files again: $(cat "$STUB/landclaim" 2>/dev/null)"
}

# Bug: a ready card waited behind an older waiting card that was not ready, which itself waited on a card away (gave
# way), so the ready card did not land meanwhile. Picked in order #7, #8, #9, all on a.txt: #7 is away being fitted,
# #8's change no longer applies to main and #8 waits; #9's applies, and claims a.txt at once. Were #8 ready, #9 would
# wait for it, the older one, as before.
t_givewaypast() {
  setup '[]'; seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8 9; do
    git -C "$R" worktree add -q "$CARDS/c$n-$n" -b "card-$n" main
    echo "{\"card\":\"c$n-$n\",\"issue\":$n,\"step\":\"picked\"}" >> "$ST/cards.jsonl"
  done
  sed -i 1s/1/seven/ "$CARDS/c7-7/a.txt"; sed -i 1s/1/eight/ "$CARDS/c8-8/a.txt"; sed -i 20s/20/nine/ "$CARDS/c9-9/a.txt"
  for n in 7 8 9; do git -C "$CARDS/c$n-$n" add -A; done
  sed -i 1s/1/main/ "$R/a.txt"; git -C "$R" commit -qam "main changes the first line" # #8's change no longer applies
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":false,\"away\":true,\"gave\":1,\"for\":[],\"to\":null}" > "$CARDS/c7-7.claim"
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":false,\"passed\":false}" > "$CARDS/c8-8.claim"
  # claim() and ready() as the engine has them, and what they call, run from main's checkout.
  eval "$(sed -n '/^claim() {/,/^}/p; /^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p; /^testedhere() {/p; /^readysince() {/,/^}/p' "$SRC/lib/claim.sh")"
  # The card records are read through the state helper (state.py), as the engine reads them.
  eval "$(sed -n '/^declare -A ASKED_K/p; /^stdb() {/,/^}/p' "$SRC/lib/records.sh")"
  # shellcheck disable=SC2034 # read by stdb(), for the folder state.py is in
  local HERE=$SRC
  ctl() { cat "$ST/control.json"; }
  w=$(cd "$R" && STATE=$ST/cards.jsonl BRANCH=main claim c9-9 "$CARDS/c9-9" $$) || fail "claim failed"
  [ -z "$w" ] && [ "$(jq -c .held "$CARDS/c9-9.claim")" = true ] \
    || fail "#9, ready, waited behind #8, which is not ready: $w $(cat "$CARDS/c9-9.claim")"
  # #8 brought onto main (ready): #9 waits for it, the older card.
  git -C "$CARDS/c8-8" reset -q --hard main; sed -i 2s/2/eight/ "$CARDS/c8-8/a.txt"; git -C "$CARDS/c8-8" add -A
  w=$(cd "$R" && STATE=$ST/cards.jsonl BRANCH=main claim c9-9 "$CARDS/c9-9" $$) || fail "claim failed"
  [ "$(jq -r .on <<<"$w")" = c8-8 ] || fail "#9 did not wait for #8, older and ready: $w"
}

# Stacking is bounded (stackto()): a card stacked on a holder whose change kept changing would be ported and reviewed
# again each time. #8 waits on #7: it is stacked onto main plus #7's kept change; with that change the same, not
# again; changed, once more (restacks 1); changed again, not: #8 waits, as before stacking. Bug it catches too: a card
# whose issue says `Depends on: #7` was stacked; it only waits. Bug it catches too (a ready card lands first, the
# owner, 2026-11-18): #8 was stacked on #7 while #7's tests had not passed, so #8, tested on #7's change, waited for
# them; it waits running its own on main instead, and goes past #7 once they pass (claim()).
t_stackonce() {
  setup '[]'; seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"; git -C "$R" worktree add -q "$CARDS/c7-7" -b card-7 main
  # stackto() as the engine has it, and what it calls; the pack's landBatch at its default. #7's tests passed
  # (readysince(), which t_readyclaim runs) but where named.
  eval "$(sed -n '/^stackto() {/,/^}/p; /^merge3() {/,/^}/p' "$SRC/lib/claim.sh")"
  # shellcheck disable=SC2034 # read by DEPS
  local MAX_DEPTH=2 BRANCH=main b
  eval "$(sed -n '/^DEPS=/,/unique;'"'"'$/p' "$SRC/lib/prompts.sh")"
  packget() { printf -v "$2" 8; }
  readysince() { [ ! -e "$STUB/untested" ] && echo 1; }
  st8() { (cd "$R" && stackto c8-8 "$CARDS/c8-8" '{"on":"c7-7","paths":["a.txt"]}' "${1:-{\}}"); } # [#8's issue json]
  keep7() { sed -i "$1s/.*/seven/" "$CARDS/c7-7/a.txt"; git -C "$CARDS/c7-7" diff > "$CARDS/c7-7.cpatch"; } # <a line #7 changes too>
  keep7 1
  : > "$STUB/untested"
  ! st8 >/dev/null && [ ! -e "$CARDS/c8-8.stack" ] || fail "#8 was stacked on #7, whose tests have not passed"
  rm -f "$STUB/untested"
  b=$(st8) && [ "$(git -C "$R" show "$b:a.txt" | head -n 1)" = seven ] && [ "$(git -C "$R" rev-parse "$b^")" = "$(git -C "$R" rev-parse main)" ] \
    && [ "$(jq -c '[.on, .restacks, .base]' "$CARDS/c8-8.stack")" = "[\"c7-7\",0,\"$b\"]" ] || fail "#8 was not stacked onto main plus #7's change: $b $(cat "$CARDS/c8-8.stack")"
  ! st8 >/dev/null || fail "#8 was stacked again on #7's change as it was"
  keep7 2
  b=$(st8) && [ "$(git -C "$R" show "$b:a.txt" | sed -n 2p)" = seven ] && [ "$(jq -c .restacks "$CARDS/c8-8.stack")" = 1 ] \
    || fail "#8 was not stacked once more on #7's changed change: $b $(cat "$CARDS/c8-8.stack")"
  keep7 3
  ! st8 >/dev/null || fail "#8 was stacked a third time: it should wait"
  rm -f "$CARDS/c8-8.stack"
  ! st8 '{"body":"Fix it.\nDepends on: #7"}' >/dev/null && [ ! -e "$CARDS/c8-8.stack" ] || fail "#8, whose issue depends on #7, was stacked on it"
}

# A card stacked on a holder lands after it. Bug: the holder, claiming again, waited on the card stacked on it, an
# older waiting card whose change fits main, and the stacked card then left its stack to land first (a session and a
# review for nothing). #8, picked first, is stacked on #7 (its worktree on main plus #7's change, its own change on line
# 10, no kept change, so it overlaps #7): #7's claim does not wait on it; on another base, #8 is an older card that
# waits, ready, and #7 waits for it, as before. #7, having given way 3 times, gives way once more for a test fix while
# #8 is stacked on it, so #8 goes on; with no card stacked on it, it keeps its claim.
t_stackfirst() {
  setup '[]'; seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 8 7; do
    git -C "$R" worktree add -q "$CARDS/c$n-$n" -b "card-$n" main
    echo "{\"card\":\"c$n-$n\",\"issue\":$n,\"step\":\"picked\"}" >> "$ST/cards.jsonl"
  done
  sed -i 1s/1/seven/ "$CARDS/c7-7/a.txt"; git -C "$CARDS/c7-7" add -A
  sed -i 1s/1/seven/ "$CARDS/c8-8/a.txt"; git -C "$CARDS/c8-8" commit -qam "main plus #7's change"
  sed -i 10s/10/eight/ "$CARDS/c8-8/a.txt"; git -C "$CARDS/c8-8" add -A
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":false,\"passed\":false}" > "$CARDS/c8-8.claim"
  jq -cn --arg b "$(git -C "$CARDS/c8-8" rev-parse HEAD)" '{on: "c7-7", base: $b, id: "x", restacks: 0}' > "$CARDS/c8-8.stack"
  # claim(), giveway() and what they call, as the engine has them, run from main's checkout.
  eval "$(sed -n '/^claim() {/,/^}/p; /^giveway() {/,/^}/p; /^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p; /^testedhere() {/p; /^readysince() {/,/^}/p' "$SRC/lib/claim.sh")"
  eval "$(sed -n '/^declare -A ASKED_K/p; /^stdb() {/,/^}/p' "$SRC/lib/records.sh")"
  # shellcheck disable=SC2034 # read by stdb(), for the folder state.py is in
  local HERE=$SRC GIVEWAY=3
  ctl() { cat "$ST/control.json"; }
  w=$(cd "$R" && STATE=$ST/cards.jsonl BRANCH=main claim c7-7 "$CARDS/c7-7" $$) || fail "claim failed"
  [ -z "$w" ] && [ "$(jq -c .held "$CARDS/c7-7.claim")" = true ] || fail "#7 waited on #8, stacked on it: $w $(cat "$CARDS/c7-7.claim")"
  jq -c '.base = "another"' "$CARDS/c8-8.stack" > "$CARDS/c8-8.stack.new" && mv "$CARDS/c8-8.stack.new" "$CARDS/c8-8.stack"
  w=$(cd "$R" && STATE=$ST/cards.jsonl BRANCH=main claim c7-7 "$CARDS/c7-7" $$) || fail "claim failed"
  [ "$(jq -r .on <<<"$w")" = c8-8 ] || fail "#7 did not wait on #8, older and ready, no longer on its stack: $w"
  jq -c '.held = true | .gave = 3' "$CARDS/c7-7.claim" > "$CARDS/c7-7.claim.new" && mv "$CARDS/c7-7.claim.new" "$CARDS/c7-7.claim"
  (giveway c7-7 "$CARDS/c7-7" fixing) && [ "$(jq -c '[.held, .away, .fixing, .gave]' "$CARDS/c7-7.claim")" = '[false,true,true,4]' ] \
    || fail "#7, given way 3 times, did not give way for its test fix with #8 stacked on it: $(cat "$CARDS/c7-7.claim")"
  jq -c '.held = true | .gave = 3' "$CARDS/c7-7.claim" > "$CARDS/c7-7.claim.new" && mv "$CARDS/c7-7.claim.new" "$CARDS/c7-7.claim"; rm -f "$CARDS/c8-8.stack"
  ! (giveway c7-7 "$CARDS/c7-7" fixing) && [ "$(jq -c .held "$CARDS/c7-7.claim")" = true ] || fail "#7, given way 3 times, gave way with no card stacked on it"
}

# A stacked card that passed its tests goes on when its holder goes to any fix round (the owner, 2026-11-17), not only
# a test fix. Bug: #8, stacked on #7 (its change on line 2, next to #7's, so it fits only on #7's) and tested there,
# waited at its claim while #7 was away for the fix of its review findings. #7, given way 3 times, gives way for that
# round with #8 stacked on it (fix); away already (given way to be reviewed again), it is marked for the round. #8,
# tested, waits on #7 away for no fix round, goes on once #7 is in one, and waits on still while not yet tested.
t_stackfixround() {
  setup '[]'; seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8; do
    git -C "$R" worktree add -q "$CARDS/c$n-$n" -b "card-$n" main
    echo "{\"card\":\"c$n-$n\",\"issue\":$n,\"step\":\"picked\"}" >> "$ST/cards.jsonl"
  done
  sed -i 1s/1/seven/ "$CARDS/c7-7/a.txt"; git -C "$CARDS/c7-7" add -A
  sed -i 1s/1/seven/ "$CARDS/c8-8/a.txt"; git -C "$CARDS/c8-8" commit -qam "main plus #7's change"
  sed -i 2s/2/eight/ "$CARDS/c8-8/a.txt"; git -C "$CARDS/c8-8" add -A
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true,\"gave\":3}" > "$CARDS/c7-7.claim"
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":false,\"passed\":false}" > "$CARDS/c8-8.claim"
  jq -cn --arg b "$(git -C "$CARDS/c8-8" rev-parse HEAD)" '{on: "c7-7", base: $b, id: "x", restacks: 0}' > "$CARDS/c8-8.stack"
  # claim(), giveway() and what they call, as the engine has them, run from main's checkout.
  eval "$(sed -n '/^claim() {/,/^}/p; /^giveway() {/,/^}/p; /^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p; /^tested() {/,/} # <worktree>$/p; /^testedhere() {/p; /^readysince() {/,/^}/p' "$SRC/lib/claim.sh")"
  eval "$(sed -n '/^declare -A ASKED_K/p; /^stdb() {/,/^}/p' "$SRC/lib/records.sh")"
  # shellcheck disable=SC2034 # read by stdb(), for the folder state.py is in
  local HERE=$SRC GIVEWAY=3
  ctl() { cat "$ST/control.json"; }
  cl8() { (cd "$R" && STATE=$ST/cards.jsonl BRANCH=main claim c8-8 "$CARDS/c8-8" $$); }
  (giveway c7-7 "$CARDS/c7-7" fix) && [ "$(jq -c '[.held, .away, .fix, .fixing, .gave]' "$CARDS/c7-7.claim")" = '[false,true,true,false,4]' ] \
    || fail "#7, given way 3 times, did not give way for its review fix round with #8 stacked on it: $(cat "$CARDS/c7-7.claim")"
  echo '{"issue":8}' > "$CARDS/c8-8.ready"; (cd "$R" && tested "$CARDS/c8-8")
  jq -c '.fix = false' "$CARDS/c7-7.claim" > "$CARDS/c7-7.claim.new" && mv "$CARDS/c7-7.claim.new" "$CARDS/c7-7.claim"
  w=$(cl8) && [ "$(jq -r .on <<<"$w")" = c7-7 ] || fail "#8 did not wait on #7, away for no fix round: $w"
  ! (giveway c7-7 "$CARDS/c7-7" fix) && [ "$(jq -c '[.away, .fix, .gave]' "$CARDS/c7-7.claim")" = '[true,true,4]' ] \
    || fail "#7, away already, was not marked for its review fix round: $(cat "$CARDS/c7-7.claim")"
  w=$(cl8) && [ -z "$w" ] || fail "#8, stacked on #7 and tested, waited on #7 in its review fix round: $w"
  rm -f "$CARDS/c8-8.ready"
  w=$(cl8) && [ "$(jq -r .on <<<"$w")" = c7-7 ] || fail "#8, stacked on #7 and not yet tested, did not wait on it: $w"
  # A test fix while away (its tests run holding nothing after a give-way) is marked too; there #8 goes on untested, as before.
  jq -c '.fix = false' "$CARDS/c7-7.claim" > "$CARDS/c7-7.claim.new" && mv "$CARDS/c7-7.claim.new" "$CARDS/c7-7.claim"
  ! (giveway c7-7 "$CARDS/c7-7" fixing) && [ "$(jq -c .fixing "$CARDS/c7-7.claim")" = true ] && w=$(cl8) && [ -z "$w" ] \
    || fail "#8 waited on #7, away already, in the fix of its failed tests: $w $(cat "$CARDS/c7-7.claim")"
}

# The two cases below run two cards through the real loop (loop run): a direct check of giveway(), claim() or land()
# shows each part, but only card() and settle() join them (a holder gives way before its rebase or fix session, and the
# other card claims, is tested and lands while that session runs), and only a run of both cards shows that join.
# The stubs meet at named pipes in $STUB (gwpipes). `hear <pipe>` waits for one line on it, 100 s at most, so a run
# where the engine never gets there fails what the case checks and does not hang; `listen <pipe>` opens it, and
# `heard` waits so, for a reader that must be open before the writer can come. `say <pipe>` gives the pipe its line
# and goes on at once: a process of its own waits for the reader, 100 s at most, as a writer left waiting holds the
# loop's output open. `tell <pipe>` writes with no wait, to a reader that listened first (with none, the line is lost).
# Main's pre-commit hook, which land() runs just before it lands, does <say|tell> landed8 when it lands #8.
# No stub polls a file.
gwpipes() { # <say|tell> <pipe>...
  local p
  for p in "${@:2}"; do mkfifo "$STUB/$p" || fail "the pipe $p could not be made"; done
  # say's writer closes the engine's lock (fd 8) and fd 9, which it must not hold while it waits.
  cat > "$STUB/pipes.sh" <<'EOF'
say() { ( timeout 100 bash -c 'echo go > "$1"' _ "$STUB/$1" ) > /dev/null 2>&1 < /dev/null 8>&- 9>&- & }
tell() { echo go 1<> "$STUB/$1"; }
hear() { local l; read -r -t 100 l <> "$STUB/$1"; }
listen() { exec {LISTEN}<> "$STUB/$1"; }
heard() { local l; read -r -t 100 l <&"$LISTEN"; }
EOF
  printf '#!/usr/bin/env bash\ncase $GIT_INDEX_FILE in *-8.index) STUB=%q; . "$STUB/pipes.sh"; %s landed8 ;; esac\n' "$STUB" "$1" > "$R/.git/hooks/pre-commit"
  chmod +x "$R/.git/hooks/pre-commit"
}
# Ends any writer still waiting (a run where its reader gave up): it opens each pipe and closes it.
gwfree() { local p; for p in "$@"; do : <> "$STUB/$p"; done; } # <pipe>...

# Bug it catches: a card took its land turn and kept it through its rebase session (card.sh: the give-way before the
# rebuild), so a card that shares its files and is ready waited the whole session. #7 changes a.txt's line 8 and
# appends seven; its first tests change main's last line, so its landing conflicts and it is rebuilt. #8 changes line 1
# and line 8 (it clashes with #7's change) and is built only once #7's rebase session has begun (go8). That session waits
# for #8's landing (landed8): #8 claims a.txt, is tested and lands during it; the session then appends seven on main as
# it was at the rebase, and #7 is fitted onto #8's main and lands. Main has both changes.
t_givewayrebase() {
  local out rc
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in $(seq 8); do echo "$GO" > "$STUB/review.$i"; done
  seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  # The rebase session listens on landed8 before it lets #8 be built: #8 cannot land before it listens (tell).
  gwpipes tell go8 landed8
  cat > "$STUB/build" <<'EOF'
. "$STUB/pipes.sh"
if grep -q '^# Landing conflict' "$STUB/brief" && [ "${PWD##*-}" = 7 ]; then
  listen landed8; say go8; ! heard || : > "$STUB/heard8"; cp "$PWD.claim" "$STUB/rebaseclaim"; echo seven >> a.txt
elif grep -q '^# Main moved' "$STUB/brief"; then sed -i '1s/.*/eight/;8s/.*/eight-8/' a.txt
else case $PWD in
  *-7) echo seven >> a.txt; sed -i 8s/.*/seven-8/ a.txt ;;
  *) hear go8; sed -i '1s/.*/eight/;8s/.*/eight-8/' a.txt ;;
esac; fi
EOF
  { echo 'case $PWD in *-7) [ -e "$STUB/moved" ] || { : > "$STUB/moved"; sed -i 20s/.*/twenty/ "$R/a.txt"; git -C "$R" commit -qnam "main changes the last line"; } ;; esac'
    cat "$STUB/test-cmd"; } > "$STUB/test-cmd.new" && mv "$STUB/test-cmd.new" "$STUB/test-cmd"
  out=$(loop run 2>&1); rc=$?; gwfree go8 landed8; [ $rc = 0 ] || fail "run exited $rc: $out"
  [ -e "$STUB/heard8" ] && [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] \
    || fail "#8 did not land during #7's rebase session, before #7: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(jq -c '[.held, .away, .to]' "$STUB/rebaseclaim" 2>/dev/null)" = '[false,true,8]' ] \
    || fail "#7 did not give way for its rebase, or does not name #8: $(cat "$STUB/rebaseclaim" 2>/dev/null)"
  [ "$(sed -n '1p;8p;20p;21p' "$R/a.txt" | tr '\n' ' ')" = "eight eight-8 twenty seven " ] && [ "$(wc -l < "$R/a.txt")" -eq 21 ] \
    || fail "main does not hold #8's change, main's own and #7's as rebuilt: $(cat "$R/a.txt")"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test rebase review test test landed " ] \
    || fail "steps of #7: $(st "select(.issue == 7) | .step" | tr '\n' ' ')"
}

# Bug it catches: a card stacked on another (stackto()) whose checks or tests failed there, on the other card's change,
# was sent to a fix of its own (claim(): stackred), or waited on that card through its fix (card(): the give-way for
# the fix of failed tests). #7 changes a.txt's first and last lines and adds `broken`, which fails the tests. #8,
# built once #7 holds a.txt (go8), appends eight, which does not apply with #7's last line: it waits on #7 and is stacked
# on it (the control record's order, #8 then #7, lets it be stacked on #7 before #7's tests pass), and its tests there
# fail on `broken` (red8). Only then do #7's first tests end, failing. #7's fix session waits for #8's landing
# (landed8): #8 is brought onto main alone, reviewed and tested there, and lands alone during it. The fix then removes
# `broken` and puts the last line back, and #7 lands on #8's main. The mark (settle(): stackred) is what keeps #8 from
# running its tests on #7's stack again: #7's tests wait up to 2 s on again8, which #8's tests say when a second run
# of them starts there (again8.seen; the run again of the failed cases within one run, <worktree>.first, is not one),
# so without the mark #8 runs them again before #7 gives way.
t_givewaystackred() {
  local out rc c7 c8
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; tune '.landBatch = 8'; for i in $(seq 10); do echo "$GO" > "$STUB/review.$i"; done
  jq -c '.order = [8, 7]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  # #7's first tests listen on red8 before they let #8 be built (tell); #8 can land before #7's fix session opens
  # landed8 (#7 gives way just before it), so the hook says it.
  gwpipes say go8 red8 landed8 again8
  cat > "$STUB/build" <<'EOF'
. "$STUB/pipes.sh"
if grep -q '^# The changed tests fail' "$STUB/brief"; then
  [ "${PWD##*-}" != 7 ] || { ! hear landed8 || : > "$STUB/heard8"; }; rm -f broken; sed -i 20s/.*/20/ a.txt
else case $PWD in
  *-7) sed -i '1s/.*/seven/;20s/.*/seven-20/' a.txt; : > broken ;;
  *) grep -q '^# Stacked\|^# Main moved' "$STUB/brief" || hear go8; echo eight >> a.txt ;;
esac; fi
EOF
  { echo 'case $PWD in *-7) [ -e "$STUB/said7" ] || { : > "$STUB/said7"; . "$STUB/pipes.sh"; exec {AG}<> "$STUB/again8"; listen red8; say go8; heard; read -r -t 2 l <&"$AG"; } ;;'
    echo '  *-8) [ ! -e broken ] || [ -e "$PWD.first" ] || { . "$STUB/pipes.sh"; if [ -e "$STUB/said8" ]; then : > "$STUB/again8.seen"; tell again8; else : > "$STUB/said8"; tell red8; fi; } ;; esac'
    cat "$STUB/test-cmd"; echo '[ ! -e broken ] || { echo "FAIL broken.test"; exit 1; }'; } > "$STUB/test-cmd.new" && mv "$STUB/test-cmd.new" "$STUB/test-cmd"
  out=$(loop run 2>&1); rc=$?; gwfree go8 red8 landed8 again8; [ $rc = 0 ] || fail "run exited $rc: $out"
  c7=$(st 'select(.issue == 7 and .step == "picked") | .card'); c8=$(st 'select(.issue == 8 and .step == "picked") | .card')
  grep -q "card $c8 is stacked on card $c7" <<<"$out" && grep -q "card $c8: its checks or tests failed on main with the change of card $c7" <<<"$out" \
    || fail "#8 was not stacked on #7, or its tests there did not fail on #7's change: $out"
  [ ! -e "$STUB/again8.seen" ] || fail "#8 was not marked stackred: it ran its tests again on #7's stack: $out"
  [ -e "$STUB/heard8" ] && [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] \
    || fail "#8 did not land during #7's fix session, before #7: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.issue == 8 and .step == "fix") | .reason' | cut -c1-14 | tr '\n' ,)" = "stacked on car,main moved sin," ] \
    && [ -z "$(st 'select(.issue == 8 and .step == "test" and .result == "fail")')" ] && [ "$(st 'select(.issue == 8 and .step == "landed") | .batch')" = null ] \
    || fail "#8 was not brought onto main alone after its stack, or was sent to a fix for #7's failure, or did not land alone: $(st 'select(.issue == 8) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 8 and $NOMARK) | .step" | tr '\n' ' ' | sed 's/.* fix //')" = "review test landed " ] \
    || fail "#8 was not reviewed and tested on main alone before it landed: $(st "select(.issue == 8) | .step" | tr '\n' ' ')"
  [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] && [ ! -e "$R/broken" ] || fail "main does not hold both changes, #7's as fixed: $(cat "$R/a.txt"; ls "$R")"
}
