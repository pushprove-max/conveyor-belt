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
# change and its own change after it, after its GO and untested there. On main alone #8 is not ready (ready()).
gwstack8() {
  gwchg 7 1s/.*/seven/
  (cd "$CARDS/c8-8" && sed -i 1s/.*/seven/ a.txt && git commit -qam "main plus #7's change" && sed -i 1s/.*/seven-eight/ a.txt && git add -A)
  jq -cn --arg b "$(git -C "$CARDS/c8-8" rev-parse HEAD)" '{on: "c7-7", base: $b, id: "x", restacks: 0}' > "$CARDS/c8-8.stack"
  echo '{"issue":8}' > "$CARDS/c8-8.ready"
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
  # What the snapshot's gaveWay is read from (aways(); t_givewayfix runs the whole snapshot on it).
  out=$(gweng aways) && [ "$out" = '{"c7-7":{"to":8,"fixing":false}}' ] || fail "the Board's view does not say #7 gave way to #8: $out"
}

# Bug (O188): claim() gave jq the list of the staged paths, and the other cards' claims, each as one argument
# (--argjson); over 128 KiB Linux refuses to start jq, so claim() failed and a card with a very large change could not
# claim its files. #8 stages a.txt and 2,000 files of 80-byte paths, and #7's claim holds a.txt and 2,000 other paths of
# 80 bytes (each over 160 KiB as JSON: the review found a large claim of another card unchecked): #8 waits on #7, which
# holds a.txt, then claims all 2,001 once #7 gives way, and #7's claim names it.
# gwbig7 <the rest of its claim>: #7's claim, alive, on a.txt and the 2,000 other paths.
gwbig7() {
  jq -cn --argjson p $$ --argjson r "{$1}" '{pid: $p, paths: (["a.txt"] + [range(1; 2001) | tostring | "held/f" + ("0" * (74 - length)) + .])} + $r' > "$CARDS/c7-7.claim" \
    && [ "$(wc -c < "$CARDS/c7-7.claim")" -gt 131072 ] || fail "#7's claim over 128 KiB was not made"
}
t_claimbig() {
  gwcards 7 8; gwchg 8 1s/.*/eight/
  (cd "$CARDS/c8-8" && mkdir big && for i in $(seq 2000); do : > "big/$(printf 'f%075d' "$i")"; done && git add -A) || fail "the large change could not be staged"
  gwbig7 '"held":true,"gave":0'
  w=$(gweng claim c8-8 "$CARDS/c8-8" $$) && [ "$(jq -r .on <<<"$w")" = c7-7 ] && [ "$(gwc 8 '[.held, (.paths | length)]')" = '[false,2001]' ] \
    || fail "#8, with 2,001 staged paths, did not wait on #7, whose claim of 2,001 paths holds a.txt: $w $(gwc 8 '[.held, (.paths | length)]')"
  gwbig7 '"held":false,"away":true,"gave":1,"for":[],"to":null'
  w=$(gweng claim c8-8 "$CARDS/c8-8" $$) && [ -z "$w" ] && [ "$(gwc 8 '[.held, (.paths | length)]')" = '[true,2001]' ] && [ "$(gwc 7 .to)" = 8 ] \
    || fail "#8, with 2,001 staged paths, did not claim them once #7 gave way, or #7's claim does not name it: $w $(cat "$CARDS/c7-7.claim")"
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

# Bug: a card that gave its files way to wait for main to change (giveway() red, from cardfailed() or mainredhold())
# never claims again during that wait, yet a card that was not ready (ready()) waited for it as for a holder: the
# main-red fix card, its change clashing with main, waited on it, and nothing freed either. #7 holds a.txt and gives
# way red; main then changes line 1, so #8's change (line 1 too) no longer applies: #8 still claims a.txt. Given way
# for another reason, #7 is still waited for. Bug: a card already away (given way for its review's fix, so no settle()
# since) that then waits for main kept its claim unmarked (giveway() red returned first), and #8 waited on it for good.
t_givewayred() {
  gwcards 7 8; gwchg 7 8s/.*/seven-8/; gwchg 8 1s/.*/eight/
  gwclaim 7 '"held":true,"gave":3'; gwclaim 8 '"held":false,"passed":false'
  gweng giveway c7-7 "$CARDS/c7-7" red && [ "$(gwc 7 '[.held, .away, .red]')" = '[false,true,true]' ] \
    || fail "#7 did not give way red to wait for main: $(cat "$CARDS/c7-7.claim")"
  sed -i 1s/.*/main/ "$R/a.txt" && git -C "$R" commit -qam "main changes the first line" || fail "main did not move"
  w=$(gweng claim c8-8 "$CARDS/c8-8" $$) && [ -z "$w" ] && [ "$(gwc 8 .held)" = true ] \
    || fail "#8, not ready, waited on #7, away to wait for main: $w $(cat "$CARDS/c8-8.claim")"
  gwclaim 7 '"held":false,"away":true,"gave":1,"for":[],"to":null'; gwclaim 8 '"held":false,"passed":false'
  w=$(gweng claim c8-8 "$CARDS/c8-8" $$) && [ "$(jq -r .on <<<"$w")" = c7-7 ] || fail "#8, not ready, did not wait on #7, away to be fitted: $w"
  ! gweng giveway c7-7 "$CARDS/c7-7" red && [ "$(gwc 7 '[.held, .away, .red]')" = '[false,true,true]' ] \
    || fail "#7, already away, was not marked red to wait for main: $(cat "$CARDS/c7-7.claim")"
  gwclaim 8 '"held":false,"passed":false'
  w=$(gweng claim c8-8 "$CARDS/c8-8" $$) && [ -z "$w" ] && [ "$(gwc 8 .held)" = true ] \
    || fail "#8, not ready, waited on #7, already away and then waiting for main: $w $(cat "$CARDS/c8-8.claim")"
}

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
  # shellcheck disable=SC2329 # called by gweng: both in one load of the engine's files
  gwstands() { testedhere "$1" && readysince "$1" >/dev/null; }
  gweng gwstands "$CARDS/c7-7" \
    || fail "#7's tests do not stand on the main that moved ($1) in a file it does not touch: $(cat "$CARDS/c7-7.ready")"
  out=$(gweng land c7-7 7 "$CARDS/c7-7" "card 7") || fail "#7 did not land on the main that moved ($1): $out"
  [ "$(git -C "$R" log -1 --format=%s main~1)" = "main adds b.txt" ] && [ "$(head -n 1 "$R/a.txt")" = seven ] && [ "$(st 'select(.step == "landed") | .issue')" = 7 ] \
    || fail "#7 did not land on the main that moved ($1): $(git -C "$R" log --format=%s -3)"
}
# Main moved during the card's tests.
t_heldtestpass() { heldpass test; }
# Main moved after the card's tests ended, before its landing.
t_heldlandpass() { heldpass land; }

