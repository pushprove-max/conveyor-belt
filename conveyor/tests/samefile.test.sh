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
# The cases call the engine's functions on card worktrees made here, with no loop run: claim() in the case's own shell
# (sfclaim, as readyfirst.test.sh's t_readyclaim loads it), and settle(), land(), urgent() and pick() in the engine
# shell (fx_in, lib.sh).

# sfcard <issue> <change>: card c<issue>-<issue>'s worktree on main, <change> made in it and staged, its picked line
# in the card records.
sfcard() {
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  git -C "$R" worktree add -q --detach "$CARDS/c$1-$1" main && (cd "$CARDS/c$1-$1" && eval "$2") && git -C "$CARDS/c$1-$1" add -A \
    || fail "the change of card $1 could not be staged"
  landed "$1" | jq -c --arg c "c$1-$1" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"
}
# claim() and what it calls (lib/claim.sh), with stdb() (lib/records.sh), in the case's shell. cl <issue>: that card's
# claim, under this shell's pid (alive), printing what it waits on ({"on": ...}), nothing when it holds its files.
sfclaim() {
  eval "$(sed -n '/^claim() {/,/^}/p; /^together() {/,/^}/p; /^ready() {/,/^}/p; /^fits() {/,/^}/p; /^merge3() {/,/^}/p; /^cardpatch() {/p; /^tested() {/,/} # <worktree>$/p; /^testedhere() {/p; /^readysince() {/,/^}/p; /^bpid() {/,/^}/p' "$SRC/lib/claim.sh")"
  eval "$(sed -n '/^stdb() {/,/^}/p' "$SRC/lib/records.sh")"
  # shellcheck disable=SC2034 # read by stdb(): its answers, and the folder state.py is in
  declare -gA ASKED_K=() ASKED_V=() && HERE=$SRC
  ctl() { cat "$ST/control.json"; }
  # Defined here, in the case's shell, not at the top of this file: the runner sources every case file into one shell,
  # and a top-level order() would replace deps.test.sh's.
  cl() { (cd "$R" && STATE=$ST/cards.jsonl BRANCH=main claim "c$1-$1" "$CARDS/c$1-$1" $$); } # <issue>
  order() { jq -c --argjson o "$1" '.order = $o' "$ST/control.json" > "$STUB/c" && mv "$STUB/c" "$ST/control.json"; } # <order json>
}
# gone <issue> [<change>]: card <issue> landed: its change (or <change>, made in main's checkout, as a session fitted
# it there) committed on main, its landed line written, its claim gone with it.
gone() {
  if [ -n "${2:-}" ]; then (cd "$R" && eval "$2") && git -C "$R" add -A; else git -C "$CARDS/c$1-$1" diff --cached --binary | git -C "$R" apply --index; fi \
    && git -C "$R" commit -qm "title $1 (#$1)" || fail "the change of card $1 could not land"
  landed "$1" | jq -c --arg c "c$1-$1" '.card = $c' >> "$ST/cards.jsonl"; rm -f "$CARDS/c$1-$1.claim" "$CARDS/c$1-$1.cpatch"
}
# sfsettle <issue>: settle() of card <issue> at its landing step, as card() calls it, in the engine shell (fx_in), with
# card()'s caught set to $SFCAUGHT; run.out ends with "settle: <its exit>". Each look of a wait sleeps the live
# record's seconds: here sleep() counts the looks (SLEPT) and calls atlook() at each instead, to do what the case needs
# done during the wait (the holder lands); a wait of over 10 looks ends the call (exit 8).
atlook() { :; }
# sfsleep: what sleep() does in sfsettle's engine shell (sleep() calls it, so its caller's caller is settle()).
sfsleep() {
  [ "${FUNCNAME[2]}" = settle ] || { command sleep "$@"; return; } # sleep: a sleep outside settle() is the real one
  SLEPT=$((SLEPT + 1)); [ "$SLEPT" -le 10 ] || exit 8; atlook
}
sfsettle() {
  # shellcheck disable=SC2034 # read by the commands fx_in runs
  SFN=$1
  fx_in 'cd "$R" || exit 9; caught=${SFCAUGHT:-} waitsec=0 behind="[]" parsecheck="" SLEPT=0
    sleep() { sfsleep "$@"; }
    settle "c$SFN-$SFN" "$SFN" "$CARDS/c$SFN-$SFN" "Build the issue." land "$(issue "$SFN" 2026-01-01)"; echo "settle: $?"'
}
sfout() { tail -n 1 "$T/$CASE/run.out"; }

