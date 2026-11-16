#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the same-file rule.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# Each case that runs cards sets a live record every second (the pack's default), not the test pack's 0.2 s: a card
# waiting at its claim looks again each `live` seconds, and these cards wait a lot. The cases wait on what the cards
# do (a stub's wait lasts until what it waits for is there), not on those seconds. t_sameoffretry sets its own.

# Bug: two cards in flight that change the same file both go to review, and the second meets "rebase onto
# main conflicts" at landing. Then (the owner's order): seven cards sharing conveyor.sh queued behind one holder for
# its whole review, none of them reviewed. Cards that share a file are reviewed at the same time, neither review
# waiting; the second waits only to land, shown as waiting on the first with the file, then goes on from main once
# the first has landed. Here its patch no longer applies (the first changed the same lines): one session brings it
# there, and it is reviewed again on main.
t_samefile() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  # Both append to a.txt. #8's build ends once #7 is in review. The first reviews end only once both are in review
  # (a stub's wait lasts until what it waits for is there, or the stub folder is gone: the test's end), #8's once #7
  # holds a.txt too; #7's tests end once #8 is seen waiting at its landing step.
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Main moved: apply the same change' "$STUB/brief"; then cp "$STUB/brief" "$STUB/caught"; printf 'one\nseven\neight\n' > a.txt
else case $PWD in
  *-7) echo seven >> a.txt ;;
  *) while [ -d "$STUB" ]; do [ -e "$STUB/inreview.7" ] && break; sleep 0.1; done; echo eight >> a.txt ;;
esac; fi
EOF
  cat > "$STUB/review-cmd" <<'EOF'
n=${PWD##*-}
if [ ! -e "$STUB/inreview.$n" ]; then
  [ -z "$(ls ../*.claim 2>/dev/null)" ] || : > "$STUB/claimed.$n"; : > "$STUB/inreview.$n"
  while [ -d "$STUB" ]; do [ -e "$STUB/inreview.7" ] && [ -e "$STUB/inreview.8" ] && break; sleep 0.1; done
  [ -e "$STUB/inreview.7" ] && [ -e "$STUB/inreview.8" ] || : > "$STUB/alone"
  [ "$n" = 7 ] || while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done
else git -C "$R" log --format=%s > "$STUB/main-at-$n"; fi
EOF
  echo 'case $PWD in *-7) while [ -d "$STUB" ]; do grep -q waiting ../*-8.live 2>/dev/null && { cp ../*-8.live "$STUB/waitlive"; break; }; sleep 0.1; done ;; esac' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(st 'select(.issue == 7 and .step == "picked") | .card')
  [ ! -e "$STUB/alone" ] && [ -z "$(ls "$STUB"/claimed.* 2>/dev/null)" ] || fail "the two same-file cards were not in review side by side, or one claimed a file before its review"
  [ "$(jq -r .step "$STUB/waitlive" 2>/dev/null)" = land ] && [ "$(jq -r .action "$STUB/waitlive")" = "waiting on card $c7, which changes the same files: a.txt" ] \
    && [ "$(jq -c .waits "$STUB/waitlive")" = "{\"on\":\"$c7\",\"paths\":[\"a.txt\"]}" ] || fail "#8 was not shown waiting on #7 to land, with the file: $(cat "$STUB/waitlive" 2>/dev/null)"
  [ "$(grep -c 'waits on card' <<<"$out")" = 1 ] && grep -q "waits on card $c7, which changes the same files: a.txt" <<<"$out" || fail "the loop did not say #8 waits, once: $out"
  grep -q '^feat(product): title 7 (#7)' "$STUB/main-at-8" || fail "#8's second review was not on main after #7 landed: $(cat "$STUB/main-at-8")"
  st '.reason' | grep -q 'rebase onto main conflicts' && fail "a card met a landing conflict: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 8 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review fix review test landed " ] \
    || fail "steps of #8: $(st "select(.issue == 8) | .step" | tr '\n' ' ')"
  st 'select(.issue == 8 and .step == "fix") | .reason' | grep -q '^main moved since the card' || fail "#8's fix line does not say why"
  grep -q '^The file .*\.patch, made against commit [0-9a-f]*\.$' "$STUB/caught" || fail "the session after the wait was not given the card's patch"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 8 " ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "one seven eight " ] \
    && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "both did not land in turn, main is dirty, or a worktree or claim is left"
  [ "$(st 'select(.step == "review") | "\(.issue) \(.result)"' | tr '\n' ,)" = "7 GO,8 GO,8 GO," ] || fail "reviews: $(st 'select(.step == "review") | .issue' | tr '\n' ' ')"
}

# Bug: among cards waiting on a file with no holder, the older pick always went first, so an ordered card waited
# behind any older one. Here #6 holds a.txt and is ordered, so no card goes past it; once it lands, the ordered #9
# and #8 go before the older #7 that is not ordered, and #9, earlier in the order list, before #8.
t_samequeue() {
  setup "[$(issue 6 2026-01-01),$(issue 7 2026-01-02),$(issue 8 2026-01-03),$(issue 9 2026-01-04)]"; for i in $(seq 7); do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Main moved: apply the same change' "$STUB/brief"; then echo "${PWD##*-}" >> a.txt
else case $PWD in
  *-6) while [ -d "$STUB" ]; do [ "$(jq -s 'map(select(.step == "picked")) | length' "$ST/cards.jsonl")" = 4 ] && break; sleep 0.1; done
       jq -c '.order = [6, 9, 8]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; echo 6 >> a.txt ;;
  *) while [ -d "$STUB" ]; do [ -n "$(ls ../*-6.claim 2>/dev/null)" ] && break; sleep 0.1; done; echo "${PWD##*-}" >> a.txt ;;