# Bug (R77): #8, stacked on #7 (its worktree on main plus #7's change), passed its tests there; #7 then failed its own
# and holds nothing, so settle() fits #8 onto main alone, where its patch (line 10) applies as it is. Its pass on the
# stack's base still counted as its own there (testedhere()), so card() ran no test and #8 landed untested on main
# alone. Its tests now run again before it lands.
t_stackbasepass() {
  local rc
  gwcards 7 8; gwchg 7 1s/.*/seven/
  (cd "$CARDS/c8-8" && sed -i 1s/.*/seven/ a.txt && git commit -qam "main plus #7's change" && sed -i 10s/.*/eight/ a.txt && git add -A) || fail "#8's change on the stack's base"
  jq -cn --arg b "$(git -C "$CARDS/c8-8" rev-parse HEAD)" '{on: "c7-7", base: $b, id: "x", restacks: 0}' > "$CARDS/c8-8.stack"
  echo '{"issue":8}' > "$CARDS/c8-8.ready"; gweng tested "$CARDS/c8-8"
  gweng testedhere "$CARDS/c8-8" || fail "#8's pass on the stack's base was not recorded: $(cat "$CARDS/c8-8.ready")"
  gweng settle c8-8 8 "$CARDS/c8-8" '' land '{}'; rc=$?
  [ $rc = 0 ] && [ "$(git -C "$CARDS/c8-8" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] && [ "$(git -C "$CARDS/c8-8" show :a.txt | sed -n '1p;10p' | paste -sd' ')" = '1 eight' ] \
    || fail "settle() did not fit #8 alone onto main: exit $rc, $(git -C "$CARDS/c8-8" show :a.txt | sed -n '1p;10p' | paste -sd' ')"
  ! gweng testedhere "$CARDS/c8-8" || fail "#8, moved off its stack's base onto main, kept the pass it had with #7's change, so it lands untested: $(cat "$CARDS/c8-8.ready")"
}

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
# while #8, stacked on it and untested there (gwstack8), waits: #7 gives way for the fix (fixing), #8 goes past it (on main
# alone it is not ready: only a give-way for a fix lets a stacked card go on), and #7's claim, its live record
# (watch()) and the Board (the snapshot's gaveWay and gaveWayFixing) name #8.
t_givewayfix() {
  gwcards 7 8; gwstack8; gwclaim 7 '"held":true,"gave":0'; gwclaim 8 '"held":false,"passed":false'
  gweng giveway c7-7 "$CARDS/c7-7" fixing && [ "$(gwc 7 '[.held, .away, .gave, .for, .fixing]')" = '[false,true,1,["c8-8"],true]' ] \
    || fail "#7 did not give way to #8 for the fix of its failed tests: $(cat "$CARDS/c7-7.claim")"
  w=$(gweng claim c8-8 "$CARDS/c8-8" $$) && [ -z "$w" ] && [ "$(gwc 8 .held)" = true ] \
    || fail "#8, stacked on #7 and untested there, waited on #7 away for the fix of its tests: $w $(cat "$CARDS/c8-8.claim")"
  [ "$(gwc 7 .to)" = 8 ] || fail "#7's claim does not name #8, which went in front: $(cat "$CARDS/c7-7.claim")"
  gwlive 7; [ "$(jq -c '[.step, .gaveWay]' "$STUB/live" 2>/dev/null)" = '["fix",8]' ] || fail "#7's live record does not name #8: $(cat "$STUB/live" 2>/dev/null)"
  # The file's one whole snapshot (about 2 s): #7, given way, and #8, which did not, show how snapshot() reads aways().
  out=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq -c '[.belt[] | select(.issue == 7 or .issue == 8) | [.issue, .gaveWay, .gaveWayFixing]] | sort' <<<"$out" 2>/dev/null)" = '[[7,8,true],[8,null,false]]' ] \
    || fail "the snapshot does not say #7 gave way to #8 while fixing, and #8 to none: $(jq -c .belt <<<"$out" 2>&1 | head -c 2000)"
}