# Bug: two cards in flight that change the same file both went on to land, and the second met "rebase onto main
# conflicts". The second, #8, waits at its landing claim while #7 holds a.txt, its live record naming #7 and the file,
# and says it waits once however many looks the wait takes. Once #7 has landed (during the second look) #8's patch no
# longer applies (both changed the same lines): one session, told main moved and given the card's patch, brings it
# onto main, and settle() returns 2, so it is reviewed again there.
t_samefile() {
  setup '[]'; sfclaim; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight >> a.txt'
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"
  echo 'if grep -q "^# Main moved: apply the same change" "$STUB/brief"; then cp "$STUB/brief" "$STUB/caught"; printf "one\nseven\neight\n" > a.txt; fi' > "$STUB/build"
  atlook() { [ "$SLEPT" != 1 ] || cp "$CARDS/c8-8.live" "$STUB/waitlive"; [ "$SLEPT" != 2 ] || gone 7; }
  sfsettle 8
  [ "$(sfout)" = "settle: 2" ] || fail "#8 was not to be reviewed again after its wait: $(cat "$T/$CASE/run.out")"
  [ "$(jq -r .step "$STUB/waitlive" 2>/dev/null)" = land ] && [ "$(jq -r .action "$STUB/waitlive")" = "waiting on card c7-7, which changes the same files: a.txt" ] \
    && [ "$(jq -c .waits "$STUB/waitlive")" = '{"on":"c7-7","paths":["a.txt"]}' ] || fail "#8 was not shown waiting on #7 to land, with the file: $(cat "$STUB/waitlive" 2>/dev/null)"
  [ "$(grep -c 'waits on card' "$T/$CASE/run.out")" = 1 ] && grep -qx 'conveyor: card c8-8 waits on card c7-7, which changes the same files: a.txt' "$T/$CASE/run.out" \
    || fail "settle() did not say #8 waits, once: $(cat "$T/$CASE/run.out")"
  grep -q '^The file .*\.patch, made against commit [0-9a-f]*\.$' "$STUB/caught" 2>/dev/null || fail "the session after the wait was not told main moved, with the card's patch"
  [ "$(st 'select(.issue == 8) | [.step, .of // empty] | join(" ")' | tr '\n' ,)" = "picked,start land,start fix,fix," ] \
    && st 'select(.issue == 8 and .step == "fix") | .reason' | grep -q '^main moved since the card' || fail "steps of #8: $(st 'select(.issue == 8) | "\(.step) \(.of // "") \(.reason)"' | tr '\n' ,)"
  [ "$(tr '\n' ' ' < "$CARDS/c8-8/a.txt")" = "one seven eight " ] && [ "$(git -C "$CARDS/c8-8" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] \
    || fail "#8's change was not brought onto main with #7's"
}

# Bug: among cards waiting on a file with no holder, the older pick always went first, so an ordered card waited
# behind any older one. #6 holds a.txt and is ordered, so no card goes past it; once it lands, the ordered #9 and #8
# go before the older #7 that is not ordered, and #9, earlier in the order list, before #8.
t_samequeue() {
  setup '[]'; sfclaim; for n in 6 7 8 9; do sfcard $n "echo $n >> a.txt"; done
  [ -z "$(cl 6)" ] || fail "#6 waited with no other claim"; order '[6, 9, 8]'
  for n in 7 8 9; do w=$(cl $n) && [ "$(jq -r .on <<<"$w")" = c6-6 ] || fail "#$n went past the ordered holder #6: $w"; done
  gone 6
  w=$(cl 7) && [ "$(jq -r .on <<<"$w")" = c9-9 ] || fail "the older #7, not ordered, did not wait on the ordered #9 first: $w"
  w=$(cl 8) && [ "$(jq -r .on <<<"$w")" = c9-9 ] || fail "the ordered #8 did not wait on #9, earlier in the order list: $w"
  w=$(cl 9) && [ -z "$w" ] && [ "$(jq .held "$CARDS/c9-9.claim")" = true ] || fail "#9, first in the order list, did not claim a.txt: $w"
  gone 9 'echo 9 >> a.txt'
  w=$(cl 7) && [ "$(jq -r .on <<<"$w")" = c8-8 ] || fail "the older #7 did not wait on the ordered #8: $w"
  w=$(cl 8) && [ -z "$w" ] && [ "$(jq .held "$CARDS/c8-8.claim")" = true ] || fail "the ordered #8 did not claim a.txt before the older #7: $w"
}

# Bug: once the ordered #9 went past #7 on a.txt, both held it, and the Board told #8 it was waiting on #7 (the
# earlier claim) though the ordered #9 goes first. #8's wait must name #9.
t_sameboard() {
  setup '[]'; sfclaim; for n in 7 8 9; do sfcard $n "echo $n >> a.txt"; done
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"; order '[9]'
  w=$(cl 9) && [ -z "$w" ] && [ "$(jq -c '[.held, .passed]' "$CARDS/c7-7.claim")" = '[true,true]' ] || fail "the ordered #9 did not go past #7: $w $(cat "$CARDS/c7-7.claim")"
  w=$(cl 8) && [ "$(jq -r .on <<<"$w")" = c9-9 ] || fail "#8 was not shown waiting on the ordered #9: $w"
}

# Bug: a card the owner ordered first sat built behind an older card that was not ordered and held the same file.
# The ordered #8 claims a.txt while #7 holds it and goes on; #7, marked passed, waits on #8 at its next claim.
t_samepast() {
  setup '[]'; sfclaim; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight >> a.txt'
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"; order '[8]'
  w=$(cl 8) && [ -z "$w" ] && [ "$(jq .held "$CARDS/c8-8.claim")" = true ] || fail "the ordered #8 waited on #7: $w"
  w=$(cl 7) && [ "$(jq -c . <<<"$w")" = '{"on":"c8-8","paths":["a.txt"]}' ] && [ "$(jq -c '[.held, .passed]' "$CARDS/c7-7.claim")" = '[false,true]' ] \
    || fail "#7 did not wait on the ordered #8 at its next claim, marked passed: $w $(cat "$CARDS/c7-7.claim")"
}

# Bug: a card the ordered #8 went past landed without another review when its patch still applied to main after #8
# landed, so nobody reviewed it against #8's change. #7, passed (as claim() marks it: t_samepast), changes a.txt's
# first line and main's #8 its last: settle() fits its patch as it is and returns 2, so it is reviewed again.
t_samepastclean() {
  setup '[]'; seq 20 | sed 1s/1/one/ > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  sfcard 7 'sed -i 1s/one/seven/ a.txt'; sfcard 8 'echo eight >> a.txt'
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true,\"passed\":true}" > "$CARDS/c7-7.claim"; gone 8
  sfsettle 7
  [ "$(sfout)" = "settle: 2" ] || fail "#7, passed by the ordered #8, was not to be reviewed again though its patch applied: $(cat "$T/$CASE/run.out")"
  [ "$(sed -n '1p;$p' "$CARDS/c7-7/a.txt" | tr '\n' ' ')" = "seven eight " ] && [ ! -e "$STUB/sessions" ] && [ "$(jq .was "$CARDS/c7-7.claim")" = true ] \
    || fail "#7's patch was not applied on main as it is, with no session: $(cat "$CARDS/c7-7.claim")"
}

# Bug: a card the ordered #8 went past landed without another review when #8 had landed and let go of a.txt before
# #7's next claim, so #7 found nobody to wait on. Its claim says it was passed (was), for settle() to review it again.
t_samepastgone() {
  setup '[]'; sfclaim; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight >> a.txt'
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"; order '[8]'
  [ -z "$(cl 8)" ] || fail "the ordered #8 waited on #7"
  gone 8
  w=$(cl 7) && [ -z "$w" ] && [ "$(jq -c '[.held, .was]' "$CARDS/c7-7.claim")" = '[true,true]' ] \
    || fail "#7, passed by #8 that has landed since, is not to be reviewed again: $w $(cat "$CARDS/c7-7.claim")"
}

# Bug: a card read that no ordered card had gone past it, then, before its locked landing, the ordered #8 went past it
# and landed a change on other lines of the same file; #7's patch still applied, so it landed without another review.
# land() reads the mark again under the lock: #7, passed while at its landing step, lands nothing.
t_samepastland() {
  setup '[]'; sfcard 7 'echo seven >> a.txt'
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true,\"was\":false,\"passed\":true}" > "$CARDS/c7-7.claim"
  m=$(git -C "$R" rev-parse main)
  fx_in 'cd "$R" && land c7-7 7 "$CARDS/c7-7" "title 7 (#7)"; echo "land: $?"'
  [ "$(cat "$T/$CASE/run.out")" = "an ordered or ready card went past it since its claim; nothing was landed"$'\n'"land: 1" ] \
    && [ "$(git -C "$R" rev-parse main)" = "$m" ] || fail "#7 landed though an ordered card went past it: $(cat "$T/$CASE/run.out")"
}

# The owner (2026-11-12): "how do we avoid having so many cards waiting". Cards that share a file and changed
# different functions of it do not overlap: their changes apply together, so #8 claims a.txt while #7 holds it,
# neither waiting nor going past the other.
t_sameapply() {
  setup '[]'; { printf '%s\n' 'first() {' '  echo one' '}'; seq 10; printf '%s\n' 'last() {' '  echo two' '}'; } > "$R/a.txt"; git -C "$R" commit -qam "a.txt of two functions"
  sfclaim; sfcard 7 'sed -i "s/echo one/echo seven/" a.txt'; sfcard 8 'sed -i "s/echo two/echo eight/" a.txt'
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"
  w=$(cl 8) && [ -z "$w" ] && [ "$(jq -sc 'map([.held, .paths, .passed])' "$CARDS/c7-7.claim" "$CARDS/c8-8.claim")" = '[[true,["a.txt"],null],[true,["a.txt"],null]]' ] \
    || fail "#8 waited on #7, or went past it, though their changes apply together: $w $(cat "$CARDS"/*.claim)"
}

# Bug: cards with no file in common are held to one at a time. #8 on b.txt claims while #7 holds a.txt.
t_apart() {
  setup '[]'; sfclaim; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight > b.txt'
  [ -z "$(cl 7)" ] || fail "#7 waited with no other claim"
  w=$(cl 8) && [ -z "$w" ] && [ "$(jq -sc 'map(.held)' "$CARDS/c7-7.claim" "$CARDS/c8-8.claim")" = '[true,true]' ] || fail "#8 waited on #7, with no file in common: $w"
}

# Bug: an older card that claimed a file after a younger card had claimed it went past its claim too, both past
# their claim on the same file. The older #7 waits at its claim on the younger #8 that holds a.txt. #8 then lands while
# #7 waits, and #7's tests had run on its change before (card()'s caught): settle() puts that change back as it was, on
# its own commit, for the landing's rebuild session to bring onto main, and returns 0.
t_sameorder() {
  setup '[]'; sfclaim; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight >> a.txt'
  [ -z "$(cl 8)" ] || fail "#8 waited with no other claim"
  w=$(cl 7) && [ "$(jq -c . <<<"$w")" = '{"on":"c8-8","paths":["a.txt"]}' ] || fail "the older #7 went past the younger #8's claim: $w"
  old=$(git -C "$CARDS/c7-7" rev-parse HEAD)
  atlook() { [ "$SLEPT" != 1 ] || gone 8; }
  SFCAUGHT=1 sfsettle 7
  [ "$(sfout)" = "settle: 0" ] && grep -qx 'conveyor: card c7-7 waits on card c8-8, which changes the same files: a.txt' "$T/$CASE/run.out" \
    || fail "#7 did not wait on #8, or did not go on to land: $(cat "$T/$CASE/run.out")"
  [ "$(git -C "$CARDS/c7-7" rev-parse HEAD)" = "$old" ] && [ "$(git -C "$CARDS/c7-7" diff --cached HEAD | grep -c '^+seven')" = 1 ] \
    && [ ! -e "$STUB/sessions" ] || fail "#7's change, its tests run on it, was not put back as it was for the landing's rebuild"
  # Its landing then meets the conflict with #8's change and lands nothing: that message is what starts card()'s one
  # rebuild, which brings #7 onto main and reviews it again there (port.test.sh t_rebase).
  m=$(git -C "$R" rev-parse main)
  fx_in 'cd "$R" && land c7-7 7 "$CARDS/c7-7" "title 7 (#7)"; echo "land: $?"'
  grep -q '^rebase onto main conflicts: ' "$T/$CASE/run.out" && [ "$(sfout)" = "land: 1" ] && [ "$(git -C "$R" rev-parse main)" = "$m" ] \
    || fail "#7, put back as it was, did not meet the conflict at landing for its rebuild: $(cat "$T/$CASE/run.out")"
}

# Bug: an older card holding x.txt whose fix added a.txt, while a younger card held a.txt, ignored the younger holder:
# both were past their claim on a.txt. #7 claimed x.txt alone, then #8 a.txt; #7's fix adds a.txt, and at its next
# claim #7 waits on #8 for a.txt, and once #8 lands it is brought onto main and reviewed again.
t_samelast() {
  setup '[]'; sfclaim; sfcard 7 'echo seven > x.txt'; sfcard 8 'echo eight >> a.txt'
  [ -z "$(cl 7)" ] && [ -z "$(cl 8)" ] || fail "#7 on x.txt and #8 on a.txt did not both claim"
  echo seven >> "$CARDS/c7-7/a.txt"; git -C "$CARDS/c7-7" add -A
  w=$(cl 7) && [ "$(jq -c . <<<"$w")" = '{"on":"c8-8","paths":["a.txt"]}' ] && [ "$(jq .held "$CARDS/c7-7.claim")" = false ] \
    || fail "#7, its fix adding a.txt, did not wait on #8 holding it: $w $(cat "$CARDS/c7-7.claim")"
  # #8 lands during the wait: #7's patch no longer applies, one session told main moved brings it onto main, and
  # settle() returns 2, so it is reviewed again there.
  echo 'if grep -q "^# Main moved: apply the same change" "$STUB/brief"; then printf "one\neight\nseven\n" > a.txt; echo seven > x.txt; fi' > "$STUB/build"
  atlook() { [ "$SLEPT" != 1 ] || gone 8; }
  sfsettle 7
  [ "$(sfout)" = "settle: 2" ] || fail "#7 was not to be reviewed again after #8 landed: $(cat "$T/$CASE/run.out")"
  st 'select(.issue == 7 and .step == "fix") | .reason' | grep -q '^main moved since the card' && [ "$(tr '\n' ' ' < "$CARDS/c7-7/a.txt")" = "one eight seven " ] \
    && [ "$(cat "$CARDS/c7-7/x.txt")" = seven ] && [ "$(git -C "$CARDS/c7-7" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] \
    || fail "no session brought #7 onto main with #8's change: $(st 'select(.issue == 7)' | tr '\n' ' ')"
}

# Bug: a card whose overlapping card landed before it claimed anything saw no claim, skipped the move onto main, and
# met "rebase onto main conflicts" at landing. At its landing claim #8 waits on nobody, its patch no longer applies to
# main, and one session brings it there; settle() returns 2, so it is reviewed again.
t_samelate() {
  setup '[]'; sfcard 7 'echo seven >> a.txt'; sfcard 8 'echo eight >> a.txt'; gone 7
  echo 'if grep -q "^# Main moved: apply the same change" "$STUB/brief"; then printf "one\nseven\neight\n" > a.txt; fi' > "$STUB/build"
  sfsettle 8
  [ "$(sfout)" = "settle: 2" ] && ! grep -q 'waits on card' "$T/$CASE/run.out" || fail "#8 was not brought onto main to be reviewed again: $(cat "$T/$CASE/run.out")"
  st 'select(.issue == 8 and .step == "fix") | .reason' | grep -q '^main moved since the card' && [ "$(tr '\n' ' ' < "$CARDS/c8-8/a.txt")" = "one seven eight " ] \
    || fail "no session brought #8 onto main: $(st 'select(.issue == 8)' | tr '\n' ' ')"
}

# Bug: a card that blocked while it held a file, and was given back by `retry`, kept every card that shares the file
# waiting on it, each holding a builder slot (8 of 10 slots for 70 minutes). A card that is not on the belt holds no
# file: card c1-7, its claim on a.txt standing and its process alive, makes #8 wait only while it is on the belt.
t_sameoff() {
  setup '[]'; sfclaim; sfcard 8 'echo two >> a.txt'
  landed 7 | jq -c '.card = "c1-7" | .step = "picked"' >> "$ST/cards.jsonl"
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true}" > "$CARDS/c1-7.claim"
  w=$(cl 8) && [ "$(jq -r .on <<<"$w")" = c1-7 ] || fail "#8 did not wait on c1-7 while it was on the belt: $w"
  landed 7 | jq -c '.card = "c1-7" | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"' >> "$ST/cards.jsonl"
  w=$(cl 8) && [ -z "$w" ] || fail "#8 waited on the blocked c1-7: $w"
  loop retry 7 >/dev/null || fail "retry of #7 exited non-zero"
  [ -e "$CARDS/c1-7.claim" ] && w=$(cl 8) && [ -z "$w" ] && [ "$(jq .held "$CARDS/c8-8.claim")" = true ] || fail "#8 waited on c1-7, given back by retry: $w"
}
# sameoffsetup <waiter> <holder>: those two issues and the belt's cap 1; card c3-<waiter> on the belt waits at its
# landing claim on card c4-<holder> (its live record names it), which blocked and `retry` gave back.
sameoffsetup() {
  setup "[$(issue "$1" 2026-01-03),$(issue "$2" 2026-01-04)]"; CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  loop control cap 1 >/dev/null || fail "cap 1 was refused"
  { landed "$1" | jq -c --arg c "c3-$1" '.card = $c | .step = "picked"'
    landed "$2" | jq -c --arg c "c4-$2" '.card = $c | .step = "picked"'
    landed "$2" | jq -c --arg c "c4-$2" '.card = $c | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"'; } >> "$ST/cards.jsonl"
  loop retry "$2" >/dev/null || fail "retry of #$2 exited non-zero"
  jq -cn --arg on "c4-$2" '{step: "land", waits: {on: $on, paths: ["a.txt"]}}' > "$CARDS/c3-$1.live"
}

# The belt full (cap 1) with #11, which waits at its landing claim on card c4-12; c4-12 blocked and `retry` gave #12
# back. Bug: #11 held the only slot, waiting on a card that was never picked. The loop's next turn picks #12 past the
# cap: urgent() names it, and the pick run() makes for it (ONLY=<urgent> pick retried) takes it.
t_sameoffretry() {
  sameoffsetup 11 12
  fx_in 'u=$(urgent); echo "urgent: $u"; ONLY=$u locked fresh pick retried "" "$(asked)"'
  [ "$RC" = 0 ] && [ "$(head -n 1 "$T/$CASE/run.out")" = "urgent: [12]" ] && [ "$(sed -n 2p "$T/$CASE/run.out" | cut -d' ' -f2)" = 12 ] \
    && [ -n "$(st 'select(.issue == 12 and .step == "picked" and .card != "c4-12")')" ] || fail "the retried holder #12 was not picked past the cap: $(cat "$T/$CASE/run.out")"
}

# The belt full (cap 1) with #15, which waited on card c4-16 once and went on to its tests when its claim went: its
# live record names no card now. `retry` gives #16 back. Bug: #16 was picked past the cap, a builder for nobody.
# urgent() names no card, so run() picks nothing beyond the cap.
t_sameoffcap() {
  sameoffsetup 15 16
  echo '{"step": "test"}' > "$CARDS/c3-15.live"
  fx_in 'echo "urgent: $(urgent)"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "urgent: " ] || fail "the retried #16 is to be picked past the cap while nobody waits on it: $(cat "$T/$CASE/run.out")"
}

# As t_sameoffretry, in a run with --only 13: the run builds only what it lists, so the retried #14 #13 waits on is
# not picked past the cap (urgent() names it only when the --only list, if any, has its issue).
t_sameoffonly() {
  sameoffsetup 13 14
  fx_in 'echo "all: $(urgent)"; ONLY="[13]"; echo "only: $(urgent)"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = $'all: [14]\nonly: ' ] || fail "run --only 13 is to pick the retried #14: $(cat "$T/$CASE/run.out")"
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
  s=$(loop snapshot --fresh) || fail "snapshot failed"
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
  s=$(loop snapshot --fresh) || fail "snapshot failed"
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

# The three cases below run cards through the real loop (loop run): the direct checks above show claim(), settle(),
# land() and urgent() each on its own, but only card() and run() join them (a fix round to the next claim, a pass at
# the landing step to another review, a wait on the belt to the pick past the cap), and only a run shows that join.
# Each acts at a hook in the step it waits for (settle()'s sleep, the reading before land(), a session), never polls.

# Bug it catches: the fix round's change was not what the card claimed next (card(): the fix, then settle() at its
# landing step), so a card whose fix added a file another card holds went on past that holder. #7 builds x.txt; its
# first review is a NO-GO and its fix adds a.txt, which card c1-8 holds (a stand-in: its claim under this shell's pid,
# alive). At its landing claim #7 waits on c1-8, naming it. At the first look of that wait (settle()'s sleep, the
# hook) c1-8 lands a change to b.txt and lets go of a.txt, and #7 goes on and lands.
t_samefixclaim() {
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$T/$CASE/cards"
  printf '%s\n' '[P1] x.txt:1 a.txt needs the line too' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  echo 'if [ -e x.txt ]; then echo seven >> a.txt; else echo seven > x.txt; fi' > "$STUB/build"
  landed 8 | jq -c '.card = "c1-8" | .step = "picked"' >> "$ST/cards.jsonl"; landed 8 | jq -c '.card = "c1-8"' > "$STUB/landed8"
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true}" > "$T/$CASE/cards/c1-8.claim"
  out=$(sleep() {
      if [ "${FUNCNAME[1]:-}" = settle ] && [ ! -e "$STUB/released" ]; then
        : > "$STUB/released"; local w; w=$(echo "$CONVEYOR_CARDS"/*-7)
        cp "$w.live" "$STUB/waitlive"; jq -c . "$w.claim" > "$STUB/waitclaim"; git -C "$w" diff --cached --name-only | tr '\n' ' ' > "$STUB/waitpaths"
        echo eight > "$R/b.txt" && git -C "$R" add b.txt && git -C "$R" commit -qm "title 8 (#8)" && cat "$STUB/landed8" >> "$ST/cards.jsonl" && rm -f "$CONVEYOR_CARDS/c1-8.claim"
      fi
      command sleep "$@"; } # sleep: the engine's own sleep, passed on as it was called
    export -f sleep; loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(st 'select(.issue == 7 and .step == "picked") | .card')
  [ "$(st 'select(.issue == 7 and (.step | IN("review", "fix"))) | "\(.step) \(.result)"' | tr '\n' ,)" = "review NO-GO,fix ok,review GO," ] \
    || fail "#7 was not reviewed, fixed and reviewed again: $(st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(cat "$STUB/waitpaths" 2>/dev/null)" = "a.txt x.txt " ] && [ "$(jq -c .held "$STUB/waitclaim")" = false ] \
    || fail "#7 did not claim the file its fix added, or held it while c1-8 did: $(cat "$STUB/waitpaths" "$STUB/waitclaim" 2>/dev/null)"
  [ "$(jq -c '[.step, .waits, .action]' "$STUB/waitlive")" = '["land",{"on":"c1-8","paths":["a.txt"]},"waiting on card c1-8, which changes the same files: a.txt"]' ] \
    && grep -qxF "conveyor: card $c7 waits on card c1-8, which changes the same files: a.txt" <<<"$out" \
    || fail "#7 was not shown waiting on c1-8 for a.txt: $(cat "$STUB/waitlive") $out"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] && [ "$(tail -n 1 "$R/a.txt")" = seven ] && [ "$(cat "$R/x.txt" "$R/b.txt" | tr '\n' ' ')" = "seven eight " ] \
    || fail "#7 did not go on and land once c1-8 let go: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}

# Bug it catches: a card that read no pass before its locked landing (card(): the passed check, then land()) landed
# though the ordered #8 went past it and landed just before, so nobody reviewed it against #8's change. #7 adds a case
# at the end of the test file a.test.sh. The weekly limit reading #7 asks for at its landing step, outside the lock and
# before land(), is the hook: there #8, first in the order list, claims a.test.sh with the engine's claim() and lands
# its own case at the end. The two additions conflict in a three-way merge, so claim() finds that they do not apply
# together (together(), on #7's claimed change) and #8 goes past #7; yet they are compatible: the landing fit merges
# the test file keeping both sides (unionfit()). land() then lands nothing, and #7 is fitted onto #8's commit and
# reviewed again there before it lands.
t_samepastrun() {
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done
  echo case1 > "$R/a.test.sh"; git -C "$R" add a.test.sh; git -C "$R" commit -qm "a test file"; m0=$(git -C "$R" rev-parse main)
  echo 'echo case7 >> a.test.sh' > "$STUB/build"; echo 'git rev-parse HEAD >> "$STUB/reviewheads"' > "$STUB/review-cmd"
  w8=$T/$CASE/c8-8; git -C "$R" worktree add -q --detach "$w8" main && echo case8 >> "$w8/a.test.sh" && git -C "$w8" add -A || fail "#8's change could not be staged"
  landed 8 | jq -c '.card = "c8-8" | .step = "picked"' > "$STUB/picked8"; landed 8 | jq -c '.card = "c8-8"' > "$STUB/landed8"
  { printf 'W=%q SRC=%q\n' "$w8" "$SRC"; cat <<'EOF'; } > "$STUB/limit"
if [ ! -e "$STUB/past" ] && jq -se 'map(select(.issue == 7)) | last | .step == "start" and .of == "land"' "$ST/cards.jsonl" >/dev/null 2>&1; then
  : > "$STUB/past"; cat "$STUB/picked8" >> "$ST/cards.jsonl"; jq -c '.order = [8]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  ( . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && cd "$R" && locked claim c8-8 "$W" $$; echo "claim: $?" ) > "$STUB/claim8" 2>&1
  jq -c .passed "$CONVEYOR_CARDS"/*-7.claim > "$STUB/past7"
  git -C "$W" diff --cached --binary | git -C "$R" apply --index && git -C "$R" commit -qm "title 8 (#8)" && cat "$STUB/landed8" >> "$ST/cards.jsonl"
fi
false
EOF
  out=$(CONVEYOR_LIMIT_CMD=". \"$STUB/limit\"" loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(cat "$STUB/claim8" 2>/dev/null)" = "claim: 0" ] && [ "$(cat "$STUB/past7")" = true ] \
    || fail "the ordered #8 did not go past #7 at #7's landing step: $(cat "$STUB/claim8" "$STUB/past7" 2>/dev/null)"
  m8=$(git -C "$R" rev-parse main~1)
  [ "$(git -C "$R" log -1 --format=%s "$m8")" = "title 8 (#8)" ] && [ "$(git -C "$R" rev-parse main~2)" = "$m0" ] \
    && [ "$(tr '\n' ' ' < "$STUB/reviewheads")" = "$m0 $m8 " ] && [ "$(st 'select(.step == "review") | "\(.issue) \(.result)"' | tr '\n' ,)" = "7 GO,7 GO," ] \
    || fail "#7 was not reviewed again on #8's commit before it landed: $(cat "$STUB/reviewheads") $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "8 7 " ] && [ "$(tr '\n' ' ' < "$R/a.test.sh")" = "case1 case8 case7 " ] \
    || fail "#7 did not land on #8's change: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  # The pass path, not the rebuild: a land() that tried the fit before reading the pass would meet the conflict and
  # rebuild #7 on #8's tip, a second session that appends case7 again and ends the same way as the lines above.
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ -z "$(st 'select(.issue == 7 and (.step == "rebase" or .of == "rebase")) | .step')" ] \
    || fail "#7 was rebuilt in place of being fitted onto #8's commit as passed: $(cat "$STUB/sessions") $(st '"\(.issue) \(.step) \(.of // "")"' | tr '\n' ,)"
}

# Bug it catches: the turn's pick past the cap (run(): urgent(), then `pick retried` with ONLY) did not take a card
# that `retry` gave back while a card on the belt waited on it, or took one --only leaves out, or one nobody waits on
# now. The cap is 1, the run is `run --only 11,12,16`, and three cards of another loop are on the belt (stand-ins:
# their picked line and live record): c3-13 comes to wait on card c4-12, c3-15 waits on c4-14, and c3-17 once waited
# on c4-16 and went on (its live record names no card). `retry` gave back #12, #14 and #16 before the run. The run
# picks #11, the oldest; its build session makes c3-13 wait on c4-12, then waits for #12's build (a pipe, 100 s at
# most): #12 is picked past the cap while #11 holds the only slot. #14 (not in --only) is never picked; #16 only once
# #11 and #12 have landed.
t_sameoffrun() {
  setup "[$(issue 11 2026-01-01),$(issue 12 2026-01-02),$(issue 14 2026-01-03),$(issue 16 2026-01-04)]"; mkdir -p "$T/$CASE/cards"
  for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done; tune '.tunables.poll = 1'; loop control cap 1 >/dev/null || fail "cap 1 was refused"
  for n in 12 14 16; do
    { landed $n | jq -c --arg c "c4-$n" '.card = $c | .step = "picked"'
      landed $n | jq -c --arg c "c4-$n" '.card = $c | .step = "blocked" | .result = "blocked" | .reason = "review 1: review failed (exit 124)"'
      landed $((n + 1)) | jq -c --arg c "c3-$((n + 1))" '.card = $c | .step = "picked"'; } >> "$ST/cards.jsonl"
    loop retry $n >/dev/null || fail "retry of #$n exited non-zero"
  done
  jq -cn '{step: "land", waits: {on: "c4-14", paths: ["a.txt"]}}' > "$T/$CASE/cards/c3-15.live"; echo '{"step": "test"}' > "$T/$CASE/cards/c3-17.live"
  mkfifo "$STUB/built12" || fail "the pipe could not be made"
  { printf 'C=%q\n' "$T/$CASE/cards"; cat <<'EOF'; } > "$STUB/build"
case $PWD in
  *-11) exec {L}<> "$STUB/built12"; jq -cn '{step: "land", waits: {on: "c4-12", paths: ["a.txt"]}}' > "$C/c3-13.live"
    read -r -t 100 l <&"$L" && : > "$STUB/heard12"; exec {L}<&-; echo eleven > b.txt ;;
  *-12) echo go 1<> "$STUB/built12"; echo twelve > c.txt ;;
  *) echo sixteen > e.txt ;;
esac
EOF
  out=$(loop run --only 11,12,16 2>&1) || fail "run exited non-zero: $out"
  [ -e "$STUB/heard12" ] || fail "the retried #12 was not picked while #11 held the only slot: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  [ -z "$(st 'select(.issue == 14 and .step == "picked")')" ] || fail "run --only 11,12,16 picked the retried #14: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  # The picked and landed lines in their order, #11's and #12's landings in either order.
  [ "$(jq -rs '[.[] | select((.issue | IN(11, 12, 16)) and (.step | IN("picked", "landed"))) | "\(.issue) \(.step)"] | [.[:2], (.[2:4] | sort), .[4:]] | map(join(",")) | join(" ")' "$ST/cards.jsonl")" \
    = "11 picked,12 picked 11 landed,12 landed 16 picked,16 landed" ] \
    || fail "#16, waited on by nobody now, was picked past the cap, or a card did not land: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
}