esac; fi
EOF
  # #6's tests end once the three others, each reviewed, wait to land.
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in
  *-6) while [ -d "$STUB" ]; do [ "$(cat ../*-[789].live 2>/dev/null | grep -c waiting)" = 3 ] && { cat ../*-[89].live > "$STUB/waitlive"; break; }; sleep 0.1; done ;;
esac
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c6=$(st 'select(.issue == 6 and .step == "picked") | .card')
  [ "$(jq -sc 'map([.step, .waits.on]) | unique' "$STUB/waitlive" 2>/dev/null)" = "[[\"land\",\"$c6\"]]" ] || fail "the ordered #8 and #9 did not both wait to land on the ordered #6: $(cat "$STUB/waitlive" 2>/dev/null)"
  st '.reason' | grep -q 'rebase onto main conflicts' && fail "a card met a landing conflict: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "6 9 8 7 " ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "one 6 9 8 7 " ] && [ -z "$(ls "$T/$CASE/cards")" ] \
    || fail "the waiters did not go ordered first, in the order list's order: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}

# Bug: once the ordered #9 went past #7 on a.txt, both held it, and the Board told #8 it was waiting on #7 (the
# earlier claim) though the ordered #9 goes first. #8's wait must name #9.
t_sameboard() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"; for i in $(seq 8); do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Main moved: apply the same change' "$STUB/brief"; then echo "${PWD##*-}" >> a.txt
else case $PWD in
  *-7) echo 7 >> a.txt ;;
  *-9) while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done
       jq -c '.order = [9]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; echo 9 >> a.txt ;;
  *) while [ -d "$STUB" ]; do jq -e .held ../*-9.claim >/dev/null 2>&1 && break; sleep 0.1; done; echo 8 >> a.txt ;;
esac; fi
EOF
  # The first tests of #7 and #9 end once #8 waits, so both hold a.txt when #8 claims it.
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in
  *-7|*-9) [ -e "$STUB/tested.${PWD##*-}" ] || { : > "$STUB/tested.${PWD##*-}"
           while [ -d "$STUB" ]; do grep -q waiting ../*-8.live 2>/dev/null && { cp ../*-8.live "$STUB/waitlive8"; break; }; sleep 0.1; done; } ;;
esac
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c9=$(st 'select(.issue == 9 and .step == "picked") | .card')
  [ "$(jq -r .waits.on "$STUB/waitlive8" 2>/dev/null)" = "$c9" ] || fail "#8 was not shown waiting on the ordered #9: $(cat "$STUB/waitlive8" 2>/dev/null)"
  [ "$(st 'select(.step == "landed") | .issue' | sort | tr '\n' ' ')" = "7 8 9 " ] && [ -z "$(ls "$T/$CASE/cards")" ] \
    || fail "not all three landed: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}

# The belt full (cap 1) with #11, which waited on card c4-12 holding a.txt; c4-12 blocks and `retry` gives #12 back
# while #11 still holds the only slot, its live record naming c4-12 (it looks again every 10 s; its tests, after the
# wait, end only once #12 is picked, or at the run's time limit): #12 is picked within one poll, past the cap, never after #11
# lands. #12 is given back while the loop sleeps out a poll (3 s here), so the turn that poll ends must pick it: a
# poll that starts after the retry with #12 not yet picked is one missed.
t_sameoffretry() {
  sameoffsetup 11 12
  echo 'case $PWD in *-12) echo twelve > c.txt ;; *) echo eleven >> a.txt ;; esac' > "$STUB/build"; tune '.tunables.poll = 3 | .tunables.live = 10'
  landed 12 | jq -c '.card = "c4-12" | .step = "picked"' >> "$ST/cards.jsonl"
  sleep 300 & holder=$!; jq -cn --argjson p "$holder" '{pid: $p, paths: ["a.txt"], held: true}' > "$T/$CASE/cards/c4-12.claim" # sleep: a stand-in for the holder's process, alive
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in *-11) while [ -d "$STUB" ]; do jq -e 'select(.issue == 12 and .step == "picked" and .card != "c4-12")' "$ST/cards.jsonl" >/dev/null && { : > "$STUB/picked12"; break; }; sleep 0.1; done ;; esac
EOF
  # The giver's waits, here and below, last until what they wait for is there, or the holder is gone (killed when the run ends).
  ( until jq -e '.waits.on == "c4-12"' "$T/$CASE/cards/"*-11.live >/dev/null 2>&1 || ! kill -0 $holder 2>/dev/null; do sleep 0.1; done
    landed 12 | jq -c '.card = "c4-12" | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"' >> "$ST/cards.jsonl"
    rm -f "$STUB/polled"; until [ -e "$STUB/polled" ] || ! kill -0 $holder 2>/dev/null; do sleep 0.1; done
    [ -e "$STUB/polled" ] || { : > "$STUB/nopoll"; exit; }
    loop retry 12 >/dev/null; : > "$STUB/retried12" ) & giver=$!
  # The loop's poll is seen by an exported sleep function: on macOS p_tools puts GNU sleep ahead of any stub on PATH.
  out=$(sleep() { [ "$1" != 3 ] || { : > "$STUB/polled"; [ ! -e "$STUB/retried12" ] || jq -e 'select(.issue == 12 and .step == "picked" and .card != "c4-12")' "$ST/cards.jsonl" >/dev/null || : > "$STUB/missed12"; }; command sleep "$@"; } # sleep: the engine's own, passed on as called
    export -f sleep; CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards timeout 120 bash "$SRC/conveyor.sh" run 2>&1); rc=$?; kill $holder; wait $holder $giver 2>/dev/null; rm -f "$STUB/review-cmd"
  [ $rc = 0 ] && grep -q 'waits on card c4-12' <<<"$out" || fail "#11 did not wait on c4-12, or the run did not end (exit $rc): $out"
  [ ! -e "$STUB/nopoll" ] || fail "the loop did not sleep out a poll after c4-12 blocked, so #12 was never given back"
  [ -e "$STUB/picked12" ] || fail "the retried holder #12 was not picked while the waiter #11 held the only slot: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  [ -e "$STUB/retried12" ] && [ ! -e "$STUB/missed12" ] || fail "the retried holder #12 was not picked within one poll of its retry"
  [ "$(st 'select(.step == "landed") | .issue' | sort -n | tr '\n' ' ')" = "11 12 " ] || fail "#11 and #12 did not both land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
}

# The belt full (cap 1) with #15, which waited on card c6-16 once and went on to its tests when its claim went: nobody
# waits now. `retry` gives #16 back during #15's tests (open for three more turns of the loop after): #16 stays queued, past the
# cap it would start a builder for nobody, and is picked only once #15 lands.
t_sameoffcap() {
  sameoffsetup 15 16; watchturns
  echo 'case $PWD in *-16) echo sixteen > e.txt ;; *) echo fifteen >> a.txt ;; esac' > "$STUB/build"; tune '.tunables.poll = 1'
  landed 16 | jq -c '.card = "c6-16" | .step = "picked"' >> "$ST/cards.jsonl"
  sleep 300 & holder=$!; jq -cn --argjson p "$holder" '{pid: $p, paths: ["a.txt"], held: true}' > "$T/$CASE/cards/c6-16.claim" # sleep: a stand-in for the holder's process, alive
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in *-15) : > "$STUB/intests15"; while [ -d "$STUB" ]; do [ -e "$STUB/given16" ] && break; sleep 0.1; done
  t=$(wc -l < "$TURNS"); while [ -d "$STUB" ] && [ "$(wc -l < "$TURNS")" -lt $((t + 3)) ]; do jq -e 'select(.issue == 16 and .step == "picked" and .card != "c6-16")' "$ST/cards.jsonl" >/dev/null && { : > "$STUB/early16"; break; }; sleep 0.1; done ;; esac
EOF
  ( until jq -e '.waits.on == "c6-16"' "$T/$CASE/cards/"*-15.live >/dev/null 2>&1 || ! kill -0 $holder 2>/dev/null; do sleep 0.1; done
    rm -f "$T/$CASE/cards/c6-16.claim"
    until [ -e "$STUB/intests15" ] || ! kill -0 $holder 2>/dev/null; do sleep 0.1; done
    landed 16 | jq -c '.card = "c6-16" | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"' >> "$ST/cards.jsonl"
    loop retry 16 >/dev/null; : > "$STUB/given16" ) & giver=$!
  out=$(CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards timeout 120 bash "$SRC/conveyor.sh" run 2>&1); rc=$?; kill $holder; wait $holder $giver 2>/dev/null; rm -f "$STUB/review-cmd"
  [ $rc = 0 ] && grep -q 'waits on card c6-16' <<<"$out" && [ -e "$STUB/given16" ] || fail "#15 did not wait on c6-16, #16 was not given back, or the run did not end (exit $rc): $out"
  [ ! -e "$STUB/early16" ] || fail "the retried #16 was picked past the cap while #15 no longer waited on it: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | sort -n | tr '\n' ' ')" = "15 16 " ] || fail "#15 and #16 did not both land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
}

# The owner (2026-11-12): "how do we avoid having so many cards waiting". Cards that share a file and changed
# different functions of it do not overlap: their changes apply together. Both are reviewed at the same time, and #8
# does not wait on #7 to land: it holds a.txt while #7 does (#7's tests end only then). #7 lands first (#8's first
# tests end only then); #8, whose tests ran on a main without #7's change, is fitted onto main with no session and no
# second review, and lands on the tests it passed (the owner, 2026-11-13: no second run only because main moved).
t_sameapply() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  { printf '%s\n' 'first() {' '  echo one' '}'; seq 10; printf '%s\n' 'last() {' '  echo two' '}'; } > "$R/a.txt"; git -C "$R" commit -qam "a.txt of two functions"
  cat > "$STUB/build" <<'EOF'
case $PWD in
  *-7) sed -i 's/echo one/echo seven/' a.txt ;;
  *) while [ -d "$STUB" ]; do [ -e "$STUB/inreview.7" ] && break; sleep 0.1; done; sed -i 's/echo two/echo eight/' a.txt ;;
esac
EOF
  cat > "$STUB/review-cmd" <<'EOF'
n=${PWD##*-}; : > "$STUB/inreview.$n"
while [ -d "$STUB" ]; do [ -e "$STUB/inreview.7" ] && [ -e "$STUB/inreview.8" ] && break; sleep 0.1; done
[ -e "$STUB/inreview.7" ] && [ -e "$STUB/inreview.8" ] || : > "$STUB/alone"
[ "$n" = 7 ] || while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done
EOF
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in
  *-7) while [ -d "$STUB" ]; do jq -e .held ../*-8.claim >/dev/null 2>&1 && { cat ../*-7.claim ../*-8.claim > "$STUB/claims"; break; }; sleep 0.1; done ;;
  *) [ -e "$STUB/tested.8" ] || { : > "$STUB/tested.8"
    while [ -d "$STUB" ]; do jq -e 'select(.issue == 7 and .step == "landed")' "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done; } ;;
esac
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ ! -e "$STUB/alone" ] || fail "the two same-file cards were not in review side by side"
  [ "$(jq -sc 'map([.held, .paths])' "$STUB/claims" 2>/dev/null)" = '[[true,["a.txt"]],[true,["a.txt"]]]' ] && ! grep -q "waits on card" <<<"$out" \
    || fail "#8 waited on #7, whose change applies together with its own: $(cat "$STUB/claims" 2>/dev/null) $out"
  [ -z "$(st 'select(.step == "fix") | .issue')" ] || fail "a session brought a change onto main though it applied: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 8 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test test landed " ] \
    && [ "$(st 'select(.issue == 8 and .step == "test") | .reused // false' | tr '\n' ' ')" = "false true " ] \
    || fail "#8, whose change applied to main with #7's, did not land on the tests it passed, its line saying it reused them: $(st "select(.issue == 8 and .step == \"test\")")"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 8 " ] && [ "$(grep -c 'echo seven\|echo eight' "$R/a.txt")" = 2 ] \
    && [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ -z "$(ls "$T/$CASE/cards")" ] \
    || fail "both did not land in turn with one review each: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
}

# Bug: a card whose overlapping card landed before it claimed anything saw no claim, skipped the move onto
# main, and met "rebase onto main conflicts" at landing. At its landing claim it must be brought onto main, then
# reviewed again there.
t_samelate() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Main moved: apply the same change' "$STUB/brief"; then printf 'one\nseven\neight\n' > a.txt
else case $PWD in
  *-7) echo seven >> a.txt ;;
  *) while [ -d "$STUB" ]; do grep -qx seven "$R/a.txt" && [ -z "$(ls ../*-7.claim 2>/dev/null)" ] && break; sleep 0.1; done; echo eight >> a.txt ;;
esac; fi
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  st '.reason' | grep -q 'rebase onto main conflicts' && fail "a card met a landing conflict: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 8 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review fix review test landed " ] \
    || fail "steps of #8: $(st "select(.issue == 8) | .step" | tr '\n' ' ')"
  [ "$(tr '\n' ' ' < "$R/a.txt")" = "one seven eight " ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] || fail "both did not land, #8 reviewed again once brought onto main"
}

# Bug: an older card that claimed a file after a younger card had claimed it either went past its claim too, both
# past their claim on the same file, or waited for the younger one to land even when the younger one claimed again.
# Both are reviewed with no wait; the older card waits at its landing claim on the younger one, which holds the file
# through its tests. Those fail once, so the younger one claims again after its fix and review: there it waits on the
# older one (the older waiting pick goes first), the older one lands, and the younger one is brought onto main and
# reviewed again.
t_sameorder() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3 4; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  cat > "$STUB/build" <<'EOF'
if grep -q '^# The changed tests fail' "$STUB/brief"; then :
elif grep -q '^# Main moved: apply the same change' "$STUB/brief"; then printf 'one\nseven\neight\n' > a.txt
else case $PWD in
  *-7) echo seven >> a.txt ;;
  *) while [ -d "$STUB" ]; do [ -e "$STUB/inreview.7" ] && break; sleep 0.1; done; echo eight >> a.txt ;;
esac; fi
EOF
  # #7's review ends once #8 holds a.txt; #8's first tests fail once #7 waits on it; #7's tests end once #8 waits on
  # it at #8's next claim.
  cat > "$STUB/review-cmd" <<'EOF'
[ "$(cat ../*.claim 2>/dev/null | jq -s '[.[] | select(.held and (.paths | index("a.txt")))] | length')" -le 1 ] || : > "$STUB/both"
case $PWD in
  *-7) : > "$STUB/inreview.7"; git -C "$R" log --format=%s > "$STUB/main-at-7"
       while [ -d "$STUB" ]; do jq -e .held ../*-8.claim >/dev/null 2>&1 && break; sleep 0.1; done ;;
esac
EOF
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in *-8) echo x >> "$STUB/failed.8"; [ "$(wc -l < "$STUB/failed.8")" -gt 2 ] || { # its first run and its run again (tests()) fail
  while [ -d "$STUB" ]; do grep -q waiting ../*-7.live 2>/dev/null && { cp ../*-7.live "$STUB/waitlive"; break; }; sleep 0.1; done
  echo "FAIL a.test"; exit 1; } ;;
  *-7) [ -e "$STUB/waitlive8" ] || while [ -d "$STUB" ]; do grep -q waiting ../*-8.live 2>/dev/null && { cp ../*-8.live "$STUB/waitlive8"; break; }; sleep 0.1; done ;;
esac
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(st 'select(.issue == 7 and .step == "picked") | .card'); c8=$(st 'select(.issue == 8 and .step == "picked") | .card')
  [ "$(grep -c 'waits on card' <<<"$out")" = 2 ] && grep -q "card $c7 waits on card $c8, which changes the same files: a.txt" <<<"$out" \
    && grep -q "card $c8 waits on card $c7, which changes the same files: a.txt" <<<"$out" || fail "#7 did not wait on #8, then #8 on #7: $out"
  [ "$(jq -r .step "$STUB/waitlive" 2>/dev/null)" = land ] && [ "$(jq -c .waits "$STUB/waitlive")" = "{\"on\":\"$c8\",\"paths\":[\"a.txt\"]}" ] \
    || fail "#7 did not wait to land on #8 while #8 held a.txt: $(cat "$STUB/waitlive" 2>/dev/null)"
  [ "$(jq -r .step "$STUB/waitlive8" 2>/dev/null)" = land ] && [ "$(jq -c .waits "$STUB/waitlive8")" = "{\"on\":\"$c7\",\"paths\":[\"a.txt\"]}" ] \
    || fail "#8 was not waiting on #7 at its next claim while #7 ran its tests: $(cat "$STUB/waitlive8" 2>/dev/null)"
  [ ! -e "$STUB/both" ] || fail "both cards held a.txt at once"
  grep -q '^feat(product): title 8 (#8)' "$STUB/main-at-7" && fail "#7 was reviewed after #8 landed: $(cat "$STUB/main-at-7")"
  st '.reason' | grep -q 'rebase onto main conflicts' && fail "a card met a landing conflict: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  st 'select(.issue == 8 and .step == "fix") | .reason' | grep -q '^main moved since the card' || fail "#8 was not brought onto main after #7 landed"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 8 " ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "one seven eight " ] \
    && [ "$(st 'select(.step == "review") | "\(.issue) \(.result)"' | tr '\n' ,)" = "8 GO,7 GO,8 GO,8 GO," ] && [ -z "$(ls "$T/$CASE/cards")" ] \
    || fail "#7 did not land first, or #8 was not reviewed again once brought onto main: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
}

# Bug: an older card holding x.txt whose fix added a.txt, while a younger card held a.txt, ignored the younger holder:
# both were past their claim on a.txt. The older card must wait on the younger one at its landing claim until the
# younger one's next claim (its tests fail once), where the younger one waits on it; the older one lands first.
t_samelast() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3 4 5; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  cat > "$STUB/build" <<'EOF2'
if grep -q '^# The changed tests fail' "$STUB/brief"; then :
elif grep -q '^# Main moved: apply the same change' "$STUB/brief"; then printf 'one\nseven\neight\n' > a.txt
else case $PWD in
  *-7) if [ -e "$STUB/seven-built" ]; then echo seven >> a.txt; else : > "$STUB/seven-built"; echo seven > x.txt; fi ;;
  *) while [ -d "$STUB" ]; do [ -e "$STUB/inreview.7" ] && break; sleep 0.1; done; echo eight >> a.txt ;;
esac; fi
EOF2
  # #7's first review ends once #8 holds a.txt, with a NO-GO: its fix adds a.txt. #8's first tests fail once #7 waits
  # on it; #7's tests end once #8 waits on it at #8's next claim.
  cat > "$STUB/review-cmd" <<'EOF2'
[ "$(cat ../*.claim 2>/dev/null | jq -s '[.[] | select(.held and (.paths | index("a.txt")))] | length')" -le 1 ] || : > "$STUB/both"
case $PWD in
  *-7) if [ ! -e "$STUB/inreview.7" ]; then : > "$STUB/inreview.7"
       while [ -d "$STUB" ]; do jq -e '.held and (.paths | index("a.txt"))' ../*-8.claim >/dev/null 2>&1 && break; sleep 0.1; done
       printf '[P1] x.txt:1 a.txt needs the line too\nUSER-VISIBLE: no\nVERDICT: NO-GO\n' > "$out"
       echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":7}}'; exit 0
     fi ;;
esac
EOF2
  cat >> "$STUB/test-cmd" <<'EOF2'
case $PWD in *-8) echo x >> "$STUB/failed.8"; [ "$(wc -l < "$STUB/failed.8")" -gt 2 ] || { # its first run and its run again (tests()) fail
  while [ -d "$STUB" ]; do grep -q waiting ../*-7.live 2>/dev/null && { cp ../*-7.live "$STUB/waitlive"; break; }; sleep 0.1; done
  echo "FAIL a.test"; exit 1; } ;;
  *-7) while [ -d "$STUB" ]; do grep -q waiting ../*-8.live 2>/dev/null && { cp ../*-8.live "$STUB/waitlive8"; break; }; sleep 0.1; done ;;
esac
EOF2
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(st 'select(.issue == 7 and .step == "picked") | .card'); c8=$(st 'select(.issue == 8 and .step == "picked") | .card')
  [ "$(jq -r .step "$STUB/waitlive" 2>/dev/null)" = land ] && [ "$(jq -c .waits "$STUB/waitlive")" = "{\"on\":\"$c8\",\"paths\":[\"a.txt\"]}" ] \
    || fail "#7 did not wait on #8 once its fix added a.txt: $(cat "$STUB/waitlive" 2>/dev/null)"
  [ "$(jq -r .step "$STUB/waitlive8" 2>/dev/null)" = land ] && [ "$(jq -c .waits "$STUB/waitlive8")" = "{\"on\":\"$c7\",\"paths\":[\"a.txt\"]}" ] \
    || fail "#8 did not wait on #7 at its next claim: $(cat "$STUB/waitlive8" 2>/dev/null)"
  [ ! -e "$STUB/both" ] || fail "both cards held a.txt at once"
  st '.reason' | grep -q 'rebase onto main conflicts' && fail "a card met a landing conflict: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 8 " ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "one seven eight " ] \
    && [ "$(cat "$R/x.txt")" = seven ] && [ "$(st 'select(.step == "review") | "\(.issue) \(.result)"' | tr '\n' ,)" = "8 GO,7 NO-GO,7 GO,8 GO,8 GO," ] \
    && [ -z "$(ls "$T/$CASE/cards")" ] || fail "#7 did not land first, or #8 was not reviewed again from main: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
}

# Bug: a card the owner ordered first sat built behind an older card that was not ordered and held the same file
# (the fix that card needed waited on it). The ordered card must claim the file at its landing step and go on to its
# tests while the older card holds it; the older card, past its own claim then, claims again before it lands and waits
# for it there, then is brought onto main, reviewed again and lands.
t_samepast() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  # #8 is ordered once both are picked and #7 holds a.txt.
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Main moved: apply the same change' "$STUB/brief"; then echo seven >> a.txt
else case $PWD in
  *-7) echo seven >> a.txt ;;
  *) while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done
     jq -c '.order = [8]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; echo eight >> a.txt ;;
esac; fi
EOF
  # #7's first tests end once #8 is in its tests; #8's tests end once #7 waits at its next claim.
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in
  *-7) while [ -d "$STUB" ]; do [ -e "$STUB/intests.8" ] && break; sleep 0.1; done ;;
  *) jq -e .held ../*-7.claim >/dev/null 2>&1 && : > "$STUB/past"; : > "$STUB/intests.8"
     while [ -d "$STUB" ]; do grep -q waiting ../*-7.live 2>/dev/null && { cp ../*-7.live "$STUB/waitlive7"; break; }; sleep 0.1; done ;;
esac
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(st 'select(.issue == 7 and .step == "picked") | .card'); c8=$(st 'select(.issue == 8 and .step == "picked") | .card')
  [ -e "$STUB/past" ] && ! grep -q "card $c8 waits" <<<"$out" || fail "the ordered #8 waited on #7, or was not in its tests while #7 held a.txt: $out"
  [ "$(jq -r .step "$STUB/waitlive7" 2>/dev/null)" = land ] && [ "$(jq -c .waits "$STUB/waitlive7")" = "{\"on\":\"$c8\",\"paths\":[\"a.txt\"]}" ] \
    || fail "#7 did not wait on the ordered #8 at its next claim: $(cat "$STUB/waitlive7" 2>/dev/null)"
  st '.reason' | grep -q 'rebase onto main conflicts' && fail "a card met a landing conflict: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "one eight seven " ] \
    && [ "$(st 'select(.step == "review") | "\(.issue) \(.result)"' | tr '\n' ,)" = "7 GO,8 GO,7 GO," ] && [ -z "$(ls "$T/$CASE/cards")" ] \
    || fail "#8 did not land first, or #7 was not reviewed again from main: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
}

# Bug: a card the ordered #8 went past landed without another review when its patch still applied to main after #8
# landed, so nobody reviewed it against #8's change. #7 changes a.txt's first line and #8 its last: #7 must be
# reviewed again from main, with no session to bring it there. In this case and the two after it, a claim keeps no
# patch of its card's change (it is taken away once the card holds a.txt: #7's before #8 claims, #8's before #7 claims
# again): the two cards, whose changes apply together, overlap on the shared file all the same (together()).
t_samepastclean() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  seq 20 | sed 1s/1/one/ > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  cat > "$STUB/build" <<'EOF'
case $PWD in
  *-7) { echo seven; tail -n +2 a.txt; } > a.new && mv a.new a.txt ;;
  *) while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done; rm -f ../*-7.cpatch
     jq -c '.order = [8]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; echo eight >> a.txt ;;
esac
EOF
  # #7's first tests end once #8 is in its tests; #8's tests end once #7 waits at its next claim.
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in
  *-7) while [ -d "$STUB" ]; do [ -e "$STUB/intests.8" ] && break; sleep 0.1; done ;;
  *) rm -f "$PWD.cpatch"; : > "$STUB/intests.8"; while [ -d "$STUB" ]; do grep -q waiting ../*-7.live 2>/dev/null && break; sleep 0.1; done ;;
esac
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ -z "$(st 'select(.step == "fix") | .issue')" ] || fail "a session brought a change onto main though it applied: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] && [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] \
    && [ "$(st 'select(.step == "review") | "\(.issue) \(.result)"' | tr '\n' ,)" = "7 GO,8 GO,7 GO," ] && [ -z "$(ls "$T/$CASE/cards")" ] \
    || fail "#7 landed after #8 without being reviewed again from main: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
}

# Bug: a card the ordered #8 went past landed without another review when #8 had landed and let go of a.txt before
# #7's next claim (here, before #7's tests end), so #7 found nobody to wait on. #7 must still be reviewed again from main.
t_samepastgone() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  seq 20 | sed 1s/1/one/ > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  cat > "$STUB/build" <<'EOF'
case $PWD in
  *-7) { echo seven; tail -n +2 a.txt; } > a.new && mv a.new a.txt ;;
  *) while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done; rm -f ../*-7.cpatch
     jq -c '.order = [8]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; echo eight >> a.txt ;;
esac
EOF
  # #7's first tests end only once #8 has landed.
  cat >> "$STUB/test-cmd" <<'EOF'
case $PWD in
  *-7) while [ -d "$STUB" ]; do jq -e 'select(.issue == 8 and .step == "landed")' "$ST/cards.jsonl" >/dev/null 2>&1 && break; sleep 0.1; done ;;
esac
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  ! grep -q "waits on card" <<<"$out" || fail "a card waited, so #8 had not landed before #7's next claim: $out"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] && [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] \
    && [ "$(st 'select(.step == "review") | "\(.issue) \(.result)"' | tr '\n' ,)" = "7 GO,8 GO,7 GO," ] && [ -z "$(ls "$T/$CASE/cards")" ] \
    || fail "#7 landed after #8 without being reviewed again from main: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
}

# Bug: a card read that no ordered card had gone past it, then, before its locked landing, the ordered #8 went past it
# and landed a change on other lines of the same file; #7's patch still applied, so it landed without another review.
# Here #8 goes past #7 while #7 is at its landing step (its usage reading before the lock waits for that): #7 must not
# land then, but wait for #8 and be reviewed again from main.
t_samepastland() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  seq 20 | sed 1s/1/one/ > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  cat > "$STUB/build" <<'EOF2'
case $PWD in
  *-7) { echo seven; tail -n +2 a.txt; } > a.new && mv a.new a.txt ;;
  *) while [ -d "$STUB" ]; do [ -e "$STUB/tested.7" ] && break; sleep 0.1; done; rm -f ../*-7.cpatch
     jq -c '.order = [8]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; echo eight >> a.txt ;;
esac
EOF2
  cat >> "$STUB/test-cmd" <<'EOF2'
case $PWD in *-7) : > "$STUB/tested.7" ;; esac
EOF2
  # The reading #7 asks for at its landing step, before the lock, ends once #8 has gone past it.
  cat > "$STUB/limit" <<EOF2
if [ ! -e "$STUB/landing.7" ] && jq -se 'map(select(.issue == 7)) | last | .step == "start" and .of == "land"' "\$ST/cards.jsonl" >/dev/null 2>&1; then
  : > "$STUB/landing.7"; while [ -d "$STUB" ]; do jq -e '.passed == true' "$T/$CASE/cards/"*-7.claim >/dev/null 2>&1 && { : > "$STUB/past"; break; }; sleep 0.1; done
  while [ -d "$STUB" ]; do jq -e .held "$T/$CASE/cards/"*-8.claim >/dev/null 2>&1 && { rm -f "$T/$CASE/cards/"*-8.cpatch; break; }; sleep 0.1; done
fi
false
EOF2
  out=$(CONVEYOR_LIMIT_CMD=". \"$STUB/limit\"" loop run 2>&1) || fail "run exited non-zero: $out"
  [ -e "$STUB/past" ] || fail "the ordered #8 did not go past #7 while #7 was at its landing step: $(st '"\(.issue) \(.step) \(.result) \(.of // "")"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] && [ "$(sed -n '1p;$p' "$R/a.txt" | tr '\n' ' ')" = "seven eight " ] \
    && [ "$(st 'select(.step == "review") | "\(.issue) \(.result)"' | tr '\n' ,)" = "7 GO,8 GO,7 GO," ] && [ -z "$(ls "$T/$CASE/cards")" ] \
    || fail "#7 landed without being reviewed again after the ordered #8 went past it at its landing step: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
}

# Bug: cards with no file in common are held to one at a time. Both must be in review at once, as before.
t_apart() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  echo 'case $PWD in *-7) echo seven >> a.txt ;; *) echo eight > b.txt ;; esac' > "$STUB/build"
  cat > "$STUB/review-cmd" <<'EOF'
: > "$STUB/inreview.${PWD##*-}"
while [ -d "$STUB" ]; do [ -e "$STUB/inreview.7" ] && [ -e "$STUB/inreview.8" ] && break; sleep 0.1; done
[ -e "$STUB/inreview.7" ] && [ -e "$STUB/inreview.8" ] || : > "$STUB/alone"
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ ! -e "$STUB/alone" ] || fail "the two cards were not in review side by side"
  grep -q 'waits on card' <<<"$out" && fail "a card waited on a card with no file in common: $out"
  [ "$(st 'select(.step == "landed") | .issue' | sort | tr '\n' ' ')" = "7 8 " ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    && [ -z "$(ls "$T/$CASE/cards")" ] || fail "both did not land with one session each, or a worktree or claim is left: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
}

# Bug: a card that blocked while it held a file, and was given back by `retry`, kept every card that shares the file
# waiting on it, each holding a builder slot; with the belt full of them its own retry was never picked (8 of 10 slots
# for 70 minutes), and the Board showed them all in review. A card that is not on the belt holds no file: the card
# waiting on it goes on to review at once, and the retried issue is picked; a waiting card's step reads waiting, and
# one that has waited STUCK seconds on a card not on the belt is reported stuck.
t_sameoff() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  echo 'case $PWD in *-7) echo seven > b.txt ;; *) echo two >> a.txt ;; esac' > "$STUB/build"
  # Card c1-7 blocked holding a.txt, its claim not yet gone and its process alive; then #7 is given back.
  landed 7 | jq -c '.card = "c1-7" | .step = "picked"' >> "$ST/cards.jsonl"
  landed 7 | jq -c '.card = "c1-7" | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"' >> "$ST/cards.jsonl"
  sleep 300 & holder=$!; mkdir -p "$T/$CASE/cards" # sleep: a stand-in for the blocked card's process, alive
  jq -cn --argjson p "$holder" '{pid: $p, paths: ["a.txt"], held: true}' > "$T/$CASE/cards/c1-7.claim"
  loop control cap 1 >/dev/null || fail "cap 1 was refused"
  # While c1-7 is still blocked (picked, not retried), #8 goes on past its claim and lands.
  out=$(CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards timeout 120 bash "$SRC/conveyor.sh" run 2>&1); rc=$?
  [ $rc = 0 ] || fail "the run did not end (exit $rc): a card waited on a blocked card: $out"
  grep -q 'waits on card' <<<"$out" && fail "a card waited on a blocked card: $out"
  [ "$(st 'select(.step == "landed") | .issue')" = 8 ] || fail "#8 did not land past the blocked card: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  # Then #7 is given back, its claim still there and its process alive: the retried issue is picked and lands.
  loop retry 7 >/dev/null || fail "retry of #7 exited non-zero"
  [ -e "$T/$CASE/cards/c1-7.claim" ] || jq -cn --argjson p "$holder" '{pid: $p, paths: ["a.txt"], held: true}' > "$T/$CASE/cards/c1-7.claim"
  out=$(CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards timeout 120 bash "$SRC/conveyor.sh" run 2>&1); rc=$?; kill $holder; wait $holder 2>/dev/null
  [ $rc = 0 ] || fail "the run did not end (exit $rc): the belt deadlocked on a card that is not on it: $out"
  grep -q 'waits on card' <<<"$out" && fail "a card waited on a retried card: $out"
  [ "$(st 'select(.step == "landed") | .issue' | sort | tr '\n' ' ')" = "7 8 " ] || fail "both did not land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
}
# Each kind of wait on a card `retry` gave back is a case of its own on a main of its own (sameoff, sameoffretry,
# sameoffonly, sameoffcap, sameoffstuck), so they run side by side. sameoffsetup <issue> <issue>: those two issues,
# every review a GO, the belt's cap 1.
sameoffsetup() {
  setup "[$(issue "$1" 2026-01-03),$(issue "$2" 2026-01-04)]"; for i in $(seq 1 12); do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.live = 1'
  mkdir -p "$T/$CASE/cards"; loop control cap 1 >/dev/null || fail "cap 1 was refused"
}

# As t_sameoffretry, with `run --only 13`: #13 waited on card c5-14, which `retry` gave back. The run builds only what it
# lists, so #14 is never picked (#13's tests, after the wait, stay open for three more turns of the loop, counted
# in $TURNS, to give it the chance); #13 goes on past the card that is not on the belt and lands.
t_sameoffonly() {
  sameoffsetup 13 14
  watchturns
  echo 'case $PWD in *-13) t=$(wc -l < "$TURNS"); while [ -d "$STUB" ] && [ "$(wc -l < "$TURNS")" -lt $((t + 3)) ]; do sleep 0.1; done ;; esac' >> "$STUB/test-cmd"
  echo 'case $PWD in *-14) echo fourteen > d.txt ;; *) echo thirteen >> a.txt ;; esac' > "$STUB/build"; tune '.tunables.poll = 1'
  landed 14 | jq -c '.card = "c5-14" | .step = "picked"' >> "$ST/cards.jsonl"
  sleep 300 & holder=$!; jq -cn --argjson p "$holder" '{pid: $p, paths: ["a.txt"], held: true}' > "$T/$CASE/cards/c5-14.claim" # sleep: a stand-in for the holder's process, alive
  ( until jq -e '.waits.on == "c5-14"' "$T/$CASE/cards/"*-13.live >/dev/null 2>&1 || ! kill -0 $holder 2>/dev/null; do sleep 0.1; done
    landed 14 | jq -c '.card = "c5-14" | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"' >> "$ST/cards.jsonl"
    loop retry 14 >/dev/null ) & giver=$!
  out=$(CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards timeout 120 bash "$SRC/conveyor.sh" run --only 13 2>&1); rc=$?; kill $holder; wait $holder $giver 2>/dev/null; rm -f "$STUB/review-cmd"
  [ $rc = 0 ] && grep -q 'waits on card c5-14' <<<"$out" || fail "#13 did not wait on c5-14, or the run did not end (exit $rc): $out"
  [ -z "$(st 'select(.issue == 14 and .step == "picked")')" ] || fail "run --only 13 picked the retried #14: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  [ -n "$(st 'select(.issue == 13 and .step == "landed")')" ] || fail "#13 did not land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
}

# A card waiting on a card `retry` gave back (not on the belt) for 25 minutes (past STUCK, within waitLimitMin), and
# one waiting as long on a card on the belt. Card c1-7 blocked and was given back, as in t_sameoff.
t_sameoffstuck() {
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$T/$CASE/cards"
  landed 7 | jq -c '.card = "c1-7" | .step = "picked"' >> "$ST/cards.jsonl"
  landed 7 | jq -c '.card = "c1-7" | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"' >> "$ST/cards.jsonl"
  loop retry 7 >/dev/null || fail "retry of #7 exited non-zero"
  now=$(jq -rn 'now | todate'); ago=$(jq -rn 'now - 1500 | todate')
  for c in c2-9:c1-7 c3-10:c2-9; do
    k=${c%%:*}; n=${k#*-}
    jq -cn --arg c "$k" --argjson n "$n" --arg t "$now" '{card:$c,issue:$n,step:"picked",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:"",title:"t",created:$t},
      {card:$c,issue:$n,step:"start",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:"",of:"land"}' >> "$ST/cards.jsonl"
    jq -cn --arg on "${c#*:}" --arg at "$ago" --arg t "$now" '{step: "land", at: $at, last: $t, turns: 0, waits: {on: $on, paths: ["a.txt"]},
      action: "waiting on card \($on), which changes the same files: a.txt"}' > "$T/$CASE/cards/$k.live"
  done
  s=$(loop snapshot) || fail "snapshot failed"
  [ "$(jq -c '[.belt[] | select(.card | IN("c2-9", "c3-10")) | [.card, .step, .waitsOn.issue, .waitsOn.state]]' <<<"$s")" = '[["c2-9","waiting",7,"queued"],["c3-10","waiting",9,"brief"]]' ] \
    || fail "a waiting card's step is not waiting, or does not say what it waits on: $(jq -c '[.belt[] | {card, step, waitsOn}]' <<<"$s")"
  [ "$(loop health | jq -c '[.stuck[] | [.card, .step, .waitsOn]]')" = '[["c2-9","waiting",{"card":"c1-7","issue":7,"state":"queued"}]]' ] \
    || fail "a long wait on a card not on the belt is not stuck, or one on a card on the belt is: $(loop health | jq -c .stuck)"
  # A waiter whose own output is stale is stuck as waiting, never as the landing it waits to begin.
  jq -cn --arg t "$ago" '{card:"c3-10",issue:10,step:"start",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:"",of:"land"}' >> "$ST/cards.jsonl"
  jq -c --arg t "$ago" '.last = $t' "$T/$CASE/cards/c3-10.live" > "$T/$CASE/cards/c3-10.live.new" && mv "$T/$CASE/cards/c3-10.live.new" "$T/$CASE/cards/c3-10.live"
  [ "$(loop health | jq -c '[.stuck[] | select(.card == "c3-10") | [.step, .waitsOn]]')" = '[["waiting",{"card":"c2-9","issue":9,"state":"land"}]]' ] \
    || fail "a stale waiter is stuck in another step: $(loop health | jq -c .stuck)"
}

# Bug: a card waiting at its claim for a same-file card was reported stuck after STUCK seconds with no new step, its
# live record brought up to date every poll; waiting is normal. A card waiting there 25 minutes on a live holder (past
# STUCK, within the limit on all its waits, waitLimitMin: tests/health.test.sh) is not
# stuck and shows as waiting on that card; a silent card with no wait is stuck, as before, and so is one whose only
# fresh wait record is from another step; and once the holder's process is gone the wait never ends, so the waiter is
# stuck too.
t_waitclaim() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03),$(issue 10 2026-01-04)]"; mkdir -p "$T/$CASE/cards"
  sleep 300 & holder=$!; sleep 300 & waiter=$! # sleep: stand-ins for two cards' processes, alive
  now=$(jq -rn 'now | todate'); ago25=$(jq -rn 'now - 1500 | todate'); ago20=$(jq -rn 'now - 1200 | todate')
  line() { # <card> <issue> <step> <time> <extra json>
    jq -cn --arg c "$1" --argjson n "$2" --arg s "$3" --arg t "$4" --argjson x "$5" \
      '{card:$c,issue:$n,step:$s,time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} + $x' >> "$ST/cards.jsonl"
  }
  for c in "c1-7,7,$holder,$now" "c2-8,8,$waiter,$ago25" "c3-9,9,$waiter,$ago20" "c4-10,10,$waiter,$ago25"; do
    IFS=, read -r k n p t <<<"$c"
    line "$k" "$n" picked "$t" '{"title":"t","created":"2026-01-01T00:00:00Z"}'
    line "$k" "$n" worktree "$t" "$(jq -cn --argjson p "$p" --arg s "$(. "$SRC/lib/portable.sh"; p_started "$p")" '{pid:$p,started:$s}')"
  done
  line c1-7 7 start "$now" '{"of":"review"}'; line c2-8 8 start "$ago25" '{"of":"land"}'; line c3-9 9 start "$ago20" '{"of":"build"}'
  line c4-10 10 start "$ago25" '{"of":"build"}'
  for k in c2-8 c4-10; do # c4-10's fresh wait record is from a step it is not running: no output from its build.
    jq -cn --arg at "$ago25" --arg t "$now" '{step: "land", at: $at, last: $t, turns: 0, waits: {on: "c1-7", paths: ["a.txt"]},
      action: "waiting on card c1-7, which changes the same files: a.txt"}' > "$T/$CASE/cards/$k.live"
  done
  h=$(loop health) || fail "health failed: $h"
  [ "$(jq -c '[.stuck[].card] | sort' <<<"$h")" = '["c3-9","c4-10"]' ] \
    || fail "a card waiting at its claim on a live holder is stuck, or a silent card is not: $(jq -c .stuck <<<"$h")"
  [ "$(jq -c --arg a "$ago25" '.waitingOnCard == [{card: "c2-8", issue: 8, since: $a, waitsOn: {card: "c1-7", issue: 7, state: "review"}}]' <<<"$h")" = true ] \
    || fail "health does not show the card waiting on its holder: $(jq -c .waitingOnCard <<<"$h")"
  s=$(loop snapshot) || fail "snapshot failed"
  [ "$(jq -c '[.belt[] | select(.card == "c2-8") | [.step, .waitsOn.card, .waitsOn.issue]]' <<<"$s")" = '[["waiting","c1-7",7]]' ] \
    || fail "the Board does not show the card waiting on its holder: $(jq -c '[.belt[] | {card, step, waitsOn}]' <<<"$s")"
  # The holder's process is gone: the wait never ends, so the waiter is stuck, as waiting since its wait began.
  kill $holder; wait $holder 2>/dev/null
  h=$(loop health) || fail "health failed: $h"
  [ "$(jq -c '[.stuck[] | [.card, .step]] | sort | map(select(.[0] != "c4-10"))' <<<"$h")" = '[["c1-7","review"],["c2-8","waiting"],["c3-9","build"]]' ] \
    && [ "$(jq -r '.stuck[] | select(.card == "c2-8") | .since' <<<"$h")" = "$ago25" ] \
    || fail "a card waiting on a holder whose process is gone is not stuck since its wait began: $(jq -c .stuck <<<"$h")"
  kill $waiter; wait $waiter 2>/dev/null; :
}