# With no card waiting, the fix of failed tests goes as it always did: #7 gives way for it, but no card takes its
# turn, and its claim, its live record and the Board name none.
t_givewayfixalone() {
  gwcards 7; gwchg 7 1s/.*/seven/; gwclaim 7 '"held":true,"gave":0'
  gweng giveway c7-7 "$CARDS/c7-7" fixing && [ "$(gwc 7 '[.away, .fixing, .for, .to]')" = '[true,true,[],null]' ] \
    || fail "#7's claim names a card for the fix of its failed tests, with none waiting: $(cat "$CARDS/c7-7.claim")"
  gwlive 7; [ "$(jq -c '[.step, .gaveWay]' "$STUB/live" 2>/dev/null)" = '["fix",null]' ] || fail "#7's live record names a card that went in front: $(cat "$STUB/live" 2>/dev/null)"
  # What the snapshot's gaveWay is read from (aways(); t_givewayfix runs the whole snapshot on it).
  out=$(gweng aways) && [ "$out" = '{}' ] || fail "the Board's view says #7 gave way to a card: $out"
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
  eval "$(sed -n '/^claim() {/,/^}/p; /^claimline() {/,/^}/p; /^readyrows() {/,/^}/p; /^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p; /^testedhere() {/p; /^readysince() {/,/^}/p; /^turnq() {/,/^}/p' "$SRC/lib/claim.sh")"
  packget() { printf -v "$2" 1; } # for turnq(): the test pack's landBatch, batches off
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
# them; it waits on main instead (claim()).
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
  eval "$(sed -n '/^claim() {/,/^}/p; /^claimline() {/,/^}/p; /^readyrows() {/,/^}/p; /^giveway() {/,/^}/p; /^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p; /^testedhere() {/p; /^readysince() {/,/^}/p; /^turnq() {/,/^}/p' "$SRC/lib/claim.sh")"
  packget() { printf -v "$2" 1; } # for turnq(): the test pack's landBatch, batches off
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
  eval "$(sed -n '/^claim() {/,/^}/p; /^claimline() {/,/^}/p; /^readyrows() {/,/^}/p; /^giveway() {/,/^}/p; /^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p; /^tested() {/,/} # <worktree>$/p; /^readyput() {/,/^}/p; /^testedhere() {/p; /^readysince() {/,/^}/p; /^turnq() {/,/^}/p' "$SRC/lib/claim.sh")"
  packget() { printf -v "$2" 1; } # for turnq(): the test pack's landBatch, batches off
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
